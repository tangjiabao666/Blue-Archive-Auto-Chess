extends SceneTree
var fails:=0
func ck(ok:bool,message:String):
	if not ok:fails+=1;printerr(message)
func _initialize():
	var g=load("res://core/game_session.gd").new();var sim=g.clock.sim
	ck(g.has_method("_cover_query"),"source cover passive needs arena cover adapter")
	if fails:quit(1);return
	sim.configure([{"id":0,"team":0,"cell":Vector2(-1.3,0.5),"character_id":"yuuka","star":1},{"id":7,"team":1,"cell":Vector2(-3.5,-0.5),"character_id":"aris","star":1}])
	sim.start();var u:Dictionary=sim.units[0];var enemy:Dictionary=sim.units[1];u.hp=int(u.max_hp/2);u.busy_until=1000;enemy.busy_until=1000
	ck(g._cover_query(u),"adjacent wall shields against opposite enemy")
	var before:int=u.hp;var events:Array=sim.step();ck(u.hp>before and u.in_cover,"entering cover triggers Yuuka native sub heal")
	var healed:int=u.hp;sim.step();ck(u.hp==healed,"remaining in cover does not heal every tick")
	u.cell=Vector2(0.0,3.0);sim.step();ck(not u.in_cover,"leaving obstacle clears cover")
	u.cell=Vector2(-1.3,0.5);sim.step();ck(u.hp==healed,"re-entering during10s cooldown does not heal")
	enemy.cell=Vector2(0,0.5);ck(not g._cover_query(u),"same side enemy does not give cover")
	print("OBSTACLE COVER FAILURES=",fails);quit(1 if fails else 0)
