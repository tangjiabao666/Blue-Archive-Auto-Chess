extends SceneTree
var fails:=0
func ck(ok:bool,message:String):
	if not ok:fails+=1;printerr(message)
func _initialize():
	ck(ResourceLoader.exists("res://core/opponent_formations.gd"),"public opponent formation policy exists")
	if fails:quit(1);return
	var policy=load("res://core/opponent_formations.gd").new()
	var game=load("res://core/game_session.gd").new()
	var army:Array=[];var definitions:Dictionary={}
	for key in ["hoshino","yuuka","shiroko","aru","hina","aris"]:
		army.append({"character_id":key});definitions[key]=game.clock.sim.character_data(key)
	for count in [4,5,6]:
		for style in ["guarded","spread","split"]:
			var points:Array=policy.positions(army.slice(0,count),definitions,style,game.navigation)
			ck(points.size()==count,"one position per enemy")
			ck(points==policy.positions(army.slice(0,count),definitions,style,game.navigation),"formation is deterministic")
			for i in range(count):
				ck(points[i].y<0 and game.navigation.is_free(points[i],0.35),"legal enemy-side position")
				for j in range(i):ck(points[i].distance_to(points[j])>=0.7,"no overlapping enemies")
	var guarded=policy.positions(army,definitions,"guarded",game.navigation)
	ck(guarded[0].y>guarded[2].y and guarded[1].y>guarded[3].y,"tanks form the frontline")
	ck(guarded!=policy.positions(army,definitions,"spread",game.navigation),"public styles create distinct threats")
	game.new_game(17)
	var preview=game.opponent_preview()
	ck(preview.has("formation_name"),"scouting exposes enemy doctrine")
	if preview.has("formation_name"):
		ck(not str(preview.formation_name).is_empty(),"doctrine has readable name")
	print("OPPONENT FORMATION FAILURES=",fails);quit(1 if fails else 0)
