"""Official PCM provenance and source-state binding integrity, independent of Godot."""
import hashlib
import json
from pathlib import Path
import unittest
import wave
from asuna_audio_activation_boundary import validate, fixture, OLD_13_ROWS_SHA
ROOT=Path(__file__).resolve().parents[1]
class OrdinaryAudioAssets(unittest.TestCase):
 def test_official_waveforms_and_bindings(self):
  path=ROOT/'data/audio/native-ordinary-sfx.json'
  self.assertTrue(path.exists(),'ordinary source manifest exists')
  data=json.loads(path.read_text())
  self.assertEqual(data['source']['container_sha256'],'4fa5eb323d8d859a5afedf4044c1c8f9bcebbbdc880d91fcf44fdab95c7683c2')
  self.assertEqual(len(data['assets']),96)
  self.assertEqual(len(data['bindings']),28)
  validate(data,json.loads((ROOT/'data/audio/native-skill-sfx.json').read_text()),ROOT)
  # All26 rows independently compared to pinned AudioAnimator source before this digest was frozen.
  rows=sorted([r for r in data['bindings'] if r['character']!='asuna'],key=lambda r:r['binding_id'])
  self.assertEqual(len(rows),26,'retain exact original thirteen-character rows')
  self.assertEqual(hashlib.sha256(json.dumps(rows,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest(),'fbdc597411aa331e479b93946bd0e909b31d76c000823486a46955ef9ba65de1')
  profiles=json.loads((ROOT/'data/character-presentations.json').read_text())
  for key,row in data['assets'].items():
   file=ROOT/row['path'].removeprefix('res://')
   self.assertEqual(hashlib.sha256(file.read_bytes()).hexdigest(),row['wav_sha256'],key)
   settings=file.with_suffix(file.suffix+'.import').read_text()
   for required in ['compress/mode=0','edit/normalize=false','edit/trim=false','force/8_bit=false','force/max_rate=false','edit/loop_mode=0']:self.assertIn(required,settings,key)
   with wave.open(str(file),'rb') as w:
    self.assertEqual((w.getnchannels(),w.getframerate(),w.getsampwidth()),(1,22050,2),key)
    self.assertEqual(w.getnframes(),row['frames'],key)
    self.assertEqual(hashlib.sha256(w.readframes(w.getnframes())).hexdigest(),row['pcm_sha256'],key)
  seen=set()
  for row in data['bindings']:
   identity=(row['character'],row['state_name']);self.assertNotIn(identity,seen);seen.add(identity)
   slot={'Base Layer.Normal.AttackIng':'attack_fire','Base Layer.Normal.Reload':'reload'}[row['state_name']]
   self.assertEqual(row['native_clip'],profiles[row['character']]['clips'][slot])
   self.assertTrue(row['clips'])
   for key in row['clips']:self.assertIn(key,data['assets'])
   self.assertGreaterEqual(row['raw_delay'],0)
   self.assertGreaterEqual(row['raw_volume'],0)
   self.assertLessEqual(row['raw_volume'],1)
  self.assertEqual(len({x[0] for x in seen}),14)
  self.assertEqual(data['adapter']['pitch_scale'],1.0)
  self.assertFalse(data['adapter']['native_playback_parity_claimed'])
if __name__=='__main__':unittest.main()
