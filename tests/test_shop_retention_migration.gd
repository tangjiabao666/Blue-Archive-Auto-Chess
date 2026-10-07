extends SceneTree
const TacticalProjection=preload("res://tests/tactical_save_projection.gd")
const Session=preload("res://core/game_session.gd")
const SaveProjection=preload("res://tests/asuna_save_projection.gd")
const Store=preload("res://core/session_save_store.gd")
const Rules=preload("res://core/prototype_match.gd")
const FIXTURE:="res://tests/fixtures/shop_retention_legacy_session_v1.json"
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func live(game)->Dictionary:
	return {"rules":game.rules.snapshot(),"seed":game.seed,"positions":game.positions.duplicate(true),"manual":game.manual_positions.duplicate(true),"generation":game.clock.generation,"phase":game.phase(),"paused":game.paused,"showing_result":game.showing_result,"error":game.last_error,"simulation":game.clock.sim.snapshot(),"jobs":game._ai_jobs.duplicate(),"feedback":game.battle_feedback(),"ids":game.id_to_unit.duplicate(true)}
func reject(game,payload:Dictionary,label:String)->void:
	var before:Dictionary=live(game);var original:Dictionary=payload.duplicate(true)
	var result:Dictionary=game.restore_save(payload)
	ck(result.get("ok")==false and result.get("error","")!="","reject "+label)
	ck(live(game)==before and payload==original,"failed "+label+" preserves live session and input")
func put(path:String,value:String)->void:
	var file=FileAccess.open(path,FileAccess.WRITE);ck(file!=null,"fixture file opens")
	if file!=null:file.store_string(value);file.close()
func _initialize()->void:
	var legacy:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	ck(legacy.version==1 and legacy.rules.version==4 and not legacy.rules.players[0].has("shop_locked"),"fixture is actual pre-feature schema")
	var game=Session.new();ck(game.new_game(77).ok,"target initializes")
	var original:Dictionary=legacy.duplicate(true)
	ck(game.restore_save(legacy).ok,"actual legacy session migrates")
	ck(Session.SAVE_VERSION==10 and game.rules.snapshot().version==6,"legacy migrates to session10 rules6")
	ck(game.export_save().get("data",{}).get("version")==10,"next export is canonical version10")
	ck(legacy==original,"migration leaves caller-owned legacy input unchanged")
	if failures:quit(1);return
	var migrated:Dictionary=game.export_save().data
	var projected:Dictionary=TacticalProjection.legacy_envelope(migrated);projected.version=1;projected.rules.version=4;projected.erase("normal_target_policy");projected.rules.config.erase("reinforcement_recruitment")
	projected.rules.catalog=SaveProjection.legacy_catalog(projected.rules.catalog)
	ck(projected.rules.catalog.size()==13,"inverse validates and removes only exact Asuna row")
	for player in projected.rules.players:
		ck(player.shop_locked==false,"each legacy player starts unlocked");player.erase("shop_locked");player.erase("reinforcement")
	ck(Rules.new()._normalize_json(projected)==Rules.new()._normalize_json(legacy),"migration preserves every legacy seed RNG offer opponent ID history and precise placement")
	for repeat in range(3):
		ck(game.restore_save(legacy).ok and game.export_save().data==migrated,"repeated legacy load consumes no shop or RNG")
	# Canonical retained save loads without consuming; next result acknowledgment also cannot consume.
	ck(game.command({"type":"set_shop_locked","locked":true}).ok,"migrated session can retain")
	var locked:Dictionary=game.export_save().data
	var target=Session.new();ck(target.restore_save(locked).ok,"canonical retained save restores")
	ck(target.export_save().data==locked and target.rules.get_player().shop_locked,"canonical load preserves pending retention")
	game.showing_result=true
	var before:Dictionary=game.rules.snapshot()
	ck(game.command({"type":"next_round"}).ok and game.rules.snapshot()==before,"result acknowledgment never consumes retention")
	# Both restored and original make the same subsequent paid-roll RNG draw.
	ck(game.command({"type":"refresh_shop"}).ok and target.command({"type":"refresh_shop"}).ok,"migrated continuation refreshes")
	ck(game.export_save().data==target.export_save().data,"migrated and canonical command continuation remain identical")
	var invalid:Array=[]
	# Wrong JSON primitive/container types must return a structured rejection,
	# never trigger a Variant comparison error before backup recovery can run.
	for value in [true,false,0,1,[],{}]:
		var malformed:Dictionary=legacy.duplicate(true);malformed.format=value
		invalid.append([malformed,"legacy format type "+str(value)])
		malformed=locked.duplicate(true);malformed.format=value
		invalid.append([malformed,"canonical format type "+str(value)])
	for key in ["player_id","outcome","placement"]:
		var malformed:Dictionary=legacy.duplicate(true);malformed.rules[key]=true
		invalid.append([malformed,"legacy root type "+key])
	var malformed:Dictionary=legacy.duplicate(true);malformed.rules.players[0].id=true;invalid.append([malformed,"legacy player ID type"])
	for key in ["base_enabled","passive_enabled"]:
		malformed=legacy.duplicate(true);malformed.rules.players[0].units[0][key]=1
		invalid.append([malformed,"legacy unit Boolean type "+key])
	malformed=legacy.duplicate(true);malformed.rules.next_opponent.round=true;invalid.append([malformed,"legacy encounter round type"])
	malformed=legacy.duplicate(true);malformed.rules.last_result.ai_results[0].finish_reason=true;invalid.append([malformed,"legacy estimated finish reason type"])

	var bad:Dictionary=legacy.duplicate(true);bad.version=2;invalid.append([bad,"envelope2/rules4 hybrid"])
	bad=locked.duplicate(true);bad.version=1;invalid.append([bad,"envelope1/rules6 hybrid"])
	for version in [0,4,999,"1",true]:
		bad=legacy.duplicate(true);bad.version=version;invalid.append([bad,"unsupported envelope "+str(version)])
	for version in [0,3,5,999,"4",true]:
		bad=legacy.duplicate(true);bad.rules.version=version;invalid.append([bad,"unsupported legacy rules "+str(version)])
	bad=legacy.duplicate(true);bad.rules.players[0].shop_locked=false;invalid.append([bad,"partial legacy new schema"])
	bad=legacy.duplicate(true)
	for player in bad.rules.players:player.shop_locked=false
	invalid.append([bad,"all new fields under legacy versions"])
	bad=locked.duplicate(true);bad.rules.players[7].erase("shop_locked");invalid.append([bad,"partial canonical schema"])
	bad=locked.duplicate(true);bad.rules.players[7].shop_locked=0;invalid.append([bad,"canonical flag coercion"])
	for key in legacy:
		bad=legacy.duplicate(true);bad.erase(key);invalid.append([bad,"missing legacy envelope "+str(key)])
	bad=legacy.duplicate(true);bad.extra=0;invalid.append([bad,"extra envelope field"])
	bad=legacy.duplicate(true);bad.rules.extra=0;invalid.append([bad,"extra legacy rules field"])
	for index in range(8):
		for key in legacy.rules.players[index]:
			bad=legacy.duplicate(true);bad.rules.players[index].erase(key);invalid.append([bad,"missing legacy player%d/%s"%[index,key]])
		bad=legacy.duplicate(true);bad.rules.players[index].extra=0;invalid.append([bad,"extra legacy player field"])
	bad=legacy.duplicate(true);bad.rules.players[0]=[];invalid.append([bad,"nonobject player"])
	bad=legacy.duplicate(true);bad.rules.players={};invalid.append([bad,"nonarray players"])
	bad=legacy.duplicate(true);bad.rules.players[0].gold="10";invalid.append([bad,"wrong gold type"])
	bad=legacy.duplicate(true);bad.rules.players[0].shop[0].extra=true;invalid.append([bad,"extra offer field"])
	bad=legacy.duplicate(true);bad.rules.rng_state=0;invalid.append([bad,"invalid legacy RNG"])
	bad=legacy.duplicate(true);bad.seed+=1;invalid.append([bad,"legacy seed mismatch"])
	bad=legacy.duplicate(true);bad.rules.next_opponent.opponent_id="p0";invalid.append([bad,"legacy opponent corruption"])
	bad=legacy.duplicate(true);bad.rules.catalog[0].cost+=1;invalid.append([bad,"legacy catalog corruption"])
	bad=legacy.duplicate(true);bad.rules.config.income+=1;invalid.append([bad,"legacy unsupported config"])
	bad=legacy.duplicate(true);bad.positions[bad.positions.keys()[0]]=[0,-1];invalid.append([bad,"legacy enemy-side placement"])
	bad=legacy.duplicate(true);bad.manual_positions[bad.manual_positions.keys()[0]]=false;invalid.append([bad,"legacy manual flag"])
	bad=legacy.duplicate(true);bad.rules.players[0].units[0].star=3;invalid.append([bad,"legacy unsupported star"])
	game.paused=true;game.showing_result=true
	for entry in invalid:reject(game,entry[0],entry[1])
	# Raw v4 rules are not accepted by the ordinary v6 restore route.
	var raw=Rules.new();raw.new_match(2);before=raw.snapshot()
	ck(not raw.restore(legacy.rules).ok and raw.snapshot()==before,"raw legacy rules require the explicit session migration route")
	var path:="user://retention-migration-%d-%d.json"%[OS.get_process_id(),Time.get_ticks_usec()]
	var bytes:String=FileAccess.get_file_as_string(FIXTURE)
	put(path,bytes)
	var read:Dictionary=Store.read_save(path)
	ck(read.ok and not read.recovered and game.restore_save(read.data).ok,"ordinary store read accepts validated legacy session")
	ck(FileAccess.get_file_as_string(path)==bytes and not FileAccess.file_exists(path+".bak"),"legacy read never rewrites file or creates backup")
	put(path+".bak",bytes)
	var malformed_format:Dictionary=legacy.duplicate(true);malformed_format.format=true
	put(path,JSON.stringify(malformed_format))
	read=Store.read_save(path)
	ck(read.get("ok")==true and read.get("recovered")==true,"wrong-type legacy format still recovers valid backup")
	put(path,"{broken")
	read=Store.read_save(path)
	ck(read.ok and read.recovered and game.restore_save(read.data).ok and game.export_save().data==migrated,"corrupt main recovers and migrates actual legacy backup")
	ck(FileAccess.get_file_as_string(path)=="{broken" and FileAccess.get_file_as_string(path+".bak")==bytes,"legacy backup recovery writes nothing")
	ck(Store.write_save(game.export_save().data,path).ok,"explicit subsequent save writes canonical checkpoint")
	read=Store.read_save(path)
	ck(read.ok and read.data.version==10 and read.data.rules.version==6,"explicit save writes new envelope and rules versions")
	ck(FileAccess.get_file_as_string(path+".bak")==bytes,"explicit save over bad main preserves legacy backup")
	DirAccess.remove_absolute(path);DirAccess.remove_absolute(path+".bak")
	print("SHOP RETENTION MIGRATION ",checks," checks FAILURES=",failures);quit(1 if failures else 0)
