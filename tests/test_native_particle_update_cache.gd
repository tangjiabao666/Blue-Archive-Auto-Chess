extends SceneTree
## Exact-value shader updates and lifetime skipping, including seek/pool boundaries.
const Player=preload("res://vfx/native_effect_player.gd")
const Particles=preload("res://vfx/native_particles.gd")
const TEMPLATE="res://data/effects/hoshino/visual-templates.json#FX_Hoshino_Original_Ex01_Motion_Mesh_Muzzle"
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: "+label)
func identity(_binding:Dictionary,_event:Dictionary,_at:float)->Transform3D:return Transform3D.IDENTITY
func _initialize()->void:call_deferred("run")
func check_values(player,at:float)->void:
 for effect in player._effects:
  var active:bool=at>=effect.start and at<effect.end
  ck(effect.node.visible==active,"effect window at "+str(at))
  if not active:continue
  var local_time:float=float(effect.clip_in)+(at-float(effect.start))*float(effect.speed)
  for layer in effect.layers:
   for item in layer.particles:
    var state:Dictionary=Particles.state(layer.params,item.sample,local_time)
    ck(item.node.visible==state.visible,"exact lifetime visibility at "+str(at))
    if not state.visible:continue
    var rotation:Vector3=state.rotation
    var basis:Basis=Basis.from_euler(rotation,EULER_ORDER_YXZ)
    if layer.mode==2:basis=Basis(Vector3.RIGHT,-PI/2.0)*basis
    var size:Vector3=state.size
    if layer.mode==1:size.y*=maxf(1.0,float(layer.render.get("m_LengthScale",2.0)))
    var transform:Transform3D=layer.base_transform*Transform3D(basis.scaled_local(size),state.position)
    transform.origin+=state.world_offset*player.world_gravity_scale
    ck(item.node.global_transform==transform,"unchanged source transform")
    ck(item.material.get_shader_parameter("particle_color")==state.color,"unchanged source color")
    var packed:Array[Vector4]=Particles.shader_custom_streams(layer.render,state.custom0,state.custom1)
    ck(item.material.get_shader_parameter("custom0")==packed[0] and item.material.get_shader_parameter("custom1")==packed[1],"unchanged source custom streams")
    ck(item.material.get_shader_parameter("uv_sheet")==state.uv_sheet,"unchanged source UV sheet")
    ck(item.material.get_shader_parameter("effect_time")==at,"unchanged global shader time")
    ck(item.material.get_shader_parameter("roll")== (rotation.z if layer.billboard else 0.0),"unchanged source roll")
func run()->void:
 var player=Player.new();root.add_child(player)
 var has_mapping:bool=player.has_method("_custom_stream_mapping") and player.has_method("_pack_custom_streams")
 ck(has_mapping,"immutable custom stream layouts compile once per layer")
 if has_mapping:
  var layouts:Array=[{}, {"m_UseCustomVertexStreams":false}, {"m_UseCustomVertexStreams":true,"m_VertexStreams":[]}, {"m_UseCustomVertexStreams":true,"m_VertexStreams":[0,3,4,5,34,38]}, {"m_UseCustomVertexStreams":true,"m_VertexStreams":[0,3,4,34,38]}, {"m_UseCustomVertexStreams":true,"m_VertexStreams":[0,3,4,32,38]}, {"m_UseCustomVertexStreams":true,"m_VertexStreams":[4,99,34]}]
  var rng:=RandomNumberGenerator.new();rng.seed=1701
  for n in range(100):
   var streams:Array=[]
   for i in range(12):streams.append([0,1,2,3,4,5,31,32,33,34,35,36,37,38][rng.randi_range(0,13)])
   layouts.append({"m_UseCustomVertexStreams":true,"m_VertexStreams":streams})
  for layout in layouts:
   var mapping=player._custom_stream_mapping(layout)
   var a:=Vector4(0.125,-12.5,7.25,1000);var b:=Vector4(-4.5,0.0625,80.0,0.0)
   ck(player._pack_custom_streams(mapping,a,b)==Particles.shader_custom_streams(layout,a,b),"compiled mapping preserves exact source packing")
 var handle:int=player.spawn(TEMPLATE,942,0.0,identity,2.0)
 player.update_time(0.26);check_values(player,0.26)
 var before:Dictionary=player.diagnostics()
 ck(before.has("shader_parameter_writes"),"diagnostics measure actual shader submissions")
 ck(before.has("particle_state_evaluations"),"diagnostics measure actual particle state evaluations")
 var snapshot:Dictionary=player.snapshot()
 player.update_time(0.26)
 ck(snapshot==player.snapshot(),"paused snapshot remains value-identical")
 ck(int(player.diagnostics().get("shader_parameter_writes",-1))==int(before.get("shader_parameter_writes",-2)),"paused update submits no unchanged uniforms")
 # At a new time, every visible shader needs scene time, while static UV/custom/color do not.
 before=player.diagnostics();player.update_time(0.27);check_values(player,0.27)
 var visible_count:int=player.diagnostics().visible_particles
 var submitted:int=int(player.diagnostics().get("shader_parameter_writes",-1))-int(before.get("shader_parameter_writes",-1))
 ck(submitted>=visible_count and submitted<visible_count*6,"moving clock updates only changing shader inputs")
 # Same subtraction/boundary predicate as Particles.state, including nonmonotonic seeks.
 var times:Array[float]=[-0.01,0.0,0.01,0.26,1.9,0.1,2.0,0.26]
 for effect in player._effects:
  for layer in effect.layers:
   for item in layer.particles:
    times.append(float(item.sample.birth));times.append(float(item.sample.birth)+float(item.sample.life))
 for at in times:
  player.update_time(at);check_values(player,at)
 before=player.diagnostics();player.update_time(1.9)
 ck(player.diagnostics().visible_particles==0,"late fixture has no living particles")
 ck(int(player.diagnostics().get("particle_state_evaluations",-1))==int(before.get("particle_state_evaluations",-2)),"dead scheduled particles skip state evaluation")
 player.release(handle)
 handle=player.spawn(TEMPLATE,1234,0.0,identity,2.0);player.update_time(0.26);check_values(player,0.26)
 ck(player.diagnostics().nodes_reused>0,"pool-reused materials reinitialize their cached inputs")
 player.reset(3)
 player.spawn(TEMPLATE,942,0.0,identity,2.0);player.update_time(0.26);check_values(player,0.26)
 ck(player.diagnostics().generation==3,"reset permits fresh effects and cache state")
 player.free()
 print("PARTICLE_UPDATE_CACHE ",checks," checks; ",failures," failures")
 quit(1 if failures else 0)
