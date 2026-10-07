"""Ordinary audio packaging gates, using synthetic WAV/PCK fixtures only."""
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
import wave

from test_pipeline import HERE, load_module


def ordinary_fixture(root):
    path = root / 'assets/audio/native-ordinary/fixture.wav'
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = b'\x01\x00\xff\xff' * 4
    with wave.open(str(path), 'wb') as stream:
        stream.setparams((1, 2, 22050, 0, 'NONE', 'not compressed'))
        stream.writeframes(pcm)
    asset = {'path': 'res://' + path.relative_to(root).as_posix(),
             'wav_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
             'pcm_sha256': hashlib.sha256(pcm).hexdigest(), 'frames': 8,
             'channels': 1, 'sample_rate_hz': 22050, 'bits_per_sample': 16,
             'duration_seconds': 8 / 22050}
    data = {'schema_version': 1, 'assets': {'fixture': asset}, 'bindings': [
        {'binding_id': 'unit:' + state, 'character': 'unit', 'state_name': state,
         'native_clip': clip, 'clips': ['fixture'], 'raw_delay': 0, 'raw_volume': 1}
        for state, clip in [('Base Layer.Normal.AttackIng', 'fire'),
                            ('Base Layer.Normal.Reload', 'reload')]]}
    target = root / 'data/audio/native-ordinary-sfx.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(data))
    for name in ['ordinary_combat_audio', 'native_combat_audio']:
        target = root / ('scripts/' + name + '.gd')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text('extends Node\n')
    (root / 'assets/audio/combat_bus_layout.tres').write_text('[gd_resource type="AudioBusLayout" format=3]\n[resource]\n')
    return data, path


def write_pack(path, names):
    header = struct.pack('<4s5IQ', b'GDPC', 2, 4, 6, 3, 0, 0) + b'\0' * 64 + struct.pack('<I', len(names))
    offset = len(header) + sum(4 + len(k.encode()) + 8 + 8 + 16 + 4 for k in names)
    directory = b''
    for name, content in names.items():
        encoded = name.encode()
        directory += struct.pack('<I', len(encoded)) + encoded + struct.pack('<QQ', offset, len(content)) + hashlib.md5(content).digest() + struct.pack('<I', 0)
        offset += len(content)
    path.write_bytes(header + directory + b''.join(names.values()))


class OrdinaryDependencies(unittest.TestCase):
    def setUp(self):
        self.m = load_module('dependency_manifest')
        self.tmp = tempfile.TemporaryDirectory(dir=HERE)
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.data, self.wav = ordinary_fixture(self.root)
        self.profiles = {'unit': {'clips': {'attack_fire': 'fire', 'reload': 'reload'}}}

    def validate(self, data=None):
        (self.root / 'data/audio/native-ordinary-sfx.json').write_text(json.dumps(self.data if data is None else data))
        return self.m.ordinary_audio_dependencies(self.root, self.profiles, ['unit'])

    def test_preserves_pcm_metadata_for_runtime_verification(self):
        rows = self.validate()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['path'], 'assets/audio/native-ordinary/fixture.wav')
        self.assertEqual(rows[0]['pcm_sha256'], self.data['assets']['fixture']['pcm_sha256'])
        self.assertEqual(rows[0]['frames'], 8)

    def test_rejects_changed_wav_bytes_and_pcm_digest(self):
        self.wav.write_bytes(self.wav.read_bytes() + b'extra')
        with self.assertRaisesRegex(ValueError, 'WAV SHA256'):
            self.validate()
        self.data['assets']['fixture']['wav_sha256'] = hashlib.sha256(self.wav.read_bytes()).hexdigest()
        self.data['assets']['fixture']['pcm_sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'PCM SHA256'):
            self.validate()

    def test_rejects_pcm_format_frames_and_malformed_metadata(self):
        for field, value in [('frames', 9), ('frames', True), ('frames', 8.5),
                             ('channels', 2), ('bits_per_sample', 8), ('sample_rate_hz', 44100),
                             ('duration_seconds', 1.0)]:
            with self.subTest(field=field, value=value):
                data = copy.deepcopy(self.data)
                data['assets']['fixture'][field] = value
                with self.assertRaises(ValueError):
                    self.validate(data)

    def test_rejects_missing_unsafe_and_symlinked_wav(self):
        for path in ['res://assets/audio/native-ordinary/missing.wav', '../escape.wav',
                     'res://assets/audio/elsewhere.wav']:
            with self.subTest(path=path):
                data = copy.deepcopy(self.data)
                data['assets']['fixture']['path'] = path
                with self.assertRaises(ValueError):
                    self.validate(data)
        original = self.wav.with_suffix('.original')
        self.wav.rename(original)
        self.wav.symlink_to(original)
        with self.assertRaises(ValueError):
            self.validate()

    def test_rejects_incomplete_duplicate_or_invalid_bindings(self):
        variants = []
        data = copy.deepcopy(self.data); data['bindings'].pop(); variants.append(data)
        data = copy.deepcopy(self.data); data['bindings'].append(data['bindings'][0]); variants.append(data)
        for field, value in [('clips', ['unknown']), ('native_clip', 'wrong'),
                             ('state_name', 'other'), ('character', 'outsider'),
                             ('raw_delay', float('nan')), ('raw_volume', -1), ('clips', [])]:
            data = copy.deepcopy(self.data); data['bindings'][0][field] = value; variants.append(data)
        for data in variants:
            with self.subTest(bindings=data['bindings']):
                with self.assertRaises(ValueError):
                    self.validate(data)


class OrdinaryPack(unittest.TestCase):
    def test_requires_imported_ordinary_audio_resource_and_reports_count(self):
        p = load_module('verify_pck')
        with tempfile.TemporaryDirectory(dir=HERE) as directory:
            root = Path(directory); pack = root / 'fixture.pck'; report = root / 'report.json'
            path = 'assets/audio/native-ordinary/fixture.wav'
            manifest = {'files': [{'category': 'ordinary_audio_streams', 'path': path}], 'excluded_effect_source_json': []}
            names = {'project.binary': b'project', 'game.tscn': b'scene'}
            write_pack(pack, names)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertFalse(p.verify(pack, manifest, report))
            self.assertEqual(json.loads(report.read_text())['ordinary_audio_missing'], [path])
            names[path + '.import'] = b'[remap]\npath="res://.godot/imported/fixture.sample"\n'
            names['.godot/imported/fixture.sample'] = b'imported resource checked by runtime harness'
            write_pack(pack, names)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertTrue(p.verify(pack, manifest, report))
            self.assertEqual(json.loads(report.read_text())['ordinary_audio_resource_count'], 1)


class OrdinaryRuntimeGates(unittest.TestCase):
    def test_pins_skill_and_ordinary_audio_counts_and_rejects_issues(self):
        p = load_module('release_pipeline')
        base = dict(p.COUNTERS, passed=True, failures=[], failure_count=0,
                    audio_streams=43, ordinary_audio_streams=96, ordinary_audio_bindings=28,
                    ordinary_audio_issues=[], dependency_diagnostics=[])
        self.assertTrue(p.compare_runtime_reports(base, base, True)['passed'])
        for key, value in [('audio_streams', 40), ('ordinary_audio_streams', 91),
                           ('ordinary_audio_bindings', 25), ('ordinary_audio_scheduled', 25),
                           ('ordinary_audio_issues', ['missing_ordinary_clip'])]:
            with self.subTest(key=key):
                bad = dict(base, **{key: value})
                self.assertFalse(p.compare_runtime_reports(bad, bad, True)['passed'])
                self.assertFalse(p.compare_runtime_reports(base, bad, True)['passed'])

    def test_rejects_changed_deterministic_source_pack_choices(self):
        p = load_module('release_pipeline')
        base = dict(p.COUNTERS, passed=True, failures=[], failure_count=0,
                    ordinary_audio_issues=[], ordinary_audio_choices=[{'clip_name': 'first'}])
        changed = dict(base, ordinary_audio_choices=[{'clip_name': 'second'}])
        self.assertFalse(p.compare_runtime_reports(base, changed, True)['passed'])


if __name__ == '__main__':
    unittest.main()
