extends SceneTree
const Sim=preload("res://core/character_sim.gd")
var failures:=0
func ck(ok:bool,message:String):
	if not ok:failures+=1;printerr(message)
func _initialize():
	var cases:Array=[
		["shiroko","ex","",10,52,70,7.6088],
		["hoshino","ex","",5,35,106,6.9754],
		["aris","ex","",1,49,49,5.9113],
		["hina","ex","",10,22,91,12.0834],
		["yuuka","basic","",9,23,38,5.7382],
		["serika","basic","",11,12,33,4.2562],
		["aru","ex","direct",1,13,13,5.2125],
		["aru","basic","direct",1,46,46,2.9014],
		["shiroko","basic","",1,20,20,3.68],
		["aru","ex","explosion",1,61,61,5.5487]]
	for fixture in cases:
		var character:String=fixture[0];var ability:String=fixture[1];var component:String=fixture[2]
		var label:String=character+":"+ability+":"+component
		var sim=Sim.new()
		ck(sim.configure([{"id":0,"team":0,"cell":Vector2(0,0.75),"character_id":character,"star":2},{"id":7,"team":1,"cell":Vector2(0,-0.75),"character_id":"yuuka","star":1}],{"random_damage":false}).is_empty(),"configure "+label)
		sim.start();sim.tick=200
		ck(sim._try_skill(sim.units[0],ability),"cast "+label)
		var offsets:Array=[];var ratio:=0.0
		for hit in sim._pending:
			if hit.get("effect")=="damage" and hit.get("ability")==ability and hit.get("component","")==component:
				offsets.append(int(hit.due)-200);ratio+=float(hit.atk_ratio)
		ck(offsets.size()==fixture[3],"source damage count preserved: "+label)
		if offsets.is_empty():continue
		ck(offsets.front()==fixture[4] and offsets.back()==fixture[5],"contact must follow native visual schedule: "+label+" got "+str(offsets))
		ck(is_equal_approx(ratio,float(fixture[6])),"source aggregate damage unchanged: "+label)
		if character=="hoshino":ck(offsets==[35,54,64,76,106],"Hoshino contacts follow all five muzzle cues")
		if character=="shiroko" and ability=="ex":ck(offsets==[52,54,56,58,60,62,64,66,68,70],"drone ten paired flashes use native .1s burst interval")
		if character=="shiroko" and ability=="basic":
			ck(sim._pending[0].get("timing_adaptation","")=="not_before_hand_prop_end_adaptation","grenade hand bound is labeled adaptation, not verified impact")
	print("NATIVE SKILL CONTACT FAILURES=",failures);quit(1 if failures else 0)
