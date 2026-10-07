extends SceneTree
const Sim=preload("res://core/character_sim.gd")
const F=preload("res://tests/normal_target_fixtures.gd")
var failures: Array=[]
var checks:=0

func ck(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL: "+label)

func tid(target) -> int:
	return -1 if target==null else int(target.id)

func policy_sim(actor: String="shiroko"):
	return F.make_sim(F.standard_rows(actor),{"normal_target_policies":["wounded","nearest"]})

func option_contract() -> void:
	var sim=Sim.new()
	ck(sim.configure(F.standard_rows(),{}).is_empty(),"omitted option configures")
	ck(sim.options.get("normal_target_policies")==["nearest","nearest"],"omitted options default both teams to nearest")
	ck(sim.get_script().get_script_constant_map().get("NORMAL_TARGET_POLICIES")==["nearest","wounded"],"supported policy enum exposes both strict modes")
	for malformed in [null,false,0,"wounded",{},[],["nearest"],["nearest","nearest","nearest"],["nearest",null],["nearest",1],["nearest",false],["nearest",{}],["nearest",["wounded"]],["nearest","Wounded"],["nearest",""],["nearest",&"wounded"],PackedStringArray(["nearest","wounded"])]:
		var before: String=F.digest([sim.snapshot(),sim._initial,sim.events])
		ck(not sim.configure(F.standard_rows(),{"normal_target_policies":malformed}).is_empty(),"malformed policy rejected: "+str(malformed))
		ck(F.digest([sim.snapshot(),sim._initial,sim.events])==before,"invalid option is atomic: "+str(malformed))
	var chosen: Array=["wounded","nearest"]
	var settings: Dictionary={"normal_target_policies":chosen}
	var error: String=sim.configure(F.standard_rows(),settings)
	ck(error.is_empty(),"valid team policy pair configures: "+error)
	if not error.is_empty():return
	chosen[0]="nearest";settings.normal_target_policies[1]="wounded"
	ck(sim.options.normal_target_policies==["wounded","nearest"],"caller array mutation cannot alter frozen options")
	var snapshot: Dictionary=sim.snapshot();snapshot.adaptations.normal_target_policies[0]="nearest"
	ck(sim.options.normal_target_policies==["wounded","nearest"],"snapshot arrays are detached")
	ck(sim.start(),"policy fixture starts")
	sim._unit(8).hp=100
	ck(tid(sim._normal_target(sim._unit(0)))==8,"copied settings control actual target after caller mutation")
	var live: String=F.digest([sim.snapshot(),sim._initial,sim.events])
	ck(not sim.configure(F.standard_rows(),{"normal_target_policies":["nearest","nearest"]}).is_empty(),"running reconfigure rejected")
	ck(F.digest([sim.snapshot(),sim._initial,sim.events])==live,"running rejection preserves whole state")
	sim.reset();ck(sim.options.normal_target_policies==["wounded","nearest"],"reset preserves configured policies")
	ck(sim.configure(F.standard_rows()).is_empty() and sim.options.normal_target_policies==["nearest","nearest"],"subsequent omitted configure restores defaults")

func selection_contract() -> void:
	var sim=policy_sim();var actor: Dictionary=sim._unit(0);var near: Dictionary=sim._unit(7);var far: Dictionary=sim._unit(8)
	far.hp=100
	ck(tid(sim._normal_target(actor))==8,"wounded selects lower fraction instead of nearest")
	ck(tid(sim._target(actor,actor.range))==7,"shared target selector is unchanged")
	near.hp=100;near.max_hp=1000;far.hp=90;far.max_hp=100
	ck(tid(sim._normal_target(actor))==7,"fraction ranking is not raw HP ranking")
	near.hp=500000;near.max_hp=1000000;far.hp=500000;far.max_hp=1000001
	ck(tid(sim._normal_target(actor))==8,"strict cross-product distinguishes close fractions instead of approximate ties")
	near.hp=1;near.max_hp=2;far.hp=2;far.max_hp=4
	ck(tid(sim._normal_target(actor))==7,"equal rational fractions rank by distance")
	near.cell=Vector2(1.0000005,-1);far.cell=Vector2(1,-1)
	ck(tid(sim._normal_target(actor))==8,"strict squared-distance tie-break rejects approximate grouping")
	near.cell=Vector2(-1,-1);far.cell=Vector2(1,-1);sim.units.reverse()
	ck(tid(sim._normal_target(actor))==7,"equal fraction and squared distance use actor ID independent of iteration")
	near.hp=3025960;near.max_hp=3025960;far.hp=3025959;far.max_hp=3025960
	ck(tid(sim._normal_target(actor))==8,"maximum supported HP cross-products stay exact and within int64")
	near.hp=100;far.hp=1;near.max_hp=100;far.max_hp=100
	far.cell=Vector2(6,-6)
	ck(tid(sim._normal_target(actor))==7,"out-of-range wounded enemy excluded")
	far.cell=Vector2(1,-1);sim.line_of_sight=func(_a,b):return b!=Vector2(1,-1)
	ck(tid(sim._normal_target(actor))==7,"LOS-blocked wounded enemy excluded")
	sim.line_of_sight=Callable();far.hp=0
	ck(tid(sim._normal_target(actor))==7,"dead enemy excluded")
	far.hp=1;far.team=0
	ck(tid(sim._normal_target(actor))==7,"allied low-HP unit excluded")
	near.hp=0
	ck(sim._normal_target(actor)==null,"no eligible enemy yields null")
	# Team indexing must work independently in both directions.
	sim=F.make_sim([F.row(0,0,"shiroko",Vector2(0,1)),F.row(1,0,"shiroko",Vector2(2,2)),F.row(7,1,"shiroko",Vector2(0,-.75))],{"normal_target_policies":["nearest","wounded"]})
	sim._unit(1).hp=1
	ck(tid(sim._normal_target(sim._unit(7)))==1,"right-side wounded policy uses index one")
	ck(tid(sim._target(sim._unit(7),sim._unit(7).range))==0,"right-side shared selector still nearest")

func taunt_contract() -> void:
	var sim=policy_sim();var actor: Dictionary=sim._unit(0);var near: Dictionary=sim._unit(7)
	sim._unit(8).hp=100;actor.taunt_source_id=7;actor.taunt_until=10
	var unchanged: String=F.digest(sim.snapshot())
	ck(tid(sim._normal_target(actor))==7,"active living enemy taunt overrides wounded")
	ck(F.digest(sim.snapshot())==unchanged,"selection is read-only and consumes no RNG")
	sim.line_of_sight=func(_a,b):return b!=Vector2(0,-1)
	ck(sim._normal_target(actor)==null,"blocked valid taunt does not fall back")
	sim.line_of_sight=Callable();near.cell=Vector2(0,-6)
	ck(sim._normal_target(actor)==null,"out-of-range valid taunt does not fall back")
	near.cell=Vector2(0,-1);sim.tick=9
	ck(tid(sim._normal_target(actor))==7,"taunt remains active just before expiry")
	sim.tick=10
	ck(tid(sim._normal_target(actor))==8,"taunt expires at exact until tick")
	sim.tick=0;actor.taunt_until=10;near.hp=0
	ck(tid(sim._normal_target(actor))==8,"dead taunt source falls back to wounded")
	near.hp=near.max_hp;near.team=0
	ck(tid(sim._normal_target(actor))==8,"allied taunt source falls back to wounded")
	near.team=1;actor.taunt_source_id=9999
	ck(tid(sim._normal_target(actor))==8,"missing taunt source falls back to wounded")
	actor.taunt_source_id=-1
	ck(tid(sim._normal_target(actor))==8,"unset taunt source falls back to wounded")

func aim_and_queue_contract() -> void:
	var sim=policy_sim();F.inactive(sim,0);var actor: Dictionary=sim._unit(0)
	var first: Array=sim.step()
	ck(first.filter(func(e):return e.type=="aim" and e.actor_id==0).size()==1,"first normal acquisition begins aim")
	ck(actor.aim_started==1 and actor.aim_ready==45,"Shiroko source acquisition ticks remain 1 to 45")
	sim._unit(8).hp=5000
	var second: Array=sim.step()
	ck(actor.aim_target_id==8 and actor.aim_started==1 and actor.aim_ready==45,"prospective retarget preserves aim readiness")
	ck(second.filter(func(e):return e.type in ["aim","aim_lost"]).is_empty(),"retarget emits no reacquisition or aim-loss events")
	var shots: Array=[]
	while sim.tick<45:
		for event in sim.step():
			if event.type=="attack" and event.actor_id==0:shots.append(event)
	ck(shots.size()==1 and shots[0].tick==45 and shots[0].target_id==8,"retarget fires at original ready boundary")
	ck(actor.ammo==12 and actor.attack_ready==88 and actor.busy_until==61,"normal ammo, period and recovery remain source-derived")
	var queued: Array=sim._pending.duplicate(true)
	ck(queued.map(func(hit):return hit.due)==[46,52,58],"Shiroko committed contacts remain exact source burst ticks")
	ck(queued.map(func(hit):return hit.target)==[8,8,8],"burst commits selected target for all contacts")
	sim._unit(7).hp=100;actor.busy_until=99999
	ck(tid(sim._normal_target(actor))==7 and sim._pending==queued,"later health priority changes do not mutate pending targets or timing")
	var seen: Array=[]
	while sim.tick<=58:
		for event in sim.step():
			if event.type=="damage" and event.actor_id==0:seen.append([event.target_id,event.tick])
	ck(seen==[[8,46],[8,52],[8,58]],"actual queued damage remains pinned to original victim at every contact")
	# Real loss of every firing solution still uses existing movement/aim-loss path.
	sim=policy_sim();F.inactive(sim,0);sim.step();sim.line_of_sight=func(_a,_b):return false
	var lost: Array=sim.step()
	ck(not sim._unit(0).aimed,"LOS loss still clears aim")
	ck(lost.filter(func(e):return e.type=="attack" and e.actor_id==0).is_empty(),"no normal shot through LOS loss")
	# Pending burst never migrates to a replacement after the committed victim dies.
	sim=policy_sim();F.inactive(sim);sim._normal_attack(sim._unit(0),sim._unit(7));sim._unit(7).hp=0
	var contacts: Array=[]
	for i in range(20):
		for event in sim.step():
			if event.type=="damage" and event.actor_id==0:contacts.append(event)
	ck(contacts.is_empty() and sim._pending.is_empty(),"dead committed target cancels future hits without rerouting")
	# Death before due boundary also cancels the source's queued burst.
	sim=policy_sim();F.inactive(sim);sim._normal_attack(sim._unit(0),sim._unit(7));sim._unit(0).hp=0
	var after_death: Array=sim.step()
	ck(after_death.filter(func(e):return e.type=="damage" and e.actor_id==0).is_empty() and sim._pending.is_empty(),"dead source cancels future contacts")

func aris_contract() -> void:
	var sim=F.make_sim([F.row(0,0,"aris",Vector2(0,1)),F.row(7,1,"aris",Vector2(2,-1)),F.row(8,1,"aris",Vector2(0,-2)),F.row(9,1,"aris",Vector2(0,-10))],{"arena_half":12.0,"normal_target_policies":["wounded","nearest"]})
	F.inactive(sim,0);sim._unit(8).hp=7352
	ck(not sim.can_attack(sim._unit(0),sim._unit(9)),"secondary fixture is beyond primary acquisition range")
	var shot: Dictionary={}
	for i in range(60):
		for event in sim.step():
			if event.type=="attack" and event.actor_id==0:shot=event
		if not shot.is_empty():break
	ck(shot.get("target_id")==8,"Aris normal branch selects wounded primary")
	ck(sim._pending.map(func(hit):return hit.target)==[8,9],"Aris line retains original secondary beyond acquisition range")
	sim._unit(0).busy_until=99999;var hit_ids: Array=[]
	for event in sim.step():
		if event.type=="damage" and event.actor_id==0:hit_ids.append(event.target_id)
	ck(hit_ids==[8,9],"both original Aris line victims actually receive scheduled damage")

func parity_contract() -> void:
	var baseline: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(F.BASELINE))
	for count in [4,5,6]:
		for star in [1,2]:
			var name: String="%dv%d-star%d"%[count,count,star]
			var omitted: Dictionary=F.natural_trace(count,star)
			var explicit: Dictionary=F.natural_trace(count,star,true)
			ck(omitted==explicit,name+" omitted and explicit nearest match every full event/snapshot/RNG/queue")
			ck(omitted.trace_sha256==baseline.natural[name].trace_sha256,name+" accepted trace parity strips only declared new metadata")
	for key in F.KEYS:
		for ability in ["basic","ex"]:
			ck(F.skill_dispatch(key,ability,{"normal_target_policies":["wounded","nearest"]})==baseline.skills[key+":"+ability],key+" "+ability+" remains identical to accepted same-state dispatch")
	for name in F.DIAGNOSTICS:
		var nearest: Dictionary=F.diagnostic(name)
		var wounded: Dictionary=F.diagnostic(name,{"normal_target_policies":["wounded","nearest"]})
		ck(nearest.trace_sha256==baseline.diagnostics[name].trace_sha256,name+" default diagnostic preserves exact accepted state/trace")
		ck(nearest.primary_id==7 and wounded.primary_id==8,name+" paired diagnostic selects declared primaries")
		print("DIAGNOSTIC ",name," nearest=",nearest," wounded=",wounded)

func _initialize() -> void:
	option_contract()
	if Sim.new().has_method("_normal_target"):
		selection_contract();taunt_contract();aim_and_queue_contract();aris_contract();parity_contract()
	else:ck(false,"normal-only selector is not implemented")
	print("NORMAL TARGET ENGINE CHECKS=",checks," FAILURES=",failures.size())
	quit(1 if not failures.is_empty() else 0)
