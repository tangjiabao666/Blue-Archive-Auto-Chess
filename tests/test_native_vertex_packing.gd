extends SceneTree
const Player=preload("res://vfx/native_effect_player.gd")
const Particles=preload("res://vfx/native_particles.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func identity(_binding:Dictionary,_event:Dictionary,_at:float)->Transform3D:return Transform3D.IDENTITY
func _initialize()->void:call_deferred("run")
func run()->void:
 var a:=Vector4(1,2,3,4);var b:=Vector4(5,6,7,8)
 var packed:Array[Vector4]=Particles.shader_custom_streams({"m_UseCustomVertexStreams":true,"m_VertexStreams":[0,3,4,5,34,38]},a,b)
 ck(packed==[a,b],"UV2-backed full-float4 layout unchanged")
 packed=Particles.shader_custom_streams({"m_UseCustomVertexStreams":true,"m_VertexStreams":[0,3,4,34,38]},a,b)
 ck(packed==[Vector4(3,4,5,6),Vector4(7,8,0,0)],"packed custom streams straddle TEXCOORD boundaries")
 packed=Particles.shader_custom_streams({"m_UseCustomVertexStreams":true,"m_VertexStreams":[0,3,4,32,38]},a,b)
 ck(packed==[b,Vector4.ZERO],"two-component Custom1 completes UV0 register")
 packed=Particles.shader_custom_streams({"m_UseCustomVertexStreams":false,"m_VertexStreams":[0,3,4,34]},a,b)
 ck(packed==[a,b],"unverified implicit layouts unchanged")
 var player=Player.new();root.add_child(player)
 player.spawn("res://data/effects/hoshino/visual-templates.json#FX_Hoshino_Original_Ex01_Motion_Mesh_Muzzle",942,0.0,identity,1.0)
 player.update_time(0.26)
 var checked:=0
 for effect in player._effects:
  for layer in effect.layers:
   if not str(layer.path).ends_with("/shock_wave"):continue
   for item in layer.particles:
    if not item.node.visible:continue
    var source_state:Dictionary=Particles.state(layer.params,item.sample,0.26)
    var shader_tex1:Vector4=item.material.get_shader_parameter("custom0")
    ck(is_equal_approx(shader_tex1.x,source_state.custom0.z),"source no-UV2 packing: Hoshino Step threshold must use custom0.z instead of zero custom0.x")
    ck(shader_tex1.x>0.0,"native shock wave is eroding rather than stuck at zero")
    checked+=1
 ck(checked>0,"actual native shock-wave particle inspected")
 player.reset(1);player.free()
 print("VERTEX_PACKING ",checks," checks; ",failures," failures")
 quit(1 if failures else 0)
