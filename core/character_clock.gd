extends RefCounted
const Sim=preload("res://core/character_sim.gd")
const TacticalSim=preload("res://core/tactical_sim.gd")
var sim=Sim.new()
var accumulator:=0.0
var generation:=0:
	set(value):
		generation=value
		if sim.has_method("set_command_generation"):sim.set_command_generation(value)
func use_combat_mode(mode:String)->bool:
	if sim.phase=="running" or mode not in ["legacy","tactical_v1"]:return false
	if mode=="tactical_v1":
		sim=TacticalSim.new();sim.set_command_generation(generation)
	else:sim=Sim.new()
	accumulator=0.0
	return true
func advance(delta: float) -> Array:
	var batch:Array=[]
	if not is_finite(delta) or delta<0:return batch
	if sim.phase!="running":accumulator=0;return batch
	accumulator+=minf(delta,sim.options.max_ticks*Sim.STEP_SECONDS)
	while accumulator+0.000000001>=Sim.STEP_SECONDS and sim.phase=="running":
		accumulator=maxf(0,accumulator-Sim.STEP_SECONDS)
		for event in sim.step():
			event.generation=generation;batch.append(event)
	if sim.phase!="running":accumulator=0
	return batch
func reset() -> void:
	sim.reset();accumulator=0;generation+=1
