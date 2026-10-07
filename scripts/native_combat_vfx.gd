extends Node3D
## Live-game glue only: no combat mutation, gameplay timers, or autonomous process.
## Call consume for events, then update_time AFTER all UnitView poses are updated.
const PoseHistory=preload("res://scripts/sampled_pose_history.gd")
const Player=preload("res://vfx/native_effect_player.gd")
const Source=preload("res://vfx/native_source.gd")
const EVENTS="res://data/effects/battle-events-compact.json"
const WEAPONS="res://data/effects/shared-weapons/visual-templates.json"
const ADAPTATIONS="res://data/skill-impact-adaptations.json"
const TICK_SECONDS=0.05
# Cx * Cz = diag(-1,1,-1): GLB reflects X, particle adapter reflects Z.
# Right multiplication maps each VFX-local basis into the imported bone basis.
const REFLECTION_BRIDGE=Basis(Vector3(-1,0,0),Vector3(0,1,0),Vector3(0,0,-1))
# Verified original source AND GLB transforms: p0, quaternion identity, s1.
# Only these unskinned, unanimated chains may be reconstructed if Godot prunes them.
const STATIC_DM_CHARACTERS=["hoshino","aru","yuuka","aris","iori","koharu"]
# Original transform IDs; values are identity and no canonical EX/basic animates them.
const STATIC_ANCHOR_PROVENANCE={
 "shiroko":["CAB-643731497c327a692f823325e350e877","-7629969987914723426"],
 "hoshino":["CAB-1d74217275224e4ba8d7167893fe01e5","-4585702410337445308","4385677441179327044"],
 "hina":["CAB-dd5ee21a832156ef3ffee1204939e3c3","1949460138624985899"],
 "aru":["CAB-239820dc45cf44decf86bd21cea69550","-1652567840128802913","-1892698671607488609"],
 "yuuka":["CAB-eab1b343087322dc55c69afe43ec2626","-3618660196681695934","-198669916450833086"],
 "aris":["CAB-e70dbeb74a0f9d9829e8f42ba5e8b839","-2987032736837344046","-8363282200950676270"],
 "serika":["CAB-c5eb619971a4bbd45ebcdae8245fff96","-1594539665212321882"],
 # roster-expansion/static-anchor-provenance.extension.json: exact identity TRS,
 # no local transform animation in all 25-37 inspected clips per character.
 "iori":["CAB-6d2c9eb73a4bdce4adfbab4e8ef723b4","3092145410991681273","4117321087554187001"],
 "tsubaki":["CAB-413a47cd866b70e8135819a9674f6baf","6909517304231779164"],
 "nonomi":["CAB-670011ef9c02583f7cb5bffe64e4f01c","564474350357371256"],
 "mutsuki":["CAB-e6b061afc0b52f8cae893aa90b21ca7c","-859243527254223379"],
 "haruna":["CAB-74c6534b085dec2492aeeec90d96600c","-5107921179460844019"],
 "koharu":["CAB-07bd2287cce6015ee0f3dc45dde1725b","-1494616201231100576","4205756883919672672"]
}
# Verified root alias: Yuuka_Original source -> Echelon_Yuuka_Original GLB.
# bone_Calculator is animated; no rest-pose fallback is permitted.
var max_live_handles:int=160
var max_queued_events:int=4096
var history_seconds:float=12.0
var max_history_samples:int=768
var generation:int=-1
var _player:Node3D
var _reduce_smoke:bool=false
var _profiles:Dictionary={}
var _views:Dictionary={}
var _characters:Dictionary={}
var _weapons:Dictionary={}
var _weapon_families:Dictionary={}
var _compact:Dictionary={}
var _events_path:String=EVENTS
var _adaptations:Dictionary={}
var _ready_adaptations:Dictionary={}
var _casts:Dictionary={}
var _source_roots:Dictionary={}
var _source_paths:Dictionary={}
var _indices:Dictionary={}
# Successful bindings store identity only; poses are read on every capture.
var _muzzle_bindings:Dictionary={}
var _history:Dictionary={}
var _pending:Array=[]
var _event_sequence:int=0
var _handles:Array=[]
var _seen_ids:Dictionary={}
var _seen_visuals:Dictionary={}
var _issues:Array=[]
var _issue_keys:Dictionary={}
var _now:float=0.0
var _stats:Dictionary={}

func _init()->void:set_process(false);set_physics_process(false)

func configure(profiles:Dictionary)->void:
 _configure_sources(profiles,Source.read_json(EVENTS),EVENTS)

func _configure_sources(profiles:Dictionary,compact:Dictionary,events_path:String)->void:
 _events_path=events_path
 _profiles=profiles.duplicate(true)
 _indices.clear();_muzzle_bindings.clear()
 _compact=compact.duplicate(true)
 _adaptations=Source.read_json(ADAPTATIONS)
 _weapon_families=Source.read_json(WEAPONS).get("weaponFamilies",{})
 var skills:Dictionary=Source.read_json("res://data/character_skills.json")
 for character in skills.get("characters",[]):_weapons[str(character.get("key",""))]=str(character.get("weaponType",""))
 _source_roots.clear();_source_paths.clear()
 for character in _compact.get("activeRoster",[]):
  var paths:Array[String]=[]
  for timeline in _compact.get("characters",{}).get(character,{}).get("timelines",[]):
   if timeline.get("kind") not in ["ex","basic"]:continue
   for event in timeline.get("events",[]):
    if event.get("kind")!="effect":continue
    for binding in event.get("bindings",[]):
     var path:String=str(binding.get("hierarchy",""))
     if path.is_empty():continue
     _source_roots[character]=path.get_slice("/",0)
     if not paths.has(path):paths.append(path)
  var source_root:String=str(_source_roots.get(character,""))
  for anchor in _profiles.get(character,{}).get("anchors",[]):
   var path:String=_join_source_root(source_root,str(anchor.get("path","")))
   if not paths.has(path):paths.append(path)
  _source_paths[character]=paths
 _ensure_player()

## Private opt-in source fixture. Validate completely before changing existing state.
func configure_fixture(profiles:Dictionary,events_path:String,characters:Array)->bool:
 var compact:Dictionary=Source.read_json(events_path)
 if not compact.get("active") is bool or not compact.get("fixtureOnly") is bool:return false
 if compact.active or not compact.fixtureOnly:return false
 if not compact.get("activeRoster") is Array or not compact.activeRoster.is_empty():return false
 if not compact.get("fixtureCharacters") is Array or not compact.get("characters") is Dictionary:return false
 if characters.is_empty():return false
 var selected:Array=[]
 for character in characters:
  if not character is String or selected.has(character) or not compact.fixtureCharacters.has(character):return false
  if not profiles.get(character) is Dictionary:return false
  var profile:Dictionary=profiles[character]
  if not profile.get("anchors") is Array or profile.anchors.is_empty():return false
  if not profile.get("model_path") is String or not ResourceLoader.exists(profile.model_path):return false
  for anchor in profile.anchors:
   if not anchor is Dictionary or not anchor.get("path") is String:return false
  var record=compact.characters.get(character)
  if not record is Dictionary or not record.get("active") is bool or record.active or not record.get("timelines") is Array:return false
  var kinds:Array=[]
  for timeline in record.timelines:
   if not timeline is Dictionary or timeline.get("kind") not in ["ex","basic"] or not timeline.get("events") is Array:return false
   kinds.append(timeline.kind)
   for event in timeline.events:
    if not event is Dictionary or event.get("kind")!="effect" or not event.get("bindings") is Array or event.bindings.is_empty():return false
    if not event.get("asset") is Dictionary or not event.asset.get("resolved") is bool or not event.asset.resolved:return false
    for binding in event.bindings:
     if not binding is Dictionary or not binding.get("hierarchy") is String or binding.hierarchy.is_empty():return false
  if not kinds.has("ex") or not kinds.has("basic"):return false
  selected.append(character)
 compact.activeRoster=selected
 reset(generation)
 _configure_sources(profiles,compact,events_path)
 return true

func begin_roster(views:Dictionary,units:Array,new_generation:int)->void:
 reset(new_generation)
 _views=views.duplicate()
 for unit in units:_characters[int(unit.id)]=str(unit.get("character_id",""))
 var warmed_characters:Dictionary={};var warmed_families:Dictionary={}
 for actor_id in _views:
  if not is_instance_valid(_views[actor_id]):continue
  var character:String=str(_characters.get(actor_id,""))
  _indices[actor_id]=_index_view(_views[actor_id])
  if not warmed_characters.has(character):
   warmed_characters[character]=true
   for kind in ["ex","basic"]:_player.warmup_timeline(_events_path,character,kind)
   for row in _adaptations.get("skills",{}).values():
    if str(row.get("character",""))==character:_warm_adaptation(str(row.get("template","")))
   for row in _adaptations.get("normalMuzzleFallbacks",{}).values():
    if str(row.get("character",""))==character:_warm_adaptation(str(row.get("template","")))
  var family:String=str(_weapons.get(character,""))
  if not warmed_families.has(family):
   warmed_families[family]=true
   var mapping:Dictionary=_weapon_families.get(family,{})
   for field in ["muzzlePrefab","hitPrefab"]:
    var prefab=mapping.get(field)
    if prefab is String and not prefab.is_empty():_player.warmup_prefab(WEAPONS+"#"+prefab,1)
  var native_scale:float=float(_profiles.get(character,{}).get("model_scale",1.0))
  if warmed_characters.size()==1:
   _player.world_gravity_scale=native_scale
   _player.world_sorting_scale=native_scale
  elif not is_equal_approx(native_scale,float(_player.world_gravity_scale)):_issue("mixed_source_gravity_scales","One player has one world_gravity_scale; root should use uniform native unit scale")
 _capture_history(0.0)

func consume(event:Dictionary,units:Array,event_pose:bool=false)->void:
 if int(event.get("generation",generation))!=generation:_stats.stale_events+=1;return
 for unit in units:_characters[int(unit.id)]=str(unit.get("character_id",_characters.get(int(unit.id),"")))
 var kind:String=str(event.get("type",""))
 var ability:String=str(event.get("ability",""))
 if not (kind=="action_cancelled" or (kind=="damage" and ability in ["normal","ex","basic"]) or (kind=="heal" and ability in ["ex","basic"]) or (kind=="miss" and ability=="normal") or (kind=="skill" and ability=="ex") or (kind=="basic" and ability=="basic")):return
 var event_id:String=str(event.get("event_id",""))
 if not event_id.is_empty():
  var identity:String=str(generation)+":"+event_id
  if _seen_ids.has(identity):return
  _seen_ids[identity]=float(event.get("tick",0))*TICK_SECONDS
 if event.get("component","")=="echo":_stats.echoes_skipped+=1;return
 var queued:Dictionary=event.duplicate(true)
 queued["_sequence"]=_event_sequence;_event_sequence+=1
 if event_pose:
  var origin_anchors:Dictionary={}
  for id in [int(event.get("actor_id",-1)),int(event.get("target_id",-1))]:
   var samples:Array=_history.get(id,[])
   if not samples.is_empty() and absf(float(samples[-1].time)-float(event.get("tick",0))*TICK_SECONDS)<0.0000001:
    origin_anchors[id]=samples[-1].anchors.duplicate()
  queued["_origin_anchors"]=origin_anchors
 _pending.append(queued)
 while _pending.size()>maxi(0,max_queued_events):
  _pending.pop_front();_stats.queue_budget_drops+=1
  _issue("pending_event_budget","Oldest queued event dropped at configured cap "+str(max_queued_events))

func update_time(time:float)->void:
 if not is_finite(time):return
 if time<_now-0.000001:_issue("rewind_requires_reset","Glue releases completed handles; reset and replay combat events for full replay")
 _now=time
 _capture_history(time)
 _prune(time)
 # Array.sort_custom is unstable: preserve received order within one core tick.
 _pending.sort_custom(func(a,b):return int(a._sequence)<int(b._sequence) if int(a.get("tick",0))==int(b.get("tick",0)) else int(a.get("tick",0))<int(b.get("tick",0)))
 var later:Array=[]
 for event in _pending:
  if float(event.get("tick",0))*TICK_SECONDS>time+0.0000001:later.append(event);continue
  _consume_ready(event)
 _pending=later
 _player.update_time(time)
 _prune(time)

func reset(new_generation:int)->void:
 _ensure_player();generation=new_generation;_player.reset(new_generation)
 _views.clear();_characters.clear();_indices.clear();_history.clear();_pending.clear();_event_sequence=0;_handles.clear();_seen_ids.clear();_seen_visuals.clear();_issues.clear();_issue_keys.clear();_now=0
 _casts.clear();_ready_adaptations.clear();_muzzle_bindings.clear()
 _stats={"muzzles_spawned":0,"exact_muzzles_spawned":0,"adapted_muzzles_spawned":0,"adapted_skill_hits_spawned":0,"adapted_skill_heals_spawned":0,"adaptations_warmed":0,"hits_spawned":0,"timelines_spawned":0,"echoes_skipped":0,"stale_events":0,"budget_releases":0,"queue_budget_drops":0}

func _ensure_player()->void:
 if is_instance_valid(_player):return
 _player=Player.new();_player.name="NativeSourceEffects";_player.max_pooled_nodes=1024;add_child(_player);_player.set_reduce_smoke(_reduce_smoke)

func _consume_ready(event:Dictionary)->void:
 var actor_id:int=int(event.get("actor_id",-1))
 if not _views.has(actor_id) or not is_instance_valid(_views[actor_id]):_issue("missing_actor",str(actor_id));return
 var character:String=str(_characters.get(actor_id,event.get("character_id","")))
 var at:float=float(event.get("tick",0))*TICK_SECONDS
 var kind:String=str(event.type)
 if kind=="action_cancelled":
  # Only source timelines have future emissions. Contact-spawned impacts and
  # muzzles already happened; retained projectile contacts still reach this glue.
  for handle in _handles:
   if int(handle.actor_id)!=actor_id or str(handle.kind)!="timeline":continue
   if str(handle.get("ability","")) not in ["normal","basic"] or str(handle.get("ability","")) not in event.get("abilities",[]):continue
   if int(handle.get("cast_start_tick",-1))>int(event.tick):continue
   _player.stop_emission(int(handle.id),at)
  return
 if kind in ["skill","basic"]:
  var ability:String=str(event.ability)
  var cast_tick:int=int(event.get("cast_start_tick",event.tick))
  _casts["%d:%s:%d"%[actor_id,ability,cast_tick]]={"actor_id":actor_id,"ability":ability,"tick":cast_tick,"time":at,"target_cell":event.get("target_cell")}
  while _casts.size()>maxi(0,max_queued_events):_casts.erase(_casts.keys()[0])
  var key:String="timeline:%d:%d:%s"%[actor_id,int(event.tick),ability]
  if _seen_visuals.has(key):return
  _seen_visuals[key]=at
  var handle:int=_player.play_timeline(_events_path,character,ability,at,_resolve_history.bind(actor_id,"",at,event.get("_origin_anchors",{}).get(actor_id)))
  _register(handle,"timeline",actor_id,at,ability,cast_tick);_stats.timelines_spawned+=int(handle>0)
  return
 if str(event.get("ability",""))!="normal":
  _skill_impact(event,character,actor_id,at);return
 var family:String=str(_weapons.get(character,""))
 var mapping:Dictionary=_weapon_families.get(family,{})
 var muzzle_key:String="muzzle:%d:%d:%d"%[actor_id,int(event.tick),int(event.get("hit_index",0))]
 if not _seen_visuals.has(muzzle_key):
  _seen_visuals[muzzle_key]=at
  var prefab=mapping.get("muzzlePrefab")
  var template:String=WEAPONS+"#"+str(prefab)
  var adapted:bool=false
  if not prefab is String or prefab.is_empty():
   var fallback:Dictionary=_adaptations.get("normalMuzzleFallbacks",{}).get(character+":"+family,{})
   template=str(fallback.get("template",""))
   if bool(_ready_adaptations.get(template,false)):
    prefab=template.get_slice("#",1);adapted=true
    _issue("autochess_muzzle_fallback",character+":"+family+":"+template+"; native_runtime_binding_verified=false")
  if prefab is String and not prefab.is_empty():
   var transform=_event_anchor(event,actor_id,"@muzzle",at)
   if transform!=null:
    var handle:int=_player.spawn(template,muzzle_key.hash(),at,_resolve_history.bind(actor_id,"@muzzle",at,event.get("_origin_anchors",{}).get(actor_id)))
    _register(handle,"muzzle",actor_id,at);_stats.muzzles_spawned+=int(handle>0)
    if adapted:_stats.adapted_muzzles_spawned+=int(handle>0)
    else:_stats.exact_muzzles_spawned+=int(handle>0)
   else:_issue("missing_muzzle_anchor",character)
  else:_issue("unbound_weapon_muzzle",family+": no verified source mapping; RF is not assumed to be SR")
 if kind!="damage":return
 var target_id:int=int(event.get("target_id",-1))
 var hit_key:String="hit:%d:%d:%d:%d"%[actor_id,int(event.tick),int(event.get("hit_index",0)),target_id]
 if _seen_visuals.has(hit_key):return
 _seen_visuals[hit_key]=at
 var hit_prefab=mapping.get("hitPrefab")
 var hit_transform=_event_anchor(event,target_id,"@hit",at)
 if not hit_prefab is String or hit_prefab.is_empty():_issue("unbound_weapon_hit",family);return
 if hit_transform==null:_issue("missing_victim_anchor",str(target_id));return
 # Impacts stay at the sampled contact location. They do not follow a moving victim.
 var resolver:Callable=_fixed_anchor.bind(hit_transform)
 var hit_handle:int=_player.spawn(WEAPONS+"#"+hit_prefab,hit_key.hash(),at,resolver)
 _register(hit_handle,"hit",target_id,at);_stats.hits_spawned+=int(hit_handle>0)

# Policy-only direct spawning never unmutes or rewrites recovered source Timelines.
func _warm_adaptation(template:String)->void:
 if template.is_empty() or _ready_adaptations.has(template):return
 var handle:int=_player.spawn(template,1,0.0,_fixed_anchor.bind(Transform3D.IDENTITY))
 var supported:bool=_has_scheduled_particles(handle)
 if handle>0:_player.release(handle)
 _ready_adaptations[template]=supported
 if supported:_stats.adaptations_warmed+=1
 else:_issue("unsupported_empty_adaptation",template+"; no implemented scheduled source particles")

func _has_scheduled_particles(handle:int)->bool:
 for effect in _player.get("_effects"):
  if int(effect.id)!=handle:continue
  for layer in effect.layers:
   if not layer.particles.is_empty():return true
 return false

func _skill_impact(event:Dictionary,character:String,actor_id:int,at:float)->void:
 var contact_type:String=str(event.get("type",""))
 if contact_type not in ["damage","heal"]:return
 var ability:String=str(event.get("ability",""))
 var component:String=str(event.get("component",""))
 var policy_key:String=character+":"+ability+":"+component
 var row:Dictionary=_adaptations.get("skills",{}).get(policy_key,{})
 if row.is_empty():
  if _adaptations.get("unsupportedSkillComponents",{}).has(policy_key):_issue("unsupported_skill_impact",policy_key+":"+str(_adaptations.unsupportedSkillComponents[policy_key]))
  return
 # Healing is opt-in per source-art policy. Damage/heal use one visual key
 # when their authoritative cast/component/hit/ground center is shared.
 if contact_type not in row.get("eventTypes",["damage"]):return
 var template:String=str(row.get("template",""))
 if not bool(_ready_adaptations.get(template,false)):
  _issue("unsupported_empty_adaptation",template+"; no implemented scheduled source particles");return
 var cast_tick:int=int(event.get("cast_start_tick",-1))
 var cast:Dictionary={}
 if cast_tick>=0:cast=_casts.get("%d:%s:%d"%[actor_id,ability,cast_tick],{})
 else:
  # Older fixtures may supply only a recorded cast event. Never infer an area
  # center from the first victim or from its current damage-event target_cell.
  for candidate in _casts.values():
   if int(candidate.actor_id)==actor_id and str(candidate.ability)==ability and int(candidate.tick)<=int(event.tick) and int(candidate.tick)>cast_tick:
    cast=candidate;cast_tick=int(candidate.tick)
  _issue("legacy_cast_context_adaptation",policy_key+"; recorded cast fallback, native_runtime_binding_verified=false")
 var target_id:int=int(event.get("target_id",-1))
 var area:bool=str(row.get("anchor",""))=="cast_target_ground"
 var mine:bool=character=="mutsuki" and ability=="basic" and component=="mine"
 var anchor
 if area:
  # Triggered mines originate at the actual placed mine, not the old cast aim.
  var cell=event.get("origin") if mine else event.get("cast_target_cell",cast.get("target_cell"))
  if not cell is Vector2 or not (cell as Vector2).is_finite():_issue("missing_adapted_mine_origin" if mine else "missing_adapted_cast_target",policy_key);return
  var native_scale:float=float(_profiles.get(character,{}).get("model_scale",1.0))
  anchor=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*native_scale),Vector3(cell.x,0.0,cell.y))
 else:
  anchor=_event_anchor(event,target_id,"@hit",at)
  if anchor==null:_issue("missing_victim_anchor",str(target_id));return
 if cast_tick<0:cast_tick=int(event.tick)
 var key:String="adapted-hit:%d:%d:%s:%s:%d:%d"%[actor_id,cast_tick,ability,component,int(event.get("hit_index",0)),-1 if area else target_id]
 if mine:
  if event.has("mine_id"):key+=":mine:"+str(event.mine_id)
  else:
   # Compatibility only: exact serialized ground point and contact tick keep
   # legacy separate mine centers apart. Authoritative events carry mine_id.
   key+=":legacy-mine:%d:"%int(event.tick)+var_to_bytes(anchor.origin).hex_encode()
   _issue("legacy_mine_identity_adaptation",policy_key+"; origin/contact tick fallback")
 if _seen_visuals.has(key):return
 _seen_visuals[key]=at
 var handle:int=_player.spawn(template,key.hash(),at,_fixed_anchor.bind(anchor))
 if not _has_scheduled_particles(handle):
  if handle>0:_player.release(handle)
  _issue("unsupported_empty_adaptation",template+"; no implemented scheduled source particles");return
 _register(handle,"adapted_skill_heal" if contact_type=="heal" else "adapted_skill_hit",actor_id if area else target_id,at)
 if contact_type=="heal":_stats.adapted_skill_heals_spawned+=1
 else:_stats.adapted_skill_hits_spawned+=1

func _register(handle:int,kind:String,actor_id:int,at:float,ability:String="",cast_start_tick:int=-1)->void:
 if handle<=0:return
 var deadline:float=at
 # Frozen adapter has no public deadline getter; read its immutable source windows.
 # This narrow glue dependency is covered by exact-window integration tests.
 for effect in _player.get("_effects"):
  if int(effect.id)==handle:deadline=maxf(deadline,float(effect.end))
 _handles.append({"id":handle,"kind":kind,"actor_id":actor_id,"start":at,"end":deadline,"ability":ability,"cast_start_tick":cast_start_tick})
 while _handles.size()>maxi(0,max_live_handles):
  _player.release(int(_handles[0].id));_handles.pop_front();_stats.budget_releases+=1
  _issue("live_handle_budget","Oldest visual released at configured cap "+str(max_live_handles))

func _prune(at:float)->void:
 for key in _casts.keys():
  if at-float(_casts[key].time)>history_seconds:_casts.erase(key)
 for i in range(_handles.size()-1,-1,-1):
  if at>=float(_handles[i].end):_player.release(int(_handles[i].id));_handles.remove_at(i)
 for dictionary in [_seen_ids,_seen_visuals]:
  for key in dictionary.keys():
   if at-float(dictionary[key])>history_seconds:dictionary.erase(key)

func _index_view(view:Node3D)->Dictionary:
 var model=view.get("_model")
 if not model is Node3D or not is_instance_valid(model):return {"model":null,"names":{},"bones":{},"bindings":{}}
 var names:Dictionary={};var bones:Dictionary={}
 var nodes:Array=[model];nodes.append_array(model.find_children("*","Node3D",true,false))
 for node in nodes:
  var key:String=str(node.name)
  if not names.has(key):names[key]=[]
  names[key].append(node)
  if node is Skeleton3D:
   for i in range(node.get_bone_count()):
    var bone_name:String=node.get_bone_name(i)
    if not bones.has(bone_name):bones[bone_name]=[]
    bones[bone_name].append({"skeleton":node,"index":i})
 return {"model":model,"names":names,"bones":bones,"bindings":{}}

func _anchor_index(actor_id:int,character:String)->Dictionary:
 var view=_views.get(actor_id)
 if not is_instance_valid(view):return {}
 var model=view.get("_model")
 if not model is Node3D or not is_instance_valid(model):return {}
 var index:Dictionary=_indices.get(actor_id,{})
 if index.get("model")!=model or str(index.get("character",character))!=character:
  index=_index_view(view);_indices[actor_id]=index
 index["character"]=character
 return index

func resolve_live_anchor(actor_id:int,source_path:String):
 var character:String=str(_characters.get(actor_id,""))
 var index:Dictionary=_anchor_index(actor_id,character)
 if index.is_empty():return null
 # The index is a roster hierarchy snapshot. Replacing it or the view's model
 # drops all successful bindings; missing and ambiguous entries are never cached.
 var bindings:Dictionary=index.bindings
 var binding:Array=bindings.get(source_path,[])
 if not binding.is_empty() and not is_instance_valid(binding[0]):
  bindings.erase(source_path);binding=[]
 if binding.is_empty():
  binding=_bind_live_anchor(index,character,source_path)
  if binding.is_empty():return null
  bindings[source_path]=binding
 var node:Node3D=binding[0]
 if int(binding[1])<0:return _bridge(node.global_transform)
 var skeleton:Skeleton3D=node
 var bone:int=int(binding[1])
 if bone>=skeleton.get_bone_count() or skeleton.get_bone_name(bone)!=binding[2]:
  bindings.erase(source_path);return null
 var transform:Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(bone)
 if binding.size()>3:
  for child in binding[3]:
   if not is_instance_valid(child):bindings.erase(source_path);return null
   transform=transform*child.transform
 return _bridge(transform)

func _asuna_node_binding(node:Node3D)->Array:
 # The verified Asuna import inserts non-overriding BoneAttachment3D aliases.
 # Their derived node transform may lag a manual AnimationPlayer.advance call.
 # Read the current source bone and authored descendant locals instead; never
 # collapse an unrelated same-named node or an overriding/external attachment.
 # This identity cache shares UnitView's immutable-hierarchy setup contract.
 var chain:Array=[];var current:Node=node
 while current!=null:
  if current is BoneAttachment3D:
   var skeleton=current.get_parent()
   var bone:int=current.bone_idx
   if skeleton is Skeleton3D and not current.override_pose and not current.use_external_skeleton and bone>=0 and bone<skeleton.get_bone_count() and skeleton.get_bone_name(bone)==current.bone_name:
    chain.reverse();return [skeleton,bone,String(current.bone_name),chain]
   return [node,-1]
  if current is Node3D:chain.append(current)
  current=current.get_parent()
 return [node,-1]

func _bind_live_anchor(index:Dictionary,character:String,source_path:String)->Array:
 var source_root:String=str(_source_roots.get(character,""))
 if source_path!=source_root and not source_path.begins_with(source_root+"/"):
  _issue("foreign_source_anchor",character+":"+source_path);return []
 var model:Node3D=index.model
 if source_path==source_root:return [model,-1]
 var leaf:String=source_path.get_file()
 var matches:Array=[]
 for node in index.get("names",{}).get(leaf,[]):
  if is_instance_valid(node):
   var candidate:Array=_asuna_node_binding(node) if character=="asuna" else [node,-1]
   if not matches.has(candidate):matches.append(candidate)
 for bone in index.get("bones",{}).get(leaf,[]):
  if is_instance_valid(bone.skeleton) and int(bone.index)<bone.skeleton.get_bone_count() and bone.skeleton.get_bone_name(int(bone.index))==leaf:
   var candidate:Array=[bone.skeleton,bone.index,leaf,[]] if character=="asuna" else [bone.skeleton,bone.index,leaf]
   if not matches.has(candidate):matches.append(candidate)
 if matches.size()==1:return matches[0]
 if matches.size()>1:_issue("ambiguous_live_anchor",character+":"+source_path);return []
 var relative:String=source_path.trim_prefix(source_root+"/")
 if STATIC_ANCHOR_PROVENANCE.has(character) and (relative=="Ex_Root" or (relative=="Ex_Root/FX_Local_DM" and character in STATIC_DM_CHARACTERS)):
  _issue("verified_identity_anchor_reconstruction",character+":"+relative)
  return [model,-1]
 # Iori FX_Rotate Transform -5734234413284495623 in the same source CAB:
 # identity local TRS, unanimated across 33 clips. Its bone_root parent IS
 # animated, so retain the live parent identity rather than the model root.
 if character=="iori" and relative=="bone_root/FX_Rotate":
  var parent:Array=_bind_live_anchor(index,character,source_root+"/bone_root")
  if not parent.is_empty():
   _issue("verified_identity_child_reconstruction",character+":"+relative)
   return parent
 _issue("missing_source_anchor",character+":"+source_path)
 return []

static func _join_source_root(source_root:String,path:String)->String:
 return path if path==source_root or path.begins_with(source_root+"/") else source_root+"/"+path

func _muzzle_sources(character:String)->Array:
 if _muzzle_bindings.has(character):return _muzzle_bindings[character]
 var profile:Dictionary=_profiles.get(character,{})
 var name:String=str(profile.get("muzzle_anchor",""))
 var source_root:String=str(_source_roots.get(character,""))
 var result:Array=[]
 for anchor in profile.get("anchors",[]):
  if str(anchor.get("name",""))!=name:continue
  var path:String=str(anchor.get("path",""))
  var binding:Dictionary={"path":_join_source_root(source_root,path),"name":name}
  var parent_path:String=path.get_base_dir()
  var p:Array=anchor.get("local_translation",[]);var q:Array=anchor.get("local_rotation",[]);var scale_values:Array=anchor.get("local_scale",[1,1,1])
  if p.size()==3 and q.size()==4 and scale_values.size()==3 and not parent_path.is_empty() and parent_path!=".":
   binding["parent"]=_join_source_root(source_root,parent_path)
   binding["socket"]=Transform3D(Basis(Quaternion(q[0],q[1],q[2],q[3])).scaled_local(Vector3(scale_values[0],scale_values[1],scale_values[2])),Vector3(p[0],p[1],p[2]))
  result.append(binding)
 _muzzle_bindings[character]=result
 return result

func _live_muzzle(actor_id:int,captured:Dictionary={}):
 var character:String=str(_characters.get(actor_id,""))
 for binding in _muzzle_sources(character):
  var path:String=binding.path
  # Reuse only this exact capture's transform, never another actor or timestamp.
  var exact=captured[path] if captured.has(path) else resolve_live_anchor(actor_id,path)
  if exact!=null:return exact
  # Ordinary-fire-only reconstruction from an extracted local socket plus its
  # verified live parent. Never accept UnitView's emergency actor-root fallback.
  if not binding.has("socket"):continue
  var parent_path:String=binding.parent
  var parent=captured[parent_path] if captured.has(parent_path) else resolve_live_anchor(actor_id,parent_path)
  if parent==null:continue
  _issue("verified_static_socket_fallback",character+":"+str(binding.name)+"; ordinary fire only, authored local profile offset and live parent")
  return _bridge((parent as Transform3D)*Transform3D(REFLECTION_BRIDGE,Vector3.ZERO)*(binding.socket as Transform3D))
 return null

func capture_event_pose(at:float,actor_ids:Array)->void:
 if actor_ids.is_empty() or not is_finite(at) or at<_now-0.0000001:return
 _capture_history(at,actor_ids)

func _capture_history(at:float,actor_ids:Array=[])->void:
 for actor_id in (_views.keys() if actor_ids.is_empty() else actor_ids):
  var view=_views.get(actor_id)
  if not is_instance_valid(view):continue
  var character:String=str(_characters.get(actor_id,""))
  var anchors:Dictionary={}
  for path in _source_paths.get(character,[]):
   var value=resolve_live_anchor(actor_id,path)
   if value!=null:anchors[path]=value
  var muzzle=_live_muzzle(actor_id,anchors)
  if muzzle!=null:anchors["@muzzle"]=muzzle
  if view.has_method("hit_position"):
   var model=_indices.get(actor_id,{}).get("model")
   if model is Node3D and is_instance_valid(model):
    anchors["@hit"]=Transform3D(Basis.IDENTITY.scaled(model.global_transform.basis.get_scale().abs()),view.hit_position())
  if not _history.has(actor_id):_history[actor_id]=[]
  var samples:Array=_history[actor_id]
  PoseHistory.record(samples,{"time":at,"anchors":anchors},history_seconds,max_history_samples)


func _sample_anchor(actor_id:int,path:String,at:float):
 var samples:Array=_history.get(actor_id,[])
 if samples.is_empty():return null
 if at<float(samples[0].time)-0.000001:_issue("missing_anchor_history",str(actor_id)+":"+path);return null
 for i in range(samples.size()-1,-1,-1):
  var a:Dictionary=samples[i]
  if at<float(a.time)-0.0000001:continue
  if not a.anchors.has(path):return null
  if i==samples.size()-1 or absf(at-float(a.time))<0.0000001:return a.anchors[path]
  var b:Dictionary=samples[i+1]
  if not b.anchors.has(path):return null
  var blend:float=clampf((at-float(a.time))/maxf(0.000001,float(b.time)-float(a.time)),0,1)
  return (a.anchors[path] as Transform3D).interpolate_with(b.anchors[path],blend)
 return null

func _event_anchor(event:Dictionary,actor_id:int,path:String,at:float):
 var origins:Dictionary=event.get("_origin_anchors",{})
 if origins.has(actor_id):return origins[actor_id].get(path)
 return _sample_anchor(actor_id,path,at)

func _resolve_history(binding:Dictionary,event:Dictionary,at:float,actor_id:int,mode:String,origin_time:float=-1.0,origin_anchors:Variant=null):
 var path:String=mode if not mode.is_empty() else str(binding.get("hierarchy",""))
 if path.is_empty():
  var asset=event.get("asset")
  _issue("unbound_runtime_effect_skipped",str(asset.get("name",event.get("label",""))) if asset is Dictionary else str(event.get("label","")))
  return null
 if binding.get("_native_anchor_query","")=="birth" and absf(at-origin_time)<0.0000001 and origin_anchors is Dictionary:return origin_anchors.get(path)
 return _sample_anchor(actor_id,path,at)

func _fixed_anchor(_binding:Dictionary,_event:Dictionary,_at:float,transform:Transform3D)->Transform3D:return transform
static func _bridge(transform:Transform3D)->Transform3D:return transform*Transform3D(REFLECTION_BRIDGE,Vector3.ZERO)

func diagnostics()->Dictionary:
 var result:Dictionary=_stats.duplicate()
 result.merge({"adaptation_classification":"AUTOCHESS VISUAL ADAPTATIONS","native_runtime_binding_verified":false,"adaptation_policy":ADAPTATIONS,"binding_paths":{"exact_normal_weapon_manifest":WEAPONS,"exact_normal_weapon_families":_weapon_families.duplicate(true),"autochess_skill_impacts":_adaptations.get("skills",{}).duplicate(true),"autochess_muzzle_fallbacks":_adaptations.get("normalMuzzleFallbacks",{}).duplicate(true)},"generation":generation,"time":_now,"queued_events":_pending.size(),"active_handles":_handles.size(),"issues":_issues.duplicate(true),"native":_player.diagnostics() if is_instance_valid(_player) else {},"changes_combat_state":false,"history":"Sampled source anchors with Transform3D interpolation; full replay requires reset and event replay"})
 return result
func handle_deadlines()->Array:return _handles.duplicate(true)
func visual_snapshot()->Dictionary:return _player.snapshot()
func _issue(code:String,context:String)->void:
 var key:String=code+":"+context
 if not _issue_keys.has(key):_issue_keys[key]=true;_issues.append({"code":code,"context":context})

func set_reduce_smoke(enabled:bool)->void:
 _reduce_smoke=enabled;_ensure_player();_player.set_reduce_smoke(enabled)
