extends SceneTree
const Sim=preload("res://core/character_sim.gd")
var fails:=0
func ck(ok:bool,label:String):
	if not ok:fails+=1;printerr("FAIL: "+label)
func support_fixture():
	var s=Sim.new();s.configure([{"id":0,"team":0,"cell":Vector2(0,2),"character_id":"koharu","star":2},{"id":1,"team":0,"cell":Vector2(1,1),"character_id":"yuuka","star":1},{"id":7,"team":1,"cell":Vector2(0,-1),"character_id":"yuuka","star":1}],{"random_damage":false});s.start();s.units[1].hp=1;return s
func _initialize():
	var s=support_fixture();s._try_skill(s.units[0],"ex")
	var contacts:Array=s._pending.duplicate(true);s.events=[]
	for hit in contacts:s._resolve_hit(hit)
	var heals=s.events.filter(func(e):return e.type=="heal")
	var damage=s.events.filter(func(e):return e.type=="damage")
	ck(not heals.is_empty() and not damage.is_empty(),"fixture resolves heal and damage from same grenade")
	for e in heals:
		ck(e.get("component","missing")=="circle","EX heal preserves circle component")
		ck(e.get("hit_index",-1)==0 and e.get("hit_count",-1)==1,"EX heal has explicit contact ordinal")
		if not damage.is_empty():
			var d=damage[0]
			ck(e.cast_start_tick==d.cast_start_tick and e.cast_target_cell==d.cast_target_cell and e.get("component") == d.component and e.get("hit_index")==d.hit_index,"EX heal and damage share one presentation identity")
	s=support_fixture();s._try_skill(s.units[0],"basic");s.events=[]
	for hit in s._pending:s._resolve_hit(hit)
	heals=s.events.filter(func(e):return e.type=="heal")
	ck(heals.size()==1,"basic fixture emits one heal")
	if heals.size()==1:ck(heals[0].get("component","missing")=="" and heals[0].get("hit_index",-1)==0,"basic heal keeps empty component and first contact index")
	# All three mines intentionally overlap. Cast/position/ordinal alone cannot distinguish them.
	s=Sim.new();s.configure([{"id":0,"team":0,"cell":Vector2(0,2),"character_id":"mutsuki","star":1},{"id":7,"team":1,"cell":Vector2(0,-4),"character_id":"yuuka","star":1}],{"random_damage":false,"mutsuki_mine_lateral_spacing_world_units":0.0});s.start()
	for u in s.units:u.busy_until=100000;u.basic_ready=100000;u.skill_ready=100000
	s._try_skill(s.units[0],"basic");s.units[0].busy_until=100000
	for i in range(41):s.step()
	var mines:Array=s.snapshot().mines
	ck(mines.size()==3,"three overlapping independent mines armed")
	if mines.size()==3:
		s.units[1].cell=mines[0].cell;s.units[1].hp=1000000;s.units[1].max_hp=1000000
		var observed:Array=[]
		for i in range(3):
			for e in s.step():
				if e.type=="damage":observed.append(e)
		ck(observed.size()==3,"three mines retain three damage applications")
		var ids:Array=[]
		for e in observed:
			ids.append(e.get("mine_id",-1))
			ck(e.component=="mine" and e.hit_index==0 and is_equal_approx(e.atk_ratio,6.3566),"mine metadata never changes component, hit count, or coefficient")
		ids.sort();ck(ids==[0,1,2],"overlapping mine damage carries distinct actual entity IDs")
	print("EXPANDED CONTACT METADATA FAILURES=",fails);quit(1 if fails else 0)
