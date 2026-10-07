extends SceneTree
## Subprocess fixture for test_native_drone_pose.py. The reference deliberately
## exercises the unmodified engine player; only that subprocess may emit its two
## known first-seek diagnostics. Production errors must never be suppressed.
const Props=preload("res://scripts/native_skill_props.gd")
var checks:=0
var failures:=0
class MockView extends Node3D:
 var _model:Node3D
 func _init()->void:
  _model=Node3D.new();_model.name="Shiroko_Original";add_child(_model)
  _model.scale=Vector3.ONE*1.3;_model.rotation=Vector3(0.1,0.7,-0.2)
  _model.position=Vector3(4,1,-2)
  var ex:=Node3D.new();ex.name="Ex_Root";_model.add_child(ex)
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func matrix(value:Transform3D)->Array:
 var result:Array=[]
 for column in [value.basis.x,value.basis.y,value.basis.z,value.origin]:
  result.append_array([column.x,column.y,column.z])
 return result
func snapshot(container:Node3D,skeleton:Skeleton3D,geometry:bool)->Dictionary:
 var bones:Dictionary={}
 for bone in skeleton.get_bone_count():bones[str(skeleton.get_bone_name(bone))]=matrix(skeleton.global_transform*skeleton.get_bone_global_pose(bone))
 var meshes:Dictionary={}
 for mesh in container.find_children("*","MeshInstance3D",true,false):
  var palette:Array=[]
  for bind in mesh.skin.get_bind_count():
   var bone:int=skeleton.find_bone(mesh.skin.get_bind_name(bind))
   if bone<0:bone=mesh.skin.get_bind_bone(bind)
   palette.append(skeleton.global_transform*skeleton.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(bind))
  var item:Dictionary={"transform":matrix(mesh.global_transform),"palette":[]}
  for transform in palette:item.palette.append(matrix(transform))
  if geometry:
   item.vertices=[]
   for surface in mesh.mesh.get_surface_count():
    var arrays:Array=mesh.mesh.surface_get_arrays(surface)
    var positions:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
    var indices:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
    var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
    var stride:int=indices.size()/positions.size()
    for vertex in positions.size():
     var position:=Vector3.ZERO
     for influence in stride:
      var index:int=vertex*stride+influence
      if weights[index]!=0:position+=(palette[indices[index]] as Transform3D)*positions[vertex]*weights[index]
     item.vertices.append_array([position.x,position.y,position.z])
  meshes[str(mesh.name)]=item
 var muzzle:int=skeleton.find_bone("bone_dron_com")
 return {"bones":bones,"meshes":meshes,"muzzle":matrix(skeleton.global_transform*skeleton.get_bone_global_pose(muzzle)*Transform3D(Props.PARTICLE_BRIDGE,Vector3.ZERO))}
func _initialize()->void:call_deferred("run")
func run()->void:
 var args:=OS.get_cmdline_user_args()
 var reference:bool="--reference" in args
 var output:String=args[args.find("--output")+1]
 var view:=MockView.new();root.add_child(view)
 var props:=Props.new();root.add_child(props)
 var units=[{"id":1,"character_id":"shiroko"}]
 var container:Node3D
 var player:AnimationPlayer
 var skeleton:Skeleton3D
 if reference:
  container=load(Props.MODEL).instantiate();root.add_child(container)
  container.global_transform=view._model.global_transform
  player=container.find_children("*","AnimationPlayer",true,false)[0]
  skeleton=container.find_children("*","Skeleton3D",true,false)[0]
  player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
  player.play("Recorded")
 else:
  props.configure({"shiroko":{"model_scale":1.3}});props.begin_roster({1:view},units,9)
  props.consume({"type":"skill","ability":"ex","actor_id":1,"tick":0,"generation":9,"event_id":"first"},units)
  props.update_time(0.0)
  container=props._active[1].container;player=props._active[1].player;skeleton=props._active[1].skeleton
 var animation:Animation=player.get_animation("Recorded")
 ck(animation.get_track_count()==10,"all ten imported tracks retained")
 var rests:Array=[]
 for bone in skeleton.get_bone_count():rests.append(matrix(skeleton.get_bone_rest(bone)))
 var boundary_times:Array=[0.0,0.33385416865348816,0.5833333333333333,0.5838541666666667,0.5843750238418579,0.59,0.60,0.6666666666666666,1.0,2.566666666666667,2.63281238,3.0,4.2338540554,4.566666666666666,5.99999]
 # Probe every imported scale-transition key, both neighboring keys, and
 # interval interiors. wingA and wingB swap visibility around 0.5833-0.6000 s.
 for track in animation.get_track_count():
  if animation.track_get_type(track)!=Animation.TYPE_SCALE_3D:continue
  for key in animation.track_get_key_count(track):
   var value:Vector3=animation.track_get_key_value(track,key)
   if value.x<=0.0 or value.x>=1.0:continue
   for adjacent in range(maxi(0,key-1),mini(animation.track_get_key_count(track),key+2)):
    var at:float=animation.track_get_key_time(track,adjacent)
    if at not in boundary_times:boundary_times.append(at)
    if adjacent>0:
     var midpoint:float=(at+animation.track_get_key_time(track,adjacent-1))*0.5
     if midpoint not in boundary_times:boundary_times.append(midpoint)
 var times:Array=boundary_times.duplicate()
 for frame in 360:
  var at:float=frame/60.0
  if at not in times:times.append(at)
 times.sort()
 var samples:Array=[]
 var paused:Dictionary={}
 for at in times:
  if reference:player.seek(float(at),true)
  else:props.update_time(float(at))
  var pose:Dictionary=snapshot(container,skeleton,at in boundary_times)
  if not reference:
   var live_muzzle:Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("bone_dron_com"))*Transform3D(Props.PARTICLE_BRIDGE,Vector3.ZERO)
   ck((props._resolve_muzzle({}, {},float(at),1) as Transform3D).is_equal_approx(live_muzzle),"historical muzzle resolver equals live bone at "+str(at))
   if is_equal_approx(float(at),3.0):
    paused=pose.duplicate(true)
    var particle_before:Dictionary=props._particles.snapshot()
    props.update_time(float(at))
    ck(snapshot(container,skeleton,true)==pose,"same-clock seek preserves visible geometry")
    ck(props._particles.snapshot()==particle_before,"pause preserves nested muzzle particles")
  samples.append({"time":at,"pose":pose})
 # Local rest transforms and mesh resources are never rewritten by the adapter.
 for bone in skeleton.get_bone_count():ck(matrix(skeleton.get_bone_rest(bone))==rests[bone],"source rest unchanged "+str(bone))
 if not reference:
  props.update_time(6.0)
  ck(props._active.is_empty() and props._particles.get("_effects").is_empty(),"source window frees drone and muzzle")
  props.begin_roster({1:view},units,10)
  props.consume({"type":"skill","ability":"ex","actor_id":1,"tick":0,"generation":10,"event_id":"replay"},units)
  props.update_time(3.0)
  var replay:Dictionary=props._active[1]
  ck(snapshot(replay.container,replay.skeleton,true)==paused,"reset replay recreates visible pose exactly")
  props.consume({"type":"death","actor_id":1,"tick":61,"generation":10,"event_id":"death"},units)
  props.update_time(3.05)
  ck(props._active.is_empty() and props._particles.get("_effects").is_empty(),"death releases drone and muzzle")
  props.consume({"type":"skill","ability":"ex","actor_id":1,"tick":62,"generation":10,"event_id":"after-death"},units)
  props.update_time(3.1);ck(props._active.is_empty(),"dead actor cannot restart prop")
  props.begin_roster({1:view},units,11)
  props.consume({"type":"skill","ability":"ex","actor_id":1,"tick":0,"generation":11,"event_id":"reset-active"},units)
  props.update_time(0.0)
  props.consume({"type":"skill","ability":"ex","actor_id":1,"tick":200,"generation":11,"event_id":"reset-pending"},units)
  props.reset(12)
  ck(props._active.is_empty() and props._pending.is_empty() and props._particles.get("_effects").is_empty(),"reset clears active and pending drone work")
 else:container.free()
 var file:=FileAccess.open(output,FileAccess.WRITE)
 file.store_string(JSON.stringify({"samples":samples,"rests":rests}));file.close()
 props.free();view.free()
 print("DRONE_POSE_PROBE ","reference" if reference else "runtime"," ",samples.size()," samples; ",checks," checks; ",failures," failures")
 quit(1 if failures else 0)
