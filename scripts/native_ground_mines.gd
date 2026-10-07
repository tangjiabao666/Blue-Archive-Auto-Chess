extends Node3D
## Generic native mine art, bound to authoritative autochess mine lifecycle events.
## Mutsuki ownership is unverified. This is a static armed-pose display adaptation.
## No combat mutation, autonomous processing, particle clock, or damage/timing logic.
const NativeMaterials=preload("res://scripts/native_material_adapter.gd")
const ASSET_DIR="res://assets/ground_mines/common_landmine/"
const MODEL=ASSET_DIR+"landmine.glb"
const TICK_SECONDS:float=0.05
const CLASSIFICATION:String="generic-native-art/autochess-adaptation"
var generation:int=-1
var _now:float=0.0
var _finished:bool=false
var _profiles:Dictionary={}
var _active:Dictionary={}
var _pending:Array=[]
var _seen:Dictionary={}
var _terminal:Dictionary={}
var _dead:Dictionary={}
var _issues:Array=[]
var _issue_keys:Dictionary={}
var _packed:PackedScene
var _metadata:Dictionary={}
var _materials:Dictionary={}
var _stats:Dictionary={"spawned":0,"released":0,"stale_events":0,"duplicate_events":0}

func _init()->void:
 set_process(false)
 set_physics_process(false)

func configure(profiles:Dictionary={})->void:
 _profiles=profiles.duplicate(true)
 _warm_assets()

func reset(new_generation:int)->void:
 for mine_id in _active.keys():_release(int(mine_id))
 generation=new_generation;_now=0.0;_finished=false
 _pending.clear();_seen.clear();_terminal.clear();_dead.clear();_issues.clear();_issue_keys.clear()
 _stats={"spawned":0,"released":0,"stale_events":0,"duplicate_events":0}
 _warm_assets()

func consume(event:Dictionary,units:Array)->void:
 if generation<0 or int(event.get("generation",-1))!=generation:
  _stats.stale_events+=1
  return
 if _finished:return
 var kind:String=str(event.get("type",""))
 if kind not in ["mine_placed","mine_triggered","mine_expired","mine_removed","death","finished"]:return
 var actor:int=int(event.get("actor_id",-1))
 var mine_id:int=int(event.get("mine_id",-1))
 if kind!="finished" and (actor<0 or (kind!="death" and mine_id<0)):_issue("invalid_event_identity",kind);return
 var key:String=str(event.get("event_id",""))
 if key.is_empty():key="%s:%s:%s:%s"%[kind,actor,mine_id,event.get("tick",0)]
 if _seen.has(key):_stats.duplicate_events+=1;return
 _seen[key]=true
 var value:Dictionary=event.duplicate(true)
 value["presentation_order"]=_seen.size()
 for unit in units:
  if int(unit.get("id",-1))!=actor:continue
  value["presentation_team"]=int(unit.get("team",0))
  value["presentation_character"]=str(unit.get("character_id",""))
  break
 _pending.append(value)

func update_time(battle_time:float)->void:
 if not is_finite(battle_time):return
 if battle_time<_now-0.0000001:
  _issue("rewind_requires_reset","Reset and replay the authoritative event stream before seeking backwards")
  return
 _now=battle_time
 _pending.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
  var a_tick:int=int(a.get("tick",0));var b_tick:int=int(b.get("tick",0))
  return int(a.presentation_order)<int(b.presentation_order) if a_tick==b_tick else a_tick<b_tick)
 var later:Array=[]
 for event in _pending:
  if float(event.get("tick",0))*TICK_SECONDS>_now+0.0000001:later.append(event);continue
  var kind:String=str(event.type)
  if _finished:continue
  if kind=="finished":
   _finished=true
   for mine_id in _active.keys():_terminal[mine_id]=true;_release(int(mine_id))
   continue
  var actor:int=int(event.actor_id)
  if kind=="death":
   _dead[actor]=true;_release_actor(actor)
   continue
  var mine_id:int=int(event.mine_id)
  if kind=="mine_placed":
   if not _dead.has(actor) and not _terminal.has(mine_id) and not _active.has(mine_id):_place(event)
  else:
   _terminal[mine_id]=true;_release(mine_id)
   if kind=="mine_removed" and str(event.get("reason",""))=="source_dead":
    _dead[actor]=true;_release_actor(actor)
 _pending=[] if _finished else later
 for mine_id in _active.keys():
  if _now+0.0000001>=float(_active[mine_id].expires_tick)*TICK_SECONDS:
   _terminal[mine_id]=true;_release(int(mine_id))

func _warm_assets()->void:
 if _packed!=null and not _materials.is_empty():return
 _metadata=_read_json(ASSET_DIR+"runtime-metadata.json")
 if not ResourceLoader.exists(MODEL):_issue("missing_native_model",MODEL);return
 _packed=load(MODEL) as PackedScene
 if _packed==null:_issue("invalid_native_model",MODEL);return
 var sample:Node3D=_packed.instantiate()
 NativeMaterials.apply(sample,_read_json(ASSET_DIR+"material-bindings.json").get("materials",[]))
 for mesh in sample.find_children("*","MeshInstance3D",true,false):
  if mesh.mesh==null:continue
  for surface in mesh.mesh.get_surface_count():
   var material:Material=mesh.get_active_material(surface)
   if material is ShaderMaterial and material.shader.resource_path=="res://shaders/native_weapon.gdshader":
    _materials["%s:%s"%[mesh.name,surface]]=material
 sample.free()
 if _materials.is_empty():_issue("unmapped_native_material",MODEL)

func _place(event:Dictionary)->void:
 var mine_id:int=int(event.mine_id)
 var expires_tick:int=int(event.get("expires_tick",-1))
 if expires_tick<=int(event.get("tick",0)) or _now+0.0000001>=float(expires_tick)*TICK_SECONDS:
  _terminal[mine_id]=true
  return
 var cell=event.get("cell")
 if not cell is Vector2 or not is_finite(cell.x) or not is_finite(cell.y):_issue("invalid_mine_cell",str(mine_id));return
 if _packed==null or _materials.is_empty():_issue("native_mine_unavailable",str(mine_id));return
 var character:String=str(event.get("presentation_character","mutsuki"))
 var world_scale:float=float(_profiles.get(character,{}).get("model_scale",_metadata.get("world_scale_adaptation",1.3)))
 if not is_finite(world_scale) or world_scale<=0.0:_issue("invalid_world_scale",character);return
 var holder:=Node3D.new();holder.name="NativeGroundMine_%s"%mine_id
 holder.set_meta("classification",CLASSIFICATION)
 holder.set_meta("mutsuki_runtime_association_verified",false)
 var model:Node3D=_packed.instantiate();holder.add_child(model)
 # GLB already includes the source emitter's -90° X node rotation. A single
 # +90° armed-pose adapter follows native_particles.gd's converted initial
 # X rotation convention and exposes mesh-space Y-up. No particle emission,
 # renderer pivot or source timeline is replayed; see the asset metadata.
 var pose:Dictionary=_metadata.get("static_pose_adaptation",{})
 model.rotation.x=float(pose.get("counter_emitter_x_radians",PI/2.0))
 model.scale=Vector3.ONE*float(_metadata.get("source_initial_size",2.2))*world_scale
 var meshes:Array=model.find_children("*","MeshInstance3D",true,false)
 var mapped_surfaces:int=0
 for mesh in meshes:
  if mesh.mesh==null:continue
  for surface in mesh.mesh.get_surface_count():
   var key:String="%s:%s"%[mesh.name,surface]
   if _materials.has(key):mesh.set_surface_override_material(surface,_materials[key]);mapped_surfaces+=1
 if mapped_surfaces==0:holder.free();_issue("unmapped_native_instance",str(mine_id));return
 var bounds:AABB=_local_mesh_bounds(holder,meshes)
 var center:Vector3=bounds.get_center()
 model.position=Vector3(-center.x,-bounds.position.y+float(pose.get("ground_clearance",0.005)),-center.z)
 holder.position=Vector3(cell.x,0.0,cell.y)
 add_child(holder)
 _active[mine_id]={"actor_id":int(event.actor_id),"cell":cell,"team":int(event.get("presentation_team",0)),"expires_tick":expires_tick,"container":holder,"model":model,"native_mesh_count":meshes.size(),"mapped_surfaces":mapped_surfaces}
 _stats.spawned+=1

func _local_mesh_bounds(holder:Node3D,meshes:Array)->AABB:
 var result:=AABB();var started:bool=false
 for mesh in meshes:
  if mesh.mesh==null:continue
  var local:Transform3D=mesh.transform
  var ancestor:Node=mesh.get_parent()
  while ancestor!=holder and ancestor is Node3D:
   local=(ancestor as Node3D).transform*local;ancestor=ancestor.get_parent()
  var value:AABB=local*mesh.get_aabb()
  if started:result=result.merge(value)
  else:result=value;started=true
 return result

func _release(mine_id:int)->void:
 if not _active.has(mine_id):return
 var holder:Node3D=_active[mine_id].container
 # Synchronous free also prevents same-frame resets leaving hidden geometry.
 if is_instance_valid(holder):holder.free()
 _active.erase(mine_id);_stats.released+=1

func _release_actor(actor:int)->void:
 for mine_id in _active.keys():
  if int(_active[mine_id].actor_id)==actor:
   _terminal[mine_id]=true;_release(int(mine_id))

func diagnostics()->Dictionary:
 var result:Dictionary=_stats.duplicate()
 result.merge({"generation":generation,"time":_now,"finished":_finished,"active_mines":_active.size(),"active_props":_active.size(),"queued_events":_pending.size(),"cached_materials":_materials.size(),"terminal_mines":_terminal.size(),"classification":CLASSIFICATION,"mutsuki_runtime_association_verified":false,"changes_combat_state":false,"issues":_issues.duplicate(true)})
 return result

func snapshot()->Dictionary:
 var result:Dictionary={}
 for mine_id in _active:
  var item:Dictionary=_active[mine_id]
  var holder:Node3D=item.container
  var bounds:AABB=holder.transform*_local_mesh_bounds(holder,holder.find_children("*","MeshInstance3D",true,false))
  result[mine_id]={"cell":item.cell,"actor_id":item.actor_id,"team":item.team,"expires_tick":item.expires_tick,"bounds":bounds,"native_mesh_count":item.native_mesh_count,"mapped_surfaces":item.mapped_surfaces,"world_transform":holder.global_transform,"classification":CLASSIFICATION}
 return result

func _read_json(path:String)->Dictionary:
 if not FileAccess.file_exists(path):_issue("missing_metadata",path);return {}
 var value=JSON.parse_string(FileAccess.get_file_as_string(path))
 if not value is Dictionary:_issue("invalid_metadata",path);return {}
 return value

func _issue(code:String,context:String)->void:
 var key:String=code+":"+context
 if _issue_keys.has(key):return
 _issue_keys[key]=true;_issues.append({"code":code,"context":context})
