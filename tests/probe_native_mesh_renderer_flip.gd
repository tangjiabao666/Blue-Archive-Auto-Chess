extends SceneTree
## Real-source before/after pixel harness. No shader, color, texture, or source edits.
## Full prefab and explicitly labeled isolated-layer pairs use the same camera/time.
const Player=preload("res://vfx/native_effect_player.gd")
const Source=preload("res://vfx/native_source.gd")
const FILE="res://data/effects/iori/visual-templates.json"
const PREFAB="FX_Iori_Original_Ex01_Motion_Start"
var players:Array=[]
var world:Node3D
var camera:Camera3D
var title:Label
func anchor(_b:Dictionary,_e:Dictionary,_t:float)->Transform3D:return Transform3D.IDENTITY
func _initialize()->void:call_deferred("run")
func run()->void:
 root.size=Vector2i(1000,800)
 world=Node3D.new();root.add_child(world)
 var environment:=WorldEnvironment.new();var env:=Environment.new()
 env.background_mode=Environment.BG_COLOR;env.background_color=Color(.16,.19,.23)
 environment.environment=env;world.add_child(environment)
 camera=Camera3D.new();world.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.current=true
 var canvas:=CanvasLayer.new();world.add_child(canvas)
 title=Label.new();title.position=Vector2(16,14);canvas.add_child(title)
 var data:Dictionary=Source.read_json(FILE);var source:Dictionary=Source.find_prefab(data,PREFAB)
 var control:Dictionary=source.duplicate(true)
 for node in control.nodes:
  for c in node.components:
   if c.type=="ParticleSystemRenderer":c.nativeParameters.m_Flip={"x":0.0,"y":0.0,"z":0.0}
 var event:Dictionary={"start":0.0,"duration":1.0,"speed":1.0,"clipIn":0.0,"particleRandomSeed":7390,"bindings":[]}
 for prefab in [control,source]:
  var player=Player.new();world.add_child(player);players.append(player)
  player._spawn_event(1,data,prefab,"res://data/effects",event,0.0,anchor)
 var times:Array[float]=[0.26,0.4]
 var report:Array=[]
 for at in times:
  for isolated in [false,true]:
   var bounds:AABB;var have_bounds:bool=false
   for player in players:
    player.update_time(at)
    for effect in player._effects:
     for layer in effect.layers:
      for item in layer.particles:
       if isolated and not layer.path.ends_with("/stretch_line (9)"):item.node.visible=false
       if not item.node.visible:continue
       var current:AABB=item.node.global_transform*item.node.get_aabb()
       if have_bounds:bounds=bounds.merge(current)
       else:bounds=current;have_bounds=true
       if layer.path.ends_with("/stretch_line (9)"):
        report.append({"time":at,"case":"isolated_line9" if isolated else "full_prefab","variant":"ignored_flip" if player==players[0] else "source_flip","transform":str(item.node.global_transform),"flip":layer.render.get("m_Flip",{}),"pivot":layer.render.get("m_Pivot",{}),"material":item.material.resource_name,"source_cull":item.material.get_meta("native_source_descriptor",{}).get("floats",{}).get("_Cull_Mode"),"indices":item.node.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()})
   camera.position=bounds.get_center()+Vector3(0,0,12)
   camera.look_at(bounds.get_center())
   camera.size=maxf(1.0,maxf(bounds.size.y,bounds.size.x/1.25)*1.3)
   for index in range(2):
    for other in range(2):players[other].visible=other==index
    title.text="Iori native EX at %.2fs | %s | %s\nSame original mesh, material and particle schedule; only source renderer flip differs"%[at,"ISOLATED stretch_line (9)" if isolated else "FULL PREFAB","Ignored flip baseline" if index==0 else "Source deterministic mesh flip"]
    if DisplayServer.get_name()!="headless":
     var path:String="res://evidence/native-mesh-flip-%s-%.2f-%s.png"%["line9" if isolated else "full",at,"before" if index==0 else "after"]
     await capture(path)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/native-mesh-flip"))
 FileAccess.open("res://evidence/native-mesh-flip/paired-state.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("NATIVE_MESH_FLIP_PAIR ","headless state only; no pixel verification" if DisplayServer.get_name()=="headless" else "native paired images captured")
 world.free();quit()
func capture(path:String)->void:
 for frame in range(5):await process_frame
 await RenderingServer.frame_post_draw
 var error:int=root.get_texture().get_image().save_png(path)
 print("NATIVE_MESH_FLIP_IMAGE ",path," error=",error)
