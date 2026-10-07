extends SceneTree
const Session=preload("res://core/game_session.gd")
const Stage=preload("res://scripts/battle_stage.gd")
func _initialize():call_deferred("run")
func run():
	var g=Session.new();var sim=g.clock.sim
	print("CONFIG=",sim.configure([{"id":0,"team":0,"cell":Vector2(4,1),"character_id":"hoshino","star":2},{"id":7,"team":1,"cell":Vector2(4,-1),"character_id":"aris","star":1}],{"random_damage":false}))
	var stage=Stage.new();root.add_child(stage);stage.configure(g.profiles,g.OBSTACLES);stage.set_roster(sim.units,1,false)
	sim.start();sim.tick=20;sim._normal_attack(sim.units[1],sim.units[0])
	for event in sim.events:event.generation=1
	stage.update_display(sim.units,sim.events,1.0)
	sim.events=[];sim.tick=22;sim._knockback(sim.units[0],sim.units[1],0.5)
	for event in sim.events:event.generation=1
	stage.update_display(sim.units,sim.events,1.15)
	print("KNOCKBACK_EVENT=",sim.events)
	print("KNOCKBACK_SNAPSHOT target=",sim.units[1].cell," target_view=",stage.views[7].position," view_state=",stage.views[7].state," ends=",stage.views[7]._action_ends_at)
	stage.update_display(sim.units,[],2.0)
	print("AFTER_0.9S view_target=",stage.views[7].position," sim_target=",sim.units[1].cell)
	var correct:bool=stage.views[7].position.distance_to(Vector3(sim.units[1].cell.x,0,sim.units[1].cell.y))<0.001
	stage.queue_free();await process_frame;quit(0 if correct else 1)
