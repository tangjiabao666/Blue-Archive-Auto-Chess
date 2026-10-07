extends RefCounted
## Pure terrain presets shared by tactical navigation, deployment and visuals.
## Unit centers still need navigation.is_free(point, radius) inside a region.
## Presets use binary-exact coordinates so reflection preserves exact footprints.
const HALF_SIZE := 9.0
const DEFAULT_ID := "open_plaza"
const MAP_IDS := ["open_plaza", "two_lane_street", "staggered_cover"]

func get_map(id: String) -> Dictionary:
	var name: String
	var half: Array
	match id:
		"open_plaza":
			name = "开放广场"
			# Peripheral cover leaves the center open for short approach routes.
			half = [
				{"rect": Rect2(-5.75, -2.5, 0.75, 2.0), "blocks_projectiles": true},
				{"rect": Rect2(-3.5, -1.75, 2.0, 0.5), "blocks_projectiles": false},
				{"rect": Rect2(4.75, -3.25, 0.75, 1.5), "blocks_projectiles": true},
				{"rect": Rect2(1.75, -3.75, 2.0, 0.5), "blocks_projectiles": false},
			]
		"two_lane_street":
			name = "双通道街区"
			# A central divider makes two broad lanes; both ends remain open.
			half = [
				{"rect": Rect2(-0.5, -3.75, 1.0, 3.5), "blocks_projectiles": true},
				{"rect": Rect2(-6.0, -2.5, 1.0, 2.0), "blocks_projectiles": true},
				{"rect": Rect2(1.75, -3.0, 2.0, 0.5), "blocks_projectiles": false},
				{"rect": Rect2(-3.75, -1.0, 2.0, 0.5), "blocks_projectiles": false},
			]
		"staggered_cover":
			name = "错位掩体区"
			# Alternating short cover pieces allow diagonal and flanking routes.
			half = [
				{"rect": Rect2(-5.75, -3.5, 1.75, 0.5), "blocks_projectiles": false},
				{"rect": Rect2(-3.0, -2.75, 0.75, 1.5), "blocks_projectiles": true},
				{"rect": Rect2(-1.0, -3.75, 2.0, 0.5), "blocks_projectiles": false},
				{"rect": Rect2(1.5, -1.5, 1.75, 0.5), "blocks_projectiles": false},
				{"rect": Rect2(4.75, -2.75, 0.75, 1.5), "blocks_projectiles": true},
			]
		_:
			return {}
	var obstacles: Array = []
	for obstacle in half:
		var rect: Rect2 = obstacle.rect
		obstacles.append(obstacle)
		obstacles.append({"rect": Rect2(-rect.end, rect.size), "blocks_projectiles": obstacle.blocks_projectiles})
	# Slightly inside the 0.35-radius limit; exact eighths avoid rounding a
	# displayed legal region onto an illegal navigation boundary.
	var player := Rect2(-8.625, 0.375, 17.25, 8.25)
	var player_points: Array[Vector2] = []
	var enemy_points: Array[Vector2] = []
	for x in [-4.0, -2.4, -0.8, 0.8, 2.4, 4.0]:
		var point := Vector2(x, 4.7)
		player_points.append(point)
		enemy_points.append(-point)
	return {
		"id": id,
		"name": name,
		"half_size": HALF_SIZE,
		"obstacles": obstacles,
		"deployment_regions": {0: player, 1: Rect2(-player.end, player.size)},
		"deployment_points": {0: player_points, 1: enemy_points},
	}
