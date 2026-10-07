extends SceneTree

const Maps = preload("res://core/tactical_maps.gd")
const LegacyArena = preload("res://core/combat_arena_hooks.gd")
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
	var environment = load("res://scripts/arena_environment.gd").new()
	root.add_child(environment)
	var supports_half_size := false
	for method in environment.get_method_list():
		if method.name == "configure":
			supports_half_size = method.args.size() == 2 and method.default_args.size() == 1
	check(supports_half_size, "environment supports explicit half-size with legacy default")
	if not supports_half_size:
		environment.queue_free()
		await process_frame
		finish()
		return
	environment.configure(LegacyArena.OBSTACLES)
	var legacy_geometry := geometry_signature(environment)
	check(environment.get_meta("playable_bounds") == Rect2(-6.6, -6.6, 13.2, 13.2), "omitting size retains legacy bounds")
	var maps = Maps.new()
	for id in Maps.MAP_IDS:
		var map: Dictionary = maps.get_map(id)
		var original := map.duplicate(true)
		environment.configure(map.obstacles, map.half_size)
		check(environment.get_meta("playable_bounds") == Rect2(-9, -9, 18, 18), id + ": exact 18x18 metadata")
		var floor: MeshInstance3D = environment.get_node("Ground/PlayableSurface")
		var bounds := floor.transform * floor.get_aabb()
		check(bounds.position.is_equal_approx(Vector3(-9, -0.09, -9)), id + ": physical mesh has exact ground extent")
		check(bounds.size.is_equal_approx(Vector3(18, 0.09, 18)), id + ": floor stays at y=0")
		var covers: Node3D = environment.get_node("Cover")
		check(covers.get_child_count() == map.obstacles.size(), id + ": one visible cover per navigation obstacle")
		for index in range(map.obstacles.size()):
			var obstacle: Dictionary = map.obstacles[index]
			var rect: Rect2 = obstacle.rect
			var cover: Node3D = covers.get_child(index)
			var cover_bounds := mesh_bounds(cover)
			check(cover.get_meta("rect") == rect, id + ": visible and navigation footprints share coordinates")
			check(cover.get_meta("blocks_projectiles") == obstacle.blocks_projectiles, id + ": visible high/low tag matches navigation")
			check(cover_bounds.position.is_equal_approx(Vector3(rect.position.x, 0, rect.position.y)), id + ": visible cover starts on exact footprint")
			check(cover_bounds.size.is_equal_approx(Vector3(rect.size.x, 1.05 if obstacle.blocks_projectiles else 0.42, rect.size.y)), id + ": visible cover footprint and high/low height are exact")
		for scenery in environment.get_node("Scenery").get_children():
			var scenery_bounds := mesh_bounds(scenery)
			check(scenery_bounds.end.x <= -9 or scenery_bounds.position.x >= 9 or scenery_bounds.end.z <= -9 or scenery_bounds.position.z >= 9, id + ": scenery stays outside expanded gameplay")
			check(not (scenery_bounds.position.x < 0 and scenery_bounds.end.z > 0 and scenery_bounds.size.y > 0.15), id + ": expanded foreground stays low")
		var repeated := geometry_signature(environment)
		environment.configure(map.obstacles, map.half_size)
		check(geometry_signature(environment) == repeated, id + ": repeated map configure keeps identical mesh geometry")
		check(map == original, id + ": rendering never mutates authoritative map data")
		check(physics_node_count(environment) == 0, id + ": renderer owns no competing collision")
		environment.configure(LegacyArena.OBSTACLES)
		check(geometry_signature(environment) == legacy_geometry, id + ": legacy rendering restored without leaked scale or nodes")
		check(environment.get_node("Cover").get_child_count() == 4, id + ": legacy four-obstacle layout restored")
	environment.queue_free()
	await process_frame
	finish()

func mesh_bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for child in node.get_children():
		if child is MeshInstance3D:
			var bounds: AABB = child.transform * child.get_aabb()
			result = bounds if first else result.merge(bounds)
			first = false
	return result

func geometry_signature(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D:
		result.append([node.name, node.transform, node.mesh.get_surface_count()])
		for index in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(index)
			result.append([arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL]])
	for child in node.get_children():
		result.append(geometry_signature(child))
	return result

func physics_node_count(node: Node) -> int:
	var count := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children():
		count += physics_node_count(child)
	return count

func finish() -> void:
	print("TACTICAL MAP ENVIRONMENT CHECKS=", checks, " FAILURES=", failures)
	quit(1 if failures else 0)
