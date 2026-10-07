extends SceneTree
## Paired real-pixel diagnostic of the expanded 3v3 Haruna start flash.
## Only sorting_offset differs. The old ignored-bias case is diagnostic-only.
const Session=preload("res://core/game_session.gd")
const Stage=preload("res://scripts/battle_stage.gd")
var stage:Node3D
func _initialize()->void:call_deferred("run")
func run()->void:
 root.size=Vector2i(1280,900)
 var session=Session.new();stage=Stage.new();root.add_child(stage)
 stage.configure(session.profiles,Session.OBSTACLES)
 var roster:Array=[]
 for team in range(2):
  for i in range(3):roster.append({"id":team*7+i,"team":team,"cell":Vector2((i-1)*1.6,3.8 if team==0 else -3.8),"character_id":Session.ACTIVE[(i+7+team*3)%Session.ACTIVE.size()],"star":2})
 var error:String=session.clock.sim.configure(roster,{"seed":771,"random_damage":false,"initial_basic_delay_cap_seconds":Session.INITIAL_BASIC_DELAY_CAP_SECONDS})
 if not error.is_empty():push_error(error);quit(1);return
 session.clock.generation=1;session.clock.sim.start();stage.set_roster(session.clock.sim.units,1,false)
 for tick in range(1,162):
  var events:Array=session.clock.advance(0.05)
  stage.update_display(session.clock.sim.units,events,tick*0.05)
 stage.update_display(session.clock.sim.units,[],8.08)
 var saved:Array=[];var report:Array=[]
 for effect in stage.native_vfx._player._effects:
  for layer in effect.layers:
   for item in layer.particles:
    saved.append({"node":item.node,"offset":item.node.sorting_offset})
    if not effect.node.visible or not item.node.visible:continue
    var descriptor:Dictionary=item.material.get_meta("native_source_descriptor",{})
    report.append({"prefab":effect.prefab,"path":layer.path,"start":effect.start,"end":effect.end,"event":effect.event,"source_sorting_fudge":layer.render.get("m_SortingFudge",0.0),"sorting_offset":item.node.sorting_offset,"render_priority":item.material.render_priority,"source_renderer":layer.render,"material":descriptor,"position":str(item.node.global_position),"color":str(item.material.get_shader_parameter("particle_color")),"scale":str(item.node.global_basis.get_scale())})
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence"))
 var file:=FileAccess.open("res://evidence/public-start-sorting-state.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"time":8.08,"world_sorting_scale":stage.native_vfx._player.world_sorting_scale,"visible_particles":report},"  "));file.close()
 if DisplayServer.get_name()=="headless":
  print("PUBLIC_START_SORTING headless state verified; no rendered image");stage.free();quit();return
 for row in saved:row.node.sorting_offset=0.0
 await capture("res://evidence/probe-public-start-sorting-before.png")
 for row in saved:row.node.sorting_offset=row.offset
 await capture("res://evidence/probe-public-start-sorting-after.png")
 print("PUBLIC_START_SORTING paired native screenshots saved")
 stage.free();quit()
func capture(path:String)->void:
 for frame in range(5):await process_frame
 await RenderingServer.frame_post_draw
 var error:int=root.get_texture().get_image().save_png(path)
 print("PUBLIC_START_SORTING_IMAGE ",path," error=",error)
