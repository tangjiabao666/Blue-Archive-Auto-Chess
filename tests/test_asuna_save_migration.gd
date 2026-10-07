extends SceneTree
const TacticalProjection=preload("res://tests/tactical_save_projection.gd")
const Session=preload("res://core/game_session.gd")
const Rules=preload("res://core/prototype_match.gd")
const Store=preload("res://core/session_save_store.gd")
const SaveProjection=preload("res://tests/asuna_save_projection.gd")
const FIXTURES=["shop_retention_legacy_session_v1.json","normal_target_legacy_session_v2.json","reinforcement_legacy_session_v3.json","asuna_legacy_session_v4_pending.json","asuna_legacy_session_v4_claimed.json"]
const FIXTURE_HASHES={
	"shop_retention_legacy_session_v1.json":"5c556cc219e63f0d7e5ed16f07e2b660a0b7a106ebfa4b0ae744b8cd465da7da",
	"normal_target_legacy_session_v2.json":"7e361755beadaa870943a480d98e08cf0168ebc1831387bdcc7c399485d7ebcb",
	"reinforcement_legacy_session_v3.json":"9d9611ad8a098e37d50f13d73e297fa3dca20051d32f4b32500423de182c9787",
	"asuna_legacy_session_v4_pending.json":"937b7a0060867e4a88ccc7fdddb358f156d30e1123184853d114690ea4df4594",
	"asuna_legacy_session_v4_claimed.json":"4348a6c7147dca0f6ba9f326bbd529cc0fd2ce3e7f38bfc13444a5648bc7ebf1",
}
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func fixture(name:String)->Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/"+name))
func live(game)->Dictionary:
	return {"rules":game.rules.snapshot(),"seed":game.seed,"positions":game.positions.duplicate(true),"manual":game.manual_positions.duplicate(true),"clock":game.clock,"navigation":game.navigation,"generation":game.clock.generation,"accumulator":game.clock.accumulator,"phase":game.phase(),"paused":game.paused,"showing_result":game.showing_result,"error":game.last_error,"simulation":game.clock.sim.snapshot(),"jobs":game._ai_jobs.duplicate(),"feedback":game.battle_feedback(),"ids":game.id_to_unit.duplicate(true),"policy":game.normal_target_policy()}
func reject(game,payload:Dictionary,label:String)->void:
	var before:Dictionary=live(game);var original:Dictionary=payload.duplicate(true)
	var result:Dictionary=game.restore_save(payload)
	ck(not result.ok and not result.error.is_empty(),"reject "+label)
	ck(live(game)==before and payload==original,"atomic rejection: "+label)
func project(current:Dictionary,source:Dictionary)->Dictionary:
	var result:Dictionary=TacticalProjection.legacy_envelope(current)
	result.rules.catalog=SaveProjection.legacy_catalog(result.rules.catalog)
	ck(result.rules.catalog.size()==13,"inverse validates exact appended Asuna row")
	result.version=source.version
	if source.version<4:
		result.rules.version=source.rules.version;result.rules.config.erase("reinforcement_recruitment")
		for player in result.rules.players:
			ck(player.reinforcement.is_empty(),"old disabled rules receive no reinforcement")
			player.erase("reinforcement")
			if source.version==1:player.erase("shop_locked")
	if source.version<3:result.erase("normal_target_policy")
	return Rules.new()._normalize_json(result)
func put(path:String,contents:String)->void:
	var file=FileAccess.open(path,FileAccess.WRITE);ck(file!=null,"fixture file opens")
	if file!=null:file.store_string(contents);file.close()
func _initialize()->void:
	var game=Session.new();ck(game.new_game(812).ok,"new session initializes")
	var baseline:Dictionary=fixture(FIXTURES[3])
	var old_catalog:Array=baseline.rules.catalog
	ck(Session.SAVE_VERSION==10 and Rules.VERSION==6,"canonical Save10 with unchanged Rules6")
	ck(game.catalog.size()==14 and Session.ACTIVE.size()==14,"exactly fourteen active catalog entries")
	ck(Session.COSTS.get("asuna")==1 and game.catalog.back()==SaveProjection.ASUNA,"Asuna costs one gold and keeps source-derived fifteen-second EX")
	ck(Rules.new()._normalize_json(SaveProjection.legacy_catalog(game.catalog))==Rules.new()._normalize_json(old_catalog),"original thirteen catalog rows and order unchanged")
	ck(game.rules.snapshot().config.initial_level==4 and game.rules.snapshot().config.max_level==6 and game.rules.snapshot().config.bench_capacity==9,"population four through six and bench nine unchanged")
	if failures:print("ASUNA SAVE MIGRATION ",checks," checks FAILURES=",failures);quit(1);return
	for name in FIXTURES:
		ck(FileAccess.get_sha256("res://tests/fixtures/"+name)==FIXTURE_HASHES[name],"genuine legacy bytes stay frozen: "+name)
		var source:Dictionary=fixture(name);var original:Dictionary=source.duplicate(true)
		ck(source.rules.catalog==old_catalog,"all genuine legacy catalogs are identical: "+name)
		var loaded:Dictionary=game.restore_save(source)
		ck(loaded.ok,"genuine legacy migrates: "+name)
		if not loaded.ok:print("MIGRATION REJECTED ",name,": ",loaded.error);quit(1);return
		var canonical:Dictionary=game.export_save().data
		ck(canonical.version==10 and canonical.rules.version==6 and canonical.rules.catalog==game.catalog,"legacy export is exact Save10/Rules6/catalog14")
		ck(project(canonical,source)==Rules.new()._normalize_json(source),"every original field survives: "+name)
		ck(source==original,"successful migration leaves caller untouched")
		for repeat in range(3):ck(game.restore_save(source).ok and game.export_save().data==canonical,"repeat migration consumes no RNG or offers")
		var peer=Session.new();ck(peer.restore_save(JSON.parse_string(JSON.stringify(canonical))).ok and peer.export_save().data==canonical,"canonical JSON roundtrip")
		var caller:Dictionary=canonical.duplicate(true);ck(peer.restore_save(caller).ok,"caller payload restores")
		caller.rules.players[0].gold=0;caller.rules.catalog.back().name="changed";caller.positions.clear()
		ck(peer.export_save().data==canonical,"restored migration detached from caller")
		var exported:Dictionary=peer.export_save().data;exported.rules.catalog.back().cost=999;exported.rules.players[0].shop.clear()
		ck(peer.export_save().data==canonical,"export detached from live state")
		ck(game.command({"type":"refresh_shop"}).ok==peer.command({"type":"refresh_shop"}).ok and game.export_save().data==peer.export_save().data,"same continuation shares expanded-catalog RNG deterministically")
		_test_invalid(game,source,canonical)
		_test_store(name,source,canonical)
	_test_reinforcement(baseline)
	_test_projection_guards(game.catalog)
	_test_asuna_roundtrip()
	print("ASUNA SAVE MIGRATION ",checks," checks FAILURES=",failures);quit(1 if failures else 0)
func _test_invalid(game,source:Dictionary,canonical:Dictionary)->void:
	var invalid:Array=[]
	for version in [1,2,3,4,5]:
		var bad:Dictionary=source.duplicate(true);bad.version=version
		if version>=3:bad["normal_target_policy"]=source.get("normal_target_policy","nearest")
		else:bad.erase("normal_target_policy")
		var paired:bool=(version==1 and source.rules.version==4) or (version in [2,3] and source.rules.version==5) or (version==4 and source.rules.version==6)
		if not paired:invalid.append([bad,"legacy pair envelope%d/rules%d"%[version,source.rules.version]])
	for payload in [source,canonical]:
		var bad:Dictionary=payload.duplicate(true);bad.rules.catalog.reverse();invalid.append([bad,"reordered catalog"])
		bad=payload.duplicate(true);bad.rules.catalog.append({"id":"extra","name":"Extra","cost":2,"ex_cooldown":15.0});invalid.append([bad,"unknown catalog row"])
		bad=payload.duplicate(true);bad.rules.catalog.append(bad.rules.catalog[0].duplicate(true));invalid.append([bad,"duplicate catalog row"])
		bad=payload.duplicate(true);bad.rules.catalog[0].extra=0;invalid.append([bad,"unknown catalog field"])
		for key in ["id","name","cost","ex_cooldown"]:
			bad=payload.duplicate(true);bad.rules.catalog[0].erase(key);invalid.append([bad,"missing catalog "+key])
		for key in ["name","cost","ex_cooldown"]:
			bad=payload.duplicate(true);bad.rules.catalog[0][key]="changed" if key=="name" else bad.rules.catalog[0][key]+1;invalid.append([bad,"changed catalog "+key])
		for cost in [0,-1,1.5,true,"2",null]:
			bad=payload.duplicate(true);bad.rules.catalog[0].cost=cost;invalid.append([bad,"invalid catalog cost"])
		bad=payload.duplicate(true);bad.rules.rng_state=0;invalid.append([bad,"invalid RNG"])
		bad=payload.duplicate(true);bad.seed+=1;invalid.append([bad,"wrong seed"])
		bad=payload.duplicate(true);bad.rules.players[0].gold="16";invalid.append([bad,"wrong gold type"])
		bad=payload.duplicate(true);bad.rules.next_opponent.opponent_id="p0";invalid.append([bad,"corrupt opponent"])
		bad=payload.duplicate(true);bad.positions[bad.positions.keys()[0]]=[0,-1];invalid.append([bad,"corrupt placement"])
		bad=payload.duplicate(true);bad.rules.config.income+=1;invalid.append([bad,"unsupported config"])
		bad=payload.duplicate(true);bad.extra=true;invalid.append([bad,"unknown envelope field"])
	var bad:Dictionary=source.duplicate(true);bad.rules.catalog=canonical.rules.catalog.duplicate(true);invalid.append([bad,"legacy envelope with catalog14"])
	bad=canonical.duplicate(true);bad.rules.catalog=source.rules.catalog.duplicate(true);invalid.append([bad,"Save5 with catalog13"])
	for version in [1,2,3,4]:
		bad=canonical.duplicate(true);bad.version=version;invalid.append([bad,"catalog14 under legacy envelope"])
	for key in SaveProjection.ASUNA:
		bad=canonical.duplicate(true);bad.rules.catalog.back().erase(key);invalid.append([bad,"missing Asuna field "+key])
	bad=canonical.duplicate(true);bad.rules.catalog.back().extra=0;invalid.append([bad,"extra Asuna field"])
	bad=canonical.duplicate(true);bad.rules.catalog.back().cost=2;invalid.append([bad,"Asuna wrong gold cost"])
	bad=canonical.duplicate(true);bad.rules.catalog.back().ex_cooldown=20.0;invalid.append([bad,"Asuna wrong EX cooldown"])
	bad=canonical.duplicate(true);bad.rules.catalog.back().name="Asuna";invalid.append([bad,"Asuna wrong display name"])
	if source.version==4:
		bad=source.duplicate(true);bad.rules.players[0].reinforcement.offers[0]="asuna";invalid.append([bad,"legacy event references new character"])
		bad=source.duplicate(true);bad.rules.players[0].erase("reinforcement");invalid.append([bad,"Save4 missing reinforcement schema"])
		bad=source.duplicate(true);bad.rules.players[0].shop_locked=1;invalid.append([bad,"Save4 nonboolean retained shop"])
	game.paused=true;game.showing_result=true
	for entry in invalid:reject(game,entry[0],entry[1])
func _test_store(name:String,source:Dictionary,canonical:Dictionary)->void:
	var bytes:String=FileAccess.get_file_as_string("res://tests/fixtures/"+name)
	var path:="user://asuna-save-%d-%d.json"%[OS.get_process_id(),checks]
	put(path,bytes)
	var result:Dictionary=Store.read_save(path)
	ck(result.ok and not result.recovered and result.data==source,"store returns genuine legacy input without rewriting")
	ck(FileAccess.get_file_as_string(path)==bytes and not FileAccess.file_exists(path+".bak"),"legacy read preserves disk bytes")
	put(path+".bak",bytes)
	var hybrid:Dictionary=canonical.duplicate(true);hybrid.version=4
	for broken in ["{broken",JSON.stringify(hybrid)]:
		put(path,broken);result=Store.read_save(path)
		var game=Session.new()
		ck(result.ok and result.recovered and game.restore_save(result.data).ok and game.export_save().data==canonical,"invalid main recovers exact legacy migration")
		ck(FileAccess.get_file_as_string(path)==broken and FileAccess.get_file_as_string(path+".bak")==bytes,"backup migration performs no writes")
	ck(Store.write_save(canonical,path).ok,"explicit save writes canonical migration")
	result=Store.read_save(path)
	ck(result.ok and not result.recovered and result.data.version==10 and result.data.rules.catalog.size()==14,"explicit save stores new envelope/catalog")
	ck(FileAccess.get_file_as_string(path+".bak")==bytes,"known-good legacy backup survives corrupt primary replacement")
	DirAccess.remove_absolute(path);DirAccess.remove_absolute(path+".bak")
func _test_reinforcement(pending:Dictionary)->void:
	var game=Session.new();ck(game.restore_save(pending).ok,"pending Save4 restores")
	ck(game.rules.get_reinforcement()==Rules.new()._normalize_json(pending.rules.players[0].reinforcement) and game.rules.get_player().shop_locked,"pending offers and retained shop unchanged")
	ck(game.normal_target_policy()=="wounded" and game.rules.snapshot().last_result==Rules.new()._normalize_json(pending.rules.last_result),"tactic and full battle history unchanged")
	var before:Dictionary=live(game)
	ck(game.command({"type":"start_battle"}).error=="reinforcement_pending" and live(game)==before,"migration does not bypass pending recruitment")
	ck(game.command({"type":"claim_reinforcement","round":3,"slot":1}).ok,"existing offer can be claimed")
	var claimed:Dictionary=game.export_save().data
	ck(project(claimed,fixture(FIXTURES[4]))==Rules.new()._normalize_json(fixture(FIXTURES[4])),"claim preserves exact pre-activation outcome including IDs and RNG")
	var peer=Session.new();ck(peer.restore_save(claimed).ok and not peer.command({"type":"claim_reinforcement","round":3,"slot":1}).ok and peer.export_save().data==claimed,"claim remains one-time after migrated save/load")
func _test_projection_guards(catalog:Array)->void:
	for key in SaveProjection.ASUNA:
		var bad:Array=catalog.duplicate(true);bad.back().erase(key)
		ck(SaveProjection.legacy_catalog(bad).is_empty(),"inverse rejects missing Asuna field "+key)
	var bad:Array=catalog.duplicate(true);bad.back().cost=2
	ck(SaveProjection.legacy_catalog(bad).is_empty(),"inverse rejects changed Asuna cost")
	bad=catalog.duplicate(true);bad.back().extra=true
	ck(SaveProjection.legacy_catalog(bad).is_empty(),"inverse rejects unknown Asuna field")
	bad=catalog.duplicate(true);bad.reverse()
	ck(SaveProjection.legacy_catalog(bad).is_empty(),"inverse rejects reordered Asuna row")
func _test_asuna_roundtrip()->void:
	var game=Session.new();ck(game.new_game(17).ok,"Asuna economy fixture initializes")
	var player:Dictionary=game.rules._player_ref("p0");player.gold=100
	for slot in range(3):player.shop[slot]={"character_id":"asuna","cost":1}
	var first:Dictionary=game.command({"type":"buy_offer","slot":0})
	ck(first.ok and game.command({"type":"deploy_unit","unit_id":first.unit_id}).ok,"Asuna buys for one gold and deploys")
	ck(game.place(first.unit_id,Vector2(-3.1234567,4.234567)),"Asuna receives precise manual position")
	ck(game.command({"type":"buy_offer","slot":1}).ok and game.rules.get_player().units.size()==2,"two Asuna copies stay one star")
	var merged:Dictionary=game.command({"type":"buy_offer","slot":2})
	player=game.rules.get_player()
	ck(merged.ok and merged.unit_id==first.unit_id and merged.merged_ids.size()==2 and player.units.size()==1 and player.units[0].star==2 and player.units[0].ex_enabled,"three Asuna copies merge once into deployed survivor")
	ck(player.gold==97 and game.positions[first.unit_id]==Vector2(-3.1234567,4.234567) and game.manual_positions.has(first.unit_id),"merge preserves ID and position and costs exactly three gold")
	var payload:Dictionary=game.export_save().data
	var peer=Session.new();ck(peer.restore_save(JSON.parse_string(JSON.stringify(payload))).ok and peer.export_save().data==payload,"Save5 roundtrips actual Asuna unit and placements")
	for buy in range(2):ck(peer.command({"type":"buy_xp"}).ok,"population four upgrades")
	ck(peer.rules.get_player().level==5,"population reaches five")
	for buy in range(3):ck(peer.command({"type":"buy_xp"}).ok,"population five upgrades")
	ck(peer.rules.get_player().level==6,"population reaches six")
	var before:Dictionary=live(peer)
	ck(not peer.command({"type":"buy_xp"}).ok and live(peer)==before,"population remains capped at six transactionally")
	player=peer.rules._player_ref("p0")
	player.shop[0]={"character_id":"asuna","cost":1}
	ck(peer.command({"type":"buy_offer","slot":0}).ok,"fresh Asuna after two-star merge remains buyable")
	player=peer.rules.get_player()
	ck(player.units.size()==2 and player.units[0].star==2 and player.units[1].star==1,"two-star Asuna never participates in another merge")
	payload=peer.export_save().data
	ck(game.restore_save(payload).ok and game.export_save().data==payload,"capacity and mixed-star Asuna checkpoint roundtrips")
	reject(game,fixture(FIXTURES[3]).merged({"version":5},true),"up-versioning an old catalog cannot fabricate Save5")
