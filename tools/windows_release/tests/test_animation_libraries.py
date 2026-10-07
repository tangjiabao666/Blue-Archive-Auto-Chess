"""Optional native animation packaging gates; no Godot/export invocation."""
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest

from test_pipeline import HERE, load_module
from test_ordinary_audio import ordinary_fixture, write_pack


def digest(data):
    return hashlib.sha256(data).hexdigest()


def fixture(root):
    def put(path, data):
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data if isinstance(data, bytes) else json.dumps(data).encode())
    profiles = {'unit': {'model_path': 'res://assets/unit.glb', 'clips': {'attack_fire': 'fire', 'reload': 'reload'}},
                'optional': {'model_path': 'res://assets/optional.glb', 'clips': {'idle': 'idle', 'attack_fire': 'fire', 'unused': ''},
                             'animation_library_path': 'res://assets/optional.animations.res',
                             'animation_library_manifest_path': 'res://assets/optional.contract.res',
                             'animation_library_sha256': digest(b'RSRClibrary'),
                             'animation_library_manifest_sha256': digest(b'RSRCcontract'),
                             'source_glb_sha256': digest(b'glTFsource')}}
    put('data/character-presentations.json', profiles)
    put('data/effects/battle-events-compact.json', {'activeRoster': ['unit']})
    put('data/skill-icons.json', {'assets': {}, 'characters': {}})
    put('data/audio/native-skill-sfx.json', {'records': []})
    ordinary_fixture(root)
    put('assets/unit.glb', b'glTFunit')
    put('assets/ui/portraits/unit.png', b'portrait')
    put('assets/optional.glb', b'glTFsource')
    put('assets/optional.animations.res', b'RSRClibrary')
    put('assets/optional.contract.res', b'RSRCcontract')
    return profiles


class AnimationDependencies(unittest.TestCase):
    def setUp(self):
        self.m = load_module('dependency_manifest')
        self.tmp = tempfile.TemporaryDirectory(dir=HERE)
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.profiles = fixture(self.root)

    def manifest(self):
        (self.root / 'data/character-presentations.json').write_text(json.dumps(self.profiles))
        return self.m.build_manifest(self.root)

    def test_discovers_inactive_override_and_required_metadata_without_portrait(self):
        result = self.manifest()
        self.assertEqual(result['summary']['active_roster'], ['unit'])
        rows = {row['path']: row for row in result['files']}
        self.assertEqual(rows['assets/optional.animations.res']['category'], 'animation_libraries')
        self.assertEqual(rows['assets/optional.contract.res']['category'], 'animation_library_manifests')
        self.assertEqual(rows['assets/optional.glb']['category'], 'optional_animation_models')
        self.assertEqual(result['summary']['counts']['character_models'], 1)
        self.assertNotIn('assets/ui/portraits/optional.png', rows)
        expected = dict(self.profiles['optional'], character='optional', required_clips=['fire', 'idle'])
        expected.pop('clips')
        self.assertEqual(result['animation_overrides'], [expected])
        self.assertTrue({'animation_libraries', 'animation_library_manifests'} <= self.m.RAW_CATEGORIES)

    def test_profiles_without_override_remain_optional(self):
        self.profiles['optional'] = {'model_path': 'res://assets/absent.glb'}
        result = self.manifest()
        self.assertEqual(result['animation_overrides'], [])
        self.assertNotIn('optional_animation_models', result['summary']['counts'])

    def test_rejects_partial_or_invalid_override_fields(self):
        base = copy.deepcopy(self.profiles)
        fields = ['model_path', 'source_glb_sha256', 'animation_library_path',
                  'animation_library_manifest_path', 'animation_library_sha256',
                  'animation_library_manifest_sha256', 'clips']
        for field in fields:
            with self.subTest(missing=field):
                self.profiles = copy.deepcopy(base)
                del self.profiles['optional'][field]
                with self.assertRaises(ValueError):
                    self.manifest()
        for field, value in [('animation_library_sha256', True), ('source_glb_sha256', '0' * 63),
                             ('animation_library_manifest_sha256', 'g' * 64), ('clips', {}),
                             ('clips', {'idle': None}), ('clips', {'idle': ''}),
                             ('animation_library_path', 'res://assets/optional.tres'),
                             ('animation_library_path', '../outside.res'),
                             ('animation_library_manifest_path', 'user://contract.res'),
                             ('model_path', 'res://assets/optional.fbx')]:
            with self.subTest(field=field, value=value):
                self.profiles = copy.deepcopy(base)
                self.profiles['optional'][field] = value
                with self.assertRaises(ValueError):
                    self.manifest()

    def test_rejects_missing_modified_or_symlinked_dependencies(self):
        for relative in ['assets/optional.glb', 'assets/optional.animations.res', 'assets/optional.contract.res']:
            path = self.root / relative
            original = path.read_bytes()
            with self.subTest(path=relative, kind='missing'):
                path.unlink()
                with self.assertRaises(ValueError):
                    self.manifest()
                path.write_bytes(original)
            with self.subTest(path=relative, kind='modified'):
                path.write_bytes(original + b'changed')
                with self.assertRaisesRegex(ValueError, 'SHA256'):
                    self.manifest()
                path.write_bytes(original)
            with self.subTest(path=relative, kind='symlink'):
                moved = path.with_suffix('.saved'); path.rename(moved); path.symlink_to(moved)
                with self.assertRaises(ValueError):
                    self.manifest()
                path.unlink(); moved.rename(path)

    def test_active_override_does_not_duplicate_model_or_require_extra_roster(self):
        self.profiles['unit'] = dict(self.profiles['optional'], clips={'attack_fire': 'fire', 'reload': 'reload'})
        del self.profiles['optional']
        result = self.manifest()
        models = [row for row in result['files'] if row['path'] == 'assets/optional.glb']
        self.assertEqual(len(models), 1)
        self.assertEqual(models[0]['category'], 'character_models')
        self.assertEqual([row['character'] for row in result['animation_overrides']], ['unit'])


class AnimationPack(unittest.TestCase):
    def test_native_resources_require_exact_raw_members_even_when_model_is_remapped(self):
        verifier = load_module('verify_pck')
        with tempfile.TemporaryDirectory(dir=HERE) as directory:
            root = Path(directory); pack = root / 'fixture.pck'; report = root / 'report.json'
            names = {'project.binary': b'project', 'game.tscn': b'scene', 'assets/optional.glb.remap': b'remap'}
            rows = [{'category': category, 'path': path, 'sha256': digest(content)} for category, path, content in [
                ('animation_libraries', 'assets/optional.animations.res', b'RSRClibrary'),
                ('animation_library_manifests', 'assets/optional.contract.res', b'RSRCcontract')]]
            manifest = {'files': rows, 'excluded_effect_source_json': []}
            def verify():
                write_pack(pack, names)
                with contextlib.redirect_stdout(io.StringIO()):
                    return verifier.verify(pack, manifest, report)
            self.assertFalse(verify())
            self.assertEqual(json.loads(report.read_text())['raw_missing'], [row['path'] for row in rows])
            names.update({'assets/optional.animations.res': b'RSRClibrary', 'assets/optional.contract.res': b'RSRCcontract'})
            self.assertTrue(verify())
            names['assets/optional.animations.res'] += b'changed'
            self.assertFalse(verify())
            self.assertEqual(json.loads(report.read_text())['raw_mismatched'], ['assets/optional.animations.res'])


class AnimationRuntimeReports(unittest.TestCase):
    def test_runtime_harness_declares_real_view_content_checks(self):
        # Structural guard only: actual Godot execution is reserved for the authorized gate.
        harness = (HERE / 'verify_runtime.gd').read_text()
        for required in ['func verify_animation_overrides(', 'res://scripts/unit_view.gd',
                         'view.setup(', 'view.diagnostics()', 'source_identity', 'source_extras',
                         'position_track_interpolate', 'rotation_track_interpolate',
                         'scale_track_interpolate', 'track_get_key_count',
                         'animation_override_samples', 'animation_library_manifests']:
            self.assertIn(required, harness)

    def test_runtime_sampler_never_mutates_cached_animation_resources(self):
        harness = (HERE / 'verify_runtime.gd').read_text()
        sampler = harness.split('func animation_sample(', 1)[1].split('func verify_animation_overrides(', 1)[0]
        self.assertNotRegex(sampler, r'clip\.\w+\s*=(?!=)')
        self.assertNotRegex(sampler, r'clip\.(?:set_|track_set_|track_insert_|track_remove_)')
        self.assertIn('track_get_key_value', sampler)
        self.assertIn('track_get_key_time', sampler)
        interpolation = sampler.split('func animation_sample_matches(', 1)[0]
        self.assertNotIn('track_get_key_value', interpolation)

    def test_declared_overrides_must_run_with_clean_diagnostics_and_parity(self):
        pipeline = load_module('release_pipeline')
        base = dict(pipeline.COUNTERS, passed=True, failures=[], failure_count=0, ordinary_audio_issues=[],
                    animation_override_profiles=['optional'], animation_override_models=1,
                    animation_override_libraries=1, animation_override_clips=2, animation_override_keys=12,
                    animation_override_samples=4, animation_override_issues=[],
                    animation_override_details={'optional': {'clips': {'idle': {'keys': 6}, 'fire': {'keys': 6}}}})
        self.assertTrue(pipeline.compare_runtime_reports(base, base, True, ['optional'])['passed'])
        for key, value in [('animation_override_profiles', []), ('animation_override_models', 0),
                           ('animation_override_libraries', 0), ('animation_override_libraries', True), ('animation_override_clips', 0),
                           ('animation_override_keys', 0), ('animation_override_samples', 0),
                           ('animation_override_issues', ['fallback']), ('animation_override_details', {})]:
            with self.subTest(key=key):
                bad = dict(base, **{key: value})
                self.assertFalse(pipeline.compare_runtime_reports(bad, bad, True, ['optional'])['passed'])
        missing = dict(base); del missing['animation_override_issues']
        self.assertFalse(pipeline.compare_runtime_reports(missing, missing, True, ['optional'])['passed'])
        changed = copy.deepcopy(base); changed['animation_override_details']['optional']['clips']['idle']['keys'] = 5
        self.assertFalse(pipeline.compare_runtime_reports(base, changed, True, ['optional'])['passed'])


if __name__ == '__main__':
    unittest.main()
