"""Offline source-byte, inactive-roster and reproducible packet boundary checks."""
from pathlib import Path
import hashlib,json,unittest,zipfile
ROOT=Path(__file__).resolve().parents[1]
P=ROOT/'data/effects/asuna'
E=ROOT/'evidence/asuna-effect-packet'
def read(p):return json.loads(p.read_text())
def sha(b):return hashlib.sha256(b).hexdigest()
class AsunaEffectSource(unittest.TestCase):
 def test_runtime_packet_bytes_match_verified_source_receipt(self):
  receipt=read(E/'merge-receipt.json')
  for row in receipt['runtimeFiles']:
   with self.subTest(path=row['path']):
    data=(P/row['path']).read_bytes()
    self.assertEqual(len(data),row['bytes']);self.assertEqual(sha(data),row['sha256'])
 def test_original_source_archive_member_bytes(self):
  receipt=read(E/'merge-receipt.json');raw=(E/'source-packets.zip').read_bytes()
  self.assertEqual(sha(raw),receipt['archiveSha256'])
  with zipfile.ZipFile(E/'source-packets.zip') as z:
   self.assertIsNone(z.testzip())
   for row in receipt['archiveFiles']:
    with self.subTest(path=row['path']):
     data=z.read(row['path']);self.assertEqual(len(data),row['bytes']);self.assertEqual(sha(data),row['sha256'])
 def test_private_fixture_never_activates_roster(self):
  d=read(P/'battle-events-compact.json')
  self.assertIs(d['active'],False);self.assertIs(d['fixtureOnly'],True)
  self.assertEqual(d['activeRoster'],[]);self.assertEqual(d['fixtureCharacters'],['asuna'])
  self.assertEqual(read(ROOT/'data/effects/battle-events-compact.json')['activeRoster'][-1],'asuna')
 def test_exact_source_timing_and_identity(self):
  d=read(P/'effect-events.json')['events']
  self.assertEqual(len(d),5)
  self.assertEqual([(e['start'],e['duration'],e['particleRandomSeed']) for e in d],[(.4,1.6,2648),(.6,2.0333333333333337,7554),(1.8666666666666667,1.9333333333333331,1536),(.5333333333333333,2.4333333333333336,9751),(0.,1.,7390)])
  self.assertEqual(d[3]['asset']['name'],'FX_Public_AR_Motion_Shot_Asuna')
  self.assertEqual(d[3]['asset']['pathId'],'-8415816298001506071')
  self.assertEqual(d[3]['label'],'FX_Public_AR_Motion_Shot_1')
if __name__=='__main__':unittest.main()
