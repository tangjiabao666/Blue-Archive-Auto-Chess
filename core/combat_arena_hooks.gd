extends RefCounted
## Scene-free arena callbacks shared by visible and offscreen battles.
## Every instance owns its simulation/navigation references; never shared across jobs.
const HALF_SIZE:=6.6
const OBSTACLES=[{"rect":Rect2(-2.3,-0.8,0.6,1.6),"blocks_projectiles":true},{"rect":Rect2(1.7,-0.8,0.6,1.6),"blocks_projectiles":true},{"rect":Rect2(-0.8,2.2,1.6,0.45),"blocks_projectiles":false},{"rect":Rect2(-0.8,-2.65,1.6,0.45),"blocks_projectiles":false}]
var simulation
var navigation
var obstacles:Array=[]
var _low_cover:Array[Rect2]=[]
var _cover_distance:=0.6
var _cover_multiplier:=0.8
func bind(sim,nav,source_obstacles:Array)->void:
	simulation=sim;navigation=nav;obstacles=source_obstacles.duplicate(true)
	_low_cover.clear()
	for obstacle in obstacles:
		if not obstacle.blocks_projectiles and obstacle.get("cover_kind","low")=="low":_low_cover.append(obstacle.rect)
	if simulation.has_method("bind_tactical_navigation"):simulation.bind_tactical_navigation(navigation)
	if simulation.has_method("bind_tactical_cover"):simulation.bind_tactical_cover(Callable(self,"incoming_cover"),Callable(self,"cover_status"),Callable(self,"configure_tactical_cover"),obstacles)
	simulation.position_free=Callable(navigation,"is_free")
	simulation.segment_free=Callable(navigation,"is_segment_free")
	simulation.line_of_sight=Callable(navigation,"has_line_of_sight")
	simulation.path_step=Callable(self,"route_step")
	simulation.cover_query=Callable(self,"cover_query")
func route_step(unit:Dictionary,target:Vector2,reach:float)->Vector2:
	var origin:Vector2=unit.cell
	var waypoint:Vector2=navigation.next_waypoint(origin,target,0.35)
	if waypoint==origin:return origin
	var blockers:Array=[]
	for other in simulation.units:
		# The destination actor is approached only to firing range; including
		# its center would make every route to the goal impossible.
		if other.id!=unit.id and other.hp>0 and other.cell.distance_to(target)>0.00001:
			blockers.append(other.cell)
	if not navigation.is_crowd_segment_free(origin,waypoint,0.35,blockers):
		waypoint=navigation.next_crowd_waypoint(origin,target,0.35,blockers,unit.id,simulation.tick)
		if waypoint==origin:return origin
	var travel:float=minf(0.125,origin.distance_to(waypoint))
	if waypoint.distance_to(target)<0.0001:travel=minf(travel,maxf(0.0,origin.distance_to(target)-maxf(0.0,reach-0.12)))
	var direction:=origin.direction_to(waypoint)
	var best:=origin;var remaining:=origin.distance_to(waypoint)
	for angle in [0.0,0.35,-0.35,0.7,-0.7,1.05,-1.05,1.4,-1.4,1.5,-1.5,1.52,-1.52,1.55,-1.55]:
		var point:Vector2=origin+direction.rotated(angle)*travel
		if not navigation.is_segment_free(origin,point,0.35):continue
		var free:=true
		for other in simulation.units:
			if other.id!=unit.id and other.hp>0 and point.distance_to(other.cell)<0.7-0.000001:free=false;break
		if free and point.distance_to(waypoint)<remaining-0.000001:best=point;remaining=point.distance_to(waypoint)
	return best

func incoming_cover(source:Vector2,target:Vector2,policy:String)->Dictionary:
	# Contact-specific tactical protection must not replace native in_cover:
	# a nearby wall only protects when this incoming ray crosses that wall.
	if policy in ["lob","penetrating"]:return {"blocked":false,"multiplier":1.0}
	var multiplier:=1.0
	for obstacle in obstacles:
		var rect:Rect2=obstacle.rect
		if not _cover_segment_intersects(source,target,rect):continue
		if obstacle.blocks_projectiles:return {"blocked":true,"multiplier":1.0}
		if obstacle.get("cover_kind","low")!="low":continue
		var closest:=Vector2(clampf(target.x,rect.position.x,rect.end.x),clampf(target.y,rect.position.y,rect.end.y))
		if target.distance_to(closest)<=_cover_distance+0.000001:multiplier=_cover_multiplier
	return {"blocked":false,"multiplier":multiplier}

func configure_tactical_cover(distance:float,multiplier:float)->void:
	_cover_distance=distance;_cover_multiplier=multiplier

func cover_status(unit:Dictionary,public_units:Array)->Dictionary:
	var status:Dictionary={"state":"none","threat_id":-1,"multiplier":1.0,"direction":Vector2.ZERO}
	if unit.hp<=0:return status
	var nearby:=false
	for rect in _low_cover:
		var closest:=Vector2(clampf(unit.cell.x,rect.position.x,rect.end.x),clampf(unit.cell.y,rect.position.y,rect.end.y))
		if unit.cell.distance_to(closest)<=_cover_distance+0.000001:nearby=true;break
	if not nearby:return status
	var threat:Dictionary={};var nearest:=INF
	for enemy in public_units:
		if enemy.hp<=0 or enemy.team==unit.team:continue
		var distance:float=unit.cell.distance_squared_to(enemy.cell)
		if distance<nearest or (is_equal_approx(distance,nearest) and enemy.id<threat.get("id",2147483647)):
			nearest=distance;threat=enemy
	if threat.is_empty():return status
	var cover:Dictionary=incoming_cover(threat.cell,unit.cell,"direct")
	status.threat_id=threat.id;status.direction=unit.cell.direction_to(threat.cell)
	# High-wall obstruction is not presented as low-cover protection.
	if cover.blocked:return status
	status.multiplier=cover.multiplier
	status.state="protected" if cover.multiplier<1.0 else "exposed"
	return status

func _cover_segment_intersects(source:Vector2,target:Vector2,rect:Rect2)->bool:
	if rect.has_point(source) or rect.has_point(target):return true
	var corners=[rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
	for index in range(4):
		if Geometry2D.segment_intersects_segment(source,target,corners[index],corners[(index+1)%4])!=null:return true
	return false

func cover_query(unit:Dictionary)->bool:
	# Autochess cover adaptation: within0.6world units of solid cover, with
	# that same obstacle intersecting the line to a live opposing actor.
	# Native crouch/cover clips are not represented by this geometric hook.
	for obstacle in obstacles:
		if not obstacle.blocks_projectiles:continue
		var rect:Rect2=obstacle.rect
		var closest:=Vector2(clampf(unit.cell.x,rect.position.x,rect.end.x),clampf(unit.cell.y,rect.position.y,rect.end.y))
		if unit.cell.distance_to(closest)>0.6:continue
		var corners=[rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
		for enemy in simulation.units:
			if enemy.hp<=0 or enemy.team==unit.team:continue
			for index in range(4):
				if Geometry2D.segment_intersects_segment(unit.cell,enemy.cell,corners[index],corners[(index+1)%4])!=null:return true
	return false
