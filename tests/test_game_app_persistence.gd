extends SceneTree
var checks:int=0
var failures:int=0
func ck(value:bool,message:String):
 checks+=1
 if not value:failures+=1;printerr("FAIL: ",message)
func _initialize():call_deferred("run")
func run():
 var App=load("res://scripts/game_app.gd")
 var app=App.new()
 ck("persistence_enabled" in app,"game app exposes isolated persistence configuration")
 if failures:app.free();quit(1);return
 var suffix:String=str(Time.get_ticks_usec())
 app.persistence_enabled=true;app.save_path="user://app-save-"+suffix+".json";app.settings_path="user://app-settings-"+suffix+".cfg"
 root.add_child(app)
 app.set_process(false)
 ck(not FileAccess.file_exists(app.save_path),"fresh unplayed launch does not overwrite a checkpoint")
 ck(app.act({"type":"buy_offer","slot":0}).ok,"legal purchase")
 ck(FileAccess.file_exists(app.save_path),"preparation purchase creates checkpoint")
 var saved_gold:int=app.session.rules.get_player().gold
 app.session.command({"type":"buy_xp"})
 app._open_menu();app._open_menu()
 ck(app.game_menu.visible and app.session.paused,"menu pauses once and remains modal")
 ck(app._load_checkpoint().ok,"load validated preparation checkpoint")
 ck(app.session.rules.get_player().gold==saved_gold and not app.session.paused and not app.game_menu.visible,"load restores economy and closes menu safely")
 app.session.paused=true;app._open_menu();app._close_menu();app._close_menu()
 ck(app.session.paused,"already-paused state survives repeated menu close")
 app.session.paused=false;app._open_menu();app._close_menu()
 ck(not app.session.paused,"unpaused state restored on close")
 var before:Dictionary=app.settings_values.duplicate(true)
 app._open_menu();app.game_menu.volume.value=35;app._close_menu()
 ck(app.settings_values==before and not FileAccess.file_exists(app.settings_path),"cancel does not apply settings")
 app._apply_settings({"volume":0.35,"muted":true,"fullscreen":false})
 ck(app.settings_values.volume==0.35 and FileAccess.file_exists(app.settings_path),"apply persists basic preferences")
 var existing:Dictionary=app.session.rules.snapshot()
 var file=FileAccess.open(app.save_path,FileAccess.WRITE);file.store_string("broken save");file.close()
 # Prior writes may leave a legitimate backup; use an isolated absent backup path.
 app.save_path="user://app-corrupt-"+suffix+".json";file=FileAccess.open(app.save_path,FileAccess.WRITE);file.store_string("broken save");file.close()
 ck(not app._load_checkpoint().ok and app.session.rules.snapshot()==existing,"failed load cannot mutate current match")
 app.free();print("GAME_APP_PERSISTENCE ",checks," checks; ",failures," failures");quit(1 if failures else 0)
