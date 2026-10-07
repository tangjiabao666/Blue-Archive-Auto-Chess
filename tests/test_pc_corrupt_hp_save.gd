extends SceneTree
const Session=preload('res://core/game_session.gd')
const Store=preload('res://core/session_save_store.gd')
const Synthetic=preload('res://tests/synthetic_league_settlement.gd')
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():call_deferred('run')
func run():
 var game=Session.new();game.new_game(23,'tactical_v1');game.rules._prepare_ai(game.rules._player_ref('p0'));game.preview_roster()
 var battle:Dictionary=game.rules.execute({'type':'start_battle'}).battle
 ck(game.rules.execute(Synthetic.command(game,battle)).ok,'valid fabricated history')
 game.showing_result=true
 var payload:Dictionary=game.export_save().data
 var index:=0
 for field in ['duration_ticks','finish_reason']:
  for value in [true,[],{},null,'1800']:
   var broken:Dictionary=payload.duplicate(true);broken.rules.league.rounds[0].outcomes[0][field]=value
   var path:String='user://broken-hp-'+str(Time.get_ticks_usec())+'-'+str(index)+'.json';index+=1
   var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(broken));file.close()
   var hash:String=FileAccess.get_sha256(path)
   ck(not Store.read_save(path).ok,'store rejects malformed HP history')
   var app=load('res://game.tscn').instantiate();app.save_path=path;root.add_child(app)
   ck(app.flow_state=='title' and app.game==null and app.title_menu.continue_button.disabled,'corrupt checkpoint boots safely to title')
   ck(FileAccess.get_sha256(path)==hash,'rejected checkpoint bytes retained')
   app.queue_free();await process_frame
 print('PC_CORRUPT_HP_SAVE checks=',checks,' failures=',failures);quit(1 if failures else 0)
