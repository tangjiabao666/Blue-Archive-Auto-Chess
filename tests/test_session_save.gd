extends SceneTree
const Session=preload("res://core/game_session.gd")
var failures:=0
var checks:=0
func ck(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+message)
func ready(seed_value:int=17):
	var game=Session.new();ck(game.new_game(seed_value).ok,"save fixture initializes")
	for slot in range(3):
		var bought:Dictionary=game.command({"type":"buy_offer","slot":slot})
		if bought.ok:ck(game.command({"type":"deploy_unit","unit_id":bought.unit_id}).ok,"fixture deploys legally")
	var player:Dictionary=game.rules.get_player()
	ck(player.deployed.size()>=2,"fixture has two deployment placements")
	ck(game.place(player.deployed[0],Vector2(-3.1234567,4.234567)),"fixture first manual placement")
	ck(game.place(player.deployed[1],Vector2(3,4)),"fixture second manual placement")
	return game
func live_state(game)->Dictionary:
	return {"rules":game.rules.snapshot(),"positions":game.positions.duplicate(true),"manual":game.manual_positions.duplicate(true),
		"seed":game.seed,"generation":game.clock.generation,"phase":game.phase(),"paused":game.paused,
		"simulation":game.clock.sim.snapshot(),"feedback":game.battle_feedback(),"ids":game.id_to_unit.duplicate(true),"error":game.last_error}
func json_copy(value:Dictionary)->Dictionary:
	return JSON.parse_string(JSON.stringify(value,"",true,true))
func play(game)->Array:
	var events:Array=[]
	for step in range(500):
		if game.phase()!="battle":break
		events.append_array(game.advance(0.4))
	ck(game.phase()=="result","checkpoint fixture round reaches next preparation")
	for event in events:event.erase("generation")
	return events
func reject(game,payload:Dictionary,label:String)->void:
	var before:Dictionary=live_state(game);var jobs:Array=game._ai_jobs.duplicate()
	var outcome:Dictionary=game.restore_save(payload)
	ck(not outcome.ok and not outcome.error.is_empty(),"reject "+label)
	ck(live_state(game)==before and game._ai_jobs==jobs,"failed "+label+" restore leaves all live state unchanged")
func _initialize()->void:
	var game=ready()
	ck(game.has_method("export_save") and game.has_method("restore_save"),"session exposes validated preparation checkpoint API")
	if failures:quit(1);return
	var before:Dictionary=live_state(game)
	var exported:Dictionary=game.export_save();ck(exported.ok,"preparation exports")
	ck(live_state(game)==before,"export does not alter live rules, RNG or presentation")
	var payload:Dictionary=json_copy(exported.data)
	var target=Session.new();target.new_game(99)
	var restored:Dictionary=target.restore_save(payload)
	ck(restored.ok,"JSON checkpoint restores")
	ck(target.rules.snapshot()==game.rules.snapshot() and target.seed==game.seed,"roundtrip preserves canonical rules and source seed")
	ck(target.positions==game.positions and target.manual_positions==game.manual_positions,"roundtrip preserves manual positions")
	ck(target.phase()=="preparation" and not target.paused and target.clock.sim.phase=="prepare","load begins clean preparation")
	var copied:Dictionary=target.export_save().data;copied.rules.players[0].gold=0
	ck(target.rules.get_player().gold==game.rules.get_player().gold,"exports never alias session internals")
	var unknown:Dictionary=payload.duplicate(true);ck(target.restore_save(unknown).ok,"caller-owned payload restores");unknown.rules.players[0].gold=0
	ck(target.rules.get_player().gold==game.rules.get_player().gold,"restore never aliases caller payload")
	var benched=Session.new();ck(benched.restore_save(payload).ok,"manual bench fixture restores")
	var bench_id:String=benched.rules.get_player().deployed[0]
	ck(benched.command({"type":"bench_unit","unit_id":bench_id}).ok,"manual unit moves to bench")
	var bench_save:Dictionary=benched.export_save()
	ck(bench_save.ok and target.restore_save(json_copy(bench_save.data)).ok,"checkpoint keeps remembered bench placements")
	ck(target.positions==benched.positions and target.manual_positions==benched.manual_positions,"manual bench preference roundtrips")
	ck(target.command({"type":"deploy_unit","unit_id":bench_id}).ok and target.positions[bench_id]==game.positions[bench_id],"redeployed saved manual unit retains valid placement")
	ck(target.restore_save(payload).ok,"reset fixture after bench placement test")
	var invalid:Array=[]
	var bad:Dictionary=payload.duplicate(true);bad.version=999;invalid.append([bad,"future version"])
	bad=payload.duplicate(true);bad.extra=true;invalid.append([bad,"unknown envelope fields"])
	bad=payload.duplicate(true);bad.seed=99;invalid.append([bad,"seed mismatch"])
	bad=payload.duplicate(true);bad.rules.catalog[0].cost=77;invalid.append([bad,"catalog mismatch"])
	bad=payload.duplicate(true);bad.rules.config.income+=1;invalid.append([bad,"unsupported gameplay config"])
	bad=payload.duplicate(true);bad.rules.rng_state=0;invalid.append([bad,"invalid RNG"])
	bad=payload.duplicate(true);bad.rules.players[0].units[0].character_id="unknown";invalid.append([bad,"unknown character"])
	var ids:Array=game.rules.get_player().deployed
	bad=payload.duplicate(true);bad.positions["u999999"]=[0,4];invalid.append([bad,"unknown placement unit"])
	bad=payload.duplicate(true);bad.positions.erase(ids[0]);invalid.append([bad,"missing deployed placement"])
	bad=payload.duplicate(true);bad.positions[ids[0]]=[0,INF];invalid.append([bad,"nonfinite placement"])
	bad=payload.duplicate(true);bad.positions[ids[0]]=[0,NAN];invalid.append([bad,"NaN placement"])
	bad=payload.duplicate(true);bad.positions[ids[0]]=[99,4];invalid.append([bad,"out of bounds"])
	bad=payload.duplicate(true);bad.positions[ids[0]]=[0,-1];invalid.append([bad,"enemy placement zone"])
	bad=payload.duplicate(true);bad.positions[ids[0]]=[-2,0.5];invalid.append([bad,"obstructed placement"])
	bad=payload.duplicate(true);bad.positions[ids[0]]=bad.positions[ids[1]];invalid.append([bad,"overlapping deployment"])
	bad=payload.duplicate(true);bad.manual_positions["u999999"]=true;invalid.append([bad,"unknown manual position"])
	bad=payload.duplicate(true);bad.manual_positions[ids[0]]=false;invalid.append([bad,"invalid manual flag"])
	bad=payload.duplicate(true);bad.rules=Node.new();invalid.append([bad,"non JSON value"])
	for entry in invalid:reject(target,entry[0],entry[1])
	bad.rules.free()
	# A previous battle may have cached a detour around an actor that is gone.
	var origin:=Vector2(-3,4);var goal:=Vector2(3,4)
	var detour:Vector2=target.navigation.next_crowd_waypoint(origin,goal,0.35,[Vector2(0,4)],0,11)
	ck(detour!=goal and detour!=origin,"route-cache fixture creates a genuine crowd detour")
	ck(target.restore_save(payload).ok,"checkpoint restores after cached navigation")
	var clean_navigation=Session.Navigation.new();clean_navigation.configure(Session.HALF_SIZE,Session.OBSTACLES)
	var expected_route:Vector2=clean_navigation.next_crowd_waypoint(origin,goal,0.35,[Vector2(1,4)],0,12)
	ck(target.navigation.next_crowd_waypoint(origin,goal,0.35,[Vector2(1,4)],0,12)==expected_route,"load discards previous battle route detours")
	var generation:int=target.clock.generation
	for repeat in range(3):
		ck(target.restore_save(payload).ok,"repeated restore succeeds")
		ck(target.clock.generation>generation,"every restore invalidates old presentation generation")
		generation=target.clock.generation
	ck(target.command({"type":"restart"}).ok and target.clock.generation>generation,"restart advances presentation generation")
	generation=target.clock.generation
	ck(target.new_game(17).ok and target.clock.generation>generation,"new game advances presentation generation")
	ck(target.restore_save(payload).ok,"restore before deterministic comparison")
	if "--validation-only" in OS.get_cmdline_user_args():
		print("SESSION SAVE VALIDATION ",checks," checks FAILURES=",failures);quit(1 if failures else 0);return
	ck(game.command({"type":"refresh_shop"}).ok==target.command({"type":"refresh_shop"}).ok,"same next shop action succeeds")
	ck(game.rules.snapshot()==target.rules.snapshot() and game.opponent_preview()==target.opponent_preview(),"next shop and opponent schedule remain deterministic")
	var start:Dictionary=game.command({"type":"start_battle"});ck(start.ok,"checkpoint starts source combat")
	ck(not game.export_save().ok,"live battle cannot replace stable checkpoint")
	var old_job=weakref(game._ai_jobs[0].job)
	bad=payload.duplicate(true);bad.version=-1;reject(game,bad,"invalid save during active battle")
	generation=game.clock.generation
	ck(game.restore_save(payload).ok,"prebattle checkpoint restores over live worker jobs")
	ck(game.ai_battle_status().scheduled==0 and old_job.get_ref()==null,"load cancels, joins and releases old jobs")
	ck(game.clock.generation>generation and game.battle_feedback().is_empty() and game.id_to_unit.is_empty(),"load clears prior visual and audio event state")
	ck(target.restore_save(payload).ok and game.export_save().data==target.export_save().data,"checkpoint remains identical after interruption")
	# Equal commands on original and restored saves must settle equal real battles.
	ck(game.command({"type":"start_battle"}).ok and target.command({"type":"start_battle"}).ok,"restored preparation can replay same battle")
	var first:Array=play(game);var second:Array=play(target)
	ck(first==second and game.rules.snapshot()==target.rules.snapshot() and game.battle_feedback()==target.battle_feedback(),"restored battle and NPC outcomes are deterministic")
	var result_save:Dictionary=game.export_save();ck(result_save.ok,"completed round exports next preparation")
	ck(target.restore_save(json_copy(result_save.data)).ok and target.phase()=="preparation" and not target.showing_result,"result checkpoint resumes directly into next preparation")
	ck(game.rules.snapshot()==target.rules.snapshot(),"round completion checkpoint preserves next shop and opponent")
	ck(game.command({"type":"next_round"}).ok,"original acknowledges round result")
	ck(game.command({"type":"refresh_shop"}).ok==target.command({"type":"refresh_shop"}).ok,"subsequent shop action has same legality")
	ck(game.rules.snapshot()==target.rules.snapshot(),"subsequent shop RNG is equal")
	ck(game.command({"type":"start_battle"}).ok and target.command({"type":"start_battle"}).ok,"both continue into subsequent battle")
	first=play(game);second=play(target)
	ck(first==second and game.rules.snapshot()==target.rules.snapshot(),"subsequent battle and all AI outcomes remain equal")
	print("SESSION SAVE ",checks," checks FAILURES=",failures);quit(1 if failures else 0)
