extends SceneTree
const Adapter=preload("res://scripts/native_material_adapter.gd")
const BODY_ID="3842354575187673020"
const WEAPON_ID="-301851123381183171"
const BODY_IDS=[BODY_ID,"-7604909151915441593"]
const WEAPON_IDS=[WEAPON_ID,"6511698410500800698"]
const HALO_ID="-3862970092140889420"
var failures:=0
var counts:Dictionary={"body":0,"weapon":0,"weapon_glow":0}
func ck(ok:bool,label:String)->void:
	if not ok:
		failures+=1
		printerr("FAIL: "+label)
func _initialize()->void:call_deferred("run")
func _mesh_for(name:String)->MeshInstance3D:
	var mesh:=MeshInstance3D.new()
	var primitive:=BoxMesh.new()
	var material:=StandardMaterial3D.new()
	material.resource_name=name
	primitive.material=material
	mesh.mesh=primitive
	return mesh
func run()->void:
	var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	for id in profiles:
		var model:=Node3D.new()
		root.add_child(model)
		var meshes:Dictionary={}
		for record in profiles[id].materials:
			var mesh:=_mesh_for(record.name)
			model.add_child(mesh)
			meshes[record.name]=mesh
		Adapter.apply(model,profiles[id].materials)
		for record in profiles[id].materials:
			var path:=""
			if record.shader_id in BODY_IDS:
				path="res://shaders/native_body_layer4.gdshader"
				counts.body+=1
			elif record.shader_id in WEAPON_IDS:
				path="res://shaders/native_weapon.gdshader"
				counts.weapon+=1
			elif record.shader_id==HALO_ID and not record.name.ends_with("Halo"):
				path="res://shaders/native_halo.gdshader"
				counts.weapon_glow+=1
			if path.is_empty():continue
			var material:Material=meshes[record.name].get_active_material(0)
			ck(material is ShaderMaterial,"source family overrides PBR: "+record.name)
			if not material is ShaderMaterial:continue
			ck(material.shader.resource_path==path,"shader identity: "+record.name)
			var uniforms:Dictionary={}
			for info in material.shader.get_shader_uniform_list():uniforms[info.name]=true
			ck(uniforms.has("main_texture"),"shader parsed/reflected: "+record.name)
			ck(material.get_shader_parameter("main_texture") is Texture2D,"main source texture bound: "+record.name)
			if record.shader_id in BODY_IDS:
				ck(material.get_shader_parameter("mask_texture") is Texture2D,"body data mask bound: "+id)
				for property in ["_BaseBrightness4","_ViewOffset4","_ViewPower4","_ViewStrength4","_InvViewPower4","_InvViewStrength4","_ViewLightEdge4","_RimAreaMultiplier4","_RimStrength4","_ShadowThreshold4","_ShadowTintR4","_ShadowTintG4","_ShadowTintB4"]:
					var uniform=property.substr(1).to_snake_case().replace("_4","4")
					var c=record.colors[property]
					ck(uniforms.has(uniform),"four-lane uniform exists: "+uniform)
					ck(material.get_shader_parameter(uniform)==Vector4(c.r,c.g,c.b,c.a),"preserve all four source lanes: "+id+" "+property)
				ck(material.get_shader_parameter("use_cutout")== ("_CHAR_CUTOUT_MODE" in record.keywords),"source cutout keyword: "+id)
				ck(material.get_shader_parameter("native_cull")==int(record.floats._Cull),"native cull: "+id)
				ck(is_equal_approx(material.get_shader_parameter("cutoff"),record.floats._Cutoff),"source cutoff: "+id)
			elif record.shader_id in WEAPON_IDS:
				ck(material.get_shader_parameter("source_texture") is Texture2D,"weapon data mask bound: "+record.name)
				ck(material.get_shader_parameter("glow_enabled")== ("_GLOW_0" in record.keywords),"weapon glow keyword: "+record.name)
				var expected_floats={"_ShadowThreshold":"shadow_threshold","_ShadowStrong":"shadow_strong","_LightValue":"light_value","_LightStrong":"light_strong","_SpecStrong":"spec_strong","_GlowStrictness0":"glow_strictness0","_GlowStrength0":"glow_strength0"}
				for property in expected_floats:
					if record.floats.has(property):
						var uniform:String=expected_floats[property]
						ck(uniforms.has(uniform),"weapon scalar uniform exists: "+uniform)
						ck(is_equal_approx(material.get_shader_parameter(uniform),record.floats[property]),"weapon native scalar: "+record.name+" "+property)
				var expected_vectors={"_Color":"color_tint","_FakeLightDir":"fake_light_direction","_SpecColor":"spec_color","_ShadowTint":"shadow_tint","_GlowMaskColor0":"glow_mask_color0","_GlowTint0":"glow_tint0","_CodeMultiplyColor":"code_multiply_color","_CodeAddColor":"code_add_color","_CodeAddRimColor":"code_add_rim_color"}
				for property in expected_vectors:
					var uniform:String=expected_vectors[property]
					var c:Dictionary=record.colors[property]
					ck(uniforms.has(uniform),"weapon RGB uniform exists: "+uniform)
					ck(material.get_shader_parameter(uniform)==Vector3(c.r,c.g,c.b),"weapon raw numeric RGB: "+record.name+" "+property)
		model.free()
	ck(counts.body==profiles.size() and counts.body>=7 and counts.weapon>=profiles.size() and counts.weapon_glow>=1,"all imported profiles retain verified body/weapon/glow coverage")
	# Exact shader ID guards against assigning native arithmetic to a similarly named unknown material.
	var unrelated:=Node3D.new();root.add_child(unrelated)
	var fake_mesh:=_mesh_for("Unknown_Body");unrelated.add_child(fake_mesh)
	Adapter.apply(unrelated,[{"name":"Unknown_Body","shader_id":"unknown","textures":{},"floats":{},"colors":{},"texture_st":{},"keywords":[]}])
	ck(fake_mesh.get_surface_override_material(0)==null,"unknown body material left unchanged")
	unrelated.free()
	print("NATIVE BODY MATERIAL TESTS: ",JSON.stringify({"failures":failures,"coverage":counts}))
	quit(1 if failures else 0)
