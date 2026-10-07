extends SceneTree
## Native render receipt: baseline is the pre-fix omitted activation record.
## Run with a real rendering backend, never --headless. No combat simulation.
const View=preload("res://scripts/unit_view.gd")
const OUT="res://evidence/mutsuki-activation/captures"
const BAG="Mutsuki_Original_Bomb_Weapon"
var records:Array=[]
func _initialize():call_deferred("run")
func create_subject(profile:Dictionary,mode:String)->Dictionary:
	var viewport=SubViewport.new();viewport.size=Vector2i(720,720)
	viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world=Node3D.new();viewport.add_child(world)
	var env=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("e2e8ef")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=0.8
	world.add_child(env)
	var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-30,0);world.add_child(light)
	var view=View.new();world.add_child(view)
	var p=profile.duplicate(true)
	if mode=="baseline":p.erase("activation_windows")
	var unit={"id":0,"team":0,"cell":Vector2.ZERO,"range":3,"presentation":p}
	view.setup(unit,{},1);view._disk.visible=false
	var camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3.2;camera.position=Vector3(3,1.8,-5);world.add_child(camera)
	camera.look_at(Vector3(0,0.85,0));camera.current=true
	view.consume({"type":"skill","actor_id":0,"generation":1,"event_id":"capture-ex","tick":20,"recovery_ticks":106})
	return {"viewport":viewport,"view":view,"unit":unit,"mode":mode}
func advance(subject:Dictionary,source_time:float):
	# Same deterministic sampling schedule preserves blend/pose parity in both.
	var tick:=0.0
	while tick<source_time:
		subject.view.update_time(1.0+tick,subject.unit);tick+=1.0/120.0
	subject.view.update_time(1.0+source_time,subject.unit)
func bones(view)->Array:
	var result:Array=[]
	for skeleton in view._model.find_children("*","Skeleton3D",true,false):
		for i in skeleton.get_bone_count():result.append(skeleton.get_bone_pose(i))
	return result
func run():
	if DisplayServer.get_name()=="headless":
		printerr("Native capture requires a rendering backend; rerun without --headless.");quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var profile:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json")).mutsuki
	for point in [{"label":"initial","time":0.0},{"label":"before-release","time":2.26},{"label":"after-release","time":2.28},{"label":"late-ex","time":4.0},{"label":"after-ex","time":5.5}]:
		var baseline=create_subject(profile,"baseline");var fixed=create_subject(profile,"fixed")
		advance(baseline,point.time);advance(fixed,point.time)
		await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
		var a:Array=bones(baseline.view);var b:Array=bones(fixed.view);var same_pose:bool=a.size()==b.size()
		for i in mini(a.size(),b.size()):same_pose=same_pose and a[i].is_equal_approx(b[i])
		if not same_pose:printerr("Capture pose mismatch: "+point.label);quit(1);return
		for subject in [baseline,fixed]:
			var file:String=OUT+"/"+point.label+"-"+subject.mode+".png"
			var result:int=subject.viewport.get_texture().get_image().save_png(file)
			if result!=OK:printerr("Capture write failed: "+file);quit(1);return
			records.append({"file":file,"mode":subject.mode,"source_timeline_time":point.time,"battle_time":1.0+point.time,"clip":str(subject.view.current_clip),"native_clip_time":subject.view.player.current_animation_position,"clip_speed":subject.view._clip_speed,"bag_visible":subject.view._model.find_child(BAG,true,false).visible,"body_visible":subject.view._model.find_child("Mutsuki_Original_Body",true,false).visible,"gun_visible":subject.view._model.find_child("Mutsuki_Original_Weapon",true,false).visible,"same_native_pose":same_pose,"source_glb_sha256":profile.source_glb_sha256})
		baseline.viewport.queue_free();fixed.viewport.queue_free();await process_frame
	var receipt=FileAccess.open(OUT+"/receipt.json",FileAccess.WRITE)
	receipt.store_string(JSON.stringify({"baseline":"original profile with omitted activation window","fixed":"source-resolved LeaveAsIs ActivationTrack","records":records},"  "));receipt.close()
	print("MUTSUKI NATIVE CAPTURES ",OUT," (",records.size()," frames; same-pose checked)");quit()
