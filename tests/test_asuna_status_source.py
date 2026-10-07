"""Asuna-only presentation additions; source identity and old manifest rows are pinned."""
import gzip
import hashlib
import json
from pathlib import Path
import unittest
from asuna_activation_boundary import reverse_activation
ROOT = Path(__file__).resolve().parents[1]
PIN = '6f4d5bbaf93c9987bd2c1cff91581337765a1f21'
class AsunaStatusSource(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base = json.loads((ROOT/'tests/fixtures/asuna_status/baseline.json').read_text())
        cls.manifest = json.loads((ROOT/'data/skill-icons.json').read_text())
        cls.data = json.loads((ROOT/'data/character_skills.json').read_text())
        cls.asuna = next(c for c in cls.data['characters'] if c['key']=='asuna')
        raw_bytes = gzip.decompress((ROOT/'evidence/asuna-source-kit/students-6f4d5bb.json.gz').read_bytes())
        assert hashlib.sha256(raw_bytes).hexdigest() == '3e8ccddcf8dbfbd1eaadbe407c56e45a295f46b462ef715b26e4b9718a15c272'
        cls.raw = next(c for c in json.loads(raw_bytes) if c['Id']==16001)
    def test_three_bindings_match_raw_and_normalized_source(self):
        raw={s['SkillType']:s for s in self.raw['Skills']}
        expected={slot:'skill/'+raw[source]['Icon'] for slot,source in [('ex','ex'),('basic','normal'),('sub','sub')]}
        self.assertEqual(self.manifest['characters'].get('asuna'),expected)
        for source in ['ex','normal','sub']:self.assertEqual(raw[source],self.asuna['sourceSkills'][source])
    def test_existing_manifest_rows_are_preserved(self):
        before=self.base['manifest'];after=self.manifest
        for key,row in before['characters'].items():self.assertEqual(after['characters'][key],row,key)
        for key,row in before['assets'].items():self.assertEqual(after['assets'][key],row,key)
        self.assertEqual(set(after['characters'])-set(before['characters']),{'asuna'})
        self.assertEqual(set(after['assets'])-set(before['assets']),{'skill/COMMON_SKILLICON_EVASION','buff/Buff_Dodge'})
        self.assertEqual(after['source'],before['source'])
        self.assertEqual(after['statusSemanticMap'],before['statusSemanticMap'])
    def test_new_images_match_verified_historical_git_blobs(self):
        expected={'skill/COMMON_SKILLICON_EVASION':'a8f194c058c91c29b8273ccda3f48c7ef01153ea','buff/Buff_Dodge':'feaa04326692cc0e788352294741ea4ae8981ff6'}
        for key,sha in expected.items():
            row=self.manifest['assets'][key]
            raw=(ROOT/row['path'].removeprefix('res://')).read_bytes()
            self.assertEqual(row['sourceUrl'],f'https://github.com/SchaleDB/SchaleDB/blob/{PIN}/images/{key}.webp')
            self.assertEqual(row['gitBlobSha'],sha)
            self.assertEqual(hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest(),sha)
    def test_dash_buff_glyph_has_explicit_asuna_scope_and_source_evidence(self):
        self.assertIn('<b:Dodge>',self.asuna['sourceSkills']['ex']['Desc'])
        row=self.manifest.get('statusEffectMap',{}).get('asuna_ex_dash_evasion',{})
        self.assertEqual(row.get('assetKey'),'buff/Buff_Dodge')
        self.assertEqual(row.get('stat'),'DodgePoint')
        self.assertIn('Id=16001',str(row.get('evidence',[])))
    def test_only_asuna_hint_is_added(self):
        source=(ROOT/'scripts/game_app.gd').read_text()
        hints=json.loads(source.split('func _character_hint(key:String)->String:\n\treturn ',1)[1].split('.get(key,"")',1)[0])
        self.assertEqual({k:v for k,v in hints.items() if k!='asuna'},self.base['hints'])
        self.assertEqual(set(hints)-set(self.base['hints']),{'asuna'})
        for phrase in ['20 秒','11 连射','EX：','57.37%','38.31%','30 秒','43.41%','仅冲刺位移期间']:
            self.assertIn(phrase,hints.get('asuna',''))
    def test_combat_data_roster_and_source_fields_unchanged(self):
        self.assertEqual(hashlib.sha256(reverse_activation((ROOT/'data/character_skills.json').read_bytes())).hexdigest(),self.base['characterSkillsSha256'])
        self.assertEqual(len(self.data['active_roster']),14)
        self.assertEqual(self.data['active_roster'][-1],'asuna')
        self.assertEqual(self.data['pending_native_roster'],[])
if __name__=='__main__':unittest.main()
