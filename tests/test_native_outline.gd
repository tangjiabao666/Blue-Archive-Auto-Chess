extends SceneTree
const Adapter=preload("res://scripts/native_material_adapter.gd")
const IDS=["3842354575187673020","7510402755012584619","-5291362573210086922","-301851123381183171",
	"-7604909151915441593","7684728650434188911","5040786680278498505","6511698410500800698"]
var failures:=0
func ck(ok:bool,label:String)->void:
	if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	var tested:=0
	var expected:=0
	for profile in profiles.values():
		for record in profile.materials:
			if record.shader_id in IDS:expected+=1
	for id in profiles:
		var model:=Node3D.new();root.add_child(model)
		for record in profiles[id].materials:
			var mesh:=MeshInstance3D.new();var primitive:=BoxMesh.new();var base:=StandardMaterial3D.new()
			base.resource_name=record.name;primitive.material=base;mesh.mesh=primitive;mesh.name=record.name;model.add_child(mesh)
		Adapter.apply(model,profiles[id].materials)
		for record in profiles[id].materials:
			var material:Material=model.get_node(record.name).get_active_material(0)
			if record.shader_id not in IDS:
				ck(material.next_pass==null,"do not outline unsupported family: "+record.name);continue
			tested+=1
			ck(material.next_pass is ShaderMaterial,"source outline pass attached: "+record.name)
			if not material.next_pass is ShaderMaterial:continue
			var outline:ShaderMaterial=material.next_pass
			ck(outline.shader.resource_path=="res://shaders/native_outline.gdshader","source outline shader: "+record.name)
			var uniforms:Dictionary={};for u in outline.shader.get_shader_uniform_list():uniforms[u.name]=true
			for key in ["main_texture","outline_tint","outline_z_correction","main_light_color","use_cutout","cutoff"]:ck(uniforms.has(key),"outline reflected uniform: "+key)
			var c:Dictionary=record.colors._OutlineTint
			ck(outline.get_shader_parameter("outline_tint")==Vector3(c.r,c.g,c.b),"source outline tint: "+record.name)
			ck(outline.get_shader_parameter("main_texture").resource_path==record.textures._MainTex,"source outline vertex texture: "+record.name)
			ck(outline.get_shader_parameter("use_cutout")== ("_CHAR_CUTOUT_MODE" in record.keywords),"native outline cutout keyword: "+record.name)
			ck(is_equal_approx(outline.get_shader_parameter("outline_z_correction"),record.floats.get("_OutlineZCorrection",0.0)),"native outline depth correction: "+record.name)
			ck(outline.next_pass==null,"no duplicate/solid-color outline chain: "+record.name)
		Adapter.apply(model,profiles[id].materials)
		for mesh in model.get_children():
			var material:Material=mesh.get_active_material(0)
			if material.next_pass!=null:ck(material.next_pass.next_pass==null,"reapply does not stack outlines")
		model.free()
	ck(tested==expected and tested>=31,"all eligible source materials retain native outlines")
	print("NATIVE OUTLINE TESTS: ",tested,"; FAILURES=",failures);quit(1 if failures else 0)
