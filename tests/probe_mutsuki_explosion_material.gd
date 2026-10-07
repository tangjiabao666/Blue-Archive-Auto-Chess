extends SceneTree
## Run on baseline and corrected revisions with -- baseline or -- restored.
## Captures the untouched direct-spawn prefab and its isolated authored layer.
const Player=preload("res://vfx/native_effect_player.gd")
const TEMPLATE="res://data/effects/mutsuki/visual-templates.json#FX_Mutsuki_Explosion"
func anchor(_binding:Dictionary,_event:Dictionary,_at:float)->Transform3D:return Transform3D.IDENTITY
func _initialize()->void:call_deferred("run")
func run()->void:
 var args:=OS.get_cmdline_user_args()
 var label:String=args[0] if not args.is_empty() else "restored"
 if label not in ["baseline","restored"]:printerr("Use baseline or restored");quit(2);return
 root.size=Vector2i(1000,800)
 var world:=Node3D.new();root.add_child(world)
 var environment:=WorldEnvironment.new();var env:=Environment.new()
 env.background_mode=Environment.BG_COLOR;env.background_color=Color(0.16,0.19,0.23)
 environment.environment=env;world.add_child(environment)
 var camera:=Camera3D.new();world.add_child(camera)
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=10.0;camera.current=true
 var center:=Vector3(-0.24,0.0,-4.0)
 camera.position=center+Vector3(0,5,12);camera.look_at(center)
 var player=Player.new();world.add_child(player)
 player.spawn(TEMPLATE,3614,0.0,anchor)
 var report:Dictionary={"variant":label,"template":TEMPLATE,"seed":3614,"anchor":"identity","display":DisplayServer.get_name(),"camera_transform":str(camera.global_transform),"camera_size":camera.size,"frames":[]}
 var output:String="res://evidence/mutsuki-explosion-source"
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
 for at in [0.1,0.5,1.5]:
  for isolated in [false,true]:
   player.update_time(at)
   var frame:Dictionary={"time":at,"isolated":isolated,"layers":[]}
   for effect in player._effects:
    for layer in effect.layers:
     var summary:Dictionary={"path":layer.path,"particles":[]}
     for item in layer.particles:
      if isolated and not layer.path.ends_with("/bao_explosion"):item.node.visible=false
      summary.particles.append({"visible":item.node.visible,"birth":item.birth,"life":item.life,"transform":str(item.node.global_transform),"custom0":str(item.material.get_shader_parameter("custom0")),"material":item.material.resource_name})
     frame.layers.append(summary)
   if DisplayServer.get_name()!="headless":
    for index in range(5):await process_frame
    await RenderingServer.frame_post_draw
    var file:String=output.path_join("%s-%s-%.2f.png"%[label,"bao" if isolated else "full",at])
    var error:int=root.get_texture().get_image().save_png(file)
    if error!=OK:printerr("Capture failed: ",file);world.free();quit(1);return
    frame.image=file
   report.frames.append(frame)
 report.diagnostics=player.diagnostics()
 FileAccess.open(output.path_join(label+("-headless-state.json" if DisplayServer.get_name()=="headless" else "-state.json")),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("MUTSUKI_EXPLOSION_PROBE ",label," ","headless state only" if DisplayServer.get_name()=="headless" else "six native images captured")
 world.free();quit()
