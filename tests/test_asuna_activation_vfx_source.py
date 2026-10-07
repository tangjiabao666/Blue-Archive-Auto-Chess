from pathlib import Path
import copy,gzip,hashlib,json,unittest
ROOT=Path(__file__).resolve().parents[1]
def load(p):return json.loads(p.read_bytes())
def sha(b):return hashlib.sha256(b).hexdigest()
class AsunaLiveVFXSource(unittest.TestCase):
 def test_exact_private_source_preserved(self):
  self.assertEqual(sha((ROOT/'data/effects/asuna/battle-events-compact.json').read_bytes()),'cb4b5bebf755936d98a1e3325022e9155e1ce96c6f1590bc8153038e8e0ad17e')
  self.assertEqual(sha((ROOT/'data/effects/asuna/asuna/visual-templates.json').read_bytes()),'1413c29e604e019abdf8c2effd48243d41e3a214e5fdfe51eb0440516070e541')
 def test_exact_additive_global_timeline(self):
  old=gzip.decompress((ROOT/'tests/fixtures/asuna_activation/inactive-global-effects.json.gz').read_bytes())
  self.assertEqual(sha(old),'6194d68e488c32beda5156c028431382c6b0a662ef473663de52563008f75208')
  current=load(ROOT/'data/effects/battle-events-compact.json');baseline=json.loads(old)
  self.assertEqual(current['activeRoster'],baseline['activeRoster']+['asuna'])
  private=load(ROOT/'data/effects/asuna/battle-events-compact.json');expected=copy.deepcopy(private['characters']['asuna']);expected['active']=True
  for timeline in expected['timelines']:
   for event in timeline['events']:
    if 'active' in event:event['active']=True
  self.assertEqual(current['characters']['asuna'],expected)
  self.assertEqual(current['asunaActivationProvenance']['rebasedResourceReferences'],56)
  self.assertEqual(current['asunaActivationProvenance']['newResourceCopies'],0)
  del current['characters']['asuna'];current['activeRoster'].pop();del current['asunaActivationProvenance']
  self.assertEqual(json.dumps(current,ensure_ascii=False,indent=2).encode(),old)
 def test_only_reviewed_template_relocations_and_render_policy(self):
  raw=(ROOT/'data/effects/asuna/visual-templates.json').read_bytes()
  self.assertEqual(sha(raw),'cc6ad656f8d6ea4856b36a57dfb4a14b4d2cef6b5142fdf100efbde048c7d013')
  data=json.loads(raw);self.assertIs(data['active'],True);self.assertIs(data['fixtureOnly'],False)
  self.assertEqual(data.pop('renderAdaptations'),{'asunaMuzzleLineVelocityOrientation':True})
  data['active']=False;data['fixtureOnly']=True
  receipt=load(ROOT/'evidence/asuna-activation/vfx-relocation-receipt.json')
  self.assertEqual(receipt['resourcesCopied'],0);self.assertEqual(len(receipt['rebasedPaths']),56)
  for row in receipt['rebasedPaths']:
   value=data
   for key in row['jsonPath'][:-1]:value=value[key]
   self.assertEqual(value[row['jsonPath'][-1]],row['after'])
   self.assertEqual((ROOT/'data/effects'/row['after']).read_bytes(),(ROOT/'data/effects/asuna'/row['before']).read_bytes())
   value[row['jsonPath'][-1]]=row['before']
  self.assertEqual((json.dumps(data,ensure_ascii=False,indent=2)+'\n').encode(),(ROOT/'data/effects/asuna/asuna/visual-templates.json').read_bytes())
if __name__=='__main__':unittest.main()
