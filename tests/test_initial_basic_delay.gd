extends SceneTree
const Sim=preload("res://core/character_sim.gd")
const Session=preload("res://core/game_session.gd")
var fails:=0
func ck(ok:bool,message:String):
	if not ok:fails+=1;printerr(message)
func roster(character:String,star:int=2)->Array:
	return [{"id":0,"team":0,"cell":Vector2(0,0.75),"character_id":character,"star":star},{"id":7,"team":1,"cell":Vector2(0,-0.75),"character_id":"hoshino","star":1}]
func _initialize():
	for character in ["shiroko","aru","yuuka","aris","serika"]:
		var sim=Sim.new();sim.configure(roster(character))
		var interval:int=int(round(float(sim.character_data(character).basic.trigger.intervalSeconds)/0.05))
		ck(sim.units[0].basic_ready==interval,"core default preserves original first basic interval")
		var error:String=sim.configure(roster(character),{"initial_basic_delay_cap_seconds":5.0})
		ck(error.is_empty(),"autochess can opt into bounded initial basic wait")
		if not error.is_empty():continue
		ck(sim.units[0].basic_ready==100,"first periodic basic ready after5seconds: "+character)
		sim.start();sim.tick=100
		ck(sim._try_skill(sim.units[0],"basic"),"basic casts: "+character)
		ck(sim.units[0].basic_ready==100+interval,"recurring native basic interval unchanged: "+character)
	var aris=Sim.new()
	var error:String=aris.configure(roster("aris"),{"initial_basic_delay_cap_seconds":5.0,"random_damage":false})
	if error.is_empty():
		aris.units[1].hp=1000000;aris.units[1].max_hp=1000000;aris.units[1].busy_until=100000
		aris.start();var found:=false
		for i in range(250):
			for event in aris.step():
				if event.type=="skill" and event.actor_id==0:
					ck(event.get("charges",0)==1,"Aris first EX can show native charge interaction");found=true
			if found:break
		ck(found,"Aris auto EX still fires after the basic cast lock")
	for invalid in [-1.0,NAN,INF,"bad"]:
		var sim=Sim.new();ck(not sim.configure(roster("aris"),{"initial_basic_delay_cap_seconds":invalid}).is_empty(),"invalid initial wait rejected")
	var session=Session.new();session.new_game(17)
	var buy:Dictionary=session.command({"type":"buy_offer","slot":0})
	session.command({"type":"deploy_unit","unit_id":buy.unit_id});session.command({"type":"start_battle"})
	ck(session.clock.sim.options.get("initial_basic_delay_cap_seconds",0)==5.0,"live autochess opts in explicitly")
	print("INITIAL BASIC FAILURES=",fails);quit(1 if fails else 0)
