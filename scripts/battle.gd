extends Node3D
## Presentation consumes the root-authored core; it never applies combat damage.
const Clock = preload("res://core/arena_clock.gd")
const NativeImpact = preload("res://scripts/native_impact.gd")
const NativeMuzzle = preload("res://scripts/native_muzzle.gd")
const UnitView = preload("res://scripts/unit_view.gd")
const CELL_SIZE := 1.5
const FRIENDLY := Color("#50baff")
const HOSTILE := Color("#ff7897")
const SKILL_NAMES := {"single": "单体", "area": "范围", "shield": "护盾"}
var clock = Clock.new()
var views: Dictionary = {}
var bars: Dictionary = {}
var cards: Dictionary = {}
var tiles: Array = []
var durations: Dictionary = {}
var camera: Camera3D
var selected_id := 0
var paused := false
var dragging_unit := false
var focus_camera := false
var preparation_time := 0.0
var post_result_time := 0.0
var status_label: Label
var time_label: Label
var result_label: Label
var detail_label: Label
var start_button: Button
var pause_button: Button
var event_label: Label
var total_hp_label: Label
var ui: CanvasLayer
var font: SystemFont
var event_counts: Dictionary = {}
var shot_effects: Array = []
var event_history: Array[String] = []
var event_ids: Dictionary = {}
var debug_capture_shot := false
var capture_mode := false
var capture_stage := 0
var capture_elapsed := 0.0
var presentation_ready := false
var initialization_error := ""

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "SimHei", "Arial"])
	durations = JSON.parse_string(FileAccess.get_file_as_string("res://data/verified-durations.json"))
	if durations.is_empty():
		initialization_error = "缺少已验证动作时长"
		push_error(initialization_error)
		return
	_build_world()
	_build_ui()
	var error: String = clock.sim.configure(default_roster())
	if not error.is_empty():
		initialization_error = error
		push_error(error)
		return
	_rebuild_views()
	presentation_ready = true
	_refresh_ui()
	if "--capture" in OS.get_cmdline_user_args():
		capture_mode = true
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/screenshots"))

func default_roster() -> Array:
	var roster: Array = []
	var skills := ["single", "area", "shield"]
	var friendly := [Vector2(-2.4, 3.1), Vector2(0.5, 1.9), Vector2(2.6, 3.0)]
	var hostile := [Vector2(-2.4, -3.1), Vector2(0.5, -1.9), Vector2(2.6, -3.0)]
	for team in range(2):
		for slot in range(3):
			roster.append({"id": team * 3 + slot, "team": team,
				"cell": friendly[slot] if team == 0 else hostile[slot],
				"hp": 180, "damage": 16, "weapon": "HG", "attack_ticks": 54,
				"move_ticks": 14, "attack_windup_ticks": 16, "skill_cooldown_ticks": 200, "skill_recovery_ticks": 110, "skill": skills[slot], "skill_power": 70})
	return roster

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#091322")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#dfeeff")
	environment.ambient_light_energy = 0.8
	environment_node.environment = environment
	add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -28, 0)
	light.light_energy = 1.25
	light.shadow_enabled = true
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 145, 0)
	fill.light_energy = 0.5
	add_child(fill)
	var base := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(9.6, 0.18, 9.6)
	base.mesh = mesh
	base.position.y = -0.15
	base.material_override = _material(Color("#14243a"))
	add_child(base)
	# Continuous battlefield, subtle territory divider; no tile grid.
	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(9.2,9.2)
	ground.mesh = ground_mesh
	ground.material_override = _material(Color("#46515c"))
	add_child(ground)
	for z in [-4.45,0.0,4.45]:
		var line := MeshInstance3D.new()
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(8.9,0.012,0.025)
		line.mesh = line_mesh
		line.position = Vector3(0,0.012,z)
		line.material_override = _material(Color("#8498a4") if z==0 else Color("#5c6c79"))
		add_child(line)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.4
	camera.position = Vector3(-9.0, 7.5, 13.5)
	camera.near = 0.05
	camera.far = 100
	add_child(camera)
	camera.look_at(Vector3(0, 0.3, 0), Vector3.UP)
	camera.h_offset = 1.45
	camera.current = true

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material

func _tile_color(cell: Vector2i) -> Color:
	if selected_id >= 0 and clock.sim.phase == "prepare" and cell.y >= 3:
		return Color("#29445c") if (cell.x + cell.y) % 2 else Color("#315069")
	return (Color("#233348") if cell.y >= 3 else Color("#372b40")).lightened(0.035 if (cell.x + cell.y) % 2 else 0.0)

static func cell_world(cell: Vector2) -> Vector3:
	return Vector3(cell.x, 0, cell.y)

func _panel(rect: Rect2, color: Color, parent: Node) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _label(text: String, at: Vector2, size: int, color := Color.WHITE, parent: Node = null) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	(parent if parent != null else ui).add_child(label)
	return label

func _button(text: String, rect: Rect2, callback: Callable, accent := Color("#243b54")) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 18)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = accent.lightened(0.08 if state == "hover" else -0.07 if state == "pressed" else 0.0)
		if state == "disabled":
			style.bg_color = Color("#1b2b3d")
		style.set_corner_radius_all(10)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	ui.add_child(button)
	return button

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	_panel(Rect2(22, 18, 1236, 100), Color("#101f33"), ui)
	_label("BLUE / A", Vector2(42, 29), 15, FRIENDLY)
	_label("3v3 战斗原型", Vector2(40, 53), 29)
	_label("CH0331 · 原版动画与导出贴图", Vector2(333, 66), 18, Color("#9eb3cd"))
	time_label = _label("00.00 s", Vector2(1118, 56), 24, FRIENDLY)
	status_label = _label("准备站位", Vector2(730, 53), 22)
	total_hp_label = _label("", Vector2(729, 84), 13, Color("#9eb3cd"))
	_panel(Rect2(934, 138, 324, 586), Color("#101f33"), ui)
	_label("我方编队", Vector2(956, 154), 22, FRIENDLY)
	_label("己方区域自由拖放；不可越界或重叠", Vector2(956, 189), 12, Color("#9eb3cd"))
	for id in range(3):
		var b := _button("", Rect2(952, 219 + id * 66, 287, 56), select_unit.bind(id))
		b.add_theme_font_size_override("font_size", 16)
		cards[id] = b
	detail_label = _label("", Vector2(956, 430), 14, Color("#b7cce5"))
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.size = Vector2(280, 94)
	start_button = _button("开始战斗", Rect2(952, 535, 287, 49), start_battle, Color("#245579"))
	pause_button = _button("暂停", Rect2(952, 599, 136, 44), toggle_pause)
	_button("重开 / 站位", Rect2(1102, 599, 137, 44), restart_battle)
	_label("操作：空格 开始/暂停 · R 重开", Vector2(956, 671), 13, Color("#9eb3cd"))
	_panel(Rect2(934, 741, 324, 134), Color("#101f33"), ui)
	_label("事件时间线", Vector2(956, 755), 16, Color("#d0e3f5"))
	event_label = _label("等待开始…", Vector2(956, 786), 12, Color("#9eb3cd"))
	event_label.size = Vector2(280, 75)
	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label = _label("", Vector2(253, 130), 26, Color("#ffeeac"))
	_panel(Rect2(22, 791, 890, 84), Color("#101f33"), ui)
	_label("测试规则：单体 / 范围 / 护盾；双方均使用 CH0331。", Vector2(40, 805), 16, Color("#c5d9ee"))
	_label("攻击前摇后统一结算；原版骨骼动画。原版技能粒子尚未恢复。", Vector2(40, 838), 14, Color("#9eb3cd"))

func _rebuild_views() -> void:
	for view in views.values():
		view.queue_free()
	for bar in bars.values():
		bar.root.queue_free()
	views.clear()
	bars.clear()
	for unit in clock.sim.snapshot().units:
		var view = UnitView.new()
		add_child(view)
		view.setup(unit, durations, clock.generation)
		views[unit.id] = view
		var root := Control.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.size = Vector2(116, 50)
		ui.add_child(root)
		var name_label := _label("%s · %02d" % ["我方" if unit.team == 0 else "对手", unit.id + 1],
			Vector2(0, 0), 12, FRIENDLY if unit.team == 0 else HOSTILE, root)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.size.x = 116
		var progress := ProgressBar.new()
		progress.position = Vector2(0, 22)
		progress.size = Vector2(116, 9)
		progress.show_percentage = false
		progress.max_value = unit.max_hp
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color("#0a111c")
		bg.set_corner_radius_all(4)
		var fg := StyleBoxFlat.new()
		fg.bg_color = FRIENDLY if unit.team == 0 else HOSTILE
		fg.set_corner_radius_all(4)
		progress.add_theme_stylebox_override("background", bg)
		progress.add_theme_stylebox_override("fill", fg)
		root.add_child(progress)
		var hp_label := _label("", Vector2(0, 33), 11, Color("#d3e2f4"), root)
		hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp_label.size.x = 116
		bars[unit.id] = {"root": root, "hp": progress, "label": hp_label}
	_update_views(0.0)

func select_unit(id: int) -> void:
	if clock.sim.phase != "prepare":
		return
	selected_id = id
	_refresh_ui()
	for view_id in views:
		views[view_id].set_selected(view_id == selected_id)

func place_selected(cell: Vector2) -> bool:
	if selected_id < 0:
		return false
	if not clock.sim.place(selected_id, cell):
		return false
	# Formation changes use the core's authoritative snapshot.
	_update_views(0.0)
	_refresh_ui()
	return true

func start_battle() -> void:
	if clock.sim.start():
		paused = false
		post_result_time = 0.0
		selected_id = -1
		_rebuild_views()
		event_history.clear()
		for view in views.values():
			view.set_selected(false)
		_refresh_ui()

func toggle_pause() -> void:
	if clock.sim.phase == "prepare":
		start_battle()
		return
	if clock.sim.phase != "running":
		return
	paused = not paused
	for view in views.values():
		view.player.speed_scale = 0.0 if paused else 1.0
	_refresh_ui()

func restart_battle() -> void:
	for effect in shot_effects:
		remove_child(effect);effect.queue_free()
	shot_effects.clear()
	clock.reset()
	preparation_time = 0.0
	post_result_time = 0.0
	paused = false
	selected_id = 0
	event_counts.clear()
	event_history.clear()
	event_ids.clear()
	_rebuild_views()
	_refresh_ui()

func advance_battle(delta: float) -> Array:
	if paused or not is_finite(delta) or delta <= 0.0:
		return []
	if clock.sim.phase == "finished":
		post_result_time += delta
		_update_views(clock.sim.tick * 0.05 + post_result_time)
		_update_shot_effects(clock.sim.tick * 0.05 + post_result_time)
		return []
	var batch: Array = clock.advance(delta)
	for event in batch:
		if event.generation != clock.generation:
			continue
		var identity := "%d/%s" % [event.generation, event.event_id]
		if event_ids.has(identity):
			continue
		event_ids[identity] = true
		event_counts[event.type] = event_counts.get(event.type, 0) + 1
		if views.has(event.get("actor_id", -1)):
			views[event.actor_id].consume(event)
		if event.type == "damage" and event.get("kind","") == "attack" and views.has(event.actor_id):
			var source_view=views[event.actor_id]
			for source_unit in clock.sim.units:
				if source_unit.id==event.actor_id:source_view.update_time(event.tick*0.05,source_unit);break
			var flash=NativeMuzzle.new();add_child(flash)
			flash.begin(source_view.muzzle_transform(),event.tick*0.05,hash(identity),1.3)
			shot_effects.append(flash)
			if views.has(event.target_id):
				var impact=NativeImpact.new();add_child(impact)
				impact.begin(views[event.target_id].hit_position(),event.tick*0.05,hash(identity)+1,1.3)
				shot_effects.append(impact)
		if event.type in ["skill", "death", "finished"]:
			var description := ""
			if event.type == "skill":
				description = "%02d 释放%s测试技能" % [event.actor_id + 1, SKILL_NAMES[event.skill]]
			elif event.type == "death":
				description = "%02d 退场" % (event.actor_id + 1)
			else:
				description = "战斗结束"
			event_history.push_front("%05.2fs  %s" % [event.tick * 0.05, description])
			if event_history.size() > 4:
				event_history.pop_back()
	_update_views(clock.sim.tick * 0.05 + clock.accumulator)
	_update_shot_effects(clock.sim.tick * 0.05 + clock.accumulator)
	if debug_capture_shot and not shot_effects.is_empty() and clock.sim.tick*0.05+clock.accumulator-shot_effects[0].born>=0.075:
		debug_capture_shot = false
		paused = true
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/screenshots"))
		_save_capture("06-native-muzzle")
	_refresh_ui()
	return batch

func _update_shot_effects(battle_time: float) -> void:
	for i in range(shot_effects.size()-1,-1,-1):
		var effect=shot_effects[i]
		effect.update_time(battle_time)
		if battle_time>=effect.born+effect.lifetime:
			shot_effects.remove_at(i);remove_child(effect);effect.queue_free()

func _update_views(battle_time: float) -> void:
	for unit in clock.sim.snapshot().units:
		if not views.has(unit.id):
			continue
		views[unit.id].update_time(battle_time, unit)
		views[unit.id].set_selected(unit.id == selected_id)
		var hud: Dictionary = bars[unit.id]
		var at: Vector3 = views[unit.id].global_position + Vector3(0, 1.7, 0)
		hud.root.position = camera.unproject_position(at) - Vector2(58, 20)
		hud.hp.value = unit.hp
		hud.label.text = "%d/%d%s" % [unit.hp, unit.max_hp, " 盾%d" % unit.shield if unit.shield > 0 else ""]
		hud.root.modulate.a = 0.5 if unit.hp <= 0 else 1.0

func _refresh_ui() -> void:
	var snapshot: Dictionary = clock.sim.snapshot()
	var phase: String = snapshot.phase
	status_label.text = "准备站位" if phase == "prepare" else "已暂停" if paused else "自动战斗中" if phase == "running" else "战斗结束"
	time_label.text = "%05.2f s" % (snapshot.tick * 0.05)
	var totals := [0, 0]
	for unit in snapshot.units:
		totals[unit.team] += unit.hp
		if unit.id < 3:
			cards[unit.id].text = "%s %02d · %s  HP %d  EX冷却 %ds" % ["●" if selected_id == unit.id else "○", unit.id + 1, SKILL_NAMES[unit.skill], unit.hp, ceili(maxi(0,unit.skill_ready-snapshot.tick)*0.05)]
			cards[unit.id].disabled = phase != "prepare"
	total_hp_label.text = "我方 HP %d   /   对手 HP %d" % [totals[0], totals[1]]
	start_button.disabled = phase != "prepare"
	pause_button.disabled = phase != "running"
	pause_button.text = "继续" if paused else "暂停"
	detail_label.text = "普攻 16 · 每 2.7 秒行动\nEX由AI判断，独立冷却10秒。
技能强度70；无手动施放。\n站位和结算来自已测试的战斗核心。"
	event_label.text = "\n".join(event_history) if not event_history.is_empty() else "等待开始…"
	result_label.text = ""
	if phase == "finished":
		result_label.text = "平局" if snapshot.winner == -1 else "我方胜利" if snapshot.winner == 0 else "对手胜利"
		result_label.text += " · 点击重开"
	for index in range(tiles.size()):
		tiles[index].material_override.albedo_color = _tile_color(Vector2i(index % 6, index / 6))

func _process(delta: float) -> void:
	if not presentation_ready:
		return
	if not paused:
		if clock.sim.phase == "prepare":
			preparation_time += delta
			_update_views(preparation_time)
		else:
			advance_battle(delta)
	if capture_mode:
		capture_elapsed += delta
		_capture_step()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			toggle_pause()
		elif event.keycode == KEY_F4:
			get_tree().change_scene_to_file("res://gallery.tscn")
		elif event.keycode == KEY_F3:
			debug_capture_shot = true
			if clock.sim.phase == "prepare":start_battle()
		elif event.keycode == KEY_R:
			restart_battle()
		elif event.keycode == KEY_F2:
			focus_camera = not focus_camera
			if focus_camera:
				var focus: Vector3 = views[0].position + Vector3(0,0.65,0)
				camera.position = focus + Vector3(2.0,1.25,-3.0)
				camera.look_at(focus,Vector3.UP)
				camera.size = 3.6
				camera.h_offset = 0.5
			else:
				camera.position = Vector3(-9.0,7.5,13.5)
				camera.look_at(Vector3(0,0.3,0),Vector3.UP)
				camera.size = 10.4
				camera.h_offset = 1.45
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			dragging_unit = false
			return
		if clock.sim.phase != "prepare": return
		var point = _mouse_ground()
		if point == null: return
		var picked := -1
		var nearest := 0.65
		for unit in clock.sim.units:
			if unit.team != 0: continue
			var distance: float = point.distance_to(unit.cell)
			if distance < nearest: nearest=distance; picked=unit.id
		if picked >= 0:
			select_unit(picked)
			dragging_unit = true
		else: place_selected(point)
	elif event is InputEventMouseMotion and dragging_unit and clock.sim.phase == "prepare":
		var point = _mouse_ground()
		if point != null: place_selected(point)

func _mouse_ground():
	var mouse := get_viewport().get_mouse_position()
	if mouse.x >= 920 or mouse.y < 130 or mouse.y > 785: return null
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	if absf(direction.y) < 0.001: return null
	var hit := origin + direction * (-origin.y / direction.y)
	return Vector2(hit.x,hit.z)

func _capture_step() -> void:
	if capture_stage == 0 and capture_elapsed > 1.5:
		capture_stage = 1
		_save_capture("01-formation")
		start_battle()
	elif capture_stage == 1 and clock.sim.tick >= 50:
		capture_stage = 2
		_save_capture("02-combat")
	elif capture_stage == 2 and event_counts.get("skill", 0) > 0:
		capture_stage = 3
		_save_capture("03-test-skills")
	elif capture_stage == 3 and clock.sim.phase == "finished":
		capture_stage = 4
		_save_capture("04-result")
		var file := FileAccess.open("res://evidence/capture-summary.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"snapshot": clock.sim.snapshot(), "events": event_counts}, "  "))
		restart_battle()
	elif capture_stage == 4 and clock.sim.phase == "prepare":
		capture_stage = 5
		_save_capture("05-restart")
		get_tree().create_timer(0.5).timeout.connect(func(): get_tree().quit())

func _save_capture(name: String) -> void:
	# Wait one rendered frame so screenshots correspond to the updated UI.
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var result: Error = image.save_png("res://evidence/screenshots/" + name + ".png")
	print("CAPTURE ", name, " result=", result)
