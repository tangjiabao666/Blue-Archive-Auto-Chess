extends "res://core/character_sim.gd"
## New battle orchestration is isolated from the immutable legacy scheduler.
const AttackVolumes=preload('res://core/attack_volumes.gd')
const VolumeBuilder=preload('res://core/tactical_volume_builder.gd')
const TacticalOrders=preload('res://core/tactical_orders.gd')
const Navigation=preload('res://core/obstacle_navigation.gd')
const TacticalAI=preload('res://core/tactical_ai.gd')
const CoverPlanner=preload('res://core/tactical_cover_planner.gd')
const Resources=preload('res://core/tactical_resources.gd')
const CommandQueue=preload('res://core/tactical_command_queue.gd')
var _commands=CommandQueue.new()
var _command_generation:=0
var _resources=Resources.new()
var _manual_actor:=-1
var _manual_target:Dictionary={}
var _ex_busy_until:Dictionary={}
var _ai=TacticalAI.new()
var _ai_teams:Array=[]
var command_sequence_allocator:Callable
var _volumes=AttackVolumes.new()
var _orders=TacticalOrders.new()
var _order_navigation
var _navigation_bound:=false
var _incoming_cover:Callable
var _contact_cover_multiplier:=1.0
var _tactical_damage_scale:=1.0
var _timeout_total_hp:=false
var _tactical_cover_distance:=0.6
var _tactical_cover_multiplier:=0.8
var _tactical_cover_ai:=false
var _cover_status_query:Callable
var _cover_configure:Callable
var _cover_obstacles:Array=[]
var _cover_planner=CoverPlanner.new()
func set_command_generation(value:int)->void:
 _command_generation=value;_commands.reset(value)
 _commands.configure_actors(units)
 _ai.configure(_ai_teams,_command_generation,_characters,options.source_units_per_world_unit)
 _ai.bind_cover_planner(Callable(_cover_planner,"choose") if _tactical_cover_ai else Callable())
func configure(roster:Array,settings:Dictionary={})->String:
 var candidate:Dictionary=settings.duplicate(true)
 if candidate.get('combat_mode','tactical_v1')!='tactical_v1':return 'invalid combat mode'
 candidate.erase('combat_mode')
 var ai_teams:Variant=candidate.get('tactical_ai_teams',[])
 if not ai_teams is Array:return 'invalid tactical AI teams'
 var seen:Dictionary={}
 for team in ai_teams:
  if not team is int or team not in [0,1] or seen.has(team):return 'invalid tactical AI teams'
  seen[team]=true
 candidate.erase('tactical_ai_teams')
 var pacing:Variant=candidate.get('tactical_damage_scale',1.0)
 if not (pacing is int or pacing is float) or not is_finite(float(pacing)) or pacing<=0 or pacing>1:return 'invalid tactical damage scale'
 candidate.erase('tactical_damage_scale')
 var hp_timeout:Variant=candidate.get('timeout_total_hp',false)
 if not hp_timeout is bool:return 'invalid timeout decision'
 candidate.erase('timeout_total_hp')
 var cover_distance:Variant=candidate.get('tactical_cover_distance',0.6)
 if not (cover_distance is int or cover_distance is float) or not is_finite(float(cover_distance)) or cover_distance<0.35 or cover_distance>2.0:return 'invalid tactical cover distance'
 var cover_multiplier:Variant=candidate.get('tactical_cover_multiplier',0.8)
 if not (cover_multiplier is int or cover_multiplier is float) or not is_finite(float(cover_multiplier)) or cover_multiplier<=0.0 or cover_multiplier>1.0:return 'invalid tactical cover multiplier'
 var cover_ai:Variant=candidate.get('tactical_cover_ai',false)
 if not cover_ai is bool:return 'invalid tactical cover AI'
 for key in ['tactical_cover_distance','tactical_cover_multiplier','tactical_cover_ai']:candidate.erase(key)
 var error:String=super.configure(roster,candidate)
 if error.is_empty():
  _tactical_damage_scale=float(pacing);_timeout_total_hp=hp_timeout
  _tactical_cover_distance=float(cover_distance);_tactical_cover_multiplier=float(cover_multiplier);_tactical_cover_ai=cover_ai
  _ai_teams=ai_teams.duplicate();set_command_generation(_command_generation);_resources.reset();_ex_busy_until.clear()
  for unit in units:unit.skill_cooldown_ticks=Resources.EX_COOLDOWN_TICKS;unit.skill_ready=0
  _initial=units.duplicate(true);_orders.reset();_volumes.reset()
  if not _navigation_bound:
   _order_navigation=Navigation.new();_order_navigation.configure(options.arena_half,[])
  _configure_cover_geometry();_refresh_cover_status()
 return error
func reset()->void:
 super.reset();set_command_generation(_command_generation);_resources.reset();_ex_busy_until.clear();_manual_actor=-1;_manual_target.clear();_orders.reset();_volumes.reset();_refresh_cover_status()
func queue_tactical_command(command:Dictionary)->Dictionary:
 if phase!='running':return {'ok':false,'error':'battle_required'}
 return _commands.enqueue(command,tick)
func step() -> Array:
 events=[]
 if phase!="running":return []
 tick+=1
 _resources.advance(tick)
 if tick%10==0 and not _ai_teams.is_empty():
  for ai_command in _ai.decide(_ai_view(),tick):
   if command_sequence_allocator.is_valid():ai_command.sequence=command_sequence_allocator.call(ai_command.team)
   _commands.enqueue(ai_command,tick)
 if options.overtime_enabled and tick==_ticks(options.overtime_start_seconds):
  _emit("overtime_started",overtime_state())
 if cover_query.is_valid():
  for unit in units:
   if unit.hp<=0:continue
   var covered:bool=cover_query.call(unit)
   if covered!=unit.in_cover:_cover_changes.append({"id":unit.id,"in_cover":covered})
 _apply_cover_changes()
 _expire_and_reload()
 for command in _commands.drain(tick):
  var result:Dictionary=_execute_tactical_command(command)
  _emit("command_accepted" if result.ok else "command_rejected",{"sequence":command.sequence,"team":command.team,"actor_id":command.actor_id,"command_type":command.type,"error":result.get("error","")})
 _update_packs()
 _update_dashes()
 _move_units()
 _update_conditional_states()
 _update_mines()
 var queue:Array=[]
 var later:Array=[]
 # All actors alive at this tick boundary may resolve already-due attacks,
 # even if a simultaneous queued hit kills them later in this same tick.
 for hit in _pending:
  var actor=_unit(hit.source)
  var target=_unit(hit.target)
  if actor==null or actor.hp<=0 or target==null or target.hp<=0:continue
  if hit.due<=tick:queue.append(hit)
  else:later.append(hit)
 _pending=later
 for u in units:
  if u.hp<=0:continue
  var c:Dictionary=_characters[u.character_id]
  if c.sub.trigger.kind=="periodic" and tick>=u.sub_ready:_periodic_sub(u)
  if c.basic.trigger.kind=="hp_below_threshold" and not _orders.has_order(u.id) and u.basic_activations==0 and float(u.hp)/u.max_hp<c.basic.trigger.thresholdHpRatio:
   _start_health_skill(u)
  if u.aimed and _target(u,u.range)==null:_clear_aim(u,"target_lost")
  if tick<u.busy_until or tick<u.stun_until or u.reload_until>tick:continue
  if u.star==2 and tick>=u.skill_ready and _try_skill(u,"ex"):continue
  if c.basic.trigger.kind in ["periodic","ally_hp_below_threshold"] and tick>=u.basic_ready and _try_skill(u,"basic"):continue
  if c.normalAttack.enabled and u.ammo>0:
   var target=_normal_target(u)
   if target==null:continue
   if not u.aimed:
    _begin_aim(u,target)
    continue
   u.aim_target_id=target.id
   if tick>=u.attack_ready and tick>=u.aim_ready:_normal_attack(u,target)
 # Newly queued zero-delay actions still join this batch before resolution.
 later=[]
 for hit in _pending:
  if hit.due<=tick:queue.append(hit)
  else:later.append(hit)
 _pending=later
 queue.append_array(_volumes.resolve(tick,units,_volume_target_visible))
 for hit in queue:_resolve_hit(hit)
 for u in units:
  if u.hp<=0 and not u.dead:
   _cancel_dash(u,"death")
   u.hp=0;u.dead=true
   u.taunt_source_id=-1;u.taunt_until=0;u.stationary=false;u.damage_taken_multiplier=1.0
   for buff_id in u.buffs.keys():
    if u.buffs[buff_id].has("condition"):u.buffs.erase(buff_id)
   _emit("death",{"actor_id":u.id,"character_id":u.character_id})
 _remove_dead_owner_mines()
 _clear_invalid_taunts()
 _refresh_stats()
 _check_finish()
 _refresh_cover_status()
 return events.duplicate(true)

func snapshot()->Dictionary:
 _refresh_cover_status()
 var state:Dictionary=super.snapshot()
 state.tactical={'mode':'tactical_v1','damage_scale':_tactical_damage_scale,'cover_distance':_tactical_cover_distance,'cover_multiplier':_tactical_cover_multiplier,'cover_ai':_tactical_cover_ai,'queue':_commands.snapshot(),'resources':_resources.snapshot(),'ex_busy_until':_ex_busy_until.duplicate(true),'ai':_ai.snapshot(),'orders':_orders.snapshot(),'volumes':_volumes.snapshot(),'next_volume_id':_volumes.next_id()}
 return state

func _execute_tactical_command(command:Dictionary)->Dictionary:
 if command.type=='move':return _execute_move(command)
 if command.type!='cast_ex':return {'ok':false,'error':'action_unavailable'}
 var u=_unit(command.actor_id)
 if u==null or u.hp<=0:return {'ok':false,'error':'actor_dead'}
 if u.star!=2:return {'ok':false,'error':'ex_locked'}
 if tick<u.stun_until:return {'ok':false,'error':'actor_stunned'}
 if tick<_ex_busy_until.get(u.id,0):return {'ok':false,'error':'ex_in_progress'}
 var skill:Dictionary=_characters[u.character_id].ex
 var cost:int=int(skill.originalCost)
 if not _resources.can_cast(u.team,u.id,cost,tick):return {'ok':false,'error':'energy_or_cooldown'}
 var selected:Dictionary=_validate_manual_target(u,skill,command)
 if not selected.ok:return selected
 _cancel_ordinary_action(u,'manual_ex')
 if _orders.has_order(u.id):
  _orders.cancel(u.id,'ex_cast');_emit('tactical_move_finished',{'actor_id':u.id,'reason':'ex_cast'})
 _manual_actor=u.id;_manual_target=selected.target
 var cast:bool=_cast_source_skill(u,'ex')
 _manual_actor=-1;_manual_target={}
 if not cast:return {'ok':false,'error':'skill_unavailable'}
 var committed:bool=_resources.commit_cast(u.team,u.id,cost,tick)
 assert(committed,'validated EX resource commit must be atomic')
 u.skill_ready=tick+Resources.EX_COOLDOWN_TICKS
 _ex_busy_until[u.id]=u.busy_until
 if u.ammo==0 and u.reload_until==0:u.reload_at=u.busy_until
 return {'ok':true,'error':''}
func _validate_manual_target(u:Dictionary,skill:Dictionary,command:Dictionary)->Dictionary:
 var self_kinds:Array=['self_barrier','reload_and_self_buff','self_defense_buff_and_aoe_taunt','self_buff']
 if skill.kind in self_kinds:
  if command.target_id not in [-1,u.id] or command.point.distance_to(u.cell)>RADIUS:return {'ok':false,'error':'invalid_self_target'}
  return {'ok':true,'target':u}
 var reach:float=skill.get('targetingRangeSourceUnits',_characters[u.character_id].statsLevel50ThreeStar.Range)/options.source_units_per_world_unit
 if skill.kind in ['drone_damage','single_target_burst','direct_shot_then_explosion','three_shot_target_then_rear_fan']:
  var target=_unit(command.target_id)
  if target==null or target.hp<=0 or target.team==u.team:return {'ok':false,'error':'invalid_enemy_target'}
  if u.cell.distance_to(target.cell)>reach:return {'ok':false,'error':'target_out_of_range'}
  if line_of_sight.is_valid() and not line_of_sight.call(u.cell,target.cell):return {'ok':false,'error':'target_obstructed'}
  return {'ok':true,'target':target}
 var point:Vector2=command.point
 if not _inside(point) or u.cell.distance_to(point)>reach:return {'ok':false,'error':'target_out_of_range'}
 if skill.kind in ['fan_damage','fan_damage_knockback_stun','charge_scaled_line_damage','line_damage_with_target_falloff','directional_dash_and_self_buffs'] and u.cell.distance_to(point)<0.00001:return {'ok':false,'error':'invalid_direction'}
 return {'ok':true,'target':{'id':-1,'team':1-u.team,'cell':point,'hp':1.0,'max_hp':1.0}}
func _try_skill(u:Dictionary,ability:String)->bool:
 if ability=='ex' and _manual_actor!=u.id:return false
 return _cast_source_skill(u,ability)
func _target(u:Dictionary,reach:float=-1.0):
 if _manual_actor==u.id:return _manual_target
 return super._target(u,reach)
func _area_ex_target(u:Dictionary,skill:Dictionary,reach:float):
 if _manual_actor==u.id:return _manual_target
 return super._area_ex_target(u,skill,reach)
func _support_circle_target(u:Dictionary,skill:Dictionary,reach:float):
 if _manual_actor==u.id:return _manual_target
 return super._support_circle_target(u,skill,reach)
func _heal_target(u:Dictionary,reach:float):
 if _manual_actor==u.id:return _manual_target
 return super._heal_target(u,reach)

func _ai_view()->Dictionary:
 return {'units':units.duplicate(true),'arena_half':options.arena_half,'telegraphs':_volumes.snapshot(),'tactical':{'resources':_resources.snapshot(),'ex_busy_until':_ex_busy_until.duplicate(true),'orders':_orders.snapshot()}}

func bind_tactical_navigation(navigation)->void:
 _order_navigation=navigation;_navigation_bound=true
 _configure_cover_geometry()
func bind_tactical_cover(query:Callable,status_query:Callable=Callable(),configure_query:Callable=Callable(),obstacles:Array=[])->void:
 _incoming_cover=query;_cover_status_query=status_query;_cover_configure=configure_query;_cover_obstacles=obstacles.duplicate(true)
 _configure_cover_geometry();_refresh_cover_status()
func _configure_cover_geometry()->void:
 if _cover_configure.is_valid():_cover_configure.call(_tactical_cover_distance,_tactical_cover_multiplier)
 _cover_planner.configure(_order_navigation,_cover_obstacles,_tactical_cover_distance,_incoming_cover)
func _refresh_cover_status()->void:
 for unit in units:
  unit.cover_status=_cover_status_query.call(unit,units) if _cover_status_query.is_valid() else {'state':'none','threat_id':-1,'multiplier':1.0,'direction':Vector2.ZERO}
func _order_context()->Dictionary:return {'navigation':_order_navigation,'units':units,'tick':tick}
func _execute_move(command:Dictionary)->Dictionary:
 var u=_unit(command.actor_id)
 if u==null or u.hp<=0:return {'ok':false,'error':'actor_dead'}
 if tick<u.stun_until:return {'ok':false,'error':'actor_stunned'}
 if tick<_ex_busy_until.get(u.id,0):return {'ok':false,'error':'ex_in_progress'}
 if not _resources.can_move(u.team):return {'ok':false,'error':'no_move_charges'}
 var requested:Dictionary=_orders.request(u,command.point,_order_context())
 if not requested.ok:return requested
 assert(_resources.commit_move(u.team),'validated move spend is atomic')
 _cancel_ordinary_action(u,'tactical_move');u.busy_until=tick
 _emit('tactical_move_started',{'actor_id':u.id,'destination':command.point,'path':requested.path,'distance':requested.distance})
 return {'ok':true,'error':''}
func _cancel_ordinary_action(u:Dictionary,reason:String)->void:
 for volume in _volumes.snapshot():
  if volume.source==u.id and volume.ability in ['normal','basic'] and not volume.get('emitted',false):_volumes.cancel_cast(u.id,volume.cast_start_tick,volume.ability)
 # Existing ordinary contacts emit and resolve together. An explicitly emitted
 # projectile is retained if a future flight implementation supplies that flag.
 _pending=_pending.filter(func(hit):return not (hit.source==u.id and hit.get('ability','') in ['normal','basic'] and hit.due>=tick and not hit.get('emitted',false)))
 u.reload_until=0;u.reload_at=0;_clear_aim(u,reason)
 _emit('action_cancelled',{'actor_id':u.id,'reason':reason,'abilities':['normal','basic']})
func _move_units()->void:
 for u in units:
  if not _orders.has_order(u.id):continue
  var result:Dictionary=_orders.step(u,_order_context())
  u.busy_until=maxi(u.busy_until,tick+1)
  if result.moved:
   _clear_aim(u,'tactical_move');u.cell=result.to;u.move_ready=tick+1;u.last_moved_tick=tick;u.stationary=false
   _emit('move',{'actor_id':u.id,'from':result.from,'to':result.to,'duration':STEP_SECONDS,'forced':true,'tactical':true})
  if result.finished:
   _emit('tactical_move_finished',{'actor_id':u.id,'reason':result.reason})
   if u.ammo==0 and u.reload_until==0:u.reload_at=tick+1
 super._move_units()

func _latest_cast_context(actor:int,ability:String)->Dictionary:
 for index in range(events.size()-1,-1,-1):
  var event:Dictionary=events[index]
  if event.get('actor_id',-1)==actor and event.get('ability','')==ability and event.type in ['attack','basic','skill']:
   var context:Dictionary=event.duplicate(true);context.cast_start_tick=event.get('cast_start_tick',tick);return context
 return {}
func _cast_source_skill(u:Dictionary,ability:String)->bool:
 var cast:bool=super._try_skill(u,ability)
 if not cast:return false
 var skill:Dictionary=_characters[u.character_id][ability]
 var context:Dictionary=_latest_cast_context(u.id,ability)
 var duration:int=_ticks(skill.castSeconds)
 if skill.kind=='line_damage_with_target_falloff':
  _schedule_spatial_pattern(u,skill,skill.damage,ability,duration,{},'piercing',-1,context)
 if skill.kind=='circle_heal_and_damage':
  var offset:int=_single_contact_offset(u.character_id,ability,'circle',duration,0.2)
  _pending=_pending.filter(func(hit):return not (hit.source==u.id and hit.get('ability','')==ability and hit.get('effect','')=='heal' and hit.get('cast_context',{}).get('cast_start_tick',-1)==tick))
  var volume:Dictionary={'source':u.id,'team':u.team,'ability':ability,'cast_start_tick':tick,'origin':u.cell,'direction':Vector2.UP,'centers':[context.target_cell],
   'shape':'circle','radius':skill.shapeSource[0].Radius/options.source_units_per_world_unit,'contact_policy':'lob','impacts':[{'due':tick+offset,'hit':{'source':u.id,'due':tick+offset,'effect':'heal','ratio':skill.healPowerRatio,'ability':ability,'cast_context':context.duplicate(true),'component':'circle'}}]}
  _publish_volume(volume)
 return true
func _damage_pattern(u:Dictionary,victims:Array,damage:Dictionary,ability:String,duration:int,skill:Dictionary={},component:String='',first_offset:int=-1,cast_context:Dictionary={})->void:
 var source:Dictionary=_characters[u.character_id].normalAttack if ability=='normal' else _characters[u.character_id][ability]
 if source.get('kind','')=='line_damage_with_target_falloff':return # one unsplit volume is scheduled after source casting
 var context:Dictionary=cast_context if not cast_context.is_empty() else _latest_cast_context(u.id,ability)
 if _schedule_spatial_pattern(u,source,damage,ability,duration,skill,component,first_offset,context):return
 super._damage_pattern(u,victims,damage,ability,duration,skill,component,first_offset,cast_context)
func _schedule_spatial_pattern(u:Dictionary,source:Dictionary,damage:Dictionary,ability:String,duration:int,effect_skill:Dictionary,component:String,first_offset:int,context:Dictionary)->bool:
 var built:Dictionary=VolumeBuilder.build({'source':u,'source_skill':source,'damage':damage,'ability':ability,'duration':duration,'effect_skill':effect_skill,'component':component,'first_offset':first_offset,'context':context,
  'scale':options.source_units_per_world_unit,'tick':tick,'contact_ticks':_native_contact_ticks(u.character_id,ability,component,damage.hitWeights.size()),'lower_bound':_native_contact_lower_bound(u.character_id,ability,component),'final_stun':options.hoshino_stun_on_final_hit})
 if built.is_empty():return false
 _publish_volume(built);return true
func _publish_volume(volume:Dictionary)->void:
 if volume.shape=='target_fan':
  for impact in volume.impacts:
   impact.hit.cover_fan_origin=volume.fan_origin;impact.hit.cover_primary_target=volume.primary_target
 var id:int=_volumes.schedule(volume)
 assert(id>=0,'source geometry must produce valid attack volume')
 if id<0:return
 _emit('attack_telegraph',{'actor_id':volume.source,'ability':volume.ability,'volume_id':id,'cast_start_tick':volume.cast_start_tick,'shape':volume.shape,'first_impact_tick':volume.impacts[0].due})

func _volume_target_visible(volume:Dictionary,target:Dictionary)->bool:
 if volume.get('contact_policy','area') in ['lob','penetrating'] or not line_of_sight.is_valid():return true
 var origin:Vector2=volume.origin
 if volume.shape=='target_fan' and target.id!=volume.primary_target:origin=volume.fan_origin
 return line_of_sight.call(origin,target.cell)

func _resolve_hit(hit:Dictionary)->void:
 if hit.effect!='damage' or not _incoming_cover.is_valid():
  super._resolve_hit(hit);return
 var target=_unit(hit.target)
 if target==null or target.hp<=0:return
 var origin:Vector2=hit.origin
 if hit.has('cover_fan_origin') and hit.target!=hit.cover_primary_target:origin=hit.cover_fan_origin
 var cover:Dictionary=_incoming_cover.call(origin,target.cell,hit.get('contact_policy','direct'))
 if cover.blocked:return
 # Keep source coefficients intact and apply protection at the authoritative
 # damage calculation, before its single rounding/shield step. Echo recursion
 # establishes its own contact factor rather than multiplying its parent's.
 var previous:float=_contact_cover_multiplier
 _contact_cover_multiplier=cover.multiplier
 super._resolve_hit(hit)
 _contact_cover_multiplier=previous

func damage_components(source:Dictionary,target:Dictionary,ratio:float,critical:bool=false,stability:float=1.0)->Dictionary:
 var components:Dictionary=super.damage_components(source,target,ratio,critical,stability)
 components.raw*=_contact_cover_multiplier*_tactical_damage_multiplier()
 return components

func _tactical_damage_multiplier()->float:
 var overtime:Dictionary=super.overtime_state()
 return lerpf(_tactical_damage_scale,1.0,float(overtime.progress))
func overtime_state()->Dictionary:
 var state:Dictionary=super.overtime_state()
 state.damage_multiplier=lerpf(_tactical_damage_scale,1.0,float(state.progress))
 state.base_damage_multiplier=_tactical_damage_scale
 return state

func attack_telegraphs()->Array:return _volumes.snapshot()

func tactical_controls()->Dictionary:return {'resources':_resources.snapshot(),'ex_busy_until':_ex_busy_until.duplicate(true)}

func preview_unit(character_id:String,star:int=1,id:int=0,team:int=0,cell:Vector2=Vector2.ZERO)->Dictionary:
 var unit:Dictionary=super.preview_unit(character_id,star,id,team,cell)
 if not unit.is_empty():unit.skill_ready=0;unit.skill_cooldown_ticks=Resources.EX_COOLDOWN_TICKS
 return unit

func _check_finish()->void:
 if _timeout_total_hp and tick>=options.max_ticks and units.any(func(unit):return unit.team==0 and unit.hp>0) and units.any(func(unit):return unit.team==1 and unit.hp>0):
  var totals:Dictionary=preload("res://core/battle_outcome.gd").totals(units)
  var result:String=preload("res://core/battle_outcome.gd").winner(totals.remaining_hp_totals)
  _end(0 if result=="left" else 1 if result=="right" else -1,"timeout")
  return
 super._check_finish()

func enable_ai_team(team:int)->void:
 if team not in [0,1]:return
 _commands.cancel_pending(team)
 if team not in _ai_teams:_ai_teams.append(team)
 _ai.enable_team(team)
