extends SceneTree
var fails:=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func _initialize():call_deferred("run")
func run():
	var scene=load("res://battle.tscn").instantiate();root.add_child(scene);scene.set_process(false)
	var ring=scene.views[0].get_node_or_null("AttackRangeIndicator")
	ck(ring!=null,"selected character has range indicator")
	if ring!=null:
		ck(ring.visible,"selected friendly shows range in preparation")
		ck(is_equal_approx(ring.radius,scene.clock.sim.units[0].range),"visual radius uses authoritative weapon range")
		var arrays=ring.mesh.surface_get_arrays(0)
		for p in arrays[Mesh.ARRAY_VERTEX]:
			var radius=Vector2(p.x,p.z).length()
			ck(radius<=ring.radius+0.00001 and radius>=ring.radius-0.04,"thin ring geometry fits attack radius")
		var target=Vector2(-1.231,3.234)
		ck(scene.place_selected(target),"free placement accepted")
		ck(Vector2(ring.global_position.x,ring.global_position.z).distance_to(target)<0.0001,"range ring follows free placement")
		scene.select_unit(1)
		ck(not ring.visible,"previous selection ring hidden")
		ck(scene.views[1].get_node("AttackRangeIndicator").visible,"new selection ring shown")
		for id in [3,4,5]:ck(not scene.views[id].get_node("AttackRangeIndicator").visible,"enemy range hidden")
		scene.start_battle()
		for view in scene.views.values():ck(not view.get_node("AttackRangeIndicator").visible,"battle hides all range indicators")
		scene.restart_battle();await process_frame
		ck(scene.views[0].get_node("AttackRangeIndicator").visible,"restart restores selected preparation ring")
	scene.queue_free();await process_frame
	print("RANGE INDICATOR FAILURES=",fails);quit(1 if fails else 0)
