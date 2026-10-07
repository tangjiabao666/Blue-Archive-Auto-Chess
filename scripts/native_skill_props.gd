extends Node3D
## Original animated EX props, driven only by the battle clock after UnitView poses.
## Owns no combat state. Does not replay any of the outer EX particle layers.
const PoseHistory=preload("res://scripts/sampled_pose_history.gd")
const Source=preload("res://vfx/native_source.gd")
const EffectPlayer=preload("res://vfx/native_effect_player.gd")
const NativeMaterials=preload("res://scripts/native_material_adapter.gd")
const ASSET_DIR="res://assets/skill_props/shiroko_drone/"
const MODEL=ASSET_DIR+"shiroko_drone.glb"
const MUZZLE="res://data/effects/shiroko/visual-templates.json#FX_Shiroko_Original_Ex01_Motion_Drone_Muzzle"
const SOURCE_PROP_KEY="CAB-e0537c9ce08dd670888e863e56d6dc4d/-5412878399146000981"
const TICK_SECONDS=0.05
# Cx * Cz, only used when feeding the X-reflected prop bone into Z-reflected particles.
const PARTICLE_BRIDGE=Basis(Vector3(-1,0,0),Vector3(0,1,0),Vector3(0,0,-1))
# Source Ex_Root Transform CAB-643731497c327a692f823325e350e877/-7629969987914723426 is identity.
# Godot may prune this unanimated unskinned node; its exact model-relative transform is identity.
var generation:int=-1
var max_queued_events:int=2048
var max_history_samples:int=768
var _profiles:Dictionary={}
var _views:Dictionary={}
var _characters:Dictionary={}
var _history:Dictionary={}
# Roster identities only; Ex_Root global transforms are always sampled live.
var _anchor_bindings:Dictionary={}
var _active:Dictionary={}
var _pending:Array=[]
var _event_sequence:int=0
var _seen:Dictionary={}
var _dead:Dictionary={}
var _issues:Array=[]
var _issue_keys:Dictionary={}
var _stats:Dictionary={}
var _metadata:Dictionary={}
var _materials:Array=[]
var _prop_materials:Dictionary={}
var _particles:Node3D
var _reduce_smoke:bool=false
var _packed:PackedScene
var _now:float=0.0

func _init()->void:set_process(false);set_physics_process(false)

func configure(profiles:Dictionary)->void:
 _profiles=profiles.duplicate(true)
 _anchor_bindings.clear()
 _metadata=Source.read_json(ASSET_DIR+"runtime-metadata.json")
 _prop_materials.clear()
 _materials=Source.read_json(ASSET_DIR+"material-bindings.json").get("materials",[])
 _packed=load(MODEL) as PackedScene
 _ensure_particles()

func begin_roster(views:Dictionary,units:Array,new_generation:int)->void:
 reset(new_generation)
 _views=views.duplicate()
 for unit in units:_characters[int(unit.id)]=str(unit.get("character_id",""))
 if "shiroko" in _characters.values():
  _warm_prop_materials()
  var nested:Dictionary=_metadata.nested_timeline.tracks[1].events[0]
  _particles.warmup_prefab(MUZZLE,int(nested.parameters.particleRandomSeed),float(nested.durationSeconds))
 _capture_history(0.0)

func consume(event:Dictionary,units:Array)->void:
 if int(event.get("generation",-1))!=generation:_stats.stale_events+=1;return
 for unit in units:_characters[int(unit.id)]=str(unit.get("character_id",_characters.get(int(unit.id),"")))
 var actor:int=int(event.get("actor_id",-1))
 if str(_characters.get(actor,""))!="shiroko":return
 var kind:String=str(event.get("type",""))
 if kind!="death" and not (kind=="skill" and str(event.get("ability",""))=="ex"):return
 if event.get("component","")=="echo":return
 var key:String=str(event.get("event_id",""))
 if key.is_empty():key="%s:%s:%s"%[actor,event.get("tick",0),kind]
 if _seen.has(key):return
 _seen[key]=float(event.get("tick",0))*TICK_SECONDS
 var queued:Dictionary=event.duplicate(true)
 queued["_sequence"]=_event_sequence;_event_sequence+=1
 _pending.append(queued)
 while _pending.size()>maxi(0,max_queued_events):_pending.pop_front();_stats.queue_drops+=1

func update_time(time:float)->void:
 if not is_finite(time):return
 if time<_now-0.000001:_issue("rewind_requires_reset","Reset and replay events to recreate completed props")
 _now=time
 _capture_history(time)
 # Array.sort_custom is unstable: preserve received order within one core tick.
 _pending.sort_custom(func(a,b):return int(a._sequence)<int(b._sequence) if int(a.get("tick",0))==int(b.get("tick",0)) else int(a.get("tick",0))<int(b.get("tick",0)))
 var later:Array=[]
 for event in _pending:
  var at:float=float(event.get("tick",0))*TICK_SECONDS
  if at>time+0.0000001:later.append(event);continue
  var actor:int=int(event.get("actor_id",-1))
  if event.type=="death":_dead[actor]=true;_release_actor(actor);continue
  if _dead.has(actor):continue
  _start_drone(actor,at)
 _pending=later
 for actor in _active.keys():
  var instance:Dictionary=_active[actor]
  if time>=float(instance.end) or not is_instance_valid(_views.get(actor)):
   _release_actor(actor);continue
  var anchor=_sample_anchor(actor,time)
  if anchor==null:instance.container.visible=false;continue
  instance.container.visible=time>=float(instance.start)
  instance.container.global_transform=anchor
  _seek_pose(instance,clampf(time-float(instance.start),0.0,6.0))
 _particles.update_time(time)
 for key in _seen.keys():
  if time-float(_seen[key])>12.0:_seen.erase(key)

func reset(new_generation:int)->void:
 _ensure_particles()
 for actor in _active.keys():_release_actor(actor)
 _particles.reset(new_generation);generation=new_generation
 _views.clear();_characters.clear();_anchor_bindings.clear();_history.clear();_pending.clear();_event_sequence=0;_seen.clear();_dead.clear();_issues.clear();_issue_keys.clear();_now=0.0
 _stats={"spawned":0,"stale_events":0,"queue_drops":0,"released":0}

func _ensure_particles()->void:
 if is_instance_valid(_particles):return
 _particles=EffectPlayer.new();_particles.name="NativeDroneMuzzle";add_child(_particles);_particles.set_reduce_smoke(_reduce_smoke)

func _warm_prop_materials()->void:
 if _packed==null or not _prop_materials.is_empty():return
 var sample:Node3D=_packed.instantiate()
 NativeMaterials.apply(sample,_materials)
 for mesh in sample.find_children("*","MeshInstance3D",true,false):
  var material=mesh.get_active_material(0)
  if str(mesh.name)=="Siroko_Dron_Wing" and material is BaseMaterial3D:
   # Native Unlit/Transparent is alpha blended without depth writes; Godot's
   # default glTF BLEND import instead enables alpha depth prepass.
   material=material.duplicate()
   material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
   material.depth_draw_mode=BaseMaterial3D.DEPTH_DRAW_DISABLED
  _prop_materials[str(mesh.name)]=material
 sample.free()

func _start_drone(actor:int,at:float)->void:
 if _packed==null or not _views.has(actor) or not is_instance_valid(_views[actor]):_issue("missing_actor_or_model",str(actor));return
 # Late events whose entire source window elapsed must not leave a transient prop.
 if _now>=at+6.0:return
 var anchor=_sample_anchor(actor,_now)
 if anchor==null:_issue("missing_source_ex_root",str(actor));return
 _release_actor(actor)
 var container:Node3D=_packed.instantiate();container.name="ShirokoDrone_"+str(actor);add_child(container)
 container.global_transform=anchor
 for mesh in container.find_children("*","MeshInstance3D",true,false):
  if _prop_materials.has(str(mesh.name)):mesh.set_surface_override_material(0,_prop_materials[str(mesh.name)])
 var players:Array=container.find_children("*","AnimationPlayer",true,false)
 var skeletons:Array=container.find_children("*","Skeleton3D",true,false)
 var roots:Array=container.find_children("FX_Shiroko_Original_Drone_Mesh","Node3D",true,false)
 if players.size()!=1 or skeletons.size()!=1 or roots.size()!=1:
  container.free();_issue("invalid_source_hierarchy",str(actor));return
 var player:AnimationPlayer=players[0]
 var skeleton:Skeleton3D=skeletons[0]
 var prop_root:Node3D=roots[0]
 var bone:int=skeleton.find_bone("bone_dron_com")
 if bone<0:container.free();_issue("missing_native_muzzle_bone",str(actor));return
 player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 # AnimationMixer decomposes the two authored zero-scale wingB rest bases
 # while building its seek cache (Godot 4.6.3 animation_mixer.cpp:738-741).
 # Their scales become nonzero at 0.584375 s: neither bone nor track can be
 # discarded. Read the intact imported component tracks without that cache.
 player.active=false
 var animation:Animation=player.get_animation("Recorded")
 var pose_tracks:Array=_bind_pose_tracks(animation,player,skeleton,prop_root)
 if pose_tracks.is_empty():container.free();return
 var translation_track:int=-1;var rotation_track:int=-1
 for track in animation.get_track_count():
  if str(animation.track_get_path(track))!="FX_Shiroko_Original_Drone_Mesh":continue
  if animation.track_get_type(track)==Animation.TYPE_POSITION_3D:translation_track=track
  if animation.track_get_type(track)==Animation.TYPE_ROTATION_3D:rotation_track=track
 if translation_track<0 or rotation_track<0:
  container.free();_issue("missing_native_root_tracks",str(actor));return
 var nested:Dictionary=_metadata.nested_timeline.tracks[1].events[0]
 var muzzle_start:float=at+float(nested.startSeconds)
 var instance:Dictionary={"actor":actor,"start":at,"end":at+6.0,"container":container,"player":player,"root":prop_root,"skeleton":skeleton,"bone":bone,"animation":animation,"pose_tracks":pose_tracks,"translation_track":translation_track,"rotation_track":rotation_track,"muzzle_handle":-1,"muzzle_end":muzzle_start+float(nested.durationSeconds),"skeleton_local":prop_root.global_transform.affine_inverse()*skeleton.global_transform,"bone_local":skeleton.get_bone_global_pose(bone)}
 _active[actor]=instance
 _particles.world_gravity_scale=float(_profiles.get("shiroko",{}).get("model_scale",1.3))
 instance.muzzle_handle=_particles.spawn(MUZZLE,int(nested.parameters.particleRandomSeed),muzzle_start,_resolve_muzzle.bind(actor),float(nested.durationSeconds))
 _stats.spawned+=1

func _bind_pose_tracks(animation:Animation,player:AnimationPlayer,skeleton:Skeleton3D,prop_root:Node3D)->Array:
 # This adapter deliberately supports only the verified Recorded clip layout.
 # New/changed tracks fail closed with one diagnostic instead of being skipped
 # or sent back through the singular-rest AnimationMixer path.
 var expected:Dictionary={}
 for name in ["bone_dron_armL_wingA","bone_dron_armL_wingB","bone_dron_armR_wingA","bone_dron_armR_wingB"]:
  expected[name+":"+str(Animation.TYPE_ROTATION_3D)]=true
  expected[name+":"+str(Animation.TYPE_SCALE_3D)]=true
 expected[":"+str(Animation.TYPE_POSITION_3D)]=true
 expected[":"+str(Animation.TYPE_ROTATION_3D)]=true
 var result:Array=[]
 var animation_root:Node=player.get_node(player.root_node)
 for track in animation.get_track_count():
  var path:NodePath=animation.track_get_path(track)
  var type:int=animation.track_get_type(track)
  var target:Node=animation_root.get_node_or_null(NodePath(path.get_concatenated_names()))
  var bone:int=-1
  var key:String=":"+str(type)
  if target==skeleton and path.get_subname_count()==1:
   var bone_name:String=path.get_subname(0)
   bone=skeleton.find_bone(bone_name);key=bone_name+key
  elif target!=prop_root or path.get_subname_count()!=0:key="unsupported"
  if not expected.has(key) or not animation.track_is_enabled(track) or animation.track_get_key_count(track)==0 or (target==skeleton and bone<0):
   _issue("unsupported_native_animation_track",str(path)+":"+str(type));return []
  expected.erase(key)
  result.append({"track":track,"type":type,"bone":bone})
 if not expected.is_empty():_issue("missing_native_animation_tracks",str(expected.keys()));return []
 return result

func _seek_pose(instance:Dictionary,at:float)->void:
 # Absolute component setters preserve zero scales, all four rotor animations,
 # and the exact imported interpolation. No source resource/rest is modified.
 var animation:Animation=instance.animation
 var skeleton:Skeleton3D=instance.skeleton
 var prop_root:Node3D=instance.root
 for binding in instance.pose_tracks:
  var track:int=int(binding.track)
  var bone:int=int(binding.bone)
  match int(binding.type):
   Animation.TYPE_POSITION_3D:prop_root.position=animation.position_track_interpolate(track,at)
   Animation.TYPE_ROTATION_3D:
    var rotation:Quaternion=animation.rotation_track_interpolate(track,at)
    if bone<0:prop_root.quaternion=rotation
    else:skeleton.set_bone_pose_rotation(bone,rotation)
   Animation.TYPE_SCALE_3D:skeleton.set_bone_pose_scale(bone,animation.scale_track_interpolate(track,at))

func _release_actor(actor:int)->void:
 if not _active.has(actor):return
 var instance:Dictionary=_active[actor]
 _particles.release(int(instance.muzzle_handle))
 if is_instance_valid(instance.container):instance.container.free()
 _active.erase(actor)
 if _stats.has("released"):_stats.released+=1

func _live_anchor(actor:int):
 var view=_views.get(actor)
 if not is_instance_valid(view):return null
 var model=view.get("_model")
 if not model is Node3D or not is_instance_valid(model):return null
 var binding:Dictionary=_anchor_bindings.get(actor,{})
 if binding.get("model")==model and is_instance_valid(binding.get("anchor")):
  return binding.anchor.global_transform
 var matches:Array=model.find_children("Ex_Root","Node3D",true,false)
 if matches.size()>1:
  _anchor_bindings.erase(actor);_issue("ambiguous_ex_root",str(actor));return null
 var anchor:Node3D=matches[0] if matches.size()==1 else model
 _anchor_bindings[actor]={"model":model,"anchor":anchor}
 if matches.is_empty():_issue("verified_identity_ex_root",str(actor)+": original unanimated identity Ex_Root pruned by importer")
 return anchor.global_transform

func capture_event_pose(at:float,actor_ids:Array)->void:
 if actor_ids.is_empty() or not is_finite(at) or at<_now-0.0000001:return
 _capture_history(at,actor_ids)

func _capture_history(at:float,actor_ids:Array=[])->void:
 for actor in (_views.keys() if actor_ids.is_empty() else actor_ids):
  if str(_characters.get(actor,""))!="shiroko":continue
  var value=_live_anchor(actor)
  if value==null:continue
  if not _history.has(actor):_history[actor]=[]
  var samples:Array=_history[actor]
  PoseHistory.record(samples,{"time":at,"transform":value},12.0,max_history_samples)


func _sample_anchor(actor:int,at:float):
 var samples:Array=_history.get(actor,[])
 if samples.is_empty() or at<float(samples[0].time)-0.000001:return null
 for i in range(samples.size()-1,-1,-1):
  var a:Dictionary=samples[i]
  if at<float(a.time)-0.0000001:continue
  if i==samples.size()-1 or absf(at-float(a.time))<0.0000001:return a.transform
  var b:Dictionary=samples[i+1]
  return (a.transform as Transform3D).interpolate_with(b.transform,clampf((at-float(a.time))/maxf(0.000001,float(b.time)-float(a.time)),0,1))
 return null

func _resolve_muzzle(_binding:Dictionary,_event:Dictionary,at:float,actor:int):
 if not _active.has(actor):return null
 var instance:Dictionary=_active[actor]
 var anchor=_sample_anchor(actor,at)
 if anchor==null:return null
 var local_time:float=clampf(at-float(instance.start),0.0,6.0)
 var animation:Animation=instance.animation
 # Only prop root and four rotor bones animate. bone_dron_com itself is static.
 # Evaluate the exact imported root tracks for historical world-space particle birth.
 var position:Vector3=animation.position_track_interpolate(int(instance.translation_track),local_time)
 var rotation:Quaternion=animation.rotation_track_interpolate(int(instance.rotation_track),local_time)
 return (anchor as Transform3D)*Transform3D(Basis(rotation),position)*(instance.skeleton_local as Transform3D)*(instance.bone_local as Transform3D)*Transform3D(PARTICLE_BRIDGE,Vector3.ZERO)

static func owns_source_asset(asset:Dictionary)->bool:
 return str(asset.get("cab",""))+"/"+str(asset.get("pathId",""))==SOURCE_PROP_KEY

func diagnostics()->Dictionary:
 var result:Dictionary=_stats.duplicate()
 result.merge({"generation":generation,"time":_now,"active_props":_active.size(),"cached_prop_materials":_prop_materials.size(),"queued_events":_pending.size(),"issues":_issues.duplicate(true),"native_muzzle":_particles.diagnostics() if is_instance_valid(_particles) else {},"changes_combat_state":false})
 return result

func snapshot()->Dictionary:
 var result:Dictionary={}
 for actor in _active:
  var instance:Dictionary=_active[actor];var p:Vector3=instance.root.position
  var meshes:Array=instance.container.find_children("*","MeshInstance3D",true,false)
  var body_shader:String="";var rotor_transparency:int=-1
  for mesh in meshes:
   var material=mesh.get_active_material(0)
   if str(mesh.name)=="Siroko_Dron" and material is ShaderMaterial:body_shader=material.shader.resource_path
   if str(mesh.name)=="Siroko_Dron_Wing" and material is BaseMaterial3D:rotor_transparency=material.transparency
  result[actor]={"native_time":_now-float(instance.start),"local_position":[p.x,p.y,p.z],"world_transform":instance.container.global_transform,"mesh_count":meshes.size(),"body_shader":body_shader,"rotor_transparency":rotor_transparency}
 return result

func _issue(code:String,context:String)->void:
 var key:String=code+":"+context
 if not _issue_keys.has(key):_issue_keys[key]=true;_issues.append({"code":code,"context":context})

func set_reduce_smoke(enabled:bool)->void:
 _reduce_smoke=enabled;_ensure_particles();_particles.set_reduce_smoke(enabled)
