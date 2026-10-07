extends SceneTree
const Sim=preload("res://core/character_sim.gd")
var fails:=0
func ck(ok:bool,label:String):
	if not ok:fails+=1;printerr("FAIL: "+label)
func fixture(key:String):
	var s=Sim.new()
	s.configure([{"id":0,"team":0,"cell":Vector2(0,2),"character_id":key,"star":1},{"id":1,"team":1,"cell":Vector2(0,-4),"character_id":"yuuka","star":1}],{"random_damage":false})
	s.start();s.tick=10
	for u in s.units:u.basic_ready=100000;u.skill_ready=100000;u.attack_ready=100000;u.aim_ready=100000;u.aimed=true;u.busy_until=100000
	return s
func _initialize():
	var s=fixture("haruna");var h=s.units[0]
	s.path_step=func(u,g,r):return u.cell+Vector2(0,-0.1)
	h.busy_until=0;s.units[1].cell=Vector2(0,-6);h.range=0.1;s.step()
	ck(not h.get("stationary",true),"actual move removes stationary state")
	ck(not h.buffs.has("haruna_stationary"),"actual move removes stationary buff")
	ck(s.stat(h,"AttackPower")==h.base_stats.AttackPower,"moving Haruna has no stationary attack bonus")
	h.busy_until=100000;s.step()
	ck(h.get("stationary",false) and h.buffs.has("haruna_stationary"),"one unmoved simulation tick restores stationary condition")
	# Tsubaki threshold heals once and never creates Hoshino regeneration ticks.
	s=fixture("tsubaki");var tank=s.units[0];tank.hp=int(tank.max_hp*0.29)
	var healing:Array=[]
	for i in range(65):
		for e in s.step():
			if e.type=="heal" and e.actor_id==0:healing.append(e)
	ck(healing.size()==1,"Tsubaki threshold triggers exactly one heal")
	ck(tank.busy_until==100000,"health trigger does not shorten an in-flight action")
	if healing.size()==1:ck(healing[0].raw_amount==floor(s.stat(tank,"HealPower")*6.6363),"Tsubaki exact one-shot heal coefficient")
	tank.hp=1
	for i in range(100):
		for e in s.step():ck(not(e.type=="heal" and e.actor_id==0),"Tsubaki emergency heal cannot repeat")
	# Persistent mines arm at cast completion, expire, reset, and disappear on owner death.
	s=fixture("mutsuki");s._try_skill(s.units[0],"basic")
	var damages:=0
	for i in range(41):
		for e in s.step():
			if e.type=="damage":damages+=1
	ck(s.snapshot().get("mines",[]).size()==3,"Mutsuki spawns three persistent mines")
	ck(damages==0,"untriggered mines do not damage distant enemy")
	var snap=s.snapshot();s.phase="paused";ck(s.step().is_empty() and s.snapshot()==snap.merged({"phase":"paused"},true),"pause freezes mines and every combat timer")
	s.phase="running"
	var mines:Array=s.snapshot().get("mines",[])
	if mines.size()==3:
		s.units[1].cell=mines[1].cell;s.units[1].max_hp=1000000;s.units[1].hp=1000000
		var hits:Array=[]
		for i in range(3):
			for e in s.step():
				if e.type=="damage":hits.append(e)
		ck(hits.size()==1,"one triggered mine damages target once")
		if hits.size()==1:
			ck(absf(hits[0].atk_ratio-6.3566)<0.00001,"mine preserves full native coefficient")
			ck(hits[0].origin==mines[1].cell,"mine impact originates at its placed ground position")
			ck(hits[0].cast_target_cell==mines[1].cell,"mine visual contact center remains the actual placed mine")
		ck(s.snapshot().get("mines",[]).size()==2,"triggered mine consumed, untriggered mines persist")
		s.units[1].cell=Vector2(0,-4)
		for i in range(301):s.step()
		ck(s.snapshot().get("mines",[]).is_empty(),"mines expire after source 15 seconds")
	s.reset();ck(s.snapshot().get("mines",[]).is_empty() and s.tick==0,"reset removes mine state")
	# New conditional echoes are never activated by inferred size/cover.
	for key in ["iori","nonomi"]:
		s=fixture(key);s._normal_attack(s.units[0],s.units[1]);var hit=s._pending[0]
		s._pending=[];s.events=[];s._resolve_hit(hit)
		var echoes=s.events.filter(func(e):return e.type=="damage" and e.component=="echo")
		ck(echoes.size()==(1 if key=="iori" else 0),"conditional echo default "+key)
		s.events=[];s.units[0].in_cover=true;s.units[1].size_class="large";s._resolve_hit(hit)
		echoes=s.events.filter(func(e):return e.type=="damage" and e.component=="echo")
		ck(echoes.size()==(0 if key=="iori" else 1),"conditional echo explicit source condition "+key)
	print("EXPANDED CHARACTER LIFECYCLE FAILURES=",fails);quit(1 if fails else 0)
