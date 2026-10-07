extends SceneTree
## Diagnostic only. -- plain uses production ownership; -- unretained reproduces
## the old lifetime by removing the model keepalive before rapid teardown.
## Other diagnostic modes isolate binding, pass, shader and renderer lifetime.
var held:Array=[]
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	var mode:String=args[0] if not args.is_empty() else "plain"
	var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	print("MATERIAL_PROBE START ",mode)
	var views:Array=[]
	for i in 2:
		var view:Node3D
		if mode=="model_only":
			view=load(profiles.shiroko.model_path).instantiate();root.add_child(view)
		else:
			view=load("res://scripts/unit_view.gd").new();root.add_child(view)
			var profile:Dictionary=profiles.shiroko.duplicate(true)
			if mode=="empty_bindings":profile.materials=[]
			if mode.begins_with("binding:"):profile.materials=profile.materials.filter(func(binding):return binding.name==mode.substr(8))
			view.setup({"id":i,"team":i,"cell":Vector2(i,0),"range":3,"presentation":profile},{},1)
		if mode=="parent_retained":
			var materials:Array=[]
			for mesh in view._model.find_children("*","MeshInstance3D",true,false):
				if mesh.mesh:
					for surface in mesh.mesh.get_surface_count():materials.append(mesh.get_active_material(surface))
			view._model.set_meta("_native_material_keepalive",materials)
		if mode=="inspect":
			for mesh in view.find_children("*","MeshInstance3D",true,false):
				if mesh.mesh:
					for surface in mesh.mesh.get_surface_count():
						var material=mesh.get_active_material(surface)
						if material is ShaderMaterial:print("MESH ",mesh.name," SURFACE ",surface," SHADER ",material.shader.resource_path," RID ",material.get_rid())
		if mode=="no_outline":
			for mesh in view.find_children("*","MeshInstance3D",true,false):
				if mesh.mesh:
					for surface in mesh.mesh.get_surface_count():
						var material=mesh.get_active_material(surface)
						if material:material.next_pass=null
		if mode=="unretained":view._model.remove_meta("_native_material_keepalive")
		views.append(view)
	print("MATERIAL_PROBE BUILT")
	if mode=="settled":
		await process_frame;await process_frame
		print("MATERIAL_PROBE SETTLED")
	for view in views:
		if mode=="shader_retained":
			for mesh in view.find_children("*","MeshInstance3D",true,false):
				if mesh.mesh:
					for surface in mesh.mesh.get_surface_count():
						var material=mesh.get_active_material(surface)
						if material is ShaderMaterial:held.append(material.shader)
		if mode=="retained":
			for mesh in view.find_children("*","MeshInstance3D",true,false):
				if mesh.material_override:held.append(mesh.material_override)
				if mesh.mesh:
					held.append(mesh.mesh)
					for surface in mesh.mesh.get_surface_count():held.append(mesh.get_active_material(surface))
		if mode=="detached":
			for mesh in view.find_children("*","MeshInstance3D",true,false):
				mesh.material_override=null
				if mesh.mesh:
					for surface in mesh.mesh.get_surface_count():mesh.set_surface_override_material(surface,null)
		view.queue_free()
	print("MATERIAL_PROBE QUEUED")
	await process_frame
	print("MATERIAL_PROBE FREED")
	held.clear()
	await process_frame
	print("MATERIAL_PROBE END")
	quit()
