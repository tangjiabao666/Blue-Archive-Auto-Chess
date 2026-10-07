extends RefCounted
const Sim = preload("res://core/arena_sim.gd")
var sim = Sim.new()
var accumulator := 0.0
var generation := 0

func advance(delta: float) -> Array:
	var batch: Array = []
	if not is_finite(delta) or delta < 0.0: return batch
	if sim.phase != "running":
		accumulator = 0.0
		return batch
	# No frame-time dropping: at most MAX_TICKS remain in a whole battle.
	accumulator += minf(delta, Sim.MAX_TICKS * Sim.STEP_SECONDS)
	while accumulator + 0.000000001 >= Sim.STEP_SECONDS and sim.phase == "running":
		accumulator = maxf(0.0, accumulator - Sim.STEP_SECONDS)
		for event in sim.step():
			event["generation"] = generation
			batch.append(event)
	if sim.phase != "running": accumulator = 0.0
	return batch

func reset() -> void:
	sim.reset()
	accumulator = 0.0
	generation += 1
