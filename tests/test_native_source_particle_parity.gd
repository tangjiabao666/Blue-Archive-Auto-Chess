extends SceneTree
## Actual player comparison: frozen original JSON parser vs immutable canonical source.
const Source=preload("res://vfx/native_source.gd")
const Helpers=preload("res://tests/native_source_memory_helpers.gd")
const Player=preload("res://vfx/native_effect_player.gd")
const EVENTS="res://data/effects/battle-events-compact.json"
var failures:=0
var comparisons:=0
var mesh_checks:=0
var particles:=0
func ck(ok:bool,label:String)->void:
 if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize()->void:call_deferred("run")
func anchor(_binding:Dictionary,_event:Dictionary,at:float)->Transform3D:
 return Transform3D(Basis(Vector3.UP,at*0.13),Vector3(at*0.2,sin(at)*0.1,0.0))
func compare(current,reference,at:float,label:String)->void:
 current.update_time(at);reference.update_time(at);comparisons+=1
 ck(var_to_bytes(current.snapshot())==var_to_bytes(reference.snapshot()),"exact particle snapshot "+label+" at="+str(at))
 for i in current._effects.size():
  var effect:Dictionary=current._effects[i];var previous:Dictionary=reference._effects[i]
  ck(effect.layers.size()==previous.layers.size(),"same emitter layer count "+label)
  for j in effect.layers.size():
   var layer:Dictionary=effect.layers[j];var before:Dictionary=previous.layers[j]
   ck(layer.particles.size()==before.particles.size(),"same full particle schedule "+label)
   for k in layer.particles.size():
    var item:Dictionary=layer.particles[k];var other:Dictionary=before.particles[k]
    ck(var_to_bytes(item.sample)==var_to_bytes(other.sample),"exact seeded particle samples "+label)
    ck(item.node.visible==other.node.visible,"same particle visibility "+label)
    if effect.node.visible and item.node.visible:
     for parameter in ["effect_time","roll"]:ck(item.material.get_shader_parameter(parameter)==other.material.get_shader_parameter(parameter),"same shader clock/roll "+label)
func run()->void:
 var roster:Array=Source.read_json(EVENTS).activeRoster
 for character in roster:
  var path:String="res://data/effects/"+character+"/visual-templates.json"
  var original:Dictionary=Helpers.read_original(path)
  Source.json_cache[path]=original
  var reference=Player.new();root.add_child(reference)
  for kind in ["ex","basic"]:reference.play_timeline(EVENTS,character,kind,0.0,anchor)
  Source.json_cache.erase(path)
  # Reconstruct independently: the original player's live nodes keep old resources
  # alive, while the canonical reader rebuilds meshes/materials from cold caches.
  Source.mesh_cache.clear();Player._material_cache.clear()
  var current=Player.new();root.add_child(current)
  for kind in ["ex","basic"]:current.play_timeline(EVENTS,character,kind,0.0,anchor)
  ck(current._effects.size()==reference._effects.size(),"same effect count "+character)
  for i in current._effects.size():
   var effect:Dictionary=current._effects[i];var previous:Dictionary=reference._effects[i]
   for j in effect.layers.size():
    var layer:Dictionary=effect.layers[j];var before:Dictionary=previous.layers[j]
    particles+=layer.particles.size()
    if layer.particles.is_empty():continue
    var mesh:Mesh=layer.particles[0].node.mesh;var old_mesh:Mesh=before.particles[0].node.mesh
    ck(not is_same(mesh,old_mesh),"independent cold-cache mesh reconstruction "+character)
    ck(mesh.get_surface_count()==old_mesh.get_surface_count(),"same mesh surface count "+character)
    for surface in mesh.get_surface_count():
     ck(var_to_bytes(mesh.surface_get_arrays(surface))==var_to_bytes(old_mesh.surface_get_arrays(surface)),"byte-identical source mesh buffers "+character)
     mesh_checks+=1
  for at in [-0.01,0.0,0.001,0.1,0.26,0.5,1.0,1.5,2.0,3.0,5.0,10.0,1.0,0.26,0.26,-0.01,0.0]:compare(current,reference,at,character)
  current.free();reference.free();original={};Source.json_cache.erase(path)
  print("SOURCE_PARITY character=",character," complete")
 print("SOURCE_PARTICLE_PARITY roster=",roster.size()," comparisons=",comparisons," mesh_buffers=",mesh_checks," scheduled_particles=",particles," failures=",failures)
 quit(1 if failures else 0)
