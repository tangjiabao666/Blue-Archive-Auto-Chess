extends RefCounted
## Deterministic 50 ms source-backed original-student combat.
## Native numeric data is preserved; autochess adaptations are explicit below.
const DirectionalDash=preload("res://core/directional_dash.gd")
const ARENA_HALF := 6.6
const RADIUS := 0.35
const SPEED := 2.5
const MAX_TICKS := 2400
const STEP_SECONDS := 0.05
const DATA_PATH := "res://data/character_skills.json"
const CONTACTS_PATH := "res://data/native-skill-contacts.json"
const NORMAL_TARGET_POLICIES := ["nearest", "wounded"]
const DEFAULT_OPTIONS := {
	"normal_target_policies": ["nearest", "nearest"],
	# Opt-in offensive EX adaptation; native isolated scenarios remain nearest.
	"area_ex_coverage_targeting": false,
	"seed": 1729, "arena_half": ARENA_HALF, "source_units_per_world_unit": 100.0,
	"merge_hp_bonus": 0.20, "merge_atk_bonus": 0.20,
	"ex_base_seconds": 5.0, "ex_seconds_per_cost": 5.0, "ex_initial_cooldown_fraction": 0.2, "initial_basic_delay_cap_seconds": 0.0, "max_ticks": MAX_TICKS,
	"random_damage": true, "terrain_multiplier": 1.0,
	"serina_target_by_hp_fraction": true, "healing_pack_offset": 0.8,
	"hina_echo_per_hit": true, "hoshino_stun_on_final_hit": true,
	"iori_echo_per_hit": true, "nonomi_echo_per_hit": true,
	# Opt-in match-level sustain pressure; isolated native simulations stay unchanged.
	"overtime_enabled": false, "overtime_start_seconds": 75.0, "overtime_ramp_seconds": 30.0,
	"overtime_min_sustain_multiplier": 0.2,
	# Explicit autochess geometry. Source placement/trigger offsets remain null.
	"mutsuki_mine_forward_world_units": 3.0, "mutsuki_mine_lateral_spacing_world_units": 1.0,
	"mutsuki_mine_trigger_radius_world_units": 0.4, "mutsuki_ex_circle_spacing_world_units": 1.25,
}
const AREA_EX_COVERAGE_KINDS := ["fan_damage", "fan_damage_knockback_stun", "charge_scaled_line_damage",
	"line_damage_with_target_falloff", "three_shot_target_then_rear_fan", "direct_shot_then_explosion", "three_circle_damage"]
const SKILL_KINDS := ["aoe_damage", "drone_damage", "single_target_burst", "fan_damage", "fan_damage_knockback_stun",
	"direct_shot_then_optional_explosion", "direct_shot_then_explosion", "gain_charge_and_self_buff",
	"charge_scaled_line_damage", "reload_and_self_buff", "self_barrier", "single_ally_heal",
	"place_healing_pack_and_reposition", "self_regeneration", "self_heal_once", "self_buff",
	"three_shot_target_then_rear_fan", "line_damage_with_target_falloff", "self_defense_buff_and_aoe_taunt",
	"place_persistent_mines", "three_circle_damage", "ally_threshold_heal", "circle_heal_and_damage", "directional_dash_and_self_buffs"]
var units: Array = []
var phase := "prepare"
var winner := -2
var tick := 0
var events: Array = []
var options: Dictionary = DEFAULT_OPTIONS.duplicate(true)
# Optional adapters. Pure callbacks must not mutate combat or consume RNG.
var line_of_sight: Callable
var path_step: Callable
var position_free: Callable
var segment_free: Callable
var cover_query: Callable
var _data: Dictionary = {}
var _characters: Dictionary = {}
var _contact_schedules: Dictionary = {}
var _contact_constraints: Dictionary = {}
var _initial: Array = []
var _pending: Array = []
var _packs: Array = []
var _mines: Array = []
var _next_mine_id := 0
var _cover_changes: Array = []
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if parsed is Dictionary:
		_data=parsed
		for c in _data.characters:_characters[c.key]=c
	if FileAccess.file_exists(CONTACTS_PATH):
		var contacts=JSON.parse_string(FileAccess.get_file_as_string(CONTACTS_PATH))
		if contacts is Dictionary:
			_contact_schedules=contacts.get("skills",{})
			_contact_constraints=contacts.get("timingConstraints",{})

func character_keys() -> Array:
	return _characters.keys()

func active_character_keys() -> Array:
	return _data.get("active_roster",_characters.keys()).duplicate()

func character_data(key: String) -> Dictionary:
	return _characters.get(key,{}).duplicate(true)

func preview_unit(character_id: String,star: int=1,id: int=0,team: int=0,cell: Vector2=Vector2.ZERO) -> Dictionary:
	if not _characters.has(character_id) or star not in [1,2] or id<0 or team not in [0,1] or not cell.is_finite():return {}
	var u:=_make_unit(id,team,cell,character_id,star,options)
	for name in u.base_stats:u.stats[name]=_stat_value(u,name,[u])
	u.damage=int(u.stats.AttackPower)
	return u

func configure(roster: Array, settings: Dictionary={}) -> String:
	if phase=="running":return "battle is running"
	if _characters.size()<7:return "source data requires at least seven characters"
	if roster.size()<2 or roster.size()>14:return "requires two to fourteen units"
	var next_options:Dictionary=DEFAULT_OPTIONS.duplicate(true)
	for key in settings:
		if not next_options.has(key):return "unknown adaptation option: "+str(key)
		next_options[key]=settings[key]
	if not next_options.normal_target_policies is Array or next_options.normal_target_policies.size()!=2:return "invalid normal target policies"
	for policy in next_options.normal_target_policies:
		if not policy is String or policy not in NORMAL_TARGET_POLICIES:return "invalid normal target policy"
	next_options.normal_target_policies=next_options.normal_target_policies.duplicate(true)
	for key in ["arena_half","source_units_per_world_unit","ex_base_seconds","ex_seconds_per_cost","terrain_multiplier","overtime_start_seconds","overtime_ramp_seconds"]:
		if not _number(next_options[key]) or next_options[key]<=0:return "invalid positive adaptation: "+key
	for key in ["merge_hp_bonus","merge_atk_bonus","healing_pack_offset","initial_basic_delay_cap_seconds","mutsuki_mine_forward_world_units","mutsuki_mine_lateral_spacing_world_units","mutsuki_mine_trigger_radius_world_units","mutsuki_ex_circle_spacing_world_units"]:
		if not _number(next_options[key]) or next_options[key]<0:return "invalid adaptation: "+key
	if not _number(next_options.ex_initial_cooldown_fraction) or next_options.ex_initial_cooldown_fraction<0 or next_options.ex_initial_cooldown_fraction>1:return "invalid initial EX cooldown fraction"
	for key in ["random_damage","serina_target_by_hp_fraction","hina_echo_per_hit","hoshino_stun_on_final_hit","iori_echo_per_hit","nonomi_echo_per_hit","overtime_enabled","area_ex_coverage_targeting"]:
		if not next_options[key] is bool:return "invalid boolean adaptation: "+key
	if next_options.overtime_start_seconds>3600 or next_options.overtime_ramp_seconds>3600:return "overtime duration outside supported range"
	if not _number(next_options.overtime_min_sustain_multiplier) or next_options.overtime_min_sustain_multiplier<0 or next_options.overtime_min_sustain_multiplier>1:return "invalid overtime sustain multiplier"
	if next_options.arena_half<RADIUS*3 or next_options.arena_half>100:return "arena half-size outside supported range"
	if next_options.source_units_per_world_unit>10000:return "range conversion outside supported range"
	if next_options.merge_hp_bonus>100 or next_options.merge_atk_bonus>100:return "merge bonus outside supported range"
	if not next_options.seed is int or not next_options.max_ticks is int or next_options.max_ticks<1 or next_options.max_ticks>72000:return "invalid seed or tick limit"
	var next:Array=[];var ids:Dictionary={};var teams:Array=[0,0]
	for raw in roster:
		if not raw is Dictionary:return "unit must be a dictionary"
		if not raw.get("id") is int or raw.id<0:return "invalid id"
		if not raw.get("team") is int or raw.team not in [0,1]:return "invalid team"
		if not raw.get("cell") is Vector2:return "invalid cell"
		if not raw.cell.is_finite() or absf(raw.cell.x)>next_options.arena_half-RADIUS or absf(raw.cell.y)>next_options.arena_half-RADIUS:return "invalid cell"
		if not _deployment(raw.team,raw.cell):return "wrong deployment zone"
		if ids.has(raw.id):return "duplicate id"
		for other in next:
			if other.cell.distance_to(raw.cell)<RADIUS*2:return "overlapping units"
		if position_free.is_valid() and not position_free.call(raw.cell,RADIUS):return "obstructed cell"
		var key=raw.get("character_id",raw.get("character",""))
		var star=raw.get("star",raw.get("stars",1))
		if not key is String or not _characters.has(key):return "unknown character"
		if not star is int or star not in [1,2]:return "only one three-copy upgrade is supported"
		if raw.has("character") and raw.character!=key:return "conflicting character aliases"
		if raw.has("stars") and raw.stars!=star:return "conflicting star aliases"
		var windup=raw.get("attack_windup_ticks",0)
		if not windup is int or windup<0 or windup>10000:return "invalid attack windup"
		var candidate:=_make_unit(raw.id,raw.team,raw.cell,key,star,next_options)
		candidate.attack_windup_ticks=windup
		next.append(candidate)
		ids[raw.id]=true;teams[raw.team]+=1
	if teams[0]<1 or teams[1]<1 or teams[0]>7 or teams[1]>7:return "one to seven units per team required"
	next.sort_custom(func(a,b):return a.id<b.id)
	options=next_options;units=next
	_reset_transient()
	_refresh_stats()
	_initial=units.duplicate(true)
	return ""

func _make_unit(id: int,team: int,cell: Vector2,key: String,star: int,settings: Dictionary) -> Dictionary:
	var c:Dictionary=_characters[key]
	var base_hp:float=c.statsLevel50ThreeStar.MaxHP
	if c.enhanced.stat=="MaxHP":base_hp=floor(round(base_hp*(1.0+c.enhanced.bonusFraction)*10000.0)/10000.0+0.5)
	var hp:=int(ceil(base_hp*(1.0+settings.merge_hp_bonus if star==2 else 1.0)))
	var cd:=_ticks(settings.ex_base_seconds+settings.ex_seconds_per_cost*c.ex.originalCost)
	var basic_ready:=_ticks(c.basic.trigger.get("intervalSeconds",1000000.0))
	if c.basic.trigger.kind=="ally_hp_below_threshold":basic_ready=0
	if c.basic.trigger.kind=="periodic" and settings.initial_basic_delay_cap_seconds>0:
		basic_ready=_ticks(minf(float(c.basic.trigger.intervalSeconds),settings.initial_basic_delay_cap_seconds))
	var reach:float=c.statsLevel50ThreeStar.Range/settings.source_units_per_world_unit
	var u:Dictionary={"id":id,"team":team,"cell":cell,"character_id":key,"star":star,
		"max_hp":hp,"hp":hp,"damage":0,"range":reach,"weapon":c.weaponType,
		"base_stats":c.statsLevel50ThreeStar.duplicate(true),"stats":{},"level":50,
		"damage_type":c.damageType,"armor_type":c.armorType,
		"skill":"ex","skill_ready":maxi(1,int(ceil(cd*settings.ex_initial_cooldown_fraction))),"skill_cooldown_ticks":cd,"skill_recovery_ticks":_ticks(c.ex.castSeconds),
		"basic_ready":basic_ready,"basic_activations":0,"attack_ready":0,
		"aimed":false,"aim_target_id":-1,"aim_ready":0,"aim_started":0,
		"attack_ticks":_ticks(c.normalAttack.burstPeriodSecondsBeforePassives) if c.normalAttack.enabled else 0,
		"attack_windup_ticks":0,"busy_until":0,"move_ready":0,"move_ticks":1,
		"ammo":int(c.normalAttack.nativeAmmoCapacity),"reload_at":0,"reload_until":0,
		"shield":0,"shield_until":0,"charges":0,"buffs":{},"sub_ready":0,"cover_ready":0,
		"in_cover":false,"stun_until":0,"energy":0,"dead":false,
		"taunt_source_id":-1,"taunt_until":0,"stationary":true,"last_moved_tick":-1,
		"damage_taken_multiplier":1.0,"size_class":str(c.get("sizeClass","unknown")).to_lower()}
	if key=="asuna":u.dash={}
	if c.sub.trigger.kind=="periodic":u.sub_ready=_ticks(c.sub.trigger.intervalSeconds)
	if c.sub.trigger.kind=="while_stationary":
		u.buffs[key+"_stationary"]={"stat":c.sub.stat,"fraction":c.sub.bonusFraction,"until":settings.max_ticks+1,"condition":"while_stationary"}
	return u

func place(id: int,cell: Vector2) -> bool:
	if phase!="prepare" or not _inside(cell):return false
	var u=_unit(id)
	if u==null or u.team!=0 or not _deployment(0,cell) or not _free(cell,id):return false
	u.cell=cell
	return true

func start() -> bool:
	if phase!="prepare" or units.is_empty():return false
	_initial=units.duplicate(true)
	_reset_transient()
	phase="running"
	return true

func _reset_transient() -> void:
	phase="prepare";winner=-2;tick=0;events=[];_pending=[];_packs=[];_mines=[];_next_mine_id=0;_cover_changes=[]
	_rng.seed=int(options.seed)

func reset() -> void:
	units=_initial.duplicate(true)
	_reset_transient()

func snapshot() -> Dictionary:
	return {"phase":phase,"winner":winner,"tick":tick,"units":units.duplicate(true),
		"pending_hits":_pending.duplicate(true),"healing_packs":_packs.duplicate(true),
		"mines":_mines.duplicate(true),"next_mine_id":_next_mine_id,
		"pending_cover_changes":_cover_changes.duplicate(true),
		"rng_state":_rng.state,"adaptations":options.duplicate(true),"overtime":overtime_state()}

## Explicit autochess rule, evaluated only from simulation ticks. It does not
## modify source stats, coefficients, animation speed, skill timing or old shields.
func overtime_state() -> Dictionary:
	var start_tick:=_ticks(options.overtime_start_seconds)
	var ramp_ticks:=_ticks(options.overtime_ramp_seconds)
	var active:bool=options.overtime_enabled and tick>=start_tick
	var progress:=clampf(float(tick-start_tick)/ramp_ticks,0.0,1.0) if active else 0.0
	var sustain:=_overtime_sustain_multiplier()
	return {"enabled":options.overtime_enabled,"active":active,"start_tick":start_tick,"ramp_ticks":ramp_ticks,
		"start_seconds":start_tick*STEP_SECONDS,"ramp_seconds":ramp_ticks*STEP_SECONDS,
		"progress":progress,"healing_multiplier":sustain,"shield_multiplier":sustain,
		"damage_multiplier":1.0,"min_sustain_multiplier":options.overtime_min_sustain_multiplier}

func _overtime_sustain_multiplier() -> float:
	if not options.overtime_enabled:return 1.0
	var progress:=clampf(float(tick-_ticks(options.overtime_start_seconds))/_ticks(options.overtime_ramp_seconds),0.0,1.0)
	# Preserve the configured endpoint exactly before integer amount truncation.
	if progress>=1.0:return float(options.overtime_min_sustain_multiplier)
	return lerpf(1.0,options.overtime_min_sustain_multiplier,progress)

func step() -> Array:
	events=[]
	if phase!="running":return []
	tick+=1
	if options.overtime_enabled and tick==_ticks(options.overtime_start_seconds):
		_emit("overtime_started",overtime_state())
	if cover_query.is_valid():
		for unit in units:
			if unit.hp<=0:continue
			var covered:bool=cover_query.call(unit)
			if covered!=unit.in_cover:_cover_changes.append({"id":unit.id,"in_cover":covered})
	_apply_cover_changes()
	_expire_and_reload()
	_update_packs()
	_update_dashes()
	_move_units()
	_update_conditional_states()
	_update_mines()
	var queue:Array=[]
	var later:Array=[]
	# All actors alive at this tick boundary may resolve already-due attacks,
	# even if a simultaneous queued hit kills them later in this same tick.
	for hit in _pending:
		var actor=_unit(hit.source)
		var target=_unit(hit.target)
		if actor==null or actor.hp<=0 or target==null or target.hp<=0:continue
		if hit.due<=tick:queue.append(hit)
		else:later.append(hit)
	_pending=later
	for u in units:
		if u.hp<=0:continue
		var c:Dictionary=_characters[u.character_id]
		if c.sub.trigger.kind=="periodic" and tick>=u.sub_ready:_periodic_sub(u)
		if c.basic.trigger.kind=="hp_below_threshold" and u.basic_activations==0 and float(u.hp)/u.max_hp<c.basic.trigger.thresholdHpRatio:
			_start_health_skill(u)
		if u.aimed and _target(u,u.range)==null:_clear_aim(u,"target_lost")
		if tick<u.busy_until or tick<u.stun_until or u.reload_until>tick:continue
		if u.star==2 and tick>=u.skill_ready and _try_skill(u,"ex"):continue
		if c.basic.trigger.kind in ["periodic","ally_hp_below_threshold"] and tick>=u.basic_ready and _try_skill(u,"basic"):continue
		if c.normalAttack.enabled and u.ammo>0:
			var target=_normal_target(u)
			if target==null:continue
			if not u.aimed:
				_begin_aim(u,target)
				continue
			u.aim_target_id=target.id
			if tick>=u.attack_ready and tick>=u.aim_ready:_normal_attack(u,target)
	# Newly queued zero-delay actions still join this batch before resolution.
	later=[]
	for hit in _pending:
		if hit.due<=tick:queue.append(hit)
		else:later.append(hit)
	_pending=later
	for hit in queue:_resolve_hit(hit)
	for u in units:
		if u.hp<=0 and not u.dead:
			_cancel_dash(u,"death")
			u.hp=0;u.dead=true
			u.taunt_source_id=-1;u.taunt_until=0;u.stationary=false;u.damage_taken_multiplier=1.0
			for buff_id in u.buffs.keys():
				if u.buffs[buff_id].has("condition"):u.buffs.erase(buff_id)
			_emit("death",{"actor_id":u.id,"character_id":u.character_id})
	_remove_dead_owner_mines()
	_clear_invalid_taunts()
	_refresh_stats()
	_check_finish()
	return events.duplicate(true)

func _expire_and_reload() -> void:
	_clear_invalid_taunts()
	for u in units:
		if u.hp<=0:continue
		if u.shield>0 and tick>=u.shield_until:
			u.shield=0;_emit("shield_expired",{"actor_id":u.id})
		for key in u.buffs.keys():
			if tick>=u.buffs[key].until:
				u.buffs.erase(key);_emit("buff_expired",{"actor_id":u.id,"buff_id":key})
		if u.reload_until>0 and tick>=u.reload_until:
			u.ammo=int(_characters[u.character_id].normalAttack.nativeAmmoCapacity)
			u.reload_until=0
			_emit("reload_complete",{"actor_id":u.id,"ammo":u.ammo,"character_id":u.character_id})
		if u.reload_at>0 and tick>=u.reload_at and tick>=u.busy_until and tick>=u.stun_until:
			_start_reload(u)

func _start_reload(u: Dictionary) -> void:
	var c:Dictionary=_characters[u.character_id]
	u.reload_at=0
	var seconds:float=c.normalAttack.reloadSeconds
	u.reload_until=tick+_ticks(seconds)
	u.attack_ready=u.reload_until
	_emit("reload",{"actor_id":u.id,"character_id":u.character_id,"until_tick":u.reload_until,"duration_ticks":_ticks(seconds)})
	if c.sub.trigger.kind=="while_reloading":
		_buff(u,u.character_id+"_reload","DamageTakenReduction",c.sub.damageTakenReductionFraction,u.reload_until,"sub")
		u.buffs[u.character_id+"_reload"].condition="while_reloading"
		u.damage_taken_multiplier=1.0-c.sub.damageTakenReductionFraction
	if u.character_id=="hina":
		u.basic_activations+=1
		_emit("basic",_ability_event(u,u,"basic",c.basic,_ticks(seconds)))
		_buff(u,"hina_reload",c.basic.stat,c.basic.bonusFraction,tick+_ticks(c.basic.durationSeconds),"basic")

func _move_units() -> void:
	for u in units:
		if u.hp<=0 or tick<u.busy_until or tick<u.stun_until or u.reload_until>tick:continue
		var goal:Vector2=u.cell;var reach:float=u.range;var forced:=false
		for pack in _packs:
			if pack.target==u.id:goal=pack.cell;reach=0.05;forced=true;break
		if not forced:
			# Healers stay in formation unless they are collecting a pack.
			if not _characters[u.character_id].normalAttack.enabled:continue
			# Hold a valid firing position even when a nearer enemy is hidden.
			if _target(u,u.range)!=null:continue
			var target=_target(u)
			if target==null:continue
			if can_attack(u,target,u.range):continue
			goal=target.cell
			# When LOS is blocked, travel toward target rather than stopping at range.
			if line_of_sight.is_valid() and not line_of_sight.call(u.cell,target.cell):reach=RADIUS*2
		var dest:Vector2=_path_step(u,goal,reach)
		if dest!=u.cell and _inside(dest) and _free(dest,u.id) and _segment_clear(u.cell,dest):
			var origin:Vector2=u.cell
			_clear_aim(u,"movement")
			u.cell=dest;u.move_ready=tick+1;u.last_moved_tick=tick;u.stationary=false
			_emit("move",{"actor_id":u.id,"from":origin,"to":dest,"duration":STEP_SECONDS,"forced":forced})

func _try_skill(u: Dictionary,ability: String) -> bool:
	var c:Dictionary=_characters[u.character_id]
	var skill:Dictionary=c[ability]
	if not skill.kind in SKILL_KINDS:
		_emit("skill_unavailable",{"actor_id":u.id,"character_id":u.character_id,"ability":ability,"skill":skill.kind,"reason":"unsupported_semantic"})
		return false
	if skill.kind=="directional_dash_and_self_buffs" and _target(u)==null:return false
	var target=u
	var reach:float=skill.get("targetingRangeSourceUnits",c.statsLevel50ThreeStar.Range)/options.source_units_per_world_unit
	if skill.kind=="circle_heal_and_damage":
		target=_support_circle_target(u,skill,reach)
	elif skill.kind=="ally_threshold_heal":
		target=_threshold_ally_target(u,skill,reach)
	elif skill.target in ["lowest_HP_ally","ally_closest_to_selected_location"]:
		target=_heal_target(u,reach)
	elif skill.target not in ["self","fixed_positions_in_front_of_self"]:
		if ability=="ex" and options.area_ex_coverage_targeting and skill.kind in AREA_EX_COVERAGE_KINDS:
			target=_area_ex_target(u,skill,reach)
		else:target=_target(u,reach)
	if target==null:return false
	var duration:=_ticks(skill.castSeconds)
	u.busy_until=tick+duration
	if ability=="ex":
		u.skill_ready=tick+u.skill_cooldown_ticks
		u.energy=0
	else:
		if skill.trigger.kind=="periodic":u.basic_ready=tick+_ticks(skill.trigger.intervalSeconds)
		elif skill.trigger.has("internalCooldownSeconds"):u.basic_ready=tick+_ticks(skill.trigger.internalCooldownSeconds)
		u.basic_activations+=1
	var payload:=_ability_event(u,target,ability,skill,duration)
	var charge:int=u.charges
	if u.character_id=="aru":payload.explosion_proc=ability=="ex" or _rng.randf()<skill.explosionProbability
	if u.character_id=="aris":payload.charges=charge
	if skill.kind=="directional_dash_and_self_buffs":
		var reference=_target(u)
		payload.target_cell=reference.cell;payload.reference_target_id=reference.id
		payload.dash_start_tick=tick+8;payload.dash_end_tick=tick+40
		payload.dash_adaptation="frozen_forward; max_two_world_units; swept_legal_prefix; no_damage_or_refill"
	if skill.kind=="circle_heal_and_damage":payload.targeting_adaptation="low_hp_allies_then_effective_heal_damage; unit_centers_and_pair_midpoints"
	_emit("skill" if ability=="ex" else "basic",payload)
	if ability=="ex":_ex_sub(u,charge,duration)
	match skill.kind:
		"ally_threshold_heal":
			var offset:=_single_contact_offset(u.character_id,ability,"",duration,0.5)
			_pending.append({"source":u.id,"target":target.id,"due":tick+offset,"effect":"heal","ratio":skill.healPowerRatio,"ability":ability,"cast_context":payload.duplicate(true)})
		"circle_heal_and_damage":
			var radius:float=skill.shapeSource[0].Radius/options.source_units_per_world_unit
			var offset:=_single_contact_offset(u.character_id,ability,"circle",duration,0.2)
			_damage_pattern(u,_circle_targets(u,target.cell,radius),skill.damage,ability,duration,{},"circle",-1,payload)
			for ally in _allied_circle_targets(u,target.cell,radius):
				_pending.append({"source":u.id,"target":ally.id,"due":tick+offset,"effect":"heal","ratio":skill.healPowerRatio,"ability":ability,"cast_context":payload.duplicate(true),"component":"circle"})
		"directional_dash_and_self_buffs":
			_buff(u,"asuna_ex_attack_speed",skill.stat,skill.bonusFraction,tick+_ticks(skill.durationSeconds),ability)
			_begin_dash(u,skill)
		"self_buff":
			_buff(u,u.character_id+"_"+ability,skill.stat,skill.bonusFraction,tick+_ticks(skill.durationSeconds),ability)
		"self_defense_buff_and_aoe_taunt":
			_buff(u,u.character_id+"_"+ability,skill.stat,skill.bonusFraction,tick+_ticks(skill.durationSeconds),ability)
			for enemy in _circle_targets(u,u.cell,skill.shapeSource[0].Radius/options.source_units_per_world_unit):
				var taunt_ticks:=_ticks(skill.tauntSeconds*100.0/maxf(1,stat(enemy,"OppressionResist")))
				enemy.taunt_source_id=u.id;enemy.taunt_until=tick+taunt_ticks
				_clear_aim(enemy,"taunted")
				_emit("taunt",{"actor_id":u.id,"target_id":enemy.id,"until_tick":enemy.taunt_until,"duration_ticks":taunt_ticks,"ability":ability})
		"three_shot_target_then_rear_fan":
			var victims:Array=[target]
			victims.append_array(_rear_fan_targets(u,target,skill.shapeSource[0]))
			var damage:Dictionary=skill.damagePerShot.duplicate(true)
			damage.totalAtkRatio*=skill.shotCount
			damage.hitWeights=[]
			for i in range(int(skill.shotCount)):damage.hitWeights.append(1.0/skill.shotCount)
			_damage_pattern(u,victims,damage,ability,duration,{},"rear_fan",-1,payload)
		"line_damage_with_target_falloff":
			var victims:=_shape_targets(u,target,skill.shapeSource[0])
			var direction:Vector2=u.cell.direction_to(target.cell)
			victims.sort_custom(func(a,b):
				var da:float=(a.cell-u.cell).dot(direction);var db:float=(b.cell-u.cell).dot(direction)
				return a.id<b.id if is_equal_approx(da,db) else da<db)
			for i in range(victims.size()):
				var damage:Dictionary=skill.damage.duplicate(true)
				damage.totalAtkRatio*=maxf(skill.minimumDamageFraction,1.0-skill.damageReductionPerSubsequentTarget*i)
				_damage_pattern(u,[victims[i]],damage,ability,duration,{},"piercing",-1,payload)
		"three_circle_damage":
			var centers:=_three_circle_centers(u,target,skill)
			for i in range(centers.size()):
				var center:Vector2=centers[i]
				var context:Dictionary=payload.duplicate(true);context.target_cell=center
				_damage_pattern(u,_circle_targets(u,center,skill.shapeSource[0].Radius/options.source_units_per_world_unit),skill.damagePerArea,ability,duration,{},"area_"+str(i),maxi(1,roundi(duration*lerpf(0.2,0.85,float(i)/maxi(1,skill.areaCount-1)))),context)
		"place_persistent_mines":
			var aimed=_target(u)
			var direction:Vector2=u.cell.direction_to(aimed.cell) if aimed!=null else Vector2.UP if u.team==0 else Vector2.DOWN
			_pending.append({"source":u.id,"target":u.id,"due":tick+duration,"effect":"place_mines","origin":u.cell,"direction":direction,"ability":ability,"cast_context":payload.duplicate(true)})
		"self_heal_once":
			_pending.append({"source":u.id,"target":u.id,"due":tick+maxi(1,int(duration*0.5)),"effect":"heal","ratio":skill.healPowerRatio,"ability":ability})
		"aoe_damage":
			_damage_pattern(u,_circle_targets(u,target.cell,skill.shapeSource[0].Radius/options.source_units_per_world_unit),skill.damage,ability,duration,{},"",-1,payload)
		"drone_damage","single_target_burst":
			_damage_pattern(u,[target],skill.damage,ability,duration,{},"",-1,payload)
		"fan_damage","fan_damage_knockback_stun":
			var victims:=_shape_targets(u,target,skill.shapeSource[0])
			_damage_pattern(u,victims,skill.damage,ability,duration,skill,"",-1,payload)
		"direct_shot_then_optional_explosion","direct_shot_then_explosion":
			_damage_pattern(u,[target],skill.direct,ability,duration,{},"direct",maxi(1,int(duration*0.4)),payload)
			if payload.explosion_proc:
				_damage_pattern(u,_circle_targets(u,target.cell,skill.shapeSource[0].Radius/options.source_units_per_world_unit),skill.explosion,ability,duration,{},"explosion",maxi(1,int(duration*0.7)),payload)
		"gain_charge_and_self_buff":
			u.charges=mini(skill.maximumEnergyCharges,u.charges+skill.energyChargeAdded)
			_buff(u,"aris_basic",skill.stat,skill.bonusFraction,tick+_ticks(skill.buffDurationSeconds),ability)
			_emit("charge",{"actor_id":u.id,"charges":u.charges})
		"charge_scaled_line_damage":
			var d:Dictionary={"totalAtkRatio":skill.damageAtkRatioByChargeCount[str(charge)],"hitWeights":[1.0],"canCrit":skill.canCrit}
			_damage_pattern(u,_shape_targets(u,target,skill.shapeSource[0]),d,ability,duration,{},"",-1,payload)
			u.charges=0
			_emit("charge",{"actor_id":u.id,"charges":0,"consumed":charge})
		"reload_and_self_buff":
			u.reload_at=0
			u.reload_until=tick+duration
			u.attack_ready=u.reload_until
			_emit("reload",{"actor_id":u.id,"character_id":u.character_id,"ability":ability,"via_ex":true,"until_tick":u.reload_until,"duration_ticks":duration})
			_buff(u,"serika_ex",skill.stat,skill.bonusFraction,tick+_ticks(skill.durationSeconds),ability)
		"self_barrier":
			_shield(u,skill.barrierHealPowerRatio,tick+_ticks(skill.durationSeconds),ability)
		"single_ally_heal":
			_pending.append({"source":u.id,"target":target.id,"due":tick+maxi(1,int(duration*0.5)),"effect":"heal","ratio":skill.healPowerRatio,"ability":ability})
		"place_healing_pack_and_reposition":
			var destination:=_pack_destination(target)
			_pending.append({"source":u.id,"target":target.id,"due":tick+maxi(1,int(duration*0.4)),"effect":"pack","ratio":skill.healPowerRatio,"cell":destination,"ability":ability})
	return true

func _ability_event(u: Dictionary,target: Dictionary,ability: String,skill: Dictionary,duration: int) -> Dictionary:
	return {"actor_id":u.id,"target_id":target.id,"character_id":u.character_id,"ability":ability,
		"kind":ability,"skill":skill.kind,"ability_name":skill.name,"recovery_ticks":duration,"cast_start_tick":tick,
		"origin":u.cell,"target_cell":target.cell,"timing_adaptation":"source_visual_contacts_where_available; otherwise_even_dispatch"}

func _ex_sub(u: Dictionary,charge: int,duration: int) -> void:
	var sub:Dictionary=_characters[u.character_id].sub
	match u.character_id:
		"hoshino":_shield(u,sub.barrierHealPowerRatio,tick+duration,"sub")
		"aru":_buff(u,"aru_sub",sub.stat,sub.bonusFraction,tick+duration,"sub")
		"aris":_buff(u,"aris_sub",sub.stat,sub.bonusFractionByChargeCount[str(charge)],tick+_ticks(sub.durationSeconds),"sub")
		"serika":_buff(u,"serika_sub",sub.stat,sub.bonusFraction,tick+_ticks(sub.durationSeconds),"sub")
		"asuna":_buff(u,"asuna_sub_attack_speed",sub.stat,sub.bonusFraction,tick+_ticks(sub.durationSeconds),"sub")

func _start_health_skill(u:Dictionary)->void:
	var basic:Dictionary=_characters[u.character_id].basic
	if basic.kind=="self_regeneration":_start_regeneration(u)
	elif basic.kind=="self_heal_once":
		var previous_busy:int=u.busy_until
		_try_skill(u,"basic")
		u.busy_until=maxi(previous_busy,u.busy_until)

func _start_regeneration(u: Dictionary) -> void:
	var basic:Dictionary=_characters[u.character_id].basic
	u.basic_activations+=1
	u.busy_until=maxi(u.busy_until,tick+_ticks(basic.castSeconds))
	_emit("basic",_ability_event(u,u,"basic",basic,_ticks(basic.castSeconds)))
	# Unknown native initial tick: deliberately no unverified immediate bonus tick.
	var period:=_ticks(basic.tickSeconds)
	var total:=_ticks(basic.durationSeconds)
	for offset in range(period,total+1,period):
		_pending.append({"source":u.id,"target":u.id,"due":tick+offset,"effect":"heal","ratio":basic.healPowerRatioPerTick,"ability":"basic","regeneration":true})

func _begin_aim(u: Dictionary,target: Dictionary) -> void:
	var frames:Dictionary=_data.runtimeSourceFrames[u.character_id]
	var speed:float=stat(u,"AttackSpeed")/10000.0
	var start_ticks:=_ticks(frames.get("AttackStartDuration",1)/30.0/speed)
	var entry_ticks:=_ticks(frames.get("AttackEnterDuration",1)/30.0/speed)
	# These named source durations do not prove an exact engine-state timeline.
	# Explicit adaptation: never compress Start when Enter happens to be shorter.
	var window:=maxi(start_ticks,entry_ticks)
	u.aimed=true;u.aim_target_id=target.id;u.aim_started=tick;u.aim_ready=tick+window
	_emit("aim",{"actor_id":u.id,"target_id":target.id,"character_id":u.character_id,
		"origin":u.cell,"target_cell":target.cell,"start_tick":tick,"start_ticks":start_ticks,
		"duration_ticks":start_ticks,"entry_ticks":entry_ticks,"recovery_ticks":window,
		"ready_tick":u.aim_ready,"timing_adaptation":"acquisition_window_max_source_start_enter"})

func _clear_aim(u: Dictionary,reason: String) -> void:
	if not u.aimed:return
	var previous:int=u.aim_target_id
	u.aimed=false;u.aim_target_id=-1;u.aim_ready=0;u.aim_started=0
	_emit("aim_lost",{"actor_id":u.id,"target_id":previous,"character_id":u.character_id,"reason":reason})

func _normal_attack(u: Dictionary,target: Dictionary) -> void:
	var c:Dictionary=_characters[u.character_id]
	var attack:Dictionary=c.normalAttack
	var frames:Dictionary=_data.runtimeSourceFrames[u.character_id]
	var speed:float=stat(u,"AttackSpeed")/10000.0
	var period:=_ticks(attack.burstPeriodSecondsBeforePassives/speed)
	var span:=_ticks(frames.get("AttackIngDuration",1)/30.0/speed)
	var windup:=maxi(1,int(u.attack_windup_ticks))
	u.attack_ticks=period;u.attack_ready=tick+maxi(period,windup)
	u.busy_until=tick+maxi(span,windup)
	u.ammo=maxi(0,u.ammo-int(attack.ammoConsumedPerBurst))
	if u.ammo==0:u.reload_at=tick+maxi(span,windup)
	var victims:Array=[target]
	if not attack.shapeSource.is_empty():victims=_shape_targets(u,target,attack.shapeSource[0])
	_emit("attack",{"actor_id":u.id,"target_id":target.id,"character_id":u.character_id,"ability":"normal",
		"origin":u.cell,"target_cell":target.cell,"impact_tick":tick+windup,"burst_ticks":span,"period_ticks":period,"recovery_ticks":period,"hit_count":attack.hitWeights.size(),"ammo":u.ammo})
	var damage:Dictionary={"totalAtkRatio":attack.totalAtkRatioPerBurst,"hitWeights":attack.hitWeights,"canCrit":true}
	_damage_pattern(u,victims,damage,"normal",span,{},"normal",windup)
	if c.sub.trigger.kind=="normal_attack_proc" and tick>=u.sub_ready and _rng.randf()<c.sub.trigger.probability:
		u.sub_ready=tick+_ticks(c.sub.trigger.internalCooldownSeconds)
		_buff(u,u.character_id+"_sub",c.sub.stat,c.sub.bonusFraction,tick+_ticks(c.sub.durationSeconds),"sub")

func _damage_pattern(u: Dictionary,victims: Array,damage: Dictionary,ability: String,duration: int,skill: Dictionary={},component: String="",first_offset: int=-1,cast_context:Dictionary={}) -> void:
	var weights:Array=damage.hitWeights
	var contact_ticks:Array[int]=_native_contact_ticks(u.character_id,ability,component,weights.size())
	var lower_bound:int=_native_contact_lower_bound(u.character_id,ability,component)
	var first:=maxi(1,int(duration*0.2)) if first_offset<0 else maxi(1,first_offset)
	var last:=maxi(first,int(duration*0.85))
	for victim in victims:
		for i in range(weights.size()):
			var offset:=first if weights.size()==1 else int(round(lerpf(first,last,float(i)/(weights.size()-1))))
			if contact_ticks.size()==weights.size():offset=contact_ticks[i]
			offset=maxi(offset,lower_bound)
			var hit:Dictionary={"source":u.id,"target":victim.id,"due":tick+offset,"effect":"damage",
				"atk_ratio":damage.totalAtkRatio*weights[i],"can_crit":damage.get("canCrit",true),
				"kind":"attack" if ability=="normal" else "skill","ability":ability,"component":component,
				"hit_index":i,"hit_count":weights.size(),"origin":cast_context.get("damage_origin",u.cell),"target_cell":victim.cell,
				"cast_start_tick":int(cast_context.get("cast_start_tick",tick)),"cast_target_cell":cast_context.get("target_cell",victim.cell),
				"timing_adaptation":"source_visual_contact" if contact_ticks.size()==weights.size() else "not_before_hand_prop_end_adaptation" if lower_bound>0 else "legacy_cast_dispatch"}
			if cast_context.has("mine_id"):hit.mine_id=cast_context.mine_id
			if skill.get("knockbackPerHit",false):hit.knockback=skill.knockbackDisplayedSourceUnits/options.source_units_per_world_unit
			if skill.has("stunSeconds") and (not options.hoshino_stun_on_final_hit or i==weights.size()-1):hit.stun_seconds=skill.stunSeconds
			_pending.append(hit)

func _native_contact_ticks(character:String,ability:String,component:String,count:int)->Array[int]:
	# Source-visual synchronization, not a claim of recovered native damage callbacks.
	# The manifest leaves unresolved impact registrations absent; numeric skill data
	# and hit weights stay untouched. Quantization never precedes a verified cue.
	var result:Array[int]=[]
	if ability=="normal" or count<=0:return result
	var row:Dictionary=_contact_schedules.get(character+":"+ability+":"+component,{})
	if int(row.get("hitCount",0))!=count:return result
	match str(row.get("mode","")):
		"points":
			var seconds:Array=row.get("seconds",[])
			if seconds.size()!=count:return []
			var previous:=-1.0
			for value in seconds:
				var at:=float(value)
				if not is_finite(at) or at<0 or at<previous:return []
				result.append(maxi(1,ceili(at/STEP_SECONDS-0.000001)));previous=at
		"window":
			var start:=float(row.get("startSeconds",-1));var end:=float(row.get("endSeconds",-1))
			if not is_finite(start) or not is_finite(end) or start<0 or end<start:return []
			var first:=maxi(1,ceili(start/STEP_SECONDS-0.000001))
			var last:=floori(end/STEP_SECONDS+0.000001)
			if last<first:return []
			for i in range(count):result.append(first if count==1 else int(round(lerpf(first,last,float(i)/(count-1)))))
	return result

func _native_contact_lower_bound(character:String,ability:String,component:String)->int:
	# A hand-prop clip end is not proof of projectile arrival. This is a conservative
	# visibility constraint only, leaving the original runtime impact unresolved.
	if ability=="normal":return 0
	var row:Dictionary=_contact_constraints.get(character+":"+ability+":"+component,{})
	var seconds:=float(row.get("notBeforeSeconds",-1))
	if not is_finite(seconds) or seconds<0:return 0
	return maxi(1,ceili(seconds/STEP_SECONDS-0.000001))

func _resolve_hit(hit: Dictionary) -> void:
	var source=_unit(hit.source);var target=_unit(hit.target)
	if source==null or target==null:return
	if hit.effect=="place_mines":
		_place_mines(source,hit)
		return
	if hit.effect=="heal":
		var context:Dictionary=hit.get("cast_context",{}).duplicate(true)
		if not context.is_empty():
			context.component=hit.get("component","");context.hit_index=hit.get("hit_index",0);context.hit_count=hit.get("hit_count",1)
		_heal(source,target,hit.ratio,hit.ability,context)
		return
	if hit.effect=="pack":
		if target.hp<=0:return
		var recipient=_nearest_ally(source,hit.cell)
		if recipient==null:return
		_packs.append({"source":source.id,"target":recipient.id,"cell":hit.cell,"ratio":hit.ratio,"expires":tick+200})
		_emit("healing_pack",{"actor_id":source.id,"target_id":recipient.id,"cell":hit.cell,"ability":"ex","expires_tick":tick+200})
		return
	if target.hp<=0:return
	var landed:=true;var critical:=false;var stability:=1.0
	if options.random_damage:
		landed=_rng.randf()<hit_probability(stat(source,"AccuracyPoint"),stat(target,"DodgePoint"))
		critical=hit.can_crit and _rng.randf()<critical_probability(stat(source,"CriticalPoint"),stat(target,"CriticalChanceResistPoint"))
		var sp:=stat(source,"StabilityPoint")
		stability=_rng.randf_range(clampf(sp/(sp+1000.0)+0.2,0,1),1.0)
	if not landed:
		_emit("miss",{"actor_id":source.id,"target_id":target.id,"kind":hit.kind,"ability":hit.ability,"hit_index":hit.hit_index,
			"cast_start_tick":hit.get("cast_start_tick",tick),"cast_target_cell":hit.get("cast_target_cell",hit.target_cell)})
		return
	var components:=damage_components(source,target,hit.atk_ratio,critical,stability)
	var amount:int=maxi(0,int(floor(components.raw)))
	var absorbed:int=mini(target.shield,amount)
	target.shield-=absorbed
	var dealt:int=mini(target.hp,amount-absorbed)
	target.hp-=dealt
	var damage_payload:Dictionary={"actor_id":source.id,"target_id":target.id,"character_id":source.character_id,"amount":dealt,
		"raw_amount":amount,"absorbed":absorbed,"hp":target.hp,"shield":target.shield,"kind":hit.kind,"ability":hit.ability,
		"component":hit.component,"hit_index":hit.hit_index,"hit_count":hit.hit_count,"atk_ratio":hit.atk_ratio,
		"critical":critical,"damage_type":source.damage_type,"origin":hit.origin,"target_cell":target.cell,
		"timing_adaptation":hit.get("timing_adaptation","legacy_cast_dispatch"),
		"cast_start_tick":hit.get("cast_start_tick",tick),"cast_target_cell":hit.get("cast_target_cell",hit.target_cell)}
	if hit.has("mine_id"):damage_payload.mine_id=hit.mine_id
	_emit("damage",damage_payload)
	if target.hp>0 and hit.has("stun_seconds"):
		# Duration resistance mapping is an autochess approximation, not an engine dump.
		var stun_ticks:=_ticks(hit.stun_seconds*100.0/maxf(1,stat(target,"OppressionResist")))
		target.stun_until=maxi(target.stun_until,tick+stun_ticks)
		_cancel_dash(target,"stun")
		_emit("stun",{"actor_id":source.id,"target_id":target.id,"until_tick":target.stun_until,"duration_ticks":stun_ticks})
	if target.hp>0 and hit.has("knockback"):_knockback(source,target,hit.knockback)
	if source.character_id=="hina" and hit.component!="echo" and not target.in_cover and target.hp>0:
		if options.hina_echo_per_hit or hit.hit_index==hit.hit_count-1:
			var echo:Dictionary=hit.duplicate(true)
			echo.atk_ratio=_characters.hina.sub.echoAtkRatio;echo.component="echo"
			echo.erase("stun_seconds");echo.erase("knockback")
			_resolve_hit(echo)

	if source.character_id in ["iori","nonomi"] and hit.component!="echo" and target.hp>0:
		var sub:Dictionary=_characters[source.character_id].sub
		var active:bool=not source.in_cover if source.character_id=="iori" else target.size_class=="large"
		var per_hit:bool=options.iori_echo_per_hit if source.character_id=="iori" else options.nonomi_echo_per_hit
		if active and (per_hit or hit.hit_index==hit.hit_count-1):
			var echo:Dictionary=hit.duplicate(true)
			echo.atk_ratio=sub.echoAtkRatio;echo.component="echo";echo.can_crit=sub.canCrit
			echo.erase("stun_seconds");echo.erase("knockback")
			_resolve_hit(echo)

func _heal(source: Dictionary,target: Dictionary,ratio: float,ability: String,cast_context:Dictionary={}) -> void:
	if target.hp<=0:return
	var native_raw:=int(floor(stat(source,"HealPower")*ratio))
	var multiplier:=_overtime_sustain_multiplier()
	var raw:=int(floor(native_raw*multiplier))
	var amount:=mini(raw,target.max_hp-target.hp)
	target.hp+=amount
	var payload:Dictionary={"actor_id":source.id,"target_id":target.id,"character_id":source.character_id,"ability":ability,
		"amount":amount,"raw_amount":raw,"hp":target.hp,"max_hp":target.max_hp}
	if not cast_context.is_empty():
		payload.cast_start_tick=cast_context.cast_start_tick;payload.cast_target_cell=cast_context.target_cell
		payload.origin=cast_context.origin;payload.target_cell=target.cell
		payload.component=cast_context.get("component","");payload.hit_index=cast_context.get("hit_index",0);payload.hit_count=cast_context.get("hit_count",1)
	if options.overtime_enabled and tick>=_ticks(options.overtime_start_seconds):
		payload.native_raw_amount=native_raw;payload.overtime_multiplier=multiplier
	_emit("heal",payload)

func _shield(u: Dictionary,ratio: float,until: int,ability: String) -> void:
	var native_raw:=int(floor(stat(u,"HealPower")*ratio))
	var multiplier:=_overtime_sustain_multiplier()
	u.shield=int(floor(native_raw*multiplier));u.shield_until=until
	var payload:Dictionary={"actor_id":u.id,"amount":u.shield,"until_tick":until,"ability":ability}
	if options.overtime_enabled and tick>=_ticks(options.overtime_start_seconds):
		payload.native_raw_amount=native_raw;payload.overtime_multiplier=multiplier
	_emit("shield",payload)

func _buff(u: Dictionary,id: String,stat_name: String,fraction: float,until: int,ability: String) -> void:
	u.buffs[id]={"stat":stat_name,"fraction":fraction,"until":until}
	_emit("buff",{"actor_id":u.id,"character_id":u.character_id,"buff_id":id,"stat":stat_name,"fraction":fraction,"until_tick":until,"ability":ability})

func set_cover(id: int,in_cover: bool) -> bool:
	var u=_unit(id)
	if u==null or u.hp<=0 or phase=="finished":return false
	if phase=="prepare":u.in_cover=in_cover
	else:_cover_changes.append({"id":id,"in_cover":in_cover})
	return true

func _apply_cover_changes() -> void:
	var queued:Array=_cover_changes
	_cover_changes=[]
	for change in queued:
		var u=_unit(change.id)
		if u==null or u.hp<=0:continue
		var entered:bool=change.in_cover and not u.in_cover
		u.in_cover=change.in_cover
		if entered and u.character_id=="yuuka" and tick>=u.cover_ready:
			var sub:Dictionary=_characters.yuuka.sub
			u.cover_ready=tick+_ticks(sub.trigger.internalCooldownSeconds)
			_heal(u,u,sub.healPowerRatio,"sub")

func stat(u: Dictionary,name: String) -> float:
	return _stat_value(u,name,units)

func _stat_value(u: Dictionary,name: String,allies: Array) -> float:
	if name=="MaxHP":return float(u.max_hp)
	var base:float=u.base_stats.get(name,0.0)
	var bonus:=0.0
	var enhanced:Dictionary=_characters[u.character_id].enhanced
	if enhanced.stat==name:bonus+=enhanced.bonusFraction
	for buff in u.buffs.values():
		if buff.stat==name and buff.until>tick:bonus+=buff.fraction
	if name=="OppressionResist":
		for ally in allies:
			if ally.team==u.team and ally.hp>0 and ally.character_id=="serina":
				bonus+=_characters.serina.sub.bonusFraction
				break # Duplicate identical auras do not stack.
	var merge:=1.0
	if u.star==2:
		if name=="MaxHP":merge+=options.merge_hp_bonus
		if name=="AttackPower":merge+=options.merge_atk_bonus
	# Archived SchaleDB getTotal: round to four decimals, then Math.round.
	var total:float=base*maxf(0.2,1.0+bonus)*merge
	var rounded_four:float=round(total*10000.0)/10000.0
	return maxf(0.0,floor(rounded_four+0.5))

func _refresh_stats() -> void:
	for u in units:
		for name in u.base_stats:u.stats[name]=stat(u,name)
		u.damage=int(floor(stat(u,"AttackPower")))
		u.energy=0 if u.star==1 else int(clampf(1.0-float(u.skill_ready-tick)/maxi(1,u.skill_cooldown_ticks),0.0,1.0)*100)

func defense_multiplier(defense: float,flat_penetration: float=0.0,penetration_rate: float=1.0) -> float:
	return 10000000.0/(maxf(defense-flat_penetration,0.0)*penetration_rate*6000.0+10000000.0)
func hit_probability(accuracy: float,evasion: float) -> float:
	return clampf(2000.0/(maxf(evasion-accuracy,0.0)*3.0+2000.0),0,1)
func critical_probability(critical: float,resistance: float) -> float:
	return clampf(1.0-4000000.0/(maxf(critical-resistance,0.0)*6000.0+4000000.0),0,1)
func type_multiplier(damage_type: String,armor: String) -> float:
	if armor=="Structure":return 1.0
	return _data.typeEffectivenessRaw.get(damage_type,{}).get(armor,10000)/10000.0
func damage_components(source: Dictionary,target: Dictionary,ratio: float,critical: bool=false,stability: float=1.0) -> Dictionary:
	var defense:=defense_multiplier(stat(target,"DefensePower"))
	var affinity:=type_multiplier(source.damage_type,target.armor_type)
	var crit:float=maxf(0.0,(stat(source,"CriticalDamageRate")-stat(target,"CriticalDamageResistRate"))/10000.0) if critical else 1.0
	var level:=clampf(1.0-(target.level-source.level)*0.02,0.4,1.0)
	var reduction:=1.0
	var sub:Dictionary=_characters[target.character_id].sub
	if sub.trigger.kind=="while_reloading" and target.reload_until>tick:reduction=1.0-sub.damageTakenReductionFraction
	var raw:float=stat(source,"AttackPower")*ratio*defense*affinity*crit*stability*options.terrain_multiplier*level*reduction
	return {"raw":raw,"defense_multiplier":defense,"type_multiplier":affinity,"critical_multiplier":crit,"stability_multiplier":stability,"level_multiplier":level,"damage_taken_multiplier":reduction}

func can_attack(attacker: Dictionary,target: Dictionary,reach: float=-1.0) -> bool:
	if reach<0:reach=attacker.range
	if target.hp<=0 or attacker.cell.distance_to(target.cell)>reach+0.00001:return false
	return not line_of_sight.is_valid() or line_of_sight.call(attacker.cell,target.cell)

func _target(u: Dictionary,reach: float=-1.0):
	if u.taunt_until>tick:
		var taunter=_unit(u.taunt_source_id)
		if taunter!=null and taunter.hp>0 and taunter.team!=u.team:
			return taunter if reach<0 or can_attack(u,taunter,reach) else null
	var best=null;var best_distance:=INF
	for enemy in units:
		if enemy.hp<=0 or enemy.team==u.team:continue
		if reach>=0 and not can_attack(u,enemy,reach):continue
		var d:float=u.cell.distance_to(enemy.cell)
		if d<best_distance-0.000001:best=enemy;best_distance=d
	return best

# Pure coverage ranking at the offensive EX dispatch boundary only. Geometry
# comes from the same helpers as dispatch; overlapping hits count once here.
func _area_ex_target(u:Dictionary,skill:Dictionary,reach:float):
	if u.taunt_until>tick:
		var taunter=_unit(u.taunt_source_id)
		if taunter!=null and taunter.hp>0 and taunter.team!=u.team:
			return taunter if can_attack(u,taunter,reach) else null
	var candidates:Array=[];var best_count:=-1;var nearest:=INF
	for enemy in units:
		if enemy.hp<=0 or enemy.team==u.team or not can_attack(u,enemy,reach):continue
		var count:=_area_ex_coverage(u,enemy,skill)
		var distance:float=u.cell.distance_to(enemy.cell)
		if count>best_count:
			best_count=count;nearest=distance;candidates=[]
		if count==best_count:
			nearest=minf(nearest,distance)
			candidates.append({"unit":enemy,"distance":distance})
	var best=null
	# Apply the existing nearest tolerance against the actual minimum, then ID.
	# Two passes avoid iteration-dependent results for chains of near-ties.
	for candidate in candidates:
		if candidate.distance>nearest+0.000001:continue
		if best==null or candidate.unit.id<best.id:best=candidate.unit
	return best

func _area_ex_coverage(u:Dictionary,target:Dictionary,skill:Dictionary)->int:
	var victims:Array=[]
	match skill.kind:
		"fan_damage","fan_damage_knockback_stun","charge_scaled_line_damage","line_damage_with_target_falloff":
			victims=_shape_targets(u,target,skill.shapeSource[0])
		"three_shot_target_then_rear_fan":
			victims=[target]
			victims.append_array(_rear_fan_targets(u,target,skill.shapeSource[0]))
		"direct_shot_then_explosion":
			victims=[target]
			victims.append_array(_circle_targets(u,target.cell,skill.shapeSource[0].Radius/options.source_units_per_world_unit))
		"three_circle_damage":
			for center in _three_circle_centers(u,target,skill):
				victims.append_array(_circle_targets(u,center,skill.shapeSource[0].Radius/options.source_units_per_world_unit))
	var unique:Dictionary={}
	for victim in victims:unique[victim.id]=true
	return unique.size()

func _three_circle_centers(u:Dictionary,target:Dictionary,skill:Dictionary)->Array[Vector2]:
	var centers:Array[Vector2]=[]
	var direction:Vector2=u.cell.direction_to(target.cell)
	var sideways:=Vector2(-direction.y,direction.x)
	for i in range(int(skill.areaCount)):
		centers.append(target.cell+sideways*(i-(skill.areaCount-1)*0.5)*options.mutsuki_ex_circle_spacing_world_units)
	return centers

func _normal_target(u: Dictionary):
	if options.normal_target_policies[u.team]=="nearest":return _target(u,u.range)
	if u.taunt_until>tick:
		var taunter=_unit(u.taunt_source_id)
		if taunter!=null and taunter.hp>0 and taunter.team!=u.team:
			return taunter if can_attack(u,taunter,u.range) else null
	var best=null;var best_distance:=INF
	for enemy in units:
		if enemy.hp<=0 or enemy.team==u.team or not can_attack(u,enemy,u.range):continue
		var distance:float=u.cell.distance_squared_to(enemy.cell)
		if best!=null:
			# Source max HP with the supported merge bonus is <= 3,025,960;
			# these exact integer cross-products therefore fit safely in int64.
			var left:int=int(enemy.hp)*int(best.max_hp)
			var right:int=int(best.hp)*int(enemy.max_hp)
			if left>right:continue
			if left==right and (distance>best_distance or (distance==best_distance and enemy.id>=best.id)):continue
		best=enemy;best_distance=distance
	return best

func _heal_target(u: Dictionary,reach: float):
	var best=null;var best_score:=INF
	for ally in units:
		if ally.team!=u.team or ally.hp<=0 or not can_attack(u,ally,reach):continue
		var score:float=float(ally.hp)/ally.max_hp if options.serina_target_by_hp_fraction else float(ally.hp)
		if score<best_score:best=ally;best_score=score
	return best

func _circle_targets(u: Dictionary,center: Vector2,radius: float) -> Array:
	var result:Array=[]
	for enemy in units:
		if enemy.team!=u.team and enemy.hp>0 and enemy.cell.distance_to(center)<=radius+0.000001:
			if not line_of_sight.is_valid() or line_of_sight.call(center,enemy.cell):result.append(enemy)
	return result

func _shape_targets(u: Dictionary,target: Dictionary,shape: Dictionary) -> Array:
	var result:Array=[]
	var direction:Vector2=u.cell.direction_to(target.cell)
	if direction==Vector2.ZERO:direction=Vector2.UP if u.team==0 else Vector2.DOWN
	for enemy in units:
		if enemy.hp<=0 or enemy.team==u.team:continue
		if line_of_sight.is_valid() and not line_of_sight.call(u.cell,enemy.cell):continue
		var offset:Vector2=enemy.cell-u.cell
		var forward:float=offset.dot(direction)
		if forward<0:continue
		if shape.Type=="Fan":
			# Source Degree is preserved; interpreting it as full angle is adaptation.
			if offset.length()<=shape.Radius/options.source_units_per_world_unit and absf(direction.angle_to(offset))<=deg_to_rad(shape.Degree*0.5)+0.000001:result.append(enemy)
		elif shape.Type=="Obb":
			var lateral:float=absf(offset.cross(direction))
			if forward<=shape.Height/options.source_units_per_world_unit and lateral<=shape.Width/options.source_units_per_world_unit*0.5:result.append(enemy)
	return result

func _rear_fan_targets(u:Dictionary,target:Dictionary,shape:Dictionary)->Array:
	var result:Array=[]
	var direction:Vector2=u.cell.direction_to(target.cell)
	for enemy in units:
		if enemy.id==target.id or enemy.team==u.team or enemy.hp<=0:continue
		var offset:Vector2=enemy.cell-target.cell
		if offset.dot(direction)<0:continue
		if offset.length()>shape.Radius/options.source_units_per_world_unit:continue
		if absf(direction.angle_to(offset))>deg_to_rad(shape.Degree*0.5)+0.000001:continue
		if line_of_sight.is_valid() and not line_of_sight.call(target.cell,enemy.cell):continue
		result.append(enemy)
	return result

func _pack_destination(target: Dictionary) -> Vector2:
	var direction:float=1.0 if target.team==0 else -1.0
	for shift in [Vector2(0,direction),Vector2(1,0),Vector2(-1,0),Vector2(0,-direction)]:
		var point:Vector2=target.cell+shift*options.healing_pack_offset
		if _inside(point) and _free(point,target.id) and _segment_clear(target.cell,point):return point
	return target.cell

func _nearest_ally(source: Dictionary,point: Vector2):
	var best=null;var distance:=INF
	for ally in units:
		if ally.team!=source.team or ally.hp<=0:continue
		var d:float=ally.cell.distance_to(point)
		if d<distance:distance=d;best=ally
	return best

func _update_packs() -> void:
	var remaining:Array=[]
	for pack in _packs:
		var source=_unit(pack.source);var target=_unit(pack.target)
		if source==null or source.hp<=0 or target==null or target.hp<=0 or tick>=pack.expires:continue
		if target.cell.distance_to(pack.cell)<=0.16:
			_heal(source,target,pack.ratio,"ex")
			_emit("pack_collected",{"actor_id":source.id,"target_id":target.id,"cell":pack.cell})
		else:remaining.append(pack)
	_packs=remaining

func _knockback(source: Dictionary,target: Dictionary,distance: float) -> void:
	var direction:Vector2=source.cell.direction_to(target.cell)
	var point:Vector2=target.cell+direction*distance
	if _inside(point) and _free(point,target.id) and _segment_clear(target.cell,point):
		var origin:Vector2=target.cell
		_cancel_dash(target,"knockback")
		_clear_aim(target,"knockback")
		target.cell=point;target.last_moved_tick=tick;target.stationary=false
		_update_conditional_state(target)
		_emit("knockback",{"actor_id":source.id,"target_id":target.id,"from":origin,"to":point})

func _path_step(u: Dictionary,target: Vector2,reach: float=-1.0) -> Vector2:
	if reach<0:reach=u.range
	if path_step.is_valid():return path_step.call(u,target,reach)
	var origin:Vector2=u.cell
	var gap:=origin.distance_to(target)
	var travel:=minf(SPEED*STEP_SECONDS,maxf(0.0,gap-maxf(0.0,reach-0.12)))
	if travel<0.000001:return origin
	var direction:=origin.direction_to(target)
	var best:=origin;var distance:=gap
	for angle in [0.0,0.35,-0.35,0.7,-0.7,1.05,-1.05,1.4,-1.4,1.5,-1.5,1.52,-1.52,1.55,-1.55]:
		var point:=origin+direction.rotated(angle)*travel
		var remaining:=point.distance_to(target)
		if _inside(point) and _free(point,u.id) and _segment_clear(origin,point) and remaining<distance-0.000001:
			best=point;distance=remaining
	return best

func _inside(point: Vector2) -> bool:
	return point.is_finite() and absf(point.x)<=options.arena_half-RADIUS and absf(point.y)<=options.arena_half-RADIUS
func _free(point: Vector2,except_id: int) -> bool:
	if position_free.is_valid() and not position_free.call(point,RADIUS):return false
	for u in units:
		if u.id!=except_id and u.hp>0 and point.distance_to(u.cell)<RADIUS*2-0.000001:return false
	return true
func _segment_clear(a: Vector2,b: Vector2) -> bool:
	return not segment_free.is_valid() or segment_free.call(a,b,RADIUS)
func _deployment(team: int,point: Vector2) -> bool:
	return point.y>=RADIUS if team==0 else point.y<=-RADIUS
func _unit(id: int):
	for u in units:
		if u.id==id:return u
	return null
func _ticks(seconds: float) -> int:
	return maxi(1,int(ceil(seconds/STEP_SECONDS-0.00000001)))
func _number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))
func _check_finish() -> void:
	var alive:Array=[0,0];var hp:Array=[0,0];var maximum:Array=[0,0]
	for u in units:
		if u.hp>0:alive[u.team]+=1
		hp[u.team]+=u.hp;maximum[u.team]+=u.max_hp
	if alive[0]==0 or alive[1]==0:_end(-1 if alive[0]==0 and alive[1]==0 else (0 if alive[1]==0 else 1),"elimination")
	elif tick>=options.max_ticks:
		_end(-1,"timeout") # Match rules require elimination for a win.
func _end(team: int,reason: String) -> void:
	for u in units:_cancel_dash(u,"round_end")
	if units.any(func(u):return u.character_id=="asuna"):_refresh_stats()
	phase="finished";winner=team;_pending=[];_packs=[];_mines=[];_cover_changes=[]
	_emit("finished",{"winner":winner,"reason":reason})
func _emit(kind: String,payload: Dictionary) -> void:
	payload["type"]=kind;payload["tick"]=tick;payload["event_id"]="%d:%d"%[tick,events.size()]
	events.append(payload)


func _update_conditional_states()->void:
	for u in units:
		if u.hp>0:_update_conditional_state(u)

func _update_conditional_state(u:Dictionary)->void:
	u.stationary=u.last_moved_tick<tick
	var sub:Dictionary=_characters[u.character_id].sub
	if sub.trigger.kind=="while_stationary":
		var id:String=u.character_id+"_stationary"
		if u.stationary and not u.buffs.has(id):
			_buff(u,id,sub.stat,sub.bonusFraction,options.max_ticks+1,"sub")
			u.buffs[id].condition="while_stationary"
		elif not u.stationary and u.buffs.has(id):
			u.buffs.erase(id);_emit("buff_expired",{"actor_id":u.id,"buff_id":id,"reason":"movement"})
	u.damage_taken_multiplier=1.0-sub.damageTakenReductionFraction if sub.trigger.kind=="while_reloading" and u.reload_until>tick else 1.0

func _place_mines(u:Dictionary,hit:Dictionary)->void:
	if u.hp<=0:return
	var skill:Dictionary=_characters[u.character_id].basic
	var sideways:=Vector2(-hit.direction.y,hit.direction.x)
	for i in range(int(skill.mineCount)):
		var point:Vector2=hit.origin+hit.direction*options.mutsuki_mine_forward_world_units+sideways*(i-(skill.mineCount-1)*0.5)*options.mutsuki_mine_lateral_spacing_world_units
		if not _inside(point):
			_emit("mine_placement_blocked",{"actor_id":u.id,"cell":point,"reason":"outside_arena"});continue
		var mine:Dictionary={"id":_next_mine_id,"source":u.id,"cell":point,"armed_tick":tick,
			"expires":tick+_ticks(skill.lifetimeSeconds),"trigger_radius":options.mutsuki_mine_trigger_radius_world_units,
			"explosion_radius":skill.shapeSource[0].Radius/options.source_units_per_world_unit,
			"damage":skill.damagePerMine.duplicate(true),"cast_context":hit.cast_context.duplicate(true)}
		_next_mine_id+=1;_mines.append(mine)
		_emit("mine_placed",{"actor_id":u.id,"mine_id":mine.id,"cell":point,"expires_tick":mine.expires,"trigger_radius":mine.trigger_radius,"explosion_radius":mine.explosion_radius,"geometry_adaptation":"autochess_explicit_mine_options"})

func _update_mines()->void:
	var remaining:Array=[]
	for mine in _mines:
		var source=_unit(mine.source)
		if source==null or source.hp<=0:
			_emit("mine_removed",{"actor_id":mine.source,"mine_id":mine.id,"reason":"source_dead"});continue
		if tick>=mine.expires:
			_emit("mine_expired",{"actor_id":mine.source,"mine_id":mine.id});continue
		if not _circle_targets(source,mine.cell,mine.trigger_radius).is_empty():
			var context:Dictionary=mine.cast_context.duplicate(true);context.target_cell=mine.cell;context.damage_origin=mine.cell;context.mine_id=mine.id
			_damage_pattern(source,_circle_targets(source,mine.cell,mine.explosion_radius),mine.damage,"basic",1,{},"mine",1,context)
			_emit("mine_triggered",{"actor_id":mine.source,"mine_id":mine.id,"cell":mine.cell,"radius":mine.explosion_radius})
		else:remaining.append(mine)
	_mines=remaining

func _remove_dead_owner_mines()->void:
	var remaining:Array=[]
	for mine in _mines:
		var source=_unit(mine.source)
		if source!=null and source.hp>0:remaining.append(mine)
		else:_emit("mine_removed",{"actor_id":mine.source,"mine_id":mine.id,"reason":"source_dead"})
	_mines=remaining

func _clear_invalid_taunts()->void:
	for u in units:
		if u.taunt_source_id<0:continue
		var taunter=_unit(u.taunt_source_id)
		if u.hp<=0 or tick>=u.taunt_until or taunter==null or taunter.hp<=0:
			u.taunt_source_id=-1;u.taunt_until=0
			_emit("taunt_expired",{"actor_id":u.id})


func _periodic_sub(u:Dictionary)->void:
	var sub:Dictionary=_characters[u.character_id].sub
	u.sub_ready=tick+_ticks(sub.trigger.intervalSeconds)
	_buff(u,u.character_id+"_sub",sub.stat,sub.bonusFraction,tick+_ticks(sub.durationSeconds),"sub")

func _single_contact_offset(character:String,ability:String,component:String,duration:int,fraction:float)->int:
	var contacts:=_native_contact_ticks(character,ability,component,1)
	var offset:int=contacts[0] if contacts.size()==1 else maxi(1,int(duration*fraction))
	return maxi(offset,_native_contact_lower_bound(character,ability,component))

func _threshold_ally_target(u:Dictionary,skill:Dictionary,reach:float):
	var best=null;var score:=INF
	for ally in units:
		if ally.team!=u.team or ally.id==u.id or ally.hp<=0 or not can_attack(u,ally,reach):continue
		var fraction:float=float(ally.hp)/ally.max_hp
		if fraction>=skill.trigger.thresholdHpRatio:continue
		if fraction<score-0.000001 or (is_equal_approx(fraction,score) and (best==null or ally.id<best.id)):
			best=ally;score=fraction
	return best

func _allied_circle_targets(u:Dictionary,center:Vector2,radius:float)->Array:
	var result:Array=[]
	for ally in units:
		if ally.team!=u.team or ally.hp<=0 or ally.cell.distance_to(center)>radius+0.000001:continue
		if line_of_sight.is_valid() and not line_of_sight.call(center,ally.cell):continue
		result.append(ally)
	return result

func _support_circle_target(u:Dictionary,skill:Dictionary,reach:float):
	# Automatic selection is explicitly separate from the source damage/heal data.
	# Prioritize endangered allies; then combined effective healing and damage.
	var radius:float=skill.shapeSource[0].Radius/options.source_units_per_world_unit
	var candidates:Array=[];var living:Array=[]
	for unit in units:
		if unit.hp>0:living.append(unit);candidates.append({"id":unit.id,"cell":unit.cell})
	for i in range(living.size()):
		for j in range(i+1,living.size()):
			if living[i].cell.distance_to(living[j].cell)<=radius*2.0:
				candidates.append({"id":mini(living[i].id,living[j].id),"cell":(living[i].cell+living[j].cell)*0.5})
	var best=null;var best_urgent:=-1;var best_value:=-1.0
	var raw_heal:float=floor(stat(u,"HealPower")*skill.healPowerRatio)
	for candidate in candidates:
		if u.cell.distance_to(candidate.cell)>reach+0.000001:continue
		if line_of_sight.is_valid() and not line_of_sight.call(u.cell,candidate.cell):continue
		var urgent:=0;var value:=0.0
		for ally in _allied_circle_targets(u,candidate.cell,radius):
			var effective:=minf(raw_heal,ally.max_hp-ally.hp)
			value+=effective/maxf(1,ally.max_hp)
			if effective>0 and float(ally.hp)/ally.max_hp<0.5:urgent+=1
		for enemy in _circle_targets(u,candidate.cell,radius):
			value+=minf(enemy.hp,damage_components(u,enemy,skill.damage.totalAtkRatio).raw)/maxf(1,enemy.max_hp)
		if value<=0:continue
		if urgent>best_urgent or (urgent==best_urgent and value>best_value+0.000001):
			best=candidate;best_urgent=urgent;best_value=value
	return best


## Explicit autochess displacement: source animation window, not Unity controller parity.
## Max distance 2 world units, frozen forward direction, movement T+8 through T+39.
func _begin_dash(u:Dictionary,skill:Dictionary)->void:
	_cancel_dash(u,"recast")
	var target=_target(u)
	var direction:Vector2=u.cell.direction_to(target.cell) if target!=null else Vector2.UP if u.team==0 else Vector2.DOWN
	u.dash={"start_tick":tick+8,"end_tick":tick+40,"direction":direction,"origin":u.cell,"active":false,"destination":DirectionalDash.legal_prefix(u.cell,u.cell+direction*2.0,u.id,units,options.arena_half,RADIUS,position_free,segment_free)}
	_clear_aim(u,"dash_cast")

func _update_dashes()->void:
	for u in units:
		if not u.has("dash") or u.dash.is_empty():continue
		if u.hp<=0 or tick<u.stun_until:
			_cancel_dash(u,"death" if u.hp<=0 else "stun");continue
		var dash:Dictionary=u.dash
		if tick>=dash.end_tick:
			_cancel_dash(u,"complete");continue
		if tick<dash.start_tick:continue
		if not dash.active:
			var available:Vector2=DirectionalDash.legal_prefix(u.cell,dash.destination,u.id,units,options.arena_half,RADIUS,position_free,segment_free)
			if u.cell.distance_to(dash.origin)>0.000001 or available.distance_to(dash.destination)>0.000001:
				_cancel_dash(u,"windup_obstructed");continue
			if u.cell.distance_to(dash.destination)<0.001:
				_cancel_dash(u,"blocked");continue
			dash.active=true
			var evade:Dictionary=_characters[u.character_id].ex.evasion
			_buff(u,"asuna_ex_dash_evasion",evade.stat,evade.bonusFraction,dash.end_tick,"ex")
		var fraction:float=float(tick-dash.start_tick+1)/float(dash.end_tick-dash.start_tick)
		var desired:Vector2=dash.origin.lerp(dash.destination,fraction)
		var next:Vector2=DirectionalDash.legal_prefix(u.cell,desired,u.id,units,options.arena_half,RADIUS,position_free,segment_free)
		var from:Vector2=u.cell
		if from.distance_to(next)>0.000001:
			u.cell=next;u.last_moved_tick=tick;u.stationary=false
			_emit("dash_move",{"actor_id":u.id,"character_id":u.character_id,"from":from,"to":next,"duration":STEP_SECONDS,"ability":"ex"})
		if next.distance_to(desired)>0.000001:_cancel_dash(u,"blocked")

func _cancel_dash(u:Dictionary,reason:String)->void:
	if not u.has("dash"):return
	if reason in ["death","round_end"]:
		for buff_id in ["asuna_ex_attack_speed","asuna_sub_attack_speed"]:
			if u.buffs.has(buff_id):
				u.buffs.erase(buff_id)
				_emit("buff_expired",{"actor_id":u.id,"buff_id":buff_id,"reason":reason})
	if u.dash.is_empty():return
	u.dash={}
	if u.buffs.has("asuna_ex_dash_evasion"):
		u.buffs.erase("asuna_ex_dash_evasion")
		_emit("buff_expired",{"actor_id":u.id,"buff_id":"asuna_ex_dash_evasion","reason":reason})
	_emit("dash_finished",{"actor_id":u.id,"character_id":u.character_id,"reason":reason,"cell":u.cell})
