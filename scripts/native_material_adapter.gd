extends RefCounted
const FLOAT_MAP={"_AdjustiveHairShadow":"adjustive_hair_shadow","_AdjustiveFaceShadow":"adjustive_face_shadow","_MaskGSensitivity":"mask_g_sensitivity","_ShadowThreshold":"shadow_threshold","_SpecBotArea":"spec_bot_area","_SpecBotMultiplier":"spec_bot_multiplier","_SpecTopMultiplier":"spec_top_multiplier","_SpecTopLeveler":"spec_top_leveler","_SpecStrength":"spec_strength","_RimAreaMultiplier":"rim_area_multiplier","_RimAreaLeveler":"rim_area_leveler","_RimStrength":"rim_strength","_GlowStrength":"glow_strength"}
const COLOR_MAP={"_ShadowTint":"shadow_tint","_SpecDirMultiplier":"spec_direction_multiplier","_GlowTint":"glow_tint","_ShadowLightDir":"shadow_light_direction"}
# Family selection uses recovered Unity shader IDs, never a Body/Weapon filename guess.
const BODY_SHADER_ID="3842354575187673020"
const WEAPON_SHADER_ID="-301851123381183171"
const HALO_SHADER_ID="-3862970092140889420"
const HAIR_SHADER_ID="7510402755012584619"
const EYEBROW_TEXTURE_SHADER_ID="-1426215029351013349"
const EYEBROW_COLOR_SHADER_ID="8580738742837111177"
# Reviewed current program IDs, not family-name aliases. Source CAB, hashes and
# compatibility limits: docs/asuna-material-bridge.md and its tracked receipt.
# Keep the original scalar IDs for existing consumers; never rewrite source IDs.
const BODY_SHADER_IDS=[BODY_SHADER_ID,"-7604909151915441593"]
const WEAPON_SHADER_IDS=[WEAPON_SHADER_ID,"6511698410500800698"]
const HAIR_SHADER_IDS=[HAIR_SHADER_ID,"7684728650434188911"]
const EYEBROW_TEXTURE_SHADER_IDS=[EYEBROW_TEXTURE_SHADER_ID,"2868214095323921473"]
const FACE_SHADER_IDS=["-5291362573210086922","5040786680278498505"]
const REVIEWED_HALO_SHADER_ID="-3724798367777686984"
const CHARACTER_RGB_PROPERTIES={"_Tint":"tint","_CodeAddColor":"code_add_color","_CodeMultiplyColor":"code_multiply_color","_CodeAddRimColor":"code_add_rim_color"}
const BODY_VECTOR4_PROPERTIES={"_BaseBrightness4":"base_brightness4","_ViewOffset4":"view_offset4","_ViewPower4":"view_power4","_ViewStrength4":"view_strength4","_InvViewPower4":"inv_view_power4","_InvViewStrength4":"inv_view_strength4","_ViewLightEdge4":"view_light_edge4","_RimAreaMultiplier4":"rim_area_multiplier4","_RimStrength4":"rim_strength4","_ShadowThreshold4":"shadow_threshold4","_ShadowTintR4":"shadow_tint_r4","_ShadowTintG4":"shadow_tint_g4","_ShadowTintB4":"shadow_tint_b4","_Tint":"tint"}
const BODY_VECTOR3_PROPERTIES={"_TwoSideTint":"two_side_tint","_CodeAddColor":"code_add_color","_CodeMultiplyColor":"code_multiply_color","_CodeAddRimColor":"code_add_rim_color"}
const WEAPON_FLOAT_PROPERTIES={"_ShadowThreshold":"shadow_threshold","_ShadowStrong":"shadow_strong","_LightValue":"light_value","_LightStrong":"light_strong","_SpecStrong":"spec_strong","_GlowStrictness0":"glow_strictness0","_GlowStrength0":"glow_strength0"}
const WEAPON_VECTOR3_PROPERTIES={"_Color":"color_tint","_FakeLightDir":"fake_light_direction","_SpecColor":"spec_color","_ShadowTint":"shadow_tint","_GlowMaskColor0":"glow_mask_color0","_GlowTint0":"glow_tint0","_CodeMultiplyColor":"code_multiply_color","_CodeAddColor":"code_add_color","_CodeAddRimColor":"code_add_rim_color"}

static func _set_vector3_properties(material:ShaderMaterial,colors:Dictionary,mapping:Dictionary)->void:
	for key in mapping:
		if colors.has(key):
			var c:Dictionary=colors[key]
			material.set_shader_parameter(mapping[key],Vector3(c.r,c.g,c.b))

static func _body_material(record:Dictionary)->ShaderMaterial:
	var material:=ShaderMaterial.new()
	material.shader=load("res://shaders/native_body_layer4.gdshader")
	material.set_shader_parameter("main_texture",load(record.textures._MainTex))
	material.set_shader_parameter("mask_texture",load(record.textures._MaskTex))
	for key in BODY_VECTOR4_PROPERTIES:
		if record.colors.has(key):
			var c:Dictionary=record.colors[key]
			material.set_shader_parameter(BODY_VECTOR4_PROPERTIES[key],Vector4(c.r,c.g,c.b,c.a))
	_set_vector3_properties(material,record.colors,BODY_VECTOR3_PROPERTIES)
	material.set_shader_parameter("native_cull",int(record.floats.get("_Cull",2.0)))
	material.set_shader_parameter("cutoff",float(record.floats.get("_Cutoff",0.20000000298)))
	material.set_shader_parameter("use_cutout","_CHAR_CUTOUT_MODE" in record.get("keywords",[]))
	return material

static func _weapon_material(record:Dictionary)->ShaderMaterial:
	var material:=ShaderMaterial.new()
	material.shader=load("res://shaders/native_weapon.gdshader")
	material.set_shader_parameter("main_texture",load(record.textures._MainTex))
	material.set_shader_parameter("source_texture",load(record.textures._SourceTex))
	for key in WEAPON_FLOAT_PROPERTIES:
		if record.floats.has(key):material.set_shader_parameter(WEAPON_FLOAT_PROPERTIES[key],float(record.floats[key]))
	_set_vector3_properties(material,record.colors,WEAPON_VECTOR3_PROPERTIES)
	material.set_shader_parameter("glow_enabled","_GLOW_0" in record.get("keywords",[]))
	return material

static func _eyebrow_material(record:Dictionary)->ShaderMaterial:
	var material:=ShaderMaterial.new()
	material.shader=load("res://shaders/native_eyebrow.gdshader")
	var textured:bool=String(record.shader_id) in EYEBROW_TEXTURE_SHADER_IDS
	material.set_shader_parameter("use_main_texture",textured)
	if textured:material.set_shader_parameter("main_texture",load(record.textures._MainTex))
	_set_vector3_properties(material,record.colors,CHARACTER_RGB_PROPERTIES)
	material.set_shader_parameter("native_cull",int(record.floats.get("_Cull",2.0)))
	# Follow the roster's source-unit GLB convention (old-seven provenance limit
	# in docs/native-hair-eyebrow.md). This is object distance, not a depth bias.
	material.set_shader_parameter("z_correction",float(record.floats.get("_ZCorrection",0.0)))
	return material

# Recovered Outline pass exists on these exact families. Solid Color Outline is
# a different render-feature pass and must not be stacked automatically.
const OUTLINE_SHADER_IDS=BODY_SHADER_IDS+WEAPON_SHADER_IDS+HAIR_SHADER_IDS+FACE_SHADER_IDS
static func _outline_material(record:Dictionary)->ShaderMaterial:
	var outline:=ShaderMaterial.new()
	outline.shader=load("res://shaders/native_outline.gdshader")
	outline.set_shader_parameter("main_texture",load(record.textures._MainTex))
	var c:Dictionary=record.colors.get("_OutlineTint",{"r":0.5,"g":0.5,"b":0.5})
	outline.set_shader_parameter("outline_tint",Vector3(c.r,c.g,c.b))
	outline.set_shader_parameter("outline_z_correction",float(record.floats.get("_OutlineZCorrection",0.0)))
	outline.set_shader_parameter("cutoff",float(record.floats.get("_Cutoff",0.20000000298)))
	outline.set_shader_parameter("use_cutout","_CHAR_CUTOUT_MODE" in record.get("keywords",[]))
	return outline

static func apply(model:Node3D,bindings:Array)->void:
	var materials:Dictionary={}
	for record in bindings:
		var tex:Dictionary=record.textures
		var name:String=record.name
		var shader_id:String=String(record.get("shader_id",""))
		var material:Material=null
		if shader_id in BODY_SHADER_IDS and tex.has("_MainTex") and tex.has("_MaskTex"):
			material=_body_material(record)
		elif shader_id in WEAPON_SHADER_IDS and tex.has("_MainTex") and tex.has("_SourceTex"):
			material=_weapon_material(record)
		elif name.ends_with("EyeMouth") and tex.has("_MainTex"):
			var eye:=ShaderMaterial.new();eye.shader=load("res://shaders/native_eyemouth.gdshader")
			eye.set_shader_parameter("eye_texture",load(tex._MainTex))
			eye.set_shader_parameter("mouth_atlas",load(tex.get("_MouthTileTex","res://assets/native/Character_Mouth.png")))
			var st:Array=record.texture_st.get("_MouthTileTex",[0.5,0.5,0.125,0.5])
			eye.set_shader_parameter("mouth_st",Vector4(st[0],st[1],st[2],st[3]))
			material=eye
		elif (shader_id in [HALO_SHADER_ID,REVIEWED_HALO_SHADER_ID] or name.ends_with("Halo")) and tex.has("_MainTex"):
			var halo:=ShaderMaterial.new()
			# Only this verified current program/state gets the source Cull Back
			# variant. Do not change unrelated historical Halo or glow profiles.
			var cull_back:bool=shader_id==REVIEWED_HALO_SHADER_ID and int(record.floats.get("_Cull",0.0))==2
			halo.shader=load("res://shaders/native_halo_cull_back.gdshader" if cull_back else "res://shaders/native_halo.gdshader")
			halo.set_shader_parameter("main_texture",load(tex._MainTex))
			var t:Dictionary=record.colors.get("_Tint",{"r":1.0,"g":1.0,"b":1.0,"a":1.0})
			halo.set_shader_parameter("tint",Vector4(t.r,t.g,t.b,t.a))
			halo.set_shader_parameter("use_glow","_GLOW_0" in record.get("keywords",[]))
			for pair in [["_GlowMaskColor0","glow_mask_color"],["_GlowTint0","glow_tint"]]:
				var c:Dictionary=record.colors.get(pair[0],{"r":0.0,"g":0.0,"b":0.0})
				halo.set_shader_parameter(pair[1],Vector3(c.r,c.g,c.b))
			halo.set_shader_parameter("glow_strength",float(record.floats.get("_GlowStrength0",0.0)))
			halo.set_shader_parameter("glow_strictness",float(record.floats.get("_GlowStrictness0",1.0)))
			material=halo
		elif shader_id in HAIR_SHADER_IDS and tex.has("_MainTex") and tex.has("_HairSpecTex") and tex.has("_MaskTex"):
			var hair:=ShaderMaterial.new();hair.shader=load("res://shaders/native_hair.gdshader")
			hair.set_shader_parameter("main_texture",load(tex._MainTex));hair.set_shader_parameter("mask_texture",load(tex._MaskTex));hair.set_shader_parameter("hair_spec_texture",load(tex._HairSpecTex))
			hair.set_shader_parameter("native_cull",int(record.floats.get("_Cull",2.0)))
			_set_vector3_properties(hair,record.colors,CHARACTER_RGB_PROPERTIES)
			_set_vector3_properties(hair,record.colors,{"_TwoSideTint":"two_side_tint"})
			material=hair
		elif (shader_id in FACE_SHADER_IDS or name.ends_with("Face")) and tex.has("_MainTex") and tex.has("_MaskTex"):
			var face:=ShaderMaterial.new();face.shader=load("res://shaders/native_face.gdshader")
			face.set_shader_parameter("main_texture",load(tex._MainTex));face.set_shader_parameter("mask_texture",load(tex._MaskTex))
			material=face
		elif shader_id==EYEBROW_COLOR_SHADER_ID or (shader_id in EYEBROW_TEXTURE_SHADER_IDS and tex.has("_MainTex")):
			material=_eyebrow_material(record)
		if material is ShaderMaterial:
			for key in FLOAT_MAP:
				if record.floats.has(key):material.set_shader_parameter(FLOAT_MAP[key],float(record.floats[key]))
			for key in COLOR_MAP:
				if record.colors.has(key):
					var c:Dictionary=record.colors[key];material.set_shader_parameter(COLOR_MAP[key],Vector3(c.r,c.g,c.b))
		if material!=null:
			if shader_id in OUTLINE_SHADER_IDS and tex.has("_MainTex"):
				material.next_pass=_outline_material(record)
			materials[name]=material
	var retained:Dictionary={}
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null:continue
		for surface in mesh.mesh.get_surface_count():
			var original=mesh.mesh.surface_get_material(surface)
			if original!=null and materials.has(original.resource_name):mesh.set_surface_override_material(surface,materials[original.resource_name])
			var active:Material=mesh.get_surface_override_material(surface)
			if active!=null:retained[active]=true
	# A MeshInstance releases its surface materials before freeing its renderer
	# instance. A pending renderer update can then query a freed material RID.
	# The model outlives its children: keep their actual overrides (and next_pass
	# chains) alive until every child renderer is gone. Replace on reapply, and
	# include unchanged overrides when bindings are partial; never cache globally.
	model.set_meta("_native_material_keepalive",retained.keys())
