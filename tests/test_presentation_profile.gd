extends SceneTree
var fails:=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func _initialize():call_deferred("run")
func run():
	var view=load("res://scripts/unit_view.gd").new();root.add_child(view)
	var durations=JSON.parse_string(FileAccess.get_file_as_string("res://data/verified-durations.json"))
	var unit={"id":0,"team":0,"cell":Vector2(0,1),"range":2.4,"attack_ticks":54,"presentation":{"clips":{"idle":"CH0331_Formation_Idle"},"model_scale":100.0,"fire_contact_offset":0.2}}
	view.setup(unit,durations,1)
	ck(view.current_clip=="CH0331_Formation_Idle","per-character clip binding honored")
	ck(is_equal_approx(view._model.scale.x,100.0),"per-character native model scale honored")
	view.setup({"id":0,"team":0,"cell":Vector2(0,1),"range":2.4,"attack_ticks":54},durations,2)
	ck(view.current_clip=="CH0331_Normal_Idle","reused view resets to default clip map")
	ck(is_equal_approx(view._model.scale.x,130.0),"reused view resets native scale")
	view.queue_free();await process_frame
	print("PRESENTATION PROFILE FAILURES=",fails);quit(1 if fails else 0)
