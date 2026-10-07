extends SceneTree
## Source-backed contract: MX/C-Hair and both MX/C-Eyebrow ForwardLit families.
## Recovered GLES 9-6 and serialized pass state, documented in docs/native-hair-eyebrow.md.
const Adapter=preload("res://scripts/native_material_adapter.gd")
const HAIR_ID="7510402755012584619"
const TEXTURED_ID="-1426215029351013349"
const HAIR_IDS=[HAIR_ID,"7684728650434188911"]
const TEXTURED_IDS=[TEXTURED_ID,"2868214095323921473"]
const COLOR_ID="8580738742837111177"
var checks:=0
var failures:=0
var coverage:Dictionary={"hair":0,"two_sided_hair":0,"back_culled_hair":0,"textured_brow":0,"color_brow":0}
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func _mesh_for(name:String)->MeshInstance3D:
	var mesh:=MeshInstance3D.new()
	var primitive:=BoxMesh.new()
	var original:=StandardMaterial3D.new();original.resource_name=name
	primitive.material=original;mesh.mesh=primitive
	return mesh
func _rgb(value:Dictionary)->Vector3:return Vector3(value.r,value.g,value.b)
func _check_record(mesh:MeshInstance3D,record:Dictionary)->void:
	var material:Material=mesh.get_surface_override_material(0)
	ck(material is ShaderMaterial,"source family uses shader: "+record.name)
	if not material is ShaderMaterial:return
	var hair:bool=record.shader_id in HAIR_IDS
	var textured:bool=record.shader_id in TEXTURED_IDS
	var expected_path:String="res://shaders/native_hair.gdshader" if hair else "res://shaders/native_eyebrow.gdshader"
	ck(material.shader.resource_path==expected_path,"source shader identity: "+record.name)
	var uniforms:Dictionary={}
	for info in material.shader.get_shader_uniform_list():uniforms[info.name]=true
	for name in ["native_cull","tint","code_add_color","code_multiply_color","code_add_rim_color"]:
		ck(uniforms.has(name),"parsed shader uniform "+record.name+": "+name)
	ck(material.get_shader_parameter("native_cull")==int(record.floats._Cull),"native cull unchanged: "+record.name)
	for property in {"_Tint":"tint","_CodeAddColor":"code_add_color","_CodeMultiplyColor":"code_multiply_color","_CodeAddRimColor":"code_add_rim_color"}:
		var name:String={"_Tint":"tint","_CodeAddColor":"code_add_color","_CodeMultiplyColor":"code_multiply_color","_CodeAddRimColor":"code_add_rim_color"}[property]
		ck(material.get_shader_parameter(name)==_rgb(record.colors[property]),"raw source RGB: "+record.name+" "+property)
	ck(record.floats._SrcBlend==1.0 and record.floats._DstBlend==0.0 and record.floats._ZWrite==1.0,"roster source uses opaque depth-writing state: "+record.name)
	if hair:
		coverage.hair+=1
		coverage.two_sided_hair+=int(record.floats._Cull==0.0)
		coverage.back_culled_hair+=int(record.floats._Cull==2.0)
		ck(material.get_shader_parameter("two_side_tint")==_rgb(record.colors._TwoSideTint),"native back-face tint: "+record.name)
		for property in {"_MainTex":"main_texture","_MaskTex":"mask_texture","_HairSpecTex":"hair_spec_texture"}:
			var name:String={"_MainTex":"main_texture","_MaskTex":"mask_texture","_HairSpecTex":"hair_spec_texture"}[property]
			var texture=material.get_shader_parameter(name)
			ck(texture is Texture2D and texture.resource_path==record.textures[property],"exact source texture: "+record.name+" "+property)
		ck(material.next_pass is ShaderMaterial,"source outline retained: "+record.name)
	else:
		coverage.textured_brow+=int(textured);coverage.color_brow+=int(not textured)
		ck(material.get_shader_parameter("use_main_texture")==textured,"eyebrow family selected by shader ID: "+record.name)
		ck(material.get_shader_parameter("z_correction")!=null and is_equal_approx(float(material.get_shader_parameter("z_correction")),float(record.floats._ZCorrection)),"native object-unit camera offset: "+record.name)
		var texture=material.get_shader_parameter("main_texture")
		ck((texture is Texture2D and texture.resource_path==record.textures._MainTex) if textured else texture==null,"texture only on textured family: "+record.name)
		ck(material.next_pass==null,"no invented eyebrow outline: "+record.name)
func _shader_contract()->void:
	var hair:=FileAccess.get_file_as_string("res://shaders/native_hair.gdshader")
	ck("cull_disabled" in hair,"hair admits native two-sided geometry")
	ck("native_cull == 2 && !FRONT_FACING" in hair and "native_cull == 1 && FRONT_FACING" in hair,"hair implements both Unity cull orientations")
	ck("(FRONT_FACING ? 1.0 : -1.0) * native_world_normal" in hair,"hair flips source normal on back face")
	ck("FRONT_FACING ? front : back" in hair and "two_side_tint * shadow_tone * shadow_tint" in hair,"hair selects recovered back-face shading")
	ck(not "ALPHA =" in hair,"opaque hair does not enter transparency pipeline")
	var brow_path:="res://shaders/native_eyebrow.gdshader"
	ck(FileAccess.file_exists(brow_path),"dedicated source eyebrow shader exists")
	if not FileAccess.file_exists(brow_path):return
	var brow:=FileAccess.get_file_as_string(brow_path)
	ck("cull_disabled" in brow and "depth_draw_opaque" in brow,"eyebrow source opaque depth state")
	ck("native_cull == 2 && !FRONT_FACING" in brow and "native_cull == 1 && FRONT_FACING" in brow,"eyebrow source cull orientations")
	ck("inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)" in brow,"eyebrow camera converted into object coordinates")
	ck("VERTEX += native_safe_normalize(camera_object - VERTEX) * z_correction" in brow,"eyebrow offset precedes model scale without guessed conversion")
	ck("texture(main_texture, UV" in brow and not "UV *" in brow,"source textured eyebrow uses unchanged UV, not stored unused MainTex_ST")
	ck(not "ALPHA =" in brow and not "ALPHA_SCISSOR_THRESHOLD" in brow,"source alpha never introduces blending or alpha clipping")
	ck("code_add_rim_color * 0.5" in brow,"source constant eyebrow rim term")
func run()->void:
	_shader_contract()
	var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	for id in profiles:
		var model:=Node3D.new();root.add_child(model)
		var records:Array=[]
		for record in profiles[id].materials:
			if record.shader_id not in HAIR_IDS+TEXTURED_IDS+[COLOR_ID]:continue
			records.append(record);model.add_child(_mesh_for(record.name))
		Adapter.apply(model,records)
		for index in records.size():_check_record(model.get_child(index),records[index])
		var refs:Array=[]
		for mesh in model.get_children():refs.append(weakref(mesh.get_surface_override_material(0)))
		Adapter.apply(model,records)
		for ref in refs:ck(ref.get_ref()==null,"reapply releases old hair/brow material: "+id)
		refs.clear()
		for mesh in model.get_children():refs.append(weakref(mesh.get_surface_override_material(0)))
		for mesh in model.get_children():mesh.free()
		for ref in refs:ck(ref.get_ref()!=null,"model retains material past child renderer destruction: "+id)
		model.free()
		for ref in refs:ck(ref.get_ref()==null,"model releases hair/brow material without cycle: "+id)
	ck(coverage=={"hair":14,"two_sided_hair":13,"back_culled_hair":1,"textured_brow":7,"color_brow":7},"all 14 source profiles exercised: "+JSON.stringify(coverage))
	# Shader identity is authoritative even if an unrelated resource is named Eyebrow/Hair.
	for suffix in ["Eyebrow","Hair"]:
		var model:=Node3D.new();root.add_child(model);var mesh:=_mesh_for("Unknown_"+suffix);model.add_child(mesh)
		var record:Dictionary=profiles.hina.materials.filter(func(x):return x.name.ends_with(suffix))[0].duplicate(true)
		record.name="Unknown_"+suffix;record.shader_id="unknown"
		Adapter.apply(model,[record]);ck(mesh.get_surface_override_material(0)==null,"unknown "+suffix+" family is not guessed")
		model.free()
	await process_frame
	print("NATIVE HAIR EYEBROW CHECKS=",checks," FAILURES=",failures," COVERAGE=",JSON.stringify(coverage))
	quit(1 if failures else 0)
