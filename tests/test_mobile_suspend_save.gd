extends SceneTree
const Session=preload('res://core/game_session.gd')
const Store=preload('res://core/session_save_store.gd')
var fails:=0
func ck(ok:bool,label:String):
 if not ok:fails+=1;printerr(label)
func _initialize():call_deferred('run')
func run():
 var path:String='user://mobile-suspend-'+str(Time.get_ticks_usec())+'.json'
 var old=Session.new();old.new_game(77,'tactical_v1');var saved:Dictionary=old.export_save().data
 ck(Store.write_save(saved,path).ok,'fixture saved')
 var app=load('res://scripts/gameplay.tscn').instantiate();app.mobile_ui=true;app.persistence_enabled=false;root.add_child(app);await process_frame;app.set_process(false)
 app.save_path=path;app.persistence_enabled=true;app._checkpoint_dirty=false
 var original_bytes:String=FileAccess.get_file_as_string(path)
 app._suspend_mobile();ck(FileAccess.get_file_as_string(path)==original_bytes,'backgrounding untouched new game preserves prior checkpoint')
 app._resume_mobile();app._checkpoint_dirty=true;var current:Dictionary=app.session.export_save().data;app._suspend_mobile()
 var loaded=Session.new();var read:Dictionary=Store.read_save(path)
 ck(read.ok and loaded.restore_save(read.data).ok and loaded.rules.snapshot()==current.rules and not app._checkpoint_dirty,'dirty preparation saved on background')
 app._resume_mobile();app.queue_free();await process_frame;Engine.max_fps=0
 print('MOBILE_SUSPEND_SAVE failures=',fails);quit(1 if fails else 0)
