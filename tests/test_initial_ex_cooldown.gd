extends SceneTree
var fails:=0
func ck(ok:bool,msg:String):
	if not ok:fails+=1;printerr(msg)
func _initialize():
	var factory=load("res://core/character_sim.gd")
	for key in ["shiroko","hoshino","hina","aru","yuuka","aris","serika"]:
		var sim=factory.new()
		var error:String=sim.configure([{"id":0,"team":0,"cell":Vector2(0,1),"character_id":key,"star":2},{"id":7,"team":1,"cell":Vector2(0,-1),"character_id":"hoshino","star":1}],{"random_damage":false})
		ck(error.is_empty(),"configure "+key)
		var unit:Dictionary=sim.units[0]
		ck(unit.skill_ready>0 and unit.skill_ready<=160,"upgraded "+key+" gets first EX opportunity within8s rather than full15–40s recast")
		var full_cd:int=unit.skill_cooldown_ticks
		sim.units[1].hp=1000000;sim.units[1].max_hp=1000000;sim.units[1].busy_until=100000
		sim.start();var first:=-1
		for i in range(300):
			for event in sim.step():
				if event.type=="skill" and event.actor_id==0:first=event.tick;ck(unit.skill_ready==first+full_cd,"subsequent EX keeps full cooldown")
			if first>=0:break
		ck(first>=0,key+" actually casts its unlocked EX before15s when a valid target exists")
	print("INITIAL EX FAILURES=",fails);quit(1 if fails else 0)
