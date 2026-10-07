extends SceneTree
## Source renderer bias is orthographic sort depth, never color, position, or queue.
const Player=preload("res://vfx/native_effect_player.gd")
const Source=preload("res://vfx/native_source.gd")
const TEMPLATE="res://data/effects/haruna/visual-templates.json#FX_Public_Start"
var failures:=0
var checks:=0
func ck(ok:bool,message:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: "+message)
func anchor(_binding:Dictionary,_event:Dictionary,_at:float)->Transform3D:return Transform3D.IDENTITY
func _initialize()->void:call_deferred("run")
func check_bias(player,scale:float)->void:
 var found:Dictionary={}
 for effect in player._effects:
  for layer in effect.layers:
   var expected:float=-float(layer.render.get("m_SortingFudge",0.0))*scale
   for item in layer.particles:
    ck(is_equal_approx(item.node.sorting_offset,expected),layer.path+" source bias sign/units preserved")
    # Every material in this recovered prefab uses the same transparent queue,
    # including -1 materials inheriting the shader's Transparent default.
    ck(item.material.render_priority==0,layer.path+" material queue is unchanged")
    if item.node.visible:
     found[layer.path.get_file()]=item.node.sorting_offset
     if layer.path.ends_with("/glowblack"):
      ck(item.material.get_shader_parameter("particle_color")==Color(0,0,0,1),"source black color remains unchanged")
      ck(item.material.get_shader_parameter("uv_sheet")==Vector4(1,1,0,0),"source UVs remain unchanged")
      ck(item.node.global_position.is_equal_approx(Vector3(0,0.6,0)),"bias never moves geometry")
 ck(found.has("glowblack") and found.has("glow"),"source backdrop and foreground are simultaneously visible")
 if found.has("glowblack") and found.has("glow"):
  ck(float(found.glowblack)<float(found.glow),"black backdrop sorts behind the bright glow")
func run()->void:
 var player=Player.new();root.add_child(player)
 var has_scale:bool=false
 for property in player.get_property_list():
  if property.name=="world_sorting_scale":has_scale=true
 ck(has_scale,"player exposes source-to-world distance conversion")
 var handle:int=player.spawn(TEMPLATE,7390,0.0,anchor,1.0)
 player.update_time(0.15);check_bias(player,1.0)
 var snapshot:Dictionary=player.snapshot();player.update_time(0.15)
 ck(player.snapshot()==snapshot,"sorting leaves paused source state unchanged")
 player.release(handle)
 if has_scale:player.world_sorting_scale=0.25
 handle=player.spawn(TEMPLATE,7390,0.0,anchor,1.0)
 player.update_time(0.15);check_bias(player,0.25)
 ck(player.diagnostics().nodes_reused>0,"source bias is reapplied on pool reuse at a different world scale")
 # Missing bias must clear a nonzero value from a pooled node, not inherit it.
 for effect in player._effects:
  for layer in effect.layers:
   for item in layer.particles:item.node.sorting_offset=777.0
 player.release(handle)
 var data:Dictionary=Source.read_json(TEMPLATE.get_slice("#",0))
 var prefab:Dictionary=Source.find_prefab(data,"FX_Public_Start").duplicate(true)
 for node in prefab.nodes:
  for component in node.components:
   if component.type=="ParticleSystemRenderer":component.nativeParameters.erase("m_SortingFudge")
 var event:Dictionary={"start":0.0,"duration":1.0,"speed":1.0,"clipIn":0.0,"particleRandomSeed":7390,"bindings":[]}
 player._spawn_event(9001,data,prefab,"res://data/effects",event,0.0,anchor)
 player.update_time(0.15)
 for effect in player._effects:
  for layer in effect.layers:
   for item in layer.particles:ck(item.node.sorting_offset==0.0,"absent source bias resets pooled node to exact zero")
 player.free()
 print("PARTICLE_SORTING_BIAS ",checks," checks; ",failures," failures")
 quit(1 if failures else 0)
