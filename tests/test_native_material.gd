extends SceneTree
var fails:=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func _initialize()->void:call_deferred("run")
func run()->void:
	var config=ConfigFile.new()
	ck(config.load("res://assets/native/CH0331_Hair_Spec.png.import")==OK,"hair direction import config readable")
	ck(config.get_value("params","process/fix_alpha_border",true)==false,"direction map RGB must not be modified using alpha")
	var source=Image.load_from_file(ProjectSettings.globalize_path("res://assets/native/CH0331_Hair_Spec.png"))
	var imported=load("res://assets/native/CH0331_Hair_Spec.png").get_image()
	if imported.is_compressed():imported.decompress()
	source.convert(Image.FORMAT_RGBA8);imported.convert(Image.FORMAT_RGBA8)
	ck(source.get_data()==imported.get_data(),"imported direction pixels exactly preserve source RGBA")
	var scene=load("res://battle.tscn").instantiate()
	root.add_child(scene);scene.set_process(false)
	var found=false
	for mesh in scene.views[0]._model.find_children("*","MeshInstance3D",true,false):
		if not mesh.visible:continue
		for surface in mesh.mesh.get_surface_count():
			var original=mesh.mesh.surface_get_material(surface)
			if original.resource_name!="CH0331_Hair":continue
			found=true
			var m=mesh.get_active_material(surface)
			ck(m is ShaderMaterial,"native hair uses mask/direction shader instead of generic PBR")
			if m is ShaderMaterial:
				for key in ["main_texture","mask_texture","hair_spec_texture"]:
					ck(m.get_shader_parameter(key) is Texture2D,"native hair texture bound: "+key)
	ck(found,"native hair surface exists")
	scene.queue_free();await process_frame
	print("NATIVE MATERIAL FAILURES=",fails);quit(1 if fails else 0)
