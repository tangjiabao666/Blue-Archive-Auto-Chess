extends SceneTree

const Navigation = preload("res://core/obstacle_navigation.gd")
const MAP_IDS = ["open_plaza", "two_lane_street", "staggered_cover"]
const RADIUS := 0.35
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func run() -> void:
	var path := "res://core/tactical_maps.gd"
	check(ResourceLoader.exists(path), "tactical map provider exists")
	if not ResourceLoader.exists(path):
		finish()
		return
	var maps = load(path).new()
	check(maps.has_method("get_map"), "map provider exposes get_map")
	if not maps.has_method("get_map"):
		finish()
		return
	var layouts: Array = []
	for id in MAP_IDS:
		var map: Dictionary = maps.get_map(id)
		check(map.get("id") == id, id + ": stable preset id")
		check(not str(map.get("name", "")).is_empty(), id + ": display name exists")
		check(map.get("half_size") == 9.0, id + ": exactly 18x18 playable arena")
		var obstacles: Array = map.get("obstacles", [])
		check(obstacles.size() >= 6 and obstacles.size() <= 10, id + ": six to ten obstacles")
		check(not layouts.has(obstacles), id + ": distinct obstacle arrangement")
		layouts.append(obstacles.duplicate(true))
		var high := 0
		var low := 0
		for obstacle in obstacles:
			check(obstacle.get("rect") is Rect2, id + ": navigation-compatible rectangle")
			check(obstacle.get("blocks_projectiles") is bool, id + ": explicit cover height tag")
			var rect: Rect2 = obstacle.rect
			var reflected := Rect2(-rect.end, rect.size)
			check(obstacles.has({"rect": reflected, "blocks_projectiles": obstacle.blocks_projectiles}), id + ": exact point-reflection symmetry")
			if obstacle.blocks_projectiles:
				high += 1
			else:
				low += 1
		check(high > 0 and low > 0, id + ": both high and low cover")
		var nav = Navigation.new()
		check(nav.configure(map.half_size, obstacles) == "", id + ": valid non-overlapping in-bounds navigation")
		_test_deployment(map, nav, id)
		_test_routes(map, nav, id)
		_test_boundaries(map, nav, id)
		var copied: Dictionary = maps.get_map(id)
		copied.obstacles[0].rect = Rect2(0, 0, 1, 1)
		copied.deployment_regions[0] = Rect2()
		if copied.has("deployment_points"):
			copied.deployment_points[0][0] = Vector2.ZERO
		check(maps.get_map(id) == map, id + ": returned maps have independent nested data")
	check(maps.get_map("missing_preset").is_empty(), "unknown preset returns empty instead of changing the selected map")
	finish()

func _test_deployment(map: Dictionary, nav, id: String) -> void:
	var regions: Dictionary = map.get("deployment_regions", {})
	check(regions.has(0) and regions.has(1), id + ": regions explicitly keyed by team")
	if not regions.has(0) or not regions.has(1):
		return
	var player: Rect2 = regions[0]
	var enemy: Rect2 = regions[1]
	check(player.position.y >= RADIUS, id + ": player deploys only in own half")
	check(enemy == Rect2(-player.end, player.size), id + ": reflected deployment regions")
	check(player.position.x >= -9.0 + RADIUS and player.end.x <= 9.0 - RADIUS and player.end.y <= 9.0 - RADIUS, id + ": region leaves boundary clearance for unit radius")
	var spawns: Dictionary = map.get("deployment_points", {})
	check(spawns.has(0) and spawns.has(1), id + ": both teams have safe default deployment points")
	if spawns.has(0) and spawns.has(1):
		check(spawns[0].size() == 6 and spawns[1].size() == 6, id + ": six default deployment points per team")
		for index in range(spawns[0].size()):
			var point: Vector2 = spawns[0][index]
			check(spawns[1][index] == -point, id + ": default deployment points have exact point-reflection symmetry")
			check(player.has_point(point) and enemy.has_point(-point), id + ": suggested spawns are inside their own regions")
			check(nav.is_free(point, RADIUS) and nav.is_free(-point, RADIUS), id + ": suggested spawns have full obstacle clearance")
			for other in range(index):
				check(point.distance_to(spawns[0][other]) >= RADIUS * 2.0, id + ": suggested spawns cannot overlap")
	# Existing automatic deployment uses this row for populations four to six.
	for count in [4, 5, 6]:
		for index in range(count):
			var point := Vector2((index - (count - 1) * 0.5) * 1.6, 4.7)
			check(player.has_point(point), id + ": default player spawn belongs to deployment region")
			check(enemy.has_point(-point), id + ": default opponent spawn belongs to deployment region")
			check(nav.is_free(point, RADIUS) and nav.is_free(-point, RADIUS), id + ": default spawns have full radius clearance")
	for x in [-4.8, -3.2, -1.6, 0.0, 1.6, 3.2, 4.8]:
		check(nav.is_free(Vector2(x, 4.7), RADIUS), id + ": legacy fallback spawn row stays available")

func _test_routes(map: Dictionary, nav, id: String) -> void:
	# Three independent approach columns on each team's spawn row all reach
	# all opposite columns; route segments are checked as swept unit circles.
	for start_x in [-7.5, 0.0, 7.5]:
		for goal_x in [-7.5, 0.0, 7.5]:
			var point := Vector2(start_x, 7.5)
			var goal := Vector2(goal_x, -7.5)
			var route_length := 0.0
			for step in range(map.obstacles.size() * 4 + 2):
				if point.is_equal_approx(goal):
					break
				var next: Vector2 = nav.next_waypoint(point, goal, RADIUS)
				check(next != point, id + ": route progresses between spawn regions")
				if next == point:
					break
				check(nav.is_segment_free(point, next, RADIUS), id + ": every route segment respects cover and radius")
				route_length += point.distance_to(next)
				point = next
			check(point.is_equal_approx(goal), id + ": complete route reaches other team")
			check(route_length <= Vector2(start_x, 7.5).distance_to(goal) + 8.0, id + ": routes do not manufacture long travel time")

func _test_boundaries(map: Dictionary, nav, id: String) -> void:
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		check(nav.is_free(direction * (map.half_size - RADIUS), RADIUS), id + ": tangent outer boundary is legal")
		check(not nav.is_free(direction * (map.half_size - RADIUS + 0.001), RADIUS), id + ": unit radius cannot cross outer boundary")
		check(not nav.is_segment_free(Vector2.ZERO, direction * 10.0, RADIUS), id + ": swept route cannot exit arena")
	for obstacle in map.obstacles:
		var rect: Rect2 = obstacle.rect
		check(not nav.is_free(rect.get_center(), RADIUS), id + ": visual obstacle blocks occupancy")
		var left := Vector2(rect.position.x - RADIUS - 0.001, rect.get_center().y)
		var right := Vector2(rect.end.x + RADIUS + 0.001, rect.get_center().y)
		check(not nav.is_segment_free(left, right, RADIUS), id + ": high and low cover prevent tunnelling")

func finish() -> void:
	print("TACTICAL MAP CHECKS=", checks, " FAILURES=", failures)
	quit(1 if failures else 0)
