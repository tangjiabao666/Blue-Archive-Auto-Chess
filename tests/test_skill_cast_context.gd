extends SceneTree
const Sim=preload("res://core/character_sim.gd")
var fails:=0
func ck(ok:bool,message:String):
	if not ok:fails+=1;printerr(message)
func _initialize():
	var sim=Sim.new()
	var actors:Array=[{"id":0,"team":0,"cell":Vector2(0,0.75),"character_id":"aru","star":2},{"id":7,"team":1,"cell":Vector2(0,-0.75),"character_id":"yuuka","star":1},{"id":8,"team":1,"cell":Vector2(1,-0.75),"character_id":"yuuka","star":1}]
	ck(sim.configure(actors,{"random_damage":false}).is_empty(),"configure cast-context fixture")
	sim.start();sim.tick=200;sim.units[1].busy_until=100000;sim.units[2].busy_until=100000
	ck(sim._try_skill(sim.units[0],"ex"),"cast native Aru EX")
	var damage_count:=0
	for hit in sim._pending:
		if hit.effect!="damage":continue
		damage_count+=1
		ck(hit.get("cast_start_tick",-1)==200,"every damage segment retains cast identity")
		ck(hit.get("cast_target_cell",Vector2.INF)==Vector2(0,-0.75),"AoE center stays the selected cast target, not each victim")
	ck(damage_count==3,"fixture contains direct contact plus two explosion victims")
	sim.units[1].cell=Vector2(0,-1.0)
	var resolved:=0
	for i in range(70):
		for event in sim.step():
			if event.type!="damage" or event.get("ability")!="ex":continue
			resolved+=1
			ck(event.get("cast_start_tick",-1)==200,"resolved damage preserves cast identity")
			ck(event.get("cast_target_cell",Vector2.INF)==Vector2(0,-0.75),"resolved AoE center is immutable")
			if event.target_id==7:ck(event.target_cell==Vector2(0,-1),"current victim point remains separate for direct impacts")
	ck(resolved==3,"context metadata does not change damage cardinality")
	print("SKILL CAST CONTEXT FAILURES=",fails);quit(1 if fails else 0)
