extends SceneTree
func _initialize():
	call_deferred("run")
func run():
	var scene=load("res://battle.tscn").instantiate()
	root.add_child(scene);scene.set_process(false)
	for m in scene.views[0]._model.find_children("*","MeshInstance3D",true,false):print(m.name," visible=",m.visible)
	var player=scene.views[0].player
	for name in ["CH0331_Normal_Idle"]:
		var a=player.get_animation(name)
		for i in a.get_track_count():
			if a.track_get_type(i)==Animation.TYPE_VALUE: print(name," ",a.track_get_path(i))
	scene.queue_free();await process_frame;quit()
