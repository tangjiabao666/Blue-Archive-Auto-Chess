extends SceneTree
const Sim=preload("res://core/character_sim.gd")
const Clock=preload("res://core/character_clock.gd")
var fails:=0
func ck(ok:bool,label:String):
	if not ok:fails+=1;printerr("FAIL: "+label)
func roster()->Array:
	var keys=["iori","tsubaki","nonomi","mutsuki","haruna"]
	var rows:Array=[]
	for team in range(2):
		for i in range(5):rows.append({"id":team*7+i,"team":team,"cell":Vector2(-4+i*2,2.5 if team==0 else -2.5),"character_id":keys[(i+team*2)%5],"star":2})
	return rows
func clock_fixture():
	var c=Clock.new();ck(c.sim.configure(roster(),{"seed":17,"random_damage":true,"initial_basic_delay_cap_seconds":1.0}).is_empty(),"expanded deterministic fixture")
	c.sim.start();return c
func _initialize():
	var a=clock_fixture();var b=clock_fixture();var events_a:Array=[];var events_b:Array=[]
	for i in range(400):events_a.append_array(a.advance(0.05))
	for i in range(40):events_b.append_array(b.advance(0.5))
	ck(a.sim.snapshot()==b.sim.snapshot(),"all five mechanics invariant to render frame chunking")
	ck(events_a==events_b,"all five produce identical event ordering and seeded RNG")
	var replay_events:Array=events_a.duplicate(true);a.reset();a.sim.start();events_a=[]
	for i in range(400):
		for event in a.advance(0.05):
			event.generation=0;events_a.append(event)
	ck(replay_events==events_a,"reset exactly replays all new mechanics")
	# One-star roster retains basics but cannot unlock EX.
	var s=Sim.new();var rows=roster()
	for row in rows:row.star=1
	s.configure(rows,{"random_damage":false,"initial_basic_delay_cap_seconds":0.1});s.start()
	for i in range(500):
		for e in s.step():ck(e.type!="skill","one-star does not auto-cast EX")
	# A taunt cannot become a substitute stun or force shooting beyond range.
	s=Sim.new();s.configure([{"id":0,"team":0,"cell":Vector2(0,3),"character_id":"tsubaki","star":2},{"id":1,"team":1,"cell":Vector2(0,-3),"character_id":"yuuka","star":1},{"id":2,"team":0,"cell":Vector2(2,0.5),"character_id":"yuuka","star":1}],{"random_damage":false});s.start()
	s._try_skill(s.units[0],"ex");var v=s.units[1]
	ck(s._target(v,v.range)==null,"taunt cannot ignore weapon range")
	ck(s._target(v).id==0 and v.stun_until==0,"taunt preserves movement toward source")
	var ends:int=v.taunt_until;s.tick=ends;s._expire_and_reload()
	ck(v.taunt_source_id==-1 and v.taunt_until==0,"taunt clears at exact expiry tick")
	s._try_skill(s.units[0],"ex");s.units[0].hp=1
	s._normal_attack(v,s.units[0]);s._pending[0].due=s.tick+1
	for u in s.units:u.busy_until=100000;u.basic_activations=1
	s.step()
	ck(s.units[0].hp==0 and v.taunt_source_id==-1,"taunt clears on the same tick its source dies")
	# Reload duration is the only window for damage reduction.
	s=Sim.new();s.configure([{"id":0,"team":0,"cell":Vector2(0,2),"character_id":"tsubaki","star":1},{"id":1,"team":1,"cell":Vector2(0,-2),"character_id":"yuuka","star":1}],{"random_damage":false});s.start()
	s._start_reload(s.units[0]);s.tick=s.units[0].reload_until;s._expire_and_reload();s._update_conditional_states()
	ck(s.units[0].damage_taken_multiplier==1.0 and not s.units[0].buffs.has("tsubaki_reload"),"reload end removes damage reduction and HUD buff together")
	# Mines and pending skills cannot attack after their owner died on a prior tick.
	s=Sim.new();s.configure([{"id":0,"team":0,"cell":Vector2(0,2),"character_id":"mutsuki","star":1},{"id":1,"team":1,"cell":Vector2(0,-4),"character_id":"yuuka","star":1},{"id":2,"team":0,"cell":Vector2(4,2),"character_id":"yuuka","star":1}],{"random_damage":false});s.start()
	for u in s.units:u.busy_until=100000;u.basic_ready=100000;u.skill_ready=100000
	s._try_skill(s.units[0],"basic");s.units[0].busy_until=100000
	for i in range(41):s.step()
	ck(s.snapshot().mines.size()==3,"death fixture arms mines")
	s.units[0].hp=0;var batch=s.step()
	ck(s.snapshot().mines.is_empty(),"death removes all owner mines immediately")
	for e in batch:ck(not(e.type=="damage" and e.actor_id==0),"dead source cannot deal delayed mine damage")
	ck(s.units[0].taunt_until==0 and not s.units[0].stationary and s.units[0].damage_taken_multiplier==1.0,"death clears new status fields")
	print("EXPANDED CHARACTER INVARIANTS FAILURES=",fails);quit(1 if fails else 0)
