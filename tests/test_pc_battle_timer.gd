extends SceneTree
var failures:=0
func ck(ok:bool,label:String):
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():call_deferred('run')
func run():
 var app=load('res://scripts/game_app.gd').new();app.new_game_mode='tactical_v1';app.persistence_enabled=false;root.add_child(app);app.set_process(false)
 var buy:Dictionary=app.act({'type':'buy_offer','slot':0});app.act({'type':'deploy_unit','unit_id':buy.unit_id});app.act({'type':'start_battle'})
 app.session.clock.sim.tick=800
 ck(app._battle_status_text().contains('40.0 / 90'),'clock shows elapsed and hard cap')
 app.session.clock.sim.tick=1200
 ck(app._battle_status_text().contains('60.0 / 90') and app._battle_status_text().contains('加时'),'overtime shares simulator clock')
 app.session.paused=true;app._process(5.0)
 ck(app.status.text.contains('60.0 / 90'),'pause does not advance displayed battle clock')
 app.queue_free();await process_frame;print('PC_BATTLE_TIMER failures=',failures);quit(1 if failures else 0)
