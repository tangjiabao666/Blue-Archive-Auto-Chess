extends SceneTree
const TacticalProjection=preload("res://tests/tactical_save_projection.gd")
const Session=preload("res://core/game_session.gd")
const SaveProjection=preload("res://tests/asuna_save_projection.gd")
const Rules=preload("res://core/prototype_match.gd")
const Store=preload("res://core/session_save_store.gd")
const V1:="res://tests/fixtures/shop_retention_legacy_session_v1.json"
const V2:="res://tests/fixtures/normal_target_legacy_session_v2.json"
const V3:="res://tests/fixtures/reinforcement_legacy_session_v3.json"
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func live(game)->Dictionary:
	return {"rules":game.rules.snapshot(),"seed":game.seed,"positions":game.positions.duplicate(true),"manual":game.manual_positions.duplicate(true),"clock":game.clock,"generation":game.clock.generation,"accumulator":game.clock.accumulator,"phase":game.phase(),"paused":game.paused,"showing_result":game.showing_result,"error":game.last_error,"simulation":game.clock.sim.snapshot(),"jobs":game._ai_jobs.duplicate(),"feedback":game.battle_feedback(),"ids":game.id_to_unit.duplicate(true),"policy":game.normal_target_policy()}
func reject(game,payload:Dictionary,label:String)->void:
	var before:Dictionary=live(game);var original:Dictionary=payload.duplicate(true)
	var result:Dictionary=game.restore_save(payload)
	ck(not result.ok and not result.error.is_empty(),label+" rejects")
	ck(live(game)==before and payload==original,label+" leaves live state clock jobs and caller input unchanged")
func ready(game)->void:
	var bought:Dictionary=game.command({"type":"buy_offer","slot":0})
	ck(bought.ok and game.command({"type":"deploy_unit","unit_id":bought.unit_id}).ok,"fixture has deployed army")
func reach(game,target:int)->void:
	while game.rules.snapshot().round<target:
		var started:Dictionary=game.rules.execute({"type":"start_battle"})
		ck(started.ok,"rules round starts")
		if not started.ok:return
		var result:Dictionary=game.rules.execute({"type":"resolve_battle","battle_id":started.battle.id,"winner":"player","player_remaining":1,"opponent_remaining":0})
		ck(result.ok,"rules round resolves")
		if not result.ok:return
	game._sync_positions()
func unit(id:String,character:String,star:int=1)->Dictionary:
	return {"id":id,"character_id":character,"star":star,"base_enabled":true,"passive_enabled":true,"ex_enabled":star==2}
func _initialize()->void:
	ck(Session.SAVE_VERSION==10,"new save envelope is version10")
	var game=Session.new();ck(game.new_game(812).ok,"new session starts")
	ck(game.rules.snapshot().config.get("reinforcement_recruitment")==1,"new GameSession explicitly enables reinforcements")
	if failures:quit(1);return
	ready(game);reach(game,3)
	ck(game.rules.get_reinforcement().status=="pending","round3 session event is pending")
	var save:Dictionary=game.export_save()
	ck(save.ok and save.data.version==10 and save.data.rules.version==6,"pending event exports canonical Save10 Rules6")
	var pending:Dictionary=save.data.duplicate(true);var before:Dictionary=live(game)
	var peer=Session.new();ck(peer.restore_save(JSON.parse_string(JSON.stringify(pending))).ok,"pending JSON save restores")
	ck(peer.export_save().data==pending and peer.rules.snapshot().rng_state==game.rules.snapshot().rng_state,"save/load preserves complete pending event schedule and RNG")
	ck(live(game)==before,"export does not change source session")
	var view:Dictionary=peer.rules.get_reinforcement();view.offers[0]="wrong"
	ck(peer.export_save().data==pending,"session event data detached")
	before=live(peer)
	ck(peer.command({"type":"start_battle"}).error=="reinforcement_pending" and live(peer)==before,"pending start does not create clock or worker jobs")
	peer.showing_result=true
	ck(not peer.command({"type":"claim_reinforcement","round":3,"slot":0}).ok and peer.rules.snapshot()==pending.rules,"claim waits for result acknowledgment")
	ck(peer.command({"type":"next_round"}).ok and peer.rules.snapshot()==pending.rules,"acknowledgment does not reroll")
	ck(peer.command({"type":"claim_reinforcement","round":3,"slot":0}).ok,"session routes claim")
	var claimed:Dictionary=peer.export_save().data
	ck(peer.restore_save(claimed).ok and peer.export_save().data==claimed,"claimed event roundtrips")
	before=live(peer)
	ck(not peer.command({"type":"claim_reinforcement","round":3,"slot":0}).ok and live(peer)==before,"session claim replay atomic")
	ck(peer.restore_save(pending).ok and peer.command({"type":"skip_reinforcement","round":3}).ok,"session routes explicit skip")
	var skipped:Dictionary=peer.export_save().data
	ck(peer.restore_save(skipped).ok and peer.export_save().data==skipped,"skipped event roundtrips")
	_test_manual_merge(peer,pending)
	_test_legacy(game)
	_test_malformed(game,pending)
	print("REINFORCEMENT SESSION ",checks," checks FAILURES=",failures);quit(1 if failures else 0)
func _test_manual_merge(game,pending:Dictionary)->void:
	ck(game.restore_save(pending).ok,"manual merge source restores")
	var state:Dictionary=game.rules.snapshot();var p:Dictionary=state.players[0]
	var character:String=p.reinforcement.offers[0];var serial:int=state.next_unit_id
	p.units=[unit("u%06d"%serial,character),unit("u%06d"%(serial+1),character)];serial+=2
	p.deployed=[p.units[0].id];p.bench=[p.units[1].id]
	for index in range(state.config.bench_capacity-1):
		var filler:Dictionary=unit("u%06d"%serial,"serika",2);serial+=1;p.units.append(filler);p.bench.append(filler.id)
	state.next_unit_id=serial
	ck(game.rules.restore(state).ok,"full bench session pair restores")
	game._sync_positions();var survivor:String=p.deployed[0]
	ck(game.place(survivor,Vector2(-3.2,4.7)),"manual position installs")
	var result:Dictionary=game.command({"type":"claim_reinforcement","round":3,"slot":0})
	ck(result.ok and result.unit_id==survivor and game.positions[survivor]==Vector2(-3.2,4.7) and game.manual_positions.get(survivor)==true,"claim merge preserves deployed ID and manual grid position")
	var checkpoint:Dictionary=game.export_save().data
	ck(game.restore_save(checkpoint).ok and game.export_save().data==checkpoint,"merged manual placement roundtrips")
func _test_legacy(game)->void:
	var v1:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(V1))
	var v2:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(V2))
	# Captured by the actual Save3/Rules5 implementation at 90a3dc0.
	var v3:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(V3))
	for source in [v1,v2,v3]:
		var original:Dictionary=source.duplicate(true)
		ck(game.restore_save(source).ok,"exact legacy envelope%d restores"%source.version)
		var migrated:Dictionary=game.export_save().data
		ck(migrated.version==10 and migrated.rules.version==6 and migrated.rules.config.reinforcement_recruitment==0,"legacy migrates into explicitly disabled Rules6")
		ck(game.normal_target_policy()==("wounded" if source.version==3 else "nearest"),"legacy normal-target policy preserved")
		var projection:Dictionary=TacticalProjection.legacy_envelope(migrated)
		projection.rules.catalog=SaveProjection.legacy_catalog(projection.rules.catalog)
		ck(projection.rules.catalog.size()==13,"inverse validates and removes only exact Asuna row")
		projection.version=source.version;projection.rules.version=source.rules.version;projection.rules.config.erase("reinforcement_recruitment")
		if source.version<3:projection.erase("normal_target_policy")
		for player in projection.rules.players:
			ck(player.reinforcement.is_empty(),"legacy participants have empty events");player.erase("reinforcement")
			if source.version==1:player.erase("shop_locked")
		ck(Rules.new()._normalize_json(projection)==Rules.new()._normalize_json(source),"migration preserves every old RNG offer lock ID position and schedule")
		ck(source==original,"migration is detached")
		for repeat in range(3):ck(game.restore_save(source).ok and game.export_save().data==migrated,"repeated legacy load consumes nothing")
		ck(game.command({"type":"restart"}).ok and game.rules.snapshot().config.reinforcement_recruitment==0,"legacy restart preserves disabled rules")
		ready(game);reach(game,3)
		ck(game.rules.get_reinforcement().is_empty(),"legacy restarted round3 never grants event")
		ck(game.new_game(999).ok and game.rules.snapshot().config.reinforcement_recruitment==1,"fresh new_game enables feature after legacy restart")
		for envelope in [1,2,3,4,5]:
			var bad:Dictionary=source.duplicate(true);bad.version=envelope
			if envelope>=3:bad["normal_target_policy"]="wounded"
			else:bad.erase("normal_target_policy")
			if (envelope==1 and source.rules.version!=4) or (envelope in [2,3] and source.rules.version!=5) or envelope in [4,5]:
				reject(game,bad,"exact version pair rejects hybrid envelope%d rules%d"%[envelope,source.rules.version])
		var bad:Dictionary=source.duplicate(true);bad.rules.config.reinforcement_recruitment=0
		reject(game,bad,"legacy cannot contain new config flag")
		bad=source.duplicate(true);bad.rules.players[0].reinforcement={}
		reject(game,bad,"legacy cannot contain partial event schema")
	# Both direct legacy APIs reject new fields and preserve their current live state.
	var raw=Rules.new();raw.new_match(1);var before:Dictionary=raw.snapshot()
	ck(not raw.restore(v1.rules).ok and not raw.restore(v2.rules).ok and raw.snapshot()==before,"ordinary Rules6 restore rejects unmigrated schemas")
func _test_malformed(game,pending:Dictionary)->void:
	ck(game.restore_save(pending).ok,"malformed test starts with valid pending session")
	game.paused=true;game.showing_result=true
	var invalid:Array=[]
	for version in [0,11,999,"5",true,false,null,[],{},5.5]:
		var bad:Dictionary=pending.duplicate(true);bad.version=version;invalid.append([bad,"invalid envelope version"])
	for version in [1,2,3,4,5,7,"6",true,false,null,[],{},6.5]:
		var bad:Dictionary=pending.duplicate(true);bad.rules.version=version;invalid.append([bad,"invalid Rules6 version"])
	for key in pending:
		var bad:Dictionary=pending.duplicate(true);bad.erase(key);invalid.append([bad,"missing envelope "+key])
	for key in ["reinforcement_recruitment"]:
		var bad:Dictionary=pending.duplicate(true);bad.rules.config.erase(key);invalid.append([bad,"missing feature flag"])
	for value in [null,0,[],{},true,"pending"]:
		var bad:Dictionary=pending.duplicate(true);bad.rules.players[0].reinforcement=value;invalid.append([bad,"malformed pending event"])
	var bad:Dictionary=pending.duplicate(true);bad.rules.players[0].reinforcement.status="claimed";invalid.append([bad,"claim lacks selected slot"])
	bad=pending.duplicate(true);bad.rules.players[0].reinforcement.offers[1]=bad.rules.players[0].reinforcement.offers[0];invalid.append([bad,"duplicate offers"])
	bad=pending.duplicate(true);bad.rules.players[0].erase("reinforcement");invalid.append([bad,"missing event"])
	bad=pending.duplicate(true);bad.rules.players[0].reinforcement.extra=0;invalid.append([bad,"extra event field"])
	bad=pending.duplicate(true);bad.rules.config.reinforcement_recruitment=0;invalid.append([bad,"disabled with pending event"])
	bad=pending.duplicate(true);bad.rules.config.income+=1;invalid.append([bad,"unsupported economy config"])
	bad=pending.duplicate(true);bad.normal_target_policy="invalid";invalid.append([bad,"invalid targeting policy"])
	bad=pending.duplicate(true);bad.positions[bad.positions.keys()[0]]=[0,-1];invalid.append([bad,"invalid placement"])
	bad=pending.duplicate(true);bad.extra=true;invalid.append([bad,"extra envelope field"])
	for entry in invalid:reject(game,entry[0],entry[1])
	# Validate before cancelling a genuinely running battle and offscreen job group.
	game.showing_result=false
	ck(game.command({"type":"skip_reinforcement","round":3}).ok and game.command({"type":"start_battle"}).ok,"live battle with jobs starts")
	for entry in invalid:reject(game,entry[0],"battle "+entry[1])
	ck(game.command({"type":"restart"}).ok,"test cleans up live worker jobs")
