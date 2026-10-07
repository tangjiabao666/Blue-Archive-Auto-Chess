extends SceneTree
var fails:=0
func ck(ok:bool,label:String):
 if not ok:fails+=1;printerr(label)
func _initialize():call_deferred("run")
func run():
 for profile in [2,3]:await check_profile(profile)
 print("OVERTIME UI FAILURES=",fails);quit(1 if fails else 0)
func check_profile(profile:int):
 var app=load("res://scripts/gameplay.tscn").instantiate();app.persistence_enabled=false;root.add_child(app);await process_frame;app.set_process(false)
 if profile==2:
  var historical:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/tactical_five_unit_v9.json"))
  ck(app.session.restore_save(historical).ok,"actual historical overtime profile restores")
 ck(app.session.rules_profile()==profile,"overtime UI uses requested profile "+str(profile))
 app.session.rules._prepare_ai(app.session.rules._player_ref("p0"))
 ck(app.act({"type":"start_battle"}).ok,"overtime UI enters actual battle")
 if not app.has_method("_battle_status_text"):
  ck(false,"overtime has live explanatory status");app.queue_free();await process_frame;quit(1);return
 ck(app.session.clock.sim.options.overtime_enabled,"profile enables overtime")
 var start_tick:int=1500 if profile==2 else 1200
 ck(app.session.clock.sim.options.overtime_start_seconds==(75.0 if profile==2 else 60.0),"versioned overtime start remains explicit")
 app.session.clock.sim.tick=start_tick-1
 ck(not app._battle_status_text().contains("加时"),"ordinary battle not labeled overtime")
 app.session.clock.sim.tick=start_tick+(300 if profile==2 else 100)
 app._refresh_ui()
 ck(app.status.text.contains("加时") and app.status.text.contains("60%"),"HUD explains real sustain multiplier")
 app.session.clock.sim.tick=start_tick+(600 if profile==2 else 200)
 app._process(0.0)
 ck(app.status.text.contains("20%"),"HUD updates without user interaction")
 app.session._record_feedback([{"type":"finished","reason":"elimination"}])
 var feedback=app.session.battle_feedback()
 ck(feedback.get("overtime",{}).get("active",false),"battle feedback preserves overtime state")
 app.show_battle_report()
 ck(app.report_text.text.contains("加时") and app.report_text.text.contains("20%"),"report explains final overtime state")
 app.session.clock.sim.tick=0
 ck(is_equal_approx(feedback.overtime.healing_multiplier,0.2),"recorded result does not track new simulation clock")
 app.queue_free();await process_frame
