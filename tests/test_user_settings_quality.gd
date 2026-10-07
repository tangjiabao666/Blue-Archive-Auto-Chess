extends SceneTree
var checks:int=0
var failures:int=0
func ck(value:bool,message:String)->void:
 checks+=1
 if not value:failures+=1;printerr("FAIL: ",message)
func _initialize():call_deferred("run")
func run():
 var settings=load("res://core/user_settings.gd")
 # Removing platform defaults or optional-field validation must break this suite.
 ck(settings.has_method("with_quality_defaults"),"settings expose explicit platform quality defaults")
 if failures:quit(1);return
 var legacy:Dictionary={"volume":0.35,"muted":true,"fullscreen":false,"reduce_smoke":true}
 var original:Dictionary=legacy.duplicate(true)
 var desktop:Dictionary=settings.with_quality_defaults(legacy)
 var mobile:Dictionary=settings.with_quality_defaults(legacy,true)
 ck(desktop==dict_with(legacy,{"quality_preset":"high","render_scale":1.0,"fps_limit":60}),"desktop default preserves authored presentation with a 60 FPS cap")
 ck(mobile==dict_with(legacy,{"quality_preset":"balanced","render_scale":0.85,"fps_limit":60}),"mobile default selects balanced 85 percent at 60 FPS")
 ck(legacy==original,"default enrichment cannot mutate its caller")
 var selected:Dictionary=dict_with(legacy,{"quality_preset":"high","render_scale":1.0,"fps_limit":120})
 ck(settings.with_quality_defaults(selected,true)==selected,"explicit high/native/120 selection survives mobile defaults")
 ck(settings.validate(legacy).values==legacy,"legacy settings retain original dictionary shape")
 ck(settings.validate(selected,true).values==selected,"mobile high/native/120 target is valid")
 for preset in ["performance","balanced","high"]:
  for scale in [0.5,0.67,0.85,1.0]:
   for fps in [30,60,90,120]:
    var options:Dictionary=dict_with(legacy,{"quality_preset":preset,"render_scale":scale,"fps_limit":fps})
    var checked:Dictionary=settings.validate(options,true)
    ck(checked.ok and checked.values==options,"supported mobile quality combination validates")
 for key in ["quality_preset","render_scale","fps_limit"]:
  var partial:Dictionary=dict_with(legacy,{key:selected[key]})
  ck(settings.validate(partial).values==partial,"optional quality fields validate independently")
 var normalized:Dictionary=settings.validate(dict_with(legacy,{"render_scale":1})).values
 ck(normalized.render_scale is float and normalized.render_scale==1.0,"integer native scale normalizes to float")
 var path:String="user://quality-settings-test-%s.cfg"%Time.get_ticks_usec()
 ck(settings.write_settings(selected,path,true).ok,"quality choices save using existing atomic path")
 var restored:Dictionary=settings.read_settings(path,true)
 ck(restored.ok and restored.exists and restored.values==selected,"quality choices survive version-one settings round trip")
 var saved_bytes:String=FileAccess.get_file_as_string(path)
 for key in invalid_options():
  for invalid in invalid_options()[key]:
   var bad:Dictionary=dict_with(selected,{key:invalid})
   ck(not settings.validate(bad,true).ok,"reject malformed %s = %s"%[key,str(invalid)])
   ck(not settings.write_settings(bad,path,true).ok,"reject malformed option before saving")
   ck(FileAccess.get_file_as_string(path)==saved_bytes,"invalid quality cannot overwrite last good settings")
 var unlimited:Dictionary=dict_with(selected,{"fps_limit":0})
 ck(settings.validate(unlimited).ok,"legacy desktop unlimited cap remains available")
 ck(not settings.validate(unlimited,true).ok,"mobile must use a finite supported frame target")
 var cfg=ConfigFile.new();cfg.set_value("settings","version",1)
 for key in legacy:cfg.set_value("settings",key,legacy[key])
 ck(cfg.save(path)==OK,"legacy version-one fixture saves")
 var legacy_loaded:Dictionary=settings.read_settings(path,true)
 ck(legacy_loaded.ok and legacy_loaded.values==legacy,"mobile reads old settings without injecting persisted changes")
 ck(settings.with_quality_defaults(legacy_loaded.values,true)==mobile,"old mobile settings resolve to safe mobile defaults")
 cfg.set_value("settings","render_scale",0.9);cfg.save(path)
 var bad_bytes:String=FileAccess.get_file_as_string(path)
 var rejected:Dictionary=settings.read_settings(path,true)
 ck(not rejected.ok and rejected.values==settings.DEFAULTS,"malformed persisted quality falls back to legacy-safe defaults")
 ck(FileAccess.get_file_as_string(path)==bad_bytes,"malformed read never rewrites original settings")
 ck(settings.write_settings(selected,path,true).ok,"restore quality fixture")
 saved_bytes=FileAccess.get_file_as_string(path)
 var temporary:String=path+".tmp"
 ck(DirAccess.make_dir_absolute(ProjectSettings.globalize_path(temporary))==OK,"obstruct temporary path to exercise atomic failure")
 var changed:Dictionary=dict_with(selected,{"quality_preset":"performance","render_scale":0.5,"fps_limit":30})
 ck(not settings.write_settings(changed,path,true).ok,"temporary quality write failure reported")
 ck(FileAccess.get_file_as_string(path)==saved_bytes,"quality write failure preserves all previous bytes")
 ck(DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))==OK,"remove temporary obstruction")
 DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 print("USER_SETTINGS_QUALITY ",checks," checks; ",failures," failures");quit(1 if failures else 0)
func dict_with(values:Dictionary,extra:Dictionary)->Dictionary:
 var result:Dictionary=values.duplicate(true);result.merge(extra,true);return result
func invalid_options()->Dictionary:
 return {"quality_preset":["", "ultra", "High",0,false,null,[],{}],"render_scale":[0.0,0.49,0.66,0.9,1.01,NAN,INF,-INF,"0.85",true,null,[],{}],"fps_limit":[-1,0,1,59,144,60.5,60.0,NAN,INF,"60",true,null,[],{}]}
