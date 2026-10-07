extends Node3D
const UnitView=preload("res://scripts/unit_view.gd")
var actors:Array=[]
var time:=0.0
var frame_samples:Array[float]=[]
func _ready()->void:
	var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	var rows:int=ceili(profiles.size()/4.0)
	var slots:Array[Vector2]=[]
	for slot in range(profiles.size()):slots.append(Vector2((slot%4-1.5)*2.6,(slot/4)*3.2))
	var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color("e9f0f5");environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color.WHITE;environment.ambient_light_energy=0.8
	var world:=WorldEnvironment.new();world.environment=environment;add_child(world)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-50,-30,0);light.light_energy=0.8;add_child(light)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=maxf(6.0,rows*2.2+3.0);camera.position=Vector3(0,10,-12);add_child(camera);camera.look_at(Vector3(0,0.7,(rows-1)*1.6));camera.current=true
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(14,rows*3.2+5);floor.mesh=plane;var mat:=StandardMaterial3D.new();mat.albedo_color=Color("d9e5ed");mat.roughness=1.0;mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;floor.material_override=mat;add_child(floor)
	var font:=SystemFont.new();font.font_names=PackedStringArray(["Noto Sans CJK SC","Microsoft YaHei","Arial"])
	var index:=0
	for key in profiles:
		var unit={"id":index,"team":0,"cell":slots[index],"range":3.0,"attack_ticks":60,"presentation":profiles[key]}
		var view=UnitView.new();add_child(view);view.setup(unit,{},1);actors.append({"view":view,"unit":unit})
		var label:=Label3D.new();label.text=profiles[key].display_name;label.font=font;label.font_size=38;label.pixel_size=0.005;label.position=Vector3(slots[index].x,0.07,slots[index].y-0.55);label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.modulate=Color("20384f");label.outline_size=0;add_child(label)
		index+=1
	var ui:=CanvasLayer.new();add_child(ui)
	var title:=Label.new();title.text="BLUE / A     原始角色阵容预览";title.position=Vector2(32,24);title.add_theme_font_override("font",font);title.add_theme_color_override("font_color",Color("20384f"));title.add_theme_font_size_override("font_size",26);ui.add_child(title)
	var note:=Label.new();note.text="%d 个不同角色 · 原始模型与动作数据 · 材质与特效仍在还原\nEsc 返回战斗测试 · F12 保存当前画面"%profiles.size();note.position=Vector2(32,810);note.add_theme_font_override("font",font);note.add_theme_color_override("font_color",Color("3e6079"));note.add_theme_font_size_override("font_size",16);ui.add_child(note)
func _process(delta:float)->void:
	time+=delta
	if delta>0.0:
		frame_samples.append(delta)
		if frame_samples.size()>600:frame_samples.pop_front()
	for actor in actors:actor.view.update_time(time,actor.unit)
func _unhandled_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_ESCAPE:get_tree().change_scene_to_file("res://battle.tscn")
		elif event.keycode==KEY_F12:_capture()
func _capture()->void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/screenshots"))
	get_viewport().get_texture().get_image().save_png("res://evidence/screenshots/07-native-roster.png")
	var sorted=frame_samples.duplicate();sorted.sort()
	var total:=0.0
	for value in sorted:total+=value
	var report={"scope":"cloud seven-character idle gallery, not full battle or local Windows benchmark","samples":sorted.size(),"engine_fps":Engine.get_frames_per_second(),"average_fps":sorted.size()/maxf(total,0.0001),"p95_frame_ms":sorted[int(sorted.size()*0.95)]*1000.0 if not sorted.is_empty() else 0.0,"adapter":RenderingServer.get_video_adapter_name()}
	var file=FileAccess.open("res://evidence/gallery-performance.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "))
