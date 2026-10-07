extends SceneTree
const Arena=preload("res://core/arena_sim.gd")
func _initialize():
	var sim=Arena.new();sim.configure([{"id":0,"team":0,"cell":Vector2(0,1),"hp":1000,"damage":1,"attack_windup_ticks":3,"skill_cooldown_ticks":5,"skill":"single"},{"id":1,"team":1,"cell":Vector2(0,-1),"hp":1000,"damage":1,"attack_windup_ticks":3}]);sim.start()
	var attack=false;var skill=false
	for i in range(30):
		for e in sim.step():
			if e.type=="damage":
				attack=attack or e.get("kind","")=="attack"
				skill=skill or e.get("kind","")=="skill"
	var ok=attack and skill
	if not ok:printerr("FAIL: damage events distinguish shot impacts and skill damage")
	print("DAMAGE ORIGIN FAILURES=",0 if ok else 1);quit(0 if ok else 1)
