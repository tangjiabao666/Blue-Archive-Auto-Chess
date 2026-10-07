extends SceneTree
const VFX=preload("res://scripts/native_combat_vfx.gd")
const PATH="res://data/effects/asuna/battle-events-compact.json"
var fails:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:fails+=1;printerr("FAIL: "+label)
func _initialize():call_deferred("run")
func run():
 var fx=VFX.new();root.add_child(fx)
 ck(fx.has_method("configure_fixture"),"explicit opt-in fixture API exists")
 if not fx.has_method("configure_fixture"):fx.free();finish();return
 var profiles=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
 fx.configure(profiles)
 var normal_path:String=fx._events_path
 ck(normal_path==fx.EVENTS,"normal configuration always global")
 ck(fx.configure_fixture(profiles,PATH,["asuna"]),"valid inactive Asuna fixture accepted")
 ck(fx._events_path==PATH and fx._compact.activeRoster==["asuna"],"only in-memory fixture roster selected")
 var compact=JSON.parse_string(FileAccess.get_file_as_string(PATH))
 ck(compact.active==false and compact.activeRoster.is_empty(),"source manifest remains inactive")
 fx.generation=23
 var old_profile:Dictionary=fx._profiles.duplicate(true)
 for broken in [{"asuna":null},{"asuna":{}},{}]:
  ck(not fx.configure_fixture(broken,PATH,["asuna"]),"malformed profile rejected")
  ck(fx.generation==23 and fx._events_path==PATH and fx._profiles==old_profile,"failed config leaves prior state")
 for roster in [[],["asuna","asuna"],["shiroko"],[null]]:
  ck(not fx.configure_fixture(profiles,PATH,roster),"invalid/unlisted fixture selection rejected")
 var invalid="user://invalid-asuna-fixture.json"
 for field in ["active","fixtureOnly","characters","fixtureCharacters"]:
  invalid="user://invalid-asuna-fixture-"+field+".json"
  var malformed:Dictionary=compact.duplicate(true)
  malformed[field]=true if field=="active" else false if field=="fixtureOnly" else null
  var file=FileAccess.open(invalid,FileAccess.WRITE);file.store_string(JSON.stringify(malformed));file.close()
  ck(not fx.configure_fixture(profiles,invalid,["asuna"]),"malformed manifest rejected: "+field)
  ck(fx.generation==23 and fx._events_path==PATH,"invalid manifest does not reset live state")
 for field in ["active","fixtureOnly"]:
  var numeric:Dictionary=compact.duplicate(true);numeric[field]=0 if field=="active" else 1
  var path:String="user://numeric-asuna-"+field+".json"
  var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(numeric));file.close()
  ck(not fx.configure_fixture(profiles,path,["asuna"]),"boolean fixture flags never accept numeric aliases")
  ck(fx.generation==23 and fx._events_path==PATH,"numeric flag rejection preserves fixture state")
 fx.configure(profiles)
 ck(fx._events_path==normal_path and fx._compact.activeRoster.size()==14 and fx._compact.activeRoster.back()=="asuna","normal configure returns to fourteen-character live route")
 fx.free();finish()
func finish():print("ASUNA FX FIXTURE CHECKS=",checks," FAILURES=",fails);quit(1 if fails else 0)
