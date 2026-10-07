"""Historical normal-target seams, after exactly reversing approved area-EX seams."""
import hashlib
import json
from pathlib import Path
import re
import unittest
from area_ex_source_boundary import reverse_area_ex
from asuna_source_boundary import reverse_asuna_core
from asuna_data_source_boundary import reverse_asuna_data
from asuna_activation_boundary import reverse_activation

ROOT = Path(__file__).resolve().parents[1]
BASE = json.loads((ROOT / 'tests/fixtures/normal_target/source_hashes.json').read_text())
# Preserve the original manifest and every historical assertion unchanged.
SOURCE = reverse_area_ex(reverse_asuna_core((ROOT / 'core/character_sim.gd').read_text()))
PARTS = re.split(r'(?=^func )', SOURCE, flags=re.M)
METHODS = {re.match(r'func (\w+)', part).group(1): part for part in PARTS[1:]}

def digest(text):
    return hashlib.sha256(text.strip().encode()).hexdigest()

class NormalTargetSourceBoundary(unittest.TestCase):
    def test_only_normal_target_method_added(self):
        self.assertEqual(set(METHODS) - set(BASE['methods_sha256']), {'_normal_target'})
        self.assertFalse(set(BASE['methods_sha256']) - set(METHODS))

    def test_all_unrelated_methods_are_byte_identical(self):
        for name, expected in BASE['methods_sha256'].items():
            if name not in {'configure', 'step'}:
                with self.subTest(method=name):
                    self.assertEqual(digest(METHODS[name]), expected)

    def test_step_has_only_one_normal_selector_call_changed(self):
        text = METHODS['step']
        self.assertEqual(text.count('var target=_normal_target(u)'), 1)
        self.assertEqual(digest(text.replace('var target=_normal_target(u)', 'var target=_target(u,u.range)')),
                         BASE['methods_sha256']['step'])

    def test_configure_changes_only_strict_validation_and_copy(self):
        addition = ('\tif not next_options.normal_target_policies is Array or next_options.normal_target_policies.size()!=2:return "invalid normal target policies"\n'
                    '\tfor policy in next_options.normal_target_policies:\n'
                    '\t\tif not policy is String or policy not in NORMAL_TARGET_POLICIES:return "invalid normal target policy"\n'
                    '\tnext_options.normal_target_policies=next_options.normal_target_policies.duplicate(true)\n')
        self.assertEqual(METHODS['configure'].count(addition), 1)
        self.assertEqual(digest(METHODS['configure'].replace(addition, '')), BASE['methods_sha256']['configure'])

    def test_no_other_constants_or_fields_changed(self):
        head = PARTS[0].replace('const NORMAL_TARGET_POLICIES := ["nearest", "wounded"]\n', '').replace('\t"normal_target_policies": ["nearest", "nearest"],\n', '')
        self.assertEqual(digest(head), BASE['head_sha256'])

    def test_source_numeric_and_contact_data_unchanged(self):
        for path, expected in BASE['data_sha256'].items():
            raw=(ROOT/path).read_bytes()
            if path=='data/character_skills.json':raw=reverse_asuna_data(reverse_activation(raw))
            self.assertEqual(hashlib.sha256(raw).hexdigest(), expected)

    def test_supported_hp_cross_products_fit_signed_int64(self):
        import math
        source = json.loads((ROOT/'data/character_skills.json').read_text())
        maximum = max(math.ceil(math.floor(c['statsLevel50ThreeStar']['MaxHP'] * (1+c['enhanced']['bonusFraction']) + 0.5)
                    if c['enhanced']['stat']=='MaxHP' else c['statsLevel50ThreeStar']['MaxHP']) * 101
                    for c in source['characters'])
        self.assertEqual(maximum, 3025960)
        self.assertLess(maximum * maximum, 2**63)

if __name__ == '__main__':
    unittest.main()
