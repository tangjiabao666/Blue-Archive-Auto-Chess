extends SceneTree
const Store=preload('res://core/session_save_store.gd')
var failures:=0
func ck(ok:bool,label:String)->void:
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize()->void:call_deferred('run')
func run()->void:
 var app=load('res://scripts/game_app.gd').new();app.new_game_mode='tactical_v1';app.persistence_enabled=false;root.add_child(app);app.set_process(false);await process_frame
 ck(app.stage.views.size()>0,'new-game opponent preview is visible')
 var final_save:Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/tactical_finished_league_v8.json'))
 app.save_path='user://test-final-checkpoint-ui.json';ck(Store.write_save(final_save,app.save_path).ok,'actual final-game fixture saved')
 app.persistence_enabled=true;ck(app._load_checkpoint().ok and app.session.phase()=='finished','final checkpoint loads')
 ck(app.stage.views.is_empty() and app.stage.units.is_empty(),'loading finished game clears unrelated old-preview characters')
 ck(not app.tactical_hud.visible and app.status.text.contains('名'),'finished game shows outcome without combat input')
 app._open_menu();ck(not app.game_menu.save_button.disabled,'final score can be saved from menu')
 app.queue_free();await process_frame;print('TACTICAL_FINAL_CHECKPOINT_UI failures=',failures);quit(1 if failures else 0)
