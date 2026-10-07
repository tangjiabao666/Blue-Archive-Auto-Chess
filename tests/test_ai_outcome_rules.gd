extends SceneTree
## Real result contracts exercise the actual economy, rollback and JSON validator.
const Rules = preload("res://core/prototype_match.gd")
const OUTCOME_KEYS = ["left_id", "right_id", "winner", "left_remaining", "right_remaining", "duration_ticks", "finish_reason"]
const RESULT_KEYS = ["left_id", "right_id", "winner", "left_remaining", "right_remaining", "duration_ticks", "finish_reason", "left_damage", "right_damage", "resolution"]
var failures := 0
var assertions := 0

func ck(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	_test_actual_damage_and_replay()
	_test_rejected_payloads_are_atomic()
	_test_empty_armies()
	_test_estimated_fallback()
	_test_snapshot_validation()
	_test_empty_estimated_fallback()
	_test_historical_results()
	print("AI OUTCOME RULES ASSERTIONS=", assertions, " FAILURES=", failures)
	quit(1 if failures else 0)

func _prepared_rules() -> RefCounted:
	var rules = Rules.new()
	ck(rules.new_match(17).ok, "fixture starts a real match")
	var bought: Dictionary = rules.execute({"type": "buy_offer", "slot": 0})
	ck(bought.ok and rules.execute({"type": "deploy_unit", "unit_id": bought.unit_id}).ok, "fixture buys and deploys through real commands")
	return rules

func _started_rules() -> RefCounted:
	var rules = _prepared_rules()
	ck(rules.execute({"type": "start_battle"}).ok, "fixture locks battle")
	return rules

func _outcomes(rules: RefCounted) -> Array:
	var rows: Array = []
	for pair in rules.get_battle_context().ai_pairs:
		rows.append({"left_id": pair[0], "right_id": pair[1], "winner": "left", "left_remaining": 1, "right_remaining": 0, "duration_ticks": 100, "finish_reason": "elimination"})
	return rows

func _command(rules: RefCounted, outcomes: Variant) -> Dictionary:
	return {"type": "resolve_battle", "battle_id": rules.get_battle_context().id, "winner": "player", "player_remaining": 1, "opponent_remaining": 0, "ai_outcomes": outcomes}

func _set_army(state: Dictionary, player_id: String, count: int, character: String = "serika", star: int = 1) -> void:
	for player in state.players:
		if player.id != player_id:
			continue
		player.units = []
		player.bench = []
		player.deployed = []
		for index in range(count):
			var unit_id := "u%06d" % state.next_unit_id
			state.next_unit_id += 1
			player.units.append({"id": unit_id, "character_id": character, "star": star, "base_enabled": true, "passive_enabled": true, "ex_enabled": star == 2})
			player.deployed.append(unit_id)

func _reject(rules: RefCounted, command: Dictionary, label: String) -> void:
	var before: Dictionary = rules.snapshot()
	var result: Dictionary = rules.execute(command)
	ck(not result.ok, label + " rejected")
	ck(rules.snapshot() == before, label + " leaves HP, RNG, IDs, schedule and all state unchanged")
	# Keep independent cases meaningful when running against an implementation that accepts invalid input.
	if rules.snapshot() != before:
		rules.restore(before)

func _test_actual_damage_and_replay() -> void:
	var rules = _prepared_rules()
	var state: Dictionary = rules.snapshot()
	var first_pair: Array = state.next_opponent.ai_pairs[0]
	_set_army(state, first_pair[0], 4, "aru", 2)
	_set_army(state, first_pair[1], 2)
	ck(rules.restore(state).ok, "priced army fixture restores")
	ck(rules.execute({"type": "start_battle"}).ok, "priced army fixture starts")
	var before: Dictionary = rules.snapshot()
	var outcomes: Array = _outcomes(rules)
	outcomes[0].winner = "right"
	outcomes[0].left_remaining = 0
	outcomes[0].right_remaining = 2
	outcomes[1].winner = "draw"
	outcomes[1].left_remaining = 1
	outcomes[1].right_remaining = 2
	outcomes[1].duration_ticks = 2400
	outcomes[1].finish_reason = "timeout"
	outcomes[2].winner = "draw"
	outcomes[2].left_remaining = 0
	outcomes[2].right_remaining = 0
	ck(rules._army_power(rules._player_ref(first_pair[0])) > rules._army_power(rules._player_ref(first_pair[1])), "reported loser has dominant price/star power")
	var replay = Rules.new()
	ck(replay.restore(JSON.parse_string(JSON.stringify(before))).ok, "battle JSON restores before real resolution")
	var command := _command(rules, outcomes)
	var result: Dictionary = rules.execute(command)
	ck(result.ok, "complete ordered simulation payload accepted")
	ck(replay.execute(JSON.parse_string(JSON.stringify(command))).ok, "JSON outcomes accepted by restored battle")
	ck(replay.snapshot() == rules.snapshot(), "real outcomes reproduce next schedule, armies, income and economy RNG exactly")
	ck(rules.get_player(first_pair[0]).hp == 45 and rules.get_player(first_pair[1]).hp == 50, "actual cheap winner with two survivors damages price-dominant loser")
	ck(rules.get_player(outcomes[1].left_id).hp == 45 and rules.get_player(outcomes[1].right_id).hp == 46, "timeout draw damages both sides using opposing actual survivors")
	ck(rules.get_player(outcomes[2].left_id).hp == 47 and rules.get_player(outcomes[2].right_id).hp == 47, "double elimination draw damages both sides with zero survivors")
	var rows: Array = result.result.ai_results
	ck(rows.size() == outcomes.size(), "one canonical result per AI pair")
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		ck(row.size() == RESULT_KEYS.size(), "canonical row has exactly ten fields")
		for key in OUTCOME_KEYS:
			ck(row.get(key) == outcomes[index][key], "canonical row preserves " + key)
		ck(row.get("resolution") == "simulation", "supplied outcome marked simulation")
	ck(rows[0].get("left_damage") == 5 and rows[0].get("right_damage") == 0, "canonical damage names identify damaged side")
	outcomes[0].right_remaining = 99
	rows[0]["left_damage"] = 99
	ck(rules.snapshot() == replay.snapshot(), "input and returned rows cannot mutate committed result")
	var restored = Rules.new()
	ck(restored.restore(JSON.parse_string(JSON.stringify(rules.snapshot()))).ok, "resolved version-six snapshot round trips JSON")
	ck(restored.snapshot() == rules.snapshot(), "JSON restore preserves canonical result exactly")

func _test_rejected_payloads_are_atomic() -> void:
	var rules = _started_rules()
	var rows: Array = _outcomes(rules)
	for malformed in [null, {}, "rows", 3, true]:
		_reject(rules, _command(rules, malformed), "non-array outcomes " + str(malformed))
	_reject(rules, _command(rules, []), "missing all pairs")
	var altered: Array = rows.duplicate(true)
	altered.pop_back()
	_reject(rules, _command(rules, altered), "missing last pair")
	altered = rows.duplicate(true)
	altered.append(rows[0].duplicate(true))
	_reject(rules, _command(rules, altered), "extra duplicate pair")
	altered = rows.duplicate(true)
	altered[1] = altered[0].duplicate(true)
	_reject(rules, _command(rules, altered), "duplicate participant")
	altered = rows.duplicate(true)
	altered.reverse()
	_reject(rules, _command(rules, altered), "out-of-order pairs")
	altered = rows.duplicate(true)
	altered[0].left_id = rows[0].right_id
	altered[0].right_id = rows[0].left_id
	_reject(rules, _command(rules, altered), "reversed sides")
	for invalid in ["p0", "p99", rules.get_battle_context().opponent_id, 1, null]:
		altered = rows.duplicate(true)
		altered[0].left_id = invalid
		_reject(rules, _command(rules, altered), "invalid left participant " + str(invalid))
	for key in OUTCOME_KEYS:
		altered = rows.duplicate(true)
		altered[0].erase(key)
		_reject(rules, _command(rules, altered), "missing " + key)
	altered = rows.duplicate(true)
	altered[0]["extra"] = 1
	_reject(rules, _command(rules, altered), "extra outcome field")
	for invalid in [null, [], "row", 9]:
		altered = rows.duplicate(true)
		altered[0] = invalid
		_reject(rules, _command(rules, altered), "malformed row " + str(invalid))
	for key in ["left_remaining", "right_remaining", "duration_ticks"]:
		for invalid in [-1, 0.5, "1", true, null, 2147483648, NAN, INF]:
			altered = rows.duplicate(true)
			altered[0][key] = invalid
			_reject(rules, _command(rules, altered), "invalid " + key + " " + str(invalid))
	for key in ["left_remaining", "right_remaining"]:
		altered = rows.duplicate(true)
		altered[0][key] = rules.get_player(rows[0].left_id if key == "left_remaining" else rows[0].right_id).deployed.size() + 1
		_reject(rules, _command(rules, altered), "survivors exceed locked army " + key)
	for change in [
		{"winner": "player"}, {"winner": 1}, {"winner": null},
		{"winner": "left", "left_remaining": 0}, {"winner": "left", "right_remaining": 1},
		{"winner": "right", "right_remaining": 0}, {"winner": "right", "right_remaining": 1},
		{"winner": "draw", "left_remaining": 1, "right_remaining": 0},
		{"finish_reason": "estimated"}, {"finish_reason": "other"}, {"finish_reason": 1},
		{"duration_ticks": 0}, {"finish_reason": "empty", "duration_ticks": 0},
		{"finish_reason": "timeout"}, {"finish_reason": "timeout", "winner": "draw", "left_remaining": 0},
		{"finish_reason": "elimination", "winner": "draw", "left_remaining": 1, "right_remaining": 1},
	]:
		altered = rows.duplicate(true)
		altered[0].merge(change, true)
		_reject(rules, _command(rules, altered), "inconsistent result " + str(change))
	var stale := _command(rules, rows)
	stale.battle_id = "b999999"
	_reject(rules, stale, "stale battle")
	altered = rows.duplicate(true)
	altered[-1].left_remaining = -1
	var before: Dictionary = rules.snapshot()
	ck(not rules._resolve_battle(_command(rules, altered)).ok, "direct resolver rejects invalid final row")
	ck(rules.snapshot() == before, "all AI rows validated before resolver mutates player HP or RNG even without execute rollback")

func _test_empty_armies() -> void:
	for counts in [[0, 0], [0, 2], [2, 0]]:
		var rules = _prepared_rules()
		var state: Dictionary = rules.snapshot()
		var pair: Array = state.next_opponent.ai_pairs[0]
		_set_army(state, pair[0], counts[0])
		_set_army(state, pair[1], counts[1])
		ck(rules.restore(state).ok and rules.execute({"type": "start_battle"}).ok, "empty army fixture starts " + str(counts))
		var rows: Array = _outcomes(rules)
		rows[0].winner = "draw" if counts == [0, 0] else ("left" if counts[0] > 0 else "right")
		rows[0].left_remaining = counts[0]
		rows[0].right_remaining = counts[1]
		rows[0].duration_ticks = 0
		rows[0].finish_reason = "empty"
		var altered: Array = rows.duplicate(true)
		altered[0].duration_ticks = 1
		_reject(rules, _command(rules, altered), "empty resolution consumes no ticks")
		altered = rows.duplicate(true)
		altered[0]["left_remaining" if counts[0] == 0 else "right_remaining"] = 1
		_reject(rules, _command(rules, altered), "empty side cannot have survivor")
		if counts != [0, 0]:
			altered = rows.duplicate(true)
			altered[0]["left_remaining" if counts[0] > 0 else "right_remaining"] = 1
			_reject(rules, _command(rules, altered), "empty duel cannot kill nonempty side units")
		ck(rules.execute(_command(rules, rows)).ok, "valid empty army outcome accepted")
		ck(rules.get_player(pair[0]).hp == (50 if counts[0] > 0 else 47 - counts[1]), "empty duel applies actual right survivor damage")
		ck(rules.get_player(pair[1]).hp == (50 if counts[1] > 0 else 47 - counts[0]), "empty duel applies actual left survivor damage")
		ck(Rules.new().restore(JSON.parse_string(JSON.stringify(rules.snapshot()))).ok, "empty outcome snapshot restores")

func _test_estimated_fallback() -> void:
	var rules = _started_rules()
	var command := _command(rules, [])
	command.erase("ai_outcomes")
	var result: Dictionary = rules.execute(command)
	ck(result.ok, "omission keeps standalone estimated fallback")
	for row in result.result.ai_results:
		ck(row.get("resolution") == "estimated" and row.get("finish_reason") == "estimated" and row.get("duration_ticks") == 0, "fallback rows explicitly labeled estimated")
		ck(row.size() == RESULT_KEYS.size(), "fallback uses same canonical fields")
	ck(Rules.new().restore(JSON.parse_string(JSON.stringify(rules.snapshot()))).ok, "estimated version-six snapshot restores")

func _test_snapshot_validation() -> void:
	var rules = _started_rules()
	ck(rules.snapshot().version == 6, "snapshot schema version is six")
	var before: Dictionary = rules.snapshot()
	var old: Dictionary = before.duplicate(true)
	old.version = 3
	ck(not rules.restore(old).ok and rules.snapshot() == before, "old version-three shop semantics explicitly rejected atomically")
	old.version = 2
	ck(not rules.restore(old).ok and rules.snapshot() == before, "old version-two snapshots explicitly rejected atomically")
	var config_tamper: Dictionary = before.duplicate(true)
	config_tamper.config["ai_resolution_mode"] = "estimated"
	ck(not rules.restore(config_tamper).ok, "no fallback configuration switch accepted")
	ck(rules.execute(_command(rules, _outcomes(rules))).ok, "snapshot fixture resolves")
	before = rules.snapshot()
	if not before.last_result.ai_results[0].has("left_id"):
		ck(false, "snapshot validation requires canonical simulation rows")
		return
	for key in RESULT_KEYS:
		var altered: Dictionary = before.duplicate(true)
		altered.last_result.ai_results[0].erase(key)
		ck(not rules.restore(altered).ok and rules.snapshot() == before, "snapshot rejects missing AI field " + key)
	for change in [{"round": 0}, {"round": before.round}, {"battle_id": "garbage"}, {"player_remaining": 7}, {"player_damage": 1}, {"opponent_damage": 99}]:
		var changed_result: Dictionary = before.duplicate(true)
		changed_result.last_result.merge(change, true)
		ck(not rules.restore(changed_result).ok and rules.snapshot() == before, "snapshot rejects inconsistent result metadata " + str(change))
	var changes := [
		{"left_id": "p0"}, {"left_id": before.last_result.opponent_id}, {"left_id": "p9"},
		{"left_id": before.last_result.ai_results[0].right_id},
		{"left_remaining": 7}, {"left_remaining": 0.5}, {"right_remaining": -1},
		{"left_remaining": "1"}, {"duration_ticks": -1}, {"duration_ticks": 0.5},
		{"duration_ticks": "1"}, {"duration_ticks": true}, {"winner": "right"},
		{"resolution": "unknown"}, {"resolution": "estimated"}, {"finish_reason": "estimated"},
		{"resolution": "estimated", "finish_reason": "estimated", "duration_ticks": 0},
		{"left_damage": 1}, {"right_damage": 1}, {"right_damage": -1},
		{"right_damage": 4.5}, {"extra": "field"},
	]
	for change in changes:
		var altered: Dictionary = before.duplicate(true)
		altered.last_result.ai_results[0].merge(change, true)
		ck(not rules.restore(altered).ok and rules.snapshot() == before, "snapshot rejects tampered AI result " + str(change))
		if rules.snapshot() != before:
			rules.restore(before)
	var altered: Dictionary = before.duplicate(true)
	altered.last_result.ai_results[1] = altered.last_result.ai_results[0].duplicate(true)
	ck(not rules.restore(altered).ok and rules.snapshot() == before, "snapshot rejects duplicate AI participants")
	altered = before.duplicate(true)
	altered.last_result.ai_results.pop_back()
	ck(not rules.restore(altered).ok and rules.snapshot() == before, "snapshot rejects missing historical AI pair")
	rules.restore(before)
	altered = before.duplicate(true)
	altered.last_result.ai_results[0] = {"winner_id": "p1", "loser_id": "p2", "damage": 4}
	ck(not rules.restore(altered).ok and rules.snapshot() == before, "version-six snapshot rejects legacy AI result row")

func _test_empty_estimated_fallback() -> void:
	for counts in [[0, 0], [0, 2], [2, 0]]:
		var rules = _prepared_rules()
		var state: Dictionary = rules.snapshot()
		var pair: Array = state.next_opponent.ai_pairs[0]
		_set_army(state, pair[0], counts[0])
		_set_army(state, pair[1], counts[1])
		ck(rules.restore(state).ok and rules.execute({"type": "start_battle"}).ok, "estimated empty fixture starts")
		var command := _command(rules, [])
		command.erase("ai_outcomes")
		var resolved: Dictionary = rules.execute(command)
		ck(resolved.ok, "estimated empty duel resolves")
		var row: Dictionary = resolved.result.ai_results[0]
		ck(row.left_remaining == counts[0] and row.right_remaining == counts[1], "estimated empty duel preserves exactly the nonempty army")
		ck(row.winner == ("draw" if counts == [0, 0] else ("left" if counts[0] > 0 else "right")), "estimated empty duel has possible winner")
		ck(row.resolution == "estimated" and row.finish_reason == "estimated" and row.duration_ticks == 0, "estimated empty result stays explicitly labeled")
		ck(Rules.new().restore(JSON.parse_string(JSON.stringify(rules.snapshot()))).ok, "estimated empty result is restorable without invented survivors")

func _test_historical_results() -> void:
	var rules = _prepared_rules()
	var rounds := 0
	while rules.snapshot().phase != "finished" and rounds < 30:
		ck(rules.execute({"type": "start_battle"}).ok, "historical replay starts round")
		var replay = Rules.new()
		ck(replay.restore(JSON.parse_string(JSON.stringify(rules.snapshot()))).ok, "battle snapshot accepts prior round's canonical result")
		var rows: Array = _outcomes(rules)
		for row in rows:
			row.winner = "draw"
			row.finish_reason = "timeout"
			row.left_remaining = rules.get_player(row.left_id).deployed.size()
			row.right_remaining = rules.get_player(row.right_id).deployed.size()
		var command := _command(rules, rows)
		ck(rules.execute(command).ok and replay.execute(command).ok, "subsequent real round resolves")
		ck(replay.snapshot() == rules.snapshot(), "subsequent replay matches entire state")
		ck(Rules.new().restore(JSON.parse_string(JSON.stringify(rules.snapshot()))).ok, "historical survivors remain valid after next-round army preparation")
		rounds += 1
	ck(rules.snapshot().phase == "finished" and rules.snapshot().outcome == "victory", "real-rules match reaches restorable victory")
	var defeat = Rules.new()
	ck(defeat.new_match(17, [], {"starting_hp": 1}).ok, "defeat fixture starts")
	var bought: Dictionary = defeat.execute({"type": "buy_offer", "slot": 0})
	ck(bought.ok and defeat.execute({"type": "deploy_unit", "unit_id": bought.unit_id}).ok and defeat.execute({"type": "start_battle"}).ok, "defeat fixture deploys")
	var losing := _command(defeat, _outcomes(defeat))
	losing.winner = "opponent"
	losing.player_remaining = 0
	losing.opponent_remaining = 1
	ck(defeat.execute(losing).ok and defeat.snapshot().outcome == "defeat", "real-rules match reaches defeat")
	ck(Rules.new().restore(JSON.parse_string(JSON.stringify(defeat.snapshot()))).ok, "terminal defeat canonical result restores")
