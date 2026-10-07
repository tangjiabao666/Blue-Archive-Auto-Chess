"""Recovered portable source gates. Reads vendor JS as inert text; never executes it."""
from decimal import Decimal, ROUND_CEILING, ROUND_HALF_UP
import gzip
import hashlib
import json
from pathlib import Path
import unittest
from asuna_activation_boundary import reverse_activation

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'evidence/asuna-source-kit'
STUDENTS_SHA256 = '3e8ccddcf8dbfbd1eaadbe407c56e45a295f46b462ef715b26e4b9718a15c272'
FORMULA_SHA256 = '1f56e5ba4888ecae782d1094fc9c5afc783e31c4cea297ccf9c2dd6e45e59fb3'
PRE_DATA_SHA256 = 'd58847d79ffd7eac1e8721a68782931f5d2b53b7a5a92c6f188a0528620944ca'
RAW_STATS = ('StarGrade', 'StabilityPoint', 'AttackPower1', 'AttackPower100', 'MaxHP1', 'MaxHP100', 'DefensePower1', 'DefensePower100', 'HealPower1', 'HealPower100', 'DodgePoint', 'AccuracyPoint', 'CriticalPoint', 'CriticalDamageRate', 'AmmoCount', 'AmmoCost', 'Range', 'RegenCost')
BASE_SKILLS = {'autoattack', 'ex', 'normal', 'passive', 'sub'}


def canonical_hash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()


def positive_round(value):
    return int(value.quantize(Decimal('.0001'), rounding=ROUND_HALF_UP).quantize(Decimal('1'), rounding=ROUND_HALF_UP))


def source_interpolate(low, high, level, multiplier):
    scale = (Decimal(level - 1) / 99).quantize(Decimal('.0001'), rounding=ROUND_HALF_UP)
    base = positive_round(Decimal(low) + (high - low) * scale)
    return int((Decimal(base) * Decimal(multiplier)).quantize(Decimal('.0001'), rounding=ROUND_HALF_UP).quantize(Decimal('1'), rounding=ROUND_CEILING))


class AsunaSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads(reverse_activation((ROOT / 'data/character_skills.json').read_bytes()))
        cls.baseline = json.loads((EVIDENCE / 'baseline-preservation.json').read_text())
        cls.raw_bytes = gzip.decompress((EVIDENCE / 'students-6f4d5bb.json.gz').read_bytes())
        cls.raw = next(c for c in json.loads(cls.raw_bytes) if c['Id'] == 16001)
        cls.skills = {s['SkillType']: s for s in cls.raw['Skills']}
        cls.characters = {c['key']: c for c in cls.data['characters']}

    def asuna(self):
        self.assertIn('asuna', tuple(self.characters), 'inactive Asuna record missing')
        return self.characters['asuna']

    def test_01_exact_raw_source_and_formula_bytes(self):
        self.assertEqual(hashlib.sha256(self.raw_bytes).hexdigest(), STUDENTS_SHA256)
        formula = (EVIDENCE / 'common-70a2c4b.js.txt').read_bytes()
        self.assertEqual(hashlib.sha256(formula).hexdigest(), FORMULA_SHA256)
        for sentinel in [b'levelScale = ((level-1)/99).toFixed(4)', b'transcendence = [[0, 1000, 1200, 1400, 1700], [0, 500, 700, 900, 1400], [0, 750, 1000, 1200, 1500]]', b'Math.ceil((Math.round((stat1+(stat100-stat1)*levelScale).toFixed(4))*transcendence).toFixed(4))', b'(startDelay + reloadFrames + endDelay) / 30']:
            self.assertIn(sentinel, formula)
        pre = gzip.decompress((EVIDENCE / 'pre-asuna-character-skills.json.gz').read_bytes())
        self.assertEqual(hashlib.sha256(pre).hexdigest(), PRE_DATA_SHA256)

    def test_02_recovered_historical_record_matches_full_source(self):
        history = json.loads((EVIDENCE / 'historical-2024-source-records.json').read_text())
        self.assertEqual(next(c for c in history['characters'] if c['Id'] == 16001), self.raw)

    def test_03_version_provenance(self):
        self.asuna(); p = self.data['asunaSourceSnapshot']
        self.assertEqual(p['sha256'], STUDENTS_SHA256)
        self.assertEqual(p['commit'], '6f4d5bbaf93c9987bd2c1cff91581337765a1f21')
        self.assertEqual(p['formulaCommit'], '70a2c4b8982ca860687898e61848847a60ffe3b8')
        self.assertEqual(p['formulaSha256'], FORMULA_SHA256)
        for word in ['2024', '2026', 'adaptations', 'not current-live']:
            self.assertIn(word, p['versionBoundary'])

    def test_04_inactive_registration_preserves_all_previous_records(self):
        self.asuna()
        self.assertEqual([c['key'] for c in self.data['characters']], self.baseline['characterOrder'] + ['asuna'])
        for key, expected in self.baseline['characterHashes'].items():
            self.assertEqual(canonical_hash(self.characters[key]), expected, key)
        self.assertEqual(self.data['active_roster'], self.baseline['activeRoster'])
        self.assertEqual(self.data['activeRosterCount'], 13)
        self.assertEqual(self.data['pending_native_roster'], ['asuna'])
        self.assertEqual(self.data['future_support_roster'], ['serina'])
        self.assertNotIn('asuna', self.data['active_roster'])
        self.assertEqual((self.data['rosterRecordCount'], len(self.characters)), (15, 15))

    def test_05_prior_metadata_and_frames_preserved(self):
        self.asuna()
        changed = {'characters', 'runtimeSourceFrames', 'pending_native_roster', 'rosterRecordCount', 'rosterNote'}
        for key, expected in self.baseline['topLevelHashes'].items():
            if key not in changed: self.assertEqual(canonical_hash(self.data[key]), expected, key)
        for key, expected in self.baseline['runtimeSourceFrameHashes'].items():
            self.assertEqual(canonical_hash(self.data['runtimeSourceFrames'][key]), expected, key)
        self.assertEqual(set(self.data['runtimeSourceFrames']), set(self.baseline['runtimeSourceFrameHashes']) | {'asuna'})
        self.assertTrue(self.data['rosterNote'].startswith(self.baseline['rosterNote']))

    def test_06_identity_and_base_stats(self):
        c = self.asuna()
        expected = {'key': 'asuna', 'displayName': 'Asuna', 'studentId': 16001, 'modelRoot': 'asuna_original', 'squadType': 'Main', 'role': 'damage_dealer', 'weaponType': 'AR', 'damageType': 'Mystic', 'armorType': 'LightArmor', 'nativeCoverCapable': True, 'nativeRarity': 1}
        for key, value in expected.items(): self.assertEqual(c[key], value, key)
        self.assertEqual(c['sourceStats'], {key: self.raw[key] for key in RAW_STATS})
        self.assertNotIn('sizeClass', c)
        self.assertFalse(c['nativeExclusiveWeaponEnabled'])

    def test_07_exact_five_base_skills_without_upgrades(self):
        c = self.asuna()
        self.assertEqual(c['sourceSkills'], {key: value for key, value in self.skills.items() if key in BASE_SKILLS})
        for excluded in ['weaponpassive', 'gearnormal', 'Gear', 'Weapon', 'FavorStatValue', 'inactiveSourceSkills']:
            self.assertNotIn(excluded, c)
            self.assertNotIn(excluded, c['sourceSkills'])

    def test_08_independent_native_three_star_formula(self):
        c = self.asuna()
        multipliers = {'MaxHP': '1.12', 'AttackPower': '1.22', 'DefensePower': '1', 'HealPower': '1.175'}
        expected = {'MaxHP': 14106, 'AttackPower': 1771, 'DefensePower': 71, 'HealPower': 3186}
        for key, multiplier in multipliers.items():
            actual = source_interpolate(self.raw[key + '1'], self.raw[key + '100'], 50, multiplier)
            self.assertEqual(actual, expected[key]); self.assertEqual(c['statsLevel50ThreeStar'][key], actual)
        self.assertEqual(self.data['asunaSourceFormulaReferenceValues']['baseline'], c['statsLevel50ThreeStar'])

    def test_09_unbuffed_fixed_stats_and_defaults(self):
        stats = self.asuna()['statsLevel50ThreeStar']
        expected = {'AccuracyPoint': 681, 'DodgePoint': 778, 'CriticalPoint': 243, 'CriticalDamageRate': 20000, 'CriticalChanceResistPoint': 100, 'CriticalDamageResistRate': 5000, 'Range': 650, 'StabilityPoint': 1436, 'AttackSpeed': 10000, 'OppressionResist': 100}
        self.assertEqual({k: v for k, v in stats.items() if k not in {'MaxHP', 'AttackPower', 'DefensePower', 'HealPower'}}, expected)

    def test_10_normal_attack_ammo_weights_and_composed_reload(self):
        c = self.asuna(); normal = c['normalAttack']; raw = self.skills['autoattack']['Effects'][0]
        self.assertEqual(self.data['runtimeSourceFrames']['asuna'], raw['Frames'])
        self.assertEqual(raw['Frames'], {'AttackEnterDuration': 66, 'AttackStartDuration': 24, 'AttackEndDuration': 16, 'AttackBurstRoundOverDelay': 40, 'AttackIngDuration': 24, 'AttackReloadDuration': 56})
        self.assertEqual(normal['hitWeights'], [0.3333, 0.3333, 0.3334])
        self.assertEqual(normal['totalAtkRatioPerBurst'], 1)
        self.assertEqual((normal['nativeAmmoCapacity'], normal['ammoConsumedPerBurst'], normal['burstsPerMagazine']), (15, 3, 5))
        self.assertEqual(normal['burstPeriodSecondsBeforePassives'], 64 / 30)
        self.assertEqual(normal['reloadSeconds'], 96 / 30)
        self.assertTrue(normal['canCrit']); self.assertTrue(normal['enabled'])
        self.assertEqual(normal['rangeSourceUnits'], 650)

    def test_11_basic_raw_coefficient_and_eleven_unnormalized_weights(self):
        d = self.asuna()['basic']['damage']; raw = self.skills['normal']['Effects'][0]
        self.assertEqual(d['totalAtkRatio'], raw['Scale'][9] / 10000)
        self.assertEqual(d['totalAtkRatio'], 4.1641)
        self.assertEqual(d['hitWeights'], [v / 10000 for v in raw['Hits']])
        self.assertEqual(d['hitWeights'], [0.0909] * 11)
        self.assertEqual(d['hitCount'], 11)
        weights = [Decimal(str(x)) for x in d['hitWeights']]
        self.assertEqual(sum(weights), Decimal('.9999'))
        dispatched = [Decimal(str(d['totalAtkRatio'])) * x for x in weights]
        self.assertEqual(dispatched, [Decimal('.37851669')] * 11)
        self.assertEqual(sum(dispatched), Decimal('4.16368359'))
        self.assertTrue(d['canCrit']); self.assertTrue(d['coefficientIsAggregateAcrossHits'])

    def test_12_basic_target_timer_and_unknown_native_contacts(self):
        s = self.asuna()['basic']
        self.assertEqual((s['name'], s['nativeSkillRank'], s['kind'], s['target']), (self.skills['normal']['Name'], 10, 'single_target_burst', 'one_enemy'))
        self.assertEqual(s['castSeconds'], self.skills['normal']['Duration'] / 30)
        self.assertEqual(s['trigger'], {'kind': 'periodic', 'intervalSeconds': 20})
        self.assertEqual(s['targetingRangeSourceUnits'], 850)
        self.assertIsNone(s['nativeHitOffsetsSeconds'])

    def test_13_enhanced_is_critical_damage_stat(self):
        s = self.asuna()['enhanced']
        self.assertEqual((s['nativeSkillRank'], s['stat'], s['bonusFraction']), (10, 'CriticalDamageRate', 0.266))
        self.assertEqual(s['bonusFraction'], self.skills['passive']['Effects'][0]['Scale'][9] / 10000)
        self.assertEqual(s['trigger'], {'kind': 'always'})
        self.assertEqual(positive_round(Decimal(20000) * Decimal('1.266')), 25320)
        self.assertEqual(Decimal(25320 - 5000) / 10000, Decimal('2.032'))

    def test_14_ex_is_self_buff_dash_without_damage_or_refill(self):
        s = self.asuna()['ex']; raw = self.skills['ex']
        self.assertEqual((s['name'], s['nativeSkillRank'], s['kind'], s['target']), (raw['Name'], 5, 'directional_dash_and_self_buffs', 'self'))
        self.assertEqual(s['originalCost'], raw['Cost'][4]); self.assertEqual(s['castSeconds'], raw['Duration'] / 30)
        self.assertEqual(s['targetingRangeSourceUnits'], raw['Range']); self.assertEqual(s['shapeSource'], raw['Radius'])
        self.assertEqual((s['stat'], s['bonusFraction'], s['durationSeconds']), ('AttackSpeed', 0.5737, 30))
        self.assertEqual(s['bonusFraction'], raw['Effects'][1]['Value'][0][4] / 10000)
        self.assertFalse(s['dealsDirectDamage']); self.assertFalse(s['refillMagazine']); self.assertNotIn('damage', s)
        self.assertEqual(s['sourceChannel'], 24)

    def test_15_dash_only_evasion_and_unknown_native_fields(self):
        s = self.asuna()['ex']
        self.assertEqual(s['evasion'], {'stat': 'DodgePoint', 'bonusFraction': 0.4341, 'onlyDuringDash': True, 'durationSeconds': None})
        for key in ['nativeDashStartSeconds', 'nativeDashEndSeconds', 'nativeDashDurationSeconds', 'nativeDashDistanceSourceUnits', 'nativeAttackSpeedOnsetSeconds', 'nativeEvasionOnsetSeconds', 'originalFixedCooldownSeconds', 'proposedAutochessCooldownSeconds']:
            self.assertIsNone(s[key], key)

    def test_16_sub_is_distinct_on_ex_speed_buff(self):
        s = self.asuna()['sub']
        self.assertEqual((s['nativeSkillRank'], s['kind'], s['target'], s['stat']), (10, 'self_buff', 'self', 'AttackSpeed'))
        self.assertEqual(s['trigger'], {'kind': 'on_ex_cast'})
        self.assertEqual(s['bonusFraction'], self.skills['sub']['Effects'][0]['Value'][0][9] / 10000)
        self.assertEqual((s['bonusFraction'], s['durationSeconds'], s['sourceChannel']), (0.3831, 30, 24))
        self.assertIsNone(s['nativeBuffDispatchOffsetSeconds']); self.assertNotIn('damage', s)

    def test_17_explicit_runtime_adaptation_contract(self):
        self.asuna(); a = self.data['asunaRuntimeAdaptations']
        expected = {'dashStartSeconds': 0.4, 'dashEndSeconds': 2.0, 'maxDashWorldUnits': 2.0, 'minimumDashWorldUnits': 0.001, 'geometryBisectionIterations': 16, 'attackSpeedOnset': 'accepted_cast_start', 'dashDirection': 'toward_frozen_target_legal_prefix', 'basicDispatch': 'legacy_even_dispatch', 'attackSpeedStacking': 'additive_distinct_ids', 'exAttackSpeedBuffId': 'asuna_ex_attack_speed', 'subAttackSpeedBuffId': 'asuna_sub_attack_speed', 'dashEvasionBuffId': 'asuna_ex_dash_evasion'}
        for k, v in expected.items(): self.assertEqual(a[k], v, k)
        self.assertIn('not recovered native', a['timingProvenance']); self.assertIn('not recovered root-motion', a['distanceProvenance'])

    def test_18_reference_values_match_independent_buff_merge_arithmetic(self):
        self.asuna(); r = self.data['asunaSourceFormulaReferenceValues']
        self.assertEqual((r['level'], r['levelScale'], r['sourceNativeRarity'], r['nativeStatPolicyStars']), (50, 0.4949, 1, 3))
        self.assertEqual(r['mergeTwoStar'], {'MaxHP': int((Decimal(14106) * Decimal('1.2')).to_integral_value(rounding=ROUND_CEILING)), 'AttackPower': positive_round(Decimal(1771) * Decimal('1.2'))})
        self.assertEqual(r['enhancedCriticalDamageRate'], 25320)
        self.assertEqual(r['combinedAttackSpeed'], positive_round(Decimal(10000) * (1 + Decimal('.5737') + Decimal('.3831'))))
        self.assertEqual(r['dashDodgePoint'], positive_round(Decimal(778) * Decimal('1.4341')))
        self.assertEqual(r['basicPerHitAtkRatio'], 0.37851669); self.assertEqual(r['basicDispatchedTotalAtkRatio'], 4.16368359)


if __name__ == '__main__': unittest.main()
