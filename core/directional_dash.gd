extends RefCounted
## Deterministic swept-circle legal prefix. No RNG or mutable simulation state.
## Static adapters must implement pure, prefix-monotone occupancy/sweep queries.
static func legal_prefix(origin: Vector2, destination: Vector2, actor_id: int,
 actors: Array, arena_half: float, radius: float,
 position_free: Callable=Callable(), segment_free: Callable=Callable()) -> Vector2:
 if not origin.is_finite() or not destination.is_finite(): return origin
 if not is_finite(arena_half) or not is_finite(radius) or radius <= 0.0 or arena_half <= radius: return origin
 if not _legal(origin,origin,actor_id,actors,arena_half,radius,position_free,segment_free): return origin
 if _legal(origin,destination,actor_id,actors,arena_half,radius,position_free,segment_free): return destination
 var low := 0.0
 var high := 1.0
 for iteration in range(16):
  var middle := (low+high)*0.5
  if _legal(origin,origin.lerp(destination,middle),actor_id,actors,arena_half,radius,position_free,segment_free): low=middle
  else: high=middle
 return origin.lerp(destination,low)

static func _legal(origin: Vector2, point: Vector2, actor_id: int, actors: Array,
 arena_half: float, radius: float, position_free: Callable, segment_free: Callable) -> bool:
 var limit := arena_half-radius
 if absf(point.x)>limit or absf(point.y)>limit: return false
 if position_free.is_valid() and not position_free.call(point,radius): return false
 if segment_free.is_valid() and not segment_free.call(origin,point,radius): return false
 # Scalar float intermediates avoid Vector2's float32 projection rounding at tangency.
 var dx:float=float(point.x)-float(origin.x)
 var dy:float=float(point.y)-float(origin.y)
 var length_sq:float=dx*dx+dy*dy
 for other in actors:
  if other.id==actor_id or other.hp<=0: continue
  var center:Vector2=other.cell
  var cx:float=float(center.x)-float(origin.x)
  var cy:float=float(center.y)-float(origin.y)
  var along:float=clampf((cx*dx+cy*dy)/length_sq,0.0,1.0) if length_sq>0.0 else 0.0
  var ex:float=cx-dx*along
  var ey:float=cy-dy*along
  if ex*ex+ey*ey<pow(radius*2.0-0.000001,2): return false
 return true
