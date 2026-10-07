extends Node
## Render real shader variants once offscreen before interaction; not an FPS guarantee.
const Stage=preload("res://scripts/battle_stage.gd")
const Session=preload("res://core/game_session.gd")
const Effects=preload("res://vfx/native_effect_player.gd")
static var completed:=false
static var last_report:Dictionary={}
var report:Dictionary={}
func run(profiles:Dictionary)->void:
	if completed or DisplayServer.get_name()=="headless":return
	var started:=Time.get_ticks_msec()
	var viewport:=SubViewport.new();viewport.size=Vector2i(64,64);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
	var stage=Stage.new();viewport.add_child(stage);stage.configure(profiles,Session.OBSTACLES)
	var simulation=preload("res://core/character_sim.gd").new();var units:Array=[]
	for i in range(Session.ACTIVE.size()):units.append(simulation.preview_unit(Session.ACTIVE[i],2,i,0,Vector2(-3.0+i,1.0)))
	stage.set_roster(units,1,false)
	var events:Array=[]
	for unit in units:events.append({"type":"skill","ability":"ex","actor_id":unit.id,"event_id":"warmup_"+str(unit.id),"generation":1,"tick":1,"target_cell":Vector2(0,-2),"recovery_ticks":120})
	stage.update_display(units,events,0.15)
	# CPU warming retains shared source materials; real draw calls warm shader programs.
	# Frustum-visible quads issue each material variant even when depth-occluded.
	for material in Effects._material_cache.values():
		if material==null:continue
		var mesh:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(0.1,0.1);mesh.mesh=quad;mesh.material_override=material;stage.add_child(mesh);mesh.position=Vector3(0,0.5,0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	report={"rendered":true,"material_variants":Effects._material_cache.size(),"elapsed_ms":Time.get_ticks_msec()-started}
	last_report=report.duplicate(true)
	if OS.has_feature("editor"):
		var file:=FileAccess.open("res://evidence/render-warmup.json",FileAccess.WRITE)
		if file:file.store_string(JSON.stringify(report,"  "))
	completed=true
	viewport.queue_free()
