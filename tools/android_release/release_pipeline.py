#!/usr/bin/env python3
"""Isolated pinned Android ARM64 private APK builder. Read-only dry run by default."""
import argparse
from datetime import datetime, timezone
import fnmatch
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import struct
import sys

HERE = Path(__file__).resolve().parent
WINDOWS = HERE.parent / 'windows_release'
sys.path.insert(0, str(WINDOWS))
sys.path.insert(0, str(HERE))
from dependency_manifest import build_manifest, sha256, safe_relative
from verify_apk import verify_resources, verify_metadata, make_audio_verification_pack
spec = importlib.util.spec_from_file_location('windows_pinned_pipeline', WINDOWS / 'release_pipeline.py')
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)

PRESET = 'Android ARM64 Private'
DRONE = 'assets/skill_props/shiroko_drone/shiroko_drone.glb'
DRONE_HASHES = {
    DRONE: 'ef286a557c29c712d596d80de72eb9eac653bc91c04be9bdbca248b57d67ed58',
    DRONE+'.import': '489f5e9754fafecfada0380dabe67b773cbd6c20c1d60b79efacc4573078b74b',
}
DRONE_DIAGNOSTIC = 'ERROR: Basis [X: (0.0, 0.0, 0.0), Y: (0.0, 0.0, 0.0), Z: (0.0, 0.0, 0.0)] must be normalized in order to be casted to a Quaternion. Use get_rotation_quaternion() or call orthonormalized() if the Basis contains linearly independent vectors.'
DEFAULT_TOOLCHAIN = Path(__file__).resolve().parents[2] / 'private-toolchains' / 'android'
TEMPLATES = {'android_debug.apk': (124546428, '5cd4cfc1a8fc23ed45be5f0a36a6cc279d15b50a40c6ef69c89276895441cd1d'),
             'android_release.apk': (102855501, 'e91ef7e517e73aec1ddcc4c455c5fd53de1837c240a7c520ac438b73874b54c1')}
PROJECT_OVERRIDES = {
    'application': {'config/icon': '"res://assets/ui/android_launcher.svg"'},
    'display': {'window/size/viewport_width': '1280', 'window/size/viewport_height': '900',
                'window/stretch/mode': '"canvas_items"', 'window/stretch/aspect': '"expand"',
                'window/handheld/orientation': '0'},
    'input_devices': {'pointing/emulate_mouse_from_touch': 'true'},
    'rendering': {'renderer/rendering_method': '"gl_compatibility"',
                  'renderer/rendering_method.mobile': '"gl_compatibility"',
                  'textures/vram_compression/import_etc2_astc': 'true',
                  'textures/vram_compression/import_s3tc_bptc': 'false'},
}

def sections(text):
    result = {}; current = ''; result[current] = []
    for line in text.splitlines():
        match = re.fullmatch(r'\[([^]]+)\]', line.strip())
        if match:
            current = match.group(1)
            if current in result: raise ValueError('Duplicate config section: ' + current)
            result[current] = []
        else: result[current].append(line)
    return result

def config_values(lines):
    result = {}
    for line in lines:
        if '=' in line and not line.lstrip().startswith(';'):
            key, value = line.split('=', 1)
            if key.strip() in result: raise ValueError('Duplicate config key: ' + key)
            result[key.strip()] = value.strip()
    return result

def config_value(text, section, key):
    return config_values(sections(text).get(section, []))[key]

def android_project(original):
    parts = sections(original)
    for section, overrides in PROJECT_OVERRIDES.items():
        lines = parts.setdefault(section, [])
        lines[:] = [line for line in lines if line.split('=',1)[0].strip() not in overrides]
        while lines and not lines[-1].strip(): lines.pop()
        lines.extend(key + '=' + value for key,value in overrides.items())
    return '\n\n'.join((('[' + name + ']\n') if name else '') + '\n'.join(lines).strip() for name,lines in parts.items()) + '\n'

def android_preset(templates):
    windows = (WINDOWS / 'export_presets.cfg.in').read_text()
    preset = (HERE / 'export_presets.cfg.in').read_text()
    for key in ('include_filter', 'exclude_filter'):
        preset = preset.replace('@' + key.upper() + '@', config_value(windows,'preset.0',key))
    for name in ('debug', 'release'):
        preset = preset.replace('@' + name.upper() + '_TEMPLATE@', json.dumps(str(Path(templates) / ('android_' + name + '.apk'))))
    return preset

def mobile_import_change_allowed(before, after):
    left, right = sections(before), sections(after)
    if set(left) != set(right): return False
    for section in left:
        if section not in ('remap', 'deps'):
            if '\n'.join(left[section]).strip() != '\n'.join(right[section]).strip(): return False
    lremap, rremap = config_values(left.get('remap', [])), config_values(right.get('remap', []))
    ldeps, rdeps = config_values(left.get('deps', [])), config_values(right.get('deps', []))
    # Only generated output metadata may change. Keep importer identity/source/params pinned.
    def stable_remap(values):
        return {k:v for k,v in values.items() if k != 'metadata' and k != 'path' and not k.startswith('path.')}
    return (stable_remap(lremap) == stable_remap(rremap) and
            {k:v for k,v in ldeps.items() if k != 'dest_files'} == {k:v for k,v in rdeps.items() if k != 'dest_files'})

def validate_output(path, inputs):
    base.require_fresh_output(path)
    path = Path(path).resolve()
    base.require_fresh_output(path)
    if any(path.is_relative_to(Path(source).resolve()) for source in inputs):
        raise ValueError('Output must be outside source and toolchain inputs')
    return path

def android_environment(root, sdk, java, keystore):
    env = base.environment(root)
    for key in list(env):
        if key.startswith('GODOT_ANDROID_KEYSTORE_'): del env[key]
    env.update(JAVA_HOME=str(java), ANDROID_HOME=str(sdk), ANDROID_SDK_ROOT=str(sdk),
               GODOT_ANDROID_KEYSTORE_RELEASE_PATH=str(keystore),
               GODOT_ANDROID_KEYSTORE_RELEASE_USER='androiddebugkey',
               GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD='android')
    env['PATH'] = str(Path(java)/'bin') + os.pathsep + str(Path(sdk)/'build-tools/35.0.1') + os.pathsep + env.get('PATH','')
    config = Path(env['XDG_CONFIG_HOME'])/'godot'; config.mkdir(exist_ok=True)
    (config/'editor_settings-4.6.tres').write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' +
        'export/android/android_sdk_path=' + json.dumps(str(sdk)) + '\n' +
        'export/android/java_sdk_path=' + json.dumps(str(java)) + '\n' +
        'export/android/debug_keystore=' + json.dumps(str(keystore)) + '\n' +
        'export/android/debug_keystore_user="androiddebugkey"\nexport/android/debug_keystore_pass="android"\n' +
        'export/android/shutdown_adb_on_exit=false\n')
    return env

def command(argv, env, log, cwd=None, timeout=1800, godot=False):
    with Path(log).open('xb') as stream:
        result = subprocess.run([str(a) for a in argv], cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout, umask=0o077)
    text = Path(log).read_text(errors='replace')
    if result.returncode: raise RuntimeError('Command failed (' + str(result.returncode) + '): ' + str(log))
    if godot and re.search(r'(?:ERROR:|SCRIPT ERROR:|WARNING:)', text):
        raise RuntimeError('Godot diagnostics require review: ' + str(log))
    return text

def classify_godot_diagnostics(text, phase):
    """Only identify a known import condition; resource validation remains mandatory."""
    lines=re.sub(r'\x1b\[[0-9;]*m','',text).splitlines()
    resource=''; importing=False; diagnostics=[]
    for index,line in enumerate(lines):
        active=re.search(r'\breimport\s*\|\s*(.+)$',line)
        if active: resource=active.group(1); importing=False
        if re.search(r'\bimport\s*\|\s*Importing Scene\.\.\.$',line): importing=True
        if re.search(r'\[\s*DONE\s*\]\s*import\b',line): importing=False
        if not re.search(r'(?:ERROR:|SCRIPT ERROR:|WARNING:)',line): continue
        trace=lines[index+1] if index+1<len(lines) else ''
        known=(phase=='import' and resource=='shiroko_drone.glb' and importing and
               line==DRONE_DIAGNOSTIC and trace=='   at: get_quaternion (core/math/basis.cpp:716)')
        diagnostics.append({'line':index+1,'message':line,'trace':trace,'resource':resource,'known_import_condition':known})
    accepted=bool(diagnostics) and len(diagnostics)==6 and all(r['known_import_condition'] for r in diagnostics)
    return {'passed':not diagnostics or accepted,'phase':phase,'diagnostics':diagnostics,
            'accepted_count':6 if accepted else 0,'requires_drone_resource_validation':accepted}

def validate_drone_inputs(stage):
    for path,digest in DRONE_HASHES.items():
        source=stage/path
        if not source.is_file() or source.is_symlink() or sha256(source)!=digest:
            raise ValueError('Reviewed drone input hash mismatch: '+path)
    raw=(stage/DRONE).read_bytes()
    size=struct.unpack_from('<I',raw,12)[0]
    gltf=json.loads(raw[20:20+size])
    wings=[i for i,n in enumerate(gltf['nodes']) if n.get('name','').endswith('wingB')]
    if len(wings)!=2 or gltf['skins'][1]['joints']!=wings or any(gltf['nodes'][i]['scale']!=[0.0,0.0,0.0] for i in wings):
        raise ValueError('Reviewed zero-rest drone source contract changed')
    return {'source_hashes':DRONE_HASHES,'authored_zero_rest_rotor_nodes':wings}

def validate_drone_resources(args, info, stage, env, checks, logs):
    """Run pinned existing assertions against freshly imported mobile resources."""
    report=validate_drone_inputs(stage)
    probes={
        'native_drone_pose_probe.gd':('DRONE_POSE_PROBE runtime',True),
        'test_native_drone_layout.gd':('DRONE_LAYOUT_TESTS',False),
        'test_native_skill_props_assets.gd':('SKILL_PROP_ASSETS',False),
    }
    report['probes']={}
    for name,(marker,writes_pose) in probes.items():
        data=subprocess.check_output(['git','-C',str(args.repo),'show',info['source_commit']+':tests/'+name])
        probe=checks/name
        with probe.open('xb') as output: output.write(data)
        argv=[args.godot,'--headless','--path',stage,'--script',probe]
        pose=checks/'drone-runtime-poses.json'
        if writes_pose: argv+=['--','--output',pose]
        text=command(argv,env,logs/(name+'.log'),cwd=stage,timeout=args.timeout,godot=True)
        summary=next((line for line in text.splitlines() if line.startswith(marker)),None)
        if not summary or not summary.endswith('0 failures'): raise ValueError('Drone probe did not pass: '+name)
        report['probes'][name]={'sha256':hashlib.sha256(data).hexdigest(),'summary':summary,'no_engine_diagnostics':True}
        if writes_pose:
            poses=json.loads(pose.read_text())
            def finite(value):
                if isinstance(value,dict):return all(finite(v) for v in value.values())
                if isinstance(value,list):return all(finite(v) for v in value)
                return isinstance(value,(int,float)) and math.isfinite(value)
            if len(poses.get('samples',[]))<360 or not finite(poses):raise ValueError('Drone pose samples incomplete or nonfinite')
            report['pose_samples']=len(poses['samples']);report['all_pose_values_finite']=True
    report['passed']=True
    base.write_json(checks/'drone-resource-validation.json',report)
    return report

def verify_toolchain(args):
    rows = {}
    if sha256(args.godot) != base.ENGINE_SHA256: raise ValueError('Godot 4.6.3 binary hash mismatch')
    if (args.templates/'version.txt').read_text().strip() != '4.6.3.stable': raise ValueError('Template version mismatch')
    for name,(size,digest) in TEMPLATES.items():
        path = args.templates/name
        if not path.is_file() or path.stat().st_size != size or sha256(path) != digest: raise ValueError('Template mismatch: ' + name)
        rows[name] = {'bytes': size, 'sha256': digest}
    for path in [args.sdk/'build-tools/35.0.1'/x for x in ('aapt','apksigner','zipalign')] + [args.java_home/'bin/java',args.java_home/'bin/keytool']:
        if not path.is_file() or not os.access(path, os.X_OK): raise ValueError('Missing executable: ' + str(path))
    return {'godot_sha256': base.ENGINE_SHA256, 'templates': rows, 'engine_version': '4.6.3.stable',
            'official_template_archive_sha256': '3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8',
            'build_tools_version': '35.0.1'}

def prepare_private_key_parent(parent):
    # Never chmod a pre-existing caller-owned parent (for example /tmp).
    Path(parent).mkdir(mode=0o700, parents=True, exist_ok=True)

def ensure_test_keystore(path, java, env, logs, create=False):
    path = Path(path)
    if path.is_symlink(): raise ValueError('Keystore must not be a symlink')
    if not path.exists():
        if not create: raise ValueError('Missing local test keystore; use --create-debug-keystore for first build')
        prepare_private_key_parent(path.parent)
        command([java/'bin/keytool','-genkeypair','-keystore',path,'-storetype','JKS','-storepass','android',
                 '-keypass','android','-alias','androiddebugkey','-keyalg','RSA','-keysize','2048','-validity','10000',
                 '-dname','CN=Android Debug,O=Android,C=US'],env,logs/'create-test-key.log',timeout=60)
        path.chmod(0o600)
    if not path.is_file(): raise ValueError('Keystore is not a regular file')
    cert = subprocess.check_output([str(java/'bin/keytool'),'-exportcert','-keystore',str(path),'-storepass','android','-alias','androiddebugkey'],env=env,stderr=subprocess.PIPE)
    return hashlib.sha256(cert).hexdigest()

def staging_integrity(stage, info, original_imports, project_text, keep_sidecars, preset_text):
    allowed=set(keep_sidecars); changed=[]; mobile=[]; unchanged=0
    for row in info['files']:
        path=stage/row['path']; relative=row['path']
        if not path.is_file() or path.is_symlink(): changed.append(relative); continue
        data=path.read_bytes()
        if relative=='project.godot':
            if data != project_text.encode(): changed.append(relative)
        elif relative in allowed:
            expected='[remap]\n\nimporter="keep"\n\n[deps]\n\nsource_file="res://'+relative.removesuffix('.import')+'"\n'
            if data != expected.encode(): changed.append(relative)
        else:
            digest=hashlib.new(info['git_object_format'],('blob '+str(len(data))+'\0').encode()+data).hexdigest()
            if digest == row['git_blob']: unchanged+=1
            elif relative in original_imports and mobile_import_change_allowed(original_imports[relative],data.decode()): mobile.append(relative)
            else: changed.append(relative)
    base.assert_plain_tree(stage)
    tracked={row['path'] for row in info['files']}
    generated={'project.godot','export_presets.cfg','assets/ui/android_launcher.svg'}
    extras=[]
    for path in stage.rglob('*'):
        if not path.is_file(): continue
        relative=path.relative_to(stage).as_posix()
        if relative in tracked or relative in generated or relative.startswith('.godot/'): continue
        if relative.endswith('.uid') and relative[:-4] in tracked: continue
        if relative.endswith('.import') and relative[:-7] in tracked|generated: continue
        extras.append(relative)
    icon=stage/'assets/ui/android_launcher.svg'
    if not icon.is_file() or sha256(icon)!=sha256(HERE/'launcher_icon.svg'): changed.append('assets/ui/android_launcher.svg')
    preset=stage/'export_presets.cfg'
    if not preset.is_file() or preset.read_text()!=preset_text: changed.append('export_presets.cfg')
    return {'passed':not (changed or extras),'unexpected_changed_files':changed,'unexpected_extra_files':sorted(extras),'unchanged_git_blobs':unchanged,
            'allowed_project_settings':PROJECT_OVERRIDES,'allowed_keep_sidecars':sorted(allowed),'mobile_import_metadata_changes':sorted(mobile)}

def execute(args, info):
    toolchain=verify_toolchain(args)
    args.output_root.mkdir(parents=True,exist_ok=False)
    stage=args.output_root/'staging'; checks=args.output_root/'checks'; logs=args.output_root/'logs'; deliver=args.output_root/'deliverable'
    for folder in (stage,checks,logs,deliver): folder.mkdir()
    base.write_json(checks/'source-commit.json',info)
    base.archive_commit(args.repo,info['source_commit'],stage)
    initial=base.stage_integrity(stage,info); base.write_json(checks/'archive-integrity.json',initial)
    if not initial['passed']: raise ValueError('Archive differs from pinned Git blobs')
    if (stage/'.godot').exists(): raise ValueError('Staging must start without any desktop import cache')
    manifest=build_manifest(stage)
    for category,count in base.EXPECTED.items():
        if manifest['summary']['counts'].get(category)!=count: raise ValueError('Dependency count changed: '+category)
    base.write_json(checks/'dependency-manifest.json',manifest)
    originals={row['path']:(stage/row['path']).read_text() for row in info['files'] if row['path'].endswith('.import')}
    project=android_project((stage/'project.godot').read_text()); (stage/'project.godot').write_text(project)
    keep=base.keep_raw_imports(stage,manifest)
    icon=stage/'assets/ui/android_launcher.svg'
    if icon.exists(): raise ValueError('Android generated icon would overwrite tracked source')
    icon.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(HERE/'launcher_icon.svg',icon)
    preset=android_preset(args.templates); (stage/'export_presets.cfg').write_text(preset)
    filters=json.loads(config_value(preset,'preset.0','exclude_filter')).split(',')
    collisions=sorted({row['path'] for row in manifest['files'] for pattern in filters if fnmatch.fnmatchcase(row['path'],pattern)})
    if collisions: raise ValueError('Excluded required dependency: '+str(collisions))
    env=android_environment(args.output_root/'scratch',args.sdk,args.java_home,args.keystore)
    fingerprint=ensure_test_keystore(args.keystore,args.java_home,env,logs,args.create_debug_keystore)
    apk=deliver/('Blue-A-Android-arm64-'+info['source_commit'][:12]+'-private.apk')
    invocations=[('import',[args.godot,'--headless','--path',stage,'--editor','--import']),
                 ('export',[args.godot,'--headless','--path',stage,'--export-release',PRESET,apk])]
    base.write_json(checks/'commands.json',[{'step':name,'argv':[str(x) for x in argv]} for name,argv in invocations])
    for name,argv in invocations:
        print('Running '+name,flush=True)
        text=command(argv,env,logs/(name+'.log'),cwd=stage,timeout=args.timeout,godot=name!='import')
        if name=='import':
            import_diagnostics=classify_godot_diagnostics(text,'import')
            base.write_json(checks/'import-diagnostics.json',import_diagnostics)
            if not import_diagnostics['passed']: raise ValueError('Unreviewed Android import diagnostics')
            imported=staging_integrity(stage,info,originals,project,keep,preset); base.write_json(checks/'pre-export-integrity.json',imported)
            if not imported['passed']: raise ValueError('Unexpected staging changes after import')
            drone_validation=validate_drone_resources(args,info,stage,env,checks,logs)
    integrity=staging_integrity(stage,info,originals,project,keep,preset); base.write_json(checks/'stage-integrity.json',integrity)
    if not integrity['passed']: raise ValueError('Unexpected staging source changes')
    resources=verify_resources(apk,manifest,stage); base.write_json(checks/'apk-resources.json',resources)
    if not resources['passed']: raise ValueError('APK resource verification failed')
    audio_pack=checks/'apk-audio-only.zip'
    make_audio_verification_pack(apk,manifest,audio_pack)
    audio_env=base.environment(args.output_root/'scratch-audio')
    audio_root=args.output_root/'isolated-audio'; audio_root.mkdir()
    command([args.godot,'--headless','--path',audio_root,'--script',HERE/'verify_audio.gd','--',
             audio_pack,checks/'dependency-manifest.json',checks/'apk-audio.json'],audio_env,
            logs/'apk-audio.txt',cwd=audio_root,timeout=args.timeout,godot=True)
    audio_report=json.loads((checks/'apk-audio.json').read_text())
    if (audio_report.get('passed') is not True or audio_report.get('ordinary_audio_streams')!=base.EXPECTED['ordinary_audio_streams'] or
        audio_report.get('skill_audio_streams')!=base.EXPECTED['audio_streams']): raise ValueError('Packaged audio contract failed')
    bt=args.sdk/'build-tools/35.0.1'
    badging=command([bt/'aapt','dump','badging',apk],env,logs/'apk-badging.txt')
    permissions=command([bt/'aapt','dump','permissions',apk],env,logs/'apk-permissions.txt')
    xml=command([bt/'aapt','dump','xmltree',apk,'AndroidManifest.xml'],env,logs/'apk-manifest.txt')
    metadata=verify_metadata(badging,permissions,xml); base.write_json(checks/'apk-metadata.json',metadata)
    if not metadata['passed']: raise ValueError('APK manifest verification failed: '+str(metadata['failures']))
    signature=command([bt/'apksigner','verify','--verbose','--print-certs',apk],env,logs/'apk-signature.txt')
    actual=re.search(r'^Signer #1 certificate SHA-256 digest: ([0-9a-f]+)$',signature,re.M)
    if not actual or actual.group(1)!=fingerprint or 'Verified using v2 scheme (APK Signature Scheme v2): true' not in signature:
        raise ValueError('APK signer fingerprint or v2 signature mismatch')
    command([bt/'zipalign','-c','-P','16','-v','4',apk],env,logs/'apk-zipalignment.txt')
    for name in ('ASSET-NOTICE.zh-CN.txt','GODOT-LICENSE.txt','GODOT-THIRD-PARTY-NOTICES.txt'):
        shutil.copyfile(WINDOWS/'notices'/name,deliver/name)
    (deliver/'README.zh-CN.txt').write_text(readme(info['source_commit']),encoding='utf-8')
    build={'source_commit':info['source_commit'],'source_tree':info['source_tree'],'built_at_utc':datetime.now(timezone.utc).isoformat(),
           'platform':'Android ARM64','package':'com.bluea.prototype','private_candidate':True,'runtime':'release',
           'signing':'Local standard Android debug certificate, private testing only','signer_certificate_sha256':fingerprint,
           'toolchain':toolchain,'dependencies':manifest['summary']['counts'],'project_overrides':PROJECT_OVERRIDES,
           'import_diagnostics':import_diagnostics,'drone_resource_validation':drone_validation,
           'dependency_manifest_sha256':sha256(checks/'dependency-manifest.json'),'preset_sha256':sha256(stage/'export_presets.cfg'),
           'pipeline_files':{str(p.relative_to(HERE.parent)):sha256(p) for p in sorted(HERE.glob('*.py'))+sorted(HERE.glob('*.gd'))+sorted(HERE.glob('*.in'))+sorted(HERE.glob('*.svg'))+[WINDOWS/'dependency_manifest.py',WINDOWS/'release_pipeline.py',WINDOWS/'export_presets.cfg.in']},
           'validation':{'fresh_android_import_cache':True,'pinned_staging_integrity':True,'apk_resources':True,
                         'apk_manifest':True,'apk_signature_v2':True,'zip_alignment_4_and_native_16k':True,
                         'ordinary_audio_pcm_contract':True,'skill_audio_load_contract':True,
                         'device_installation':False,'device_rendering':False,'audible_audio':False,'device_fps_or_2k':False},
           'files':{p.name:{'bytes':p.stat().st_size,'sha256':sha256(p)} for p in sorted(deliver.iterdir())}}
    base.write_json(deliver/'BUILD-MANIFEST.json',build)
    (deliver/'SHA256SUMS.txt').write_text(''.join(sha256(p)+'  '+p.name+'\n' for p in sorted(deliver.iterdir())))
    result={'passed':True,'source_commit':info['source_commit'],'apk':str(apk),'bytes':apk.stat().st_size,'sha256':sha256(apk),
            'checks':str(checks),'deliverable':str(deliver),'device_verified':False}
    base.write_json(args.output_root/'BUILD-RESULT.json',result); print(json.dumps(result,indent=2))

def readme(commit):
    return f'''Blue-A 自走棋 · Android ARM64 私人试玩包\n源码检查点：{commit}\nGodot 4.6.3 / Compatibility OpenGL / Android 7.0 (API 24) 或更新版本\n包名：com.bluea.prototype。仅支持64位 ARM 安卓兼容设备；鸿蒙4.2真实安装与运行仍需真机验证。\n\n将 APK 传到手机后使用系统安装器打开，仅在系统提示时允许该来源安装。无需 Godot、浏览器、服务器或网络权限。此包用本地 Android 调试证书签名，仅供私人测试，不用于商店或公开发布。后续更新需相同签名；更换签名可能需要卸载，卸载会删除本地存档。\n\n横屏触控；点击招募、选择角色，准备阶段拖动布阵。菜单里可以保存、读取和调整音量、画质、渲染比例、30/60/90/120帧上限。UI保持原生窗口分辨率绘制，渲染比例仅调整3D画面。设置保存在应用私有目录，不申请外部存储权限，不启用云备份。\n低档只影响显示，不改变战斗规则；高档保留角色、技能与原始音效内容。画质档位、渲染比例与帧率上限可分别调整。2K清晰度与120帧只是可选目标，云端打包检查不代表设备实测达标。\n\n本包通过源码快照、APK资源哈希、包名/ABI/权限/签名/对齐检查。尚未在用户手机核验安装、触控体验、实际可听音频、兼容性、温度或帧率。\n包含原作素材，仅供私人测试；不授予公开发布、商业使用或再分发许可。参见随附素材与Godot许可声明。\n'''

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',required=True,type=Path); parser.add_argument('--commit',required=True)
    parser.add_argument('--output-root',required=True,type=Path)
    parser.add_argument('--templates',type=Path,default=DEFAULT_TOOLCHAIN/'godot-templates/4.6.3.stable')
    parser.add_argument('--sdk',type=Path,default=DEFAULT_TOOLCHAIN/'sdk')
    parser.add_argument('--java-home',type=Path,default=Path('/usr/lib/jvm/java-21-openjdk-amd64'))
    parser.add_argument('--godot',type=Path,default=Path('/usr/local/bin/godot'))
    parser.add_argument('--keystore',required=True,type=Path)
    parser.add_argument('--create-debug-keystore',action='store_true',help='Create a local private-test signing key if it does not exist')
    parser.add_argument('--timeout',type=int,default=1800)
    group=parser.add_mutually_exclusive_group(); group.add_argument('--execute',action='store_true'); group.add_argument('--dry-run',action='store_true')
    args=parser.parse_args(argv)
    if args.timeout<=0: raise ValueError('Timeout must be positive')
    if args.keystore.is_symlink(): raise ValueError('Keystore must not be a symlink')
    args.output_root=validate_output(args.output_root,[args.repo,args.templates,args.sdk,args.java_home])
    for name in ('repo','templates','sdk','java_home','godot','keystore'): setattr(args,name,getattr(args,name).resolve())
    if args.keystore.is_relative_to(args.repo) or args.keystore.is_relative_to(args.output_root): raise ValueError('Test keystore must be outside source and build output')
    info=base.source_info(args.repo,args.commit)
    if args.execute: execute(args,info)
    else: print(json.dumps({'mode':'dry-run','source_commit':info['source_commit'],'source_tree':info['source_tree'],
        'archived_roots':base.ROOTS,'tracked_snapshot_files':len(info['files']),'output_root':str(args.output_root),
        'godot_executed':False,'output_created':False,'fresh_import_cache':True,'package':'com.bluea.prototype','abi':'arm64-v8a',
        'steps':['pinned git archive','dependency manifest and raw Keep File overrides','Android staging settings','fresh ETC2/ASTC import',
                 'release APK export with local test signing','staging source integrity','APK resource/package/ABI/permission gates',
                 'v2 signature and certificate verification','4-byte ZIP and 16K native alignment verification','notices and checksums']},indent=2))

if __name__=='__main__':
    try: main()
    except (ValueError,RuntimeError,OSError,subprocess.SubprocessError,AssertionError) as error:
        print('ERROR: '+str(error),file=sys.stderr);sys.exit(1)
