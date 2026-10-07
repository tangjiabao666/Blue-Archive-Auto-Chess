extends RefCounted
## Pure six-round scoring. The bounded round ledger is the only saved authority.
## Rankings use competition ranks (1, 1, 3); IDs only stabilize tied display rows.

const Health=preload('res://core/battle_outcome.gd')
var hp_timeout:bool=false
const VERSION := 1
# One-trillionth scoring precision, summed as integers for stable ties/reloads.
const HEALTH_PRECISION := 1000000000000
const ROUND_COUNT := 6
const PARTICIPANTS := ["p0", "p1", "p2", "p3", "p4", "p5", "p6", "p7"]
const STATE_KEYS := ["version", "rounds"]
const ROUND_KEYS := ["round_index", "outcomes"]
const OUTCOME_KEYS := ["participant_id", "opponent_id", "result", "remaining_hp_ratio"]
const OPPOSITE_RESULT := {"win": "loss", "draw": "draw", "loss": "win"}
const RESULT_POINTS := {"win": 2, "draw": 1, "loss": 0}

var _rounds: Array = []

func record_round(round_index: int, outcomes: Array) -> Dictionary:
	if round_index < 1 or round_index > ROUND_COUNT:
		return _failure("round_out_of_range", "Round index must be between 1 and 6.")
	if round_index <= _rounds.size():
		return _failure("duplicate_round", "Round %d was already recorded." % round_index)
	if round_index != _rounds.size() + 1:
		return _failure("out_of_order_round", "Expected round %d, received %d." % [_rounds.size() + 1, round_index])
	var validated := _validate_outcomes(outcomes)
	if not validated.ok:
		return validated
	_rounds.append({"round_index": round_index, "outcomes": validated.outcomes})
	return {"ok": true, "error": "", "round_index": round_index, "finished": finished(), "standings": standings()}

func standings() -> Array:
	var totals: Dictionary = {}
	var health_units:Dictionary={}
	for id in PARTICIPANTS:
		health_units[id]=0
		totals[id] = {"participant_id": id, "points": 0, "wins": 0, "draws": 0, "losses": 0, "rounds_played": 0, "remaining_hp_ratio": 0.0, "rank": 1}
	for round_record in _rounds:
		for outcome in round_record.outcomes:
			var row: Dictionary = totals[outcome.participant_id]
			row.points += RESULT_POINTS[outcome.result]
			match outcome.result:
				"win": row.wins += 1
				"draw": row.draws += 1
				"loss": row.losses += 1
			row.rounds_played += 1
			health_units[outcome.participant_id]+=int(round(float(outcome.remaining_hp_ratio)*HEALTH_PRECISION))
	for id in PARTICIPANTS:totals[id].remaining_hp_ratio=float(health_units[id])/HEALTH_PRECISION
	var rows: Array = totals.values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.points != b.points:
			return a.points > b.points
		if a.wins != b.wins:
			return a.wins > b.wins
		if a.remaining_hp_ratio != b.remaining_hp_ratio:
			return a.remaining_hp_ratio > b.remaining_hp_ratio
		return a.participant_id < b.participant_id)
	for index in range(1, rows.size()):
		var previous: Dictionary = rows[index - 1]
		var current: Dictionary = rows[index]
		var tied: bool = current.points == previous.points and current.wins == previous.wins and current.remaining_hp_ratio == previous.remaining_hp_ratio
		current.rank = previous.rank if tied else index + 1
	return rows

func finished() -> bool:
	return _rounds.size() == ROUND_COUNT

func snapshot() -> Dictionary:
	return {"version": 2 if hp_timeout else VERSION, "rounds": _rounds.duplicate(true)}

func restore(state: Dictionary) -> Dictionary:
	if not _has_exact_keys(state, STATE_KEYS):
		return _failure("invalid_state_schema", "League state must contain exactly version and rounds.")
	if not _is_json_integer(state.version, 2 if hp_timeout else VERSION, 2 if hp_timeout else VERSION):
		return _failure("invalid_state_version", "Unsupported league state version.")
	if not state.rounds is Array or state.rounds.size() > ROUND_COUNT:
		return _failure("invalid_round_ledger", "Saved rounds must be an array containing at most six rounds.")
	# Re-run record_round validation on an isolated league. A bad later round
	# never leaves an earlier one applied to the current instance.
	var replay = get_script().new()
	replay.hp_timeout=hp_timeout
	for index in range(state.rounds.size()):
		var saved = state.rounds[index]
		if not saved is Dictionary or not _has_exact_keys(saved, ROUND_KEYS):
			return _failure("invalid_saved_round_schema", "Saved round %d must contain exactly round_index and outcomes." % (index + 1))
		if not _is_json_integer(saved.round_index, 1, ROUND_COUNT):
			return _failure("invalid_saved_round_index", "Saved round %d has an invalid round_index." % (index + 1))
		if not saved.outcomes is Array:
			return _failure("invalid_saved_outcomes", "Saved round %d outcomes must be an array." % (index + 1))
		var result: Dictionary = replay.record_round(int(saved.round_index), saved.outcomes)
		if not result.ok:
			return _failure(result.error, "Saved round %d: %s" % [index + 1, result.message])
	_rounds = replay._rounds.duplicate(true)
	return {"ok": true, "error": "", "finished": finished(), "standings": standings()}

func _validate_outcomes(outcomes: Array) -> Dictionary:
	if outcomes.size() != PARTICIPANTS.size():
		return _failure("invalid_participant_count", "Every round requires exactly eight participant outcomes.")
	var by_id: Dictionary = {}
	for index in range(outcomes.size()):
		var outcome = outcomes[index]
		if not outcome is Dictionary or not _has_exact_keys(outcome, _outcome_keys()):
			return _failure("invalid_outcome_schema", "Outcome %d must contain exactly participant_id, opponent_id, result and remaining_hp_ratio." % index)
		if not outcome.participant_id is String or not PARTICIPANTS.has(outcome.participant_id):
			return _failure("invalid_participant_id", "Outcome %d participant_id must be one of p0 through p7." % index)
		if by_id.has(outcome.participant_id):
			return _failure("duplicate_participant", "Participant %s occurs more than once." % outcome.participant_id)
		if not outcome.opponent_id is String or not PARTICIPANTS.has(outcome.opponent_id) or outcome.opponent_id == outcome.participant_id:
			return _failure("invalid_opponent_id", "Participant %s must face a different participant from p0 through p7." % outcome.participant_id)
		if not outcome.result is String or not OPPOSITE_RESULT.has(outcome.result):
			return _failure("invalid_result", "Participant %s result must be win, draw or loss." % outcome.participant_id)
		if not _is_health_ratio(outcome.remaining_hp_ratio):
			return _failure("invalid_remaining_hp_ratio", "Participant %s remaining_hp_ratio must be a finite number in [0, 1]." % outcome.participant_id)
		by_id[outcome.participant_id] = {"participant_id": outcome.participant_id, "opponent_id": outcome.opponent_id, "result": outcome.result, "remaining_hp_ratio": _canonical_ratio(float(outcome.remaining_hp_ratio))}
		if hp_timeout:
			for key in ['remaining_hp_total','maximum_hp_total','duration_ticks','finish_reason']:by_id[outcome.participant_id][key]=outcome[key]
	var canonical: Array = []
	for id in PARTICIPANTS:
		var outcome: Dictionary = by_id[id]
		var opponent: Dictionary = by_id[outcome.opponent_id]
		if opponent.opponent_id != id:
			return _failure("nonreciprocal_pairing", "Participants %s and %s must name each other as opponents." % [id, outcome.opponent_id])
		if opponent.result != OPPOSITE_RESULT[outcome.result]:
			return _failure("incompatible_results", "Participants %s and %s have incompatible results." % [id, outcome.opponent_id])
		if hp_timeout:
			if not _valid_health_pair(outcome,opponent):return _failure('invalid_hp_decision','Total HP, ratio, duration and result must agree.')
			# Canonicalize only after strict whole-number validation, never truncate input.
			for key in ['remaining_hp_total','maximum_hp_total','duration_ticks']:outcome[key]=int(outcome[key])
		canonical.append(outcome)
	return {"ok": true, "error": "", "outcomes": canonical}

func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in value:
		if not key is String or not expected.has(key):
			return false
	return true

func _is_health_ratio(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= 1

func _is_json_integer(value, minimum: int, maximum: int) -> bool:
	# Godot's JSON parser returns floats for integral JSON numbers. Permit
	# those without accepting booleans, strings, fractions or non-finite values.
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum and value == floor(value)

func _failure(error: String, message: String) -> Dictionary:
	return {"ok": false, "error": error, "message": message}

func _canonical_ratio(value:float)->float:
	if value<=0.0:return 0.0
	return float(maxi(1,int(round(value*HEALTH_PRECISION))))/HEALTH_PRECISION

func _outcome_keys()->Array:
	var keys:Array=OUTCOME_KEYS.duplicate()
	if hp_timeout:keys.append_array(['remaining_hp_total','maximum_hp_total','duration_ticks','finish_reason'])
	return keys
func _valid_health_pair(left:Dictionary,right:Dictionary)->bool:
	for row in [left,right]:
		if not Health.whole(row.duration_ticks,1800) or not row.finish_reason is String or row.finish_reason not in ['timeout','elimination','empty']:return false
	if left.duration_ticks!=right.duration_ticks or left.finish_reason!=right.finish_reason:return false
	for row in [left,right]:
		if not Health.whole(row.remaining_hp_total) or not Health.whole(row.maximum_hp_total):return false
		var ratio:float=float(row.remaining_hp_total)/float(row.maximum_hp_total) if row.maximum_hp_total>0 else 0.0
		if _canonical_ratio(ratio)!=row.remaining_hp_ratio:return false
	var duel:Dictionary={'winner':'left' if left.result=='win' else 'right' if left.result=='loss' else 'draw','left_remaining':1 if left.remaining_hp_total>0 else 0,'right_remaining':1 if right.remaining_hp_total>0 else 0,'duration_ticks':left.duration_ticks,'finish_reason':left.finish_reason,'remaining_hp_totals':[left.remaining_hp_total,right.remaining_hp_total],'maximum_hp_totals':[left.maximum_hp_total,right.maximum_hp_total]}
	return Health.valid(duel,1,1,1800)
