extends SceneTree
func _initialize():call_deferred("run")
func run():
	var scene=load("res://battle.tscn").instantiate();root.add_child(scene);scene.set_process(false)
	var view=scene.views[0]
	var skeleton=view._model.find_children("*","Skeleton3D",true,false)[0]
	print("model ",view._model.transform," skeleton ",skeleton.global_transform)
	var head=skeleton.find_bone("Bip001 Head")
	var mouth=skeleton.find_bone("bone_mouth")
	print("idle face direction ",skeleton.global_basis*(skeleton.get_bone_global_pose(mouth).origin-skeleton.get_bone_global_pose(head).origin))
	scene.start_battle()
	for i in range(40):scene.advance_battle(0.05)
	view=scene.views[0];skeleton=view._model.find_children("*","Skeleton3D",true,false)[0]
	print("attack actor ",view.position," rotation=",view.rotation," state=",view.state)
	print("attack face direction ",skeleton.global_basis*(skeleton.get_bone_global_pose(mouth).origin-skeleton.get_bone_global_pose(head).origin))
	print("opponent ",scene.views[3].position)
	scene.queue_free();await process_frame;quit()
