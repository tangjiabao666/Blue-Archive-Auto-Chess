extends SceneTree
func _initialize():
	var actor=load("res://assets/native/CH0331.fbx").instantiate()
	root.add_child(actor)
	for mesh in actor.find_children("*","MeshInstance3D",true,false):
		for i in range(mesh.mesh.get_surface_count()):
			var m=mesh.get_active_material(i)
			print(mesh.name," | ",i," | ",m.resource_name," | ",m.albedo_color," | tex=",m.albedo_texture.resource_path if m.albedo_texture else "NULL"," | alpha=",m.transparency," | cull=",m.cull_mode)
	actor.queue_free();quit()
