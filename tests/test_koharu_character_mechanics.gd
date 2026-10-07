extends SceneTree
const Sim=preload("res://core/character_sim.gd")
const Clock=preload("res://core/character_clock.gd")
var fails:=0
func ck(ok:bool,label:String):
	if not ok:fails+=1;printerr("FAIL: "+label)
func fixture():
	var s=Sim.new();ck(s.configure([{"id":0,"team":0,"cell":Vector2(0,2),"character_id":"koharu","star":2},{"id":1,"team":0,"cell":Vector2(1.5,2),"character_id":"hoshino","star":1},{"id":7,"team":1,"cell":Vector2(0,-2),"character_id":"yuuka","star":1},{"id":8,"team":1,"cell":Vector2(1.5,-2),"character_id":"yuuka","star":1}],{"random_damage":false}).is_empty(),"Koharu fixture configure")
	s.start()
	for u in s.units:
		u.attack_ready=100000;u.aim_ready=100000;u.aimed=true;u.skill_ready=100000
		if u.id!=0:u.busy_until=100000;u.basic_ready=100000;u.basic_activations=1
		if u.team==1:u.max_hp=1000000;u.hp=1000000
	return s
func _initialize():
	var s=Sim.new();ck(s.character_keys().has("koharu"),"Koharu verified source record registered")
	if not s.character_keys().has("koharu"):print("KOHARU MECHANICS FAILURES=",fails);quit(1);return
	s=fixture();var k=s.units[0];var ally=s.units[1]
	ally.max_hp=40000;ally.hp=40000
	ck(k.basic_ready==0,"ally-threshold basic starts eligible, not million-second cooldown")
	ck(k.sub_ready==600,"periodic HealPower sub starts after 30 seconds")
	ck(s.stat(k,"HealPower")==5035 and s.stat(k,"AttackPower")==2109,"source baseline HealPower and merged enhanced ATK")
	ck(floor(s.stat(k,"HealPower")*1.5363)==7735 and floor(s.stat(k,"HealPower")*1.9275)==9704,"source JS unbuffed heal reference values")
	k.hp=1;s.step();ck(k.basic_activations==0,"Koharu basic never targets herself")
	k.hp=k.max_hp;ally.hp=int(ally.max_hp*0.5);s.step();ck(k.basic_activations==0,"basic threshold is strictly below half HP")
	ally.hp=int(ally.max_hp*0.49);var batch=s.step()
	ck(batch.any(func(e):return e.type=="basic" and e.target_id==1),"basic selects injured other ally")
	ck(k.basic_activations==1 and k.basic_ready==s.tick+400,"basic consumes source 20-second internal cooldown")
	var next:int=mini(k.basic_ready,s.tick+400);var heal_count:=0
	for i in range(45):
		for e in s.step():
			if e.type=="heal" and e.actor_id==0:
				heal_count+=1;ck(e.target_id==1 and e.raw_amount==floor(s.stat(k,"HealPower")*1.5363),"basic exact healing coefficient and recipient")
	ck(heal_count==1,"basic heals once per activation")
	ally.hp=1
	while s.tick<next-1:s.step()
	ck(k.basic_activations==1,"ally threshold does not bypass 20-second cooldown")
	s.step();ck(k.basic_activations==2,"Koharu ally heal is repeatable after cooldown")
	# EX handles friendly and hostile units in the same selected ground circle.
	s=fixture();k=s.units[0];ally=s.units[1];ally.cell=Vector2(0,-0.7);ally.hp=int(ally.max_hp*0.2)
	ck(s._try_skill(k,"ex"),"combined heal and damage EX casts")
	var cast=s.events.filter(func(e):return e.type=="skill")
	ck(cast.size()==1,"combined EX emits one cast")
	var pending:Array=s._pending;var heals=pending.filter(func(h):return h.effect=="heal");var hits=pending.filter(func(h):return h.effect=="damage")
	ck(not heals.is_empty() and not hits.is_empty(),"EX ground target covers endangered ally and enemies together")
	for h in heals:
		ck(s._unit(h.target).team==0 and is_equal_approx(h.ratio,1.9275),"EX exact ally heal, no enemy healing")
	for h in hits:
		ck(s._unit(h.target).team==1 and is_equal_approx(h.atk_ratio,4.3176),"EX exact enemy damage, no friendly fire")
	if not heals.is_empty() and not hits.is_empty():ck(heals[0].due==hits[0].due,"EX healing and damage share grenade contact time")
	for h in pending:s._resolve_hit(h)
	var heal_events=s.events.filter(func(e):return e.type=="heal")
	for e in heal_events:ck(e.get("cast_target_cell",Vector2.INF)==cast[0].target_cell,"EX heal preserves actual ground-circle context")
	# EX can also heal Koharu herself; only the basic excludes self.
	s=fixture();k=s.units[0];k.hp=1;s._try_skill(k,"ex")
	ck(s._pending.any(func(h):return h.effect=="heal" and h.target==0),"EX allows self healing")
	# Separate periodic sub is a real HealPower buff, not permanent and not attack.
	s=fixture();k=s.units[0];k.busy_until=100000;var base:float=s.stat(k,"HealPower")
	for i in range(599):s.step()
	ck(not k.buffs.has("koharu_sub"),"sub cannot start before 30-second boundary")
	s.step();ck(k.buffs.has("koharu_sub"),"periodic healing buff starts at 30 seconds")
	ck(s.stat(k,"HealPower")==round(base*1.41) and k.sub_ready==1200,"sub +41 percent Healing and next 30-second trigger")
	ck(s.stat(k,"HealPower")==7099 and floor(s.stat(k,"HealPower")*1.5363)==10906 and floor(s.stat(k,"HealPower")*1.9275)==13683,"source JS rounds buffed stat before truncating heals")
	for i in range(400):s.step()
	ck(not k.buffs.has("koharu_sub") and s.stat(k,"HealPower")==base,"sub expires after 20 seconds")
	# Snapshot/replay invariants cover simultaneous support and offense.
	var a=Clock.new();var b=Clock.new();a.sim=fixture();b.sim=fixture()
	a.sim.units[1].hp=1;b.sim.units[1].hp=1
	var ea:Array=[];var eb:Array=[]
	for i in range(800):ea.append_array(a.advance(0.05))
	for i in range(80):eb.append_array(b.advance(0.5))
	ck(a.sim.snapshot()==b.sim.snapshot() and ea==eb,"Koharu support timers preserve frame-chunk determinism")
	print("KOHARU MECHANICS FAILURES=",fails);quit(1 if fails else 0)
