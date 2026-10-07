"""Reverse only the reviewed area-EX source seams for historical guard tests.

The earlier normal-target manifest stays immutable. The reconstructed text must
also hash to the complete pre-area source from 79e21ec43abc2a49d9d477d28a82097fa169935c.
The three added pure helpers (including their leading comment) are an exact,
reviewed block from e65838502a024f0cf0eee022bbbee32ab8246618, not arbitrary methods
that the historical test is allowed to ignore.
"""
import hashlib

PRE_AREA_EX_SHA256 = '5fce025ec468ca5001745efb53ac07280bcd2f3ea10a73cee7d5267044e73f8e'
AREA_HELPERS_SHA256 = 'fcb2efecb83524c708fd6d9f7472f10d3e5c81761bcad1edb9bee0d3a32a2903'


def replace_once(source, approved, previous, label):
    count = source.count(approved)
    if count != 1:
        raise AssertionError(f'{label}: expected exactly one approved seam, found {count}')
    return source.replace(approved, previous, 1)


def reverse_area_ex(source):
    source = replace_once(source,
        '\t# Opt-in offensive EX adaptation; native isolated scenarios remain nearest.\n'
        '\t"area_ex_coverage_targeting": false,\n', '', 'false-default option')
    source = replace_once(source,
        'const AREA_EX_COVERAGE_KINDS := ["fan_damage", "fan_damage_knockback_stun", "charge_scaled_line_damage",\n'
        '\t"line_damage_with_target_falloff", "three_shot_target_then_rear_fan", "direct_shot_then_explosion", "three_circle_damage"]\n',
        '', 'supported EX kinds')
    source = replace_once(source,
        '\tfor key in ["random_damage","serina_target_by_hp_fraction","hina_echo_per_hit","hoshino_stun_on_final_hit","iori_echo_per_hit","nonomi_echo_per_hit","overtime_enabled","area_ex_coverage_targeting"]:\n',
        '\tfor key in ["random_damage","serina_target_by_hp_fraction","hina_echo_per_hit","hoshino_stun_on_final_hit","iori_echo_per_hit","nonomi_echo_per_hit","overtime_enabled"]:\n',
        'strict bool validation')
    source = replace_once(source,
        '\t\tif ability=="ex" and options.area_ex_coverage_targeting and skill.kind in AREA_EX_COVERAGE_KINDS:\n'
        '\t\t\ttarget=_area_ex_target(u,skill,reach)\n'
        '\t\telse:target=_target(u,reach)\n',
        '\t\ttarget=_target(u,reach)\n', 'EX-only dispatch')
    source = replace_once(source,
        '\t\t"three_circle_damage":\n'
        '\t\t\tvar centers:=_three_circle_centers(u,target,skill)\n'
        '\t\t\tfor i in range(centers.size()):\n'
        '\t\t\t\tvar center:Vector2=centers[i]\n',
        '\t\t"three_circle_damage":\n'
        '\t\t\tvar direction:Vector2=u.cell.direction_to(target.cell)\n'
        '\t\t\tvar sideways:=Vector2(-direction.y,direction.x)\n'
        '\t\t\tfor i in range(int(skill.areaCount)):\n'
        '\t\t\t\tvar center:Vector2=target.cell+sideways*(i-(skill.areaCount-1)*0.5)*options.mutsuki_ex_circle_spacing_world_units\n',
        'shared Mutsuki centers')
    start_marker = '# Pure coverage ranking at the offensive EX dispatch boundary only. Geometry\n'
    end_marker = 'func _normal_target(u: Dictionary):'
    if source.count(start_marker) != 1 or source.count(end_marker) != 1:
        raise AssertionError('expected exactly one approved helper block boundary')
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    helpers = source[start:end]
    if hashlib.sha256(helpers.encode()).hexdigest() != AREA_HELPERS_SHA256:
        raise AssertionError('approved area-EX helper block changed')
    return source[:start] + source[end:]
