extends SceneTree
## Differential value/byte parity against b316c4e update scheduling/uniform writes.
## Both paths use current renderer fidelity rules, including deterministic mesh flips.
const Player=preload("res://vfx/native_effect_player.gd")
const Source=preload("res://vfx/native_source.gd")
const EVENTS="res://data/effects/battle-events-compact.json"
var failures:=0
var comparisons:=0
var anchor_missing:=false
var anchor_shift:=0.0
class ReferencePlayer extends Player:
 func update_time(global_time: float)->void:
  _now=global_time
  for effect in _effects:
   var active: bool=effect.generation==generation and global_time>=effect.start and global_time<effect.end
   effect.node.visible=active
   if not active:continue
   var anchor=_resolve(effect,global_time)
   if anchor==null:
    effect.node.visible=false;_issue("missing_anchor",str(effect.prefab)+":"+str(effect.binding.get("hierarchy","runtime target")));continue
   var local_time: float=float(effect.clip_in)+(global_time-float(effect.start))*float(effect.speed)
   for layer in effect.layers:
    for item in layer.particles:
     var state: Dictionary=Particles.state(layer.params,item.sample,local_time)
     item.node.visible=state.visible
     if not state.visible:continue
     var transform_anchor: Transform3D=anchor
     if int(layer.params.get("moveWithTransform",0))==1:
      var birth_global: float=float(effect.start)+(float(item.sample.birth)-float(effect.clip_in))/maxf(0.000001,float(effect.speed))
      var birth_anchor=_resolve(effect,birth_global)
      if birth_anchor==null:item.node.visible=false;_issue("missing_historical_anchor",layer.path);continue
      transform_anchor=birth_anchor
     var rotation: Vector3=state.rotation
     var basis: Basis=Basis.from_euler(rotation,EULER_ORDER_YXZ)
     if layer.mode==2:basis=Basis(Vector3.RIGHT,-PI/2.0)*basis
     var size: Vector3=state.size
     if layer.mode==1:
      size.y*=maxf(1.0,float(layer.render.get("m_LengthScale",2.0)))
     if layer.mesh_flip!=Vector3.ONE:size*=layer.mesh_flip
     var local: Transform3D=Transform3D(basis.scaled_local(size),state.position)
     item.node.global_transform=transform_anchor*layer.base_transform*local
     item.node.global_position+=state.world_offset*world_gravity_scale
     var material: ShaderMaterial=item.material
     material.set_shader_parameter("particle_color",state.color)
     var packed_custom: Array[Vector4]=Particles.shader_custom_streams(layer.render,state.custom0,state.custom1)
     material.set_shader_parameter("custom0",packed_custom[0]);material.set_shader_parameter("custom1",packed_custom[1])
     material.set_shader_parameter("uv_sheet",state.uv_sheet)
     # Source Unity _Time is scene time, not per-particle age. Game clock only.
     material.set_shader_parameter("effect_time",global_time)
     material.set_shader_parameter("roll",rotation.z if layer.billboard else 0.0)
func anchor(_binding:Dictionary,_event:Dictionary,at:float):
 if anchor_missing:return null
 return Transform3D(Basis(Vector3.UP,at*0.13),Vector3(at*0.2+anchor_shift,sin(at)*0.1,0.0))
func _initialize()->void:call_deferred("run")
func compare(current,reference,at:float,label:String)->void:
 current.update_time(at);reference.update_time(at)
 comparisons+=1
 if var_to_bytes(current.snapshot())!=var_to_bytes(reference.snapshot()):
  failures+=1;printerr("FAIL: exact snapshot ",label," time=",at)
 for index in range(current._effects.size()):
  var effect:Dictionary=current._effects[index];var expected:Dictionary=reference._effects[index]
  for layer_index in range(effect.layers.size()):
   var layer:Dictionary=effect.layers[layer_index];var original:Dictionary=expected.layers[layer_index]
   for particle_index in range(layer.particles.size()):
    var item:Dictionary=layer.particles[particle_index];var before:Dictionary=original.particles[particle_index]
    if item.node.visible!=before.node.visible:
     failures+=1;printerr("FAIL: hidden/visible particle state ",label)
    # Shader scene time/roll are not included in the public particle snapshot.
    if effect.node.visible and item.node.visible:
     for parameter in ["effect_time","roll"]:
      if item.material.get_shader_parameter(parameter)!=before.material.get_shader_parameter(parameter):
       failures+=1;printerr("FAIL: shader ",parameter," ",label)
func run()->void:
 var current=Player.new();var reference=ReferencePlayer.new();root.add_child(current);root.add_child(reference)
 var compact:Dictionary=Source.read_json(EVENTS)
 for character in compact.activeRoster:
  for kind in ["ex","basic"]:
   current.play_timeline(EVENTS,character,kind,0.0,anchor);reference.play_timeline(EVENTS,character,kind,0.0,anchor)
 var times:Array[float]=[-1.0,0.0,0.001,0.1,0.26,0.5,1.0,1.5,2.0,3.0,5.0,10.0,1.0,0.26,0.26,-0.01,0.0]
 for at in times:compare(current,reference,at,"all source EX/basic")
 anchor_shift=1.0;compare(current,reference,0.26,"paused clock with moved anchor")
 anchor_missing=true;compare(current,reference,0.3,"temporarily missing anchor")
 anchor_missing=false;compare(current,reference,0.3,"restored anchor at same time")
 current.reset(2);reference.reset(2)
 var path:String="res://data/effects/hoshino/visual-templates.json#FX_Hoshino_Original_Ex01_Motion_Mesh_Muzzle"
 for seed_value in [942,154,942]:
  var handle:int=current.spawn(path,seed_value,0.0,anchor,2.0)
  var ref_handle:int=reference.spawn(path,seed_value,0.0,anchor,2.0)
  for at in [0.0,0.26,0.27,1.9,0.25]:compare(current,reference,at,"pool reuse")
  current.release(handle);reference.release(ref_handle)
 # Exercise negative timeline speed and nonzero clipIn without a forward-only cursor.
 current.spawn(path,942,0.0,anchor,2.0);reference.spawn(path,942,0.0,anchor,2.0)
 for player in [current,reference]:
  player._effects[0].clip_in=0.7;player._effects[0].speed=-1.0
 for at in [0.0,0.1,0.25,0.5,0.7,1.0,0.1]:compare(current,reference,at,"reverse timeline speed")
 current.free();reference.free()
 print("PARTICLE_SEEK_PARITY ",comparisons," byte-identical snapshot comparisons; ",failures," failures")
 quit(1 if failures else 0)
