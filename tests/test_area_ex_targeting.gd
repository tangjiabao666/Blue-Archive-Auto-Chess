extends SceneTree
const Sim=preload("res://core/character_sim.gd")
const F=preload("res://tests/area_ex_target_fixtures.gd")
var failures:Array=[]
var checks:=0

func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL: "+label)

func tid(target)->int:return -1 if target==null else int(target.id)
func skill(sim)->Dictionary:return sim.character_data(sim._unit(0).character_id).ex
func reach(sim)->float:return float(skill(sim).get("targetingRangeSourceUnits",sim._unit(0).range*100))/sim.options.source_units_per_world_unit
func selected(sim)->int:return tid(sim._area_ex_target(sim._unit(0),skill(sim),reach(sim)))

func option_contract()->void:
	var sim=Sim.new()
	ck(sim.configure(F.rows("hina")).is_empty(),"omitted option configures")
	ck(sim.options.get("area_ex_coverage_targeting")==false,"default explicitly disables coverage targeting")
	for bad in [null,0,1,0.0,1.0,"true",[],{},&"true"]:
		var before=F.digest([sim.snapshot(),sim._initial,sim.events])
		ck(sim.configure(F.rows("hina"),{"area_ex_coverage_targeting":bad})=="invalid boolean adaptation: area_ex_coverage_targeting","reject strict non-bool: "+str(bad))
		ck(F.digest([sim.snapshot(),sim._initial,sim.events])==before,"invalid bool rejection is atomic: "+str(bad))
	for value in [false,true]:
		ck(sim.configure(F.rows("hina"),{"area_ex_coverage_targeting":value}).is_empty(),"accept bool "+str(value))
		ck(sim.options.get("area_ex_coverage_targeting")==value,"retain bool "+str(value))
	var snapshot=sim.snapshot();snapshot.adaptations.area_ex_coverage_targeting=false
	ck(sim.options.get("area_ex_coverage_targeting")==true,"snapshot cannot change live adaptation")
	ck(sim.start(),"start accepted coverage setup")
	var before=F.digest(sim.snapshot())
	ck(not sim.configure(F.rows("hina"),{"area_ex_coverage_targeting":false}).is_empty() and F.digest(sim.snapshot())==before,"running configure rejection is atomic")
	sim.reset();ck(sim.options.get("area_ex_coverage_targeting")==true,"reset retains explicit adaptation")
	ck(sim.configure(F.rows("hina")).is_empty() and sim.options.get("area_ex_coverage_targeting")==false,"omitted reconfigure restores false")

func canonical_contract(baseline:Dictionary)->void:
	for key in F.KEYS:
		var old=F.make_sim(key,{"initial_basic_delay_cap_seconds":5.0,"overtime_enabled":true},true)
		var old_cast=F.first_cast(old)
		ck(old_cast.get("target_id")==7 and F.hit_ids(old)==[7],key+" natural legacy first EX keeps isolated nearest")
		ck(F.digest(F.state(old))==baseline.natural[key].digest,key+" natural default matches frozen full-state baseline")
		var explicit=F.make_sim(key,{"area_ex_coverage_targeting":false,"initial_basic_delay_cap_seconds":5.0,"overtime_enabled":true},true)
		F.first_cast(explicit)
		ck(F.digest(F.state(explicit))==baseline.natural[key].digest,key+" explicit false matches frozen natural baseline")
		for mirror in [false,true]:
			var sim=F.make_sim(key,{"area_ex_coverage_targeting":true,"initial_basic_delay_cap_seconds":5.0,"overtime_enabled":true},true,mirror)
			var cast=F.first_cast(sim);var expected:int=9 if key=="mutsuki" else 8
			var expected_ids:Array=[8,9] if key=="hoshino" else [8,9,10]
			ck(cast.get("target_id")==expected,key+" canonical natural center mirror="+str(mirror))
			ck(F.hit_ids(sim)==expected_ids,key+" actual unique coverage mirror="+str(mirror))
			ck(sim.tick==int(baseline.natural[key].tick),key+" same first EX readiness boundary mirror="+str(mirror))
			ck(cast.get("target_cell")==sim._unit(expected).cell and cast.get("origin")==sim._unit(0).cell,key+" real center and origin recorded")
			ck(sim._area_ex_coverage(sim._unit(0),sim._unit(expected),skill(sim))==expected_ids.size(),key+" predicted and actual unique count agree")

func dispatch_contract(baseline:Dictionary)->void:
	for key in F.ALL_KEYS:
		for ability in ["basic","ex"]:
			ck(F.dispatch(key,ability).digest==baseline.dispatch[key+":"+ability],key+" "+ability+" default frozen source dispatch")
			if ability=="basic" or not key in F.KEYS:
				ck(F.dispatch(key,ability,{"area_ex_coverage_targeting":true}).digest==baseline.dispatch[key+":"+ability],key+" "+ability+" opt-in preserves excluded ability and RNG")
	for key in F.KEYS:
		for candidate in [7,8,9,10]:
			for charge in ([0,1,2] if key=="aris" else [0]):
				var d=F.dispatch(key,"ex",{"area_ex_coverage_targeting":true},candidate,charge)
				ck(d.digest==baseline.forced["%s:%d:%d"%[key,candidate,charge]],key+" forced legacy metadata/coefficient/timing parity at "+str(candidate)+" charge="+str(charge))
				var sim=d.sim
				if sim.can_attack(sim._unit(0),sim._unit(candidate),reach(sim)):
					var before=F.digest(F.state(sim))
					ck(sim._area_ex_coverage(sim._unit(0),sim._unit(candidate),skill(sim))==F.hit_ids(sim).size(),key+" every legal candidate score matches dispatched unique IDs")
					ck(F.digest(F.state(sim))==before,key+" scoring preserves populated pending hits and cast state")
	# Explicit named contracts supplement the full frozen state hashes.
	var iori=F.dispatch("iori","ex",{"area_ex_coverage_targeting":true}).sim
	ck(F.ex_hits(iori).size()==9,"Iori three full-strength shots for each of three victims")
	for h in F.ex_hits(iori):ck(is_equal_approx(h.atk_ratio,6.6629) and h.component=="rear_fan","Iori shot coefficient and component preserved")
	var aru=F.dispatch("aru","ex",{"area_ex_coverage_targeting":true}).sim
	ck(F.ex_hits(aru).size()==4 and F.hit_ids(aru)==[8,9,10],"Aru primary direct and explosion remain separate hits")
	var mutsuki=F.dispatch("mutsuki","ex",{"area_ex_coverage_targeting":true},9).sim
	var centers:Array=mutsuki._three_circle_centers(mutsuki._unit(0),mutsuki._unit(9),skill(mutsuki))
	for h in F.ex_hits(mutsuki):
		ck(h.cast_target_cell==centers[int(h.component.trim_prefix("area_"))] and is_equal_approx(h.atk_ratio,7.7849),"Mutsuki exact area center, component and full per-area coefficient")
	var haruna=F.dispatch("haruna","ex",{"area_ex_coverage_targeting":true}).sim
	var hh=F.ex_hits(haruna)
	ck(hh.size()==3 and hh.map(func(h):return h.target)==[8,9,10],"Haruna actual line projectile order")
	for i in range(hh.size()):ck(is_equal_approx(hh[i].atk_ratio,8.8719*(1.0-.1*i)),"Haruna falloff coefficient "+str(i))
	var hoshino=F.dispatch("hoshino","ex",{"area_ex_coverage_targeting":true}).sim
	for h in F.ex_hits(hoshino):ck(h.has("knockback") and h.has("stun_seconds")==bool(h.hit_index==h.hit_count-1),"Hoshino per-hit knockback and final-hit stun")

func selection_contract()->void:
	for key in F.KEYS:
		var sim=F.make_sim(key,{"area_ex_coverage_targeting":true,"random_damage":true})
		var before=F.digest([sim.snapshot(),sim.events,sim._initial,sim._characters])
		var expected:int=9 if key=="mutsuki" else 8
		for i in range(5):
			ck(selected(sim)==expected,key+" repeated pure target selection")
			for enemy in sim.units:
				if enemy.team!=sim._unit(0).team:sim._area_ex_coverage(sim._unit(0),enemy,skill(sim))
		ck(F.digest([sim.snapshot(),sim.events,sim._initial,sim._characters])==before,key+" selector/scorer consume no RNG and mutate no state")
		sim.units.reverse();ck(selected(sim)==expected,key+" reversed actor iteration preserves center")
		# The normal-policy preference must not leak into EX or movement selection.
		sim.options.normal_target_policies=["wounded","wounded"];sim._unit(7).hp=1
		ck(selected(sim)==expected and tid(sim._normal_target(sim._unit(0)))==7 and tid(sim._target(sim._unit(0)))==7,key+" EX ignores HP/normal policy while shared nearest remains unchanged")
	var sim=F.make_sim("aru",{"area_ex_coverage_targeting":true})
	var actor=sim._unit(0);actor.cell=Vector2.ZERO
	for id in [9,10]:sim._unit(id).hp=0
	var a=sim._unit(7);var b=sim._unit(8)
	a.cell=Vector2(-3,0);b.cell=Vector2(4,0)
	ck(selected(sim)==7,"equal unique scores prefer nearest")
	a.cell=Vector2(-3.0000005,0);b.cell=Vector2(3,0)
	for reverse in [false,true]:
		if reverse:sim.units.reverse()
		ck(selected(sim)==7,"within existing 1e-6 distance tolerance prefers stable actor ID")
	a.cell=Vector2(-3.00001,0)
	ck(selected(sim)==8,"distance beyond tolerance prefers nearer higher ID")
	a.cell=Vector2(-3,0);b.cell=Vector2(3,0)
	ck(selected(sim)==7,"exact distance tie prefers stable ID")
	# A three-candidate near-tie chain must also be invariant under iteration order.
	var c=sim._unit(9);c.hp=c.max_hp;c.cell=Vector2(0,3.0000015)
	a.cell=Vector2(-3.000001,0);b.cell=Vector2(3,0)
	var first=selected(sim)
	for order in [[9,8,7,1,0,10],[8,0,10,7,1,9],[0,1,7,8,9,10]]:
		var reordered:Array=[]
		for id in order:reordered.append(sim._unit(id))
		sim.units=reordered;ck(selected(sim)==first,"tolerance-chain selection is order independent")
	# Candidate reach keeps can_attack's exact +1e-5 tolerance.
	c.hp=0;a.hp=0;b.cell=Vector2(3.000005,0)
	ck(tid(sim._area_ex_target(actor,skill(sim),3.0))==8,"candidate inside inherited reach tolerance remains legal")
	b.cell=Vector2(3.00002,0)
	ck(sim._area_ex_target(actor,skill(sim),3.0)==null,"candidate beyond inherited reach tolerance excluded")
	# Candidate and secondary LOS gates are independent and use existing helpers.
	sim=F.make_sim("hina",{"area_ex_coverage_targeting":true});actor=sim._unit(0)
	sim._unit(8).hp=0;ck(selected(sim)==9,"dead candidate cannot be chosen")
	sim._unit(9).team=0;ck(selected(sim)==7,"allied candidate cannot be chosen or counted; equal one-victim centers prefer nearest")
	sim._unit(10).cell=Vector2(0,-20);ck(selected(sim)==7,"out-of-range candidate excluded")
	sim._unit(10).cell=Vector2(3.2,-2.45)
	sim.line_of_sight=func(_a,bp):return bp!=Vector2(3.2,-2.45)
	ck(selected(sim)==7,"occluded candidate and victim excluded")
	sim._unit(7).hp=0;ck(selected(sim)==-1,"no legal hostile center returns null")

func taunt_contract()->void:
	for key in F.KEYS:
		var sim=F.make_sim(key,{"area_ex_coverage_targeting":true});var actor=sim._unit(0);var taunter=sim._unit(7)
		actor.taunt_source_id=7;actor.taunt_until=10
		ck(selected(sim)==7,key+" valid active taunt wins over coverage")
		sim.tick=9;ck(selected(sim)==7,key+" taunt active one tick before expiry")
		sim.tick=10;ck(selected(sim)==(9 if key=="mutsuki" else 8),key+" exact taunt expiry restores coverage")
		sim.tick=0;sim.line_of_sight=func(_a,b):return b!=Vector2(-1,-.75)
		ck(selected(sim)==-1,key+" occluded valid taunt returns null without fallback")
		var before=F.digest(F.state(sim));ck(not sim._try_skill(actor,"ex") and F.digest(F.state(sim))==before,key+" blocked taunt spends no cooldown or state")
		sim.line_of_sight=Callable();taunter.cell=Vector2(0,-20)
		ck(selected(sim)==-1,key+" unreachable valid taunt returns null without fallback")
		taunter.cell=Vector2(-1,-.75);taunter.hp=0
		ck(selected(sim)==(9 if key=="mutsuki" else 8),key+" dead taunter permits fallback")
		taunter.hp=taunter.max_hp;taunter.team=0
		ck(selected(sim)==(9 if key=="mutsuki" else 8),key+" allied taunter permits fallback")
		taunter.team=1;actor.taunt_source_id=99999
		ck(selected(sim)==(9 if key=="mutsuki" else 8),key+" missing taunter permits fallback")

func gates_contract()->void:
	for gate in ["one_star","cooldown","busy","stun","reload","dead"]:
		var states:Array=[]
		for enabled in [false,true]:
			var sim=F.make_sim("hina",{"area_ex_coverage_targeting":enabled,"ex_initial_cooldown_fraction":0.0})
			for u in sim.units:
				u.basic_ready=99999;u.sub_ready=99999;u.attack_ready=99999
				if u.id!=0:u.busy_until=99999
			var actor=sim._unit(0)
			match gate:
				"one_star":actor.star=1
				"cooldown":actor.skill_ready=99999
				"busy":actor.busy_until=99999
				"stun":actor.stun_until=99999
				"reload":actor.reload_until=99999
				"dead":actor.hp=0
			var batch=sim.step()
			ck(batch.filter(func(e):return e.type=="skill" and e.actor_id==0).is_empty(),gate+" prevents EX dispatch enabled="+str(enabled))
			states.append(F.digest(F.state(sim)))
		ck(states[0]==states[1],gate+" opt-in preserves exact gated tick, movement, aim and pending state")

func geometry_contract()->void:
	for key in ["hina","hoshino","nonomi","aris","haruna","iori","aru","mutsuki"]:
		var sim=F.make_sim(key,{"area_ex_coverage_targeting":true});var actor=sim._unit(0)
		actor.cell=Vector2.ZERO
		var sk=skill(sim);var shape:Dictionary=sk.shapeSource[0];var primary=Vector2(0,-2)
		var points:Array=[]
		match sk.kind:
			"fan_damage","fan_damage_knockback_stun":
				var radius:float=shape.Radius/100.0;var half:float=deg_to_rad(shape.Degree*.5)
				points=[primary,Vector2.UP.rotated(half)*2,Vector2.UP.rotated(half+.0001)*2,Vector2(0,-radius),Vector2(0,-radius-.0001),Vector2(0,1)]
			"charge_scaled_line_damage","line_damage_with_target_falloff":
				var lateral:float=shape.Width/200.0;var forward:float=shape.Height/100.0
				points=[primary,Vector2(lateral,-4),Vector2(lateral+.0001,-4),Vector2(0,-forward),Vector2(0,-forward-.0001),Vector2(0,1)]
			"three_shot_target_then_rear_fan":
				var radius:float=shape.Radius/100.0;var half:float=deg_to_rad(shape.Degree*.5)
				points=[primary,primary+Vector2.UP.rotated(half)*2,primary+Vector2.UP.rotated(half+.0001)*2,primary+Vector2(0,-radius),primary+Vector2(0,-radius-.0001),Vector2(0,-1.5)]
			"direct_shot_then_explosion":
				points=[primary,Vector2(2,-2),Vector2(2.0001,-2),Vector2(0,-4),Vector2(0,-4.0001),Vector2(0,1)]
			"three_circle_damage":
				points=[primary,Vector2(-2.5,-2),Vector2(-2.5001,-2),Vector2(2.5,-2),Vector2(2.5001,-2),Vector2(0,1)]
		sim.units=[actor]
		for i in range(points.size()):sim.units.append(sim.preview_unit("yuuka",1,7+i,1,points[i]))
		var count:int=sim._area_ex_coverage(actor,sim._unit(7),sk)
		ck(count==3,key+" exact shape boundaries include edges and exclude beyond/behind")
		actor.taunt_source_id=7;actor.taunt_until=999
		ck(sim._try_skill(actor,"ex"),key+" boundary dispatch succeeds")
		ck(F.hit_ids(sim)==[7,8,10] and F.hit_ids(sim).size()==count,key+" boundary scorer matches independently dispatched unique IDs")
		if key=="mutsuki":
			ck(F.ex_hits(sim).size()==5,"Mutsuki scorer deduplicates but dispatcher keeps three overlapping primary area hits")
			ck(sim._three_circle_centers(actor,sim._unit(7),sk)==[Vector2(-1.25,-2),Vector2(0,-2),Vector2(1.25,-2)],"Mutsuki helper preserves source center arithmetic and order")
	# A line's secondary victim can exceed primary acquisition range.
	var line=F.make_sim("aris",{"area_ex_coverage_targeting":true})
	line._unit(0).cell=Vector2.ZERO;line._unit(7).cell=Vector2(0,-2);line._unit(8).cell=Vector2(0,-11)
	line._unit(9).hp=0;line._unit(10).hp=0
	ck(not line.can_attack(line._unit(0),line._unit(8),reach(line)) and selected(line)==7,"out-of-range secondary is not a selectable line center")
	ck(line._area_ex_coverage(line._unit(0),line._unit(7),skill(line))==2,"valid line coverage includes secondary beyond acquisition range")
	line._try_skill(line._unit(0),"ex")
	ck(F.hit_ids(line)==[7,8],"actual line dispatch keeps beyond-acquisition secondary")
	var circles=F.make_sim("mutsuki",{"area_ex_coverage_targeting":true,"mutsuki_ex_circle_spacing_world_units":0.0})
	ck(circles._three_circle_centers(circles._unit(0),circles._unit(7),skill(circles))==[circles._unit(7).cell,circles._unit(7).cell,circles._unit(7).cell],"zero explicit spacing preserves all three centers")
	circles._unit(7).cell=circles._unit(0).cell
	ck(circles._three_circle_centers(circles._unit(0),circles._unit(7),skill(circles))==[circles._unit(0).cell,circles._unit(0).cell,circles._unit(0).cell],"zero-length direction preserves legacy zero sideways arithmetic")
	# Circle and rear-fan victims use center-to-victim LOS rather than caster LOS.
	for key in ["aru","iori","mutsuki"]:
		var sim=F.make_sim(key,{"area_ex_coverage_targeting":true});var actor=sim._unit(0)
		var target=sim._unit(8);var blocked=sim._unit(9).cell
		sim.line_of_sight=func(a,b):return not (a!=actor.cell and b==blocked)
		var count:int=sim._area_ex_coverage(actor,target,skill(sim))
		actor.taunt_source_id=8;actor.taunt_until=999;sim._try_skill(actor,"ex")
		ck(not 9 in F.hit_ids(sim) and F.hit_ids(sim).size()==count,key+" secondary LOS matches dispatcher origin")

func _initialize()->void:
	option_contract()
	if Sim.new().has_method("_area_ex_target") and Sim.new().has_method("_area_ex_coverage"):
		var baseline:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(F.BASELINE))
		canonical_contract(baseline);dispatch_contract(baseline);selection_contract();taunt_contract();gates_contract();geometry_contract()
	else:ck(false,"EX coverage selector/scorer not implemented")
	print("AREA EX TARGETING CHECKS=",checks," FAILURES=",failures.size())
	quit(1 if not failures.is_empty() else 0)
