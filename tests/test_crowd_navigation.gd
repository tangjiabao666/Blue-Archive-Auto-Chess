extends SceneTree
const Session=preload("res://core/game_session.gd")
func _initialize():
	var g=Session.new();var sim=g.clock.sim
	var roster=[{"id":0,"team":0,"character_id":"hoshino","star":1,"cell":Vector2(4,1.7)},{"id":1,"team":0,"character_id":"aris","star":1,"cell":Vector2(4,1.0)},{"id":7,"team":1,"character_id":"aris","star":1,"cell":Vector2(4,-3.0)}]
	print("CONFIG=",sim.configure(roster,{"random_damage":false}))
	sim.start()
	var moves:=0;var attacks:=0
	for tick in range(80):
		for event in sim.step():
			if event.get("actor_id",-1)!=0:continue
			if event.type=="move":moves+=1
			if event.type=="attack":attacks+=1
	print("REAR_HOSHINO_AFTER_4S moves=",moves," attacks=",attacks," range=",sim.units[0].range," cell=",sim.units[0].cell," dist=",sim.units[0].cell.distance_to(sim.units[2].cell)," front_alive=",sim.units[1].hp>0)
	var u:Dictionary=sim.units[0];var goal:Vector2=sim.units[2].cell;var dir:Vector2=u.cell.direction_to(goal)
	for angle in [1.4,1.50,1.52]:
		var point:Vector2=u.cell+dir.rotated(angle)*0.125
		print("ANGLE=",angle," point=",point," actor_clear=",point.distance_to(sim.units[1].cell)>=0.7," reduces_target_distance=",point.distance_to(goal)<u.cell.distance_to(goal)," route_static_clear=",g.navigation.is_segment_free(u.cell,point,0.35))
	quit(0 if moves>0 else 1)
