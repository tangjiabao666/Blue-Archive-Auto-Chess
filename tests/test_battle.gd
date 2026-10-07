extends SceneTree
const Sim = preload("res://core/battle_sim.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func unit(id: int, team: int, pos: Vector2i, extras: Dictionary = {}) -> Dictionary:
	var d := {"id": id, "team": team, "cell": pos}
	d.merge(extras, true)
	return d

func _initialize() -> void:
	var s = Sim.new()
	var roster := [unit(1,0,Vector2i(0,4)), unit(2,0,Vector2i(1,4)), unit(3,1,Vector2i(0,1))]
	check(s.configure(roster) == "", "valid roster configures")
	if s.units.is_empty():
		finish()
		return
	check(s.place(1,Vector2i(1,4)), "friendly swap succeeds")
	check(s.units[0].cell == Vector2i(1,4) and s.units[1].cell == Vector2i(0,4), "swap updates both units")
	check(not s.place(1,Vector2i(0,0)), "cannot deploy into enemy zone")
	check(s.start(), "start succeeds")
	check(not s.start(), "start cannot double-start")
	check(not s.place(1,Vector2i(2,4)), "combat position editing rejected")
	for i in range(1201):
		s.step()
		var occupied := {}
		for u in s.units:
			if u.hp > 0:
				check(not occupied.has(u.cell), "alive units never overlap")
				occupied[u.cell] = true
			check(u.hp >= 0 and u.hp <= u.max_hp, "hp within bounds")
	check(s.phase == "finished", "battle terminates")
	var end_tick: int = s.tick
	s.step()
	check(s.tick == end_tick, "finished battle does not advance")
	s.reset()
	check(s.phase == "prepare" and s.tick == 0, "reset returns clean prep")
	check(s.units[0].cell == Vector2i(1,4), "reset restores last starting formation")
	for u in s.units:
		check(u.hp == u.max_hp and u.energy == 0 and u.shield == 0, "reset restores resources")
	var saved = s.snapshot()
	check(s.configure([unit(1,0,Vector2i(0,4)),unit(1,1,Vector2i(0,1))]) != "", "duplicate IDs rejected")
	check(s.snapshot() == saved, "bad configure is atomic")
	check(s.configure([unit(1,0,Vector2i(-1,4)),unit(2,1,Vector2i(0,1))]) != "", "outside grid rejected")
	check(s.configure([unit(1,0,Vector2i(0,4),{"attack_ticks":0}),unit(2,1,Vector2i(0,1))]) != "", "zero cooldown rejected")
	# Simultaneous lethal attacks must allow draw.
	s.configure([unit(1,0,Vector2i(0,3),{"hp":10,"range":6}),unit(2,1,Vector2i(0,2),{"hp":10,"range":6})])
	s.start(); s.step()
	check(s.winner == -1 and s.units[0].hp == 0 and s.units[1].hp == 0, "simultaneous lethal hits draw")
	# Equal distance uses stable ID, not input order.
	s.configure([unit(9,1,Vector2i(1,2)),unit(1,0,Vector2i(0,3),{"range":6}),unit(4,1,Vector2i(0,1))])
	s.start()
	var ev: Array = s.step()
	var targets := []
	for e in ev:
		if e.type == "attack" and e.actor_id == 1: targets.append(e.target_id)
	check(targets == [4], "target tie uses ID")
	# Same setup produces exact same states and event traces.
	var a = Sim.new(); var b = Sim.new()
	a.configure(roster); b.configure(roster); a.start(); b.start()
	for i in range(1200):
		check(a.step() == b.step(), "event replay deterministic")
	check(a.snapshot() == b.snapshot(), "final state deterministic")
	# Run shield, single and area skill against durable enemies.
	for kind in ["single", "area", "shield"]:
		s = Sim.new()
		s.configure([unit(1,0,Vector2i(0,3),{"skill":kind,"hp":200,"skill_cooldown_ticks":40}),unit(2,1,Vector2i(0,2),{"hp":1000}),unit(3,1,Vector2i(1,2),{"hp":1000})])
		s.start()
		var seen := false
		for i in range(100):
			for e in s.step():
				if e.type == "skill" and e.actor_id == 1: seen = true
		check(seen, "skill emitted: " + kind)
	# No damage case hits time limit and draws.
	s = Sim.new()
	s.configure([unit(1,0,Vector2i(0,3),{"damage":0,"skill_power":0}),unit(2,1,Vector2i(0,2),{"damage":0,"skill_power":0})])
	s.start()
	for i in range(1200): s.step()
	check(s.phase == "finished" and s.tick == 1200 and s.winner == -1, "timeout is exact draw")
	finish()

func finish() -> void:
	print("CHECKS=%d FAILURES=%d" % [checks, failures])
	quit(1 if failures else 0)
