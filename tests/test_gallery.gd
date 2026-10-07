extends SceneTree
func _initialize():call_deferred("run")
func run():
	var gallery=load("res://gallery.tscn").instantiate();root.add_child(gallery);gallery.set_process(false)
	var expected=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json")).size()
	var ok=gallery.actors.size()==expected and expected>=7
	gallery._process(1.0/60.0)
	ok=ok and gallery.frame_samples.size()==1
	gallery.queue_free();await process_frame
	print("GALLERY FAILURES=",0 if ok else 1);quit(0 if ok else 1)
