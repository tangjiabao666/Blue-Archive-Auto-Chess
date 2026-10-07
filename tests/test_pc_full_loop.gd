extends SceneTree
var failures:=0
func ck(ok:bool,label:String):
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():call_deferred('run')
func run():
 var app=load('res://game.tscn').instantiate();app.save_path='user://pc-loop-'+str(Time.get_ticks_usec())+'.json';root.add_child(app);app.request_new_game()
 for i in range(300):
  if app.flow_state!='loading':break
  await process_frame
 var game=app.game;game.set_process(false)
 ck(game.get('round_result_panel')!=null,'managed runtime owns result panel')
 if failures:app.queue_free();await process_frame;quit(1);return
 var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/tactical_finished_league_v8.json'))
 ck(game.session.restore_save(saved).ok,'final checkpoint restores')
 game._refresh(true)
 ck(game.round_result_panel.visible and game.round_result_panel.new_button.visible,'final screen is presented on continue')
 game.round_result_panel.new_button.pressed.emit();await process_frame;await process_frame
 ck(app.flow_state=='title' and app.replace_dialog.visible,'restart uses same overwrite confirmation')
 app.confirm_new_game()
 for i in range(300):
  if app.flow_state!='loading':break
  await process_frame
 ck(app.flow_state=='game' and app.game.session.phase()=='preparation' and not app.game.round_result_panel.visible,'second game starts cleanly')
 app.queue_free();await process_frame;print('PC_FULL_LOOP failures=',failures);quit(1 if failures else 0)
