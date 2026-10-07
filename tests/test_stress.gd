extends SceneTree
const Sim=preload("res://core/battle_sim.gd")
var failed=0
func ck(b:bool,s:String)->void:
	if not b: failed+=1;printerr("FAIL: "+s)
func _initialize()->void:
	var rng=RandomNumberGenerator.new();rng.seed=87341
	for case_id in range(80):
		var roster=[];var used={}
		for id in range(6):
			var team=0 if id<3 else 1
			var cell=Vector2i(rng.randi_range(0,5),rng.randi_range(3,5) if team==0 else rng.randi_range(0,2))
			while used.has(cell):cell=Vector2i(rng.randi_range(0,5),rng.randi_range(3,5) if team==0 else rng.randi_range(0,2))
			used[cell]=true
			roster.append({"id":id,"team":team,"cell":cell,"skill":["single","area","shield"][id%3],"hp":rng.randi_range(40,200),"range":rng.randi_range(1,4),"attack_windup_ticks":rng.randi_range(0,8)})
		var s=Sim.new();ck(s.configure(roster)=="","stress valid roster");s.start()
		var trace=[]
		while s.phase=="running":
			trace.append(s.step())
			var occupied={}
			for u in s.units:
				ck(u.hp>=0 and u.hp<=u.max_hp and u.energy>=0 and u.energy<=100 and u.shield>=0,"bounded resources")
				if u.hp>0:ck(not occupied.has(u.cell),"no overlap");occupied[u.cell]=true
		ck(s.tick<=1200 and s.winner in [-1,0,1],"bounded finish")
		s.reset();s.start()
		for expected in trace:ck(s.step()==expected,"restarted replay matches")
	print("STRESS CASES=80 FAILURES=",failed);quit(1 if failed else 0)
