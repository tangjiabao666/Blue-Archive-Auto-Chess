extends SceneTree
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():call_deferred('run')
func run():
 var app=load('res://game.tscn').instantiate();ck(app.has_method('_show_title'),'loading can return to title')
 if failures:app.free();quit(1);return
 app.save_path='user://pc-cancel-'+str(Time.get_ticks_usec())+'.json';app.settings_path=app.save_path+'.cfg';root.add_child(app);await process_frame
 app.request_new_game();ck(app._loading_panel.get_parent() is CanvasLayer and app._loading_panel.get_parent().layer>5,'loading overlay stays above runtime HUD')
 var generation:int=app._load_generation;app._show_title();await process_frame;await process_frame
 ck(app.flow_state=='title' and app.game==null and not FileAccess.file_exists(app.save_path),'cancel queued load cannot create game or save')
 app._finish_start({'ok':true,'error':''},generation,null)
 ck(app.flow_state=='title' and app.game==null,'stale success callback cannot resurrect runtime')
 app._open_settings();app._close_settings();ck(app.game==null,'opening settings never starts game')
 app.queue_free();await process_frame;print('PC_LOADING_CANCEL checks=',checks,' failures=',failures);quit(1 if failures else 0)
