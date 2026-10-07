import copy,json,unittest
from pathlib import Path
from asuna_audio_activation_boundary import validate,strict_json
ROOT=Path(__file__).resolve().parents[1]
class ActivationBoundary(unittest.TestCase):
 def setUp(self):
  self.o=strict_json((ROOT/'data/audio/native-ordinary-sfx.json').read_bytes());self.s=strict_json((ROOT/'data/audio/native-skill-sfx.json').read_bytes())
 def test_exact_activation_inverse_and_all_waveforms(self):
  result=validate(self.o,self.s,ROOT);self.assertTrue(result['old_manifest_byte_inverse'])
 def reject(self,change):
  o=copy.deepcopy(self.o);s=copy.deepcopy(self.s);before=json.dumps([o,s],sort_keys=True);change(o,s);self.assertTrue(before!=json.dumps([o,s],sort_keys=True),'mutation must change input')
  with self.assertRaises(ValueError):validate(o,s)
 def test_original_row_corruption_rejected(self):self.reject(lambda o,s:o['bindings'][0].__setitem__('raw_volume',0.123))
 def test_original_asset_corruption_rejected(self):self.reject(lambda o,s:o['assets']['SFX_Common_AR_01'].__setitem__('wav_sha256','0'*64))
 def test_original_skill_corruption_rejected(self):self.reject(lambda o,s:s['records'][0].__setitem__('startSeconds',99))
 def test_source_metadata_mutation_rejected(self):self.reject(lambda o,s:o['source'].__setitem__('historical_numeric_or_visual_equivalence_verified',True))
 def test_adapter_mutation_rejected(self):self.reject(lambda o,s:o['adapter'].__setitem__('pitch_scale',0.9))
 def test_count_float_rejected(self):self.reject(lambda o,s:s['counts'].__setitem__('rows',48.0))
 def test_count_wrong_rejected(self):self.reject(lambda o,s:s['counts'].__setitem__('uniqueWAVs',44))
 def test_appended_rows_order_rejected(self):self.reject(lambda o,s:o['bindings'].__setitem__(slice(-2,None),list(reversed(o['bindings'][-2:]))))
 def test_appended_pool_order_rejected(self):self.reject(lambda o,s:o['bindings'][-2]['clips'].reverse())
 def test_duplicate_state_rejected(self):self.reject(lambda o,s:o['bindings'].append(copy.deepcopy(o['bindings'][-1])))
 def test_unknown_top_level_rejected(self):self.reject(lambda o,s:o.__setitem__('guess',True))
 def test_wrong_native_clip_rejected(self):self.reject(lambda o,s:o['bindings'][-1].__setitem__('native_clip','wrong'))
 def test_source_pitch_change_rejected(self):self.reject(lambda o,s:s['records'][-1].__setitem__('pitch',1.0))
 def test_ex_deactivation_rejected(self):self.reject(lambda o,s:s['records'][-1].__setitem__('currentSimSelectable',False))
 def test_basic_promotion_rejected(self):self.reject(lambda o,s:s['records'][-1].__setitem__('timelineKind','basic'))
 def test_early_track_stop_rejected(self):self.reject(lambda o,s:s['records'][-1].__setitem__('wavDurationSeconds',0.866666667))
 def test_duplicate_json_key_rejected(self):
  with self.assertRaises(ValueError):strict_json('{"assets":{},"assets":{}}')
if __name__=='__main__':unittest.main()
