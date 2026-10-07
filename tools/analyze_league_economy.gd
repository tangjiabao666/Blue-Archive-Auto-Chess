extends SceneTree
## Rules-only economy probe. Synthetic draw outcomes are NOT measured combat.
const Match = preload("res://core/tactical_match.gd")
const OUT := "res://evidence/tactical-economy/"
const POLICIES := ["league_budget_ai", "pairs_then_population"]
const SOURCE_PATHS := ["core/prototype_match.gd", "core/tactical_match.gd", "core/tactical_league.gd", "core/shop_odds.gd", "data/character_skills.json", "data/character-presentations.json", "tools/analyze_league_economy.gd", "evidence/tactical-economy/policy.md"]
var catalog: Array = []
var costs: Dictionary = {}
var failures: Array = []
var checks := 0

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	catalog = _load_catalog()
	var hashes := _hashes()
	var started := Time.get_ticks_msec()
	var manifest := {"purpose": "rules-only economy; synthetic outcomes are not combat measurements", "seeds": range(1, 21), "policies": POLICIES, "round_count": 6, "source_sha256": hashes, "catalog": catalog, "godot": Engine.get_version_info(), "catalog_session_sha256": FileAccess.get_sha256("res://core/game_session.gd")}
	_write("manifest.json", manifest)
	var runs: Array = []
	for policy in POLICIES:
		for seed_value in range(1, 21):
			var first: Dictionary = _run(policy, seed_value)
			var repeated: Dictionary = _run(policy, seed_value)
			_check(first == repeated, "%s seed %d deterministic replay" % [policy, seed_value])
			runs.append(first)
			_write("%s-seed-%02d.json" % [policy, seed_value], first)
	_check(_hashes() == hashes, "measurement sources unchanged during execution")
	_check(_load_catalog() == catalog, "session catalog unchanged during execution")
	var summary: Dictionary = _summarize(runs)
	var report := {"completed": failures.is_empty(), "synthetic_outcomes_only": true, "actual_combat_simulated": false, "planned_runs": 40, "actual_runs": runs.size(), "deterministic_repeats": runs.size(), "checks": checks, "failures": failures, "wall_seconds": (Time.get_ticks_msec() - started) / 1000.0, "source_sha256": hashes, "summary": summary}
	_write("results.json", report)
	print("LEAGUE_ECONOMY ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _load_catalog() -> Array:
	# Read the authoritative session declarations without loading any combat class.
	var active: Array = []
	var catalog_costs: Dictionary = {}
	for line in FileAccess.get_file_as_string("res://core/game_session.gd").split("\n"):
		if line.begins_with("const ACTIVE="):
			active = JSON.parse_string(line.substr(line.find("=") + 1))
		if line.begins_with("const COSTS="):
			catalog_costs = JSON.parse_string(line.substr(line.find("=") + 1))
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/character_skills.json"))
	var profiles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	var by_key: Dictionary = {}
	for entry in source.characters: by_key[entry.key] = entry
	var result: Array = []
	for key in active:
		result.append({"id": key, "name": profiles.get(key, {}).get("display_name", key), "cost": int(catalog_costs[key]), "ex_cooldown": 5.0 + 5.0 * by_key[key].get("ex", {}).get("originalCost", 2)})
	costs = catalog_costs
	_check(result.size() == 14, "authoritative catalog has 14 characters")
	return result

func _run(policy: String, seed_value: int) -> Dictionary:
	var rules = Match.new()
	var run := {"synthetic_outcomes_only": true, "actual_combat_simulated": false, "policy": policy, "seed": seed_value, "first_two_star_round": 0, "first_deployed_two_star_round": 0, "first_level6_round": 0, "first_six_deployed_round": 0, "spending": {"recruitment": 0, "xp": 0, "refresh": 0}, "rounds": [], "actions": [], "terminal": false}
	_check(rules.new_match(seed_value, catalog, {"level_shop_odds": 1, "reinforcement_recruitment": 1}).ok, "new match")
	var config: Dictionary = rules.snapshot().config
	_check(config.initial_level == 4 and config.max_level == 6 and config.bench_capacity == 9, "4/6/9 bounds")
	for round_number in range(1, 7):
		var before: Dictionary = rules.get_player()
		var first_action: int = run.actions.size()
		if policy == "league_budget_ai":
			rules._prepare_ai(rules._player_ref("p0"))
			run.actions.append({"round": round_number, "type": "league_budget_prepare_ai"})
		else:
			_prepare_player(rules, run, round_number)
		var after: Dictionary = rules.get_player()
		var free_value := 0
		if before.reinforcement.get("status") == "pending" and after.reinforcement.get("status") == "claimed": free_value = int(after.reinforcement.cost)
		var xp_spent := ceili(float(_total_xp(after) - _total_xp(before)) / float(config.xp_gain)) * int(config.xp_cost)
		var recruited: int = _roster_value(after) - _roster_value(before) - free_value
		var refresh_spent: int = before.gold - after.gold - recruited - xp_spent
		_check(recruited >= 0 and refresh_spent >= 0 and refresh_spent % config.refresh_cost == 0, "spending categories reconcile")
		if policy == "pairs_then_population":
			var command_costs := {"recruitment": 0, "xp": 0, "refresh": 0}
			for action in run.actions.slice(first_action):
				var category: String = {"buy_offer": "recruitment", "buy_xp": "xp", "refresh_shop": "refresh"}.get(action.type, "")
				if not category.is_empty(): command_costs[category] += action.gold_before - action.gold_after
			_check(command_costs == {"recruitment": recruited, "xp": xp_spent, "refresh": refresh_spent}, "independent command spending reconciliation")
		var spend := {"recruitment": recruited, "xp": xp_spent, "refresh": refresh_spent}
		for key in spend: run.spending[key] += spend[key]
		_mark(run, after, round_number)
		_validate(rules, "prepared")
		var to_six: int = ceili(float(20 - _total_xp(after)) / float(config.xp_gain)) * int(config.xp_cost)
		var record := {"round": round_number, "gold_start": before.gold, "level_start": before.level, "xp_start": before.xp, "shop_start": before.shop, "level": after.level, "xp": after.xp, "gold": after.gold, "spending": spend, "free_recruitment_value": free_value, "reinforcement": after.reinforcement, "two_star_count": after.units.filter(func(u): return u.star == 2).size(), "deployed_count": after.deployed.size(), "bench_count": after.bench.size(), "player": after, "xp_purchase_cost_to_level6_now": to_six, "level6_gold_shortfall_now": maxi(0, to_six - int(after.gold))}
		var opened: Dictionary = rules.execute({"type": "start_battle"})
		_check(opened.ok, "start six-round battle")
		if not opened.ok: break
		var command := _synthetic_draw(rules, opened.battle)
		record["synthetic_settlement_command"] = command
		var settled: Dictionary = rules.execute(command)
		_check(settled.ok, "synthetic full ledger accepted for budget progression")
		if not settled.ok: break
		var state: Dictionary = rules.snapshot()
		record["income_after"] = state.last_result.income_by_player.get("p0", 0)
		record["gold_after_settlement"] = state.players[0].gold
		record["level_after_settlement"] = state.players[0].level
		record["xp_after_settlement"] = state.players[0].xp
		_check(record.gold_after_settlement == after.gold + record.income_after, "gold conservation")
		_check(state.league.rounds.size() == round_number, "complete league ledger")
		_validate(rules, "settled")
		run.rounds.append(record)
		if round_number == 6:
			_check(state.phase == "finished" and state.round == 6 and state.last_result.income_by_player.is_empty(), "sixth round terminal with no seventh income")
			_check(state.players[0].gold == after.gold and state.players[0].xp == after.xp and state.players[0].level == after.level, "no seventh XP or gold")
			_check(not rules.execute({"type": "start_battle"}).ok, "seventh battle rejected")
			run.terminal = state.phase == "finished"
	run["final_state"] = rules.snapshot()
	return run

func _prepare_player(rules, run: Dictionary, round_number: int) -> void:
	_claim_reinforcement(rules, run, round_number)
	_deploy(rules, run, round_number)
	if round_number == 3 and rules.get_player().gold >= 4 and rules.get_player().level < 5:
		_command(rules, run, round_number, {"type": "buy_xp"})
	if round_number >= 5:
		while rules.get_player().level < 6 and rules.get_player().gold >= 4:
			_command(rules, run, round_number, {"type": "buy_xp"})
	var refreshed := false
	for _attempt in range(16):
		var player: Dictionary = rules.get_player()
		var reserve: int = mini(4, int(player.gold)) if round_number == 4 and player.level < 6 else 0
		var slot := _best_offer(player, reserve)
		if slot >= 0:
			_command(rules, run, round_number, {"type": "buy_offer", "slot": slot})
			_deploy(rules, run, round_number)
		elif round_number <= 2 and not refreshed and _affords_pair_refresh(player):
			_command(rules, run, round_number, {"type": "refresh_shop"})
			refreshed = true
		else: break
	var player: Dictionary = rules.get_player()
	if round_number <= 2:
		for offer in player.shop:
			if not offer.is_empty() and _copies(player, offer.character_id) == 2 and offer.cost > player.gold:
				_command(rules, run, round_number, {"type": "set_shop_locked", "locked": true})
				break
	_deploy(rules, run, round_number)

func _best_offer(player: Dictionary, reserve: int) -> int:
	var best_slot := -1
	var best_score := -100000
	for slot in range(player.shop.size()):
		var offer: Dictionary = player.shop[slot]
		if offer.is_empty() or offer.cost > player.gold - reserve: continue
		var copies: int = _copies(player, offer.character_id)
		if player.bench.size() >= 9 and copies < 2: continue
		if copies == 0 and player.deployed.size() >= player.level: continue
		if copies == 0 and offer.cost > 3: continue
		var visible := 0
		for peer in player.shop:
			if not peer.is_empty() and peer.character_id == offer.character_id: visible += 1
		var score: int = copies * 100 + visible * 20 - int(offer.cost) * 5
		if score > best_score: best_score = score; best_slot = slot
	return best_slot

func _affords_pair_refresh(player: Dictionary) -> bool:
	for key in costs:
		if _copies(player, key) == 2 and player.gold >= 2 + costs[key]: return true
	return false

func _claim_reinforcement(rules, run: Dictionary, round_number: int) -> void:
	var player: Dictionary = rules.get_player()
	var event: Dictionary = player.reinforcement
	if event.get("status") != "pending": return
	var best := -1
	var best_copies := -1
	for slot in range(event.offers.size()):
		var copies := _copies(player, event.offers[slot])
		if player.bench.size() >= 9 and copies < 2: continue
		if copies > best_copies: best = slot; best_copies = copies
	if best >= 0: _command(rules, run, round_number, {"type": "claim_reinforcement", "round": round_number, "slot": best})
	else: _command(rules, run, round_number, {"type": "skip_reinforcement", "round": round_number})

func _deploy(rules, run: Dictionary, round_number: int) -> void:
	var player: Dictionary = rules.get_player()
	var ranked: Array = player.units.duplicate()
	ranked.sort_custom(func(a, b):
		var av: int = int(a.star) * 100 + int(costs[a.character_id]) * 10
		var bv: int = int(b.star) * 100 + int(costs[b.character_id]) * 10
		return av > bv or (av == bv and a.id < b.id))
	var desired: Array = []
	for unit in ranked.slice(0, int(player.level)): desired.append(unit.id)
	for id in player.deployed:
		if not desired.has(id): _command(rules, run, round_number, {"type": "bench_unit", "unit_id": id})
	for id in desired:
		if not rules.get_player().deployed.has(id): _command(rules, run, round_number, {"type": "deploy_unit", "unit_id": id})

func _command(rules, run: Dictionary, round_number: int, command: Dictionary) -> void:
	var before: Dictionary = rules.get_player()
	var result: Dictionary = rules.execute(command)
	_check(result.ok, "legal player command " + JSON.stringify(command) + " " + str(result))
	var record: Dictionary = command.duplicate(true)
	record["round"] = round_number
	record["gold_before"] = before.gold
	record["gold_after"] = rules.get_player().gold
	record["result"] = result
	if command.type == "buy_offer": record["offer"] = before.shop[command.slot]
	run.actions.append(record)

func _synthetic_draw(rules, battle: Dictionary) -> Dictionary:
	var ai: Array = []
	var rows: Array = [_row("p0", battle.opponent_id), _row(battle.opponent_id, "p0")]
	for pair in battle.ai_pairs:
		ai.append({"left_id": pair[0], "right_id": pair[1], "winner": "draw", "left_remaining": rules.get_player(pair[0]).deployed.size(), "right_remaining": rules.get_player(pair[1]).deployed.size(), "duration_ticks": 3000, "finish_reason": "timeout"})
		rows.append(_row(pair[0], pair[1])); rows.append(_row(pair[1], pair[0]))
	return {"type": "resolve_battle", "battle_id": battle.id, "winner": "draw", "player_remaining": battle.player_units.size(), "opponent_remaining": battle.opponent_units.size(), "ai_outcomes": ai, "league_outcomes": rows}

func _row(id: String, opponent: String) -> Dictionary:
	return {"participant_id": id, "opponent_id": opponent, "result": "draw", "remaining_hp_ratio": 0.5}

func _copies(player: Dictionary, character: String) -> int:
	return player.units.filter(func(unit): return unit.star == 1 and unit.character_id == character).size()

func _roster_value(player: Dictionary) -> int:
	var result := 0
	for unit in player.units: result += int(costs[unit.character_id]) * (3 if unit.star == 2 else 1)
	return result

func _total_xp(player: Dictionary) -> int:
	return int(player.xp) + (20 if player.level >= 6 else 8 if player.level >= 5 else 0)

func _mark(run: Dictionary, player: Dictionary, round_number: int) -> void:
	if player.level == 6 and run.first_level6_round == 0: run.first_level6_round = round_number
	if player.deployed.size() == 6 and run.first_six_deployed_round == 0: run.first_six_deployed_round = round_number
	for unit in player.units:
		if unit.star == 2:
			if run.first_two_star_round == 0: run.first_two_star_round = round_number
			if player.deployed.has(unit.id) and run.first_deployed_two_star_round == 0: run.first_deployed_two_star_round = round_number

func _validate(rules, label: String) -> void:
	var state: Dictionary = rules.snapshot()
	for player in state.players:
		_check(player.level >= 4 and player.level <= 6 and player.deployed.size() <= player.level and player.bench.size() <= 9, label + " capacity")
		_check(player.hp == 50 and not player.eliminated, label + " no eliminated participant")
	var restored = Match.new()
	_check(restored.restore(JSON.parse_string(JSON.stringify(state))).ok and restored.snapshot() == state, label + " strict complete ledger roundtrip")

func _summarize(runs: Array) -> Dictionary:
	var summary: Dictionary = {}
	for policy in POLICIES:
		var items: Array = runs.filter(func(run): return run.policy == policy)
		var entry := {"seeds": items.size(), "first_two_star_round": {}, "first_deployed_two_star_round": {}, "first_level6_round": {}, "first_six_deployed_round": {}, "two_star_by_round2": 0, "level6_by_round5": 0, "six_deployed_by_round5": 0, "spending": {}, "rounds": []}
		for item in items:
			for field in ["first_two_star_round", "first_deployed_two_star_round", "first_level6_round", "first_six_deployed_round"]:
				var key: String = "never" if item[field] == 0 else str(item[field])
				entry[field][key] = entry[field].get(key, 0) + 1
			if item.first_two_star_round > 0 and item.first_two_star_round <= 2: entry.two_star_by_round2 += 1
			if item.first_level6_round > 0 and item.first_level6_round <= 5: entry.level6_by_round5 += 1
			if item.first_six_deployed_round > 0 and item.first_six_deployed_round <= 5: entry.six_deployed_by_round5 += 1
		for field in ["recruitment", "xp", "refresh"]:
			entry.spending[field] = _stats(items.map(func(item): return item.spending[field]))
		for round_number in range(1, 7):
			var rows: Array = items.map(func(item): return item.rounds[round_number - 1])
			var row := {"round": round_number, "level_distribution": {}, "deployed_distribution": {}}
			for item in rows:
				row.level_distribution[str(item.level)] = row.level_distribution.get(str(item.level), 0) + 1
				row.deployed_distribution[str(item.deployed_count)] = row.deployed_distribution.get(str(item.deployed_count), 0) + 1
			for field in ["gold_start", "gold", "xp", "two_star_count", "deployed_count", "bench_count", "xp_purchase_cost_to_level6_now", "level6_gold_shortfall_now"]:
				row[field] = _stats(rows.map(func(item): return item[field]))
			for field in ["recruitment", "xp", "refresh"]:
				row["spent_" + field] = _stats(rows.map(func(item): return item.spending[field]))
			entry.rounds.append(row)
		summary[policy] = entry
	return summary

func _stats(values: Array) -> Dictionary:
	values.sort()
	var total := 0.0
	for value in values: total += float(value)
	var count: int = values.size()
	return {"min": values[0], "max": values[-1], "mean": total / count, "median": (float(values[(count - 1) / 2]) + float(values[count / 2])) / 2.0}

func _hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in SOURCE_PATHS: result[path] = FileAccess.get_sha256("res://" + path)
	return result

func _write(filename: String, value: Variant) -> void:
	var file := FileAccess.open(OUT + filename, FileAccess.WRITE)
	_check(file != null, "write " + filename)
	if file != null: file.store_string(JSON.stringify(value, "\t")); file.close()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("ECONOMY_FAIL ", label)
