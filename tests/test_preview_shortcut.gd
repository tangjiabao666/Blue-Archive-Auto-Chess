extends SceneTree
func _initialize():call_deferred("run")
func run():
	var app=load("res://scripts/gameplay.tscn").instantiate();root.add_child(app);current_scene=app
	await process_frame;app.set_process(false)
	var key=InputEventKey.new();key.pressed=true;key.keycode=KEY_F10
	app._unhandled_input(key)
	await process_frame;await process_frame
	var ok:bool=current_scene!=null and current_scene.scene_file_path=="res://tests/six_combat_preview.tscn"
	if not ok:printerr("F10 must launch six-versus-six user preview")
	if current_scene:current_scene.queue_free()
	await process_frame
	print("PREVIEW SHORTCUT FAILURES=",0 if ok else 1);quit(0 if ok else 1)
