extends SceneTree
const Session=preload("res://core/game_session.gd")
func _initialize():
	var g=Session.new();var sim=g.clock.sim
	var roster=[{"id":0,"team":0,"character_id":"hina","star":1,"cell":Vector2(-3.2,3.4)},{"id":7,"team":1,"character_id":"hoshino","star":1,"cell":Vector2(-1.2,-1.0)},{"id":8,"team":1,"character_id":"aris","star":1,"cell":Vector2(-3.2,-3.4)}]
	print("CONFIG=",sim.configure(roster,{"random_damage":false}))
	sim.start();sim.units[1].busy_until=10000;sim.units[2].busy_until=10000
	var before:Vector2=sim.units[0].cell
	print("VISIBLE_IN_RANGE=",sim.can_attack(sim.units[0],sim.units[2])," NEAREST_BLOCKED=",not g.navigation.has_line_of_sight(sim.units[0].cell,sim.units[1].cell))
	var moves:=0;var resets:=0;var attacks:=0
	for tick in range(10):
		for event in sim.step():
			if event.get("actor_id",-1)!=0:continue
			if event.type=="move":moves+=1
			if event.type=="aim_lost":resets+=1
			if event.type=="attack":attacks+=1
	print("AFTER_10_TICKS moves=",moves," aim_resets=",resets," attacks=",attacks," delta=",sim.units[0].cell.distance_to(before))
	quit(1 if moves>0 or resets>0 else 0)
