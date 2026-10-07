extends SceneTree
var failures:=0
var checks:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize()->void:call_deferred('run')
func run()->void:
 var app=load('res://scripts/game_app.gd').new();app.new_game_mode='tactical_v1';app.persistence_enabled=false;root.add_child(app);app.set_process(false);await process_frame
 app._refresh_ui()
 ck(app.economy.text.contains('/6') and app.economy.text.contains('积分') and not app.economy.text.contains('生命'),'league header shows six rounds and points')
 ck(app.standings.text.contains('积分排名') and app.standings.text.contains('1.'),'standings show shared first ranks initially')
 ck(app.standings.tooltip_text.contains('剩余生命'),'standings explain tiebreak')
 var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/tactical_legacy_session_v5.json'))
 app.session.restore_save(old);app._refresh_ui()
 ck(app.economy.text.contains('生命') and not app.economy.text.contains('/6'),'legacy header remains survival')
 app.queue_free();await process_frame
 print('TACTICAL_LEAGUE_UI checks=',checks,' failures=',failures);quit(1 if failures else 0)
