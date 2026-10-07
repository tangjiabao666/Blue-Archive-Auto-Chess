extends SceneTree
const Session=preload("res://core/game_session.gd")
var failures:=0
var assertions:=0
func ck(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: "+message)
func army(game)->void:
	var state:Dictionary=game.rules.snapshot();var player:Dictionary=state.players[0]
	player.level=6;player.xp=0
	for character in ["hina","shiroko","hoshino","yuuka","aru","aris"]:
		var id:String="u%06d"%state.next_unit_id;state.next_unit_id+=1
		player.units.append({"id":id,"character_id":character,"star":2,"base_enabled":true,"passive_enabled":true,"ex_enabled":true});player.deployed.append(id)
	ck(game.rules.restore(state).ok,"legal two-star test army restores")
func duel(left:String,right:String):
	var game=Session.new();game.new_game(17)
	var state:Dictionary=game.rules.snapshot()
	for team in range(2):
		var player:Dictionary=state.players[0] if team==0 else state.players[int(state.next_opponent.opponent_id.substr(1))]
		var unit:Dictionary={"id":"u%06d"%state.next_unit_id,"character_id":left if team==0 else right,
			"star":2,"base_enabled":true,"passive_enabled":true,"ex_enabled":true}
		state.next_unit_id+=1;player.units=[unit];player.deployed=[unit.id];player.bench=[]
		if team==1:state.next_opponent.opponent_units=[unit.duplicate(true)]
	ck(game.rules.restore(state).ok,"legal source-backed duel fixture restores")
	ck(game.command({"type":"start_battle"}).ok,"source-backed duel starts")
	return game
func run_battle(game,delta:float)->Array:
	var output:Array=[]
	while game.phase()=="battle":output.append_array(game.advance(delta))
	return output
func _initialize()->void:
	var game=Session.new();game.new_game(17)
	ck(game.has_method("battle_feedback"),"session exposes factual battle feedback")
	if not game.has_method("battle_feedback"):
		print("BATTLE FEEDBACK FAILURES=",failures);quit(1);return
	ck(game.battle_feedback().is_empty(),"new game has no invented result")
	army(game);ck(game.command({"type":"start_battle"}).ok,"begin real battle")
	var fresh:Dictionary=game.battle_feedback()
	ck(not fresh.completed and fresh.first_death.is_empty(),"battle report starts without a casualty")
	var events:Array=run_battle(game,0.25);var actual:Dictionary=game.battle_feedback()
	ck(actual.completed and actual.duration_seconds==game.clock.sim.tick*0.05,"report completed at actual simulation tick")
	var expected:Dictionary={};var first:Dictionary={};var unique:Dictionary={};var ex_damage_events:=0;var shields:=0
	for actor in game.clock.sim.units:expected[actor.id]={"damage_dealt":0,"damage_taken":0,"shield_damage_dealt":0,"shield_damage_taken":0,"ex_casts":0,"ex_unique_hits":0}
	for event in events:
		if event.type=="skill":expected[event.actor_id].ex_casts+=1
		if event.type=="damage":
			expected[event.actor_id].damage_dealt+=event.amount;expected[event.target_id].damage_taken+=event.amount
			expected[event.actor_id].shield_damage_dealt+=event.absorbed;expected[event.target_id].shield_damage_taken+=event.absorbed;shields+=event.absorbed
			if event.ability=="ex":
				ex_damage_events+=1
				var key:String="%d:%d:%d"%[event.actor_id,event.cast_start_tick,event.target_id]
				if not unique.has(key):unique[key]=true;expected[event.actor_id].ex_unique_hits+=1
		if event.type=="death" and first.is_empty():first=event
		if event.type=="finished":ck(actual.finish_reason==event.reason,"finish reason comes from actual finished event")
	var unique_count:=0;var casts:=0
	for actor in actual.units:
		ck(expected.has(actor.id),"report includes only actual combatants")
		for key in expected[actor.id]:ck(actor[key]==expected[actor.id][key],"actor %d %s equals consumed events"%[actor.id,key])
		ck(actor.roster_unit_id==game.id_to_unit[actor.id],"battle actor retains economy identity")
		unique_count+=actor.ex_unique_hits;casts+=actor.ex_casts
	print("FEEDBACK EVENT COVERAGE EX contacts=",ex_damage_events," unique cast-targets=",unique_count," casts=",casts," shield HP=",shields)
	ck(ex_damage_events>unique_count and unique_count>0,"real multi-hit EX de-duplicates targets per cast")
	ck(shields>0,"real shield absorption exercised independently of HP loss")
	ck(not first.is_empty() and actual.first_death.id==first.actor_id and actual.first_death.tick==first.tick and actual.first_death.seconds==first.tick*0.05,"first death is first observed death event, with factual time")
	var borrowed:Dictionary=game.battle_feedback();borrowed.units[0].damage_dealt=-1
	ck(game.battle_feedback()==actual,"feedback result is detached")
	game.advance(100);ck(game.battle_feedback()==actual,"result screen cannot double count combat")
	var other=Session.new();other.new_game(17);army(other);other.command({"type":"start_battle"})
	other.paused=true;other.advance(3);ck(other.battle_feedback()==fresh,"pause does not fabricate events")
	other.paused=false;run_battle(other,0.05)
	ck(other.battle_feedback()==actual,"frame chunking produces identical report")
	if game.phase()=="result":
		game.command({"type":"next_round"});ck(game.battle_feedback()==actual,"feedback remains available during next preparation")
		game.command({"type":"start_battle"});ck(not game.battle_feedback().completed and game.battle_feedback().first_death.is_empty(),"next battle resets feedback")
	ck(game.command({"type":"restart","seed":17}).ok and game.battle_feedback().is_empty(),"restart clears old battle feedback")
	var repeat=duel("shiroko","yuuka");var repeated_events:Array=run_battle(repeat,0.25)
	var casts_hitting_target:Dictionary={}
	for event in repeated_events:
		if event.type=="damage" and event.ability=="ex" and event.actor_id==0:
			ck(event.target_id==7,"duel EX contacts are all against the same target")
			casts_hitting_target[event.cast_start_tick]=true
	ck(casts_hitting_target.size()>=2,"same actor really lands multiple separate EX casts on same target")
	ck(repeat.battle_feedback().units[0].ex_unique_hits==casts_hitting_target.size(),"same target counts again for each distinct actual EX cast")
	var stalemate=duel("hoshino","yuuka")
	# Isolate no-casualty report semantics using the unchanged native sustain rule.
	# Production matches opt into overtime; this fixture deliberately does not.
	stalemate.clock.sim.options.overtime_enabled=false
	var timeout_events:Array=run_battle(stalemate,0.25)
	var deaths:=0
	for event in timeout_events:
		if event.type=="death":deaths+=1
	ck(deaths==0 and stalemate.battle_feedback().completed and stalemate.battle_feedback().finish_reason=="timeout","real full-duration stalemate completes without any death event")
	ck(stalemate.battle_feedback().first_death.is_empty(),"completed no-casualty battle does not invent a first death")
	print("BATTLE FEEDBACK ASSERTIONS=",assertions," FAILURES=",failures);quit(1 if failures else 0)
