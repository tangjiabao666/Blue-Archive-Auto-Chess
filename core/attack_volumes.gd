extends RefCounted
## Authoritative spatial attacks. Victims are selected at impact, never at cast.
const UNIT_RADIUS:=0.35
const EPSILON:=0.000001
var _volumes:Array=[]
var _next_id:=0
func reset()->void:_volumes.clear();_next_id=0
func next_id()->int:return _next_id
func schedule(spec:Dictionary)->int:
 if not _valid(spec):return -1
 var volume:Dictionary=spec.duplicate(true);volume.id=_next_id;_next_id+=1
 volume.direction=volume.direction.normalized()
 volume.impacts.sort_custom(func(a,b):return a.due<b.due)
 _volumes.append(volume)
 return volume.id
func resolve(at:int,units:Array,target_filter:Callable=Callable())->Array:
 var hits:Array=[];var later:Array=[];var alive:Dictionary={}
 for unit in units:
  if unit.hp>0:alive[unit.id]=unit
 for volume in _volumes:
  if not alive.has(volume.source):continue
  var pending:Array=[]
  for impact in volume.impacts:
   if impact.due>at:pending.append(impact);continue
   var healing:bool=impact.hit.effect=='heal'
   var targets:Array=[]
   for unit in units:
    if unit.hp<=0 or (unit.team==volume.team)!=healing:continue
    if contains(volume,unit.cell,UNIT_RADIUS,unit.id) and (not target_filter.is_valid() or target_filter.call(volume,unit)):targets.append(unit)
   targets.sort_custom(func(a,b):
    if volume.has('falloff'):
     var da:float=(a.cell-volume.origin).dot(volume.direction);var db:float=(b.cell-volume.origin).dot(volume.direction)
     if not is_equal_approx(da,db):return da<db
    return a.id<b.id)
   for index in range(targets.size()):
    var target:Dictionary=targets[index];var hit:Dictionary=impact.hit.duplicate(true)
    hit.target=target.id;hit.target_cell=target.cell;hit.due=impact.due;hit.volume_id=volume.id
    hit.contact_policy=volume.get('contact_policy','area')
    if volume.has('falloff') and hit.has('atk_ratio'):
     hit.atk_ratio*=maxf(volume.falloff.minimum,1.0-volume.falloff.step*index)
    hits.append(hit)
  volume.impacts=pending
  if not pending.is_empty():later.append(volume)
 _volumes=later
 return hits
func cancel_cast(actor_id:int,cast_start_tick:int,ability:String)->void:
 _volumes=_volumes.filter(func(v):return not (v.source==actor_id and v.cast_start_tick==cast_start_tick and v.ability==ability))
func snapshot()->Array:return _volumes.duplicate(true)
static func contains(volume:Dictionary,point:Vector2,radius:float=UNIT_RADIUS,actor_id:int=-1)->bool:
 if not point.is_finite() or not is_finite(radius) or radius<0:return false
 if volume.shape=='circle':
  for center in volume.centers:
   if point.distance_squared_to(center)<=pow(volume.radius+radius,2)+EPSILON:return true
  return false
 if volume.shape=='target_fan' and actor_id>=0 and actor_id==volume.get('primary_target',-1):return true
 var origin:Vector2=volume.get('fan_origin',volume.origin) if volume.shape=='target_fan' else volume.origin
 var offset:Vector2=point-origin;var direction:Vector2=volume.direction.normalized()
 if volume.shape=='line':
  var forward:float=offset.dot(direction);var lateral:float=offset.cross(direction)
  var dx:float=forward-clampf(forward,0,volume.length)
  var dy:float=lateral-clampf(lateral,-volume.width*0.5,volume.width*0.5)
  return dx*dx+dy*dy<=radius*radius+EPSILON
 var reach:float=volume.radius;var half_angle:float=deg_to_rad(volume.degrees*0.5)
 if half_angle>=PI-EPSILON:return offset.length()<=reach+radius+EPSILON
 if offset.length_squared()<EPSILON:return true
 if absf(direction.angle_to(offset))<=half_angle+EPSILON:
  return offset.length()<=reach+radius+EPSILON
 return minf(_segment_distance_squared(point,origin,origin+direction.rotated(half_angle)*reach),_segment_distance_squared(point,origin,origin+direction.rotated(-half_angle)*reach))<=radius*radius+EPSILON
static func _segment_distance_squared(point:Vector2,a:Vector2,b:Vector2)->float:
 var ab:Vector2=b-a
 if ab.length_squared()<EPSILON:return point.distance_squared_to(a)
 return point.distance_squared_to(a+ab*clampf((point-a).dot(ab)/ab.length_squared(),0,1))
func _valid(spec:Dictionary)->bool:
 for key in ['source','team','cast_start_tick']:
  if not spec.get(key) is int or spec[key]<0:return false
 if spec.team not in [0,1] or spec.get('ability','') not in ['normal','basic','ex']:return false
 if spec.get('shape','') not in ['circle','line','fan','target_fan']:return false
 for key in ['origin','direction']:
  if not _point(spec.get(key)):return false
 if spec.direction.length_squared()<EPSILON:return false
 if spec.shape=='circle':
  if not spec.get('centers') is Array or spec.centers.is_empty() or spec.centers.size()>16:return false
  for center in spec.centers:
   if not _point(center):return false
 if spec.shape=='line':
  if not _positive(spec.get('width')) or not _positive(spec.get('length')):return false
 else:
  if not _positive(spec.get('radius')):return false
 if spec.shape in ['fan','target_fan']:
  if not _positive(spec.get('degrees')) or spec.degrees>360:return false
 if spec.shape=='target_fan' and (not _point(spec.get('fan_origin')) or not spec.get('primary_target') is int or spec.primary_target<0):return false
 if not spec.get('impacts') is Array or spec.impacts.is_empty() or spec.impacts.size()>64:return false
 for impact in spec.impacts:
  if not impact is Dictionary or not impact.get('due') is int or impact.due<spec.cast_start_tick or not impact.get('hit') is Dictionary:return false
  var hit:Dictionary=impact.hit
  if hit.get('source')!=spec.source or hit.get('ability')!=spec.ability or hit.get('effect','') not in ['damage','heal']:return false
  var ratio:Variant=hit.get('ratio') if hit.effect=='heal' else hit.get('atk_ratio')
  if not _number(ratio) or ratio<0:return false
 if spec.has('falloff'):
  if not spec.falloff is Dictionary:return false
  for key in ['step','minimum']:
   if not _number(spec.falloff.get(key)) or spec.falloff[key]<0 or spec.falloff[key]>1:return false
 return true
func _point(value:Variant)->bool:return value is Vector2 and value.is_finite() and absf(value.x)<=10000 and absf(value.y)<=10000
func _number(value:Variant)->bool:return (value is int or value is float) and is_finite(float(value))
func _positive(value:Variant)->bool:return _number(value) and value>0 and value<=10000
static func outline(volume:Dictionary,actor_radius:float=UNIT_RADIUS)->Array:
 var result:Array=[]
 if volume.shape=='circle':
  for center in volume.centers:result.append(_circle_outline(center,volume.radius+actor_radius))
  return result
 var origin:Vector2=volume.get('fan_origin',volume.origin) if volume.shape=='target_fan' else volume.origin
 var direction:Vector2=volume.direction.normalized();var side:Vector2=direction.orthogonal()
 var polygon:=PackedVector2Array()
 if volume.shape=='line':
  var half:float=volume.width*0.5;var end:Vector2=origin+direction*volume.length
  polygon=PackedVector2Array([origin-side*half,end-side*half,end+side*half,origin+side*half])
 else:
  if volume.degrees>=359.999:return [_circle_outline(origin,volume.radius+actor_radius)]
  polygon.append(origin)
  var half:float=deg_to_rad(volume.degrees*0.5)
  for index in range(49):polygon.append(origin+direction.rotated(lerpf(-half,half,index/48.0))*volume.radius)
 if actor_radius<=0:return [polygon]
 return Geometry2D.offset_polygon(polygon,actor_radius,Geometry2D.JOIN_ROUND)
static func _circle_outline(center:Vector2,radius:float)->PackedVector2Array:
 var polygon:=PackedVector2Array()
 for index in range(96):polygon.append(center+Vector2.from_angle(TAU*index/96.0)*radius)
 return polygon
