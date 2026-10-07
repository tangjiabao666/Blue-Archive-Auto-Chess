extends SceneTree
const Session=preload("res://core/game_session.gd")
const ORIGINAL_COSTS={"shiroko":2,"hoshino":3,"hina":4,"aru":3,"yuuka":2,"aris":4,"serika":1}
const EXPANSION_COSTS={"iori":4,"tsubaki":2,"nonomi":3,"mutsuki":2,"haruna":3,"koharu":3,"asuna":1}
var failures:=0
func ck(ok:bool,label:String)->void:
	if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize()->void:
	var game=Session.new()
	var expected:Array=ORIGINAL_COSTS.keys()+EXPANSION_COSTS.keys()
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character_skills.json"))
	ck(Session.ACTIVE==expected,"original seven retained in order and all six source characters activated")
	ck(data.active_roster==expected and game.clock.sim.active_character_keys()==expected,"source and playable active catalogs agree")
	ck(data.activeRosterCount==expected.size() and game.catalog.size()==expected.size(),"active counts match fourteen real characters")
	ck(data.pending_native_roster.is_empty(),"all fourteen playable characters activated")
	ck("serina" not in Session.ACTIVE and data.future_support_roster==["serina"],"historical off-field support remains outside active board roster")
	var costs:Dictionary=ORIGINAL_COSTS.merged(EXPANSION_COSTS)
	var app=load("res://scripts/game_app.gd").new()
	for key in expected:
		ck(Session.COSTS.get(key,-1)==costs[key],"explicit autochess gold price retained: "+key)
		var source:Dictionary=game.clock.sim.character_data(key)
		ck(not source.is_empty(),"source character exists: "+key)
		var profile:Dictionary=game.profiles.get(key,{})
		ck(ResourceLoader.exists(profile.get("model_path","")),"native model exists: "+key)
		ck(ResourceLoader.exists("res://assets/ui/portraits/%s.png"%key),"native portrait exists: "+key)
		ck(not app._character_hint(key).is_empty() and app._character_hint(key).contains("EX："),"real kit hint includes EX: "+key)
		var entries:Array=game.catalog.filter(func(entry):return entry.id==key)
		ck(entries.size()==1,"exactly one catalog entry: "+key)
		if entries.size()==1:
			ck(entries[0].cost==costs[key],"catalog uses gold cost: "+key)
			ck(entries[0].ex_cooldown==5.0+5.0*source.ex.originalCost,"automatic EX cooldown still derives from source EX cost: "+key)
	ck(app._character_hint("iori").contains("三连射") and app._character_hint("iori").contains("掩体"),"Iori hint states multi-shot and actual no-cover condition")
	ck(app._character_hint("tsubaki").contains("一次") and app._character_hint("tsubaki").contains("嘲讽"),"Tsubaki hint states once-only healing and taunt")
	ck(app._character_hint("nonomi").contains("扇形"),"Nonomi hint states fan attack")
	ck(app._character_hint("mutsuki").contains("地雷") and app._character_hint("mutsuki").contains("三处"),"Mutsuki hint states persistent mines and three areas")
	ck(app._character_hint("haruna").contains("静止") and app._character_hint("haruna").contains("递减"),"Haruna hint states stationary buff and line falloff")
	ck(app._character_hint("koharu").contains("友军") and app._character_hint("koharu").contains("治疗"),"Koharu hint states ally healing")
	app.free()
	print("ACTIVE ROSTER FAILURES=",failures);quit(1 if failures else 0)
