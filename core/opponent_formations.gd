extends RefCounted
## Public, deterministic formation doctrine. Never reacts to the player's later moves.
const NAMES={"guarded":"前排掩护","spread":"分散火力","split":"双路推进","line":"横向阵列"}
func style_for(opponent_id:String)->String:
	if not opponent_id.begins_with("p") or not opponent_id.substr(1).is_valid_int():return "line"
	return ["guarded","spread","split"][posmod(opponent_id.substr(1).to_int()-1,3)]
func positions(army:Array,definitions:Dictionary,style:String,navigation)->Array:
	var count:int=army.size();var points:Array=[];points.resize(count)
	var order:Array=[]
	for i in range(count):order.append(i)
	if style in ["guarded","split"]:
		order.sort_custom(func(a,b):
			var a_tank:bool=definitions.get(army[a].character_id,{}).get("role","")=="tank"
			var b_tank:bool=definitions.get(army[b].character_id,{}).get("role","")=="tank"
			return a_tank if a_tank!=b_tank else a<b)
	var tank_count:=0
	for unit in army:
		if definitions.get(unit.character_id,{}).get("role","")=="tank":tank_count+=1
	tank_count=mini(tank_count,2)
	var accepted:Array=[]
	for slot in range(count):
		var point:=Vector2((slot-(count-1)*0.5)*1.6,-4.7)
		match style:
			"spread":
				point=Vector2(0 if count==1 else -4.6+9.2*slot/float(count-1),-3.6 if mini(slot,count-1-slot)%2==0 else -4.8)
			"split":point=Vector2((-1 if slot%2==0 else 1)*3.8,-1.7-float(slot/2)*1.5)
			"guarded":
				if slot<tank_count:point=Vector2((slot-(tank_count-1)*0.5)*1.9,-1.45)
				else:point=Vector2((slot-tank_count-(count-tank_count-1)*0.5)*1.8,-4.7)
		if not _free(point,accepted,navigation):
			for fallback in range(7):
				var alternative:=Vector2(-4.8+fallback*1.6,-5.3)
				if _free(alternative,accepted,navigation):point=alternative;break
		points[order[slot]]=point;accepted.append(point)
	return points
func _free(point:Vector2,accepted:Array,navigation)->bool:
	if point.y>=0 or not navigation.is_free(point,0.35):return false
	for other in accepted:
		if point.distance_to(other)<0.7:return false
	return true
