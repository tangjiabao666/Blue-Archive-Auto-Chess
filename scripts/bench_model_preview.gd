extends Node
## On-demand native model snapshots. One renderer serves every bench/drag tile.
## Add to the SceneTree, configure once, then reuse get_texture() on UI refreshes.
## A miss returns null; texture_ready supplies an independent, static ImageTexture.
signal texture_ready(character_id: String, star: int, size: Vector2i, texture: Texture2D)
signal texture_failed(character_id: String, star: int, size: Vector2i, reason: String)

const UnitView = preload("res://scripts/unit_view.gd")
const MAX_TEXTURE_SIZE := 1024
const IDLE_POSE_SECONDS := 0.4

var _profiles: Dictionary = {}
var _cache: Dictionary = {}
var _failed: Dictionary = {}
var _pending: Dictionary = {}
var _queue: Array[Dictionary] = []
var _active: Dictionary = {}
var _token := 0
var _pump_scheduled := false
var _disposed := false
var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _view: Node3D
var _draw_callback: Callable


func configure(profiles: Dictionary) -> void:
	clear()
	if not _disposed:
		_profiles = profiles.duplicate(true)


func get_texture(character_id: String, star: int, size: Vector2i) -> Texture2D:
	if _disposed or not _profiles.has(character_id) or star < 1 or size.x < 1 or size.y < 1:
		return null
	if size.x > MAX_TEXTURE_SIZE or size.y > MAX_TEXTURE_SIZE:
		return null
	var key := cache_key(character_id, star, size)
	if _cache.has(key):
		return _cache[key] as Texture2D
	if not _pending.has(key) and not _failed.has(key):
		_pending[key] = true
		_queue.append({"key": key, "character_id": character_id, "star": star, "size": size})
		_schedule_pump()
	return null


static func cache_key(character_id: String, star: int, size: Vector2i) -> String:
	return JSON.stringify([character_id, star, size.x, size.y])


func clear() -> void:
	_token += 1
	_disconnect_draw()
	_queue.clear()
	_pending.clear()
	_active.clear()
	_cache.clear()
	_failed.clear()
	_release_view()
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		remove_child(_viewport)
		_viewport.queue_free()
	_viewport = null
	_world = null
	_camera = null


func dispose() -> void:
	_disposed = true
	clear()
	_profiles.clear()


func diagnostics() -> Dictionary:
	return {"cached": _cache.size(), "queued": _queue.size(), "active": not _active.is_empty(), "failed": _failed.size(), "disposed": _disposed}


func _enter_tree() -> void:
	_schedule_pump()


func _exit_tree() -> void:
	clear()


func _schedule_pump() -> void:
	if not _pump_scheduled and not _disposed and is_inside_tree() and not _queue.is_empty():
		_pump_scheduled = true
		call_deferred("_pump")


func _pump() -> void:
	_pump_scheduled = false
	if _disposed or not is_inside_tree() or not _active.is_empty() or _queue.is_empty():
		return
	_active = _queue.pop_front()
	_token += 1
	_ensure_viewport()
	_viewport.size = _active.size
	_render_active(_token)


func _ensure_viewport() -> void:
	if is_instance_valid(_viewport):
		return
	_viewport = SubViewport.new()
	_viewport.name = "BenchModelRenderViewport"
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.TRANSPARENT
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.65
	environment_node.environment = environment
	_world.add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -25, 0)
	light.light_energy = 0.65
	_world.add_child(light)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.near = 0.01
	_camera.far = 100.0
	_world.add_child(_camera)
	_camera.current = true


func _render_active(token: int) -> void:
	# The dummy headless renderer never emits a useful GPU frame. Never await it.
	if DisplayServer.get_name() == "headless":
		_finish_render(token, null, "renderer_unavailable")
		return
	if not _prepare_model():
		_finish_render(token, null, "model_unavailable")
		return
	_request_draw(token, 2)


func _prepare_model() -> bool:
	var profile: Dictionary = _profiles.get(_active.character_id, {})
	var path := String(profile.get("model_path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return false
	_release_view()
	_view = UnitView.new()
	_view.name = "BenchModelPose"
	_world.add_child(_view)
	var unit := {"id": 0, "character_id": _active.character_id, "star": _active.star, "team": 0, "cell": Vector2.ZERO, "range": 1.0, "presentation": profile}
	_view.setup(unit, {}, _token)
	if not is_instance_valid(_view._model) or not is_instance_valid(_view.player):
		return false
	_view.update_time(IDLE_POSE_SECONDS, unit)
	if is_instance_valid(_view._disk):
		_view._disk.visible = false
	if is_instance_valid(_view._range_indicator):
		_view._range_indicator.visible = false
	# Animation is sought once, with no battle clock, VFX or permanent name labels.
	_view.process_mode = Node.PROCESS_MODE_DISABLED
	_frame_model()
	return true


func _frame_model() -> void:
	var corners: Array[Vector3] = []
	var bounds := AABB()
	for mesh in _view._model.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or mesh.mesh == null:
			continue
		var local: AABB = mesh.get_aabb()
		for corner in range(8):
			var point: Vector3 = mesh.global_transform * local.get_endpoint(corner)
			bounds = AABB(point, Vector3.ZERO) if corners.is_empty() else bounds.expand(point)
			corners.append(point)
	if corners.is_empty():
		bounds = AABB(Vector3(-0.7, 0, -0.4), Vector3(1.4, 2.4, 0.8))
		for corner in range(8):
			corners.append(bounds.get_endpoint(corner))
	var focus := bounds.get_center()
	# Front three-quarter view frames visible mesh bounds, including weapon/halo.
	# Mesh AABBs approximate skinned poses; native tile QA must check extremities.
	_camera.position = focus + Vector3(3.8, 1.6, -6.0)
	_camera.look_at(focus)
	var to_camera := _camera.global_transform.affine_inverse()
	var half_width := 0.0
	var half_height := 0.0
	for point in corners:
		var projected: Vector3 = to_camera * point
		half_width = maxf(half_width, absf(projected.x))
		half_height = maxf(half_height, absf(projected.y))
	var aspect := float(_viewport.size.x) / float(_viewport.size.y)
	_camera.size = maxf(0.1, maxf(half_height, half_width / aspect) * 2.0 * 1.12)


func _request_draw(token: int, frames_left: int) -> void:
	_disconnect_draw()
	# All scene mutation and ImageTexture construction stay on the main thread.
	# Deferring the render-server signal avoids executing Node work on its thread.
	_draw_callback = _on_frame_drawn.bind(token, frames_left)
	RenderingServer.frame_post_draw.connect(_draw_callback, CONNECT_ONE_SHOT | CONNECT_DEFERRED)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _on_frame_drawn(token: int, frames_left: int) -> void:
	if token != _token or _disposed or _active.is_empty() or not is_instance_valid(_viewport):
		return
	_draw_callback = Callable()
	if frames_left > 1:
		_request_draw(token, frames_left - 1)
		return
	var image: Image = _viewport.get_texture().get_image()
	_finish_render(token, image, "readback_unavailable")


func _finish_render(token: int, image: Image, reason: String = "readback_unavailable") -> void:
	if token != _token or _disposed or _active.is_empty():
		return
	_disconnect_draw()
	var request := _active
	_active = {}
	_pending.erase(request.key)
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_release_view()
	if image == null or image.is_empty() or image.get_size() != request.size:
		_failed[request.key] = reason
		texture_failed.emit(request.character_id, request.star, request.size, reason)
	else:
		# Never expose the shared ViewportTexture, whose pixels change next job.
		var texture := ImageTexture.create_from_image(image)
		_cache[request.key] = texture
		texture_ready.emit(request.character_id, request.star, request.size, texture)
	_schedule_pump()


func _disconnect_draw() -> void:
	if _draw_callback.is_valid() and RenderingServer.frame_post_draw.is_connected(_draw_callback):
		RenderingServer.frame_post_draw.disconnect(_draw_callback)
	_draw_callback = Callable()


func _release_view() -> void:
	if is_instance_valid(_view):
		_view.get_parent().remove_child(_view)
		_view.queue_free()
	_view = null
