from pathlib import Path
import json,hashlib,unittest
from asuna_activation_boundary import activate,reverse_activation
ROOT=Path(__file__).resolve().parents[1]
import gzip
BASE=gzip.decompress((ROOT/'tests/fixtures/asuna_activation/inactive-character-skills.json.gz').read_bytes())
class DataActivation(unittest.TestCase):
 def test_exact_bookkeeping_only(self):
  raw=activate(BASE);d=json.loads(raw);old=json.loads(BASE)
  self.assertEqual(raw,(ROOT/'data/character_skills.json').read_bytes())
  self.assertEqual(d['active_roster'],old['active_roster']+['asuna'])
  self.assertEqual(d['activeRosterCount'],14);self.assertEqual(d['pending_native_roster'],[])
  self.assertEqual(d['characters'],old['characters']);self.assertEqual(d['runtimeSourceFrames'],old['runtimeSourceFrames'])
  self.assertEqual(reverse_activation(raw),BASE)
 def test_rejects_unapproved_mutations(self):
  raw=activate(BASE)
  for label in ['duplicate','reorder','count','floatcount','pending','oldstat','asunaratio','extra','note']:
   d=json.loads(raw)
   if label=='duplicate':d['active_roster'].append('asuna')
   if label=='reorder':d['active_roster'][0],d['active_roster'][-1]=d['active_roster'][-1],d['active_roster'][0]
   if label=='count':d['activeRosterCount']=13
   if label=='floatcount':d['activeRosterCount']=14.0
   if label=='pending':d['pending_native_roster']=['asuna']
   if label=='oldstat':d['characters'][0]['statsLevel50ThreeStar']['MaxHP']+=1
   if label=='asunaratio':d['characters'][-1]['basic']['damage']['totalAtkRatio']=4.2
   if label=='extra':d['extra']=True
   if label=='note':d['rosterNote']='unreviewed'
   with self.subTest(label=label),self.assertRaises(AssertionError):reverse_activation((json.dumps(d,ensure_ascii=False,indent=2)+'\n').encode())
 def test_rejects_duplicate_json_and_repeat_activation(self):
  raw=activate(BASE)
  with self.assertRaises(AssertionError):activate(raw)
  with self.assertRaises(AssertionError):reverse_activation(raw.replace(b'"activeRosterCount": 14',b'"activeRosterCount": 99, "activeRosterCount": 14'))
if __name__=='__main__':unittest.main()
