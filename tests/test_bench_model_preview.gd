extends SceneTree
## Tests the real cache, queue and lifecycle with only GPU readback held at a seam.
## This does not certify native pixel quality or small-tile framing.
class HeldPreview:
	extends "res://scripts/bench_model_preview.gd"
	var started: Array[int] = []
	func _render_active(token: int) -> void:
		started.append(token)

var checks := 0
var failures := 0

func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	call_deferred("run")

func colored_image(size: Vector2i, color: Color) -> Image:
	var result := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	result.fill(color)
	return result

func run() -> void:
	var preview = HeldPreview.new()
	root.add_child(preview)
	ck(preview.has_method("get_texture"), "cache exposes asynchronous texture requests")
	if failures:
		preview.free()
		quit(1)
		return
	var profiles: Dictionary = {"yuuka": {"model_path": "native.glb"}, "shiroko": {"model_path": "other.glb"}}
	preview.configure(profiles)
	profiles.yuuka.model_path = "caller mutation"
	ck(preview._profiles.yuuka.model_path == "native.glb", "configure copies caller profiles")
	var size := Vector2i(96, 112)
	var ready: Array = []
	preview.texture_ready.connect(func(character, star, dimensions, texture): ready.append([character, star, dimensions, texture]))
	ck(preview.get_texture("missing", 1, size) == null, "unknown character returns no texture")
	ck(preview.get_texture("yuuka", 0, size) == null, "invalid star returns no texture")
	ck(preview.get_texture("yuuka", 1, Vector2i.ZERO) == null, "empty size returns no texture")
	ck(preview.get_texture("yuuka", 1, Vector2i(2048, 2048)) == null, "oversized render is rejected")
	ck(preview.diagnostics().queued == 0, "invalid requests create no jobs")
	ck(preview.get_texture("yuuka", 1, size) == null, "first request waits for render")
	preview.get_texture("yuuka", 1, size)
	preview.get_texture("shiroko", 1, size)
	ck(preview.diagnostics().queued == 2, "duplicate requests share one queued job")
	await process_frame
	ck(preview.started.size() == 1 and preview.diagnostics().queued == 1, "only first queued render starts")
	ck(preview.find_children("*", "SubViewport", true, false).size() == 1, "all jobs share exactly one viewport")
	var viewport: SubViewport = preview._viewport
	ck(viewport.transparent_bg and viewport.own_world_3d, "preview has isolated transparent world")
	ck(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "viewport is not continuously rendering")
	var first_token: int = preview.started[0]
	preview.get_texture("yuuka", 1, size)
	ck(preview.diagnostics().queued == 1, "active request is also deduplicated")
	var pixels := colored_image(size, Color.RED)
	preview._finish_render(first_token, pixels)
	ck(ready.size() == 1 and ready[0].slice(0, 3) == ["yuuka", 1, size], "ready identifies exact character, star and dimensions")
	var first: Texture2D = preview.get_texture("yuuka", 1, size)
	ck(first is ImageTexture and not first is ViewportTexture, "cache stores detached ImageTexture")
	ck(first == ready[0][3] and first.get_size() == Vector2(size), "cache returns same correctly sized texture")
	pixels.fill(Color.BLUE)
	ck(first.get_image().get_pixel(0, 0) == Color.RED, "cached texture does not alias mutable readback image")
	await process_frame
	ck(preview.started.size() == 2 and preview._viewport == viewport, "next job reuses same viewport")
	preview._finish_render(preview.started[1], colored_image(size, Color.GREEN))
	var second: Texture2D = preview.get_texture("shiroko", 1, size)
	ck(second != first and first.get_image().get_pixel(0, 0) == Color.RED, "later readback cannot replace earlier character pixels")
	preview.get_texture("yuuka", 2, size)
	preview.get_texture("yuuka", 1, Vector2i(128, 128))
	ck(preview.diagnostics().queued == 2, "star and size are distinct cache keys")
	await process_frame
	var cancelled_token: int = preview.started.back()
	preview._request_draw(cancelled_token, 2)
	var cancelled_callback: Callable = preview._draw_callback
	ck(RenderingServer.frame_post_draw.is_connected(cancelled_callback), "active render connects a draw callback")
	preview.clear()
	ck(not RenderingServer.frame_post_draw.is_connected(cancelled_callback), "clear disconnects pending renderer callback")
	preview._on_frame_drawn(cancelled_token, 1)
	ck(preview.diagnostics().cached == 0 and preview.diagnostics().queued == 0 and not preview.diagnostics().active, "clear cancels jobs and drops cache")
	ck(preview.find_children("*", "SubViewport", true, false).is_empty(), "clear detaches render resources immediately")
	preview._finish_render(cancelled_token, colored_image(size, Color.BLUE))
	ck(ready.size() == 2 and preview.diagnostics().cached == 0, "late completion cannot restore cleared data or emit ready")
	preview.get_texture("yuuka", 1, size)
	await process_frame
	var next_token: int = preview.started.back()
	preview._finish_render(cancelled_token, colored_image(size, Color.BLUE))
	ck(preview.diagnostics().active and preview.diagnostics().cached == 0, "old completion cannot finish newer active job")
	preview._finish_render(next_token, colored_image(size, Color.YELLOW))
	ck(preview.get_texture("yuuka", 1, size).get_image().get_pixel(0, 0) == Color.YELLOW, "new request after clear succeeds")
	preview.configure({"shiroko": {"model_path": "updated.glb"}})
	ck(preview.get_texture("yuuka", 1, size) == null and preview.diagnostics().cached == 0, "reconfigure invalidates cache and removed profiles")
	preview.get_texture("shiroko", 1, size)
	await process_frame
	var disposed_token: int = preview.started.back()
	preview.dispose()
	preview._finish_render(disposed_token, colored_image(size, Color.BLUE))
	ck(preview.get_texture("shiroko", 1, size) == null and preview.diagnostics().queued == 0, "disposed component rejects new and stale jobs")
	preview.dispose()
	preview.free()
	await process_frame
	ck(not is_instance_valid(viewport), "retired viewport is freed")

	var lifecycle = HeldPreview.new()
	root.add_child(lifecycle)
	lifecycle.configure({"yuuka": {"model_path": "native.glb"}})
	lifecycle.get_texture("yuuka", 1, size)
	await process_frame
	var detached_token: int = lifecycle.started.back()
	root.remove_child(lifecycle)
	ck(lifecycle.diagnostics().queued == 0 and not lifecycle.diagnostics().active, "leaving scene tree cancels active render")
	lifecycle._finish_render(detached_token, colored_image(size, Color.RED))
	root.add_child(lifecycle)
	lifecycle.get_texture("yuuka", 1, size)
	await process_frame
	ck(lifecycle.diagnostics().active and lifecycle.started.size() == 2, "reattached service can serve a fresh request")
	lifecycle.free()
	await process_frame

	var native = HeldPreview.new()
	root.add_child(native)
	var native_profiles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	native.configure(native_profiles)
	for character in ["yuuka", "tsubaki"]:
		native.get_texture(character, 1, size)
		await process_frame
		ck(native._prepare_model(), character + " builds existing native model and idle pose")
		ck(native._view.process_mode == Node.PROCESS_MODE_DISABLED and is_equal_approx(native._view.player.current_animation_position, 0.4), character + " pose is frozen at selected idle time")
		ck(not native._view._disk.visible and not native._view._range_indicator.visible, character + " excludes battle selection geometry")
		ck(native.find_children("*", "Label3D", true, false).is_empty(), character + " has no permanent name")
		ck(native._camera.size > 0 and native._camera.position.x > 0, character + " has full-body orthographic three-quarter framing")
		var fits := true
		for mesh in native._view._model.find_children("*", "MeshInstance3D", true, false):
			if not mesh.is_visible_in_tree() or mesh.mesh == null:
				continue
			for corner in range(8):
				var point: Vector3 = mesh.global_transform * mesh.get_aabb().get_endpoint(corner)
				var screen: Vector2 = native._camera.unproject_position(point)
				fits = fits and Rect2(Vector2.ZERO, Vector2(size)).has_point(screen)
		ck(fits, character + " visible mesh resource bounds fit inside requested tile")
		native._finish_render(native.started.back(), colored_image(size, Color.RED))
		ck(native._view == null, character + " releases live model after static texture capture")
	native.free()
	await process_frame

	var component = load("res://scripts/bench_model_preview.gd").new()
	root.add_child(component)
	component.configure({"yuuka": {"model_path": "unused-in-headless.glb"}})
	var errors: Array = []
	component.texture_failed.connect(func(character, star, dimensions, reason): errors.append([character, star, dimensions, reason]))
	component.get_texture("yuuka", 1, size)
	for i in range(4):
		await process_frame
	ck(errors.size() == 1 and errors[0][3] == "renderer_unavailable", "headless renderer reports unavailable without awaiting draw")
	ck(not component.diagnostics().active and component.diagnostics().queued == 0, "headless failure drains queue")
	component.get_texture("yuuka", 1, size)
	await process_frame
	ck(errors.size() == 1, "failed readback is not retried on each UI refresh")
	component.free()
	await process_frame
	print("BENCH_MODEL_PREVIEW ", checks, " checks; ", failures, " failures; native pixels NOT checked")
	quit(1 if failures else 0)
