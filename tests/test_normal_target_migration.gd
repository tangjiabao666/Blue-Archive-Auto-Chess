extends SceneTree
const TacticalProjection=preload("res://tests/tactical_save_projection.gd")
const Session=preload("res://core/game_session.gd")
const SaveProjection=preload("res://tests/asuna_save_projection.gd")
const Rules=preload("res://core/prototype_match.gd")
const Store=preload("res://core/session_save_store.gd")
const V1:="res://tests/fixtures/shop_retention_legacy_session_v1.json"
const V2:="res://tests/fixtures/normal_target_legacy_session_v2.json"
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func copy(value:Dictionary)->Dictionary:
	return JSON.parse_string(JSON.stringify(value,"",true,true))
func live(game)->Dictionary:
	return {"rules":game.rules.snapshot(),"seed":game.seed,"positions":game.positions.duplicate(true),"manual":game.manual_positions.duplicate(true),"clock":game.clock,"generation":game.clock.generation,"accumulator":game.clock.accumulator,"phase":game.phase(),"paused":game.paused,"error":game.last_error,"simulation":game.clock.sim.snapshot(),"jobs":game._ai_jobs.duplicate(),"feedback":game.battle_feedback(),"ids":game.id_to_unit.duplicate(true),"policy":game.normal_target_policy()}
func reject(game,payload:Dictionary,label:String)->void:
	var before:Dictionary=live(game);var original:Dictionary=payload.duplicate(true)
	var result:Dictionary=game.restore_save(payload)
	ck(result.get("ok")==false and not result.get("error","").is_empty(),"reject "+label)
	ck(live(game)==before and payload==original,"rejected "+label+" is atomic and caller-owned input unchanged")
func put(path:String,value:String)->void:
	var file=FileAccess.open(path,FileAccess.WRITE);ck(file!=null,"store fixture opens")
	if file!=null:file.store_string(value);file.close()
func _initialize()->void:
	ck(Session.SAVE_VERSION==10,"canonical envelope is version10; economy is rules6")
	if failures:quit(1);return
	var legacy1:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(V1))
	var legacy2:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(V2))
	ck(legacy1.version==1 and legacy1.rules.version==4 and legacy1.size()==6,"genuine v1 fixture preserved")
	ck(legacy2.version==2 and legacy2.rules.version==5 and legacy2.size()==6 and legacy2.rules.players[0].shop_locked,"genuine v2 fixture has pending retention")
	var game=Session.new();game.new_game(77)
	for source in [legacy1,legacy2]:
		var original:Dictionary=source.duplicate(true)
		ck(game.restore_save(source).ok and game.normal_target_policy()=="nearest","legacy defaults nearest")
		var canonical:Dictionary=game.export_save().data
		ck(canonical.version==10 and canonical.rules.version==6 and canonical.size()==11 and canonical.rules_profile==0 and canonical.match_format=="survival" and canonical.arena_version==0 and canonical.combat_mode=="legacy" and canonical.normal_target_policy=="nearest","legacy exports canonical exact eleven-key envelope10")
		var projected:Dictionary=TacticalProjection.legacy_envelope(canonical);projected.version=source.version;projected.erase("normal_target_policy");projected.rules.version=source.rules.version;projected.rules.config.erase("reinforcement_recruitment")
		projected.rules.catalog=SaveProjection.legacy_catalog(projected.rules.catalog)
		ck(projected.rules.catalog.size()==13,"inverse validates and removes only exact Asuna row")
		for player in projected.rules.players:player.erase("reinforcement")
		if source.version==1:
			projected.rules.version=4
			for player in projected.rules.players:player.erase("shop_locked")
		ck(Rules.new()._normalize_json(projected)==Rules.new()._normalize_json(source),"migration preserves every old field RNG shop placement and schedule")
		ck(source==original,"successful migration never mutates source")
		for repeat in range(3):ck(game.restore_save(source).ok and game.export_save().data==canonical,"repeat legacy restore stable without RNG use")
	ck(game.restore_save(legacy2).ok,"reset pending retained-shop fixture")
	ck(game.command({"type":"set_normal_target_policy","policy":"wounded"}).ok,"select wounded for roundtrip")
	var wounded:Dictionary=game.export_save().data
	ck(wounded.normal_target_policy=="wounded" and wounded.rules.players[0].shop_locked,"canonical save preserves tactic and pending retention")
	var peer=Session.new();ck(peer.restore_save(copy(wounded)).ok and peer.normal_target_policy()=="wounded" and peer.export_save().data==wounded,"wounded JSON roundtrip")
	var caller:Dictionary=copy(wounded);ck(peer.restore_save(caller).ok,"caller-owned checkpoint restores");caller.normal_target_policy="nearest";caller.rules.players[0].shop_locked=false
	ck(peer.normal_target_policy()=="wounded" and peer.rules.get_player().shop_locked,"restored state detached from caller")
	var exported:Dictionary=peer.export_save().data;exported.normal_target_policy="nearest";exported.rules.players[0].shop_locked=false
	ck(peer.normal_target_policy()=="wounded" and peer.rules.get_player().shop_locked,"export detached from session")
	var invalid:Array=[]
	for source in [legacy1,legacy2,wounded]:
		for version in [0,11,999,"3",true,false,[],{},null,3.5]:
			var bad:Dictionary=source.duplicate(true);bad.version=version;invalid.append([bad,"invalid envelope version "+str(version)])
		for value in [true,false,0,1,[],{},null]:
			var bad:Dictionary=source.duplicate(true);bad.format=value;invalid.append([bad,"format type"])
		for key in source:
			var bad:Dictionary=source.duplicate(true);bad.erase(key);invalid.append([bad,"missing key "+str(key)])
		var extra:Dictionary=source.duplicate(true);extra.extra=true;invalid.append([extra,"unknown field"])
	for value in [null,true,false,0,1,1.0,[],{},["nearest","nearest"],"","WOUNDED","lowest_hp",&"nearest"]:
		var bad:Dictionary=wounded.duplicate(true);bad.normal_target_policy=value;invalid.append([bad,"strict policy "+str(value)])
	for source in [legacy1,legacy2]:
		var bad:Dictionary=source.duplicate(true);bad.normal_target_policy="nearest";invalid.append([bad,"legacy with partial new key"])
		bad=source.duplicate(true);bad.version=3;invalid.append([bad,"v3 missing policy"])
		bad=source.duplicate(true);bad.version=3;bad.normal_target_policy="nearest"
		if source.version==1:invalid.append([bad,"v3/rules4 hybrid"])
	var bad:Dictionary=legacy1.duplicate(true);bad.version=2;invalid.append([bad,"v2/rules4 hybrid"])
	bad=legacy2.duplicate(true);bad.version=1;invalid.append([bad,"v1/rules5 hybrid"])
	for version in [1,2]:
		bad=wounded.duplicate(true);bad.version=version;invalid.append([bad,"legacy envelope with new policy"])
	bad=wounded.duplicate(true);bad.rules.version=7;invalid.append([bad,"future rules"])
	bad=wounded.duplicate(true);bad.rules.normal_target_policy="wounded";invalid.append([bad,"tactic illegally in economy rules"])
	bad=wounded.duplicate(true);bad.seed+=1;invalid.append([bad,"seed mismatch"])
	bad=wounded.duplicate(true);bad.rules.rng_state=0;invalid.append([bad,"invalid RNG"])
	bad=wounded.duplicate(true);bad.rules.catalog[0].cost+=1;invalid.append([bad,"catalog mismatch"])
	bad=wounded.duplicate(true);bad.rules.config.income+=1;invalid.append([bad,"config mismatch"])
	bad=wounded.duplicate(true);bad.positions[bad.positions.keys()[0]]=[0,-1];invalid.append([bad,"invalid placement"])
	bad=wounded.duplicate(true);bad.extra="x".repeat(Session.MAX_SAVE_BYTES+1);invalid.append([bad,"oversize envelope"])
	game.paused=true;game.showing_result=true
	for entry in invalid:reject(game,entry[0],entry[1])
	for source_path in [V1,V2]:
		var path:="user://normal-target-migration-%d.json"%OS.get_process_id()
		var bytes:String=FileAccess.get_file_as_string(source_path)
		put(path,bytes)
		var read:Dictionary=Store.read_save(path)
		ck(read.ok and not read.recovered and game.restore_save(read.data).ok,"store accepts genuine legacy")
		ck(FileAccess.get_file_as_string(path)==bytes and not FileAccess.file_exists(path+".bak"),"ordinary migration never rewrites")
		put(path+".bak",bytes)
		for broken in ["{broken",JSON.stringify({"format":true}),JSON.stringify(invalid[0][0])]:
			put(path,broken);read=Store.read_save(path)
			ck(read.ok and read.recovered and game.restore_save(read.data).ok,"invalid primary recovers genuine legacy backup")
			ck(FileAccess.get_file_as_string(path)==broken and FileAccess.get_file_as_string(path+".bak")==bytes,"backup recovery writes nothing")
		ck(Store.write_save(game.export_save().data,path).ok,"explicit save writes migration")
		read=Store.read_save(path)
		ck(read.ok and read.data.version==10 and read.data.rules.version==6 and read.data.normal_target_policy=="nearest","explicit canonical save verified")
		ck(FileAccess.get_file_as_string(path+".bak")==bytes,"explicit save over corrupt primary retains genuine backup")
		DirAccess.remove_absolute(path);DirAccess.remove_absolute(path+".bak")
	# Pending retention and paid-roll continuation must remain deterministic.
	ck(game.restore_save(legacy2).ok and peer.restore_save(game.export_save().data).ok,"legacy and v4 continuation initialized")
	game.showing_result=true;peer.showing_result=true
	ck(game.command({"type":"next_round"}).ok and peer.command({"type":"next_round"}).ok,"continuations acknowledge result")
	ck(game.rules.get_player().shop_locked and game.rules.snapshot()==peer.rules.snapshot(),"acknowledgment consumes neither retention nor RNG")
	ck(game.command({"type":"refresh_shop"}).ok and peer.command({"type":"refresh_shop"}).ok and game.export_save().data==peer.export_save().data,"same paid refresh after migration preserves shared RNG and offers")
	print("NORMAL TARGET MIGRATION ",checks," checks FAILURES=",failures);quit(1 if failures else 0)
