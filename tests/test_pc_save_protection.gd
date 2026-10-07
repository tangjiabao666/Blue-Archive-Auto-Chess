extends SceneTree
const Store=preload('res://core/session_save_store.gd')
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():call_deferred('run')
func wait_ready(app):
 for i in range(240):
  if app.flow_state!='loading':return
  await process_frame
 ck(false,'load finishes')
func run():
 var app=load('res://game.tscn').instantiate();ck(app.has_method('confirm_new_game'),'replacement confirmation supported')
 if failures:app.free();quit(1);return
 app.save_path='user://pc-protect-'+str(Time.get_ticks_usec())+'.json';app.settings_path=app.save_path+'.cfg'
 var session=load('res://core/game_session.gd').new();session.new_game(23,'tactical_v1');var payload:Dictionary=session.export_save().data
 Store.write_save(payload,app.save_path);Store.write_save(payload,app.save_path);var before:String=FileAccess.get_sha256(app.save_path);var backup:String=FileAccess.get_sha256(app.save_path+'.bak')
 root.add_child(app);await process_frame
 app.request_new_game();ck(app.replace_dialog.visible and app.game==null,'existing main or backup requires confirmation')
 app.replace_dialog.canceled.emit();ck(FileAccess.get_sha256(app.save_path)==before and FileAccess.get_sha256(app.save_path+'.bak')==backup,'cancel preserves both checkpoint files')
 app.request_new_game();session.new_game(24,'tactical_v1');Store.write_save(session.export_save().data,app.save_path)
 app.confirm_new_game();ck(app.flow_state=='title' and app.game==null and app.replace_dialog.visible,'changed save requires new confirmation')
 app.replace_dialog.canceled.emit()
 var f=FileAccess.open(app.save_path,FileAccess.WRITE);f.store_string('{}');f.close()
 f=FileAccess.open(app.save_path+'.bak',FileAccess.WRITE);f.store_string('{}');f.close()
 app.request_continue();ck(app.flow_state=='title' and app.game==null,'continue revalidates files after title display')
 app.request_new_game();ck(app.replace_dialog.visible and FileAccess.get_file_as_string(app.save_path)=='{}','corrupt files also require explicit replacement')
 app.replace_dialog.canceled.emit()
 app.save_path='user://missing-pc-'+str(Time.get_ticks_usec())+'/save.json';app.request_new_game();await wait_ready(app)
 ck(app.flow_state=='title' and app.game==null and not app.title_menu.message.text.is_empty(),'save failure cannot present new game as successfully started')
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/tactical_finished_league_v8.json'))
 app.save_path='user://pc-finished-'+str(Time.get_ticks_usec())+'.json';ck(Store.write_save(fixture,app.save_path).ok,'valid finished fixture saved')
 app._refresh_checkpoint();app.request_continue();await wait_ready(app)
 ck(app.flow_state=='game' and app.game.session.phase()=='finished','completed checkpoint opens final result')
 app.queue_free();await process_frame;print('PC_SAVE_PROTECTION checks=',checks,' failures=',failures);quit(1 if failures else 0)
