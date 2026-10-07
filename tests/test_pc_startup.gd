extends SceneTree
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
 ck(false,'startup resolves within bound')
func run():
 var app=load('res://game.tscn').instantiate()
 ck(app.has_method('request_new_game'),'frontend starts selected game')
 if failures:app.free();quit(1);return
 var suffix=str(Time.get_ticks_usec());app.save_path='user://pc-start-'+suffix+'.json';app.settings_path='user://pc-start-'+suffix+'.cfg'
 root.add_child(app);await process_frame
 app.request_new_game();app.request_new_game();await wait_ready(app)
 ck(app.flow_state=='game' and is_instance_valid(app.game),'one explicit new game enters gameplay')
 ck(app.game.session.phase()=='preparation' and not app.game.game_menu.visible,'new game starts preparation without old startup overlay')
 ck(FileAccess.file_exists(app.save_path),'new checkpoint established after explicit start')
 var seed:int=app.game.session.seed
 app._show_title();await process_frame
 ck(app.game==null and app.flow_state=='title' and not app.title_menu.continue_button.disabled,'title refreshes continue after teardown')
 app.request_continue();await wait_ready(app)
 ck(app.flow_state=='game' and app.game.session.seed==seed,'continue restores original seed')
 app._show_title();await process_frame
 var hash:String=FileAccess.get_sha256(app.save_path)
 app._open_settings();ck(app.settings_menu.visible and not app.settings_menu.save_button.visible,'title settings has no game persistence actions')
 ck(app.settings_menu._panel.find_children('*','Label',false,false).any(func(label):return label.text=='设置'),'title preferences dialog has its own heading')
 app.settings_menu.volume.value=42;app._close_settings()
 ck(not FileAccess.file_exists(app.settings_path) and FileAccess.get_sha256(app.save_path)==hash,'cancel settings writes nothing')
 app._open_settings();app.settings_menu.volume.value=42;app.settings_menu.apply_button.pressed.emit()
 ck(FileAccess.file_exists(app.settings_path) and FileAccess.get_sha256(app.save_path)==hash,'apply changes only settings')
 app.queue_free();await process_frame;print('PC_STARTUP checks=',checks,' failures=',failures);quit(1 if failures else 0)
