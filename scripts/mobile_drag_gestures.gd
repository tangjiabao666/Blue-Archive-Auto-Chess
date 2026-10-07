extends RefCounted
## Translates one pointer gesture into an intent for the existing tactical input.
## It owns no selection, EX arm state, command sequence, combat, or resources.

const DRAG_THRESHOLD := 12.0

var _kind := ""
var _identity := -1
var _origin := Vector2.ZERO
var _screen := Vector2.ZERO
var _generation := -1
var _pointer := -1
var _pending := false
var _dragging := false

func begin(kind: String, identity: int, screen: Vector2, generation: int, pointer: int = 0) -> bool:
	if _pending or kind not in ["actor", "ex"]:
		return false
	if identity < 0 or generation < 0 or pointer < 0 or not screen.is_finite():
		return false
	_kind = kind
	_identity = identity
	_origin = screen
	_screen = screen
	_generation = generation
	_pointer = pointer
	_pending = true
	_dragging = false
	return true

func update(screen: Vector2, pointer: int = 0) -> void:
	if not _pending or pointer != _pointer:
		return
	if not screen.is_finite():
		cancel()
		return
	_screen = screen
	_dragging = _dragging or _origin.distance_to(screen) >= DRAG_THRESHOLD

func finish(screen: Vector2, inside_field: bool, generation: int, pointer: int = 0) -> Dictionary:
	if not _pending or pointer != _pointer:
		return {}
	if generation != _generation or not screen.is_finite():
		cancel()
		return {}
	# A platform may coalesce every motion event before the release.
	update(screen, pointer)
	if _dragging and not inside_field:
		cancel()
		return {}
	var action := "select" if _kind == "actor" else "arm"
	if _dragging:
		action = "move" if _kind == "actor" else "cast"
	var request := {
		"action": action,
		"kind": _kind,
		"identity": _identity,
		"screen": screen,
		"generation": _generation,
	}
	cancel()
	return request

func cancel() -> void:
	_kind = ""
	_identity = -1
	_origin = Vector2.ZERO
	_screen = Vector2.ZERO
	_generation = -1
	_pointer = -1
	_pending = false
	_dragging = false

func is_pending() -> bool:
	return _pending

func is_dragging() -> bool:
	return _dragging

func snapshot() -> Dictionary:
	return {
		"kind": _kind,
		"identity": _identity,
		"origin": _origin,
		"screen": _screen,
		"generation": _generation,
		"pointer": _pointer,
		"pending": _pending,
		"dragging": _dragging,
	}
