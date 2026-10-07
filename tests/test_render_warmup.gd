extends SceneTree
func _initialize():call_deferred("run")
func run():
	var warm=load("res://scripts/render_warmup.gd").new();root.add_child(warm)
	await warm.run({})
	var ok:bool=not warm.completed and warm.report.is_empty() and warm.get_child_count()==0
	warm.queue_free();await process_frame
	print("HEADLESS WARMUP SKIP=",ok," (no GPU verification claim)");quit(0 if ok else 1)
