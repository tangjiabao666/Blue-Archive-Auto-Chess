extends RefCounted

## Pure static obstacle queries. Coordinates are continuous world-space Vector2s.
## A rectangle blocks movement regardless of its blocks_projectiles flag.
const EPSILON := 0.000001
const WAYPOINT_MARGIN := 0.001

var _half_size := 0.0
var _obstacles: Array = []
var _graph_radius := -1.0
var _vertices: Array[Vector2] = []
var _edges: Array = []
var _crowd_paths: Dictionary = {}

## Returns the next visibility-graph waypoint; returns a if no route exists.
## Callers must move toward this point at their own speed, not assign it directly.
## Dynamic actors are intentionally excluded: the caller owns their collision.
func next_waypoint(a: Vector2, b: Vector2, radius: float) -> Vector2:
	if not is_free(a, radius) or not is_free(b, radius):
		return a
	if is_segment_free(a, b, radius):
		return b
	_prepare_graph(radius)
	var size := _vertices.size() + 2
	var points: Array[Vector2] = [a, b]
	points.append_array(_vertices)
	var distances: Array[float] = []
	var previous: Array[int] = []
	var visited: Array[bool] = []
	var from_start: Array[bool] = []
	var to_goal: Array[bool] = []
	distances.resize(size)
	distances.fill(INF)
	previous.resize(size)
	previous.fill(-1)
	visited.resize(size)
	visited.fill(false)
	for point in _vertices:
		from_start.append(is_segment_free(a, point, radius))
		to_goal.append(is_segment_free(point, b, radius))
	distances[0] = 0.0
	for iteration in range(size):
		var current := -1
		var nearest := INF
		# Stable canonical vertex order breaks equal-distance ties deterministically.
		for index in range(size):
			if not visited[index] and distances[index] < nearest:
				current = index
				nearest = distances[index]
		if current < 0:
			return a
		if current == 1:
			var next := 1
			while previous[next] > 0:
				next = previous[next]
			return points[next] if previous[next] == 0 else a
		visited[current] = true
		var neighbors: Array = []
		if current == 0:
			for vertex_index in range(_vertices.size()):
				if from_start[vertex_index]:
					neighbors.append(vertex_index + 2)
		else:
			if to_goal[current - 2]:
				neighbors.append(1)
			for neighbor in _edges[current - 2]:
				neighbors.append(neighbor + 2)
		for neighbor in neighbors:
			var candidate: float = distances[current] + points[current].distance_to(points[neighbor])
			if not visited[neighbor] and candidate < distances[neighbor]:
				distances[neighbor] = candidate
				previous[neighbor] = current
	return a

## A static corner can be occupied by a live actor. Replan through a small
## visibility graph around actor discs instead of insisting that every step
## get closer to that occupied corner. Canonical node order breaks ties.
func next_crowd_waypoint(a: Vector2, b: Vector2, radius: float, blockers: Array, route_id: int = -1, route_tick: int = -1) -> Vector2:
	if blockers.is_empty():
		return next_waypoint(a, b, radius)
	if not is_free(a, radius) or not is_free(b, radius):
		return a
	# Reuse only consecutive-tick routes toward the identical destination.
	# Revalidate the complete next segment against current actor positions;
	# stale, changed, reset or newly blocked routes are rebuilt immediately.
	var cached: Dictionary = _crowd_paths.get(route_id, {}) if route_id >= 0 else {}
	if not cached.is_empty() and cached.tick == route_tick - 1 and cached.goal == b and cached.radius == radius:
		var route: Array = cached.points
		while not route.is_empty() and a.distance_to(route[0]) < 0.0001:
			route.pop_front()
		if not route.is_empty() and is_crowd_segment_free(a, route[0], radius, blockers):
			cached.tick = route_tick
			return route[0]
	_crowd_paths.erase(route_id)
	if is_crowd_segment_free(a, b, radius, blockers):
		return b
	_prepare_graph(radius)
	var points: Array[Vector2] = [a, b]
	for vertex in _vertices:
		if is_crowd_segment_free(vertex, vertex, radius, blockers):
			points.append(vertex)
	# Circumscribed polygon: adjacent edges remain outside the combined
	# actor radius, rather than cutting through the occupied circular area.
	var sides := 12
	var ring := (radius * 2.0 + WAYPOINT_MARGIN) / cos(PI / sides)
	for center in blockers:
		for index in range(sides):
			var point: Vector2 = center + Vector2.from_angle(TAU * index / sides) * ring
			if is_crowd_segment_free(point, point, radius, blockers):
				points.append(point)
	var distances: Array[float] = []
	var previous: Array[int] = []
	var visited: Array[bool] = []
	distances.resize(points.size()); distances.fill(INF)
	previous.resize(points.size()); previous.fill(-1)
	visited.resize(points.size()); visited.fill(false)
	distances[0] = 0.0
	for iteration in range(points.size()):
		var current := -1
		var nearest := INF
		for index in range(points.size()):
			# Euclidean remaining distance is an admissible A* heuristic.
			var estimate := distances[index] + points[index].distance_to(b)
			if not visited[index] and estimate < nearest:
				current = index
				nearest = estimate
		if current < 0:
			return a
		if current == 1:
			var route: Array = []
			var next := 1
			while next > 0:
				route.push_front(points[next])
				next = previous[next]
			if next != 0 or route.is_empty():
				return a
			if route_id >= 0:
				_crowd_paths[route_id] = {"tick": route_tick, "goal": b, "radius": radius, "points": route}
			return route[0]
		visited[current] = true
		for neighbor in range(points.size()):
			if visited[neighbor]:
				continue
			var candidate := distances[current] + points[current].distance_to(points[neighbor])
			if candidate < distances[neighbor] and is_crowd_segment_free(points[current], points[neighbor], radius, blockers):
				distances[neighbor] = candidate
				previous[neighbor] = current
	return a

func is_crowd_segment_free(a: Vector2, b: Vector2, radius: float, blockers: Array) -> bool:
	if not is_segment_free(a, b, radius):
		return false
	var clearance := maxf(0.0, radius * 2.0 - EPSILON)
	for center in blockers:
		if _point_segment_distance_squared(center, a, b) < clearance * clearance:
			return false
	return true

func _prepare_graph(radius: float) -> void:
	if radius == _graph_radius:
		return
	_vertices.clear()
	_edges.clear()
	for obstacle in _obstacles:
		var rect: Rect2 = obstacle.rect
		var expanded := rect.grow(radius + WAYPOINT_MARGIN)
		var exact := rect.grow(radius)
		var corners := [expanded.position, Vector2(expanded.end.x, expanded.position.y), expanded.end, Vector2(expanded.position.x, expanded.end.y)]
		var exact_corners := [exact.position, Vector2(exact.end.x, exact.position.y), exact.end, Vector2(exact.position.x, exact.end.y)]
		for corner_index in range(4):
			var corner: Vector2 = corners[corner_index]
			# Prefer a tiny steering margin, but retain exactly tangent corridors.
			if not is_free(corner, radius):
				corner = exact_corners[corner_index]
			if is_free(corner, radius) and not _vertices.has(corner):
				_vertices.append(corner)
	for index in range(_vertices.size()):
		_edges.append([])
	for first in range(_vertices.size()):
		for second in range(first + 1, _vertices.size()):
			if is_segment_free(_vertices[first], _vertices[second], radius):
				_edges[first].append(second)
				_edges[second].append(first)
	_graph_radius = radius

## Tests the complete swept circle, not just its destination; prevents tunnelling.
func is_segment_free(a: Vector2, b: Vector2, radius: float) -> bool:
	if not is_free(a, radius) or not is_free(b, radius):
		return false
	var low: Vector2 = a.min(b)
	var high: Vector2 = a.max(b)
	var clearance := maxf(0.0, radius - EPSILON)
	for obstacle in _obstacles:
		var rect: Rect2 = obstacle.rect
		# Conservative broad phase: only skip rectangles outside the complete
		# swept segment bounds. Tangencies still use the unchanged exact tests.
		if high.x < rect.position.x - radius or low.x > rect.end.x + radius or high.y < rect.position.y - radius or low.y > rect.end.y + radius:
			continue
		if _segment_hits_rect(a, b, rect):
			return false
		if _segment_rect_distance_squared(a, b, rect) < clearance * clearance:
			return false
	return true

## High obstacles block even tangent shots; low obstacles only block movement.
func has_line_of_sight(a: Vector2, b: Vector2) -> bool:
	if not _inside_arena(a, 0.0) or not _inside_arena(b, 0.0):
		return false
	for obstacle in _obstacles:
		if obstacle.blocks_projectiles and _segment_hits_rect(a, b, obstacle.rect):
			return false
	return true

## Returns an error string, or "" on success. Invalid input leaves prior state intact.
func configure(half_size: float, obstacles: Array) -> String:
	if not is_finite(half_size) or half_size <= 0.0:
		return "half size must be finite and positive"
	var proposed: Array = []
	for raw in obstacles:
		if not raw is Dictionary or not raw.get("rect") is Rect2:
			return "obstacle must contain a Rect2 rect"
		var rect: Rect2 = raw.rect
		if not rect.position.is_finite() or not rect.size.is_finite() or not rect.end.is_finite():
			return "obstacle coordinates must be finite"
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return "obstacle size must be positive"
		if rect.position.x < -half_size or rect.position.y < -half_size or rect.end.x > half_size or rect.end.y > half_size:
			return "obstacle must be inside arena"
		if not raw.get("blocks_projectiles", true) is bool:
			return "blocks_projectiles must be boolean"
		for other in proposed:
			if rect.intersects(other.rect):
				return "obstacles must not overlap"
		proposed.append({"rect": rect, "blocks_projectiles": raw.get("blocks_projectiles", true)})
	proposed.sort_custom(_obstacle_less)
	_half_size = half_size
	_obstacles = proposed
	_crowd_paths.clear()
	_graph_radius = -1.0
	_vertices.clear()
	_edges.clear()
	return ""

## Tangent contact is permitted; overlap is not. The epsilon is numerical only.
func is_free(point: Vector2, radius: float) -> bool:
	if not _inside_arena(point, radius):
		return false
	var clearance := maxf(0.0, radius - EPSILON)
	for obstacle in _obstacles:
		var rect: Rect2 = obstacle.rect
		if _inside_open(point, rect) or _point_rect_distance_squared(point, rect) < clearance * clearance:
			return false
	return true

func _valid_query(point: Vector2, radius: float) -> bool:
	return _half_size > 0.0 and point.is_finite() and is_finite(radius) and radius >= 0.0

func _inside_arena(point: Vector2, radius: float) -> bool:
	return _valid_query(point, radius) and absf(point.x) + radius <= _half_size + EPSILON and absf(point.y) + radius <= _half_size + EPSILON

func _inside_open(point: Vector2, rect: Rect2) -> bool:
	return point.x > rect.position.x and point.x < rect.end.x and point.y > rect.position.y and point.y < rect.end.y

func _point_rect_distance_squared(point: Vector2, rect: Rect2) -> float:
	var closest := Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
	return point.distance_squared_to(closest)

func _segment_hits_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	var entry := 0.0
	var leave := 1.0
	var delta := b - a
	for axis in range(2):
		if delta[axis] == 0.0:
			if a[axis] < rect.position[axis] or a[axis] > rect.end[axis]:
				return false
		else:
			var near := (rect.position[axis] - a[axis]) / delta[axis]
			var far := (rect.end[axis] - a[axis]) / delta[axis]
			entry = maxf(entry, minf(near, far))
			leave = minf(leave, maxf(near, far))
			if entry > leave:
				return false
	return true

func _segment_rect_distance_squared(a: Vector2, b: Vector2, rect: Rect2) -> float:
	# Called only after an intersection test. For disjoint convex segment/box,
	# a closest pair includes either a segment endpoint or a rectangle corner.
	var result := minf(_point_rect_distance_squared(a, rect), _point_rect_distance_squared(b, rect))
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		result = minf(result, _point_segment_distance_squared(corner, a, b))
	return result

func _point_segment_distance_squared(point: Vector2, a: Vector2, b: Vector2) -> float:
	var delta := b - a
	var length_squared := delta.length_squared()
	if length_squared == 0.0:
		return point.distance_squared_to(a)
	var fraction := clampf((point - a).dot(delta) / length_squared, 0.0, 1.0)
	return point.distance_squared_to(a + delta * fraction)

func _obstacle_less(a: Dictionary, b: Dictionary) -> bool:
	var first: Rect2 = a.rect
	var second: Rect2 = b.rect
	for values in [[first.position.x, second.position.x], [first.position.y, second.position.y], [first.size.x, second.size.x], [first.size.y, second.size.y]]:
		if values[0] != values[1]:
			return values[0] < values[1]
	return int(a.blocks_projectiles) < int(b.blocks_projectiles)
