extends SceneTree
## Exact current IDs and visible-surface expectations are independent of the adapter registry.
const Adapter=preload("res://scripts/native_material_adapter.gd")
const EXPECTED={
	"Asuna_Original_Body":["-7604909151915441593","native_body_layer4",true],
	"Asuna_Original_EyeMouth":["-8370283506080789971","native_eyemouth",false],
	"Asuna_Original_Eyebrow":["2868214095323921473","native_eyebrow",false],
	"Asuna_Original_Face":["5040786680278498505","native_face",true],
	"Asuna_Original_Hair":["7684728650434188911","native_hair",true],
	"Asuna_Original_Halo":["-3724798367777686984","native_halo_cull_back",false],
	"Asuna_Original_Weapon":["6511698410500800698","native_weapon",true],
}
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func _rgb(c:Dictionary)->Vector3:return Vector3(c.r,c.g,c.b)
func _add_mesh(model:Node3D,name:String)->MeshInstance3D:
	var mesh:=MeshInstance3D.new();var geometry:=BoxMesh.new()
	var material:=StandardMaterial3D.new();material.resource_name=name
	geometry.material=material;mesh.mesh=geometry;model.add_child(mesh)
	return mesh
func _check_texture(material:ShaderMaterial,uniform:String,path:String)->void:
	var texture=material.get_shader_parameter(uniform)
	ck(texture is Texture2D and texture.resource_path==path,"exact source texture "+uniform+": "+path)
func _check_binding(material:Material,record:Dictionary,expected:Array)->void:
	ck(record.shader_id is String and record.shader_id==expected[0],"unaltered decimal source ID: "+record.name)
	ck(material is ShaderMaterial,"visible surface has native override: "+record.name)
	if not material is ShaderMaterial:return
	ck(material.shader.resource_path=="res://shaders/"+expected[1]+".gdshader","native shader selected: "+record.name)
	ck((material.next_pass is ShaderMaterial)==expected[2],"outline eligibility: "+record.name)
	if expected[2] and material.next_pass is ShaderMaterial:
		var outline:ShaderMaterial=material.next_pass
		ck(outline.shader.resource_path=="res://shaders/native_outline.gdshader","source outline shader: "+record.name)
		ck(outline.next_pass==null,"single outline pass: "+record.name)
		ck(outline.get_shader_parameter("outline_tint")==_rgb(record.colors._OutlineTint),"raw outline RGB: "+record.name)
		ck(is_equal_approx(outline.get_shader_parameter("outline_z_correction"),record.floats.get("_OutlineZCorrection",0.0)),"raw outline depth correction: "+record.name)
	if record.name.ends_with("Eyebrow"):
		ck(material.get_shader_parameter("use_main_texture")==true,"current eyebrow is textured, never OneColor")
		_check_texture(material,"main_texture","res://assets/characters/asuna/Asuna_Original_Face_3140291583861169494.png")
		ck(material.get_shader_parameter("native_cull")==2,"eyebrow source Cull Back")
		ck(material.get_shader_parameter("z_correction")==0.03999999910593033,"eyebrow source-unit ZCorrection")
	elif record.name.ends_with("EyeMouth"):
		_check_texture(material,"eye_texture",record.textures._MainTex)
		_check_texture(material,"mouth_atlas",record.textures._MouthTileTex)
		ck(material.get_shader_parameter("mouth_st")==Vector4(0.5,0.5,0.5,0.875),"actual source mouth atlas ST")
	elif record.name.ends_with("Halo"):
		_check_texture(material,"main_texture",record.textures._MainTex)
		ck(material.get_shader_parameter("use_glow")==true,"source Halo glow keyword")
		ck(material.get_shader_parameter("glow_mask_color")==_rgb(record.colors._GlowMaskColor0),"Halo raw glow mask")
		ck(material.get_shader_parameter("glow_tint")==_rgb(record.colors._GlowTint0),"Halo raw glow tint")
		ck(material.get_shader_parameter("glow_strength")==record.floats._GlowStrength0,"Halo source glow strength")
		ck(material.get_shader_parameter("glow_strictness")==record.floats._GlowStrictness0,"Halo source glow strictness")
	elif record.name.ends_with("Hair"):
		var scalar_uniforms:Dictionary={"_AdjustiveHairShadow":"adjustive_hair_shadow","_MaskGSensitivity":"mask_g_sensitivity","_ShadowThreshold":"shadow_threshold","_SpecBotArea":"spec_bot_area","_SpecBotMultiplier":"spec_bot_multiplier","_SpecTopMultiplier":"spec_top_multiplier","_SpecTopLeveler":"spec_top_leveler","_SpecStrength":"spec_strength","_RimAreaMultiplier":"rim_area_multiplier","_RimAreaLeveler":"rim_area_leveler","_RimStrength":"rim_strength","_GlowStrength":"glow_strength"}
		for property in scalar_uniforms:
			var uniform:String=scalar_uniforms[property]
			ck(material.get_shader_parameter(uniform)==record.floats[property],"Hair exact scalar: "+property)
		for pair in [["_SpecDirMultiplier","spec_direction_multiplier"],["_ShadowTint","shadow_tint"],["_GlowTint","glow_tint"]]:
			ck(material.get_shader_parameter(pair[1])==_rgb(record.colors[pair[0]]),"Hair raw numeric vector: "+pair[0])
func _references(model:Node3D)->Array:
	var refs:Array=[]
	for material in model.get_meta("_native_material_keepalive",[]):
		refs.append(weakref(material))
		if material.next_pass:refs.append(weakref(material.next_pass))
	return refs
func _check_visible(model:Node3D,records:Dictionary)->void:
	var seen:Dictionary={};var outlines:=0;var meshes:=0
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		meshes+=1
		for surface in mesh.mesh.get_surface_count():
			var name:String=mesh.mesh.surface_get_material(surface).resource_name
			ck(EXPECTED.has(name),"visible surface belongs to own character material: "+name)
			if not EXPECTED.has(name):continue
			seen[name]=seen.get(name,0)+1
			var material:Material=mesh.get_surface_override_material(surface)
			_check_binding(material,records[name],EXPECTED[name])
			if material!=null and material.next_pass!=null:outlines+=1
	ck(meshes==3,"three instantiated mesh nodes")
	ck(seen.size()==7 and seen.values().all(func(n):return n==1),"exactly seven visible material surfaces")
	ck(outlines==4,"four visible native outlines")
func _check_single(record:Dictionary,path:String,uniforms:Dictionary={})->void:
	var model:=Node3D.new();root.add_child(model)
	var mesh:=_add_mesh(model,record.name)
	Adapter.apply(model,[record])
	var material:Material=mesh.get_surface_override_material(0)
	if path.is_empty():
		ck(material==null,"unsupported identity/texture guard: "+record.name+" "+record.shader_id)
	else:
		ck(material is ShaderMaterial,"supported exact identity: "+record.name)
		if material is ShaderMaterial:
			ck(material.shader.resource_path=="res://shaders/"+path+".gdshader","exact identity dispatch: "+record.name)
			for key in uniforms:ck(material.get_shader_parameter(key)==uniforms[key],"saved property/keyword "+record.name+": "+key)
	model.free()
func _check_guards(records:Dictionary)->void:
	var slots={"Body":["_MainTex","_MaskTex"],"Weapon":["_MainTex","_SourceTex"],"Hair":["_MainTex","_MaskTex","_HairSpecTex"],"Eyebrow":["_MainTex"]}
	for suffix in slots:
		var original:Dictionary=records["Asuna_Original_"+suffix]
		for shader_id in ["unknown",str(int(original.shader_id)+1)]:
			var record:Dictionary=original.duplicate(true);record.name="Unknown_"+suffix;record.shader_id=shader_id
			_check_single(record,"")
		for slot in slots[suffix]:
			var record:Dictionary=original.duplicate(true);record.textures.erase(slot)
			_check_single(record,"")
	# Prove exact-ID recognition independently of the original name, including Face and Halo.
	for suffix in ["Body","Weapon","Hair","Eyebrow","Face","Halo"]:
		var record:Dictionary=records["Asuna_Original_"+suffix].duplicate(true);record.name="AnonymousResource"
		_check_single(record,EXPECTED["Asuna_Original_"+suffix][1])
	var body:Dictionary=records.Asuna_Original_Body.duplicate(true)
	body.keywords=["_UNREVIEWED_KEYWORD"]
	_check_single(body,"native_body_layer4",{"use_cutout":false,"native_cull":0})
	var weapon:Dictionary=records.Asuna_Original_Weapon.duplicate(true)
	weapon.floats._UseGlow=1.0
	_check_single(weapon,"native_weapon",{"glow_enabled":false})
	# Saved _Cull on unrelated Halo profiles retains the historical behavior.
	for shader_id in ["-3862970092140889420","unknown"]:
		var halo:Dictionary=records.Asuna_Original_Halo.duplicate(true);halo.shader_id=shader_id
		_check_single(halo,"native_halo")
	var off:Dictionary=records.Asuna_Original_Halo.duplicate(true);off.floats._Cull=0.0
	_check_single(off,"native_halo")
	_check_single(records.Common_FlashBang,"native_weapon")
	_check_single(records.FX_MAT_Stretch_Step_109_Heli,"")
func run()->void:
	var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	ck(profiles.has("asuna"),"inactive Asuna fixture exists")
	if not profiles.has("asuna"):quit(1);return
	var profile:Dictionary=profiles.asuna;var snapshot:String=JSON.stringify(profile.materials)
	var records:Dictionary={}
	for record in profile.materials:records[record.name]=record
	var packed:PackedScene=load(profile.model_path)
	var model:Node3D=packed.instantiate();root.add_child(model)
	Adapter.apply(model,profile.materials)
	_check_visible(model,records)
	var refs:Array=_references(model)
	ck(refs.size()==11,"seven material and four outline lifetimes")
	Adapter.apply(model,profile.materials)
	for ref in refs:ck(ref.get_ref()==null,"reapply releases old Asuna material/outline")
	_check_visible(model,records)
	refs=_references(model)
	Adapter.apply(model,[])
	for ref in refs:ck(ref.get_ref()!=null,"empty binding keeps Asuna material/outline")
	Adapter.apply(model,[records.Asuna_Original_Body])
	_check_visible(model,records)
	refs=_references(model)
	for mesh in model.find_children("*","MeshInstance3D",true,false):mesh.free()
	for ref in refs:ck(ref.get_ref()!=null,"parent retains destroyed mesh material/outline")
	model.free()
	for ref in refs:ck(ref.get_ref()==null,"parent deletion releases Asuna material/outline")
	_check_guards(records)
	ck(JSON.stringify(profile.materials)==snapshot,"adapter preserves actual IDs, floats, colors, keywords and ST")
	var cull_path:="res://shaders/native_halo_cull_back.gdshader"
	ck(FileAccess.file_exists(cull_path),"source-backed Halo Cull Back variant exists")
	if FileAccess.file_exists(cull_path):
		var code:String=FileAccess.get_file_as_string(cull_path)
		ck("render_mode unshaded,cull_back;" in code,"Halo variant uses native back-face culling")
		ck(code.replace("cull_back","cull_disabled")==FileAccess.get_file_as_string("res://shaders/native_halo.gdshader"),"Halo variant preserves all RGB/glow arithmetic")
	await process_frame
	print("ASUNA NATIVE MATERIAL CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
