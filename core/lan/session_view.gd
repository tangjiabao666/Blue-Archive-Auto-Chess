extends RefCounted
var state:Dictionary={}
var _event_sequence:=0
var _battle_id:=''
var _revision:=-1
var pending_events:Array=[]
func accept(value:Dictionary,participant_id:String)->Dictionary:
 if value.get('participant_id')!=participant_id or not value.get('revision') is int or not value.get('round') is int or not value.get('player') is Dictionary:return {'ok':false,'error':'invalid_view'}
 if value.revision<_revision:return {'ok':false,'error':'stale_view'}
 var battle:Variant=value.get('battle',{})
 if not battle is Dictionary:return {'ok':false,'error':'invalid_battle'}
 if not battle.is_empty():
  if not battle.get('battle_id') is String or not battle.get('tick') is int or not battle.get('generation') is int or not battle.get('units') is Array:return {'ok':false,'error':'invalid_battle'}
  if participant_id not in [battle.get('left_id'),battle.get('right_id')]:return {'ok':false,'error':'wrong_battle'}
  if battle.battle_id==_battle_id and battle.tick<int(state.get('battle',{}).get('tick',-1)):return {'ok':false,'error':'stale_tick'}
  if battle.battle_id!=_battle_id:_battle_id=battle.battle_id;_event_sequence=0;pending_events.clear()
  for event in value.get('events',[]):
   if not event is Dictionary or not event.get('wire_sequence') is int:continue
   if event.wire_sequence>_event_sequence:pending_events.append(event.duplicate(true));_event_sequence=event.wire_sequence
 _revision=value.revision;state=value.duplicate(true);state.erase('events')
 return {'ok':true}
func drain_events()->Array:
 var result:Array=pending_events.duplicate(true);pending_events.clear();return result
func local_team()->int:
 var battle:Dictionary=state.get('battle',{})
 return 0 if battle.get('left_id')==state.get('participant_id') else 1
func owns_actor(actor_id:int)->bool:
 for unit in state.get('battle',{}).get('units',[]):
  if unit.id==actor_id:return unit.team==local_team()
 return false
