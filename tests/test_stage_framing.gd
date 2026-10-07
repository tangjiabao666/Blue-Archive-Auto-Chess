extends SceneTree
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1280,900)
	var stage=load("res://scripts/battle_stage.gd").new();root.add_child(stage)
	var errors:=0
	for z in [-6.2,6.2]:
		for x in [-6.2,6.2]:
			var point=stage.camera.unproject_position(Vector3(x,0,z))
			if point.x<10 or point.x>1005 or point.y<105 or point.y>650:errors+=1;printerr("Unreachable field corner:",point)
	stage.queue_free();await process_frame;print("FRAMING FAILURES=",errors);quit(1 if errors else 0)
