extends SceneTree
## Native diagnostic only: untouched source actors at fixed idle time/cameras.
const View=preload("res://scripts/unit_view.gd")
const OUT="res://evidence/character-polish/portraits/"
func _initialize():call_deferred("run")
func run():
 if DisplayServer.get_name()=="headless":printerr("Real rendering backend required");quit(2);return
 root.title="Blue-A | Character polish audit"
 var output_dir:String=OUT+("after/" if "after" in OS.get_cmdline_user_args() else "")
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
 var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"));var records:Array=[]
 for key in profiles:
  var viewport=SubViewport.new();viewport.size=Vector2i(640,640);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
  var world=Node3D.new();viewport.add_child(world)
  var env=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("e2e8ef");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=0.8;world.add_child(env)
  var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-30,0);world.add_child(light)
  var view=View.new();world.add_child(view)
  var unit={"id":0,"team":0,"cell":Vector2.ZERO,"range":3.0,"attack_ticks":60,"presentation":profiles[key]}
  view.setup(unit,{},1);view._disk.visible=false
  for i in range(1,31):view.update_time(i/120.0,unit)
  var camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.8;world.add_child(camera);camera.current=true
  for angle in ["front","three-quarter"]:
   camera.position=Vector3(0,1.6,-5) if angle=="front" else Vector3(3,1.8,-5);camera.look_at(Vector3(0,0.85,0))
   await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
   var path:String=output_dir+str(key)+"-"+angle+".png";var result:int=viewport.get_texture().get_image().save_png(path)
   if result!=OK:printerr("capture failed ",path);quit(1);return
   records.append({"character":key,"angle":angle,"file":path,"diagnostics":view.diagnostics(),"source_glb_sha256":profiles[key].get("source_glb_sha256","")})
  viewport.queue_free();await process_frame
 var f=FileAccess.open(output_dir+"receipt.json",FileAccess.WRITE);f.store_string(JSON.stringify({"scope":"Native llvmpipe idle portrait audit, not battle/FPS acceptance","records":records},"  "));f.close()
 print("CHARACTER_PORTRAITS frames=",records.size());quit()
