extends RefCounted
## Detached, battle-scoped input. Acceptance here means queued, not executed.
const KEYS:=["generation","team","sequence","tick","type","actor_id","target_id","point"]
const MAX_FUTURE_TICKS:=4
const MAX_PENDING:=64
const MAX_SEQUENCE:=2147483647
var _generation:=0
var _actors:Dictionary={}
var _pending:Array=[]
var _seen:Dictionary={}
var _last_drain:=-1
func reset(generation:int)->void:
 _generation=generation;_actors.clear();_pending.clear();_seen.clear();_last_drain=-1
func configure_actors(roster:Array)->Dictionary:
 var next:Dictionary={}
 for actor in roster:
  if not actor is Dictionary or not actor.get('id') is int or not actor.get('team') is int:return _failure('invalid_actor_ownership')
  if actor.id<0 or actor.team not in [0,1] or next.has(actor.id):return _failure('invalid_actor_ownership')
  next[actor.id]=actor.team
 if not _pending.is_empty():return _failure('queue_not_empty')
 _actors=next
 return {'ok':true,'error':''}
func enqueue(command:Dictionary,current_tick:int)->Dictionary:
 if current_tick<0 or current_tick<_last_drain:return _failure('invalid_tick')
 if command.size()!=KEYS.size():return _failure('invalid_command')
 for key in KEYS:
  if not command.has(key):return _failure('invalid_command')
 for key in ['generation','team','sequence','tick','actor_id','target_id']:
  if not command[key] is int:return _failure('invalid_command')
 if command.generation!=_generation:return _failure('stale_generation')
 if command.team not in [0,1] or _actors.get(command.actor_id,-1)!=command.team:return _failure('invalid_actor_ownership')
 if command.sequence<0 or command.sequence>MAX_SEQUENCE:return _failure('invalid_sequence')
 if command.tick<=current_tick or command.tick>current_tick+MAX_FUTURE_TICKS:return _failure('invalid_tick')
 if not command.type is String or command.type not in ['cast_ex','move']:return _failure('invalid_command_type')
 if command.target_id < -1 or (command.target_id!=-1 and not _actors.has(command.target_id)):return _failure('invalid_target')
 if not command.point is Vector2 or not command.point.is_finite():return _failure('invalid_point')
 var identity:=str(command.team)+':'+str(command.sequence)
 if _seen.has(identity):return _failure('duplicate_command')
 if _pending.size()>=MAX_PENDING:return _failure('queue_full')
 _pending.append(command.duplicate(true));_seen[identity]=true
 return {'ok':true,'error':'','queued':true,'sequence':command.sequence,'tick':command.tick}
func drain(at:int)->Array:
 if at<0 or at<_last_drain:return []
 _last_drain=at
 var due:Array=[];var later:Array=[]
 for command in _pending:
  if command.tick<=at:due.append(command)
  else:later.append(command)
 _pending=later
 due.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
  if a.tick!=b.tick:return a.tick<b.tick
  if a.team!=b.team:return a.team<b.team
  return a.sequence<b.sequence)
 return due.duplicate(true)
func snapshot()->Dictionary:
 return {'generation':_generation,'actors':_actors.duplicate(true),'pending':_pending.duplicate(true),'seen':_seen.duplicate(true),'last_drain':_last_drain}
func _failure(reason:String)->Dictionary:return {'ok':false,'error':reason}

func cancel_pending(team:int)->void:
 _pending=_pending.filter(func(command):return command.team!=team)
