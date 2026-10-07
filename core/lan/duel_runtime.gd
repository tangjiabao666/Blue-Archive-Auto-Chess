extends RefCounted
const Clock=preload('res://core/character_clock.gd')
const Navigation=preload('res://core/obstacle_navigation.gd')
const Hooks=preload('res://core/combat_arena_hooks.gd')
const Health=preload('res://core/battle_outcome.gd')
var clock=Clock.new()
var pair:Dictionary={}
var _navigation=Navigation.new()
var _hooks=Hooks.new()
var _sequences:Dictionary={0:0,1:0}
var _result:Dictionary={}
var _reason:=''
var _events:Array=[]
var _event_sequence:=0
var _feedback:Dictionary={}
func configure(value:Dictionary,rosters:Array,arena:Dictionary,settings:Dictionary)->Dictionary:
 pair=value.duplicate(true);clock.use_combat_mode('tactical_v1');clock.generation=int(pair.generation)
 var error:String=_navigation.configure(arena.half_size,arena.obstacles)
 if not error.is_empty():return {'ok':false,'error':error}
 _hooks.bind(clock.sim,_navigation,arena.obstacles)
 var roster:Array=[]
 for team in range(2):
  for i in range(rosters[team].size()):
   var owned:Dictionary=rosters[team][i]
   var point:Vector2=pair.positions[team][owned.id]
   roster.append({'id':team*7+i,'team':team,'character_id':owned.character_id,'star':int(owned.star),'cell':point if team==0 else -point,'owned_id':owned.id})
 var empty:bool=rosters[0].is_empty() or rosters[1].is_empty()
 var validated:Array=roster
 if empty:validated=[{'id':0,'team':0,'character_id':'shiroko','star':1,'cell':Vector2(0,6.5)},{'id':7,'team':1,'character_id':'shiroko','star':1,'cell':Vector2(0,-6.5)}]
 error=clock.sim.configure(validated,settings)
 clock.sim.command_sequence_allocator=Callable(self,"next_sequence")
 if not error.is_empty():return {'ok':false,'error':error}
 if empty:
  clock.sim.units=[]
  for row in roster:clock.sim.units.append(clock.sim.preview_unit(row.character_id,row.star,row.id,row.team,row.cell))
  clock.sim.phase='finished';_reason='empty'
 for i in range(roster.size()):clock.sim.units[i]['roster_unit_id']=roster[i].owned_id
 if empty:_finish()
 return {'ok':true}
func start()->void:
 if _result.is_empty():clock.sim.start()
func next_sequence(team:int)->int:
 var value:int=_sequences[team];_sequences[team]=value+1;return value
func queue_intent(team:int,command:Dictionary)->Dictionary:
 var kind:Variant=command.get('type')
 if not kind is String or kind not in ['cast_ex','move'] or not command.get('actor_id') is int:return {'ok':false,'error':'invalid_command'}
 if not command.get('point') is Vector2 or not command.point.is_finite():return {'ok':false,'error':'invalid_point'}
 var target:Variant=command.get('target_id',-1)
 if not target is int:return {'ok':false,'error':'invalid_target'}
 return clock.sim.queue_tactical_command({'generation':clock.generation,'team':team,'sequence':next_sequence(team),'tick':clock.sim.tick+1,'type':kind,'actor_id':command.actor_id,'target_id':target,'point':command.point})
func advance(delta:float)->Array:
 if not _result.is_empty():return []
 var batch:Array=clock.advance(delta)
 for event in batch:
  _event_sequence+=1;event['wire_sequence']=_event_sequence
  if event.type=='finished':_reason=event.reason
  _events.append(event.duplicate(true))
 if clock.sim.phase=='finished':_finish()
 return batch
func _finish()->void:
 var alive:Array=[0,0]
 for unit in clock.sim.units:
  if unit.hp>0:alive[unit.team]+=1
 var health:Dictionary=Health.totals(clock.sim.units)
 var outcome:Dictionary={'left_id':pair.left_id,'right_id':pair.right_id,'winner':Health.winner(health.remaining_hp_totals),'left_remaining':alive[0],'right_remaining':alive[1],'duration_ticks':clock.sim.tick,'finish_reason':_reason}
 outcome.merge(health)
 _result={'ok':true,'outcome':outcome,'remaining_hp_ratios':Health.ratios(outcome)}
func result()->Dictionary:return _result.duplicate(true)
func events_since(sequence:int)->Array:return _events.filter(func(event):return int(event.wire_sequence)>sequence).duplicate(true)
func snapshot()->Dictionary:
 return {'battle_id':pair.id,'left_id':pair.left_id,'right_id':pair.right_id,'generation':clock.generation,'tick':clock.sim.tick,'phase':clock.sim.phase,'units':clock.sim.units.duplicate(true),'telegraphs':telegraph_view(),'controls':clock.sim.tactical_controls(),'overtime':clock.sim.overtime_state(),'event_sequence':_event_sequence,'result':result()}
func close()->void:
 clock.sim.command_sequence_allocator=Callable()
 clock.sim.path_step=Callable();clock.sim.cover_query=Callable();clock.sim.line_of_sight=Callable();clock.sim.position_free=Callable();clock.sim.segment_free=Callable()
 _events.clear()

func telegraph_view()->Array:
 var result:Array=[]
 for volume in clock.sim.attack_telegraphs():
  if volume.ability=='normal' or volume.impacts.is_empty():continue
  var item:Dictionary={}
  for key in ['id','team','ability','shape','cast_start_tick','origin','direction','fan_origin','centers','radius','degrees','length','width']:
   if volume.has(key):item[key]=volume[key]
  item['impacts']=[{'due':volume.impacts[-1].due}]
  result.append(item)
 return result
