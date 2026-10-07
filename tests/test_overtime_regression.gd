extends SceneTree
const Session=preload("res://core/game_session.gd")
var fails:=0
func ck(ok:bool,label:String):
	if not ok:fails+=1;printerr("FAIL: "+label)
func _initialize():
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/overtime/seed17-round13.json"))
	for enabled in [false,true]:
		var game=Session.new();game.new_game(17)
		var rows:Array=[]
		for raw in fixture.roster:
			rows.append({"id":int(raw.id),"team":int(raw.team),"cell":Vector2(raw.cell[0],raw.cell[1]),"character_id":raw.character_id,"star":int(raw.star)})
		var sim=game.clock.sim
		ck(sim.configure(rows,{"seed":int(fixture.seed),"initial_basic_delay_cap_seconds":5.0,"overtime_enabled":enabled}).is_empty(),"captured seed17 round13 configures")
		sim.start();var starts:=0;var attacks:=0;var heals:=0;var reason:=""
		while sim.phase=="running":
			for event in sim.step():
				if event.type=="overtime_started":starts+=1
				if event.type=="damage" and event.tick>=1500:attacks+=1
				if event.type=="heal" and event.tick>=1500:heals+=1
				if event.type=="finished":reason=event.reason
		ck(attacks>0 and heals>0,"captured long fight remains active damage and sustain, not navigation stall")
		if enabled:
			ck(reason=="elimination" and sim.tick==2103 and sim.winner==1,"sustain-only overtime resolves original timeout by actual elimination at 105.15s")
			ck(starts==1,"regression battle emits one overtime start")
		else:
			ck(reason=="timeout" and sim.tick==2400 and sim.winner==-1,"disabled rule preserves reproduced native timeout at 120s")
			ck(starts==0,"native battle emits no overtime event")
		print("OVERTIME REGRESSION enabled=",enabled," reason=",reason," seconds=",sim.tick*0.05," late_damage=",attacks," late_heal=",heals)
	print("OVERTIME REGRESSION FAILURES=",fails);quit(1 if fails else 0)
