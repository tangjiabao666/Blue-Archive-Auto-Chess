from pathlib import Path
import hashlib,re,unittest
from asuna_source_boundary import FIXTURE,reverse_asuna_core
ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'core/character_sim.gd').read_text()
class AsunaCoreBoundary(unittest.TestCase):
 def test_complete_original_bytes(self):
  self.assertEqual(hashlib.sha256(reverse_asuna_core(SOURCE).encode()).hexdigest(),FIXTURE['baseline_sha256'])
 def test_missing_duplicate_and_altered_seams_rejected(self):
  for index,row in enumerate(FIXTURE['seams']):
   for replacement in ['',row['after']*2,row['after']+'# mutation\n']:
    with self.subTest(seam=index,replacement_length=len(replacement)):
     with self.assertRaises(AssertionError):reverse_asuna_core(SOURCE.replace(row['after'],replacement,1))
 def test_every_method_mutation_detected(self):
  for match in re.finditer(r'^func (\w+)\([^\n]*\n',SOURCE,re.M):
   with self.subTest(method=match.group(1)):
    altered=SOURCE[:match.end()]+'\t# unapproved body mutation\n'+SOURCE[match.end():]
    with self.assertRaises(AssertionError):reverse_asuna_core(altered)
if __name__=='__main__':unittest.main()
