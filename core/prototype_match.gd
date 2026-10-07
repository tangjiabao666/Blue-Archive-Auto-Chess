extends RefCounted
## Deterministic, scene-free prototype economy. All returned values are copies.
## Balance is deliberately configurable and is not official TFT balance.

const VERSION := 6
const REINFORCEMENT_ROUNDS := {3: 2, 6: 3}
const REINFORCEMENT_KEYS := ["round", "cost", "offers", "status", "selected_slot"]
const ShopOdds=preload("res://core/shop_odds.gd")
const AI_OUTCOME_KEYS := ["left_id", "right_id", "winner", "left_remaining", "right_remaining", "duration_ticks", "finish_reason"]
const AI_RESULT_KEYS := ["left_id", "right_id", "winner", "left_remaining", "right_remaining", "duration_ticks", "finish_reason", "left_damage", "right_damage", "resolution"]
const DEFAULT_CONFIG := {
	"starting_hp": 50, "starting_gold": 10, "bench_capacity": 9,
	"shop_size": 5, "refresh_cost": 2, "initial_level": 4, "max_level": 6,
	"xp_cost": 4, "xp_gain": 4, "round_xp": 2,
	"income": 5, "interest_step": 10, "interest_cap": 5,
	"base_damage": 3, "survivor_damage": 1, "round_damage_interval": 5,
	"ai_purchase_limit": 8, "level_shop_odds": 0, "reinforcement_recruitment": 0,
}
const XP_TO_NEXT := {3: 4, 4: 8, 5: 12, 6: 16}
const DEFAULT_CATALOG := [
	{"id": "shiroko", "name": "Shiroko", "cost": 2},
	{"id": "hoshino", "name": "Hoshino", "cost": 2},
	{"id": "serika", "name": "Serika", "cost": 1},
	{"id": "nonomi", "name": "Nonomi", "cost": 2},
	{"id": "ayane", "name": "Ayane", "cost": 1},
	{"id": "aru", "name": "Aru", "cost": 3},
	{"id": "yuuka", "name": "Yuuka", "cost": 1},
]

var _state: Dictionary = {}

func new_match(seed_value: int = 1, catalog: Array = [], config: Dictionary = {}) -> Dictionary:
	if seed_value < -2147483646 or seed_value > 2147483646:
		return _failure("invalid_seed")
	var settings: Dictionary = DEFAULT_CONFIG.duplicate(true)
	for key in config:
		if not settings.has(key) or not _whole(config[key]) or int(config[key]) < 0 or int(config[key]) > 100000:
			return _failure("invalid_config")
		settings[key] = int(config[key])
	if not _valid_config(settings):
		return _failure("invalid_config")
	var roster: Array = DEFAULT_CATALOG.duplicate(true) if catalog.is_empty() else catalog.duplicate(true)
	if not _valid_catalog(roster) or (settings.level_shop_odds==1 and not ShopOdds.supports(roster)) or (settings.reinforcement_recruitment == 1 and not _supports_reinforcements(roster)):
		return _failure("invalid_catalog")
	roster = _normalize_json(roster)
	for entry in roster:
		entry["cost"] = int(entry.cost)
		entry["name"] = entry.get("name", entry.id)
		entry["ex_cooldown"] = float(entry.get("ex_cooldown", 8.0))
	var normalized_seed: int = ((seed_value % 2147483646) + 2147483646) % 2147483646 + 1
	_state = {
		"version": VERSION, "initial_seed": seed_value, "rng_state": normalized_seed,
		"phase": "preparation", "round": 1, "player_id": "p0", "players": [],
		"catalog": roster, "config": settings, "next_unit_id": 1, "next_battle_id": 1,
		"battle": {}, "last_result": {}, "outcome": "", "placement": 0,
		"last_opponent_id": "", "next_opponent": {},
	}
	for index in range(8):
		var player := {
			"id": "p%d" % index, "name": "Sensei" if index == 0 else "Rival %d" % index,
			"hp": settings.starting_hp, "gold": settings.starting_gold,
			"level": settings.initial_level, "xp": 0, "eliminated": false,
			"units": [], "bench": [], "deployed": [], "shop": [], "shop_locked": false, "reinforcement": {},
		}
		_state.players.append(player)
		_roll_shop(player)
	_prepare_round()
	return _success()

func snapshot() -> Dictionary:
	return _state.duplicate(true)

## Scalar UI queries must not duplicate rosters, shops or league history.
func get_phase() -> String:
	return _state.get("phase", "uninitialized")

func get_player(player_id: String = "p0") -> Dictionary:
	for player in _state.get("players", []):
		if player.id == player_id:
			return player.duplicate(true)
	return {}

func _valid_config(config: Dictionary) -> bool:
	for key in ["starting_hp", "bench_capacity", "shop_size", "refresh_cost", "xp_cost", "xp_gain", "interest_step", "round_damage_interval", "ai_purchase_limit"]:
		if config[key] <= 0 or config[key] > 100000:
			return false
	return config.get("reinforcement_recruitment", 0) in [0,1] and config.level_shop_odds in [0,1] and config.initial_level >= 4 and config.max_level <= 6 and config.initial_level <= config.max_level and config.shop_size <= 20 and config.bench_capacity <= 100

func _valid_catalog(catalog: Array) -> bool:
	if not _json_safe(catalog):
		return false
	if catalog.size() < 7 or catalog.size() > 1000:
		return false
	var seen: Dictionary = {}
	for entry in catalog:
		if not entry is Dictionary or not entry.get("id") is String or entry.id.is_empty() or seen.has(entry.id):
			return false
		if not _whole(entry.get("cost")) or entry.cost < 1 or entry.cost > 1000:
			return false
		if not entry.get("name", entry.id) is String:
			return false
		var cooldown = entry.get("ex_cooldown", 8.0)
		if not (cooldown is int or cooldown is float) or not is_finite(float(cooldown)) or cooldown <= 0:
			return false
		seen[entry.id] = true
	return true

func _supports_reinforcements(catalog: Array) -> bool:
	var counts := {2: 0, 3: 0}
	for entry in catalog:
		if counts.has(int(entry.cost)):
			counts[int(entry.cost)] += 1
	return counts[2] >= 3 and counts[3] >= 3

## Detached finite offer. Reading this record never consumes shared RNG.
func get_reinforcement(player_id: String = "p0") -> Dictionary:
	return get_player(player_id).get("reinforcement", {}).duplicate(true)

func _generate_reinforcements() -> void:
	if _state.config.reinforcement_recruitment == 0 or not REINFORCEMENT_ROUNDS.has(_state.round):
		return
	var cost: int = REINFORCEMENT_ROUNDS[_state.round]
	# Generate for every survivor in fixed participant order before any NPC acts.
	for player in _state.players:
		if player.eliminated or player.reinforcement.get("round", 0) == _state.round:
			continue
		var available: Array = []
		for character in _state.catalog:
			if character.cost == cost:
				available.append(character.id)
		var offers: Array = []
		for _slot in range(3):
			var index: int = _random_index(available.size())
			offers.append(available[index])
			available.remove_at(index)
		player.reinforcement = {"round": _state.round, "cost": cost, "offers": offers, "status": "pending", "selected_slot": -1}

func _reinforcement_command(player: Dictionary, command: Dictionary) -> Dictionary:
	var claim: bool = command.type == "claim_reinforcement"
	var keys: Array = ["type", "round", "slot"] if claim else ["type", "round"]
	if not _exact_keys(command, keys):
		return _failure("invalid_command")
	if not _whole(command.round):
		return _failure("invalid_reinforcement_round")
	if claim and not _bounded(command.slot, 0, 2):
		return _failure("invalid_slot")
	var event: Dictionary = player.reinforcement
	if event.is_empty() or event.status != "pending" or event.round != command.round or event.round != _state.round:
		return _failure("stale_reinforcement")
	if not claim:
		event.status = "skipped"
		return _success()
	var result: Dictionary = _acquire_one_star(player, event.offers[int(command.slot)])
	if result.ok:
		event.status = "claimed"
		event.selected_slot = int(command.slot)
	return result

func _whole(value: Variant) -> bool:
	return (value is int or (value is float and is_finite(value) and value == floor(value))) and value >= -2147483647 and value <= 2147483647

func _random_index(size: int) -> int:
	_state.rng_state = (int(_state.rng_state) * 48271) % 2147483647
	return int(_state.rng_state) % size

func _shop_has_offers(player: Dictionary) -> bool:
	for offer in player.shop:
		if not offer.is_empty():
			return true
	return false

func _roll_shop(player: Dictionary) -> void:
	player.shop_locked = false
	player.shop = []
	for _slot in range(_state.config.shop_size):
		var character: Dictionary = ShopOdds.pick(_state.catalog,int(player.level),Callable(self,"_random_index")) if _state.config.level_shop_odds==1 else _state.catalog[_random_index(_state.catalog.size())]
		player.shop.append({"character_id": character.id, "cost": character.cost})

## Actual next-refresh chances. Does not roll offers or consume RNG.
func get_shop_odds(player_id:String="p0")->Array:
	var player:Dictionary=get_player(player_id)
	if player.is_empty():return []
	return ShopOdds.describe(_state.catalog,int(player.level),_state.config.level_shop_odds==1)

func _success(data: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "error": ""}
	result.merge(data)
	return result.duplicate(true)

func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}

## Execute a command atomically. Invalid transactions also roll back RNG and IDs.
func execute(command: Variant) -> Dictionary:
	if not command is Dictionary or not command.get("type") is String:
		return _failure("invalid_command")
	if _state.is_empty():
		return _failure("no_match")
	var before := _state.duplicate(true)
	var result: Dictionary = _apply_command(command)
	if not result.ok:
		_state = before
	return result.duplicate(true)

func _apply_command(command: Dictionary) -> Dictionary:
	if command.type == "restart":
		var seed_value = command.get("seed", _state.initial_seed)
		if not _whole(seed_value):
			return _failure("invalid_seed")
		return new_match(int(seed_value), _state.catalog, _state.config)
	if command.type == "resolve_battle":
		return _resolve_battle(command)
	if _state.phase != "preparation":
		return _failure("wrong_phase")
	return _apply_player_command(_state.players[0], command)

## Shared participant-scoped economy; caller owns phase, identity and rollback.
func _apply_player_command(player: Dictionary, command: Dictionary) -> Dictionary:
	match command.type:
		"claim_reinforcement", "skip_reinforcement":
			return _reinforcement_command(player, command)
		"start_battle":
			return _start_battle()
		"set_shop_locked":
			if not command.get("locked") is bool:
				return _failure("invalid_shop_lock")
			if command.locked and not _shop_has_offers(player):
				return _failure("empty_shop")
			player.shop_locked = command.locked
			return _success()
		"refresh_shop":
			if player.gold < _state.config.refresh_cost:
				return _failure("insufficient_gold")
			player.gold -= _state.config.refresh_cost
			_roll_shop(player)
			return _success()
		"buy_offer":
			if not _whole(command.get("slot")):
				return _failure("invalid_slot")
			return _buy_offer(player, int(command.slot))
		"sell_unit":
			if not command.get("unit_id") is String:
				return _failure("invalid_unit")
			var unit: Dictionary = _find_unit(player, command.unit_id)
			if unit.is_empty():
				return _failure("unknown_unit")
			var refund: int = _character(unit.character_id).cost * (3 if unit.star == 2 else 1)
			player.gold += refund
			_remove_unit(player, unit.id)
			return _success({"gold_received": refund})
		"deploy_unit", "bench_unit":
			if not command.get("unit_id") is String:
				return _failure("invalid_unit")
			var moving_to_board: bool = command.type == "deploy_unit"
			var source: Array = player.bench if moving_to_board else player.deployed
			var target: Array = player.deployed if moving_to_board else player.bench
			if not source.has(command.unit_id):
				return _failure("unit_not_in_source")
			var cap: int = player.level if moving_to_board else _state.config.bench_capacity
			if target.size() >= cap:
				return _failure("deployment_full" if moving_to_board else "bench_full")
			source.erase(command.unit_id)
			target.append(command.unit_id)
			return _success()
		"buy_xp":
			return _buy_xp(player)
	return _failure("unknown_command")

func _buy_offer(player: Dictionary, slot: int) -> Dictionary:
	if slot < 0 or slot >= player.shop.size():
		return _failure("invalid_slot")
	var offer: Dictionary = player.shop[slot]
	if offer.is_empty():
		return _failure("empty_slot")
	if player.gold < offer.cost:
		return _failure("insufficient_gold")
	var result: Dictionary = _acquire_one_star(player, offer.character_id)
	if not result.ok:
		return result
	player.gold -= offer.cost
	player.shop[slot] = {}
	if not _shop_has_offers(player):
		player.shop_locked = false
	return result

## Shared paid/free acquisition contract; board-first identity preserves manual placement.
func _acquire_one_star(player: Dictionary, character_id: String) -> Dictionary:
	var matching: Array = []
	for unit_id in player.deployed + player.bench:
		var candidate: Dictionary = _find_unit(player, unit_id)
		if candidate.character_id == character_id and candidate.star == 1:
			matching.append(unit_id)
	if player.bench.size() >= _state.config.bench_capacity and matching.size() < 2:
		return _failure("bench_full")
	var unit := {
		"id": "u%06d" % _state.next_unit_id, "character_id": character_id,
		"star": 1, "base_enabled": true, "passive_enabled": true, "ex_enabled": false,
	}
	_state.next_unit_id += 1
	player.units.append(unit)
	player.bench.append(unit.id)
	matching.append(unit.id)
	var merged_ids: Array = []
	var survivor_id: String = unit.id
	if matching.size() >= 3:
		survivor_id = matching[0]
		var survivor: Dictionary = _find_unit(player, survivor_id)
		survivor.star = 2
		survivor.ex_enabled = true
		for consumed_id in [matching[1], matching[2]]:
			merged_ids.append(consumed_id)
			_remove_unit(player, consumed_id)
	return _success({"unit_id": survivor_id, "purchased_unit_id": unit.id, "merged_ids": merged_ids})

func _buy_xp(player: Dictionary) -> Dictionary:
	if player.level >= _state.config.max_level:
		return _failure("max_level")
	if player.gold < _state.config.xp_cost:
		return _failure("insufficient_gold")
	player.gold -= _state.config.xp_cost
	_grant_xp(player, _state.config.xp_gain)
	return _success({"level": player.level, "xp": player.xp})

func _grant_xp(player: Dictionary, amount: int) -> void:
	player.xp += amount
	while player.level < _state.config.max_level and player.xp >= XP_TO_NEXT[player.level]:
		player.xp -= XP_TO_NEXT[player.level]
		player.level += 1
	if player.level >= _state.config.max_level:
		player.xp = 0

func _find_unit(player: Dictionary, unit_id: String) -> Dictionary:
	for unit in player.units:
		if unit.id == unit_id:
			return unit
	return {}

func _remove_unit(player: Dictionary, unit_id: String) -> void:
	player.bench.erase(unit_id)
	player.deployed.erase(unit_id)
	for index in range(player.units.size() - 1, -1, -1):
		if player.units[index].id == unit_id:
			player.units.remove_at(index)
			return

func _character(character_id: String) -> Dictionary:
	for character in _state.catalog:
		if character.id == character_id:
			return character
	return {}

func get_battle_context() -> Dictionary:
	return _state.get("battle", {}).duplicate(true)

## Read-only: the encounter is prepared only when entering a new round.
func get_opponent_preview() -> Dictionary:
	var encounter: Dictionary = _state.get("next_opponent", {})
	if encounter.is_empty():
		return {}
	var opponent: Dictionary = _player_ref(encounter.opponent_id)
	return {
		"round": encounter.round, "opponent_id": opponent.id,
		"name": opponent.name, "hp": opponent.hp, "level": opponent.level,
		"opponent_units": encounter.opponent_units.duplicate(true),
	}

func _prepare_round() -> void:
	_generate_reinforcements()
	var rivals: Array = []
	for index in range(1, _state.players.size()):
		var ai: Dictionary = _state.players[index]
		if not ai.eliminated:
			_prepare_ai(ai)
			rivals.append(ai.id)
	if rivals.is_empty():
		_state.next_opponent = {}
		return
	var choices: Array = rivals.duplicate()
	if choices.size() > 1:
		choices.erase(_state.last_opponent_id)
	var opponent_id: String = choices[_random_index(choices.size())]
	rivals.erase(opponent_id)
	# Lock the full round schedule alongside the displayed army.
	for index in range(rivals.size() - 1, 0, -1):
		var swap: int = _random_index(index + 1)
		var temporary = rivals[index]
		rivals[index] = rivals[swap]
		rivals[swap] = temporary
	var pairs: Array = []
	for index in range(0, rivals.size() - 1, 2):
		pairs.append([rivals[index], rivals[index + 1]])
	_state.next_opponent = {
		"round": _state.round, "opponent_id": opponent_id,
		"opponent_units": _deployed_units(_player_ref(opponent_id)), "ai_pairs": pairs,
		"bye_id": rivals.back() if rivals.size() % 2 == 1 else "",
	}

func _start_battle() -> Dictionary:
	var player: Dictionary = _state.players[0]
	if player.reinforcement.get("status") == "pending":
		return _failure("reinforcement_pending")
	if player.deployed.is_empty():
		return _failure("empty_army")
	if _state.next_opponent.is_empty():
		return _failure("no_opponent")
	_state.battle = _state.next_opponent.duplicate(true)
	_state.battle["id"] = "b%06d" % _state.next_battle_id
	_state.battle["player_units"] = _deployed_units(player)
	_state.next_opponent = {}
	_state.next_battle_id += 1
	_state.last_opponent_id = _state.battle.opponent_id
	_state.phase = "battle"
	return _success({"battle": _state.battle})

func _resolve_battle(command: Dictionary) -> Dictionary:
	if _state.phase != "battle":
		return _failure("wrong_phase")
	var battle: Dictionary = _state.battle
	if not command.get("battle_id") is String or command.battle_id != battle.id:
		return _failure("stale_battle")
	if not command.get("winner") in ["player", "opponent", "draw"]:
		return _failure("invalid_winner")
	if not _whole(command.get("player_remaining")) or not _whole(command.get("opponent_remaining")):
		return _failure("invalid_survivors")
	var player_remaining: int = int(command.player_remaining)
	var opponent_remaining: int = int(command.opponent_remaining)
	if player_remaining < 0 or player_remaining > battle.player_units.size() or opponent_remaining < 0 or opponent_remaining > battle.opponent_units.size():
		return _failure("invalid_survivors")
	if not _valid_player_outcome(command):
		return _failure("inconsistent_result")
	# Validate the complete simulation payload before player damage or any tie-break RNG.
	if command.has("ai_outcomes") and not _valid_ai_outcomes(command.ai_outcomes, battle.ai_pairs):
		return _failure("invalid_ai_outcomes")
	var player: Dictionary = _state.players[0]
	var opponent: Dictionary = _player_ref(battle.opponent_id)
	var player_damage: int = _round_damage(opponent_remaining) if command.winner != "player" else 0
	var opponent_damage: int = _round_damage(player_remaining) if command.winner != "opponent" else 0
	_damage(player, player_damage)
	_damage(opponent, opponent_damage)
	var ai_results: Array = []
	for index in range(battle.ai_pairs.size()):
		var pair: Array = battle.ai_pairs[index]
		var left: Dictionary = _player_ref(pair[0])
		var right: Dictionary = _player_ref(pair[1])
		var duel: Dictionary = _normalize_json(command.ai_outcomes[index]) if command.has("ai_outcomes") else _estimated_ai_outcome(left, right)
		duel["resolution"] = "simulation" if command.has("ai_outcomes") else "estimated"
		duel["left_damage"] = _round_damage(duel.right_remaining) if duel.winner != "left" else 0
		duel["right_damage"] = _round_damage(duel.left_remaining) if duel.winner != "right" else 0
		_damage(left, duel.left_damage)
		_damage(right, duel.right_damage)
		ai_results.append(duel)
	var eliminated_ids: Array = []
	var alive_ai := 0
	for candidate in _state.players:
		if candidate.hp <= 0:
			if not candidate.eliminated:
				eliminated_ids.append(candidate.id)
			candidate.eliminated = true
		elif candidate.id != "p0":
			alive_ai += 1
	_state.last_result = {
		"battle_id": battle.id, "round": _state.round, "winner": command.winner,
		"opponent_id": opponent.id, "player_remaining": player_remaining,
		"opponent_remaining": opponent_remaining, "player_damage": player_damage,
		"opponent_damage": opponent_damage, "ai_results": ai_results,
		"eliminated_ids": eliminated_ids, "income_by_player": {},
	}
	_state.last_result.merge(_result_extension(command),true)
	_state.battle = {}
	_complete_round(player, alive_ai)
	return _success({"result": _state.last_result, "phase": _state.phase, "outcome": _state.outcome})

## Narrow lifecycle hook; the survival implementation remains the default.
func _complete_round(player: Dictionary, alive_ai: int) -> void:
	if player.eliminated or alive_ai == 0:
		_state.phase = "finished"
		_state.outcome = "defeat" if player.eliminated else "victory"
		_state.placement = alive_ai + 1 if player.eliminated else 1
	else:
		for candidate in _state.players:
			if candidate.eliminated:
				continue
			var interest: int = mini(int(candidate.gold) / int(_state.config.interest_step), _state.config.interest_cap)
			var income: int = _state.config.income + interest
			candidate.gold += income
			_grant_xp(candidate, _state.config.round_xp)
			if candidate.shop_locked:
				candidate.shop_locked = false
			else:
				_roll_shop(candidate)
			_state.last_result.income_by_player[candidate.id] = income
		_state.round += 1
		_state.phase = "preparation"
		_prepare_round()

## All pair IDs, order, types and army bounds are checked without touching state.
func _valid_ai_outcomes(outcomes: Variant, pairs: Array) -> bool:
	if not outcomes is Array or outcomes.size() != pairs.size():
		return false
	var seen: Dictionary = {}
	for index in range(pairs.size()):
		var duel = outcomes[index]
		var pair: Array = pairs[index]
		if not _exact_keys(duel, _ai_outcome_keys()):
			return false
		if not duel.left_id is String or not duel.right_id is String or duel.left_id != pair[0] or duel.right_id != pair[1]:
			return false
		if seen.has(duel.left_id) or seen.has(duel.right_id) or duel.left_id == duel.right_id:
			return false
		seen[duel.left_id] = true
		seen[duel.right_id] = true
		var left: Dictionary = _player_ref(duel.left_id)
		var right: Dictionary = _player_ref(duel.right_id)
		if left.is_empty() or right.is_empty():
			return false
		if not _valid_duel_outcome(duel, left.deployed.size(), right.deployed.size(), false):
			return false
		if duel.finish_reason == "empty":
			if not left.deployed.is_empty() and not right.deployed.is_empty():
				return false
			if duel.left_remaining != left.deployed.size() or duel.right_remaining != right.deployed.size():
				return false
		elif left.deployed.is_empty() or right.deployed.is_empty():
			return false
	return true

## Shared live/snapshot semantics. Historical army limits use the population cap.
func _valid_duel_outcome(duel: Dictionary, left_limit: int, right_limit: int, estimated: bool) -> bool:
	if not duel.winner is String or not duel.winner in ["left", "right", "draw"]:
		return false
	if not _bounded(duel.left_remaining, 0, left_limit) or not _bounded(duel.right_remaining, 0, right_limit) or not _bounded(duel.duration_ticks, 0, 2147483647):
		return false
	if duel.winner == "left" and (duel.left_remaining == 0 or duel.right_remaining != 0):
		return false
	if duel.winner == "right" and (duel.right_remaining == 0 or duel.left_remaining != 0):
		return false
	if duel.winner == "draw" and ((duel.left_remaining == 0) != (duel.right_remaining == 0)):
		return false
	if not duel.finish_reason is String:
		return false
	if estimated:
		return duel.finish_reason == "estimated" and duel.duration_ticks == 0 and (duel.winner != "draw" or duel.left_remaining == 0)
	if not duel.finish_reason is String or not duel.finish_reason in ["elimination", "timeout", "empty"]:
		return false
	if duel.finish_reason == "empty":
		return duel.duration_ticks == 0 and (duel.left_remaining == 0 or duel.right_remaining == 0)
	if duel.duration_ticks == 0:
		return false
	if duel.finish_reason == "timeout":
		return duel.winner == "draw" and duel.left_remaining > 0 and duel.right_remaining > 0
	return duel.left_remaining == 0 or duel.right_remaining == 0

func _estimated_ai_outcome(left: Dictionary, right: Dictionary) -> Dictionary:
	var duel := {"left_id": left.id, "right_id": right.id, "winner": "draw", "left_remaining": 0, "right_remaining": 0, "duration_ticks": 0, "finish_reason": "estimated"}
	# The old heuristic's invented survivor for two empty armies cannot be a valid result.
	if left.deployed.is_empty() or right.deployed.is_empty():
		duel.left_remaining = left.deployed.size()
		duel.right_remaining = right.deployed.size()
		if not left.deployed.is_empty():
			duel.winner = "left"
		elif not right.deployed.is_empty():
			duel.winner = "right"
		return duel
	var left_power: int = _army_power(left)
	var right_power: int = _army_power(right)
	var left_wins: bool = left_power > right_power or (left_power == right_power and _random_index(2) == 0)
	duel.winner = "left" if left_wins else "right"
	duel["left_remaining" if left_wins else "right_remaining"] = maxi(1, ceili(float((left if left_wins else right).deployed.size()) / 2.0))
	return duel

func _prepare_ai(player: Dictionary) -> void:
	var target_level: int = mini(_state.config.max_level, _state.config.initial_level + int(_state.round) / 3)
	while player.level < target_level and player.gold >= _state.config.xp_cost + 2:
		_buy_xp(player)
	var refreshed := false
	for _attempt in range(_state.config.ai_purchase_limit):
		var best_slot := -1
		var best_score := -1
		for slot in range(player.shop.size()):
			var offer: Dictionary = player.shop[slot]
			if offer.is_empty() or offer.cost > player.gold:
				continue
			var copies := 0
			for unit in player.units:
				if unit.star == 1 and unit.character_id == offer.character_id:
					copies += 1
			if player.bench.size() >= _state.config.bench_capacity and copies < 2:
				continue
			var score: int = copies * 30 + offer.cost * 3
			if score > best_score:
				best_score = score
				best_slot = slot
		if best_slot >= 0:
			_buy_offer(player, best_slot)
			_auto_deploy(player)
		elif not refreshed and player.gold >= _state.config.refresh_cost + 1:
			player.gold -= _state.config.refresh_cost
			_roll_shop(player)
			refreshed = true
		else:
			break
	_resolve_ai_reinforcement(player)
	_auto_deploy(player)
	# Only our own remaining offers, one-star pairs and gold inform retention.
	player.shop_locked = _has_unaffordable_third_copy(player)

func _resolve_ai_reinforcement(player: Dictionary) -> void:
	var event: Dictionary = player.reinforcement
	if event.get("status") != "pending":
		return
	var best_slot := -1
	var best_copies := -1
	for slot in range(event.offers.size()):
		var copies := 0
		for unit in player.units:
			if unit.star == 1 and unit.character_id == event.offers[slot]:
				copies += 1
		if player.bench.size() >= _state.config.bench_capacity and copies < 2:
			continue
		if copies > best_copies:
			best_slot = slot
			best_copies = copies
	if best_slot < 0:
		event.status = "skipped"
		return
	# Capacity was checked using the same roster; no enemy information or rerolls.
	var result: Dictionary = _acquire_one_star(player, event.offers[best_slot])
	if result.ok:
		event.status = "claimed"
		event.selected_slot = best_slot

func _has_unaffordable_third_copy(player: Dictionary) -> bool:
	for offer in player.shop:
		if offer.is_empty() or offer.cost <= player.gold:
			continue
		var copies := 0
		for unit in player.units:
			if unit.star == 1 and unit.character_id == offer.character_id:
				copies += 1
		if copies == 2:
			return true
	return false

func _auto_deploy(player: Dictionary) -> void:
	var ranked: Array = player.units.duplicate()
	ranked.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_value: int = left.star * 100 + _character(left.character_id).cost * 10
		var right_value: int = right.star * 100 + _character(right.character_id).cost * 10
		return left_value > right_value or (left_value == right_value and left.id < right.id)
	)
	player.deployed = []
	player.bench = []
	for unit in ranked:
		if player.deployed.size() < player.level:
			player.deployed.append(unit.id)
		else:
			player.bench.append(unit.id)

func _deployed_units(player: Dictionary) -> Array:
	var result: Array = []
	for unit_id in player.deployed:
		result.append(_find_unit(player, unit_id).duplicate(true))
	return result

func _army_power(player: Dictionary) -> int:
	var total := 0
	for unit_id in player.deployed:
		var unit: Dictionary = _find_unit(player, unit_id)
		total += (_character(unit.character_id).cost + 3) * (3 if unit.star == 2 else 1)
	return total

func _player_ref(player_id: String) -> Dictionary:
	for player in _state.players:
		if player.id == player_id:
			return player
	return {}

func _round_damage(survivors: int) -> int:
	return _damage_amount(survivors, _state.round, _state.config)

func _damage_amount(survivors: int, round_number: int, config: Dictionary) -> int:
	return config.base_damage + (round_number - 1) / int(config.round_damage_interval) + survivors * config.survivor_damage

func _damage(player: Dictionary, amount: int) -> void:
	player.hp = maxi(0, player.hp - amount)

## Load a JSON-compatible snapshot, validating all active state before committing.
func restore(candidate: Variant) -> Dictionary:
	if not _json_safe(candidate) or not candidate is Dictionary:
		return _failure("invalid_snapshot")
	var normalized: Dictionary = _normalize_json(candidate)
	if not _valid_snapshot(normalized):
		return _failure("invalid_snapshot")
	for entry in normalized.catalog:
		entry["ex_cooldown"] = float(entry.get("ex_cooldown", 8.0))
	_state = normalized
	return _success()

## Legacy schemas are selected only by their exact session envelope pairing.
## First validate every old field, then migrate a detached copy without any RNG.
func restore_legacy_v4(candidate: Variant) -> Dictionary:
	return _restore_legacy(candidate, 4)

func restore_legacy_v5(candidate: Variant) -> Dictionary:
	return _restore_legacy(candidate, 5)

func _restore_legacy(candidate: Variant, schema_version: int) -> Dictionary:
	if not _json_safe(candidate) or not candidate is Dictionary:
		return _failure("invalid_snapshot")
	var normalized: Dictionary = _normalize_json(candidate)
	if not _valid_snapshot(normalized, schema_version):
		return _failure("invalid_snapshot")
	normalized.version = VERSION
	normalized.config["reinforcement_recruitment"] = 0
	for player in normalized.players:
		if schema_version == 4:
			player["shop_locked"] = false
		player["reinforcement"] = {}
	return restore(normalized)

func _json_safe(value: Variant, depth: int = 0) -> bool:
	if depth > 16:
		return false
	if value == null or value is String or value is bool or value is int:
		return true
	if value is float:
		return is_finite(value)
	if value is Array:
		for item in value:
			if not _json_safe(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key in value:
			if not (key is String or key is StringName) or not _json_safe(value[key], depth + 1):
				return false
		return true
	return false

func _normalize_json(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[str(key)] = _normalize_json(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_normalize_json(item))
		return result
	if value is float and _whole(value):
		return int(value)
	return value

func _exact_keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true

func _bounded(value: Variant, minimum: int, maximum: int) -> bool:
	return _whole(value) and value >= minimum and value <= maximum

func _valid_snapshot(state: Dictionary, schema_version: int = VERSION) -> bool:
	if not _exact_keys(state, ["version", "initial_seed", "rng_state", "phase", "round", "player_id", "players", "catalog", "config", "next_unit_id", "next_battle_id", "battle", "last_result", "outcome", "placement", "last_opponent_id", "next_opponent"]):
		return false
	if not schema_version in [4, 5, VERSION] or not _whole(state.version) or state.version != schema_version or not _bounded(state.initial_seed, -2147483646, 2147483646) or not _bounded(state.rng_state, 1, 2147483646):
		return false
	if not _bounded(state.round, 1, 1000000) or not _bounded(state.next_unit_id, 1, 2147483647) or not _bounded(state.next_battle_id, 1, 2147483647):
		return false
	var config_keys: Array = DEFAULT_CONFIG.keys()
	if schema_version < VERSION:
		config_keys.erase("reinforcement_recruitment")
	if not _exact_keys(state.config, config_keys):
		return false
	for key in state.config:
		if not _bounded(state.config[key], 0, 100000):
			return false
	if not _valid_config(state.config):
		return false
	if not state.catalog is Array or not _valid_catalog(state.catalog):
		return false
	if state.config.level_shop_odds==1 and not ShopOdds.supports(state.catalog):
		return false
	if state.config.get("reinforcement_recruitment", 0) == 1 and not _supports_reinforcements(state.catalog):
		return false
	if not state.phase in ["preparation", "battle", "finished"] or not state.player_id is String or state.player_id != "p0":
		return false
	if not state.players is Array or state.players.size() != 8 or not state.battle is Dictionary or not state.last_result is Dictionary or not state.next_opponent is Dictionary:
		return false
	if not state.last_opponent_id is String or not state.last_opponent_id in ["", "p1", "p2", "p3", "p4", "p5", "p6", "p7"]:
		return false
	var characters: Dictionary = {}
	for entry in state.catalog:
		characters[entry.id] = entry
	var global_ids: Dictionary = {}
	var alive_ai := 0
	for index in range(8):
		var player = state.players[index]
		if not _valid_player_snapshot(player, "p%d" % index, state, characters, global_ids, schema_version):
			return false
		if index > 0 and not player.eliminated:
			alive_ai += 1
	if not state.outcome is String or not _bounded(state.placement, 0, 8):
		return false
	if state.phase == "finished":
		if not state.battle.is_empty() or not state.next_opponent.is_empty() or state.last_result.is_empty():
			return false
		if not _valid_finished_state(state, alive_ai):return false
	else:
		if state.players[0].eliminated or alive_ai == 0 or state.outcome != "" or state.placement != 0:
			return false
		if state.phase == "preparation" and (not state.battle.is_empty() or not _valid_encounter_snapshot(state, state.next_opponent)):
			return false
		if state.phase == "battle" and (not state.next_opponent.is_empty() or not _valid_battle_snapshot(state)):
			return false
	if not state.last_result.is_empty() and not _valid_last_result(state.last_result, state):
		return false
	if state.round > 1 and state.last_result.is_empty():
		return false
	return true

func _valid_finished_state(state: Dictionary, alive_ai: int) -> bool:
	if state.players[0].eliminated:return state.outcome == "defeat" and state.placement == alive_ai + 1
	return alive_ai == 0 and state.outcome == "victory" and state.placement == 1

func _valid_player_snapshot(player: Variant, expected_id: String, state: Dictionary, characters: Dictionary, global_ids: Dictionary, schema_version: int = VERSION) -> bool:
	var keys := ["id", "name", "hp", "gold", "level", "xp", "eliminated", "units", "bench", "deployed", "shop"]
	if schema_version >= 5:
		keys.append("shop_locked")
	if schema_version == VERSION:
		keys.append("reinforcement")
	if not _exact_keys(player, keys):
		return false
	if not player.id is String or player.id != expected_id or not player.name is String or not player.eliminated is bool:
		return false
	if not _bounded(player.hp, 0, state.config.starting_hp) or player.eliminated != (player.hp == 0) or not _bounded(player.gold, 0, 2147483647):
		return false
	if not _bounded(player.level, state.config.initial_level, state.config.max_level):
		return false
	var max_xp: int = 0 if player.level == state.config.max_level else XP_TO_NEXT[int(player.level)] - 1
	if not _bounded(player.xp, 0, max_xp):
		return false
	if not player.units is Array or not player.bench is Array or not player.deployed is Array or not player.shop is Array:
		return false
	if player.bench.size() > state.config.bench_capacity or player.deployed.size() > player.level or player.shop.size() != state.config.shop_size:
		return false
	if player.units.size() != player.bench.size() + player.deployed.size():
		return false
	var local_ids: Dictionary = {}
	var one_star_counts: Dictionary = {}
	for unit in player.units:
		if not _exact_keys(unit, ["id", "character_id", "star", "base_enabled", "passive_enabled", "ex_enabled"]):
			return false
		if not unit.id is String or not unit.id.begins_with("u") or not unit.id.substr(1).is_valid_int():
			return false
		var serial: int = unit.id.substr(1).to_int()
		if serial < 1 or serial >= state.next_unit_id or unit.id != "u%06d" % serial or global_ids.has(unit.id):
			return false
		if not unit.character_id is String or not characters.has(unit.character_id) or not _bounded(unit.star, 1, 2):
			return false
		if not unit.base_enabled is bool or unit.base_enabled != true or not unit.passive_enabled is bool or unit.passive_enabled != true or not unit.ex_enabled is bool or unit.ex_enabled != (unit.star == 2):
			return false
		global_ids[unit.id] = true
		local_ids[unit.id] = true
		if unit.star == 1:
			one_star_counts[unit.character_id] = one_star_counts.get(unit.character_id, 0) + 1
			if one_star_counts[unit.character_id] >= 3:
				return false
	var allocated: Dictionary = {}
	for unit_id in player.bench + player.deployed:
		if not unit_id is String or not local_ids.has(unit_id) or allocated.has(unit_id):
			return false
		allocated[unit_id] = true
	for offer in player.shop:
		if not offer is Dictionary:
			return false
		if offer.is_empty():
			continue
		if not _exact_keys(offer, ["character_id", "cost"]) or not offer.character_id is String or not characters.has(offer.character_id):
			return false
		if not _whole(offer.cost) or offer.cost != characters[offer.character_id].cost:
			return false
	if schema_version >= 5 and (not player.shop_locked is bool or (player.shop_locked and not _shop_has_offers(player))):
		return false
	if schema_version == VERSION and not _valid_reinforcement_snapshot(player, state, characters):
		return false
	return true

func _valid_reinforcement_snapshot(player: Dictionary, state: Dictionary, characters: Dictionary) -> bool:
	var event: Variant = player.reinforcement
	if not event is Dictionary:
		return false
	if state.config.reinforcement_recruitment == 0:
		return event.is_empty()
	var latest_round: int = 6 if state.round >= 6 else 3 if state.round >= 3 else 0
	if event.is_empty():
		# Eliminated participants do not receive later reinforcements.
		return latest_round == 0 or player.eliminated
	if not _exact_keys(event, REINFORCEMENT_KEYS):
		return false
	if not _whole(event.round) or not REINFORCEMENT_ROUNDS.has(int(event.round)) or event.round > state.round:
		return false
	if not player.eliminated and event.round != latest_round:
		return false
	if not _whole(event.cost) or event.cost != REINFORCEMENT_ROUNDS[int(event.round)]:
		return false
	if not event.offers is Array or event.offers.size() != 3:
		return false
	var seen: Dictionary = {}
	for character_id in event.offers:
		if not character_id is String or not characters.has(character_id) or seen.has(character_id):
			return false
		if characters[character_id].cost != event.cost:
			return false
		seen[character_id] = true
	if not event.status is String or not event.status in ["pending", "claimed", "skipped"]:
		return false
	if not _whole(event.selected_slot):
		return false
	if event.status == "claimed":
		return _bounded(event.selected_slot, 0, 2)
	if event.selected_slot != -1:
		return false
	if event.status == "pending":
		return state.phase == "preparation" and event.round == state.round and player.id == "p0" and not player.eliminated
	return true

func _valid_battle_snapshot(state: Dictionary) -> bool:
	var battle: Dictionary = state.battle
	if not _exact_keys(battle, ["id", "round", "opponent_id", "player_units", "opponent_units", "ai_pairs", "bye_id"]):
		return false
	if not battle.id is String or battle.id != "b%06d" % (state.next_battle_id - 1) or state.next_battle_id < 2:
		return false
	if not battle.opponent_id is String or battle.opponent_id != state.last_opponent_id or state.players[0].deployed.is_empty():
		return false
	if not battle.player_units is Array or battle.player_units != _deployed_units(state.players[0]):
		return false
	var encounter: Dictionary = battle.duplicate(true)
	encounter.erase("id")
	encounter.erase("player_units")
	return _valid_encounter_snapshot(state, encounter)

func _valid_encounter_snapshot(state: Dictionary, encounter: Dictionary) -> bool:
	if not _exact_keys(encounter, ["round", "opponent_id", "opponent_units", "ai_pairs", "bye_id"]):
		return false
	if not _whole(encounter.round) or encounter.round != state.round:
		return false
	var players: Dictionary = {}
	for player in state.players:
		players[player.id] = player
	if not encounter.opponent_id is String or encounter.opponent_id == "p0" or not players.has(encounter.opponent_id) or players[encounter.opponent_id].eliminated:
		return false
	if not encounter.opponent_units is Array or encounter.opponent_units != _deployed_units(players[encounter.opponent_id]):
		return false
	if not encounter.ai_pairs is Array or not encounter.bye_id is String:
		return false
	var seen := {"p0": true}
	seen[encounter.opponent_id] = true
	for pair in encounter.ai_pairs:
		if not pair is Array or pair.size() != 2:
			return false
		for player_id in pair:
			if not player_id is String or not players.has(player_id) or seen.has(player_id) or players[player_id].eliminated:
				return false
			seen[player_id] = true
	if encounter.bye_id != "":
		if not players.has(encounter.bye_id) or seen.has(encounter.bye_id) or players[encounter.bye_id].eliminated:
			return false
		seen[encounter.bye_id] = true
	for player in state.players:
		if not player.eliminated and not seen.has(player.id):
			return false
	return true

func _valid_last_result(result: Dictionary, state: Dictionary) -> bool:
	if not _exact_keys(result, _last_result_keys()):
		return false
	if not result.battle_id is String or not result.winner in ["player", "opponent", "draw"] or not result.opponent_id in ["p1", "p2", "p3", "p4", "p5", "p6", "p7"]:
		return false
	var previous_battle: int = state.next_battle_id - (2 if state.phase == "battle" else 1)
	var previous_round: int = state.round if state.phase == "finished" else state.round - 1
	if not _bounded(result.round, 1, 1000000) or result.round != previous_round or result.battle_id != "b%06d" % previous_battle:
		return false
	for key in ["player_remaining", "opponent_remaining"]:
		if not _bounded(result[key], 0, state.config.max_level):
			return false
	if not _valid_player_outcome(result):
		return false
	for key in ["player_damage", "opponent_damage"]:
		if not _bounded(result[key], 0, 2147483647):
			return false
	if result.player_damage != (_damage_amount(result.opponent_remaining, result.round, state.config) if result.winner != "player" else 0):
		return false
	if result.opponent_damage != (_damage_amount(result.player_remaining, result.round, state.config) if result.winner != "opponent" else 0):
		return false
	if not result.ai_results is Array or not result.eliminated_ids is Array or not result.income_by_player is Dictionary:
		return false
	var known_ids := ["p0", "p1", "p2", "p3", "p4", "p5", "p6", "p7"]
	var seen: Dictionary = {}
	for player_id in result.eliminated_ids:
		if not player_id in known_ids or seen.has(player_id):
			return false
		seen[player_id] = true
	for player_id in result.income_by_player:
		if not player_id in known_ids or not _bounded(result.income_by_player[player_id], 0, 2147483647):
			return false
	var previous_rivals: Dictionary = {}
	for player in state.players:
		if player.id != "p0" and player.id != result.opponent_id and (not player.eliminated or result.eliminated_ids.has(player.id)):
			previous_rivals[player.id] = true
	if result.ai_results.size() != previous_rivals.size() / 2:
		return false
	seen = {"p0": true}
	seen[result.opponent_id] = true
	var resolution := ""
	for duel in result.ai_results:
		if not _exact_keys(duel, _ai_result_keys()):
			return false
		for player_id in [duel.left_id, duel.right_id]:
			if not player_id is String or not previous_rivals.has(player_id) or seen.has(player_id):
				return false
			seen[player_id] = true
		if not duel.resolution is String or not duel.resolution in ["simulation", "estimated"]:
			return false
		if not resolution.is_empty() and duel.resolution != resolution:
			return false
		resolution = duel.resolution
		if not _valid_duel_outcome(duel, state.config.max_level, state.config.max_level, duel.resolution == "estimated"):
			return false
		for key in ["left_damage", "right_damage"]:
			if not _bounded(duel[key], 0, 2147483647):
				return false
		if duel.left_damage != (_damage_amount(duel.right_remaining, result.round, state.config) if duel.winner != "left" else 0):
			return false
		if duel.right_damage != (_damage_amount(duel.left_remaining, result.round, state.config) if duel.winner != "right" else 0):
			return false
	return true

# Narrow versioned-outcome hooks; legacy defaults retain their exact schema.
func _ai_outcome_keys()->Array:return AI_OUTCOME_KEYS
func _ai_result_keys()->Array:return AI_RESULT_KEYS
func _last_result_keys()->Array:return ["battle_id", "round", "winner", "opponent_id", "player_remaining", "opponent_remaining", "player_damage", "opponent_damage", "ai_results", "eliminated_ids", "income_by_player"]
func _result_extension(_command:Dictionary)->Dictionary:return {}
func _valid_player_outcome(value:Dictionary)->bool:
	if value.winner=="player" and (value.player_remaining==0 or value.opponent_remaining!=0):return false
	if value.winner=="opponent" and (value.opponent_remaining==0 or value.player_remaining!=0):return false
	return true
