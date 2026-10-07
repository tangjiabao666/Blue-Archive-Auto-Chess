"""Read-only APK content and Android manifest gates; no device or account access."""
import hashlib
from pathlib import Path, PurePosixPath
import re
import zipfile

RAW_CATEGORIES = {'runtime_json', 'vfx_texture_json', 'vfx_texture_png', 'mesh_raw',
                  'animation_libraries', 'animation_library_manifests'}
PACKAGE = 'com.bluea.prototype'

def safe_member(name):
    if not name or name.startswith('/') or '\\' in name or ':' in name or any(p in ('', '.', '..') for p in name.rstrip('/').split('/')):
        raise ValueError('Unsafe APK member: ' + name)
    return name

def forbidden(name):
    path = name.removeprefix('assets/') if name.startswith('assets/') else name
    return (path.startswith(('tests/', 'evidence/', 'docs/', 'tools/', '.git/')) or
            '/source_objects/' in path or '/source_materials/' in path or
            path.endswith(('.s3tc.ctex', '.bptc.ctex', '.py', '.pyc', '.md', '.log', '.bundle', '.unity3d', '.keystore', '.jks')) or
            'session-save' in path or path.endswith('settings.cfg'))

def resource_targets(data):
    return re.findall(r'^path(?:\.[A-Za-z0-9_]+)?="res://([^"\n]+)"\s*$', data.decode('utf-8'), re.M)

def make_audio_verification_pack(apk, manifest, output):
    """Mount only APK audio bytes, never a staging or desktop resource fallback."""
    with zipfile.ZipFile(apk) as source:
        paths=set()
        for row in manifest['files']:
            if row['category'] not in ('audio_streams','ordinary_audio_streams'): continue
            path=safe_member(row['path'])
            if 'assets/'+path in source.namelist(): paths.add(path); continue
            remap=next((path+suffix for suffix in ('.import','.remap') if 'assets/'+path+suffix in source.namelist()),None)
            if remap is None: raise ValueError('Missing packaged audio remap: '+path)
            paths.add(remap)
            paths.update(safe_member(p) for p in resource_targets(source.read('assets/'+remap)))
        with Path(output).open('xb') as file, zipfile.ZipFile(file,'w',zipfile.ZIP_STORED) as target:
            for path in sorted(paths): target.writestr(path,source.read('assets/'+path))
    return len(paths)

def verify_resources(apk, manifest, stage=None):
    entries = {}; remaps = {}; problems = []
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate APK member names')
        for item in archive.infolist():
            safe_member(item.filename)
            if item.is_dir():
                continue
            if (item.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Symlink in APK: ' + item.filename)
            with archive.open(item) as stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()  # Also verifies ZIP CRC.
            entries[item.filename] = {'bytes': item.file_size, 'sha256': digest, 'compression': item.compress_type}
            if item.filename.startswith('assets/') and item.filename.endswith(('.import', '.remap')):
                remaps[item.filename.removeprefix('assets/')] = resource_targets(archive.read(item))
        files = {p.removeprefix('assets/'): row for p,row in entries.items() if p.startswith('assets/')}
        required = {row['path']: row for row in manifest['files'] if row['category'] in RAW_CATEGORIES}
        raw_missing = sorted(p for p in required if p not in files)
        raw_mismatched = sorted(p for p,row in required.items() if p in files and files[p]['sha256'] != row['sha256'])
        resource_missing = []; missing_targets = []; imported_mismatched = []; source_remap_mismatched = []; source_remaps_checked = 0
        for row in manifest['files'] + [{'path': 'project.binary'}, {'path': 'game.tscn'}]:
            path = row['path']
            if path in files:
                continue
            mapping = next((p for p in (path + '.import', path + '.remap') if p in remaps), None)
            if mapping is None or not remaps[mapping]:
                resource_missing.append(path)
        for mapping, targets in remaps.items():
            if stage is not None and mapping.endswith('.import'):
                sidecar=Path(stage)/mapping
                source_remaps_checked+=1
                # Platform export may drop desktop variants, but may never point
                # a source resource at another resource's otherwise valid bytes.
                if (not sidecar.is_file() or sidecar.is_symlink() or not targets or
                    not set(targets).issubset(resource_targets(sidecar.read_bytes()))):
                    source_remap_mismatched.append(mapping)
            for path in targets:
                safe_member(path)
                if path not in files:
                    missing_targets.append({'remap': mapping, 'target': path})
                elif stage is not None and path.startswith('.godot/imported/'):
                    target = Path(stage) / path
                    if not target.is_file() or target.is_symlink() or hashlib.sha256(target.read_bytes()).hexdigest() != files[path]['sha256']:
                        imported_mismatched.append(path)
        blocked = sorted(p for p in entries if forbidden(p))
        leaked = sorted(p for p in manifest.get('excluded_effect_source_json', []) if p in files)
        abis = sorted({p.split('/')[1] for p in entries if p.startswith('lib/')})
        if abis != ['arm64-v8a']:
            problems.append('Only arm64-v8a native libraries are allowed')
        if 'lib/arm64-v8a/libgodot_android.so' not in entries:
            problems.append('Missing ARM64 Godot native library')
        for name in ('AndroidManifest.xml', 'classes.dex'):
            if name not in entries:
                problems.append('Missing ' + name)
    return {'passed': not any((problems, raw_missing, raw_mismatched, resource_missing, missing_targets, imported_mismatched, source_remap_mismatched, blocked, leaked)),
            'failures': problems, 'abi': abis, 'member_count': len(entries), 'zip_crc_verified': True,
            'required_raw_count': len(required), 'raw_missing': raw_missing, 'raw_mismatched': raw_mismatched,
            'required_resource_count': len({r['path'] for r in manifest['files']}), 'resource_missing': sorted(set(resource_missing)),
            'missing_import_targets': missing_targets, 'imported_payload_mismatched': sorted(set(imported_mismatched)),
            'source_import_remaps_checked': source_remaps_checked, 'source_import_remap_mismatched': sorted(source_remap_mismatched),
            'forbidden_members': blocked, 'leaked_extraction_json': leaked, 'entries': entries}

def launcher_alias_present(xmltree):
    lines=xmltree.splitlines()
    for index,line in enumerate(lines):
        if 'E: activity-alias ' not in line: continue
        indent=len(line)-len(line.lstrip())
        block=[]
        for child in lines[index+1:]:
            if child.strip() and len(child)-len(child.lstrip())<=indent: break
            block.append(child)
        text='\n'.join(block)
        if (re.search(r'android:exported\([^)]*\)=\(type 0x12\)0xffffffff',text) and
            re.search(r'android:targetActivity\([^)]*\)="com.godot.game.GodotApp"',text) and
            '"android.intent.action.MAIN"' in text and '"android.intent.category.LAUNCHER"' in text):
            return True
    return False

def verify_metadata(badging, permissions, xmltree):
    def match(pattern):
        found = re.search(pattern, badging, re.M)
        return found.group(1) if found else None
    package = match(r"^package: name='([^']+)'")
    minimum = match(r"^sdkVersion:'([^']+)'")
    target = match(r"^targetSdkVersion:'([^']+)'")
    abi_line = match(r'^native-code: (.+)$') or ''
    abis = re.findall(r"'([^']+)'", abi_line)
    requested = sorted(set(re.findall(r"uses-permission(?:-sdk-\d+)?: name='([^']+)'", badging + '\n' + permissions)))
    orientation = re.search(r'android:screenOrientation\([^)]*\)=\(type 0x10\)0x0\b', xmltree) is not None
    backup_disabled = re.search(r'android:allowBackup\([^)]*\)=\(type 0x12\)0x0\b', xmltree) is not None
    failures = []
    if package != PACKAGE: failures.append('Unexpected package ID')
    if minimum != '24' or target != '36': failures.append('Unexpected SDK levels (expected min 24 / target 36)')
    if abis != ['arm64-v8a']: failures.append('Unexpected native ABI')
    if requested: failures.append('Private offline APK must not request Android permissions')
    if not orientation: failures.append('Landscape orientation is missing')
    if not backup_disabled: failures.append('Cloud backup must be disabled')
    if 'application-debuggable' in badging: failures.append('Expected release runtime, not debuggable application')
    if 'launchable-activity:' not in badging and not launcher_alias_present(xmltree): failures.append('Missing launcher activity')
    return {'passed': not failures, 'failures': failures, 'package': package, 'min_sdk': minimum,
            'target_sdk': target, 'abis': abis, 'permissions': requested, 'landscape': orientation,
            'backup_disabled': backup_disabled, 'debuggable': 'application-debuggable' in badging}
