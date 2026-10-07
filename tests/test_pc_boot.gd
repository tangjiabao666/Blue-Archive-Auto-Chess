extends SceneTree
var failures:=0
var checks:=0
func ck(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+message)
func _initialize():call_deferred('run')
func run():
 ck(ResourceLoader.exists('res://scripts/pc_app.gd'),'PC application shell exists')
 if failures:quit(1);return
 var app=load('res://game.tscn').instantiate()
 app.save_path='user://pc-boot-absent-'+str(Time.get_ticks_usec())+'.json'
 root.add_child(app);await process_frame
 ck(app.flow_state=='title','production entry starts at title')
 ck(app.game==null,'no gameplay instance behind title')
 ck(app.game==null and not app._loading_panel.visible,'no gameplay or loading presentation active on cold boot')
 ck(not FileAccess.file_exists(app.save_path),'opening title never creates save')
 ck(app.title_menu.continue_button.disabled,'continue unavailable without valid save')
 ck(app.title_menu.new_button.text=='新游戏' and app.title_menu.settings_button.text=='设置' and app.title_menu.exit_button.text=='退出','title provides clear four actions')
 await process_frame
 ck(app.game==null and not FileAccess.file_exists(app.save_path),'idle title stays inert')
 var store=load('res://core/session_save_store.gd');var session=load('res://core/game_session.gd').new()
 ck(session.new_game(23,'tactical_v1').ok,'valid checkpoint fixture')
 var payload:Dictionary=session.export_save().data
 ck(store.write_save(payload,app.save_path).ok,'write valid checkpoint')
 app._refresh_checkpoint();ck(not app.title_menu.continue_button.disabled,'validated checkpoint enables continue')
 ck(store.write_save(payload,app.save_path).ok,'create verified backup')
 var file=FileAccess.open(app.save_path,FileAccess.WRITE);file.store_string('{}');file.close()
 app._refresh_checkpoint();ck(app.checkpoint.get('recovered',false) and not app.title_menu.continue_button.disabled,'valid backup restores continue')
 ck(FileAccess.get_file_as_string(app.save_path)=='{}','reading backup does not rewrite corrupt main')
 file=FileAccess.open(app.save_path+'.bak',FileAccess.WRITE);file.store_string('{}');file.close()
 app._refresh_checkpoint();ck(app.title_menu.continue_button.disabled and app.game==null,'both corrupt remain safely on title')
 app.queue_free();await process_frame
 print('PC_BOOT checks=',checks,' failures=',failures);quit(1 if failures else 0)
