extends SceneTree
var fails:=0
func ck(ok:bool,label:String):
 if not ok:fails+=1;printerr(label)
func _initialize():call_deferred("run")
func run():
 var app=load("res://scripts/gameplay.tscn").instantiate();root.add_child(app);await process_frame;app.set_process(false)
 var p:Dictionary=app.session.rules._player_ref("p0");p.shop[0]={"character_id":"shiroko","cost":2}
 var bought=app.act({"type":"buy_offer","slot":0});app.act({"type":"deploy_unit","unit_id":bought.unit_id});app.act({"type":"start_battle"})
 app.session.clock.sim.tick=20;app.session.last_error="offscreen battle: cancelled";app._refresh(false)
 ck(app.session.phase()=="error" and app.status.text.contains("结算失败"),"offscreen failure is clearly visible")
 ck(app.start_button.text=="重新开始" and not app.start_button.disabled,"error offers an enabled recovery action")
 app._process(1.0)
 ck(app.stage.bars[0].status.status.basic.remaining_seconds==4.0,"error screen preserves authoritative cooldown tick")
 app._start_pressed()
 ck(app.session.phase()=="preparation" and app.session.last_error.is_empty(),"recovery button actually restarts safely")
 app.queue_free();await process_frame
 print("OFFSCREEN ERROR UI FAILURES=",fails);quit(1 if fails else 0)
