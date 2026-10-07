"""Error-sensitive, source-preserving Shiroko drone regression.

Run: python -m unittest discover -s tests -p test_native_drone_pose.py -v
Only the explicit raw AnimationPlayer reference subprocess may report the known
zero-rest errors. A zero Godot exit status alone does not pass the runtime test.
"""
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / 'assets/skill_props/shiroko_drone/shiroko_drone.glb'
SOURCE_SHA256 = 'ef286a557c29c712d596d80de72eb9eac653bc91c04be9bdbca248b57d67ed58'


class NativeDronePoseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='native-drone-pose-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.directory = Path(cls.temp.name)
        cls.env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING='1')
        for variable in ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
            location = cls.directory / variable
            location.mkdir()
            cls.env[variable] = str(location)
        cls.godot = os.environ.get('GODOT_BIN') or shutil.which('godot') or shutil.which('godot4')
        if not cls.godot:
            raise unittest.SkipTest('Godot executable is required for native pose regression')
        cls.runs = {}
        for mode in ('reference', 'runtime'):
            destination = cls.directory / (mode + '.json')
            args = [cls.godot, '--headless', '--path', str(ROOT), '--script',
                    'tests/native_drone_pose_probe.gd', '--', '--output', str(destination)]
            if mode == 'reference':
                args.append('--reference')
            run = subprocess.run(args, capture_output=True, text=True, env=cls.env, timeout=90)
            cls.runs[mode] = (run, json.loads(destination.read_text()) if destination.exists() else None)

    def test_source_bytes_and_nonconstant_zero_rest_tracks(self):
        raw = MODEL.read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(), SOURCE_SHA256)
        size = struct.unpack_from('<I', raw, 12)[0]
        gltf = json.loads(raw[20:20 + size])
        binary = raw[28 + size:]
        wing_nodes = [i for i, node in enumerate(gltf['nodes']) if node.get('name', '').endswith('wingB')]
        self.assertEqual(len(wing_nodes), 2)
        self.assertEqual(gltf['skins'][1]['joints'], wing_nodes,
                         'both zero-rest bones skin the visible alpha rotor geometry')
        for node in wing_nodes:
            self.assertEqual(gltf['nodes'][node]['scale'], [0.0, 0.0, 0.0])
            animation = gltf['animations'][0]
            channel = next(c for c in animation['channels']
                           if c['target'] == {'node': node, 'path': 'scale'})
            sampler = animation['samplers'][channel['sampler']]
            accessor = gltf['accessors'][sampler['output']]
            view = gltf['bufferViews'][accessor['bufferView']]
            offset = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
            values = [struct.unpack_from('<fff', binary, offset + i * view.get('byteStride', 12))
                      for i in range(accessor['count'])]
            self.assertEqual(values[0], (0.0, 0.0, 0.0))
            self.assertEqual(values[-1], (1.0, 1.0, 1.0))
            self.assertTrue(any(0.0 < value[0] < 1.0 for value in values),
                            'visible transition must be retained, not skipped as a hidden track')

    def test_raw_reference_reproduces_two_first_seek_errors(self):
        run, data = self.runs['reference']
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIsNotNone(data, run.stdout + run.stderr)
        # This count is diagnostic evidence for Godot 4.6.3, not permission for
        # the production subprocess to emit errors. Permit an upstream engine fix.
        errors = [line for line in run.stderr.splitlines() if line.startswith('ERROR:')]
        self.assertIn(len(errors), (0, 2), run.stderr)
        self.assertTrue(all('Basis [X: (0.0, 0.0, 0.0)' in error for error in errors), run.stderr)
        print(f'DRONE_RAW_REFERENCE {len(errors)} expected zero-rest diagnostics')

    def test_runtime_has_no_engine_errors_and_passes_lifecycle_checks(self):
        run, data = self.runs['runtime']
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIsNotNone(data, run.stdout + run.stderr)
        self.assertNotIn('ERROR:', run.stderr, 'Runtime errors fail even when Godot exits 0:\n' + run.stderr)
        self.assertNotIn('SCRIPT ERROR:', run.stdout + run.stderr)
        self.assertIn('0 failures', run.stdout)
        print(run.stdout.strip().splitlines()[-1] + '; 0 runtime errors')

    def test_all_bones_skin_palettes_vertices_and_muzzle_match_native_player(self):
        reference = self.runs['reference'][1]
        runtime = self.runs['runtime'][1]
        self.assertIsNotNone(reference)
        self.assertIsNotNone(runtime)
        self.assertGreaterEqual(len(reference['samples']), 360)
        detailed_samples = [sample for sample in reference['samples']
                            if 'vertices' in sample['pose']['meshes']['Siroko_Dron']]
        self.assertGreaterEqual(len(detailed_samples), 40)
        for sample in detailed_samples:
            self.assertEqual(len(sample['pose']['meshes']['Siroko_Dron']['vertices']), 4439 * 3)
            self.assertEqual(len(sample['pose']['meshes']['Siroko_Dron_Wing']['vertices']), 36 * 3)
        max_difference = 0.0
        values_checked = 0

        def compare(a, b, path):
            nonlocal max_difference, values_checked
            if isinstance(a, dict):
                self.assertEqual(set(a), set(b), path)
                for key in a:
                    compare(a[key], b[key], path + '/' + key)
            elif isinstance(a, list):
                self.assertEqual(len(a), len(b), path)
                for index, (left, right) in enumerate(zip(a, b)):
                    compare(left, right, path + '/' + str(index))
            else:
                self.assertTrue(math.isfinite(a) and math.isfinite(b), path)
                difference = abs(a - b)
                max_difference = max(max_difference, difference)
                values_checked += 1
                self.assertLessEqual(difference, 0.00001, path)

        compare(reference, runtime, '')
        self.assertGreater(values_checked, 400000)
        print(f'DRONE_POSE_PARITY {len(reference["samples"])} poses; '
              f'{len(detailed_samples)} full 4475-vertex snapshots; '
              f'{values_checked} scalar values; max delta {max_difference:.9g}')


if __name__ == '__main__':
    unittest.main()
