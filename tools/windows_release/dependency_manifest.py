"""Derive runtime dependencies from the pinned staging tree, never a saved manifest."""
import hashlib
import json
import math
import re
import wave
from collections import Counter
from pathlib import Path, PurePosixPath

EXTRACTION_PREFIXES = ('ParticleSystem-', 'ParticleSystemRenderer-', 'MonoBehaviour-',
    'Material-', 'Mesh-', 'Shader-', 'MeshFilter-', 'MeshRenderer-', 'Animator-', 'PlayableDirector-')
RAW_CATEGORIES = {'runtime_json', 'vfx_texture_json', 'vfx_texture_png', 'mesh_raw',
                  'animation_libraries', 'animation_library_manifests'}
ORDINARY_STATES = {'Base Layer.Normal.AttackIng': 'attack_fire', 'Base Layer.Normal.Reload': 'reload'}

def safe_relative(value):
    value = str(value).removeprefix('res://')
    parts = PurePosixPath(value).parts
    if not parts or value.startswith('/') or '\\' in value or any(x in ('.', '..') for x in value.split('/')) or ':' in value:
        raise ValueError('Unsafe relative path: ' + value)
    return value

def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def animation_library_dependencies(root, profiles):
    """Pin optional native resources to actual source bytes, including inactive profiles.

    The engine validates the binary Resource contract and selected UnitView content.
    Source GLBs are hashed here, before imports can remap/remove them in the PCK.
    """
    root = Path(root).resolve()
    optional_fields = ('animation_library_path', 'animation_library_manifest_path',
                       'animation_library_sha256', 'animation_library_manifest_sha256')
    rows = []
    for character, profile in sorted(profiles.items()):
        if not any(field in profile for field in optional_fields):
            continue
        row = {'character': character}
        for path_field, hash_field, suffix in (
                ('model_path', 'source_glb_sha256', '.glb'),
                ('animation_library_path', 'animation_library_sha256', '.res'),
                ('animation_library_manifest_path', 'animation_library_manifest_sha256', '.res')):
            value = profile.get(path_field)
            if not isinstance(value, str) or not value.startswith('res://') or not value.endswith(suffix):
                raise ValueError('Invalid animation override ' + path_field + ': ' + character)
            relative = safe_relative(value); path = root / relative
            if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(root):
                raise ValueError('Missing or unsafe animation dependency: ' + relative)
            expected = profile.get(hash_field)
            if not isinstance(expected, str) or not re.fullmatch('[0-9a-f]{64}', expected):
                raise ValueError('Invalid animation override SHA256 ' + hash_field + ': ' + character)
            if sha256(path) != expected:
                raise ValueError('Animation dependency SHA256 mismatch: ' + relative)
            row[path_field] = value; row[hash_field] = expected
        if row['animation_library_path'] == row['animation_library_manifest_path']:
            raise ValueError('Animation library and manifest paths must differ: ' + character)
        clips = profile.get('clips')
        if not isinstance(clips, dict) or not clips or any(not isinstance(value, str) for value in clips.values()):
            raise ValueError('Invalid animation override required clips: ' + character)
        row['required_clips'] = sorted({value for value in clips.values() if value})
        if not row['required_clips']:
            raise ValueError('Missing animation override required clips: ' + character)
        rows.append(row)
    return rows

def ordinary_audio_dependencies(root, profiles, roster):
    """Verify source WAV bytes and retain decoded PCM expectations for import/PCK checks."""
    root = Path(root).resolve()
    source = root / 'data/audio/native-ordinary-sfx.json'
    if not source.is_file() or source.is_symlink() or not source.resolve().is_relative_to(root):
        raise ValueError('Missing or unsafe ordinary audio manifest')
    data = json.loads(source.read_text())
    if not isinstance(data, dict) or data.get('schema_version') != 1 or not isinstance(data.get('assets'), dict) or not isinstance(data.get('bindings'), list):
        raise ValueError('Invalid ordinary audio manifest')
    assets = data['assets']; rows = []; paths = set()
    for name, asset in assets.items():
        if not isinstance(asset, dict) or not isinstance(asset.get('path'), str):
            raise ValueError('Invalid ordinary audio asset: ' + name)
        relative = safe_relative(asset['path']); path = root / relative
        if not relative.startswith('assets/audio/native-ordinary/') or not relative.endswith('.wav') or relative in paths:
            raise ValueError('Unsafe or duplicate ordinary audio path: ' + relative)
        if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(root):
            raise ValueError('Missing or unsafe ordinary audio dependency: ' + relative)
        paths.add(relative)
        if sha256(path) != asset.get('wav_sha256'):
            raise ValueError('Ordinary WAV SHA256 mismatch: ' + name)
        expected = {'channels': 1, 'sample_rate_hz': 22050, 'bits_per_sample': 16}
        if any(type(asset.get(key)) is not int or asset[key] != value for key, value in expected.items()) or type(asset.get('frames')) is not int or not 0 < asset['frames'] <= 10000000:
            raise ValueError('Invalid ordinary PCM metadata: ' + name)
        duration = asset.get('duration_seconds')
        if type(duration) not in (int, float) or not math.isfinite(duration) or not math.isclose(duration, asset['frames'] / 22050, rel_tol=0, abs_tol=1e-9):
            raise ValueError('Invalid ordinary PCM duration: ' + name)
        try:
            with wave.open(str(path), 'rb') as stream:
                if (stream.getnchannels(), stream.getframerate(), stream.getsampwidth(), stream.getnframes(), stream.getcomptype()) != (1, 22050, 2, asset['frames'], 'NONE'):
                    raise ValueError('Ordinary WAV PCM format/frame mismatch: ' + name)
                pcm = stream.readframes(stream.getnframes())
        except (wave.Error, EOFError) as error:
            raise ValueError('Invalid ordinary WAV: ' + name) from error
        if len(pcm) != asset['frames'] * 2 or hashlib.sha256(pcm).hexdigest() != asset.get('pcm_sha256'):
            raise ValueError('Ordinary PCM SHA256/length mismatch: ' + name)
        rows.append(dict(expected, path=relative, frames=asset['frames'], pcm_sha256=asset['pcm_sha256']))
    seen = set()
    for binding in data['bindings']:
        if not isinstance(binding, dict):
            raise ValueError('Invalid ordinary audio binding')
        character = binding.get('character'); state = binding.get('state_name')
        if not isinstance(character, str) or character not in roster or not isinstance(state, str) or state not in ORDINARY_STATES:
            raise ValueError('Unknown ordinary audio character/state')
        identity = (character, state)
        if identity in seen or binding.get('binding_id') != character + ':' + state:
            raise ValueError('Duplicate or invalid ordinary audio binding: ' + str(identity))
        seen.add(identity)
        if not binding.get('native_clip') or binding['native_clip'] != profiles[character].get('clips', {}).get(ORDINARY_STATES[state]):
            raise ValueError('Ordinary audio clip does not match presentation: ' + str(identity))
        clips = binding.get('clips')
        if not isinstance(clips, list) or not clips or any(not isinstance(clip, str) or clip not in assets for clip in clips):
            raise ValueError('Missing ordinary audio pool: ' + str(identity))
        for field in ('raw_delay', 'raw_volume'):
            value = binding.get(field)
            if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
                raise ValueError('Invalid ordinary audio ' + field + ': ' + str(identity))
    if seen != {(character, state) for character in roster for state in ORDINARY_STATES}:
        raise ValueError('Incomplete ordinary audio state bindings')
    return sorted(rows, key=lambda row: row['path'])

def build_manifest(root):
    root = Path(root).resolve()
    rows = set()
    def add(category, path):
        relative = safe_relative(path)
        target = root / relative
        if not target.is_file() or target.is_symlink() or not target.resolve().is_relative_to(root):
            raise ValueError('Missing or unsafe source dependency: ' + relative)
        rows.add((category, relative))
    def glob(category, patterns):
        for pattern in patterns:
            for path in sorted(root.glob(pattern)):
                if path.is_file(): add(category, path.relative_to(root).as_posix())
    icons = json.loads((root/'data/skill-icons.json').read_text())
    for key, icon in icons['assets'].items():
        add('skill_icons', icon['path'])
        if sha256(root/safe_relative(icon['path'])) != icon['sha256']:
            raise ValueError('Skill icon provenance mismatch: ' + key)
    for character, slots in icons['characters'].items():
        if set(slots) != {'ex', 'basic', 'sub'}:
            raise ValueError('Incomplete skill icon slots: ' + character)
        for key in slots.values():
            if key not in icons['assets']: raise ValueError('Unknown skill icon reference: ' + key)
    glob('mesh_raw', ['data/effects/**/*.obj', 'data/effects/**/*.nativeobj'])
    glob('vfx_texture_png', ['data/effects/**/*.png'])
    glob('vfx_texture_json', ['data/effects/**/Texture2D-*.json'])
    glob('runtime_json', ['data/*.json', 'data/audio/*.json', 'data/effects/**/battle-events-compact.json',
                         'data/effects/**/visual-templates.json', 'assets/**/runtime-metadata.json', 'assets/**/material-bindings.json'])
    profiles = json.loads((root/'data/character-presentations.json').read_text())
    compact = json.loads((root/'data/effects/battle-events-compact.json').read_text())
    roster = compact['activeRoster']
    if len(set(roster)) != len(roster): raise ValueError('Duplicate active character')
    animation_overrides = animation_library_dependencies(root, profiles)
    for character in roster:
        profile = profiles[character]
        add('character_models', profile['model_path'])
        add('portraits', f'assets/ui/portraits/{character}.png')
        for material in profile.get('materials', []):
            for texture in material.get('textures', {}).values():
                if texture: add('character_textures', texture)
    active_models = {safe_relative(profiles[character]['model_path']) for character in roster}
    for override in animation_overrides:
        add('animation_libraries', override['animation_library_path'])
        add('animation_library_manifests', override['animation_library_manifest_path'])
        if safe_relative(override['model_path']) not in active_models:
            add('optional_animation_models', override['model_path'])
        # Real UnitView setup applies these textures even for an inactive fixture.
        for material in profiles[override['character']].get('materials', []):
            for texture in material.get('textures', {}).values():
                if texture: add('character_textures', texture)
    audio = json.loads((root/'data/audio/native-skill-sfx.json').read_text())
    for row in audio['records']:
        if row.get('resourcePath'): add('audio_streams', row['resourcePath'])
    add('audio_bus_layout', 'assets/audio/combat_bus_layout.tres')
    ordinary = {row['path']: row for row in ordinary_audio_dependencies(root, profiles, roster)}
    for path in ordinary: add('ordinary_audio_streams', path)
    for path in ['scripts/ordinary_combat_audio.gd', 'scripts/native_combat_audio.gd']:
        add('audio_runtime_scripts', path)
    glob('prop_fallback_or_shader', ['assets/ground_mines/**/*.png', 'assets/ground_mines/**/*.glb',
        'assets/skill_props/**/*.png', 'assets/skill_props/**/*.glb', 'assets/native/**/*.png',
        'assets/native/**/*.fbx', 'shaders/**/*.gdshader', 'vfx/materials/shaders/**/*.gdshader'])
    excluded = sorted(p.relative_to(root).as_posix() for p in root.glob('data/effects/**/*.json')
                      if p.name.startswith(EXTRACTION_PREFIXES))
    raw = {path for category, path in rows if category in RAW_CATEGORIES}
    if raw.intersection(excluded): raise ValueError('Runtime dependencies intersect extraction exclusions')
    # Every PNG needs its original Texture2D metadata; do not prune all resources JSON.
    for category, path in tuple(rows):
        if category == 'vfx_texture_png':
            add('vfx_texture_json', str(PurePosixPath(path).with_suffix('.json')))
    files = [{'category': category, 'path': path, 'bytes': (root/path).stat().st_size,
              'sha256': sha256(root/path)} for category, path in sorted(rows)]
    for row in files:
        if row['category'] == 'ordinary_audio_streams': row.update(ordinary[row['path']])
    return {'schema_version': 1, 'summary': {'source_root': str(root), 'active_roster': roster,
        'counts': dict(sorted(Counter(x['category'] for x in files).items())),
        'raw_obj_requires_keep_override': sum(x['category']=='mesh_raw' and x['path'].endswith('.obj') for x in files),
        'missing_source_dependencies': [], 'source_only_effect_json_count': len(excluded)},
        'files': files, 'animation_overrides': animation_overrides, 'excluded_effect_source_json': excluded}

def nonomi_null_material(root):
    data = json.loads((Path(root)/'data/effects/nonomi/visual-templates.json').read_text())
    for prefab in data.get('prefabs', []):
        if prefab.get('name') != 'FX_Nonomi_Original_Ex01_Motion_Fire_01': continue
        for node in prefab.get('nodes', []):
            if node.get('hierarchy') == 'FX_Nonomi_Original_Ex01_Motion_Fire_01/smoke':
                for component in node.get('components', []):
                    if component.get('type') == 'ParticleSystemRenderer':
                        materials = component.get('materials', [])
                        return bool(materials) and all(isinstance(m, dict) and 'materialKey' in m and 'sourceReference' in m and m['materialKey'] is None and m['sourceReference'] is None for m in materials)
    return False
