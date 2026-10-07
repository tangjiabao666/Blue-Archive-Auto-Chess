extends RefCounted
const Sim=preload("res://core/character_sim.gd")
const Hooks=preload("res://core/combat_arena_hooks.gd")
const Nav=preload("res://core/obstacle_navigation.gd")
const KEYS=["hina","hoshino","nonomi","aris","haruna","iori","aru","mutsuki"]
const ALL_KEYS=["shiroko","hoshino","hina","aru","yuuka","aris","serina","serika","iori","tsubaki","nonomi","mutsuki","haruna","koharu"]
const BASELINE="res://tests/fixtures/area_ex_accepted79e21ec.json"

static func row(id:int,team:int,key:String,point:Vector2,star:int=1)->Dictionary:
	return {"id":id,"team":team,"character_id":key,"cell":point,"star":star}

# Canonical natural-cast audit formation. Mirror is the same formation/team swap.
static func rows(key:String,mirror:bool=false)->Array:
	var result=[row(0,0,key,Vector2(0,.75),2),row(1,0,"yuuka",Vector2(3,.75)),row(7,1,"yuuka",Vector2(-1,-.75)),row(8,1,"tsubaki",Vector2(2,-1.25)),row(9,1,"aris",Vector2(2.6,-1.85)),row(10,1,"haruna",Vector2(3.2,-2.45))]
	if mirror:
		for r in result:r.team=1-r.team;r.cell.y=-r.cell.y
	return result

static func make_sim(key:String="hina",settings:Dictionary={},arena:bool=false,mirror:bool=false):
	var sim=Sim.new()
	if arena:
		var nav=Nav.new();nav.configure(Hooks.HALF_SIZE,Hooks.OBSTACLES)
		var hooks=Hooks.new();hooks.bind(sim,nav,Hooks.OBSTACLES)
	var opts={"random_damage":false};opts.merge(settings,true)
	var error:String=sim.configure(rows(key,mirror),opts)
	assert(error.is_empty(),error)
	assert(sim.start())
	return sim

static func digest(value)->String:
	var ctx=HashingContext.new();ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(value));return ctx.finish().hex_encode()

static func state(sim)->Array:
	var snapshot:Dictionary=sim.snapshot()
	snapshot.adaptations.erase("area_ex_coverage_targeting")
	return [sim.events.duplicate(true),snapshot]

static func ids(victims:Array)->Array:
	var result:Array=[]
	for victim in victims:
		var id:int=victim.id if victim is Dictionary else int(victim)
		if not id in result:result.append(id)
	result.sort();return result

static func ex_hits(sim)->Array:
	return sim._pending.filter(func(h):return h.source==0 and h.ability=="ex" and h.effect=="damage")

static func hit_ids(sim)->Array:
	return ids(ex_hits(sim).map(func(h):return h.target))

static func first_cast(sim)->Dictionary:
	for i in range(250):
		for event in sim.step():
			if event.type=="skill" and event.actor_id==0:return event
		if sim.phase!="running":break
	return {}

# Frozen same-state source dispatch, including complete events/pending hit metadata.
# Forced targets allow selected-center parity without changing dispatch arithmetic.
static func dispatch(key:String,ability:String,settings:Dictionary={},forced:int=-1,charges:int=0):
	var sim=make_sim(key,settings);var actor:Dictionary=sim._unit(0)
	actor.charges=charges;sim._unit(1).hp=100;sim._unit(8).hp=100
	if forced>=0:actor.taunt_source_id=forced;actor.taunt_until=1000
	var accepted:bool=sim._try_skill(actor,ability)
	return {"accepted":accepted,"digest":digest(state(sim)),"sim":sim}

static func baseline()->Dictionary:
	var result:Dictionary={"source_commit":"79e21ec","dispatch":{},"forced":{},"natural":{}}
	for key in ALL_KEYS:
		for ability in ["basic","ex"]:
			var d=dispatch(key,ability);result.dispatch[key+":"+ability]=d.digest
	for key in KEYS:
		for candidate in [7,8,9,10]:
			for charges in ([0,1,2] if key=="aris" else [0]):
				var d=dispatch(key,"ex",{},candidate,charges)
				result.forced["%s:%d:%d"%[key,candidate,charges]]=d.digest
		var sim=make_sim(key,{"initial_basic_delay_cap_seconds":5.0,"overtime_enabled":true},true)
		var cast=first_cast(sim)
		result.natural[key]={"digest":digest(state(sim)),"target":cast.get("target_id",-1),"tick":sim.tick,"victims":hit_ids(sim)}
	return result
