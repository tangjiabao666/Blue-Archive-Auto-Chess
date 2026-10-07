"""Exact source identity and ActivationPlayableAsset exporter regressions.

Source exporter tests require the recovered sibling roster-expansion workspace;
portable profile/GLB assertions always run. No exporter writes or source edits.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import unittest

PROJECT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT.parents[1] / 'roster-expansion'
TL = 'CAB-bb0721e2c19c90d0299d1c15d3fadcfb'
CHAR = 'CAB-e6b061afc0b52f8cae893aa90b21ca7c'
TRACK = 1670628901941442682
ASSET = 3324964349370857594
TARGET = 1619454327237531117
DIRECTOR = 269069558178665965


class MutsukiActivationData(unittest.TestCase):
    def test_original_glb_bytes_and_separate_mesh_identity(self):
        data = (PROJECT / 'assets/characters/mutsuki/mutsuki.glb').read_bytes()
        self.assertEqual(hashlib.sha256(data).hexdigest(), 'bdd2b2f8bc78dcdb9d406d31e3321d0148c9898a79f72f37f93729f5cc91b5c1')
        gltf = json.loads(data[20:20 + struct.unpack_from('<I', data, 12)[0]])
        bag = gltf['nodes'][107]
        self.assertEqual(bag['name'], 'Mutsuki_Original_Bomb_Weapon')
        self.assertEqual(bag['extras']['unity_path_id'], '-8594057346837555731')
        self.assertTrue(bag['extras']['unity_active'])
        self.assertTrue(bag['extras']['unity_renderer_enabled'])
        self.assertEqual((bag['mesh'], bag['skin']), (1, 1))
        self.assertEqual(len({gltf['nodes'][i]['mesh'] for i in (106, 107, 108)}), 3)
        self.assertEqual(len({gltf['nodes'][i]['skin'] for i in (106, 107, 108)}), 3)

    def test_only_exact_ex_track_enters_presentation(self):
        p = json.loads((PROJECT / 'data/character-presentations.json').read_text())['mutsuki']
        windows = p.get('activation_windows', {})
        self.assertEqual(set(windows), {'ex'})
        self.assertEqual(len(windows['ex']), 1)
        row = windows['ex'][0]
        self.assertEqual(row['node'], 'Mutsuki_Original_Bomb_Weapon')
        self.assertEqual(row['source_track'], f'{TL}/{TRACK}')
        self.assertEqual(row['source_target'], f'{CHAR}/{TARGET}')
        self.assertEqual(row['source_transform'], f'{CHAR}/-8594057346837555731')
        self.assertEqual(row['post_playback'], 'leave_as_is')
        self.assertEqual(row['post_playback_enum'], 3)
        self.assertEqual(row['start'], 0)
        self.assertEqual(row['duration'], 68 / 30)
        self.assertEqual(p['initial_hidden_nodes'], [])
        self.assertNotIn('renderer_visibility', p)

    def test_compact_event_retains_exact_binding_and_mode(self):
        compact = json.loads((PROJECT / 'data/effects/battle-events-compact.json').read_text())
        timeline = next(t for t in compact['characters']['mutsuki']['timelines'] if t['name'] == 'Mutsuki_Original_EX1')
        event = next(e for e in timeline['events'] if e.get('sourceClipAsset', {}).get('pathId') == str(ASSET))
        self.assertEqual(event['kind'], 'activation')
        self.assertEqual(event['sourceTrack']['cab'], TL)
        self.assertEqual(event['sourceTrack']['pathId'], str(TRACK))
        self.assertEqual(event['postPlayback'], 3)
        self.assertTrue(event['combatEligible'])
        self.assertEqual(event['bindings'][0]['target']['cab'], CHAR)
        self.assertEqual(event['bindings'][0]['target']['pathId'], str(TARGET))
        self.assertEqual(event['bindings'][0]['hierarchy'], 'Mutsuki_Original/Mutsuki_Original_Bomb_Weapon')


@unittest.skipUnless((SOURCE / 'tools/export_native_effects.py').exists(), 'recovered source exporter workspace not present')
class MutsukiActivationExporter(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location('native_activation_exporter', SOURCE / 'tools/export_native_effects.py')
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)
        proof = json.loads((SOURCE / 'visibility-investigation/mutsuki-activation-proof.json').read_text())
        cls.proof = proof
        files = [SOURCE / 'bundles' / row['bundle'] for row in proof['source_receipts']]
        env = cls.module.UnityPy.load(*map(str, files))
        cls.objects = {(o.assets_file.name, o.path_id): o for o in env.objects}
        cls.bundle = {o.assets_file.name: path.name for path in files for o in cls.module.UnityPy.load(str(path)).objects}

    def setUp(self):
        n = self.module.Native.__new__(self.module.Native)
        n.objects = self.objects; n.bundle = self.bundle; n.cache = {}; n.exported = {}; n.missing = {}; n.go_transforms = {}
        for o in n.objects.values():
            if o.type.name == 'Transform':
                go = n.resolve(o, n.tree(o)['m_GameObject'])
                if go: n.go_transforms[n.key(go)] = o
        # Resource copying is a write-only export side effect; preserve references,
        # but suppress all writes during this read-only source assertion test.
        n.resource = lambda o: n.ref(o) if o else None
        self.native = n

    def exported_event(self):
        timelines, _ = self.native.timelines('mutsuki')
        timeline = next(t for t in timelines if t['source']['pathId'] == '-782925957908891526')
        return next(e for e in timeline['events'] if e['sourceClipAsset'] and e['sourceClipAsset']['pathId'] == str(ASSET))

    def tree(self, cab, pid):
        return self.native.tree(self.native.objects[cab, pid])

    def test_actual_source_activation_exports_director_binding(self):
        e = self.exported_event()
        self.assertEqual(e['kind'], 'activation')
        self.assertEqual(e['postPlayback'], 3)
        self.assertEqual(e['sourceTrack']['pathId'], str(TRACK))
        self.assertEqual(e['duration'], 68 / 30)
        self.assertEqual(e['bindings'][0]['target']['pathId'], str(TARGET))
        self.assertEqual(e['bindings'][0]['director']['pathId'], str(DIRECTOR))
        self.assertTrue(e['combatEligible'])

    def test_wrong_cab_or_path_id_does_not_forge_binding(self):
        for cab, pid in [('CAB-wrong', TRACK), (TL, TRACK + 1)]:
            with self.subTest(cab=cab, pid=pid):
                self.setUp()
                original = self.native.pointer_key
                self.native.pointer_key = lambda obj, ptr: (cab, pid) if obj.path_id == DIRECTOR and int(ptr.get('m_PathID', 0)) == TRACK else original(obj, ptr)
                e = self.exported_event()
                self.assertEqual(e['bindings'], [])
                self.assertFalse(e.get('combatEligible', True))

    def test_unbound_and_non_gameobject_targets_inactive(self):
        for replacement in [0, 5481615084395451885]:
            with self.subTest(target=replacement):
                self.setUp()
                tree = self.tree(CHAR, DIRECTOR)
                for binding in tree['m_SceneBindings']:
                    if binding['key']['m_PathID'] == TRACK: binding['value']['m_PathID'] = replacement
                self.assertFalse(self.exported_event().get('combatEligible', True))

    def test_cutin_and_muted_activation_never_combat_eligible(self):
        for change in ['cutin', 'muted']:
            with self.subTest(change=change):
                self.setUp()
                if change == 'cutin': self.tree(TL, -782925957908891526)['m_Name'] = 'Mutsuki_Original_EX1_CutIn'
                else: self.tree(TL, TRACK)['m_Muted'] = 1
                self.assertFalse(self.exported_event().get('combatEligible', True))

    def test_activation_not_control_and_requires_track_mode(self):
        for change in ['control', 'missing_mode']:
            with self.subTest(change=change):
                self.setUp()
                if change == 'control': self.tree(TL, ASSET)['m_Name'] = 'ControlPlayableAsset'
                else: self.tree(TL, TRACK).pop('m_PostPlaybackState')
                self.assertEqual(self.exported_event()['kind'], 'unsupported')

    def test_post_playback_enum_is_preserved_without_relabeling(self):
        for mode in range(4):
            with self.subTest(mode=mode):
                self.setUp(); self.tree(TL, TRACK)['m_PostPlaybackState'] = mode
                self.assertEqual(self.exported_event().get('postPlayback'), mode)


if __name__ == '__main__': unittest.main()
