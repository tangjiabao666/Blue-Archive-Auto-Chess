extends SceneTree
var fails:=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func _initialize():call_deferred("run")
func run():
	var profiles=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	ck(profiles.size()>=7,"at least seven distinct native profiles")
	for key in profiles:
		var view=load("res://scripts/unit_view.gd").new();root.add_child(view)
		view.setup({"id":0,"team":0,"cell":Vector2.ZERO,"range":3.0,"attack_ticks":60,"presentation":profiles[key]}, {},1)
		ck(view.player!=null,"native model loads: "+key)
		ck(view.player.has_animation(profiles[key].clips.idle),"native idle bound: "+key)
		ck(view.player.has_animation(profiles[key].clips.ex),"native EX clip bound: "+key)
		ck(view.diagnostics().warnings.is_empty(),"no default Rio bindings leak: "+key)
		for mesh in view._model.find_children("*","MeshInstance3D",true,false):
			for surface in mesh.mesh.get_surface_count():
				var original=mesh.mesh.surface_get_material(surface)
				if original!=null and (String(original.resource_name).ends_with("EyeMouth") or String(original.resource_name).ends_with("Halo")):
					ck(mesh.get_active_material(surface) is ShaderMaterial,"character eye/mouth shader uses own textures: "+key)
		if not profiles[key].clips.attack_fire.is_empty():
			view.player.play(profiles[key].clips.attack_fire);view.player.advance(0.2)
			var muzzle=view.muzzle_transform()
			ck(muzzle.origin.y>0.15 and muzzle.origin.distance_to(view.global_position)>0.2,"native muzzle anchor follows weapon: "+key)
		view.update_time(0.25,{"cell":Vector2.ZERO});view.queue_free();await process_frame
	print("ROSTER PRESENTATION FAILURES=",fails);quit(1 if fails else 0)
