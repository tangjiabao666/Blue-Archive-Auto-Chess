extends Node3D
## Developer-only real rendered configurable source-skill verification; never the normal match.
const Session=preload("res://core/game_session.gd")
const CombatAudio=preload("res://scripts/native_combat_audio.gd")
const Stage=preload("res://scripts/battle_stage.gd")
@export var team_size:int=7
@export var opponent_offset:int=0
@export var player_offset:int=0
@export var report_slug:String="seven-v-seven"
var session=Session.new()
var combat_audio:Node
var stage:Node3D
var label:Label
var time:=0.0
var samples:Array[float]=[]
var cpu_samples:Array[Vector2]=[]
var captured:Dictionary={}
var finished:=false
func _ready():
	var requested_scale:String=OS.get_environment("BLUE_A_RENDER_SCALE")
	if not requested_scale.is_empty() and requested_scale.is_valid_float():
		get_viewport().scaling_3d_scale=clampf(float(requested_scale),0.25,1.0)
		report_slug+="-scale-%03d"%int(get_viewport().scaling_3d_scale*100)
	combat_audio=CombatAudio.new();combat_audio.output_enabled=DisplayServer.get_name()!="headless";add_child(combat_audio)
	stage=Stage.new();add_child(stage);stage.configure(session.profiles,Session.OBSTACLES)
	var roster:Array=[]
	for team in range(2):
		for i in range(team_size):roster.append({"id":team*7+i,"team":team,"cell":Vector2((i-(team_size-1)*0.5)*1.6,3.8 if team==0 else -3.8),"character_id":Session.ACTIVE[(i+player_offset+team*opponent_offset)%Session.ACTIVE.size()],"star":2})
	var error:String=session.clock.sim.configure(roster,{"seed":771,"random_damage":false,"initial_basic_delay_cap_seconds":Session.INITIAL_BASIC_DELAY_CAP_SECONDS})
	if not error.is_empty():push_error(error);return
	session.clock.generation=1;session.clock.sim.start();stage.set_roster(session.clock.sim.units,1,false)
	combat_audio.begin_roster(session.clock.sim.units,1)
	var canvas:=CanvasLayer.new();canvas.layer=10;add_child(canvas)
	label=Label.new();label.position=Vector2(22,18);label.add_theme_color_override("font_color",Color("203e54"));label.add_theme_font_size_override("font_size",18);canvas.add_child(label)
func _process(delta:float):
	if session.clock.sim.units.is_empty():return
	var cpu_start:=Time.get_ticks_usec()
	var events:Array=[]
	if session.clock.sim.phase=="running":
		events=session.clock.advance(delta);time=session.clock.sim.tick*0.05+session.clock.accumulator
		if time>5.0 and delta>0:samples.append(delta)
	else:time+=delta
	var cpu_sim:=Time.get_ticks_usec()-cpu_start
	var view_start:=Time.get_ticks_usec()
	stage.update_display(session.clock.sim.units,events,time)
	if not finished:
		for event in events:combat_audio.consume(event)
		combat_audio.update_time(time,false)
	if time>5.0 and session.clock.sim.phase=="running":cpu_samples.append(Vector2(cpu_sim,Time.get_ticks_usec()-view_start))
	label.text="开发验证 · %dv%d 原始角色 / 二星自动 EX     %.1fs · %d FPS\nEsc 返回游戏 · 非成品画质验收"%[team_size,team_size,time,Engine.get_frames_per_second()]
	for milestone in [5,8,10,15,18,20,30]:
		if time>=milestone and not captured.has(milestone):captured[milestone]=true;_capture(milestone)
	if session.clock.sim.phase=="finished" and not finished:finished=true;_write_report();combat_audio.reset(1)
func _unhandled_input(event:InputEvent):
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:get_tree().change_scene_to_file("res://scripts/gameplay.tscn")
func _capture(index:int):
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/screenshots"))
	get_viewport().get_texture().get_image().save_png("res://evidence/screenshots/qa-%s-%02d.png"%[report_slug,index])
func _write_report():
	var sorted=samples.duplicate();sorted.sort();var total:=0.0
	for sample in sorted:total+=sample
	var report={"scope":"developer rendered %dv%d alltwo-star battle after5s warmup"%[team_size,team_size],"adapter":RenderingServer.get_video_adapter_name(),"display":DisplayServer.get_name(),"frames":sorted.size(),"avg_fps":sorted.size()/maxf(total,0.001),"p95_frame_ms":sorted[int(sorted.size()*0.95)]*1000.0 if not sorted.is_empty() else 0.0,"sim_tick":session.clock.sim.tick,"winner":session.clock.sim.winner,"vfx":stage.native_vfx.diagnostics(),"skill_props":stage.native_props.diagnostics(),"audio":combat_audio.diagnostics(),"ground_mines":stage.native_mines.diagnostics(),"render_scale":get_viewport().scaling_3d_scale,"memory_static_mb":OS.get_static_memory_usage()/1048576.0,"memory_peak_mb":OS.get_static_memory_peak_usage()/1048576.0}
	var cpu:=Vector2.ZERO
	for sample in cpu_samples:cpu+=sample
	report["mean_simulation_cpu_ms"]=cpu.x/maxi(cpu_samples.size(),1)/1000.0
	report["mean_presentation_cpu_ms"]=cpu.y/maxi(cpu_samples.size(),1)/1000.0
	var file:=FileAccess.open("res://evidence/qa-"+report_slug+"-"+DisplayServer.get_name().to_lower()+".json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"  "))
	if OS.get_environment("BLUE_A_BENCH_EXIT")=="1":get_tree().quit()
