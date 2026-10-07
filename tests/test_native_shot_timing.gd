extends SceneTree
var fails:=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func _initialize():call_deferred("run")
func run():
	var scene=load("res://battle.tscn").instantiate();root.add_child(scene);scene.set_process(false)
	var view=scene.views[0];var unit=scene.clock.sim.units[0]
	ck(view._recovery_seconds>=2.63,"attack cadence accommodates original start/fire/recovery durations")
	view.consume({"generation":view.generation,"event_id":"shot-test","tick":1,"impact_tick":14,"actor_id":0,"target_id":3,"target_cell":Vector2(0,-2),"type":"attack"})
	view.update_time(0.50,unit)
	ck(view.current_clip=="CH0331_Normal_Attack_Start","raise weapon before contact")
	ck(absf(view._action_started_at+view._attack_start_duration+view.NATIVE_FIRE_CONTACT_OFFSET-0.70)<0.0001,"native recoil onset aligns with authoritative contact")
	view.update_time(0.70,unit)
	ck(view.current_clip=="CH0331_Normal_Attack_Ing","original firing clip active at authoritative contact")
	view.update_time(1.1,unit)
	ck(view.current_clip=="CH0331_Normal_Attack_Ing","original recoil clip not skipped")
	view.update_time(1.4,unit)
	ck(view.current_clip=="CH0331_Normal_Attack_Delay","original recovery follows firing")
	view.update_time(3.0,unit)
	ck(view.state=="idle","shot sequence returns idle")
	scene.queue_free();await process_frame
	print("NATIVE SHOT TIMING FAILURES=",fails);quit(1 if fails else 0)
