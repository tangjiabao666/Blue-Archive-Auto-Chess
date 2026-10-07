"""Independent whole-source seam guard and mutation proofs for area EX targeting."""
import hashlib
from pathlib import Path
import unittest
from asuna_source_boundary import reverse_asuna_core
from area_ex_source_boundary import PRE_AREA_EX_SHA256, reverse_area_ex

ROOT = Path(__file__).resolve().parents[1]
SOURCE = reverse_asuna_core((ROOT / 'core/character_sim.gd').read_text())


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


class AreaExSourceBoundary(unittest.TestCase):
    def test_exact_approved_inverse_reconstructs_complete_79e21ec_source(self):
        self.assertEqual(digest(reverse_area_ex(SOURCE)), PRE_AREA_EX_SHA256)

    def test_missing_and_duplicate_approved_seams_fail_closed(self):
        option = '\t"area_ex_coverage_targeting": false,\n'
        with self.assertRaises(AssertionError):
            reverse_area_ex(SOURCE.replace(option, '', 1))
        addition = ('\t# Opt-in offensive EX adaptation; native isolated scenarios remain nearest.\n' + option)
        with self.assertRaises(AssertionError):
            reverse_area_ex(SOURCE.replace(addition, addition + addition, 1))

    def test_unapproved_mutations_are_detected(self):
        mutations = {
            'EX branch widened to basic': ('if ability=="ex" and options.area_ex_coverage_targeting', 'if ability in ["basic","ex"] and options.area_ex_coverage_targeting'),
            'default enabled': ('"area_ex_coverage_targeting": false', '"area_ex_coverage_targeting": true'),
            'unsupported kind admitted': ('const AREA_EX_COVERAGE_KINDS := ["fan_damage",', 'const AREA_EX_COVERAGE_KINDS := ["aoe_damage", "fan_damage",'),
            'dedup removed': ('return unique.size()', 'return victims.size()'),
            'Mutsuki helper arithmetic': ('centers.append(target.cell+sideways*(i-(skill.areaCount-1)*0.5)', 'centers.append(target.cell+sideways*(i-(skill.areaCount-1)*1.0)'),
            'normal selector changed': ('if options.normal_target_policies[u.team]=="nearest":return _target(u,u.range)', 'if options.normal_target_policies[u.team]=="nearest":return null'),
            'shared target changed': ('if d<best_distance-0.000001:best=enemy;best_distance=d', 'if d<best_distance:best=enemy;best_distance=d'),
            'shared fan/line geometry changed': ('if forward<0:continue', 'if forward<=0:continue'),
            'Mutsuki dispatch coefficient changed': ('),skill.damagePerArea,ability,duration,{},"area_"+str(i)', '),skill.damage,ability,duration,{},"area_"+str(i)'),
            'ordinary attacks rerouted': ('var target=_normal_target(u)', 'var target=_target(u,u.range)'),
            'unknown helper inserted': ('func _normal_target(u: Dictionary):', 'func _unreviewed_helper():\n\treturn true\n\nfunc _normal_target(u: Dictionary):'),
        }
        for label, (before, after) in mutations.items():
            with self.subTest(mutation=label):
                self.assertEqual(SOURCE.count(before), 1, 'mutation probe must hit its intended unique seam')
                mutated = SOURCE.replace(before, after, 1)
                try:
                    reconstructed = reverse_area_ex(mutated)
                except AssertionError:
                    continue
                self.assertNotEqual(digest(reconstructed), PRE_AREA_EX_SHA256,
                                    'unapproved change was silently erased by the inverse')


if __name__ == '__main__':
    unittest.main()
