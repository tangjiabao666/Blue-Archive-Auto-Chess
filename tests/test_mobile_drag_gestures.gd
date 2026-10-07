extends SceneTree

var checks := 0
var failures := 0

func ck(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL " + label)

func _initialize() -> void:
	var path := "res://scripts/mobile_drag_gestures.gd"
	ck(FileAccess.file_exists(path), "mobile gesture controller exists")
	if failures:
		finish()
		return
	var gestures = load(path).new()
	ck(not gestures.is_pending() and not gestures.is_dragging(), "new controller is idle")
	ck(gestures.begin("actor", 10, Vector2(100, 100), 7), "actor gesture starts")
	ck(gestures.is_pending() and not gestures.is_dragging(), "pointer down is pending without movement")
	var request: Dictionary = gestures.finish(Vector2(100, 100), true, 7)
	ck(request == {"action": "select", "kind": "actor", "identity": 10, "screen": Vector2(100, 100), "generation": 7}, "actor tap selects without issuing movement")
	ck(not gestures.is_pending(), "actor tap clears gesture")
	ck(gestures.finish(Vector2(100, 100), true, 7).is_empty(), "duplicate release cannot repeat a request")
	ck(gestures.begin("ex", 0, Vector2(50, 850), 7), "zero-index EX slot starts")
	request = gestures.finish(Vector2(50, 850), false, 7)
	ck(request == {"action": "arm", "kind": "ex", "identity": 0, "screen": Vector2(50, 850), "generation": 7}, "EX button tap outside field arms without casting")
	ck(not gestures.is_pending(), "EX tap leaves arm state to tactical input")
	gestures.begin("actor", 12, Vector2(80, 90), 8)
	var state: Dictionary = gestures.snapshot()
	ck(state == {"kind": "actor", "identity": 12, "screen": Vector2(80, 90), "origin": Vector2(80, 90), "generation": 8, "pointer": 0, "dragging": false, "pending": true}, "snapshot exposes preview identity and pointer state")
	state.identity = 99
	ck(gestures.snapshot().identity == 12, "snapshot cannot mutate controller state")
	gestures.cancel()
	ck(not gestures.is_pending() and not gestures.is_dragging(), "cancel clears gesture")
	ck(gestures.finish(Vector2(200, 200), true, 8).is_empty(), "cancelled gesture cannot release")
	test_drag_threshold(gestures)
	test_pointer_ownership(gestures)
	test_lifecycle_cancellation(gestures)
	test_invalid_input(gestures)
	finish()

func test_drag_threshold(gestures) -> void:
	gestures.begin("actor", 10, Vector2(100, 100), 7)
	gestures.update(Vector2(111.999, 100))
	ck(not gestures.is_dragging(), "movement below 12 logical pixels remains a tap")
	ck(gestures.finish(Vector2(111.999, 100), true, 7).get("action") == "select", "sub-threshold actor release never moves")
	gestures.begin("actor", 10, Vector2(100, 100), 7)
	gestures.update(Vector2(108, 108))
	ck(not gestures.is_dragging(), "threshold uses Euclidean distance, not Manhattan distance")
	gestures.update(Vector2(112, 100))
	ck(gestures.is_dragging(), "exactly 12 logical pixels starts dragging")
	ck(gestures.snapshot().screen == Vector2(112, 100), "preview uses current owner position")
	var request: Dictionary = gestures.finish(Vector2(250, 300), true, 7)
	ck(request == {"action": "move", "kind": "actor", "identity": 10, "screen": Vector2(250, 300), "generation": 7}, "actor drag yields one move intent at release position")
	ck(not gestures.is_dragging() and not gestures.is_pending(), "drag release clears preview state")
	ck(gestures.finish(Vector2(260, 310), true, 7).is_empty(), "move release cannot issue twice")
	gestures.begin("ex", 2, Vector2(50, 850), 7)
	request = gestures.finish(Vector2(500, 300), true, 7)
	ck(request == {"action": "cast", "kind": "ex", "identity": 2, "screen": Vector2(500, 300), "generation": 7}, "EX release computes drag even without motion event")
	ck(gestures.finish(Vector2(500, 300), true, 7).is_empty(), "cast release cannot issue twice")
	gestures.begin("actor", 10, Vector2(100, 100), 7)
	gestures.update(Vector2(200, 100))
	gestures.update(Vector2(100, 100))
	ck(gestures.is_dragging(), "drag classification stays latched after moving back")
	ck(gestures.finish(Vector2(100, 100), true, 7).get("action") == "move", "return to origin does not become an unintended tap")
	for kind in ["actor", "ex"]:
		gestures.begin(kind, 1, Vector2(100, 100), 7)
		ck(gestures.finish(Vector2(500, 950), false, 7).is_empty(), kind + " drag released off-field is cancelled")
		ck(not gestures.is_pending(), kind + " off-field cancellation clears pointer")

func test_pointer_ownership(gestures) -> void:
	gestures.begin("actor", 10, Vector2(100, 100), 7, 2)
	ck(not gestures.begin("ex", 0, Vector2(200, 850), 7, 3), "second pointer cannot replace owner")
	ck(not gestures.begin("actor", 20, Vector2(200, 200), 7, 2), "duplicate press cannot replace active owner identity")
	gestures.update(Vector2(600, 400), 3)
	ck(not gestures.is_dragging() and gestures.snapshot().screen == Vector2(100, 100), "secondary motion cannot drag or move preview")
	ck(gestures.finish(Vector2(600, 400), true, 7, 3).is_empty(), "secondary release emits nothing")
	ck(gestures.is_pending(), "secondary release leaves owner pending")
	gestures.update(Vector2(112, 100), 2)
	ck(gestures.is_dragging(), "owner still drags after second pointer ignored")
	var request: Dictionary = gestures.finish(Vector2(400, 300), true, 7, 2)
	ck(request.get("action") == "move" and request.get("identity") == 10, "owner release preserves original actor")
	ck(gestures.finish(Vector2(400, 300), true, 7, 2).is_empty(), "owner duplicate release emits nothing")
	ck(gestures.begin("ex", 1, Vector2(100, 800), 7, 3), "new pointer may own next gesture")
	gestures.cancel()

func test_lifecycle_cancellation(gestures) -> void:
	for kind in ["actor", "ex"]:
		gestures.begin(kind, 1, Vector2(100, 100), 7)
		gestures.update(Vector2(200, 200))
		gestures.cancel() # App focus loss / menu / phase exit invokes this same API.
		ck(gestures.finish(Vector2(300, 300), true, 7).is_empty(), kind + " focus or phase cancellation cannot later issue intent")
		ck(gestures.snapshot() == {"kind": "", "identity": -1, "screen": Vector2.ZERO, "origin": Vector2.ZERO, "generation": -1, "pointer": -1, "dragging": false, "pending": false}, kind + " cancel clears all preview data")
		gestures.begin(kind, 1, Vector2(100, 100), 7)
		ck(gestures.finish(Vector2(300, 300), true, 8).is_empty(), kind + " stale generation cannot issue intent after restart")
		ck(not gestures.is_pending(), kind + " stale generation consumes old gesture")
		ck(gestures.finish(Vector2(300, 300), true, 7).is_empty(), kind + " old generation cannot revive cancelled gesture")
	gestures.cancel()
	gestures.cancel()
	gestures.update(Vector2(500, 500))
	ck(not gestures.is_pending() and gestures.snapshot().screen == Vector2.ZERO, "cancel and idle updates are harmless")
	ck(gestures.begin("actor", 10, Vector2(100, 100), 8), "controller accepts fresh generation after lifecycle cancellation")
	ck(gestures.finish(Vector2(200, 100), true, 8).get("generation") == 8, "fresh intent retains new generation")

func test_invalid_input(gestures) -> void:
	for invalid_kind in ["", "move", "cast", "Actor"]:
		ck(not gestures.begin(invalid_kind, 0, Vector2.ZERO, 7), "unsupported kind rejected: " + invalid_kind)
		gestures.cancel()
	ck(not gestures.begin("actor", -1, Vector2.ZERO, 7), "negative actor identity rejected")
	gestures.cancel()
	ck(not gestures.begin("ex", -1, Vector2.ZERO, 7), "negative EX slot rejected")
	gestures.cancel()
	ck(not gestures.begin("actor", 0, Vector2.ZERO, -1), "negative generation rejected")
	gestures.cancel()
	ck(not gestures.begin("actor", 0, Vector2.ZERO, 7, -1), "negative pointer rejected")
	gestures.cancel()
	for point in [Vector2(INF, 0), Vector2(0, -INF), Vector2(NAN, 0), Vector2(0, NAN)]:
		ck(not gestures.begin("actor", 10, point, 7), "nonfinite origin rejected")
		ck(not gestures.is_pending(), "invalid origin never claims pointer")
		gestures.cancel()
		gestures.begin("actor", 10, Vector2.ZERO, 7)
		gestures.update(point)
		ck(not gestures.is_pending(), "nonfinite owner motion cancels gesture")
		ck(gestures.finish(Vector2(100, 100), true, 7).is_empty(), "finite release cannot revive corrupted motion")
		gestures.begin("ex", 0, Vector2.ZERO, 7)
		ck(gestures.finish(point, true, 7).is_empty(), "nonfinite release never emits cast")
		ck(not gestures.is_pending(), "nonfinite owner release clears gesture")
		gestures.cancel()
	gestures.begin("actor", 10, Vector2(100, 100), 7, 2)
	gestures.update(Vector2(NAN, 0), 3)
	ck(gestures.is_pending(), "invalid secondary motion cannot cancel valid owner")
	ck(gestures.finish(Vector2(INF, 0), true, 8, 3).is_empty() and gestures.is_pending(), "invalid stale secondary release cannot cancel owner")
	ck(gestures.finish(Vector2(100, 100), true, 7, 2).get("action") == "select", "owner still finishes after invalid secondary events")

func finish() -> void:
	print("MOBILE_DRAG_GESTURES checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
