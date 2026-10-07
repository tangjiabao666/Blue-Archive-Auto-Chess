extends RefCounted
const RADIUS:=0.35
const MAX_DISTANCE:=4.0
const STEP_DISTANCE:=0.125
const EPSILON:=0.000001
var _orders:Dictionary={}
func has_order(actor_id:int)->bool:return _orders.has(actor_id)
func request(actor:Dictionary,destination:Vector2,context:Dictionary)->Dictionary:
 if not destination.is_finite() or actor.hp<=0:return _failure('invalid_destination')
 if actor.cell.distance_to(destination)<0.001:return _failure('already_at_destination')
 if _orders.has(actor.id) and _orders[actor.id].destination.distance_to(destination)<0.001:return _failure('already_moving')
 var nav=context.navigation
 if not nav.is_free(destination,RADIUS):return _failure('invalid_destination')
 var blockers:Array=_blockers(actor.id,context.units)
 if not nav.is_crowd_segment_free(destination,destination,RADIUS,blockers):return _failure('occupied_destination')
 var route:Array=[actor.cell];var cursor:Vector2=actor.cell;var distance:=0.0
 for unused in range(32):
  var next:Vector2=nav.next_crowd_waypoint(cursor,destination,RADIUS,blockers)
  if not next.is_finite() or next.distance_to(cursor)<EPSILON:return _failure('unreachable_destination')
  if not nav.is_crowd_segment_free(cursor,next,RADIUS,blockers):return _failure('unreachable_destination')
  distance+=cursor.distance_to(next)
  if distance>MAX_DISTANCE+EPSILON:return _failure('move_too_far')
  route.append(next);cursor=next
  if cursor.distance_to(destination)<EPSILON:
   _orders[actor.id]={'destination':destination,'path':route.duplicate(),'next':1,'travelled':0.0,'started_tick':context.tick}
   return {'ok':true,'error':'','path':route.duplicate(),'distance':distance}
 return _failure('unreachable_destination')
func step(actor:Dictionary,context:Dictionary)->Dictionary:
 if not _orders.has(actor.id):return {'active':false,'moved':false,'finished':false,'reason':''}
 if actor.hp<=0:return _end(actor.id,'death')
 if context.tick<actor.get('stun_until',0):return _end(actor.id,'stun')
 var order:Dictionary=_orders[actor.id]
 var origin:Vector2=actor.cell
 var target:Vector2=order.path[order.next]
 var next:Vector2=origin.move_toward(target,STEP_DISTANCE)
 var nav=context.navigation
 if not nav.is_crowd_segment_free(origin,next,RADIUS,_blockers(actor.id,context.units)):return _end(actor.id,'blocked')
 var travelled:float=origin.distance_to(next)
 if order.travelled+travelled>MAX_DISTANCE+EPSILON:return _end(actor.id,'distance_limit')
 order.travelled+=travelled
 if next.distance_to(target)<EPSILON:order.next+=1
 var finished:bool=order.next>=order.path.size()
 if finished:_orders.erase(actor.id)
 return {'active':not finished,'moved':travelled>EPSILON,'finished':finished,'reason':'arrived' if finished else '', 'from':origin,'to':next}
func cancel(actor_id:int,_reason:String)->void:_orders.erase(actor_id)
func reset()->void:_orders.clear()
func snapshot()->Dictionary:return _orders.duplicate(true)
func _end(actor_id:int,reason:String)->Dictionary:
 _orders.erase(actor_id)
 return {'active':false,'moved':false,'finished':true,'reason':reason}
func _blockers(actor_id:int,units:Array)->Array:
 var blockers:Array=[]
 for unit in units:
  if unit.id!=actor_id and unit.hp>0:blockers.append(unit.cell)
 return blockers
func _failure(reason:String)->Dictionary:return {'ok':false,'error':reason}
