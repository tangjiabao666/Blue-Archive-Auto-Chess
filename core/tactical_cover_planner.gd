extends RefCounted
## Cached map candidates plus the same movement validator used by live orders.
## All decisions use published units, never cursor input or queued commands.
const Orders=preload('res://core/tactical_orders.gd')
const RADIUS:=0.35
var _navigation
var _incoming:Callable
var _candidates:Array[Vector2]=[]
var _probe=Orders.new()
func configure(navigation,obstacles:Array,distance:float,incoming:Callable)->void:
 _navigation=navigation;_incoming=incoming;_candidates.clear();_probe.reset()
 if navigation==null or not incoming.is_valid():return
 for obstacle in obstacles:
  if obstacle.get('blocks_projectiles',true) or obstacle.get('cover_kind','low')!='low':continue
  var rect:Rect2=obstacle.rect
  # Both shallow and deep firing slots fit the legal center-clearance band.
  for clearance in [RADIUS+0.025,maxf(RADIUS+0.025,distance-0.1)]:
   if clearance>distance:continue
   for fraction in [0.15,0.5,0.85]:
    var x:float=lerpf(rect.position.x,rect.end.x,fraction)
    var y:float=lerpf(rect.position.y,rect.end.y,fraction)
    for point in [Vector2(x,rect.position.y-clearance),Vector2(x,rect.end.y+clearance),Vector2(rect.position.x-clearance,y),Vector2(rect.end.x+clearance,y)]:
     if navigation.is_free(point,RADIUS) and not _candidates.has(point):_candidates.append(point)
func choose(actor:Dictionary,view:Dictionary,at:int)->Dictionary:
 if _navigation==null or not _incoming.is_valid() or _candidates.is_empty():return {}
 var threat:Dictionary=_nearest_threat(actor.cell,actor.team,view.units)
 if threat.is_empty():return {}
 var current:Dictionary=_incoming.call(threat.cell,actor.cell,'direct')
 if not current.blocked and current.multiplier<1.0:return {}
 var candidates:Array=[]
 for point in _candidates:
  var distance:float=actor.cell.distance_to(point)
  if distance<0.15 or distance>Orders.MAX_DISTANCE:continue
  var candidate_threat:Dictionary=_nearest_threat(point,actor.team,view.units)
  if candidate_threat.is_empty() or point.distance_to(candidate_threat.cell)>actor.range:continue
  if not _navigation.has_line_of_sight(point,candidate_threat.cell):continue
  if view.units.any(func(unit):return unit.id!=actor.id and unit.hp>0 and point.distance_to(unit.cell)<RADIUS*2.0-0.000001):continue
  var cover:Dictionary=_incoming.call(candidate_threat.cell,point,'direct')
  if cover.blocked or cover.multiplier>=1.0:continue
  candidates.append({'point':point,'distance':distance,'threat_id':candidate_threat.id})
 candidates.sort_custom(func(a,b):
  if not is_equal_approx(a.distance,b.distance):return a.distance<b.distance
  return a.point.x<b.point.x if not is_equal_approx(a.point.x,b.point.x) else a.point.y<b.point.y)
 for candidate in candidates:
  _probe.reset()
  var result:Dictionary=_probe.request(actor,candidate.point,{'navigation':_navigation,'units':view.units,'tick':at})
  if result.ok:return {'point':candidate.point,'threat_id':candidate.threat_id,'distance':result.distance}
 return {}

func _nearest_threat(point:Vector2,team:int,units:Array)->Dictionary:
 var threat:Dictionary={};var nearest:=INF
 for unit in units:
  if unit.team==team or unit.hp<=0:continue
  var distance:float=point.distance_squared_to(unit.cell)
  if distance<nearest or (is_equal_approx(distance,nearest) and unit.id<threat.get('id',2147483647)):
   threat=unit;nearest=distance
 return threat
