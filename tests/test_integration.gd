extends SceneTree
var fails:=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func _initialize()->void:
	call_deferred("run")
func run()->void:
	var scene=load("res://battle.tscn").instantiate()
	root.add_child(scene);scene.set_process(false)
	ck(scene.presentation_ready,"scene initializes")
	ck(scene.views.size()==6,"six native actors")
	for view in scene.views.values():
		ck(view.player!=null and view.player.get_animation_list().size()>=32,"native clips attached")
		ck(view.diagnostics().warnings.is_empty(),"all clip durations verified")
		ck(view.player.get_animation("CH0331_Move_Ing").length<0.7,"walk duration normalized")
	scene._process(0.25)
	ck(scene.views[0].diagnostics().clock>0,"preparation idle animation clock advances")
	ck(scene.place_selected(Vector2(-2.25,3.123)),"prep place works")
	scene.start_battle();scene.advance_battle(1.0)
	ck(not scene.place_selected(Vector2(2.23,3.15)),"no moving pieces manually during battle")
	scene.toggle_pause();var tick=scene.clock.sim.tick
	scene.advance_battle(0.2)
	ck(scene.clock.sim.tick==tick,"public advance respects pause")
	scene.toggle_pause()
	for i in range(1200):
		scene.advance_battle(0.05)
		if scene.clock.sim.phase=="finished":break
	ck(scene.clock.sim.phase=="finished","full scene reaches result")
	ck(scene.event_counts.get("attack",0)>0 and scene.event_counts.get("skill",0)>0,"attacks and skills consumed")
	var final_snapshot=scene.clock.sim.snapshot()
	var visual_clock=scene.views[0].diagnostics().clock
	scene._process(0.25)
	ck(scene.views[0].diagnostics().clock>visual_clock,"post-result animations continue")
	ck(scene.clock.sim.snapshot()==final_snapshot,"post-result animation does not alter outcome")
	for i in range(5):
		scene.restart_battle()
		await process_frame
		ck(scene.views.size()==6 and scene.clock.sim.phase=="prepare","repeat restart restores six actors")
		ck(scene.event_ids.is_empty(),"restart clears consumed event ids")
		scene.start_battle();scene.advance_battle(0.5)
	scene.queue_free();await process_frame
	print("INTEGRATION FAILURES=",fails);quit(1 if fails else 0)
