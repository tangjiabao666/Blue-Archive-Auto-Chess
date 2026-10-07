extends SceneTree
const Arena=preload("res://core/arena_sim.gd")
const Weapons=preload("res://core/weapon_profiles.gd")
var fails=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func _initialize()->void:
	ck(Weapons.range_for("SG")<Weapons.range_for("HG") and Weapons.range_for("HG")<Weapons.range_for("AR") and Weapons.range_for("AR")<Weapons.range_for("SR"),"weapon ranges ordered")
	for kind in Weapons.RANGES:
		var s=Arena.new()
		var roster=[{"id":0,"team":0,"cell":Vector2(0,0.6),"weapon":kind},{"id":1,"team":1,"cell":Vector2(0,-0.6),"weapon":"HG"}]
		ck(s.configure(roster)=="","weapon config accepted")
		ck(is_equal_approx(s.units[0].range,Weapons.range_for(kind)),"weapon profile applied: "+kind)
		s.start();var moved=false;var fired=false
		for e in s.step():
			if e.actor_id==0 if e.has("actor_id") else false:
				if e.type=="move":moved=true
				if e.type=="attack":fired=true
		ck(fired and not moved,"shoots immediately within range without closing to melee")
	# Exact range boundary and out-of-range behavior for every weapon family.
	for kind in Weapons.RANGES:
		var reach=Weapons.range_for(kind)
		var boundary=Arena.new()
		ck(boundary.configure([{"id":0,"team":0,"cell":Vector2(0,reach/2),"weapon":kind},{"id":1,"team":1,"cell":Vector2(0,-reach/2),"range":0.7,"damage":0}])=="","boundary roster configures")
		boundary.start()
		var fired=false
		for e in boundary.step():
			if e.get("actor_id",-1)==0 and e.type=="attack":fired=true
		ck(fired,"fires at exact range boundary: "+kind)
		var outside=Arena.new()
		outside.configure([{"id":0,"team":0,"cell":Vector2(0,(reach+0.4)/2),"weapon":kind},{"id":1,"team":1,"cell":Vector2(0,-(reach+0.4)/2),"range":0.7,"damage":0}])
		outside.start()
		for e in outside.step():
			ck(not(e.get("actor_id",-1)==0 and e.type=="attack"),"does not shoot outside range: "+kind)
	var override=Arena.new()
	ck(override.configure([{"id":0,"team":0,"cell":Vector2(0,1),"weapon":"AR","range":4.1},{"id":1,"team":1,"cell":Vector2(0,-1)}])=="","per-character range override configures")
	ck(is_equal_approx(override.units[0].range,4.1),"per-character override preserved")
	var bad=Arena.new()
	ck(bad.configure([{"id":0,"team":0,"cell":Vector2(0,1),"weapon":"UNKNOWN"},{"id":1,"team":1,"cell":Vector2(0,-1)}])!="","unknown weapon not silently assigned")
	print("WEAPON RANGE FAILURES=",fails);quit(1 if fails else 0)
