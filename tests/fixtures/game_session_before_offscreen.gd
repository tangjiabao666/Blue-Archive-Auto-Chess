extends RefCounted
const Formations=preload("res://core/opponent_formations.gd")
const MatchRules=preload("res://core/prototype_match.gd")
const CharacterClock=preload("res://core/character_clock.gd")
const Navigation=preload("res://core/obstacle_navigation.gd")
const ACTIVE=["shiroko","hoshino","hina","aru","yuuka","aris","serika","iori","tsubaki","nonomi","mutsuki","haruna","koharu"]
# Autochess gold prices; source EX energy costs remain unchanged in character data.
const COSTS={"shiroko":2,"hoshino":3,"hina":4,"aru":3,"yuuka":2,"aris":4,"serika":1,"iori":4,"tsubaki":2,"nonomi":3,"mutsuki":2,"haruna":3,"koharu":3}
const INITIAL_BASIC_DELAY_CAP_SECONDS:=5.0
const HALF_SIZE:=6.6
const OBSTACLES=[{"rect":Rect2(-2.3,-0.8,0.6,1.6),"blocks_projectiles":true},{"rect":Rect2(1.7,-0.8,0.6,1.6),"blocks_projectiles":true},{"rect":Rect2(-0.8,2.2,1.6,0.45),"blocks_projectiles":false},{"rect":Rect2(-0.8,-2.65,1.6,0.45),"blocks_projectiles":false}]
var rules=MatchRules.new()
var clock=CharacterClock.new()
var navigation=Navigation.new()
var profiles:Dictionary={}
var catalog:Array=[]
var positions:Dictionary={}
var manual_positions:Dictionary={}
var id_to_unit:Dictionary={}
var paused:=false
var showing_result:=false
var last_error:=""
var seed:=1
var _battle_id:=""
var _feedback:Dictionary={}
var _feedback_units:Dictionary={}
var _ex_target_hits:Dictionary={}
func _init()->void:
	profiles=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	last_error=navigation.configure(HALF_SIZE,OBSTACLES)
	for key in ACTIVE:
		var source:Dictionary=clock.sim.character_data(key)
		catalog.append({"id":key,"name":profiles.get(key,{}).get("display_name",key),"cost":COSTS[key],"ex_cooldown":5.0+5.0*source.get("ex",{}).get("originalCost",2)})
	_wire_navigation()
func _wire_navigation()->void:
	clock.sim.position_free=Callable(navigation,"is_free")
	clock.sim.segment_free=Callable(navigation,"is_segment_free")
	clock.sim.line_of_sight=Callable(navigation,"has_line_of_sight")
	clock.sim.path_step=Callable(self,"_route_step")
	clock.sim.cover_query=Callable(self,"_cover_query")
func new_game(new_seed:int=1)->Dictionary:
	if not last_error.is_empty():return {"ok":false,"error":last_error}
	var result:Dictionary=rules.new_match(new_seed,catalog)
	if result.ok:
		seed=new_seed
		_reset_session()
	return result
func _reset_session()->void:
	positions.clear();manual_positions.clear();id_to_unit.clear();paused=false;showing_result=false;_battle_id=""
	_feedback.clear();_feedback_units.clear();_ex_target_hits.clear()
	clock=CharacterClock.new();_wire_navigation()
func phase()->String:
	var state:Dictionary=rules.snapshot()
	if state.is_empty():return "uninitialized"
	if state.phase=="finished":return "finished"
	return "result" if showing_result else state.phase
func command(input:Dictionary)->Dictionary:
	var kind:String=input.get("type","")
	if kind=="restart":
		var restarted:Dictionary=rules.execute(input)
		if restarted.ok:
			seed=int(rules.snapshot().initial_seed)
			_reset_session()
		return restarted
	if kind=="next_round":
		if not showing_result or rules.snapshot().phase!="preparation":return {"ok":false,"error":"没有待确认的回合结果"}
		showing_result=false;paused=false;clock.reset();return {"ok":true,"error":""}
	if showing_result:return {"ok":false,"error":"请先继续下一回合"}
	var before:Dictionary=rules.snapshot()
	var result:Dictionary=rules.execute(input)
	if not result.ok:return result
	_sync_positions()
	if kind=="start_battle":
		_battle_id=result.battle.id
		var roster:=_battle_roster(result.battle)
		var error:String=clock.sim.configure(roster,{"seed":seed+int(result.battle.round),"arena_half":HALF_SIZE,"initial_basic_delay_cap_seconds":INITIAL_BASIC_DELAY_CAP_SECONDS,
			"overtime_enabled":true,"overtime_start_seconds":75.0,"overtime_ramp_seconds":30.0,"overtime_min_sustain_multiplier":0.2})
		if not error.is_empty():rules.restore(before);return {"ok":false,"error":error}
		clock.accumulator=0;clock.generation+=1;clock.sim.start();paused=false
		_begin_feedback(result.battle)
	return result
func _owned(player:Dictionary,id:String)->Dictionary:
	for unit in player.units:
		if unit.id==id:return unit
	return {}

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
	if paused or phase()!="battle":return []
	var batch:Array=clock.advance(delta)
	_record_feedback(batch)
	if clock.sim.phase=="finished":
		var alive=[0,0]
		for unit in clock.sim.units:
			if unit.hp>0:alive[unit.team]+=1
		var winner:String="player" if clock.sim.winner==0 else "opponent" if clock.sim.winner==1 else "draw"
		if alive[0]>0 and alive[1]>0:winner="draw"
		var result:Dictionary=rules.execute({"type":"resolve_battle","battle_id":_battle_id,"winner":winner,"player_remaining":alive[0],"opponent_remaining":alive[1]})
		if result.ok:showing_result=true
		else:last_error=result.error
	return batch
## Damage is effective HP loss; shield absorption is reported separately.
## EX unique hits count each enemy once per cast, summed over the battle.
func battle_feedback()->Dictionary:
	return _feedback.duplicate(true)
func _begin_feedback(battle:Dictionary)->void:
	_feedback={"battle_id":battle.id,"round":battle.round,"opponent_id":battle.opponent_id,"completed":false,
		"duration_seconds":0.0,"finish_reason":"","units":[],"first_death":{}}
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
func _route_step(unit:Dictionary,target:Vector2,reach:float)->Vector2:
	var origin:Vector2=unit.cell
	var waypoint:Vector2=navigation.next_waypoint(origin,target,0.35)
	if waypoint==origin:return origin
	var blockers:Array=[]
	for other in clock.sim.units:
		# The destination actor is approached only to firing range; including
		# its center would make every route to the goal impossible.
		if other.id!=unit.id and other.hp>0 and other.cell.distance_to(target)>0.00001:
			blockers.append(other.cell)
	if not navigation.is_crowd_segment_free(origin,waypoint,0.35,blockers):
		waypoint=navigation.next_crowd_waypoint(origin,target,0.35,blockers,unit.id,clock.sim.tick)
		if waypoint==origin:return origin
	var travel:float=minf(0.125,origin.distance_to(waypoint))
	if waypoint.distance_to(target)<0.0001:travel=minf(travel,maxf(0.0,origin.distance_to(target)-maxf(0.0,reach-0.12)))
	var direction:=origin.direction_to(waypoint)
	var best:=origin;var remaining:=origin.distance_to(waypoint)
	for angle in [0.0,0.35,-0.35,0.7,-0.7,1.05,-1.05,1.4,-1.4,1.5,-1.5,1.52,-1.52,1.55,-1.55]:
		var point:Vector2=origin+direction.rotated(angle)*travel
		if not navigation.is_segment_free(origin,point,0.35):continue
		var free:=true
		for other in clock.sim.units:
			if other.id!=unit.id and other.hp>0 and point.distance_to(other.cell)<0.7-0.000001:free=false;break
		if free and point.distance_to(waypoint)<remaining-0.000001:best=point;remaining=point.distance_to(waypoint)
	return best

func _cover_query(unit:Dictionary)->bool:
	# Autochess cover adaptation: within0.6world units of solid cover, with
	# that same obstacle intersecting the line to a live opposing actor.
	# Native crouch/cover clips are not represented by this geometric hook.
	for obstacle in OBSTACLES:
		if not obstacle.blocks_projectiles:continue
		var rect:Rect2=obstacle.rect
		var closest:=Vector2(clampf(unit.cell.x,rect.position.x,rect.end.x),clampf(unit.cell.y,rect.position.y,rect.end.y))
		if unit.cell.distance_to(closest)>0.6:continue
		var corners=[rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
		for enemy in clock.sim.units:
			if enemy.hp<=0 or enemy.team==unit.team:continue
			for index in range(4):
				if Geometry2D.segment_intersects_segment(unit.cell,enemy.cell,corners[index],corners[(index+1)%4])!=null:return true
	return false
