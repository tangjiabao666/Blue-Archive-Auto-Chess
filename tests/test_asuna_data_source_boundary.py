"""Exact Asuna-data inverse plus adversarial mutation proofs; no repo writes."""
import copy
import gzip
import hashlib
import json
from pathlib import Path
import unittest
from asuna_data_source_boundary import reverse_asuna_data
from asuna_activation_boundary import reverse_activation

ROOT = Path(__file__).resolve().parents[1]
SOURCE = reverse_activation((ROOT / 'data/character_skills.json').read_bytes())
BASELINE = gzip.decompress((ROOT / 'evidence/asuna-source-kit/pre-asuna-character-skills.json.gz').read_bytes())
PRE_SHA = 'd58847d79ffd7eac1e8721a68782931f5d2b53b7a5a92c6f188a0528620944ca'


class AsunaDataInverseTests(unittest.TestCase):
    def test_exact_approved_inverse_recovers_historical_bytes(self):
        restored = reverse_asuna_data(SOURCE)
        self.assertEqual(hashlib.sha256(restored).hexdigest(), PRE_SHA)
        self.assertEqual(restored, BASELINE)
        self.assertEqual(reverse_asuna_data(SOURCE.decode()), BASELINE)

    def test_mutated_reviewed_additions_and_old_fields_fail_closed(self):
        def change(path, value):
            data = json.loads(SOURCE)
            cursor = data
            for key in path[:-1]: cursor = cursor[key]
            cursor[path[-1]] = value
            return data
        mutations = {
            'active roster': change(['active_roster'], json.loads(SOURCE)['active_roster'] + ['asuna']),
            'active count': change(['activeRosterCount'], 14),
            'total count': change(['rosterRecordCount'], 16),
            'total count float alias': change(['rosterRecordCount'], 15.0),
            'pending emptied': change(['pending_native_roster'], []),
            'old character attack': change(['characters', 0, 'statsLevel50ThreeStar', 'AttackPower'], 1),
            'old runtime frames': change(['runtimeSourceFrames', 'shiroko', 'AttackReloadDuration'], 56),
            'old metadata': change(['units', 'critical'], 'Guaranteed critical'),
            'Asuna identity': change(['characters', -1, 'studentId'], 10028),
            'Asuna coefficient': change(['characters', -1, 'basic', 'damage', 'totalAtkRatio'], 4.16),
            'Asuna normalized last weight': change(['characters', -1, 'basic', 'damage', 'hitWeights', -1], 0.091),
            'Asuna gear enabled': change(['characters', -1, 'nativeExclusiveWeaponEnabled'], True),
            'EX refills ammo': change(['characters', -1, 'ex', 'refillMagazine'], True),
            'Asuna frames': change(['runtimeSourceFrames', 'asuna', 'AttackReloadDuration'], 60),
            'Asuna timing': change(['asunaRuntimeAdaptations', 'dashStartSeconds'], 0),
            'Asuna source hash': change(['asunaSourceSnapshot', 'sha256'], 'unverified'),
            'Asuna reference': change(['asunaSourceFormulaReferenceValues', 'baseline', 'MaxHP'], 1),
            'roster note': change(['rosterNote'], 'unreviewed note'),
        }
        duplicated = json.loads(SOURCE); duplicated['characters'].append(copy.deepcopy(duplicated['characters'][-1]))
        mutations['duplicate Asuna'] = duplicated
        reordered = json.loads(SOURCE); reordered['characters'][-1], reordered['characters'][-2] = reordered['characters'][-2], reordered['characters'][-1]
        mutations['Asuna not last'] = reordered
        extra = json.loads(SOURCE); extra['unreviewed'] = True; mutations['unreviewed field'] = extra
        missing = json.loads(SOURCE); del missing['asunaRuntimeAdaptations']; mutations['missing addition'] = missing
        for label, data in mutations.items():
            with self.subTest(mutation=label):
                with self.assertRaises(AssertionError): reverse_asuna_data(json.dumps(data))

    def test_duplicate_json_keys_are_rejected(self):
        duplicated = SOURCE.decode().replace('"rosterRecordCount": 15', '"rosterRecordCount": 99, "rosterRecordCount": 15')
        self.assertNotEqual(duplicated.encode(), SOURCE)
        with self.assertRaises(AssertionError): reverse_asuna_data(duplicated)

    def test_missing_or_already_reversed_registration_is_rejected(self):
        with self.assertRaises(AssertionError): reverse_asuna_data(BASELINE)


if __name__ == '__main__': unittest.main()
