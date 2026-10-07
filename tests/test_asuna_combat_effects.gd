extends SceneTree
const Clock=preload("res://core/character_clock.gd")
const View=preload("res://scripts/unit_view.gd")
const FX=preload("res://scripts/native_combat_vfx.gd")
var output:=""
var candidate:=true
func _initialize():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
  if arg=="--candidate":candidate=true
 call_deferred("run")
func run():
 root.size=Vector2i(1154,812)
 var stage:=Node3D.new();root.add_child(stage)
 var world:=WorldEnvironment.new();var env:=Environment.new()
 env.background_mode=Environment.BG_COLOR;env.background_color=Color("cad7e0")
 env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("dfeaf0");env.ambient_light_energy=0.6
 world.environment=env;stage.add_child(world)
 var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-48,-30,0);light.light_energy=0.8;stage.add_child(light)
 var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=6.5;stage.add_child(camera)
 camera.position=Vector3(-7,5,8);camera.look_at(Vector3(0,0.5,0));camera.current=true
 var arena=load("res://scripts/arena_environment.gd").new();stage.add_child(arena);arena.configure([])
 var clock=Clock.new();clock.generation=1
 var roster:=[{"id":0,"team":0,"cell":Vector2(-1,1.4),"character_id":"asuna","star":2},{"id":1,"team":1,"cell":Vector2(1,-1.4),"character_id":"asuna","star":1}]
 var error=clock.sim.configure(roster,{"seed":715,"initial_basic_delay_cap_seconds":5.0,"max_ticks":600})
 if not error.is_empty():printerr(error);quit(2);return
 clock.sim.start()
 var profiles=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
 var views:Dictionary={}
 for unit in clock.sim.units:
  var view=View.new();stage.add_child(view);var shown:Dictionary=unit.duplicate(true);shown.presentation=profiles.asuna;view.setup(shown,{},1);views[unit.id]=view
 var fx=FX.new();stage.add_child(fx)
 if not fx.configure_fixture(profiles,"res://data/effects/asuna/battle-events-compact.json",["asuna"]):printerr("fixture rejected");quit(3);return
 fx._player.asuna_stretch_orientation_candidate=candidate
 fx._player.stretch_camera_at=func(at:float):return {"time":at,"transform":camera.global_transform,"projection":"orthographic"}
 fx.begin_roster(views,clock.sim.units,1)
 var counts:Dictionary={};var nonfinite:=0
 for frame in range(450):
  for event in clock.advance(1.0/60):
   counts[event.type]=int(counts.get(event.type,0))+1
   var at:float=event.tick*0.05
   for view in views.values():view.advance_event_time(at)
   for view in views.values():view.consume(event)
   fx.capture_event_pose(at,views.keys());fx.consume(event,clock.sim.units,true)
  var at:float=float(frame+1)/60.0
  for unit in clock.sim.units:views[unit.id].update_time(at,unit)
  fx.update_time(at)
  for view in views.values():
   if not view.global_transform.is_finite():nonfinite+=1
  await process_frame
  if frame in [180,300,400,430,449] and not output.is_empty() and DisplayServer.get_name()!="headless":
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(output+"/frame-%04d.png"%frame)
 var report:Dictionary={"fixedSamplingHz":60,"measuredFPS":null,"frames":450,"tick":clock.sim.tick,"candidate":candidate,"events":counts,"nonfinite":nonfinite,"fx":fx.diagnostics()}
 if not output.is_empty():
  var file=FileAccess.open(output+"/result.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 var expected:Dictionary={"aim":2,"attack":3,"miss":3,"damage":22,"skill":1,"buff":3,"aim_lost":1,"dash_move":32,"buff_expired":1,"dash_finished":1,"basic":2}
 var passed:bool=nonfinite==0 and fx._issues.is_empty() and counts==expected
 print("ASUNA COMBAT EFFECTS PASS=",passed," nonfinite=",nonfinite," events=",counts," glueissues=",fx._issues)
 quit(0 if passed else 4)
