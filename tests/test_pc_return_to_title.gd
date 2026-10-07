extends SceneTree
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():call_deferred('run')
func ready_game(app):
 for i in range(300):
  if app.flow_state!='loading':return
  await process_frame
 ck(false,'load finishes')
func run():
 var app=load('res://game.tscn').instantiate();app.save_path='user://pc-return-'+str(Time.get_ticks_usec())+'.json';app.settings_path=app.save_path+'.settings';root.add_child(app);app.request_new_game();await ready_game(app)
 var game=app.game;game.set_process(false)
 ck(game.has_method('request_return_to_title'),'game has safe title navigation')
 if failures:app.queue_free();await process_frame;quit(1);return
 ck(game.game_menu.title_button.visible,'managed gameplay menu has title action')
 var values:Dictionary=game.settings_values.duplicate(true);values.volume=0.37;game._apply_settings(values)
 game._open_menu();game.tactical_input.armed_actor=4
 game.request_return_to_title();await process_frame;await process_frame
 ck(app.flow_state=='title' and app.game==null,'safe prep return tears down gameplay')
 ck(not is_instance_valid(game),'game and child input/audio nodes freed')
 ck(is_equal_approx(float(app.preferences.volume),0.37),'title settings reflect in-game changes')
 app.request_continue();await ready_game(app);game=app.game;game.set_process(false)
 var path:String=game.save_path;game.save_path='user://absent-parent-dir/fail.json';game._checkpoint_dirty=true
 game.request_return_to_title();await process_frame
 ck(app.flow_state=='game' and game.return_dialog.visible,'failed save blocks teardown and requests explicit discard')
 game.return_dialog.canceled.emit();ck(app.flow_state=='game' and not game.return_dialog.visible,'cancel preserves live game')
 game.save_path=path
 game.session.rules._acquire_one_star(game.session.rules._player_ref('p0'),'yuuka');game.session.preview_roster()
 game.act({'type':'deploy_unit','unit_id':game.session.rules.get_player().bench[0]});game.act({'type':'start_battle'})
 game.request_return_to_title();ck(game.return_dialog.visible and app.flow_state=='game','midbattle return warns about prebattle resume')
 game.confirm_return_to_title();await process_frame;await process_frame
 ck(app.flow_state=='title' and not is_instance_valid(game),'confirmed battle return tears down NPC workers and runtime')
 app.request_continue();await ready_game(app);game=app.game;game.set_process(false)
 ck(game.session.phase()=='preparation','continue resumes saved preparation')
 game.save_path='user://absent-parent-dir/fail.json';game._checkpoint_dirty=true;game.request_return_to_title();game.confirm_return_to_title(true);await process_frame;await process_frame
 ck(app.flow_state=='title','explicit discard permits exit after write failure')
 app.queue_free();await process_frame;print('PC_RETURN_TITLE checks=',checks,' failures=',failures);quit(1 if failures else 0)
