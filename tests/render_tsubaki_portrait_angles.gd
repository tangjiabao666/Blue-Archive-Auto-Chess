extends Node3D
func _ready():
	var profile=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json")).tsubaki
	var views=[]
	for x in [-2.5,-1.2,1.2,2.5]:
		var viewport=SubViewport.new();viewport.size=Vector2i(256,256);viewport.transparent_bg=true;viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
		var world=Node3D.new();viewport.add_child(world)
		var view=load("res://scripts/unit_view.gd").new();world.add_child(view);var unit={"id":0,"team":0,"cell":Vector2.ZERO,"range":3,"presentation":profile};view.setup(unit,{},1);view.update_time(0.4,unit);view._disk.visible=false
		var focus=Vector3(0,1,0)
		for skeleton in view._model.find_children("*","Skeleton3D",true,false):
			var bone=skeleton.find_bone("Bip001 Head")
			if bone<0:bone=skeleton.find_bone("Bip001_Head")
			if bone>=0:focus=skeleton.global_transform*skeleton.get_bone_global_pose(bone).origin
		focus.y+=0.18
		var camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.3;camera.position=focus+Vector3(x,0.3,-3);world.add_child(camera);camera.look_at(focus);camera.current=true
		views.append({"viewport":viewport,"x":x})
	await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
	for row in views:row.viewport.get_texture().get_image().save_png("res://evidence/tsubaki-portrait-%s.png"%str(row.x))
	get_tree().quit()
