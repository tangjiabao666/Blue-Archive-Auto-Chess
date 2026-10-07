extends SceneTree
var checks:=0
var failures:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr(label)
func _initialize():call_deferred("run")
func run():
 var app=load("res://scripts/game_app.gd").new();app.persistence_enabled=true
 app.save_path="user://smoke-app-%d.json"%Time.get_ticks_usec();app.settings_path="user://smoke-app-%d.cfg"%Time.get_ticks_usec()
 root.add_child(app);app.set_process(false)
 ck(app.stage.has_method("set_reduce_smoke"),"stage propagates visual-only smoke preference")
 if not app.stage.has_method("set_reduce_smoke"):app.free();finish();return
 var before:Dictionary=app.session.export_save().data
 app.settings_values["reduce_smoke"]=true;app._apply_runtime_settings()
 ck(app.stage.native_vfx._player.diagnostics().smoke_alpha_scale==0.55,"combat VFX receives smoke preference even in headless checks")
 ck(app.stage.native_props._particles.diagnostics().smoke_alpha_scale==0.55,"prop particle player receives same preference")
 ck(app.session.export_save().data==before,"presentation preference cannot mutate match")
 app.act({"type":"restart","seed":17})
 ck(app.stage.native_vfx._player.diagnostics().smoke_alpha_scale==0.55,"new battle roster retains visual preference")
 app.settings_values["reduce_smoke"]=false;app._apply_runtime_settings()
 ck(app.stage.native_vfx._player.diagnostics().smoke_alpha_scale==1.0 and app.stage.native_props._particles.diagnostics().smoke_alpha_scale==1.0,"off restores source particle alpha")
 app._open_menu();app.game_menu.reduce_smoke.button_pressed=true;app._close_menu()
 ck(not app.settings_values.get("reduce_smoke",false) and app.stage.native_vfx._player.diagnostics().smoke_alpha_scale==1.0,"cancel leaves rendering and saved preferences unchanged")
 app._open_menu();app.game_menu.reduce_smoke.button_pressed=true;app.game_menu.apply_button.pressed.emit()
 var saved:Dictionary=app.UserSettings.read_settings(app.settings_path)
 ck(saved.ok and saved.values.reduce_smoke and app.settings_values.reduce_smoke,"Apply signal persists smoke preference")
 ck(app.stage.native_vfx._player.diagnostics().smoke_alpha_scale==0.55,"Apply signal updates visual player")
 var accepted:Dictionary=app.settings_values.duplicate(true)
 app.settings_path="user://missing-directory/smoke.cfg"
 app._apply_settings({"volume":0.5,"muted":false,"fullscreen":false,"reduce_smoke":false})
 ck(app.settings_values==accepted and app.stage.native_vfx._player.diagnostics().smoke_alpha_scale==0.55,"failed write cannot silently change rendering")
 app.free();finish()
func finish():print("SMOKE APP ",checks," checks; ",failures," failures");quit(1 if failures else 0)
