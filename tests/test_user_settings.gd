extends SceneTree
var checks:int=0
var failures:int=0
func ck(value:bool,message:String)->void:
 checks+=1
 if not value:failures+=1;printerr("FAIL: ",message)
func _initialize():call_deferred("run")
func run():
 ck(ResourceLoader.exists("res://core/user_settings.gd"),"persisted basic settings model exists")
 if failures:quit(1);return
 var settings=load("res://core/user_settings.gd")
 var path:String="user://settings-test-%s.cfg"%Time.get_ticks_usec()
 var missing:Dictionary=settings.read_settings(path)
 ck(missing.ok and not missing.exists and missing.values==settings.DEFAULTS,"missing file preserves defaults")
 ck(missing.values.get("reduce_smoke",true)==false,"original smoke presentation remains the default")
 var legacy:Dictionary={"volume":0.35,"muted":true,"fullscreen":false}
 var legacy_expected:Dictionary=legacy.duplicate();legacy_expected["reduce_smoke"]=false
 var legacy_checked:Dictionary=settings.validate(legacy)
 ck(legacy_checked.ok and legacy_checked.values==legacy_expected,"legacy preference dictionaries normalize with smoke reduction off")
 var cfg=ConfigFile.new();cfg.set_value("settings","version",1)
 for key in legacy:cfg.set_value("settings",key,legacy[key])
 ck(cfg.save(path)==OK,"legacy settings fixture saved")
 var legacy_loaded:Dictionary=settings.read_settings(path)
 ck(legacy_loaded.ok and legacy_loaded.exists and legacy_loaded.values==legacy_expected,"existing version-one settings preserve values and original smoke")
 var values:Dictionary={"volume":0.35,"muted":true,"fullscreen":false,"reduce_smoke":true}
 var saved:Dictionary=settings.write_settings(values,path)
 ck(saved.ok and saved.values==values,"valid settings save includes selected smoke mode")
 var restored:Dictionary=settings.read_settings(path)
 ck(restored.ok and restored.exists and restored.values==values,"smoke reduction survives settings round trip")
 var saved_bytes:String=FileAccess.get_file_as_string(path)
 for bad in [{"volume":-0.1,"muted":false,"fullscreen":false},{"volume":1.1,"muted":false,"fullscreen":false},{"volume":NAN,"muted":false,"fullscreen":false},{"volume":INF,"muted":false,"fullscreen":false},{"volume":0.5,"muted":"false","fullscreen":false},{"volume":0.5,"muted":false,"fullscreen":1}]:
  ck(not settings.write_settings(bad,path).ok,"reject invalid value types/range")
  ck(settings.read_settings(path).values==values,"failed save leaves previous settings")
 for invalid in [0,1,0.55,"false","true",null,[],{}]:
  var bad:Dictionary=values.duplicate();bad["reduce_smoke"]=invalid
  ck(not settings.write_settings(bad,path).ok,"smoke reduction rejects non-boolean value %s"%str(invalid))
  ck(FileAccess.get_file_as_string(path)==saved_bytes,"invalid smoke setting leaves file unchanged")
 var temporary:String=path+".tmp"
 ck(DirAccess.make_dir_absolute(ProjectSettings.globalize_path(temporary))==OK,"failed-write fixture obstructs only temporary destination")
 var changed:Dictionary=values.duplicate();changed["reduce_smoke"]=false
 ck(not settings.write_settings(changed,path).ok,"temporary write failure reported")
 ck(settings.read_settings(path).values==values and FileAccess.get_file_as_string(path)==saved_bytes,"write failure preserves previously selected smoke mode and settings bytes")
 ck(DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))==OK,"failed-write fixture removed")
 ck(settings.write_settings(changed,path).ok and settings.read_settings(path).values==changed,"smoke reduction can be turned off and persisted again")
 cfg=ConfigFile.new();cfg.set_value("settings","version",1);cfg.set_value("settings","reduce_smoke","true");cfg.save(path)
 var invalid_file:Dictionary=settings.read_settings(path)
 ck(not invalid_file.ok and invalid_file.values==settings.DEFAULTS,"malformed persisted smoke option falls back safely")
 cfg=ConfigFile.new();cfg.set_value("settings","version",999);cfg.save(path)
 var future:Dictionary=settings.read_settings(path)
 ck(not future.ok and future.values==settings.DEFAULTS,"unknown version falls back without applying values")
 var file=FileAccess.open(path,FileAccess.WRITE);file.store_string("not valid [config");file.close()
 var corrupt:Dictionary=settings.read_settings(path)
 ck(not corrupt.ok and corrupt.values==settings.DEFAULTS,"malformed settings safely use defaults")
 ck(not settings.write_settings(values,"user://missing-settings-parent/file.cfg").ok,"write failure reported")
 DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 print("USER_SETTINGS ",checks," checks; ",failures," failures");quit(1 if failures else 0)
