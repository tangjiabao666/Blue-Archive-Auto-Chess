extends SceneTree
## Requires a real renderer. Synthetic geometry isolates recovered material behavior.
## No source assets or presentation parameters are changed by this probe.
const Adapter=preload("res://scripts/native_material_adapter.gd")
var checks:=0
var failures:=0
var records:Array=[]
var output:String="res://evidence/character-polish/material-probe"
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func _texture(left:Color,right:Color)->ImageTexture:
	var image:=Image.create(2,1,false,Image.FORMAT_RGBA8)
	image.set_pixel(0,0,left);image.set_pixel(1,0,right)
	return ImageTexture.create_from_image(image)
func _quad()->MeshInstance3D:
	var mesh:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(1.0,1.0);mesh.mesh=quad
	return mesh
func _brow()->ShaderMaterial:
	var material:=ShaderMaterial.new();material.shader=load("res://shaders/native_eyebrow.gdshader")
	material.set_shader_parameter("native_cull",0)
	return material
func _hair(cull:int)->ShaderMaterial:
	var material:=ShaderMaterial.new();material.shader=load("res://shaders/native_hair.gdshader")
	material.set_shader_parameter("native_cull",cull)
	material.set_shader_parameter("main_texture",_texture(Color.WHITE,Color.WHITE))
	material.set_shader_parameter("mask_texture",_texture(Color.BLACK,Color.BLACK))
	material.set_shader_parameter("hair_spec_texture",_texture(Color(0.5,0.5,1,1),Color(0.5,0.5,1,1)))
	material.set_shader_parameter("spec_strength",0.0);material.set_shader_parameter("rim_strength",0.0)
	material.set_shader_parameter("ambient_tone",Vector3.ZERO);material.set_shader_parameter("mask_g_sensitivity",0.0)
	material.set_shader_parameter("shadow_threshold",0.0);material.set_shader_parameter("shadow_tint",Vector3.ONE)
	material.set_shader_parameter("light_direction",Vector3(0,0,1))
	return material
func _capture(label:String,material:ShaderMaterial,back:bool=false,blocker:bool=false,actor_scale:float=1.0)->Image:
	var viewport:=SubViewport.new();viewport.size=Vector2i(128,128);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var world:=Node3D.new();viewport.add_child(world)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color.BLACK
	world.add_child(environment)
	var mesh:=_quad();mesh.scale=Vector3.ONE*actor_scale;mesh.material_override=material;world.add_child(mesh)
	if blocker:
		# At scale 1, correction .08 does not cross z=.10. At scale 2 it does.
		# This distinguishes source object-space distance from a world-space bias.
		var cover:=_quad();cover.scale=Vector3.ONE*3.0;cover.position.z=0.10
		var cover_material:=StandardMaterial3D.new();cover_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		cover_material.albedo_color=Color.BLUE;cover.material_override=cover_material;world.add_child(cover)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.0
	camera.position=Vector3(0,0,-3 if back else 3);world.add_child(camera);camera.look_at(Vector3.ZERO);camera.current=true
	await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
	var image:=viewport.get_texture().get_image()
	ck(image.save_png(output+"/"+label+".png")==OK,"capture saved: "+label)
	var center:=image.get_pixel(64,64)
	records.append({"case":label,"center":[center.r,center.g,center.b,center.a]})
	viewport.queue_free();await process_frame
	return image
func _center(image:Image)->Color:return image.get_pixel(64,64)
func run()->void:
	if DisplayServer.get_name()=="headless":printerr("Real renderer required; headless cannot prove pixels");quit(2);return
	if not OS.get_environment("BLUE_A_MATERIAL_PROBE_OUT").is_empty():output=OS.get_environment("BLUE_A_MATERIAL_PROBE_OUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var front:=_center(await _capture("hair-cull-off-front",_hair(0)))
	var back:=_center(await _capture("hair-cull-off-back",_hair(0),true))
	ck(front.r>0.9 and back.r>0.05 and back.r<front.r*0.8,"Cull off renders both faces with darker source back branch")
	ck(_center(await _capture("hair-cull-back-front",_hair(2))).r>0.9,"Cull back keeps front")
	ck(_center(await _capture("hair-cull-back-back",_hair(2),true)).r<0.01,"Cull back removes back")
	ck(_center(await _capture("hair-cull-front-front",_hair(1))).r<0.01,"Cull front removes front")
	ck(_center(await _capture("hair-cull-front-back",_hair(1),true)).r>0.05,"Cull front keeps back")
	var colored_back:=_hair(0);colored_back.set_shader_parameter("two_side_tint",Vector3(1,0,0))
	var back_red:=_center(await _capture("hair-two-side-tint",colored_back,true))
	ck(back_red.r>0.05 and back_red.g<0.01 and back_red.b<0.01,"TwoSideTint affects recovered back branch")
	var textured:=_brow();textured.set_shader_parameter("use_main_texture",true)
	textured.set_shader_parameter("main_texture",_texture(Color(1,0,0,0),Color(0,1,0,1)))
	var uv_image:=await _capture("eyebrow-texture-uv-alpha",textured)
	var left:=uv_image.get_pixel(48,64);var right:=uv_image.get_pixel(80,64)
	ck(left.r>0.8 and left.g<0.2,"source texture UV left sampled even at alpha zero")
	ck(right.g>0.8 and right.r<0.2,"source texture UV right sampled unchanged")
	var color:=_brow();color.set_shader_parameter("tint",Vector3(1,0,0));color.set_shader_parameter("main_texture",_texture(Color.GREEN,Color.GREEN))
	var tint:=_center(await _capture("eyebrow-one-color-tint",color))
	ck(tint.r>0.9 and tint.g<0.01,"OneColor preserves tint and does not sample bound texture")
	color.set_shader_parameter("native_cull",2)
	ck(_center(await _capture("eyebrow-cull-back",color,true)).r<0.01,"eyebrow Cull back removes back")
	color.set_shader_parameter("native_cull",1)
	ck(_center(await _capture("eyebrow-cull-front",color)).r<0.01,"eyebrow Cull front removes front")
	color.set_shader_parameter("native_cull",0);color.set_shader_parameter("z_correction",0.08)
	var small:=_center(await _capture("eyebrow-offset-scale-one",color,false,true,1.0))
	var large:=_center(await _capture("eyebrow-offset-scale-two",color,false,true,2.0))
	ck(small.b>0.9 and small.r<0.01,"object offset .08 at scale1 stays behind z .10 blocker")
	ck(large.r>0.9 and large.b<0.01,"object offset .08 at scale2 crosses z .10 blocker")
	color.set_shader_parameter("z_correction",0.0)
	var zero:=_center(await _capture("eyebrow-offset-zero",color,false,true,2.0))
	ck(zero.b>0.9 and zero.r<0.01,"zero correction leaves original geometry behind blocker")
	var receipt:=FileAccess.open(output+"/receipt.json",FileAccess.WRITE)
	receipt.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"records":records},"  "));receipt.close()
	print("NATIVE HAIR EYEBROW RENDER CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
