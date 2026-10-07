extends SceneTree
## Native presentation must honor real core actions across source-tail overlap.
## Fixture events all come from CharacterClock/CharacterSim, never synthetic consume calls.
## Only target durability/inactivity and the supported initial-basic-delay option
## isolate the traces; source animation speed, gameplay cadence and contacts stay intact.
const Clock = preload("res://core/character_clock.gd")
const View = preload("res://scripts/unit_view.gd")
var profiles: Dictionary
var checks := 0
var failures := 0

func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	call_deferred("run")

func make_clock(character: String, star: int, moving_target_fixture: bool = false):
	var clock = Clock.new()
	clock.generation = 1
	var roster := [
		{"id": 0, "team": 0, "cell": Vector2(0, 0.75), "character_id": character, "star": star},
		{"id": 7, "team": 1, "cell": Vector2(0, -0.75), "character_id": "aris", "star": 1}]
	if moving_target_fixture:
		roster.append({"id": 8, "team": 1, "cell": Vector2(0, -6), "character_id": "aris", "star": 1})
	ck(clock.sim.configure(roster, {"random_damage": false, "initial_basic_delay_cap_seconds": 5.0}).is_empty(), character + " fixture configures")
	clock.sim.start()
	for unit in clock.sim.units:
		if unit.id == 0: continue
		unit.hp = 1 if moving_target_fixture and unit.id == 7 else 1000000
		unit.max_hp = 1000000
		unit.busy_until = 100000
	return clock

func make_view(clock):
	var view = View.new()
	root.add_child(view)
	var shown: Dictionary = clock.sim.units[0].duplicate(true)
	shown.presentation = profiles[shown.character_id]
	view.setup(shown, {}, clock.generation)
	return view

func run_ability_release(character: String, star: int, ability: String, delta: float) -> void:
	var clock = make_clock(character, star)
	var view = make_view(clock)
	var actor: Dictionary = clock.sim.units[0]
	var label := "%s %s %.2f FPS" % [character, ability, 1.0 / delta]
	var cast: Dictionary = {}
	var next_attack: Dictionary = {}
	var first_contact: Dictionary = {}
	var paused_checked := false
	for frame in range(2000):
		var batch: Array = clock.advance(delta)
		for event in batch:
			view.consume(event)
			if event.get("actor_id", -1) != 0: continue
			if cast.is_empty() and event.type == ("skill" if ability == "ex" else "basic") and event.get("ability", "") == ability:
				cast = event.duplicate(true)
				ck(is_equal_approx(view._clip_speed, 1.0), label + " retains native ability speed")
				ck(is_equal_approx(view._clip_offset, float(profiles[character].action_windows[ability].clipIn)), label + " retains native source clipIn")
			if not cast.is_empty() and next_attack.is_empty() and event.type == "attack":
				next_attack = event.duplicate(true)
				ck(int(event.tick) == int(cast.tick) + int(cast.recovery_ticks), label + " core emits next burst on authoritative release")
				ck(view._action_kind == "attack" and is_equal_approx(view._action_started_at, event.tick * 0.05), label + " accepts authoritative attack before rendered old-clip completion")
			if not next_attack.is_empty() and event.type in ["damage", "miss"] and event.get("ability", "") == "normal":
				first_contact = event.duplicate(true)
		var at: float = clock.sim.tick * 0.05 + clock.accumulator
		view.update_time(at, actor)
		if not cast.is_empty() and not paused_checked:
			# GameSession pause emits no new batch and keeps the visual clock fixed.
			# Repeated frozen updates must not consume the action's source tail.
			var paused_position: float = view.player.current_animation_position
			var paused_state: String = view.state
			for i in 5: view.update_time(at, actor)
			ck(view.state == paused_state and is_equal_approx(view.player.current_animation_position, paused_position), label + " frozen presentation does not advance")
			paused_checked = true
		if not first_contact.is_empty():
			ck(int(first_contact.tick) == int(next_attack.impact_tick), label + " damage/miss retains authoritative first-contact tick")
			ck(view.current_clip == view.ATTACK_FIRE, label + " native recoil is active at next burst contact")
			break
	ck(not cast.is_empty() and not next_attack.is_empty() and not first_contact.is_empty(), label + " reaches cast, attack and contact through the real core")
	if not cast.is_empty():
		ck(int(cast.tick) == (100 if character == "iori" else 160), label + " preserves the deterministic natural cast trace")
		if character == "hina":
			var tail: float = float(profiles[character].action_windows.ex.duration) - int(cast.recovery_ticks) * 0.05
			ck(tail > 0.0 and tail < 0.05, label + " valid native EX tail crosses the gameplay boundary by less than one tick")
	view.free()

func run_recovery_to_move() -> void:
	var clock = make_clock("shiroko", 1, true)
	var view = make_view(clock)
	var actor: Dictionary = clock.sim.units[0]
	var shot: Dictionary = {}
	var contact: Dictionary = {}
	var move: Dictionary = {}
	for frame in range(100):
		var batch: Array = clock.advance(0.05)
		for event in batch:
			view.consume(event)
			if event.get("actor_id", -1) != 0: continue
			if event.type == "attack" and shot.is_empty(): shot = event.duplicate(true)
			if event.type == "damage" and event.get("ability", "") == "normal": contact = event.duplicate(true)
			if event.type == "move" and move.is_empty(): move = event.duplicate(true)
		var at: float = clock.sim.tick * 0.05 + clock.accumulator
		if not move.is_empty():
			ck(int(shot.get("tick", -1)) == 45 and int(contact.get("tick", -1)) == 46 and int(move.tick) == 61, "real Shiroko target-death trace reaches recovery movement")
			ck(int(move.tick) >= int(shot.tick) + int(shot.burst_ticks) and int(move.tick) > int(contact.tick), "movement waits until active burst and resolved contact are over")
			ck(int(move.tick) < int(shot.tick) + int(shot.recovery_ticks), "movement legitimately begins before passive attack recovery ends")
			var old_pending := false
			for hit in clock.sim._pending:
				if hit.source == 0 and hit.get("ability", "") == "normal": old_pending = true
			ck(not old_pending, "dead target leaves no unresolved normal contact to truncate")
			view.update_time(at + 0.025, actor)
			ck(view.is_moving and view.position.is_equal_approx(View.cell_position(move.from.lerp(move.to, 0.5))), "real movement interpolates from the core event")
			ck(view.state == "move" and view.current_clip == view.WALK, "native walk replaces completed-shot recovery instead of sliding")
			break
		view.update_time(at, actor)
	ck(not move.is_empty(), "fixture produces authoritative movement without injecting a move event")
	view.free()

func run() -> void:
	profiles = JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	for delta in [1.0 / 60.0, 0.05, 0.08]:
		run_ability_release("iori", 1, "basic", delta)
		run_ability_release("hina", 2, "ex", delta)
	run_recovery_to_move()
	await process_frame
	print("CHARACTER ACTION PREEMPTION CHECKS=", checks, " FAILURES=", failures)
	quit(1 if failures else 0)
