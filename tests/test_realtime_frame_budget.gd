extends SceneTree
var failures:=0
func ck(ok:bool,label:String)->void:
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize()->void:call_deferred('run')
func run()->void:
 var app=load('res://scripts/game_app.gd').new()
 app.new_game_mode='tactical_v1';app.managed_startup=true;app.persistence_enabled=false
 root.add_child(app);app.set_process(false)
 app.session.rules._prepare_ai(app.session.rules._player_ref('p0'));app.session.preview_roster();app._refresh(true)
 ck(app.act({'type':'start_battle'}).ok,'start battle')
 app.session._cancel_ai_jobs()
 var before:int=app.session.clock.sim.tick
 app._process(5.0)
 ck(app.session.clock.sim.tick-before==2,'a five-second hitch advances exactly two realtime ticks')
 ck(app.frame_times.back()==5.0 and app.battle_frame_times.back()==5.0,'performance reports preserve actual wall hitch')
 ck(app.visual_time<=0.100001,'presentation cannot jump ahead across dropped wall time')
 before=app.session.clock.sim.tick
 app._process(0.05)
 ck(app.session.clock.sim.tick-before==1,'normal frame resumes without catch-up debt')
 app.session.paused=true;before=app.session.clock.sim.tick;app._process(5.0)
 ck(app.session.clock.sim.tick==before,'paused hitch cannot advance combat')
 app.session.paused=false
 before=app.session.clock.sim.tick
 app._process(0.03);ck(app.session.clock.sim.tick==before,'fractional tick retained')
 app._process(5.0);ck(app.session.clock.sim.tick==before+2 and is_equal_approx(app.session.clock.accumulator,0.03),'hitch preserves existing fractional remainder')
 before=app.session.clock.sim.tick
 for value in [-1.0,NAN,INF]:app._process(value)
 ck(app.session.clock.sim.tick==before and is_finite(app.visual_time),'invalid deltas cannot poison realtime clock')
 app._process(0.02);ck(app.session.clock.sim.tick==before+1,'fractional tick completes after invalid inputs')
 app.queue_free();await process_frame
 print('REALTIME_FRAME_BUDGET failures=',failures);quit(1 if failures else 0)
