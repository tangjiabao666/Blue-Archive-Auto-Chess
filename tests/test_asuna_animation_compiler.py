import hashlib
import json
import importlib.util
import tempfile
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/characters/asuna/asuna.glb'
PIN='a874892d8fe4fe952fe4ac0256797c73d82efa432f00eceb3e7e030375c5df07'
class CompilerInput(unittest.TestCase):
 def module(self):
  path=ROOT/'tools/asuna_animation/prepare.py'
  self.assertTrue(path.is_file(),'offline compiler preparation implementation is missing')
  spec=importlib.util.spec_from_file_location('asuna_prepare',path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
 def test_reject_missing_and_changed_source(self):
  m=self.module()
  with self.assertRaises((ValueError,FileNotFoundError)):m.build_payload(Path('/missing/asuna.glb'),PIN)
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'changed.glb';p.write_bytes(b'not the approved source')
   with self.assertRaisesRegex(ValueError,'SHA256'):m.build_payload(p,PIN)
 def test_exact_death_and_original_source_preservation(self):
  m=self.module();g=m.GLB(SOURCE.read_bytes());p=m.build_payload(SOURCE,PIN)
  self.assertEqual(g.doc['animations'][-1]['name'],'Asuna_Original_Vital_Death')
  d=p['clips']['Asuna_Original_Vital_Death']
  self.assertEqual(len(d['channels']),359)
  self.assertEqual(sum(len(t['times']) for t in d['channels'].values()),29394)
  self.assertEqual(d['length'],1.9666668176651)
  self.assertEqual(d['extras']['unity_animation']['cab'],'CAB-e86637465a6b8ff9c95be65f772c0813')
  self.assertEqual(d['extras']['unity_animation']['path_id'],'1009064993132161451')
  def digest(v):return hashlib.sha256(json.dumps(v,sort_keys=True,separators=(',',':')).encode()).hexdigest()
  self.assertEqual(digest(g.doc['animations'][:11]),'f9d28de605ac744557ff40a4040b8c75c757103b6461c64e506da6b81c76ec28')
  self.assertEqual(digest(g.doc['accessors'][:3050]),'202e3c54495935694907608c19f8644ca71ac5782eae6e5b3085a9dbccb0d0cd')
  self.assertEqual(digest(g.doc['bufferViews'][:3065]),'bd77d4ebbdb49802251b6082916b3ea5bc4a49e1380c0432254d7e41ef330645')
  self.assertEqual(hashlib.sha256(g.blob[:6239652]).hexdigest(),'90d292d65dad767f591e61ed1971b377ea72d2d61ccf23406b6c7987d0738377')
  for field,expected in {
   'nodes':'27695ecf1435e230e9890b64b5244ae19d592d3e1797380330695cf32db81b0a',
   'meshes':'3dcdd3514bbf59212629c2d194d6bf4f27f3f01da6f8a3a5b204df8fb4b460ef',
   'skins':'36cb6237ca5a08f8e9186fba7317270cd1139c563411d8cb7ea154323f092e73',
   'materials':'1f2eced8f70fe1de153999b31011c97880afb847f205939e80e754d25f8652e7',
  }.items():self.assertEqual(digest(g.doc[field]),expected,field+' preserved')
 def test_prepared_payload_is_bound_to_pinned_source(self):
  m=self.module()
  self.assertTrue(hasattr(m,'payload_bytes'),'prepared input must be authenticated before native compilation')
  payload=m.build_payload(SOURCE,PIN);encoded=m.payload_bytes(payload)
  self.assertEqual(hashlib.sha256(encoded).hexdigest(),m.PINNED_PAYLOAD)
  compiler=(ROOT/'tools/asuna_animation/compile.gd').read_text()
  self.assertIn('const PAYLOAD_SHA="'+m.PINNED_PAYLOAD+'"',compiler)
  channel=next(iter(next(iter(payload['clips'].values()))['channels'].values()))
  channel['values'][len(channel['values'])//3][0]+=0.03125
  with self.assertRaisesRegex(ValueError,'payload SHA256'):m.payload_bytes(payload)
 def test_preserves_source_keys_and_separate_root_identities(self):
  m=self.module();p=m.build_payload(SOURCE,PIN)
  self.assertEqual(p['source_glb_sha256'],PIN);self.assertEqual(len(p['clips']),12)
  self.assertEqual(sum(len(t['times']) for c in p['clips'].values() for t in c['channels'].values()),302315)
  self.assertEqual(sum(len(c['channels']) for c in p['clips'].values()),4340)
  self.assertEqual(p['clips']['Asuna_Original_Exs_Root__RootMotion']['extras']['unity_animation']['path_id'],'-3736668486879208201')
  self.assertEqual(p['clips']['Asuna_Original_Exs_Root__Animation']['extras']['unity_animation']['path_id'],'4607550408865671297')
  for clip in p['clips'].values():
   for channel in clip['channels'].values():
    self.assertEqual(channel['times'][0],0)
    self.assertEqual(channel['times'][-1],clip['length'])
    self.assertTrue(all(a<b for a,b in zip(channel['times'],channel['times'][1:])))
if __name__=='__main__':unittest.main()
