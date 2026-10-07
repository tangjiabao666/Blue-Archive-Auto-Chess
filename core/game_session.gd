extends RefCounted
const ProcessBatch=preload("res://core/offscreen_process_batch.gd")
const OffscreenDuel=preload("res://core/offscreen_duel.gd")
const ArenaHooks=preload("res://core/combat_arena_hooks.gd")
const Formations=preload("res://core/opponent_formations.gd")
const TacticalMatch=preload("res://core/tactical_match.gd")
const MatchRules=preload("res://core/prototype_match.gd")
const CharacterClock=preload("res://core/character_clock.gd")
const TacticalMaps=preload("res://core/tactical_maps.gd")
const Navigation=preload("res://core/obstacle_navigation.gd")
const ACTIVE=["shiroko","hoshino","hina","aru","yuuka","aris","serika","iori","tsubaki","nonomi","mutsuki","haruna","koharu","asuna"]
# Autochess gold prices; source EX energy costs remain unchanged in character data.
const COSTS={"shiroko":2,"hoshino":3,"hina":4,"aru":3,"yuuka":2,"aris":4,"serika":1,"iori":4,"tsubaki":2,"nonomi":3,"mutsuki":2,"haruna":3,"koharu":3,"asuna":1}
# Frozen Save1–4 catalog. Future roster changes must not reinterpret old saves.
const LEGACY_SAVE_CATALOG=[
	{"id":"shiroko","name":"白子","cost":2,"ex_cooldown":15.0},
	{"id":"hoshino","name":"星野","cost":3,"ex_cooldown":25.0},
	{"id":"hina","name":"日奈","cost":4,"ex_cooldown":40.0},
	{"id":"aru","name":"阿露","cost":3,"ex_cooldown":25.0},
	{"id":"yuuka","name":"优香","cost":2,"ex_cooldown":20.0},
	{"id":"aris","name":"爱丽丝","cost":4,"ex_cooldown":35.0},
	{"id":"serika","name":"芹香","cost":1,"ex_cooldown":15.0},
	{"id":"iori","name":"伊织","cost":4,"ex_cooldown":20.0},
	{"id":"tsubaki","name":"椿","cost":2,"ex_cooldown":25.0},
	{"id":"nonomi","name":"野宫","cost":3,"ex_cooldown":30.0},
	{"id":"mutsuki","name":"睦月","cost":2,"ex_cooldown":25.0},
	{"id":"haruna","name":"晴奈","cost":3,"ex_cooldown":20.0},
	{"id":"koharu","name":"小春","cost":3,"ex_cooldown":20.0},
]
const SAVE_FORMAT:="blue-a-session"
const SAVE_VERSION:=10
const RULES_PROFILE_PC_SHORT:=3
const Pacing=preload("res://core/battle_pacing.gd")
const Health=preload("res://core/battle_outcome.gd")
const RULES_PROFILE_SURVIVAL:=0
const RULES_PROFILE_LEAGUE_V1:=1
const RULES_PROFILE_FIVE_UNIT:=2
const MAX_SAVE_BYTES:=1048576
const INITIAL_BASIC_DELAY_CAP_SECONDS:=5.0
const AI_ACTIVE_BUDGET_US:=2000
const AI_SETTLEMENT_BUDGET_US:=6000
const AI_MAX_STEPS_PER_ADVANCE:=128
const HALF_SIZE=ArenaHooks.HALF_SIZE
const OBSTACLES=ArenaHooks.OBSTACLES
var rules=MatchRules.new()
var clock=CharacterClock.new()
var navigation=Navigation.new()
var arena_hooks=ArenaHooks.new()
var profiles:Dictionary={}
var catalog:Array=[]
var positions:Dictionary={}
var manual_positions:Dictionary={}
var id_to_unit:Dictionary={}
var paused:=false
var showing_result:=false
var last_error:=""
var seed:=1
var _normal_target_policy:="nearest"
var _combat_mode:="legacy"
var _match_format:="survival"
var _rules_profile:=RULES_PROFILE_SURVIVAL
var _arena_version:=0
var _arena:Dictionary={}
var _battle_id:=""
var _feedback:Dictionary={}
var _feedback_units:Dictionary={}
var _ex_target_hits:Dictionary={}
var process_ai_enabled:=false
var _process_batch
var _ai_execution_mode:="cooperative"
var _process_diagnostics:Dictionary={}
var _ai_jobs:Array=[]
var _ai_last_status:Dictionary={}
var _ai_cursor:=0
var _ai_last_pump_steps:=0
var _ai_total_steps:=0
var _ai_pump_calls:=0
func _init()->void:
	profiles=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	last_error=navigation.configure(HALF_SIZE,OBSTACLES)
	for key in ACTIVE:
		var source:Dictionary=clock.sim.character_data(key)
		catalog.append({"id":key,"name":profiles.get(key,{}).get("display_name",key),"cost":COSTS[key],"ex_cooldown":5.0+5.0*source.get("ex",{}).get("originalCost",2)})
	_wire_navigation()
func _wire_navigation()->void:
	arena_hooks.bind(clock.sim,navigation,arena_config().obstacles)
func arena_config()->Dictionary:
	if _arena.is_empty():return {"id":"legacy","name":"原版战场","half_size":HALF_SIZE,"obstacles":OBSTACLES.duplicate(true)}
	return _arena.duplicate(true)
func _configure_arena()->void:
	_arena={"id":"legacy","name":"原版战场","half_size":HALF_SIZE,"obstacles":OBSTACLES.duplicate(true)}
	if _arena_version==1:
		var round_number:int=int(rules.snapshot().get("round",1))
		_arena=TacticalMaps.new().get_map(TacticalMaps.MAP_IDS[posmod(seed+round_number-1,3)])
	navigation=Navigation.new();last_error=navigation.configure(_arena.half_size,_arena.obstacles)
func match_format()->String:return _match_format
func rules_profile()->int:return _rules_profile
func combat_mode()->String:return _combat_mode
func new_game(new_seed:int=1,mode:String="legacy")->Dictionary:
	if mode not in ["legacy","tactical_v1"]:return {"ok":false,"error":"invalid_combat_mode"}
	if not last_error.is_empty():return {"ok":false,"error":last_error}
	var candidate=_make_rules("six_round_league" if mode=="tactical_v1" else "survival",RULES_PROFILE_PC_SHORT if mode=="tactical_v1" else RULES_PROFILE_SURVIVAL)
	var settings:Dictionary={"level_shop_odds":1,"reinforcement_recruitment":1}
	if mode=="tactical_v1":settings.max_level=5
	var result:Dictionary=candidate.new_match(new_seed,catalog,settings)
	if result.ok:
		_rules_profile=RULES_PROFILE_PC_SHORT if mode=="tactical_v1" else RULES_PROFILE_SURVIVAL
		rules=candidate;seed=new_seed;_combat_mode=mode;_arena_version=1 if mode=="tactical_v1" else 0;_match_format="six_round_league" if mode=="tactical_v1" else "survival"
		_reset_session()
	return result
func _reset_session()->void:
	var next_generation:int=clock.generation+1
	_cancel_ai_jobs();_ai_last_status.clear();last_error=""
	positions.clear();manual_positions.clear();id_to_unit.clear();paused=false;showing_result=false;_battle_id=""
	_normal_target_policy="nearest"
	_feedback.clear();_feedback_units.clear();_ex_target_hits.clear()
	# Per-actor route caches belong to the old simulation, not the checkpoint.
	_configure_arena()
	arena_hooks=ArenaHooks.new()
	clock=CharacterClock.new();clock.use_combat_mode(_combat_mode);clock.generation=next_generation;_wire_navigation()
## Only stable preparation is durable. A result screen already holds the next
## preparation rules; presentation flags and live worker jobs never enter JSON.
func export_save()->Dictionary:
	var state:Dictionary=rules.snapshot()
	if state.get("phase","")!="preparation" and not (_match_format=="six_round_league" and state.get("phase")=="finished"):return {"ok":false,"error":"save_requires_preparation"}
	if showing_result and state.phase=="preparation" and _arena_version==1:
		# Save next preparation against its next terrain without changing the
		# still-visible finished battle or its navigation.
		var checkpoint=get_script().new()
		checkpoint.rules=_make_rules(_match_format,_rules_profile)
		checkpoint.rules.restore(state);checkpoint._match_format=_match_format;checkpoint._rules_profile=_rules_profile;checkpoint.seed=seed;checkpoint._combat_mode=_combat_mode;checkpoint._arena_version=_arena_version
		checkpoint._reset_session();checkpoint._normal_target_policy=_normal_target_policy;checkpoint.positions=positions.duplicate(true);checkpoint.manual_positions=manual_positions.duplicate(true)
		checkpoint._prune_invalid_positions();checkpoint._sync_positions()
		return checkpoint.export_save()
	var encoded:Dictionary={}
	for id in positions:
		if not positions[id] is Vector2:return {"ok":false,"error":"invalid_placement"}
		encoded[id]=[positions[id].x,positions[id].y]
	var payload:Dictionary={"format":SAVE_FORMAT,"version":SAVE_VERSION,"seed":seed,"rules":state,
		"positions":encoded,"manual_positions":manual_positions.duplicate(true),"normal_target_policy":_normal_target_policy,"combat_mode":_combat_mode,"arena_version":_arena_version,"match_format":_match_format,"rules_profile":_rules_profile}
	var checked:Dictionary=_validate_save(payload)
	if not checked.ok:return {"ok":false,"error":checked.error}
	return {"ok":true,"error":"","data":payload.duplicate(true)}

## Validate everything before cancelling jobs or changing the live session.
## Loading a prebattle save intentionally starts that battle's preparation again.
func restore_save(payload:Dictionary)->Dictionary:
	var checked:Dictionary=_validate_save(payload)
	if not checked.ok:return {"ok":false,"error":checked.error}
	_combat_mode=checked.combat_mode;_arena_version=checked.arena_version;_match_format=checked.match_format;_rules_profile=checked.rules_profile
	rules=checked.rules;seed=checked.seed
	_reset_session()
	positions=checked.positions;manual_positions=checked.manual_positions
	_normal_target_policy=checked.normal_target_policy;_combat_mode=checked.combat_mode
	return {"ok":true,"error":""}

func _validate_save(payload:Dictionary)->Dictionary:
	var validator=MatchRules.new()
	if not validator._json_safe(payload):return {"ok":false,"error":"invalid_save_data"}
	if JSON.stringify(payload).to_utf8_buffer().size()>MAX_SAVE_BYTES:return {"ok":false,"error":"save_too_large"}
	var version:Variant=payload.get("version")
	if not validator._whole(version) or not int(version) in [1,2,3,4,5,6,7,8,9,SAVE_VERSION]:
		return {"ok":false,"error":"unsupported_save_version"}
	var keys:Array=["format","version","seed","rules","positions","manual_positions"]
	if int(version)>=3:keys.append("normal_target_policy")
	if int(version)>=6:keys.append("combat_mode")
	if int(version)>=7:keys.append("arena_version")
	if int(version)>=8:keys.append("match_format")
	if int(version)>=9:keys.append("rules_profile")
	if not validator._exact_keys(payload,keys):return {"ok":false,"error":"invalid_save_schema"}
	if not payload.format is String or payload.format!=SAVE_FORMAT:
		return {"ok":false,"error":"unsupported_save_version"}
	var mode:Variant=payload.get("combat_mode","legacy")
	if not mode is String or mode not in ["legacy","tactical_v1"]:return {"ok":false,"error":"invalid_combat_mode"}
	var arena_version:Variant=payload.get("arena_version",0)
	if not validator._whole(arena_version) or int(arena_version) not in [0,1] or (mode=="legacy" and arena_version!=0):return {"ok":false,"error":"invalid_arena_version"}
	var format:Variant=payload.get("match_format","survival")
	if not format is String or format not in ["survival","six_round_league"]:return {"ok":false,"error":"invalid_match_format"}
	if format=="six_round_league":
		if mode!="tactical_v1" or int(arena_version)!=1:return {"ok":false,"error":"invalid_match_profile"}
		validator=TacticalMatch.new()
	# Old envelopes retain their historical cap and combat tuning. Save9 must
	# explicitly select a compatible profile; never infer a new profile from config.
	var profile:Variant=payload.get("rules_profile",RULES_PROFILE_LEAGUE_V1 if format=="six_round_league" else RULES_PROFILE_SURVIVAL)
	if not validator._whole(profile) or int(profile) not in [RULES_PROFILE_SURVIVAL,RULES_PROFILE_LEAGUE_V1,RULES_PROFILE_FIVE_UNIT,RULES_PROFILE_PC_SHORT]:return {"ok":false,"error":"invalid_rules_profile"}
	if int(version)<10 and profile==RULES_PROFILE_PC_SHORT:return {"ok":false,"error":"invalid_rules_profile"}
	validator=_make_rules(format,int(profile))
	if (format=="survival")!=(int(profile)==RULES_PROFILE_SURVIVAL):return {"ok":false,"error":"invalid_match_profile"}
	var policy:Variant=payload.get("normal_target_policy","nearest")
	if not policy is String or policy not in ["nearest","wounded"]:
		return {"ok":false,"error":"invalid_normal_target_policy"}
	if not payload.rules is Dictionary:
		return {"ok":false,"error":"invalid_save_rules"}
	# Version pairs are exact. Never reinterpret hybrids or partial new schemas.
	var restored:Dictionary
	if int(version)==1:restored=validator.restore_legacy_v4(payload.rules)
	elif int(version) in [2,3]:restored=validator.restore_legacy_v5(payload.rules)
	else:restored=validator.restore(payload.rules)
	if not restored.ok:
		return {"ok":false,"error":"invalid_save_rules"}
	var state:Dictionary=validator.snapshot()
	if state.phase!="preparation" and not (format=="six_round_league" and state.phase=="finished"):return {"ok":false,"error":"save_requires_preparation"}
	if not validator._whole(payload.seed) or payload.seed!=state.initial_seed:
		return {"ok":false,"error":"invalid_save_seed"}
	var expected=MatchRules.new()
	var expected_config:Dictionary={"level_shop_odds":1,"reinforcement_recruitment":state.config.reinforcement_recruitment}
	if int(profile) in [RULES_PROFILE_FIVE_UNIT,RULES_PROFILE_PC_SHORT]:
		expected_config.max_level=5;expected_config.reinforcement_recruitment=1
	if not expected.new_match(1,catalog,expected_config).ok:
		return {"ok":false,"error":"invalid_current_catalog"}
	var supported:Dictionary=expected.snapshot()
	var saved_catalog:Array=supported.catalog if int(version)>=5 else LEGACY_SAVE_CATALOG
	if state.catalog!=saved_catalog:return {"ok":false,"error":"unsupported_save_catalog"}
	if state.config!=supported.config:return {"ok":false,"error":"unsupported_save_config"}
	if not payload.positions is Dictionary or not payload.manual_positions is Dictionary:
		return {"ok":false,"error":"invalid_placements"}
	var player:Dictionary=validator.get_player()
	var owned:Dictionary={}
	for unit in player.units:owned[unit.id]=true
	var placement_nav=Navigation.new()
	var saved_arena:Dictionary={"half_size":HALF_SIZE,"obstacles":OBSTACLES}
	if arena_version==1:saved_arena=TacticalMaps.new().get_map(TacticalMaps.MAP_IDS[posmod(int(payload.seed)+int(state.round)-1,3)])
	if not placement_nav.configure(saved_arena.half_size,saved_arena.obstacles).is_empty():return {"ok":false,"error":"invalid_arena"}
	var restored_positions:Dictionary={}
	for id in payload.positions:
		var cell:Variant=payload.positions[id]
		if not owned.has(id) or not cell is Array or cell.size()!=2:
			return {"ok":false,"error":"invalid_placement_unit"}
		for coordinate in cell:
			if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
				return {"ok":false,"error":"invalid_placement_coordinate"}
		var point:=Vector2(float(cell[0]),float(cell[1]))
		if not point.is_finite() or point.y<0.35 or not placement_nav.is_free(point,0.35):
			return {"ok":false,"error":"invalid_placement_bounds"}
		restored_positions[id]=point
	for id in player.deployed:
		if not restored_positions.has(id):return {"ok":false,"error":"missing_deployed_placement"}
		for other in player.deployed:
			if id!=other and restored_positions.has(other) and restored_positions[id].distance_to(restored_positions[other])<0.7:
				return {"ok":false,"error":"overlapping_placements"}
	# Stored bench positions are remembered preferences, not active actors. They
	# may overlap the board; _sync_positions revalidates before redeployment.
	for id in payload.manual_positions:
		if not restored_positions.has(id) or not payload.manual_positions[id] is bool or not payload.manual_positions[id]:
			return {"ok":false,"error":"invalid_manual_placement"}
	# Only after the complete old state passes validation, expand a detached
	# snapshot and validate it again. Do not reroll shops, offers, IDs or RNG.
	if int(version)<5:
		state.catalog.append(supported.catalog.back().duplicate(true))
		if state.catalog!=supported.catalog or not validator.restore(state).ok:return {"ok":false,"error":"invalid_save_rules"}
	return {"ok":true,"error":"","rules":validator,"seed":int(payload.seed),
		"positions":restored_positions,"manual_positions":payload.manual_positions.duplicate(true),"normal_target_policy":policy,"combat_mode":mode,"arena_version":int(arena_version),"match_format":format,"rules_profile":int(profile)}

func phase()->String:
	var current_phase:String=rules.get_phase()
	if current_phase=="uninitialized":return "uninitialized"
	if current_phase=="finished":return "finished"
	if current_phase=="battle" and not last_error.is_empty():return "error"
	return "result" if showing_result else current_phase
func normal_target_policy()->String:
	return _normal_target_policy
func command(input:Dictionary)->Dictionary:
	var kind:Variant=input.get("type","")
	if not kind is String:return {"ok":false,"error":"invalid_command"}
	if kind in ["cast_ex","move"]:return _queue_local_tactical_command(input)
	if kind=="restart":
		var restarted:Dictionary=rules.execute(input)
		if restarted.ok:
			seed=int(rules.snapshot().initial_seed)
			_reset_session()
		return restarted
	if kind=="next_round":
		if not showing_result or rules.snapshot().phase!="preparation":return {"ok":false,"error":"没有待确认的回合结果"}
		showing_result=false;paused=false;clock.reset();_configure_arena();_wire_navigation();_prune_invalid_positions();_sync_positions();return {"ok":true,"error":""}
	if showing_result:return {"ok":false,"error":"请先继续下一回合"}
	if kind=="set_normal_target_policy":
		if phase()!="preparation":return {"ok":false,"error":"normal_target_requires_preparation"}
		if not rules._exact_keys(input,["type","policy"]) or not input.get("policy") is String or input.policy not in ["nearest","wounded"]:
			return {"ok":false,"error":"invalid_normal_target_policy"}
		_normal_target_policy=input.policy
		return {"ok":true,"error":""}
	var before:Dictionary=rules.snapshot()
	var before_positions:Dictionary=positions.duplicate(true) if kind=="start_battle" else {}
	var before_manual:Dictionary=manual_positions.duplicate(true) if kind=="start_battle" else {}
	var before_ids:Dictionary=id_to_unit.duplicate(true) if kind=="start_battle" else {}
	var result:Dictionary=rules.execute(input)
	if not result.ok:return result
	_sync_positions()
	if kind=="start_battle":
		var roster:=_battle_roster(result.battle)
		var candidate=CharacterClock.new();candidate.use_combat_mode(_combat_mode);var candidate_hooks=ArenaHooks.new()
		var candidate_navigation=Navigation.new()
		var error:String=candidate_navigation.configure(arena_config().half_size,arena_config().obstacles)
		candidate_hooks.bind(candidate.sim,candidate_navigation,arena_config().obstacles)
		if error.is_empty():error=candidate.sim.configure(roster,_battle_options(seed+int(result.battle.round),str(before.player_id),str(result.battle.opponent_id)))
		var prepared:Dictionary={"ok":false,"error":error}
		if error.is_empty():prepared=_prepare_ai_jobs(result.battle)
		if not prepared.ok:
			rules.restore(before);positions=before_positions;manual_positions=before_manual;id_to_unit=before_ids
			return {"ok":false,"error":prepared.error}
		candidate.generation=clock.generation+1
		clock=candidate;arena_hooks=candidate_hooks;navigation=candidate_navigation;_battle_id=result.battle.id
		clock.sim.start();paused=false
		_launch_ai_jobs(prepared.jobs)
		_begin_feedback(result.battle)
	return result
func _owned(player:Dictionary,id:String)->Dictionary:
	for unit in player.units:
		if unit.id==id:return unit
	return {}

func _prune_invalid_positions()->void:
	for id in positions.keys():
		if positions[id].y<0.35 or not navigation.is_free(positions[id],0.35):positions.erase(id);manual_positions.erase(id)
func _sync_positions()->void:
	var player:Dictionary=rules.get_player()
	for id in positions.keys():
		if _owned(player,id).is_empty():positions.erase(id);manual_positions.erase(id)
	# Reserve existing manual placements before returning bench units. Stale
	# stored bench positions must never displace an already fielded actor.
	var requested:Dictionary={}
	for id in player.deployed:
		if manual_positions.has(id) and positions.has(id):requested[id]=positions[id]
		positions.erase(id)
	for id in player.deployed:
		if requested.has(id) and _valid_placement(id,requested[id],player):positions[id]=requested[id]
		else:manual_positions.erase(id)
	for index in range(player.deployed.size()):
		var id:String=player.deployed[index]
		if positions.has(id):continue
		var candidates:Array[Vector2]=[Vector2((index-(player.deployed.size()-1)*0.5)*1.6,4.7)]
		for slot in range(7):candidates.append(Vector2(-4.8+slot*1.6,4.7))
		for point in candidates:
			if _valid_placement(id,point,player):positions[id]=point;break
func _valid_placement(id:String,point:Vector2,player:Dictionary)->bool:
	if point.y<0.35 or not navigation.is_free(point,0.35):return false
	for other in player.deployed:
		if other!=id and positions.has(other) and point.distance_to(positions[other])<0.7:return false
	return true
func place(unit_id:String,point:Vector2)->bool:
	if phase()!="preparation":return false
	var player:Dictionary=rules.get_player()
	if unit_id not in player.deployed or not _valid_placement(unit_id,point,player):return false
	positions[unit_id]=point;manual_positions[unit_id]=true;return true
## Bench drop is a single transaction: never deploy first and fail placement later.
func deployment_preview(unit_id:String,point:Vector2)->Dictionary:
	if phase()!="preparation":return {"ok":false,"error":"deployment_requires_preparation"}
	var player:Dictionary=rules.get_player()
	if unit_id not in player.bench:return {"ok":false,"error":"unit_not_on_bench"}
	if player.deployed.size()>=player.level:return {"ok":false,"error":"population_full"}
	if not point.is_finite() or not _valid_placement(unit_id,point,player):return {"ok":false,"error":"invalid_deployment_point"}
	return {"ok":true,"error":""}
func deploy_at(unit_id:String,point:Vector2)->Dictionary:
	var checked:Dictionary=deployment_preview(unit_id,point)
	if not checked.ok:return checked
	var candidate=_make_rules(_match_format,_rules_profile)
	var restored:Dictionary=candidate.restore(rules.snapshot())
	if not restored.ok:return restored
	var deployed:Dictionary=candidate.execute({"type":"deploy_unit","unit_id":unit_id})
	if not deployed.ok:return deployed
	var next_positions:Dictionary=positions.duplicate(true)
	var next_manual:Dictionary=manual_positions.duplicate(true)
	# Existing actors keep their visible positions when the bench adds a member.
	for id in rules.get_player().deployed:
		if next_positions.has(id):next_manual[id]=true
	next_positions[unit_id]=point;next_manual[unit_id]=true
	rules=candidate;positions=next_positions;manual_positions=next_manual
	return {"ok":true,"error":"","unit_id":unit_id}
func preview_roster()->Array:
	_sync_positions();id_to_unit.clear()
	var result:Array=[];var player:Dictionary=rules.get_player()
	for index in range(player.deployed.size()):
		var id:String=player.deployed[index];var unit:Dictionary=_owned(player,id)
		var preview:Dictionary=clock.sim.preview_unit(unit.character_id,unit.star,index,0,positions[id])
		preview.roster_unit_id=id;preview.presentation=profiles.get(unit.character_id,{})
		result.append(preview);id_to_unit[index]=id
	return result
## Scouting never changes rules, position allocations or actor selection maps.
func opponent_preview()->Dictionary:
	var result:Dictionary=rules.get_opponent_preview()
	if result.is_empty():return {}
	var army:Array=result.opponent_units
	var policy=Formations.new()
	result["formation"]=policy.style_for(str(result.opponent_id))
	result["formation_name"]=Formations.NAMES[result.formation]
	result["normal_target_policy"]=_participant_normal_target_policy(str(result.opponent_id))
	var cells:Array=_opponent_positions(army,str(result.opponent_id))
	result.erase("opponent_units");result["units"]=[]
	for index in range(army.size()):
		var unit:Dictionary=army[index]
		var preview:Dictionary=clock.sim.preview_unit(unit.character_id,unit.star,index+7,1,cells[index])
		preview.roster_unit_id=unit.id;preview.presentation=profiles.get(unit.character_id,{}).duplicate(true)
		result.units.append(preview)
	return result
func _opponent_positions(army:Array,opponent_id:String)->Array:
	var definitions:Dictionary={}
	for unit in army:definitions[unit.character_id]=clock.sim.character_data(unit.character_id)
	var policy=Formations.new()
	return policy.positions(army,definitions,policy.style_for(opponent_id),navigation)
func _opponent_cell(index:int,count:int)->Vector2:
	return Vector2((index-(count-1)*0.5)*1.6,-4.7)
func _battle_roster(battle:Dictionary)->Array:
	var result:Array=[];id_to_unit.clear()
	var enemy_cells:Array=_opponent_positions(battle.opponent_units,str(battle.get("opponent_id","")))
	for team in range(2):
		var army:Array=battle.player_units if team==0 else battle.opponent_units
		for index in range(army.size()):
			var unit:Dictionary=army[index];var id:int=index+team*7
			var point:Vector2=positions[unit.id] if team==0 else enemy_cells[index]
			result.append({"id":id,"team":team,"cell":point,"character_id":unit.character_id,"star":unit.star})
			id_to_unit[id]=unit.id
	return result
func advance(delta:float)->Array:
	if paused or phase()!="battle" or not is_finite(delta) or delta<=0:return []
	_pump_ai_jobs(AI_SETTLEMENT_BUDGET_US if clock.sim.phase=="finished" else AI_ACTIVE_BUDGET_US)
	var batch:Array=clock.advance(delta)
	_record_feedback(batch)
	if clock.sim.phase=="finished":
		for entry in _ai_jobs:
			if not entry.job.is_complete():return batch
		var alive=[0,0]
		for unit in clock.sim.units:
			if unit.hp>0:alive[unit.team]+=1
		var winner:String="player" if clock.sim.winner==0 else "opponent" if clock.sim.winner==1 else "draw"
		if _rules_profile!=RULES_PROFILE_PC_SHORT and alive[0]>0 and alive[1]>0:winner="draw"
		var ai:Dictionary=_collect_ai_outcomes()
		if not ai.ok:last_error=ai.error;return batch
		var settlement:Dictionary={"type":"resolve_battle","battle_id":_battle_id,"winner":winner,"player_remaining":alive[0],"opponent_remaining":alive[1],"ai_outcomes":ai.outcomes}
		if _rules_profile==RULES_PROFILE_PC_SHORT:settlement.combat=_combat_metadata()
		if _match_format=="six_round_league":settlement.league_outcomes=_league_rows(winner,ai)
		var result:Dictionary=rules.execute(settlement)
		if result.ok:showing_result=true
		else:last_error=result.error
	return batch
## Damage is effective HP loss; shield absorption is reported separately.
## EX unique hits count each enemy once per cast, summed over the battle.
func battle_feedback()->Dictionary:
	return _feedback.duplicate(true)
func _begin_feedback(battle:Dictionary)->void:
	_feedback={"battle_id":battle.id,"round":battle.round,"opponent_id":battle.opponent_id,"completed":false,
		"duration_seconds":0.0,"finish_reason":"","units":[],"first_death":{},
		"normal_target_policies":clock.sim.options.normal_target_policies.duplicate(true)}
	_feedback_units.clear();_ex_target_hits.clear()
	for unit in clock.sim.units:
		var row:Dictionary={"id":unit.id,"roster_unit_id":id_to_unit[unit.id],"character_id":unit.character_id,
			"star":unit.star,"team":unit.team,"damage_dealt":0,"damage_taken":0,
			"shield_damage_dealt":0,"shield_damage_taken":0,"ex_casts":0,"ex_unique_hits":0}
		_feedback.units.append(row);_feedback_units[unit.id]=row
func _record_feedback(batch:Array)->void:
	if _feedback.is_empty():return
	_feedback.duration_seconds=clock.sim.tick*clock.sim.STEP_SECONDS
	_feedback.overtime=clock.sim.overtime_state()
	for event in batch:
		match event.type:
			"skill":
				_feedback_units[event.actor_id].ex_casts+=1
			"damage":
				var source:Dictionary=_feedback_units[event.actor_id]
				var target:Dictionary=_feedback_units[event.target_id]
				source.damage_dealt+=event.amount;target.damage_taken+=event.amount
				source.shield_damage_dealt+=event.absorbed;target.shield_damage_taken+=event.absorbed
				if event.ability=="ex":
					var key:String="%d:%d:%d"%[event.actor_id,event.cast_start_tick,event.target_id]
					if not _ex_target_hits.has(key):
						_ex_target_hits[key]=true;source.ex_unique_hits+=1
			"death":
				if _feedback.first_death.is_empty():
					var unit:Dictionary=_feedback_units[event.actor_id]
					_feedback.first_death={"id":unit.id,"roster_unit_id":unit.roster_unit_id,"character_id":unit.character_id,
						"team":unit.team,"tick":event.tick,"seconds":event.tick*clock.sim.STEP_SECONDS}
			"finished":
				_feedback.completed=true;_feedback.finish_reason=event.reason

## Unknown IDs yield an invalid enum, never an implicit nearest default. The
## simulator validates this explicit pair before any prospective battle is live.
func _participant_normal_target_policy(participant_id:String)->String:
	if participant_id=="p0":return _normal_target_policy
	if participant_id in OffscreenDuel.RIVALS:return "nearest"
	return ""
func _hp_ratios(units:Array)->Array:
	var hp:Array=[0.0,0.0];var maximum:Array=[0.0,0.0]
	for unit in units:
		hp[unit.team]+=maxf(0.0,float(unit.hp));maximum[unit.team]+=float(unit.max_hp)
	return [clampf(hp[0]/maximum[0],0.0,1.0) if maximum[0]>0 else 0.0,clampf(hp[1]/maximum[1],0.0,1.0) if maximum[1]>0 else 0.0]
func _league_rows(winner:String,ai:Dictionary)->Array:
	var ratios:Array=_hp_ratios(clock.sim.units);var opponent:String=rules.snapshot().battle.opponent_id
	var rows:Array=[]
	_append_league_pair(rows,"p0",opponent,"left" if winner=="player" else "right" if winner=="opponent" else "draw",ratios,_combat_metadata() if _rules_profile==RULES_PROFILE_PC_SHORT else {})
	for index in range(ai.outcomes.size()):
		var duel:Dictionary=ai.outcomes[index]
		_append_league_pair(rows,duel.left_id,duel.right_id,duel.winner,ai.hp_ratios[index],duel if _rules_profile==RULES_PROFILE_PC_SHORT else {})
	return rows
func _append_league_pair(rows:Array,left:String,right:String,winner:String,ratios:Array,combat:Dictionary={})->void:
	rows.append({"participant_id":left,"opponent_id":right,"result":"win" if winner=="left" else "loss" if winner=="right" else "draw","remaining_hp_ratio":ratios[0]})
	rows.append({"participant_id":right,"opponent_id":left,"result":"win" if winner=="right" else "loss" if winner=="left" else "draw","remaining_hp_ratio":ratios[1]})
	if _rules_profile==RULES_PROFILE_PC_SHORT:
		for side in range(2):
			var row:Dictionary=rows[rows.size()-2+side]
			row["remaining_hp_total"]=combat.remaining_hp_totals[side];row["maximum_hp_total"]=combat.maximum_hp_totals[side]
			row["duration_ticks"]=combat.duration_ticks;row["finish_reason"]=combat.finish_reason
func _combat_metadata()->Dictionary:
	var value:Dictionary=Health.totals(clock.sim.units)
	value["duration_ticks"]=clock.sim.tick;value["finish_reason"]=_feedback.get("finish_reason","")
	return value
func _battle_options(battle_seed:int,left_id:String,right_id:String)->Dictionary:
	var result:Dictionary={"seed":battle_seed,"area_ex_coverage_targeting":true,"normal_target_policies":[_participant_normal_target_policy(left_id),_participant_normal_target_policy(right_id)],"arena_half":arena_config().half_size,"initial_basic_delay_cap_seconds":INITIAL_BASIC_DELAY_CAP_SECONDS,
		"overtime_enabled":true,"overtime_start_seconds":75.0,"overtime_ramp_seconds":30.0,"overtime_min_sustain_multiplier":0.2}
	result.merge(Pacing.options(_rules_profile),true)
	if _rules_profile in [RULES_PROFILE_FIVE_UNIT,RULES_PROFILE_PC_SHORT]:
		result.tactical_cover_distance=1.0;result.tactical_cover_multiplier=0.7;result.tactical_cover_ai=true
	if _combat_mode=="tactical_v1":
		result.combat_mode=_combat_mode;result.tactical_ai_teams=[1] if left_id=="p0" else [0,1]
	return result
func _prepare_ai_jobs(battle:Dictionary)->Dictionary:
	var jobs:Array=[]
	for pair in battle.ai_pairs:
		var left:Array=rules._deployed_units(rules._player_ref(pair[0]))
		var right:Array=rules._deployed_units(rules._player_ref(pair[1]))
		var pair_seed:int=OffscreenDuel.derive_seed(seed,int(battle.round),pair[0],pair[1])
		var job=OffscreenDuel.new()
		var options:Dictionary=_battle_options(pair_seed,pair[0],pair[1])
		var error:String=job.configure(left,right,pair[0],pair[1],pair_seed,options,arena_config())
		if not error.is_empty():return {"ok":false,"error":"offscreen battle: "+error}
		jobs.append({"job":job,"worker_input":{"left_army":left,"right_army":right,"left_id":pair[0],"right_id":pair[1],"seed":pair_seed,"settings":options.duplicate(true),"arena_config":{"obstacles":arena_config().obstacles}},"diagnostics":{"left_id":pair[0],"right_id":pair[1],"normal_target_policies":options.normal_target_policies.duplicate(true)}})
	return {"ok":true,"jobs":jobs}
func _launch_ai_jobs(jobs:Array)->void:
	_cancel_ai_jobs();_ai_last_status.clear();_ai_jobs=jobs
	if process_ai_enabled and not jobs.is_empty():
		_process_batch=ProcessBatch.new()
		var inputs:Array=[]
		for entry in jobs:inputs.append(entry.worker_input)
		var started:Dictionary=_process_batch.start(inputs,clock.generation)
		_process_diagnostics=_process_batch.snapshot()
		if started.status=="running":_ai_execution_mode="process"
		else:_process_batch=null

## Main-thread cooperative work avoids the engine's shared cold-bytecode race.
## Check time between indivisible simulation ticks; a single tick may exceed it.
func _pump_ai_jobs(budget_us:int,max_steps:int=AI_MAX_STEPS_PER_ADVANCE)->int:
	_ai_last_pump_steps=0
	if budget_us<=0 or max_steps<=0 or _ai_jobs.is_empty():return 0
	if _process_batch!=null:
		_ai_pump_calls+=1
		var polled:Dictionary=_process_batch.poll();_process_diagnostics=_process_batch.snapshot()
		if polled.status=="running":return 0
		var valid:bool=polled.status=="complete" and polled.results.size()==_ai_jobs.size()
		if valid:
			var outcomes:Array=[]
			for value in polled.results:outcomes.append(value.outcome)
			valid=rules._valid_ai_outcomes(outcomes,rules.snapshot().battle.ai_pairs)
		if valid:
			for index in range(_ai_jobs.size()):_ai_jobs[index].job._finish(polled.results[index],false)
			_process_batch=null;return 0
		_process_batch.cancel();_process_batch=null;_ai_execution_mode="cooperative"
		_process_diagnostics["fallback"]=true
		# Original unadvanced source jobs remain intact for safe fallback.
	var remaining:=0
	for entry in _ai_jobs:
		if not entry.job.is_complete():remaining+=1
	if remaining==0:return 0
	var started:int=Time.get_ticks_usec()
	_ai_pump_calls+=1
	while remaining>0 and _ai_last_pump_steps<mini(max_steps,AI_MAX_STEPS_PER_ADVANCE):
		if _ai_last_pump_steps>0 and Time.get_ticks_usec()-started>=budget_us:break
		_ai_cursor%=_ai_jobs.size()
		var entry:Dictionary=_ai_jobs[_ai_cursor]
		_ai_cursor=(_ai_cursor+1)%_ai_jobs.size()
		if entry.job.is_complete():continue
		var complete:bool=entry.job.advance(1)
		_ai_last_pump_steps+=1;_ai_total_steps+=1
		if complete:remaining-=1
	return _ai_last_pump_steps

func _cancel_ai_jobs()->void:
	if _process_batch!=null:_process_batch.cancel();_process_batch=null
	_ai_execution_mode="cooperative";_process_diagnostics.clear()
	for entry in _ai_jobs:entry.job.cancel()
	_ai_jobs.clear();_ai_cursor=0;_ai_last_pump_steps=0;_ai_total_steps=0;_ai_pump_calls=0

func _collect_ai_outcomes()->Dictionary:
	# Never block or drain simulations at the settlement boundary.
	for entry in _ai_jobs:
		if not entry.job.is_complete():return {"ok":false,"pending":true,"outcomes":[],"error":"offscreen_pending"}
	var started:int=Time.get_ticks_usec();var outcomes:Array=[];var hp_ratios:Array=[];var error:=""
	for entry in _ai_jobs:
		var value:Dictionary=entry.job.result
		if not value.get("ok",false):error="offscreen battle: "+str(value.get("error","missing result"))
		else:
			outcomes.append(value.outcome);hp_ratios.append(value.get("remaining_hp_ratios",[]))
	_ai_last_status={"battle_id":_battle_id,"scheduled":_ai_jobs.size(),"wait_us":Time.get_ticks_usec()-started,"error":error,"jobs":_ai_job_diagnostics(),"execution_mode":_ai_execution_mode,"process":_process_diagnostics.duplicate(true),"total_steps":_ai_total_steps,"pump_calls":_ai_pump_calls}
	_ai_jobs.clear()
	return {"ok":error.is_empty(),"outcomes":outcomes,"hp_ratios":hp_ratios,"error":error}
func _ai_job_diagnostics()->Array:
	var diagnostics:Array=[]
	for entry in _ai_jobs:diagnostics.append(entry.diagnostics.duplicate(true))
	return diagnostics
func ai_battle_status()->Dictionary:
	var pending:=0
	for entry in _ai_jobs:
		if not entry.job.is_complete():pending+=1
	return {"battle_id":_battle_id,"scheduled":_ai_jobs.size(),"pending":pending,"jobs":_ai_job_diagnostics(),"last_completed":_ai_last_status.duplicate(true),"execution_mode":_ai_execution_mode,"process":_process_diagnostics.duplicate(true),"last_pump_steps":_ai_last_pump_steps,"total_steps":_ai_total_steps,"pump_calls":_ai_pump_calls}
func _notification(what:int)->void:
	if what!=NOTIFICATION_PREDELETE:return
	# RefCounted at zero references cannot dispatch another method on itself.
	if _process_batch!=null:_process_batch.cancel()
	for entry in _ai_jobs:entry.job.cancel()
	_ai_jobs.clear()

func _route_step(unit:Dictionary,target:Vector2,reach:float)->Vector2:
	return arena_hooks.route_step(unit,target,reach)
func _cover_query(unit:Dictionary)->bool:
	return arena_hooks.cover_query(unit)

## The local player owns team0. Never trust a team supplied by UI/network data.
func _queue_local_tactical_command(input:Dictionary)->Dictionary:
	if _combat_mode!="tactical_v1" or phase()!="battle" or paused:return {"ok":false,"error":"tactical_battle_required"}
	if not rules._exact_keys(input,["type","actor_id","target_id","point","sequence","generation"]):return {"ok":false,"error":"invalid_tactical_command"}
	var queued:Dictionary=input.duplicate(true)
	queued.team=0;queued.tick=clock.sim.tick+1
	return clock.sim.queue_tactical_command(queued)

func _make_rules(format:String,profile:int)->RefCounted:
	if format!="six_round_league":return MatchRules.new()
	var value=TacticalMatch.new()
	if profile==RULES_PROFILE_PC_SHORT:value.combat_max_ticks=1800;value.hp_timeout=true
	return value
