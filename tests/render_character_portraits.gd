extends Node3D
## Native-model thumbnail baking, not generated substitute artwork.
var viewports:Array=[]
func _ready():
	var profiles=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	for key in profiles:
		var viewport:=SubViewport.new();viewport.size=Vector2i(256,256);viewport.transparent_bg=true;viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
		var world:=Node3D.new();viewport.add_child(world)
		var env_node:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(0,0,0,0);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=0.6;env_node.environment=env;world.add_child(env_node)
		var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-40,-25,0);light.light_energy=0.6;world.add_child(light)
		var view=load("res://scripts/unit_view.gd").new();world.add_child(view)
		var unit={"id":0,"team":0,"cell":Vector2.ZERO,"range":3,"presentation":profiles[key]};view.setup(unit,{},1);view.update_time(0.4,unit)
		if is_instance_valid(view._disk):view._disk.visible=false
		var focus:=Vector3(0,1.0,0)
		for skeleton in view._model.find_children("*","Skeleton3D",true,false):
			var index:int=skeleton.find_bone("Bip001 Head")
			if index<0:index=skeleton.find_bone("Bip001_Head")
			if index>=0:focus=skeleton.global_transform*skeleton.get_bone_global_pose(index).origin
		focus.y+=0.18
		for halo in view._model.find_children("*Halo*","MeshInstance3D",true,false):
			var bounds:AABB=halo.get_aabb()
			for corner in range(8):focus.y=maxf(focus.y,(halo.global_transform*bounds.get_endpoint(corner)).y-0.55)
		var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.3;camera.position=focus+(Vector3(2.5,0.3,-3) if key=="tsubaki" else Vector3(0,0.08,-3));world.add_child(camera);camera.look_at(focus);camera.current=true
		viewports.append({"key":key,"viewport":viewport})
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/ui/portraits"))
	for item in viewports:
		item.viewport.get_texture().get_image().save_png("res://assets/ui/portraits/"+item.key+".png")
		item.viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	print("NATIVE PORTRAITS BAKED=",viewports.size())
	if OS.get_environment("BLUE_A_BAKE_EXIT")=="1":get_tree().quit()
	else:get_tree().change_scene_to_file("res://scripts/gameplay.tscn")
