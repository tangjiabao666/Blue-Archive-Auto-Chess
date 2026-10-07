extends RefCounted
const Sim = preload("res://core/character_sim.gd")
const BASELINE = "res://tests/fixtures/normal_target/accepted4990a6b.json"
const DIAGNOSTICS = ["finish_off", "armor_mismatch", "existing_shield", "aris_line_gain", "aris_line_loss", "committed_overkill"]
const KEYS = ["shiroko", "hoshino", "hina", "aru", "yuuka", "aris", "serina", "serika", "iori", "tsubaki", "nonomi", "mutsuki", "haruna", "koharu"]

static func row(id: int, team: int, key: String, cell: Vector2, star: int = 1) -> Dictionary:
	return {"id":id,"team":team,"character_id":key,"cell":cell,"star":star}

static func standard_rows(actor: String = "aru", far: String = "shiroko") -> Array:
	return [row(0,0,actor,Vector2(0,.75)),row(7,1,"shiroko",Vector2(0,-1)),row(8,1,far,Vector2(2,-2))]

static func make_sim(rows: Array, settings: Dictionary = {}):
	var sim = Sim.new()
	var opts := {"seed":1729,"random_damage":false}
	opts.merge(settings,true)
	var error: String = sim.configure(rows,opts)
	assert(error.is_empty(), error)
	assert(sim.start())
	return sim

static func inactive(sim, active_id: int = -1) -> void:
	for u in sim.units:
		u.basic_ready=99999;u.skill_ready=99999;u.basic_activations=1;u.sub_ready=99999
		if u.id != active_id:u.busy_until=99999

static func digest(value) -> String:
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(var_to_bytes(value))
	return hash_context.finish().hex_encode()

static func old_snapshot(sim) -> Dictionary:
	var snapshot: Dictionary=sim.snapshot()
	snapshot.adaptations.erase("normal_target_policies")
	snapshot.adaptations.erase("area_ex_coverage_targeting")
	return snapshot

static func natural_rows(count: int, star: int) -> Array:
	var rows: Array=[]
	for team in range(2):
		for slot in range(count):
			rows.append(row(team*7+slot,team,KEYS[(slot+team*count)%KEYS.size()],Vector2(-4.5+1.8*slot,3.5 if team==0 else -3.5),star))
	return rows

static func natural_trace(count: int, star: int, explicit_nearest: bool = false) -> Dictionary:
	var opts := {"seed":1700+count,"random_damage":true,"initial_basic_delay_cap_seconds":5.0,"max_ticks":1200}
	if explicit_nearest:opts.normal_target_policies=["nearest","nearest"]
	var sim=make_sim(natural_rows(count,star),opts)
	var old_hash := HashingContext.new();old_hash.start(HashingContext.HASH_SHA256)
	var full_hash := HashingContext.new();full_hash.start(HashingContext.HASH_SHA256)
	old_hash.update(var_to_bytes(old_snapshot(sim)));full_hash.update(var_to_bytes(sim.snapshot()))
	var event_count:=0
	while sim.phase=="running":
		var batch: Array=sim.step();event_count+=batch.size()
		old_hash.update(var_to_bytes([batch,old_snapshot(sim)]));full_hash.update(var_to_bytes([batch,sim.snapshot()]))
	return {"trace_sha256":old_hash.finish().hex_encode(),"full_sha256":full_hash.finish().hex_encode(),"ticks":sim.tick,"event_count":event_count,"winner":sim.winner}

static func diagnostic(name: String, settings: Dictionary = {}) -> Dictionary:
	var rows := standard_rows()
	if name=="armor_mismatch":rows=standard_rows("aru","tsubaki")
	if name=="existing_shield":rows=standard_rows("aru","yuuka")
	if name in ["aris_line_gain","aris_line_loss"]:
		rows=[row(0,0,"aris",Vector2(0,.75)),row(7,1,"aris",Vector2(0,-1)),row(8,1,"aris",Vector2(2,-1.25)),row(9,1,"aris",Vector2(4,-3.25) if name=="aris_line_gain" else Vector2(0,-3))]
	if name=="committed_overkill":rows.append(row(1,0,"shiroko",Vector2(3,.75)))
	var sim=make_sim(rows,settings);inactive(sim,0)
	match name:
		"finish_off":sim._unit(8).hp=3000
		"armor_mismatch":sim._unit(7).hp=3500;sim._unit(8).hp=2000
		"existing_shield":
			sim._unit(7).hp=3500;sim._unit(8).hp=1000
			sim._shield(sim._unit(8),sim.character_data("yuuka").ex.barrierHealPowerRatio,99999,"ex")
		"aris_line_gain","aris_line_loss":sim._unit(8).hp=int(floor(.8*sim._unit(8).max_hp))
		"committed_overkill":
			sim._unit(8).hp=1;sim._normal_attack(sim._unit(1),sim._unit(8));sim._unit(1).busy_until=99999
			sim._unit(0).aimed=true;sim._unit(0).aim_ready=1;sim._unit(0).aim_target_id=7
	var hash_context := HashingContext.new();hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(var_to_bytes(old_snapshot(sim)))
	var shot: Dictionary={};var contacts: Array=[];var scheduled: Array=[]
	for i in range(250):
		var batch: Array=sim.step()
		for event in batch:
			if event.type=="attack" and event.actor_id==0:
				shot=event.duplicate(true)
				for hit in sim._pending:
					if hit.source==0:scheduled.append(hit.duplicate(true))
				sim._unit(0).busy_until=99999
			if event.type=="damage" and event.actor_id==0:contacts.append(event.duplicate(true))
		hash_context.update(var_to_bytes([batch,old_snapshot(sim)]))
		if not shot.is_empty() and sim._pending.is_empty():break
	assert(not shot.is_empty())
	var damage:=0;var absorbed:=0;var kills:=0;var victims: Array=[]
	for event in contacts:
		damage+=event.amount;absorbed+=event.absorbed
		if event.target_id not in victims:victims.append(event.target_id)
	for u in sim.units:
		if u.team==1 and u.hp<=0:kills+=1
	return {"trace_sha256":hash_context.finish().hex_encode(),"primary_id":shot.target_id,"attack_tick":shot.tick,"last_tick":sim.tick,"actor_hp_damage":damage,"actor_absorbed":absorbed,"actor_victim_ids":victims,"actor_scheduled_hits":scheduled.size(),"actor_resolved_hits":contacts.size(),"enemy_deaths_all_sources":kills}

static func skill_dispatch(key: String, ability: String, settings: Dictionary = {}) -> String:
	var sim=make_sim([row(0,0,key,Vector2(0,.75),2),row(1,0,"shiroko",Vector2(-1,.75),2),row(7,1,"shiroko",Vector2(0,-1)),row(8,1,"shiroko",Vector2(2,-2))],settings)
	sim._unit(8).hp=100;sim._unit(1).hp=100
	var accepted: bool=sim._try_skill(sim._unit(0),ability)
	return digest([accepted,sim.events,old_snapshot(sim)])
