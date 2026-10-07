extends SceneTree
var failures:=0
func ck(ok:bool,message:String):
	if not ok:failures+=1;printerr(message)
func _initialize():call_deferred("run")
func run():
	ck(ResourceLoader.exists("res://tests/four_combat_preview.tscn"),"four-player rendered preview scene exists")
	if failures:quit(1);return
	var preview=load("res://tests/four_combat_preview.tscn").instantiate();root.add_child(preview);preview.set_process(false)
	ck(preview.session.clock.sim.units.size()==8,"preview has exactly four per side")
	for team in range(2):
		var count:=0;var sum_x:=0.0
		for unit in preview.session.clock.sim.units:
			if unit.team==team:count+=1;sum_x+=unit.cell.x
		ck(count==4 and absf(sum_x)<0.001,"centered four-character preview")
	preview.queue_free();await process_frame
	print("FOUR PREVIEW FAILURES=",failures);quit(1 if failures else 0)
