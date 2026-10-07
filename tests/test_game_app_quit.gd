extends SceneTree
class InspectApp extends "res://scripts/game_app.gd":
 var quit_calls:int=0
 func _exit_application()->void:quit_calls+=1
var failures:int=0
var checks:int=0
func ck(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",message)
func _initialize():call_deferred("run")
func run():
 var app=InspectApp.new()
 ck(app.has_method("_request_quit"),"quit flow can preserve unsaved state on failure")
 if failures:app.free();quit(1);return
 var suffix:String=str(Time.get_ticks_usec());app.persistence_enabled=true
 app.save_path="user://untouched-"+suffix+".json";app.settings_path="user://quit-settings-"+suffix+".cfg"
 var file=FileAccess.open(app.save_path,FileAccess.WRITE);file.store_string("preexisting file");file.close()
 root.add_child(app);app.set_process(false)
 app._request_quit()
 ck(app.quit_calls==1 and FileAccess.get_file_as_string(app.save_path)=="preexisting file","unplayed launch exits without overwriting any prior checkpoint")
 app.save_path="user://missing-"+suffix+"/session.json"
 ck(app.act({"type":"buy_offer","slot":0}).ok,"play is allowed when autosave cannot write")
 ck(app.notice.text.contains("保存"),"autosave failure is visible")
 app._request_quit()
 ck(app.quit_calls==1 and app.quit_dialog.visible and app.game_menu.visible,"failed save requires explicit exit confirmation")
 app.quit_dialog.canceled.emit()
 ck(app.quit_calls==1 and not app.quit_dialog.visible,"cancel keeps game running")
 app._request_quit();app.quit_dialog.confirmed.emit()
 ck(app.quit_calls==2,"explicit confirmation permits unsaved exit")
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(app.save_path.get_base_dir()))
 ck(app._save_checkpoint(true).ok,"save can be retried after storage recovers")
 ck(app.notice.text.is_empty() and app.shop_odds_label.visible,"successful retry removes only the obsolete save warning")
 app.free();print("GAME_APP_QUIT ",checks," checks; ",failures," failures");quit(1 if failures else 0)
