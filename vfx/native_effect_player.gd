extends Node3D
## Pure-gameclock, seekable visual adapter. Owns no gameplay or autonomous timers.
## Shader arithmetic/source art are preserved; diagnostics distinguish approximations.
const Curves=preload("native_curves.gd")
const Particles=preload("native_particles.gd")
const Source=preload("native_source.gd")
const Materials=preload("materials/native_materials.gd")
const StretchOrientation=preload("native_stretch_orientation.gd")
# Private-fixture opt-in. Production uses exact, explicit renderAdaptations metadata.
# Caller returns {transform:Transform3D, projection:"orthographic"|"perspective", time:at}.
# No implicit viewport/global camera and no previous-frame camera velocity.
var asuna_stretch_orientation_candidate:bool=false
var stretch_camera_at:Callable
static var _material_cache: Dictionary={}
var max_particles_per_emitter: int=2048
var max_pooled_nodes: int=512
var world_gravity_scale: float=1.0
# Source-world distance conversion for transparent renderer sorting only.
# Keep 1 in an unscaled native prefab viewer; combat supplies its model scale.
var world_sorting_scale: float=1.0
var _pool: Dictionary={}
var _pooled_count: int=0
var _nodes_created: int=0
var _nodes_reused: int=0
var _shader_parameter_writes: int=0
var _particle_state_evaluations: int=0
var generation: int=0
var _next_id: int=1
var _effects: Array=[]
var _issues: Array=[]
var _issue_keys: Dictionary={}
var _now: float=0.0
# Optional autochess readability adaptation; source curves and RGB stay intact.
var _reduce_smoke: bool=false
# Verified FX_MAT_Smoke_RGB_04. Shader-family names also contain fire layers,
# so intentionally do not attenuate all Explosion_Smoke-family materials.
const OCCLUDING_SMOKE_MATERIALS=["CAB-72cabf238b0d84de1615649a40b6b13f/-4702360996300803376"]

func _init()->void:set_process(false);set_physics_process(false)

func spawn(template_path: String,seed_value: int,start_time: float,anchor_resolver: Callable,duration: float=-1.0)->int:
 var file: String=template_path.get_slice("#",0)
 var selector: String=template_path.get_slice("#",1)
 var data: Dictionary=Source.read_json(file)
 var prefab: Dictionary=Source.find_prefab(data,selector)
 if prefab.is_empty():
  _issue("missing_prefab",selector if not selector.is_empty() else "Use visual-templates.json#PrefabName or #CAB/pathId")
  return -1
 var bound_to_cycle: bool=duration<0
 if duration<0:
  duration=_natural_duration(prefab,seed_value)
 var event: Dictionary={"kind":"effect","asset":prefab.get("source",{}),"label":prefab.get("name",""),"start":0.0,"duration":duration,"speed":1.0,"clipIn":0.0,"particleRandomSeed":seed_value,"bindings":[],"nativeDirectSingleCycle":bound_to_cycle}
 var id: int=_next_id;_next_id+=1
 _spawn_event(id,data,prefab,file.get_base_dir().get_base_dir(),event,start_time,anchor_resolver)
 return id

func play_timeline(compact_path: String,character: String,timeline_name_or_kind: String,start_time: float,anchor_resolver: Callable)->int:
 var compact: Dictionary=Source.read_json(compact_path)
 var character_data: Dictionary=compact.get("characters",{}).get(character,{})
 var timeline: Dictionary={}
 for candidate in character_data.get("timelines",[]):
  if candidate.get("name")==timeline_name_or_kind or candidate.get("kind")==timeline_name_or_kind:timeline=candidate;break
 if timeline.is_empty():_issue("missing_timeline",character+":"+timeline_name_or_kind);return -1
 var root_path: String=compact_path.get_base_dir()
 var data: Dictionary=Source.read_json(root_path.path_join(character).path_join("visual-templates.json"))
 var id: int=_next_id;_next_id+=1
 for event in timeline.get("events",[]):
  if event.get("muted",false) or event.get("kind")!="effect":continue
  var ref=event.get("asset")
  if not ref is Dictionary:_issue("missing_effect_asset",str(event.get("label","")));continue
  var prefab: Dictionary=Source.find_prefab(data,Source.reference_key(ref))
  if prefab.is_empty():_issue("missing_prefab",Source.reference_key(ref));continue
  _spawn_event(id,data,prefab,root_path,event,start_time,anchor_resolver)
 return id

func _spawn_event(id: int,data: Dictionary,prefab: Dictionary,resource_root: String,event: Dictionary,start_time: float,resolver: Callable)->void:
 var holder:=Node3D.new();holder.name="NativeVFX_"+str(id)+"_"+str(_effects.size());add_child(holder)
 var start: float=start_time+float(event.get("start",0.0))
 var speed: float=float(event.get("speed",1.0));var duration: float=float(event.get("duration",0.0));var clip_in: float=float(event.get("clipIn",0.0))
 var bindings: Array=event.get("bindings",[])
 var binding: Dictionary=bindings[0] if not bindings.is_empty() else {}
 var instance: Dictionary={"id":id,"generation":generation,"node":holder,"start":start,"end":start+duration,"speed":speed,"clip_in":clip_in,"event":event,"binding":binding,"resolver":resolver,"layers":[],"prefab":prefab.get("name","")}
 var transforms: Dictionary={};var active: Dictionary={}
 var subemitters: Dictionary={}
 var path_counts: Dictionary={}
 for source_node in prefab.get("nodes",[]):
  var source_path: String=source_node.get("hierarchy","")
  path_counts[source_path]=int(path_counts.get(source_path,0))+1
 for source_node in prefab.get("nodes",[]):
  for component in source_node.get("components",[]):
   if component.get("type")!="ParticleSystem":continue
   var sub_module:Dictionary=component.get("nativeParameters",{}).get("SubModule",{})
   if not sub_module.get("enabled",false):continue
   for entry in sub_module.get("subEmitters",[]):
    var ref: Dictionary=entry.get("emitter",{})
    if str(ref.get("m_PathID","0"))!="0":subemitters[str(ref.m_PathID)]=true
 for node_data in prefab.get("nodes",[]):
  var path: String=node_data.get("hierarchy","")
  var parent_path: String=path.get_base_dir()
  var ancestor: String=parent_path
  var ambiguous: bool=false
  while not ancestor.is_empty() and ancestor!=".":
   if int(path_counts.get(ancestor,0))>1:ambiguous=true;break
   var next_ancestor: String=ancestor.get_base_dir()
   if next_ancestor==ancestor:break
   ancestor=next_ancestor
  if ambiguous:_issue("ambiguous_source_parent_skipped",path);continue
  var local: Transform3D=Curves.unity_transform(node_data.get("transform",{}))
  var world: Transform3D=transforms.get(parent_path,Transform3D.IDENTITY)*local
  transforms[path]=world
  active[path]=bool(node_data.get("active",true)) and bool(active.get(parent_path,true))
  if not active[path]:continue
  var components: Dictionary={}
  for component in node_data.get("components",[]):components[component.type]=component
  if components.has("Animator") or components.has("Animation"):_issue("unsupported_prop_animation",path)
  if components.has("PlayableDirector"):_issue("unsupported_nested_director",path)
  if components.has("TrailRenderer"):_issue("unsupported_trail_renderer",path)
  if components.has("MeshRenderer") or components.has("SkinnedMeshRenderer"):_issue("unsupported_prop_mesh",path)
  if not components.has("ParticleSystem") or not components.has("ParticleSystemRenderer"):continue
  var p: Dictionary=components.ParticleSystem.nativeParameters
  if event.get("nativeDirectSingleCycle",false) and p.get("looping",false):
   p=p.duplicate();p["looping"]=false
  if subemitters.has(str(components.ParticleSystem.get("source",{}).get("pathId",""))):
   _issue("unsupported_subemitter_skipped",path);continue
  var renderer: Dictionary=components.ParticleSystemRenderer
  var render: Dictionary=renderer.get("nativeParameters",{})
  if not render.get("m_Enabled",true):continue
  if not p.get("EmissionModule",{}).get("enabled",false):continue
  var mode: int=int(render.get("m_RenderMode",0))
  if mode==5:continue # Source ParticleSystemRenderMode.None
  if not mode in [0,1,2,3,4]:_issue("unsupported_renderer",path+":"+str(mode));continue
  var mesh: Mesh=null
  if mode==4:
   var mesh_info=renderer.get("mesh")
   if not mesh_info is Dictionary or str(mesh_info.get("obj","")).is_empty():_issue("missing_or_builtin_mesh",path);continue
   mesh=Source.obj_mesh(resource_root.path_join(mesh_info.obj))
   if mesh==null:_issue("mesh_load_failed",path);continue
  else:
   mesh=Source.source_quad()
  var slots: Array=renderer.get("materials",[])
  var material_key=slots[0].get("materialKey") if not slots.is_empty() else null
  if material_key==null or not data.get("materials",{}).has(material_key):_issue("missing_material",path);continue
  var descriptor: Dictionary=data.materials[material_key]
  var billboard: bool=mode in [0,1,3] and int(render.get("m_RenderAlignment",0))==0
  var material_cache_key: String=resource_root+":"+str(material_key)+":"+str(billboard)
  if not _material_cache.has(material_cache_key):_material_cache[material_cache_key]=Materials.create(descriptor,resource_root,billboard)
  var base_material: ShaderMaterial=_material_cache[material_cache_key]
  if base_material==null:_issue("unsupported_material",path+":"+str(descriptor.get("shader")));continue
  var material_report: Dictionary=base_material.get_meta("native_diagnostics",{})
  for warning in material_report.get("warnings",[]):_issue("material_limit",str(descriptor.get("source",{}).get("name",""))+":"+warning)
  if not material_report.get("missing_textures",[]).is_empty():_issue("missing_textures",path);continue
  if mode==1:_issue("approximate_stretched_billboard",path)
  if mode==3:_issue("approximate_vertical_billboard",path)
  if not Curves.unity_vector(render.get("m_Pivot",{})).is_zero_approx():_issue("unsupported_renderer_pivot",path)
  var mesh_flip: Vector3=_deterministic_mesh_flip(render,mode,base_material)
  if mesh_flip==Vector3.ONE and not Curves.unity_vector(render.get("m_Flip",{})).is_zero_approx():_issue("unsupported_renderer_flip",path)
  if int(render.get("m_RenderAlignment",0)) not in [0,2]:_issue("approximate_renderer_alignment",path)
  if int(p.get("scalingMode",0))!=0:_issue("approximate_scaling_mode",path)
  if int(render.get("m_MaskInteraction",0))!=0:_issue("unsupported_stencil",path)
  if slots.size()>1 and slots[1].get("materialKey")!=null and slots[1].get("materialKey")!=material_key:_issue("unsupported_extra_material_slot",path)
  for limitation in Particles.limitations(p):_issue(limitation,path)
  var seed_value: int=int(event.get("particleRandomSeed",0))
  if not p.get("autoRandomSeed",true) and int(p.get("randomSeed",0))!=0:seed_value=int(p.randomSeed)
  seed_value=seed_value ^ Source.reference_key(components.ParticleSystem.get("source",{})).hash()
  var horizon: float=maxf(0.0,clip_in+duration*speed)
  var schedule: Array=Particles.emit(p,seed_value,horizon,max_particles_per_emitter)
  if schedule.size()>=max_particles_per_emitter:_issue("emitter_budget_cap",path+":"+str(max_particles_per_emitter))
  var stretch_candidate:bool=(asuna_stretch_orientation_candidate or _has_asuna_production_orientation(data)) and _is_asuna_muzzle_line(data,prefab,node_data,components)
  if stretch_candidate:
   _issue("candidate_stretch_orientation_only",path+"; preserves legacy size/trajectory, including unsupported inherited velocity and scaling mode")
  var layer: Dictionary={"stretch_candidate":stretch_candidate,"path":path,"params":p,"render":render,"base_transform":world,"particles":[],"mode":mode,"billboard":billboard,"mesh_flip":mesh_flip,"custom_stream_mapping":_custom_stream_mapping(render),"is_smoke":Source.reference_key(descriptor.get("source",{})) in OCCLUDING_SMOKE_MATERIALS}
  for particle in schedule:
   var pool_key: String=material_cache_key+":"+str(mesh.get_instance_id())
   var visual: MeshInstance3D=_acquire_visual(pool_key,mesh,base_material)
   # Unity: lower SortingFudge is in front; Godot: higher sorting_offset is.
   # Apply the orthographic distance bias in converted world units, not particle
   # size/local scale. This preserves material queue precedence and never moves
   # geometry. Reassign even zero: pooled visuals can belong to another emitter.
   visual.sorting_offset=-float(render.get("m_SortingFudge",0.0))*world_sorting_scale
   visual.visible=false;holder.add_child(visual)
   layer.particles.append({"sample":particle,"node":visual,"material":visual.material_override,"pool_key":pool_key,"birth":float(particle.birth),"life":float(particle.life),"shader_state":{}})
  instance.layers.append(layer)
 _effects.append(instance)

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
  var emission_cutoff:float=float(effect.get("emission_stopped_local",INF))
  for layer in effect.layers:
   for item in layer.particles:
    # Match Particles.state's subtraction exactly, including seek/reverse boundaries.
    # No forward-only cursor: a past/future particle can become visible on any call.
    var elapsed: float=local_time-float(item.birth)
    if elapsed<0 or elapsed>=float(item.life) or float(item.birth)>=emission_cutoff:
     item.node.visible=false
     continue
    _particle_state_evaluations+=1
    var state: Dictionary=Particles.state(layer.params,item.sample,local_time)
    item.node.visible=state.visible
    if not state.visible:continue
    var transform_anchor: Transform3D=anchor
    if int(layer.params.get("moveWithTransform",0))==1:
     var birth_global: float=float(effect.start)+(float(item.sample.birth)-float(effect.clip_in))/maxf(0.000001,float(effect.speed))
     var birth_anchor=_resolve(effect,birth_global,true)
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
    if layer.get("stretch_candidate",false):
     var camera_snapshot:Variant=stretch_camera_at.call(global_time) if stretch_camera_at.is_valid() else {}
     var world_velocity:Vector3=(transform_anchor.basis*layer.base_transform.basis)*(item.sample.direction*float(item.sample.start_speed)*float(item.sample.simulation_speed))
     var orientation:Dictionary=StretchOrientation.orient(item.node.global_transform,world_velocity,camera_snapshot if camera_snapshot is Dictionary else {},global_time)
     if orientation.applied:item.node.global_transform=orientation.transform
     else:_issue("candidate_stretch_fallback",layer.path+":"+str(orientation.reason))
     # Source shader's generic billboard rebuild would discard the CPU basis.
     var use_shader_billboard:bool=layer.billboard and not orientation.applied
     if item.shader_state.get("candidate_billboard")!=use_shader_billboard:
      material.set_shader_parameter("billboard",use_shader_billboard);item.shader_state.candidate_billboard=use_shader_billboard;_shader_parameter_writes+=1
    # Cache exact submitted values, not approximate equality or source assumptions.
    # Each spawned item starts empty, even when its material came from the pool.
    var shader_state: Dictionary=item.shader_state
    var presented_color:Color=state.color
    if _reduce_smoke and layer.is_smoke:presented_color.a*=0.55
    if shader_state.get("color")!=presented_color:
     material.set_shader_parameter("particle_color",presented_color);shader_state.color=presented_color;_shader_parameter_writes+=1
    if shader_state.get("source_custom0")!=state.custom0 or shader_state.get("source_custom1")!=state.custom1:
     var packed_custom: Array[Vector4]=_pack_custom_streams(layer.custom_stream_mapping,state.custom0,state.custom1)
     if shader_state.get("custom0")!=packed_custom[0]:
      material.set_shader_parameter("custom0",packed_custom[0]);shader_state.custom0=packed_custom[0];_shader_parameter_writes+=1
     if shader_state.get("custom1")!=packed_custom[1]:
      material.set_shader_parameter("custom1",packed_custom[1]);shader_state.custom1=packed_custom[1];_shader_parameter_writes+=1
     shader_state.source_custom0=state.custom0;shader_state.source_custom1=state.custom1
    if shader_state.get("uv_sheet")!=state.uv_sheet:
     material.set_shader_parameter("uv_sheet",state.uv_sheet);shader_state.uv_sheet=state.uv_sheet;_shader_parameter_writes+=1
    # Source Unity _Time is scene time, not per-particle age. Game clock only.
    if shader_state.get("effect_time")!=global_time:
     material.set_shader_parameter("effect_time",global_time);shader_state.effect_time=global_time;_shader_parameter_writes+=1
    var roll: float=rotation.z if layer.billboard else 0.0
    if shader_state.get("roll")!=roll:
     material.set_shader_parameter("roll",roll);shader_state.roll=roll;_shader_parameter_writes+=1

func _has_asuna_production_orientation(data:Dictionary)->bool:
 # Strict opt-in envelope. Never reinterpret strings/numbers as approval, and
 # never let production metadata bypass the existing private-fixture switch.
 var fixture:Variant=data.get("fixtureOnly",false)
 if not fixture is bool or fixture:return false
 var adaptations:Variant=data.get("renderAdaptations",{})
 if not adaptations is Dictionary:return false
 var enabled:Variant=adaptations.get("asunaMuzzleLineVelocityOrientation",false)
 return enabled is bool and enabled

func _is_asuna_muzzle_line(data:Dictionary,prefab:Dictionary,node_data:Dictionary,components:Dictionary)->bool:
 if str(data.get("character",""))!="asuna":return false
 var fixture:Variant=data.get("fixtureOnly",false)
 if not (fixture is bool and fixture) and not _has_asuna_production_orientation(data):return false
 if str(prefab.get("name",""))!="FX_Public_AR_Motion_Shot_Asuna" or str(node_data.get("hierarchy",""))!="FX_Public_AR_Motion_Shot_Asuna/Muzzle_Line":return false
 if str(components.ParticleSystem.source.get("rawSha256",""))!="f721a4569c00cbb7d19eddf6a12bbaf6e90df4fe241efdb1e9b57331b903a87f":return false
 if str(components.ParticleSystemRenderer.source.get("rawSha256",""))!="360a0394ebdd7936f2919ff445201d4fd9b8c9ff333c446341c6fa0d25c3f819":return false
 var p:Dictionary=components.ParticleSystem.nativeParameters
 var r:Dictionary=components.ParticleSystemRenderer.nativeParameters
 # This predicate intentionally does not inspect RenderAlignment: Unity does not
 # expose that property for Stretch. Unsupported length/rotation models are out.
 if int(r.get("m_RenderMode",0))!=1 or float(r.get("m_LengthScale",0))<=0:return false
 if float(r.get("m_VelocityScale",0))!=0 or float(r.get("m_CameraVelocityScale",0))!=0 or r.get("m_FreeformStretching",false):return false
 for key in ["m_Pivot","m_Flip"]:
  if not Curves.unity_vector(r.get(key,{})).is_zero_approx():return false
 for key in ["VelocityModule","ForceModule","RotationModule"]:
  if p.get(key,{}).get("enabled",false):return false
 var initial:Dictionary=p.get("InitialModule",{})
 if initial.get("rotation3D",false):return false
 for key in ["startRotation","gravityModifier"]:
  var value:Dictionary=initial.get(key,{})
  if int(value.get("minMaxState",0))!=0 or float(value.get("scalar",0))!=0:return false
 # World-space particles have a frozen birth anchor in the current adapter;
 # this makes analytic velocity independent of frame history/anchor differencing.
 return int(p.get("moveWithTransform",0))==1

func _deterministic_mesh_flip(renderer: Dictionary,mode: int,material: ShaderMaterial)->Vector3:
 # Unity mesh flips reflect geometry along local axes, not just UVs. Godot
 # compensates mirrored instances by swapping front/back culling, so this
 # transform-only path is faithful only for already double-sided materials.
 # Fractional probabilities need an independently verified random mapping;
 # never consume or repurpose the existing source-particle RNG stream here.
 if mode!=4:return Vector3.ONE
 var source: Dictionary=renderer.get("m_Flip",{})
 var flip:=Vector3(float(source.get("x",0)),float(source.get("y",0)),float(source.get("z",0)))
 if flip==Vector3.ZERO:return Vector3.ONE
 for axis in range(3):
  if flip[axis]!=0.0 and flip[axis]!=1.0:return Vector3.ONE
 var modes: PackedStringArray=material.shader.code.get_slice("render_mode ",1).get_slice(";",0).split(",")
 var double_sided: bool=false
 for value in modes:
  if value.strip_edges()=="cull_disabled":double_sided=true;break
 if not double_sided:return Vector3.ONE
 return Vector3.ONE-2.0*flip

func _custom_stream_mapping(renderer: Dictionary)->PackedInt32Array:
 # The source layout is immutable for this layer. Let the reference packer compile
 # its projection, preserving implicit/unknown-layout fallbacks without duplicating it.
 var projection: Array[Vector4]=Particles.shader_custom_streams(renderer,Vector4(1,2,3,4),Vector4(5,6,7,8))
 if projection==[Vector4(1,2,3,4),Vector4(5,6,7,8)]:return PackedInt32Array()
 return PackedInt32Array([int(projection[0].x),int(projection[0].y),int(projection[0].z),int(projection[0].w),int(projection[1].x),int(projection[1].y),int(projection[1].z),int(projection[1].w)])

func _pack_custom_streams(mapping: PackedInt32Array,custom0: Vector4,custom1: Vector4)->Array[Vector4]:
 if mapping.is_empty():return [custom0,custom1]
 var channels: Array[float]=[0.0,custom0.x,custom0.y,custom0.z,custom0.w,custom1.x,custom1.y,custom1.z,custom1.w]
 return [Vector4(channels[mapping[0]],channels[mapping[1]],channels[mapping[2]],channels[mapping[3]]),Vector4(channels[mapping[4]],channels[mapping[5]],channels[mapping[6]],channels[mapping[7]])]

func _resolve(effect: Dictionary,at: float,historical_birth:bool=false):
 var resolver: Callable=effect.resolver
 if not resolver.is_valid():return null
 # Current local pose and world-space birth can share a timestamp but differ
 # in causal event order. Add query metadata without mutating source bindings
 # or changing the existing three-argument resolver contract.
 var binding:Dictionary=effect.binding
 if historical_birth:
  binding=binding.duplicate();binding["_native_anchor_query"]="birth"
 var resolved=resolver.call(binding,effect.event,at)
 if resolved is Transform3D:return resolved
 if resolved is Node3D and is_instance_valid(resolved):return resolved.global_transform
 return null

func reset(new_generation: int)->void:
 generation=new_generation
 for effect in _effects:
  if is_instance_valid(effect.node):effect.node.free()
 _effects.clear();_clear_pool();_issues.clear();_issue_keys.clear();_now=0.0

## Tactical adapter policy: stop new births, retaining born particles through
## their existing life/source window. Never mutates source schedules or art.
func stop_emission(handle:int,at:float)->void:
 if not is_finite(at):return
 for effect in _effects:
  if int(effect.id)==handle and int(effect.generation)==generation:
   var cutoff:float=-INF if at<=float(effect.start) else float(effect.clip_in)+(at-float(effect.start))*float(effect.speed)
   effect["emission_stopped_local"]=minf(cutoff,float(effect.get("emission_stopped_local",INF)))

func release(handle: int)->void:
 for i in range(_effects.size()-1,-1,-1):
  if int(_effects[i].id)==handle:
   var effect: Dictionary=_effects[i]
   for layer in effect.layers:
    for item in layer.particles:
     if _pooled_count<max_pooled_nodes:
      effect.node.remove_child(item.node);item.node.visible=false
      if not _pool.has(item.pool_key):_pool[item.pool_key]=[]
      _pool[item.pool_key].append(item.node);_pooled_count+=1
   effect.node.free();_effects.remove_at(i)

func diagnostics()->Dictionary:
 var visible_particles: int=0;var scheduled: int=0;var visible_effects: int=0
 for effect in _effects:
  if effect.node.visible:visible_effects+=1
  for layer in effect.layers:
   scheduled+=layer.particles.size()
   if not effect.node.visible:continue
   for item in layer.particles:
    if item.node.visible:visible_particles+=1
 return {"generation":generation,"time":_now,"smoke_alpha_scale":0.55 if _reduce_smoke else 1.0,"active_effects":_effects.size(),"visible_effects":visible_effects,"scheduled_particles":scheduled,"visible_particles":visible_particles,"pooled_nodes":_pooled_count,"nodes_created":_nodes_created,"nodes_reused":_nodes_reused,"shader_parameter_writes":_shader_parameter_writes,"particle_state_evaluations":_particle_state_evaluations,"cached_materials":_material_cache.size(),"issues":_issues.duplicate(true),"fidelity":"Source assets/curves/material arithmetic. Godot RNG, Unity simulation details and HDR/output pipeline are not exact Unity parity."}

func snapshot()->Dictionary:
 var values: Array=[]
 for effect in _effects:
  for layer in effect.layers:
   for item in layer.particles:
    if effect.node.visible and item.node.visible:
     values.append({"prefab":effect.prefab,"layer":layer.path,"transform":item.node.global_transform,"color":item.material.get_shader_parameter("particle_color"),"custom0":item.material.get_shader_parameter("custom0"),"custom1":item.material.get_shader_parameter("custom1"),"sheet":item.material.get_shader_parameter("uv_sheet")})
 return {"generation":generation,"time":_now,"particles":values}

func _issue(code: String,context: String)->void:
 var key: String=code+":"+context
 if _issue_keys.has(key):return
 _issue_keys[key]=true;_issues.append({"code":code,"context":context})

func _natural_duration(prefab: Dictionary,seed_value: int)->float:
 var result: float=0.000001
 for n in prefab.get("nodes",[]):
  var components: Dictionary={}
  for c in n.get("components",[]):components[c.type]=c
  if not components.has("ParticleSystem") or not components.has("ParticleSystemRenderer"):continue
  if not components.ParticleSystemRenderer.get("nativeParameters",{}).get("m_Enabled",true):continue
  var p: Dictionary=components.ParticleSystem.nativeParameters.duplicate()
  if p.get("looping",false):
   _issue("bounded_direct_loop",str(prefab.get("name",""))+":one source emission cycle plus tails; timeline preserves exact window")
   p["looping"]=false
  var particle_seed: int=seed_value
  if not p.get("autoRandomSeed",true) and int(p.get("randomSeed",0))!=0:particle_seed=int(p.randomSeed)
  particle_seed=particle_seed ^ Source.reference_key(components.ParticleSystem.get("source",{})).hash()
  var delay: float=maxf(Curves.sample(p.get("startDelay",{}),0,0),Curves.sample(p.get("startDelay",{}),0,1))
  var duration: float=(float(p.get("lengthInSec",5))+delay)/maxf(0.000001,float(p.get("simulationSpeed",1)))
  for particle in Particles.emit(p,particle_seed,duration,max_particles_per_emitter):result=maxf(result,float(particle.birth)+float(particle.life))
 return result

func _acquire_visual(key: String,mesh: Mesh,material: ShaderMaterial)->MeshInstance3D:
 if _pool.has(key) and not _pool[key].is_empty():
  _pooled_count-=1;_nodes_reused+=1
  return _pool[key].pop_back()
 var visual:=MeshInstance3D.new();visual.mesh=mesh
 visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 visual.material_override=material.duplicate();_nodes_created+=1
 return visual

func _clear_pool()->void:
 for nodes in _pool.values():
  for node in nodes:
   if is_instance_valid(node):node.free()
 _pool.clear();_pooled_count=0

func _exit_tree()->void:_clear_pool()

func warmup_prefab(template_path: String,seed_value: int=1,duration: float=-1.0)->Dictionary:
 var handle: int=spawn(template_path,seed_value,0.0,_identity_anchor,duration)
 if handle>0:release(handle)
 return diagnostics()

func warmup_timeline(compact_path: String,character: String,timeline_name_or_kind: String="ex")->Dictionary:
 var handle: int=play_timeline(compact_path,character,timeline_name_or_kind,0.0,_identity_anchor)
 if handle>0:release(handle)
 return diagnostics()

func _identity_anchor(_binding: Dictionary,_event: Dictionary,_time: float)->Transform3D:return Transform3D.IDENTITY

func set_reduce_smoke(enabled:bool)->void:
 if _reduce_smoke==enabled:return
 _reduce_smoke=enabled
 # Refresh at the same seekable clock, including while the menu pauses combat.
 update_time(_now)
