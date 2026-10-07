extends SceneTree
func _initialize():call_deferred("run")
func run():
	var g=load("res://core/game_session.gd").new();var stage=load("res://scripts/battle_stage.gd").new();root.add_child(stage);stage.configure(g.profiles,g.OBSTACLES)
	var roster=[]
	for team in range(2):
		for i in range(7):roster.append({"id":team*7+i,"team":team,"cell":Vector2(-4.8+1.6*i,3.8 if team==0 else -3.8),"character_id":g.ACTIVE[i],"star":2})
	g.clock.sim.configure(roster,{"seed":771,"random_damage":false});g.clock.sim.start();g.clock.generation=1;stage.set_roster(g.clock.sim.units,1,false)
	var simulation_us:=0;var view_us:=0;var count:=0
	for frame in range(1800):
		var before:=Time.get_ticks_usec();var events=g.clock.advance(1.0/60.0);simulation_us+=Time.get_ticks_usec()-before
		before=Time.get_ticks_usec();stage.update_display(g.clock.sim.units,events,g.clock.sim.tick*0.05+g.clock.accumulator);view_us+=Time.get_ticks_usec()-before;count+=1
		if count%300==0:print("CPU_ONLY frames=",count," sim_mean_ms=",simulation_us/float(count)/1000," presentation_mean_ms=",view_us/float(count)/1000," tick=",g.clock.sim.tick)
		if g.clock.sim.phase=="finished":break
	print("CPU_ONLY_FINAL frames=",count," sim_mean_ms=",simulation_us/float(count)/1000," presentation_mean_ms=",view_us/float(count)/1000)
	stage.queue_free();await process_frame;quit()
