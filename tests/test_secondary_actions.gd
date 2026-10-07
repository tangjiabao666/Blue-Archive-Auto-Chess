extends SceneTree
var fails:=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func _initialize():call_deferred("run")
func run():
	var scene=load("res://battle.tscn").instantiate();root.add_child(scene);scene.set_process(false)
	var v=scene.views[0];var u=scene.clock.sim.units[0]
	v.consume({"type":"basic","generation":v.generation,"event_id":"basic1","actor_id":0,"tick":1,"target_cell":Vector2(0,-1),"recovery_ticks":80})
	v.update_time(0.1,u)
	ck(v.current_clip=="CH0331_Public01","basic event plays original basic clip")
	v.update_time(4.1,u);ck(v.state=="idle","basic clip completes")
	v.consume({"type":"reload","generation":v.generation,"event_id":"reload1","actor_id":0,"tick":100,"duration_ticks":54,"until_tick":154})
	v.update_time(5.1,u)
	ck(v.current_clip=="CH0331_Normal_Reload","reload event plays original reload clip")
	v.update_time(7.0,u);ck(v.state=="reload","native duration_ticks keeps real reload active until tick154")
	v.update_time(8.0,u);ck(v.state=="idle","reload completes")
	scene.queue_free();await process_frame
	print("SECONDARY ACTION FAILURES=",fails);quit(1 if fails else 0)
