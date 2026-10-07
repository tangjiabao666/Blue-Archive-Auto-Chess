extends SceneTree
## Deterministic integration coverage for the playable four-per-side arena.
## Run headless: godot --headless --path . --script tests/test_four_combat_regression.gd
## No rendered-scene claims: visual contact cues remain covered by native view tests.
const Session = preload("res://core/game_session.gd")
const ACTIVE = ["shiroko", "hoshino", "hina", "aru", "yuuka", "aris", "serika"]
var failures := 0
var checks := 0

func ck(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func row_roster(keys: Array, star: int = 1) -> Array:
	var roster: Array = []
	for team in range(2):
		for slot in range(4):
			roster.append({"id": team * 7 + slot, "team": team,
				"cell": Vector2(-4.8 + slot * 1.6, 4.7 if team == 0 else -4.7),
				"character_id": keys[(slot + team * 4) % keys.size()], "star": star})
	return roster

func session_for(roster: Array, settings: Dictionary = {}):
	var session = Session.new()
	var opts := {"random_damage": false, "seed": 1701, "initial_basic_delay_cap_seconds": 5.0}
	opts.merge(settings, true)
	var error: String = session.clock.sim.configure(roster, opts)
	ck(error.is_empty(), "four-versus-four fixture configures: " + error)
	if error.is_empty():
		ck(session.clock.sim.units.size() == 8, "fixture has four units on each side")
		session.clock.sim.start()
	return session

func quiet_fixture(character: String = "hoshino", star: int = 1):
	var roster := row_roster(["yuuka"])
	roster[0].cell = Vector2(4, 0.8)
	roster[0].character_id = character
	roster[0].star = star
	roster[4].cell = Vector2(4, -0.8)
	var session = session_for(roster)
	for unit in session.clock.sim.units:
		unit.max_hp = 1000000
		unit.hp = unit.max_hp
		unit.basic_ready = 100000
		unit.skill_ready = 100000
		if unit.id != 0:
			unit.busy_until = 100000
	return session

func _initialize() -> void:
	run_natural_matches()
	run_range_and_los_loss()
	run_one_star_gate()
	run_damage_contacts()
	run_death_cancellation()
	run_clock_and_pause()
	print("FOUR COMBAT REGRESSION CHECKS=", checks, " FAILURES=", failures)
	quit(1 if failures else 0)

func run_natural_matches() -> void:
	var scenarios: Array = []
	scenarios.append({"name": "default-row", "roster": row_roster(ACTIVE)})
	scenarios.append({"name": "upgraded-row", "roster": row_roster(ACTIVE, 2)})
	var crowd := row_roster(["hoshino", "aris", "yuuka", "hina"])
	for team in range(2):
		for slot in range(4):
			crowd[team * 4 + slot].cell = Vector2(4.0 if slot < 2 else 3.2,
				(1.8 if slot % 2 == 0 else 1.0) * (1 if team == 0 else -1))
	scenarios.append({"name": "tight-front-back", "roster": crowd})
	var walls := row_roster(["hoshino", "yuuka"])
	for team in range(2):
		for slot in range(4):
			walls[team * 4 + slot].cell = Vector2(-2.0 if slot < 2 else 2.0,
				(1.3 if slot % 2 == 0 else 2.1) * (1 if team == 0 else -1))
	scenarios.append({"name": "both-wall-corners", "roster": walls})
	# Reproduced from a fixed-seed formation sweep (52993, cases 21-23).
	# These cover a static waypoint occupied by an ally, a wall corner crowd,
	# and a formation that must make a small lateral/retreating detour.
	var trapped_formations: Array = [
		[["aris", 1, -2.698315, 2.580094], ["aris", 2, -2.108034, 3.174146], ["hoshino", 2, -1.878506, 4.656374], ["hina", 2, -5.670736, 3.807954], ["hoshino", 1, 0.404339, -5.546214], ["aru", 2, 1.354881, -0.923208], ["hoshino", 2, -2.833283, -0.990627], ["yuuka", 1, 5.107616, -3.877136]],
		[["hoshino", 2, -2.365454, 4.575195], ["serika", 2, 5.393747, 5.318742], ["hina", 2, -0.236267, 4.101707], ["hoshino", 2, 0.708835, 3.264686], ["hoshino", 1, 1.892880, -3.261424], ["aris", 2, -2.500368, -4.711470], ["shiroko", 1, 2.675005, -5.056979], ["serika", 1, 4.846459, -2.400377]],
		[["hoshino", 1, 2.204200, 5.626221], ["aris", 1, 3.137975, 3.131310], ["serika", 1, 5.375637, 4.067715], ["hina", 1, 5.282466, 1.860559], ["serika", 1, -1.166027, -4.842571], ["aris", 1, -5.379573, -0.746199], ["hina", 1, -3.601209, -2.355851], ["serika", 2, 4.657019, -5.500761]]
	]
	for index in range(trapped_formations.size()):
		var roster: Array = []
		for slot in range(8):
			var row: Array = trapped_formations[index][slot]
			var team: int = slot / 4
			roster.append({"id": team * 7 + slot % 4, "team": team, "character_id": row[0], "star": row[1], "cell": Vector2(row[2], row[3])})
		scenarios.append({"name": "crowd-detour-%d" % (index + 21), "roster": roster, "seed": 52993 + index + 21})
	for scenario in scenarios:
		var session = session_for(scenario.roster, {"seed": int(scenario.get("seed", 1701))})
		var sim = session.clock.sim
		var moves := 0
		var attacks := 0
		var damage := 0
		var finish_reason := ""
		var anchors: Dictionary = {}
		var stalled: Dictionary = {}
		var reported: Dictionary = {}
		for unit in sim.units:
			anchors[unit.id] = unit.cell
			stalled[unit.id] = 0
		while sim.phase == "running":
			var batch: Array = sim.step()
			var moved: Dictionary = {}
			for event in batch:
				if event.type == "move":
					moves += 1
					moved[event.actor_id] = true
					ck(session.navigation.is_segment_free(event.from, event.to, 0.35),
						"%s actor %d never walks through an obstacle at tick %d" % [scenario.name, event.actor_id, event.tick])
				elif event.type == "attack":
					attacks += 1
					var actor = sim._unit(event.actor_id)
					ck(event.origin.distance_to(event.target_cell) <= actor.range + 0.00001,
						"%s actor %d shoots only in range at tick %d" % [scenario.name, actor.id, event.tick])
					ck(session.navigation.has_line_of_sight(event.origin, event.target_cell),
						"%s actor %d shoots only with LOS at tick %d" % [scenario.name, actor.id, event.tick])
					ck(not moved.has(actor.id), "%s moving actor %d cannot fire in the same tick" % [scenario.name, actor.id])
				elif event.type == "damage":
					damage += event.amount
				elif event.type == "finished":
					finish_reason = event.reason
			for unit in sim.units:
				# A six-second stationary interval is a defect only when the unit
				# is alive, free to act, and has no valid firing position. Casting,
				# aim/recovery, reloading and firing from cover do not count.
				var free_to_walk: bool = unit.hp > 0 and sim.tick >= unit.busy_until and sim.tick >= unit.stun_until and sim.tick >= unit.reload_until
				if not free_to_walk or sim._target(unit, unit.range) != null or unit.cell.distance_to(anchors[unit.id]) >= 0.15:
					anchors[unit.id] = unit.cell
					stalled[unit.id] = 0
				else:
					stalled[unit.id] += 1
				if stalled[unit.id] >= 120 and not reported.has(unit.id):
					reported[unit.id] = true
					ck(false, "%s actor %d stranded for six actionable seconds at tick %d position %s" % [scenario.name, unit.id, sim.tick, unit.cell])
		ck(moves > 0 and attacks > 0 and damage > 0, scenario.name + " has movement, firing and actual HP damage")
		ck(finish_reason == "elimination", scenario.name + " ends by elimination rather than timeout")
		print("FOUR MATCH ", scenario.name, " ticks=", sim.tick, " moves=", moves, " attacks=", attacks, " damage=", damage, " winner=", sim.winner, " stalled=", reported.keys())

func run_range_and_los_loss() -> void:
	for lose_los in [false, true]:
		var session = quiet_fixture()
		var sim = session.clock.sim
		var actor: Dictionary = sim._unit(0)
		var target: Dictionary = sim._unit(7)
		if lose_los:
			actor.cell = Vector2(-3.5, 0.5)
			target.cell = Vector2(-3.5, -0.5)
		var acquired := false
		for event in sim.step():
			if event.type == "aim" and event.actor_id == 0:
				acquired = true
		ck(acquired, "acquires target before " + ("LOS" if lose_los else "range") + " loss")
		# Target changes position during weapon raise, before any committed shot.
		target.cell = Vector2(-1.1, -0.5) if lose_los else Vector2(4, -5.5)
		ck(not sim.can_attack(actor, target), "moved target invalidates firing solution")
		var lost := false
		var reacquired := false
		var shots := 0
		for i in range(200):
			for event in sim.step():
				if event.get("actor_id", -1) != 0:
					continue
				if event.type == "aim_lost":
					lost = true
				if event.type == "aim":
					reacquired = true
				if event.type == "attack":
					shots += 1
					ck(event.origin.distance_to(event.target_cell) <= actor.range + 0.00001 and session.navigation.has_line_of_sight(event.origin, event.target_cell), "never fires after range/LOS loss until a valid target is acquired")
		ck(lost, "target loss cancels the raised-weapon aim")
		ck(reacquired and shots > 0, "routes to a clear firing position and resumes firing")

func run_one_star_gate() -> void:
	for star in [1, 2]:
		var session = session_for(row_roster(["yuuka", "serika", "hoshino", "shiroko"], star))
		var sim = session.clock.sim
		var ex_count := 0
		for i in range(320):
			for event in sim.step():
				if event.type == "skill":
					ex_count += 1
		ck(ex_count == 0 if star == 1 else ex_count > 0, "one-star EX locked; two-star EX actually casts (star %d, casts %d)" % [star, ex_count])
		if star == 1:
			for unit in sim.units:
				ck(unit.energy == 0, "locked one-star EX cannot show charged energy")

func run_damage_contacts() -> void:
	# Check HP changes against scheduled contacts, not merely pending metadata.
	for key in ACTIVE:
		var session = quiet_fixture(key)
		var sim = session.clock.sim
		var actor: Dictionary = sim._unit(0)
		var target: Dictionary = sim._unit(7)
		var shot: Dictionary = {}
		for i in range(100):
			for event in sim.step():
				if event.type == "attack" and event.actor_id == 0:
					shot = event
			if not shot.is_empty():
				break
		ck(not shot.is_empty(), key + " actually emits a normal shot")
		if shot.is_empty():
			continue
		var expected: Dictionary = {}
		for hit in sim._pending:
			if hit.source == 0 and hit.target == 7 and hit.ability == "normal":
				expected[hit.hit_index] = hit.due
		ck(expected.size() == int(shot.hit_count), key + " schedules every source burst contact")
		ck(expected.get(0, -1) == int(shot.impact_tick), key + " public first-contact tick matches authoritative contact")
		actor.busy_until = 100000
		var seen: Dictionary = {}
		var last_due: int = int(expected.values().max())
		while sim.tick <= last_due:
			var before: int = target.hp
			var hp_loss := 0
			for event in sim.step():
				if event.type == "damage" and event.actor_id == 0 and event.target_id == 7:
					hp_loss += event.amount
					if event.component == "normal":
						ck(event.tick == expected.get(event.hit_index, -1), key + " actual HP loss lands exactly on contact")
						seen[event.hit_index] = true
			ck(before - target.hp == hp_loss, key + " HP changes only with damage events")
		ck(seen.size() == expected.size(), key + " every live burst contact causes damage")
	# Aru's separate direct shot and explosion must produce real HP damage on
	# their authored contacts, with no early explosion hidden in the cast event.
	var session = quiet_fixture("aru", 2)
	var sim = session.clock.sim
	var actor: Dictionary = sim._unit(0)
	var target: Dictionary = sim._unit(7)
	ck(sim._try_skill(actor, "ex"), "Aru two-star EX starts")
	actor.busy_until = 100000
	var contacts: Dictionary = {}
	var previous: int = target.hp
	for i in range(70):
		var expected_loss := 0
		for event in sim.step():
			if event.type == "damage" and event.actor_id == 0 and event.ability == "ex":
				contacts[event.component] = event.tick
				expected_loss += event.amount
		ck(previous - target.hp == expected_loss, "Aru EX HP is synchronized to contact events")
		previous = target.hp
	ck(contacts == {"direct": 13, "explosion": 61}, "Aru EX actual direct/explosion HP contacts retain ticks 13/61: " + str(contacts))

func run_death_cancellation() -> void:
	var session = quiet_fixture("shiroko", 2)
	var sim = session.clock.sim
	var actor: Dictionary = sim._unit(0)
	var target: Dictionary = sim._unit(7)
	ck(sim._try_skill(actor, "ex"), "death-cancellation fixture begins a delayed drone EX")
	ck(not sim._pending.is_empty(), "death-cancellation fixture has future contacts")
	# Death is injected at a tick boundary, as if another combatant's damage
	# killed the caster. Same-tick simultaneous damage remains permitted.
	actor.hp = 0
	var hp: int = target.hp
	var ghost_damage := 0
	for i in range(100):
		for event in sim.step():
			if event.type == "damage" and event.actor_id == 0:
				ghost_damage += 1
	ck(ghost_damage == 0 and target.hp == hp, "dead caster cannot deliver future scheduled contacts")
	for hit in sim._pending:
		ck(hit.source != 0, "dead caster future contacts are removed")

func run_clock_and_pause() -> void:
	var a = session_for(row_roster(ACTIVE, 2), {"random_damage": true})
	var b = session_for(row_roster(ACTIVE, 2), {"random_damage": true})
	var first: Array = []
	var second: Array = []
	for i in range(1000):
		first.append_array(a.clock.advance(0.03))
	for i in range(300):
		second.append_array(b.clock.advance(0.10))
	ck(first == second and a.clock.sim.snapshot() == b.clock.sim.snapshot(), "four-versus-four frame chunks preserve every event, RNG and full state")
	var snapshot: Dictionary = a.clock.sim.snapshot()
	ck(a.clock.advance(-1).is_empty() and a.clock.advance(NAN).is_empty() and a.clock.advance(INF).is_empty(), "invalid frame deltas are ignored")
	ck(snapshot == a.clock.sim.snapshot(), "invalid deltas cannot change four-versus-four state")
	a.clock.sim.reset()
	a.clock.accumulator = 0
	a.clock.sim.start()
	var replay: Array = []
	for i in range(300):
		replay.append_array(a.clock.advance(0.10))
	ck(replay == first and snapshot == a.clock.sim.snapshot(), "reset also clears any observable navigation history for deterministic replay")
	# Exercise GameSession.advance's real pause gate while combat and a
	# fractional fixed-step accumulator are live; an uninitialized session
	# would return [] for the wrong reason.
	var game = session_for(row_roster(ACTIVE, 2))
	ck(game.rules.new_match(1701, game.catalog).ok, "pause fixture initializes match rules")
	game.rules._state.phase = "battle"
	ck(game.phase() == "battle", "pause fixture reaches the live battle path")
	game.advance(0.07)
	var before: Dictionary = game.clock.sim.snapshot()
	var accumulator: float = game.clock.accumulator
	game.paused = true
	ck(game.advance(5.0).is_empty() and game.clock.sim.snapshot() == before and game.clock.accumulator == accumulator, "pause freezes combat, contacts and fractional elapsed time")
	game.paused = false
	game.advance(0.03)
	ck(game.clock.sim.tick == before.tick + 1 and is_zero_approx(game.clock.accumulator), "unpause resumes the exact pending fixed step")
