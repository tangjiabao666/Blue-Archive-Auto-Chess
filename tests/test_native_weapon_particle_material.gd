extends SceneTree
var failures:=0
func ck(ok:bool,message:String):
	if not ok:failures+=1;printerr(message)
func _initialize():
	var source=load("res://vfx/native_source.gd")
	var factory=load("res://vfx/materials/native_materials.gd")
	var data:Dictionary=source.read_json("res://data/effects/common-landmine/visual-templates.json")
	var descriptor:Dictionary=data.materials.values()[0]
	var report:Dictionary=factory.diagnostics(descriptor,"res://data/effects")
	ck(report.supported,"native MX/C-Weapon mesh particles are supported")
	var material=factory.create(descriptor,"res://data/effects",false)
	ck(material!=null,"native weapon material instantiates")
	if material!=null:
		ck(material.get_shader_parameter("main_texture")!=null and material.get_shader_parameter("source_texture")!=null,"both source textures loaded")
		ck(material.get_shader_parameter("glow_enabled")==true,"source glow keyword retained")
		ck(is_equal_approx(float(material.get_shader_parameter("glow_strength0")),0.5),"source glow strength retained")
		ck(is_equal_approx(float(material.get_shader_parameter("shadow_threshold")),float(descriptor.floats._ShadowThreshold)),"native numeric properties retained")
	var no_keywords:Dictionary=descriptor.duplicate(true);no_keywords.keywords=null
	var plain=factory.create(no_keywords,"res://data/effects",false)
	ck(plain!=null,"source-null keyword list is valid opaque weapon material")
	if plain!=null:ck(plain.get_shader_parameter("glow_enabled")==false,"source-null keywords do not enable glow")
	print("WEAPON PARTICLE MATERIAL FAILURES=",failures);quit(1 if failures else 0)
