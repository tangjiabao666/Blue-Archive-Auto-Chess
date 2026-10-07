extends SceneTree
const LAYOUT="res://assets/audio/combat_bus_layout.tres"
var checks:=0
var failures:=0
func ck(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;printerr("FAIL: ",label)
func _initialize():call_deferred("run")
func run():
 ck(ResourceLoader.exists(LAYOUT),"explicit production combat mix layout exists")
 if failures:finish();return
 ck(ProjectSettings.get_setting("audio/buses/default_bus_layout","")==LAYOUT,"project loads the protected bus layout at startup")
 var layout=load(LAYOUT)
 ck(layout is AudioBusLayout,"layout is a native audio bus resource")
 var master:int=AudioServer.get_bus_index("Master")
 ck(master==0 and AudioServer.bus_count==1,"existing single Master routing remains intact")
 ck(AudioServer.get_bus_effect_count(master)==1,"one output protection effect, no duplicate or capture effects")
 if AudioServer.get_bus_effect_count(master)!=1:finish();return
 var effect=AudioServer.get_bus_effect(master,0)
 ck(effect is AudioEffectHardLimiter,"modern engine peak limiter is active")
 ck(AudioServer.is_bus_effect_enabled(master,0) and not AudioServer.is_bus_bypassing_effects(master),"output protection is enabled")
 if effect is AudioEffectHardLimiter:
  ck(is_equal_approx(effect.pre_gain_db,0.0) and is_equal_approx(effect.ceiling_db,-0.3) and is_equal_approx(effect.release,0.1),"limiter adds no gain and has explicit ceiling/release")
 ck(is_zero_approx(AudioServer.get_bus_volume_db(master)) and not AudioServer.is_bus_mute(master),"default user volume and mute remain unchanged")
 var app=load("res://scripts/game_app.gd").new();app.persistence_enabled=false;root.add_child(app);app.set_process(false)
 while app.warming:await process_frame
 app.settings_values.volume=0.35;app.settings_values.muted=true;app._apply_runtime_settings()
 if DisplayServer.get_name()=="headless":
  ck(is_zero_approx(AudioServer.get_bus_volume_db(master)) and not AudioServer.is_bus_mute(master),"headless app keeps its existing no-device-settings policy")
 else:
  ck(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(master)),0.35) and AudioServer.is_bus_mute(master),"user volume and mute still control Master")
 ck(AudioServer.get_bus_effect_count(master)==1 and AudioServer.get_bus_effect(master,0)==effect,"settings changes preserve the same protection effect")
 app.settings_values.volume=1.0;app.settings_values.muted=false;app._apply_runtime_settings()
 app.act({"type":"restart","seed":17})
 ck(AudioServer.get_bus_effect_count(master)==1 and AudioServer.get_bus_effect(master,0)==effect,"restart never duplicates output protection")
 app.free();await process_frame
 ck(AudioServer.get_bus_effect_count(master)==1,"app teardown leaves the project-level layout intact")
 finish()
func finish():print("COMBAT_MIX_PROTECTION ",checks," checks; ",failures," failures");quit(1 if failures else 0)
