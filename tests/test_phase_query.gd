extends SceneTree
## Source-only regression: real economy/league rules without character assets.
## Snapshot instrumentation catches accidentally restoring full-state copying.
class CountingRules extends "res://core/prototype_match.gd":
	var snapshot_calls := 0
	func snapshot() -> Dictionary:
		snapshot_calls += 1
		return super.snapshot()

class CountingTacticalRules extends "res://core/tactical_match.gd":
	var snapshot_calls := 0
	func snapshot() -> Dictionary:
		snapshot_calls += 1
		return super.snapshot()

var checks := 0
var failures := 0

func ck(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL " + label)

func _initialize() -> void:
	_test_rules(CountingRules.new(), "survival")
	_test_rules(CountingTacticalRules.new(), "tactical")
	print("PHASE_QUERY checks=", checks, " failures=", failures)
	quit(1 if failures else 0)

func _expect_phase(rules, expected: String, label: String) -> void:
	var before: Dictionary = rules.snapshot()
	var calls: int = rules.snapshot_calls
	var values: Array = []
	for index in range(100):
		values.append(rules.call("get_phase"))
	ck(values.all(func(value): return value == expected), label + " returns the expected phase")
	ck(rules.snapshot_calls == calls, label + " repeated phase queries never call snapshot")
	ck(rules.snapshot() == before, label + " repeated phase queries preserve match state and RNG")

func _test_rules(rules, label: String) -> void:
	ck(rules.has_method("get_phase"), label + " exposes a scalar phase query")
	if not rules.has_method("get_phase"):
		return
	_expect_phase(rules, "uninitialized", label + " empty rules")
	ck(rules.new_match(17).ok, label + " real rules initialize")
	_expect_phase(rules, "preparation", label + " new match")
	var bought: Dictionary = rules.execute({"type": "buy_offer", "slot": 0})
	ck(bought.ok, label + " buys a unit through real rules")
	if bought.ok:
		ck(rules.execute({"type": "deploy_unit", "unit_id": bought.unit_id}).ok, label + " deploys through real rules")
		ck(rules.execute({"type": "start_battle"}).ok, label + " starts a battle through real rules")
		_expect_phase(rules, "battle", label + " started match")
	# These inputs exercise the read boundary independently of settlement rules.
	rules._state.phase = "finished"
	_expect_phase(rules, "finished", label + " finished match")
	rules._state = {"round": 1}
	_expect_phase(rules, "uninitialized", label + " missing phase fallback")
