extends SceneTree

var checks := 0
var failures := 0
var League

func _initialize() -> void:
	var path := "res://core/tactical_league.gd"
	check(FileAccess.file_exists(path), "six-round league component exists")
	if failures:
		finish()
		return
	League = load(path)
	var league = League.new()
	for method in ["record_round", "standings", "finished", "snapshot", "restore"]:
		check(league.has_method(method), "league exposes " + method)
	if failures:
		finish()
		return
	test_initial_state()
	test_points_and_shared_ranks()
	test_wins_before_health()
	test_exact_health_ties()
	test_six_round_limit()
	test_invalid_rounds_are_atomic()
	test_outcomes_are_detached_and_canonical()
	test_restore_round_trip()
	test_malformed_restore_is_atomic()
	finish()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func finish() -> void:
	print("TACTICAL_LEAGUE checks=", checks, " failures=", failures)
	quit(1 if failures else 0)

func round_rows(results: Array = ["draw", "draw", "draw", "draw"], health: Array = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]) -> Array:
	var rows: Array = []
	var reciprocal := {"win": "loss", "draw": "draw", "loss": "win"}
	for pair in range(4):
		var left := pair * 2
		var right := left + 1
		rows.append({"participant_id": "p" + str(left), "opponent_id": "p" + str(right), "result": results[pair], "remaining_hp_ratio": health[left]})
		rows.append({"participant_id": "p" + str(right), "opponent_id": "p" + str(left), "result": reciprocal[results[pair]], "remaining_hp_ratio": health[right]})
	return rows

func find_row(table: Array, id: String) -> Dictionary:
	for row in table:
		if row.get("participant_id") == id:
			return row
	return {}

func successful(result: Dictionary, label: String) -> bool:
	var ok: bool = result.get("ok", false)
	check(ok, label + ": " + str(result.get("error", "missing error")))
	return ok

func reject_round(league, index: int, rows: Array, label: String) -> void:
	var before: Dictionary = league.snapshot()
	var table: Array = league.standings()
	var result: Dictionary = league.record_round(index, rows)
	check(result.get("ok") == false and result.get("error") is String and not result.error.is_empty(), label + ": informative rejection")
	check(league.snapshot() == before and league.standings() == table, label + ": no partial mutation")

func reject_restore(league, state: Dictionary, label: String) -> void:
	var before: Dictionary = league.snapshot()
	var table: Array = league.standings()
	var result: Dictionary = league.restore(state)
	check(result.get("ok") == false and result.get("error") is String and not result.error.is_empty(), label + ": informative rejection")
	check(league.snapshot() == before and league.standings() == table, label + ": no partial mutation")

func test_initial_state() -> void:
	var league = League.new()
	check(not league.finished(), "empty league is unfinished")
	check(league.snapshot() == {"version": 1, "rounds": []}, "snapshot stores bounded versioned ledger only")
	var rows: Array = league.standings()
	check(rows.size() == 8, "eight participants exist before round one")
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		check(row.get("participant_id") == "p" + str(index), "stable participant display order")
		check(row.get("points") == 0 and row.get("wins") == 0 and row.get("draws") == 0 and row.get("losses") == 0, "initial scoring is zero")
		check(row.get("rounds_played") == 0 and row.get("remaining_hp_ratio") == 0.0 and row.get("rank") == 1, "all initial scores share first rank")

func test_points_and_shared_ranks() -> void:
	var league = League.new()
	var result: Dictionary = league.record_round(1, round_rows(["win", "draw", "win", "win"], [0.7, 0.2, 0.4, 0.8, 0.5, 0.0, 0.7, 0.2]))
	if not successful(result, "valid reciprocal round accepted"):
		return
	check(result.get("round_index") == 1 and result.get("finished") == false, "record result reports accepted round and completion")
	var rows: Array = league.standings()
	check(result.get("standings") == rows, "record result returns current standings")
	var expected := [["p0", 2, 1], ["p6", 2, 1], ["p4", 2, 3], ["p3", 1, 4], ["p2", 1, 5], ["p1", 0, 6], ["p7", 0, 6], ["p5", 0, 8]]
	for index in range(mini(rows.size(), expected.size())):
		check(rows[index].get("participant_id") == expected[index][0] and rows[index].get("points") == expected[index][1] and rows[index].get("rank") == expected[index][2], "points/health sort with competition rank " + str(index))
		check(rows[index].get("rounds_played") == 1, "every participant records exactly one game")
	check(find_row(rows, "p0").get("wins") == 1 and find_row(rows, "p2").get("draws") == 1 and find_row(rows, "p1").get("losses") == 1, "win/draw/loss counters are separate")

func test_wins_before_health() -> void:
	var league = League.new()
	if not successful(league.record_round(1, round_rows(["win", "draw", "draw", "draw"], [0.0, 1.0, 1.0, 1.0, 0.5, 0.5, 0.5, 0.5])), "tie-break round one"):
		return
	if not successful(league.record_round(2, round_rows(["loss", "draw", "draw", "draw"], [0.0, 1.0, 1.0, 1.0, 0.5, 0.5, 0.5, 0.5])), "tie-break round two"):
		return
	var rows: Array = league.standings()
	check(find_row(rows, "p0").points == find_row(rows, "p2").points, "one win equals two draws in points")
	check(find_row(rows, "p0").rank < find_row(rows, "p2").rank, "wins break points ties before cumulative health")
	check(find_row(rows, "p1").rank < find_row(rows, "p0").rank, "health breaks equal points and wins")
	check(find_row(rows, "p2").remaining_hp_ratio == 2.0, "remaining health accumulates across rounds")

func test_exact_health_ties() -> void:
	var league = League.new()
	if not successful(league.record_round(1, round_rows(["draw", "draw", "draw", "draw"], [0.5, 0.5000000001, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5])), "near-tie round"):
		return
	var rows: Array = league.standings()
	check(rows[0].participant_id == "p1" and rows[0].rank == 1, "nonzero health difference is not rounded into tie")
	for index in range(1, rows.size()):
		check(rows[index].rank == 2, "stable IDs never break an exact scoring tie")

func test_six_round_limit() -> void:
	var league = League.new()
	for index in range(1, 7):
		if not successful(league.record_round(index, round_rows(["loss", "loss", "loss", "loss"])), "round " + str(index) + " accepted"):
			return
		check(league.standings().size() == 8, "all participants retained even after repeated losses")
		check(league.finished() == (index == 6), "league ends at exactly round six")
	check(find_row(league.standings(), "p1").points == 12, "six wins award twelve points")
	check(find_row(league.standings(), "p0").losses == 6 and find_row(league.standings(), "p0").rank == 5, "zero-point participant is never eliminated")
	reject_round(league, 7, round_rows(), "seventh round forbidden")
	reject_round(league, 6, round_rows(), "finished round replay forbidden")

func test_invalid_rounds_are_atomic() -> void:
	var league = League.new()
	for index in [-1, 0, 2, 6, 7]:
		reject_round(league, index, round_rows(), "invalid first round " + str(index))
	if not successful(league.record_round(1, round_rows()), "validation baseline"):
		return
	reject_round(league, 1, round_rows(), "duplicate round cannot award points twice")
	reject_round(league, 3, round_rows(), "skipped round rejected")
	var rows: Array = round_rows()
	rows.pop_back()
	reject_round(league, 2, rows, "missing participant")
	rows = round_rows()
	rows.append(rows[0].duplicate(true))
	reject_round(league, 2, rows, "extra participant")
	for value in [null, 1, "row", [], Vector2.ZERO]:
		rows = round_rows()
		rows[7] = value
		reject_round(league, 2, rows, "non-dictionary outcome " + str(value))
	for key in ["participant_id", "opponent_id", "result", "remaining_hp_ratio"]:
		rows = round_rows()
		rows[7].erase(key)
		reject_round(league, 2, rows, "missing outcome key " + key)
	rows = round_rows()
	rows[7].points = 99
	reject_round(league, 2, rows, "unknown outcome field")
	for key in ["participant_id", "opponent_id"]:
		for value in [null, true, 7, 7.0, "p8", "P0", &"p0"]:
			rows = round_rows()
			rows[7][key] = value
			reject_round(league, 2, rows, "invalid " + key + " " + str(value))
	rows = round_rows()
	rows[7].participant_id = "p6"
	reject_round(league, 2, rows, "duplicate participant")
	rows = round_rows()
	rows[7].opponent_id = "p7"
	reject_round(league, 2, rows, "self pairing")
	rows = round_rows()
	rows[7].opponent_id = "p0"
	reject_round(league, 2, rows, "nonreciprocal pairing")
	for value in [null, true, 1, "victory", "WIN", &"win"]:
		rows = round_rows()
		rows[7].result = value
		reject_round(league, 2, rows, "invalid result " + str(value))
	for pair in [["win", "win"], ["loss", "loss"], ["win", "draw"], ["draw", "loss"]]:
		rows = round_rows()
		rows[6].result = pair[0]
		rows[7].result = pair[1]
		reject_round(league, 2, rows, "incompatible pair results " + str(pair))
	for value in [null, true, "0.5", -0.001, 1.001, NAN, INF, -INF, Vector2.ZERO]:
		rows = round_rows()
		rows[7].remaining_hp_ratio = value
		reject_round(league, 2, rows, "invalid remaining HP " + str(value))
	rows = round_rows(["win", "win", "win", "win"], [1, 0, 1, 0, 1, 0, 1, 0])
	successful(league.record_round(2, rows), "integer health endpoints are valid JSON numbers")

func test_outcomes_are_detached_and_canonical() -> void:
	var league = League.new()
	var second = League.new()
	var input: Array = round_rows(["win", "loss", "draw", "draw"])
	var reversed: Array = input.duplicate(true)
	reversed.reverse()
	var result: Dictionary = league.record_round(1, input)
	if not successful(result, "detached round accepted") or not successful(second.record_round(1, reversed), "reordered round accepted"):
		return
	check(league.snapshot() == second.snapshot() and league.standings() == second.standings(), "outcome ordering cannot change canonical state")
	var before: Dictionary = league.snapshot()
	input[0].result = "loss"
	input.clear()
	var copy: Dictionary = league.snapshot()
	copy.rounds[0].outcomes[0].remaining_hp_ratio = 0.01
	copy.rounds.clear()
	var standings_copy: Array = league.standings()
	standings_copy[0].points = 999
	result.standings[0].points = 999
	check(league.snapshot() == before and league.standings() == second.standings(), "input, snapshots, standings and record return are deeply detached")

func test_restore_round_trip() -> void:
	var source = League.new()
	for index in range(1, 7):
		if not successful(source.record_round(index, round_rows(["win", "draw", "loss", "draw"], [0.9, 0.0, 0.8, 0.7, 0.0, 0.3, 0.2, 0.2])), "restore source round " + str(index)):
			return
		var state: Dictionary = JSON.parse_string(JSON.stringify(source.snapshot()))
		var restored = League.new()
		if not successful(restored.restore(state), "JSON round trip at round " + str(index)):
			continue
		check(restored.snapshot() == source.snapshot() and restored.standings() == source.standings() and restored.finished() == source.finished(), "replayed JSON ledger reproduces all derived state")
		state.rounds[0].outcomes[0].result = "loss"
		check(restored.snapshot() == source.snapshot(), "restored state is detached from caller")
	var restored = League.new()
	if successful(restored.restore(source.snapshot()), "restore complete league"):
		reject_round(restored, 7, round_rows(), "restored complete league cannot accept extra round")
		check(successful(restored.restore({"version": 1, "rounds": []}), "restore empty league") and not restored.finished(), "empty ledger resets existing league")
		check(restored.standings()[0].points == 0 and restored.snapshot().rounds.is_empty(), "restore replaces rather than adds scores")

func test_malformed_restore_is_atomic() -> void:
	var league = League.new()
	if not successful(league.record_round(1, round_rows()), "restore rejection baseline"):
		return
	var good: Dictionary = league.snapshot()
	for state in [{}, {"version": 1}, {"rounds": []}, {"version": 1, "rounds": [], "points": {"p0": 99}}]:
		reject_restore(league, state, "invalid top-level schema " + str(state))
	for value in [null, true, "1", 0, 2, 1.1, NAN, INF]:
		var state: Dictionary = good.duplicate(true)
		state.version = value
		reject_restore(league, state, "invalid version " + str(value))
	for value in [null, {}, "rounds", 1, PackedStringArray()]:
		var state: Dictionary = good.duplicate(true)
		state.rounds = value
		reject_restore(league, state, "non-array ledger " + str(value))
	for value in [null, 1, [], "round"]:
		var state: Dictionary = good.duplicate(true)
		state.rounds[0] = value
		reject_restore(league, state, "non-dictionary ledger round " + str(value))
	for value in [null, true, "1", 0, 2, 7, 1.1, NAN, INF, -INF]:
		var state: Dictionary = good.duplicate(true)
		state.rounds[0].round_index = value
		reject_restore(league, state, "invalid ledger round index " + str(value))
	for key in ["round_index", "outcomes"]:
		var state: Dictionary = good.duplicate(true)
		state.rounds[0].erase(key)
		reject_restore(league, state, "missing ledger field " + key)
	var state: Dictionary = good.duplicate(true)
	state.rounds[0].standings = [{"points": 99}]
	reject_restore(league, state, "ledger cannot smuggle aggregate state")
	for value in [null, {}, "outcomes", PackedStringArray()]:
		state = good.duplicate(true)
		state.rounds[0].outcomes = value
		reject_restore(league, state, "invalid saved outcomes type")
	state = good.duplicate(true)
	state.rounds.append(state.rounds[0].duplicate(true))
	reject_restore(league, state, "duplicate saved round")
	state = good.duplicate(true)
	state.rounds.append({"round_index": 3, "outcomes": round_rows()})
	reject_restore(league, state, "out-of-order saved round")
	state = good.duplicate(true)
	state.rounds.append({"round_index": 2, "outcomes": round_rows()})
	state.rounds[1].outcomes[7].remaining_hp_ratio = NAN
	reject_restore(league, state, "late invalid round cannot partially replace original ledger")
	state = {"version": 1, "rounds": []}
	for index in range(1, 8):
		state.rounds.append({"round_index": index, "outcomes": round_rows()})
	reject_restore(league, state, "more than six saved rounds rejected")
