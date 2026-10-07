extends SceneTree
const EXPECTED=[{"rect":Rect2(-2.3,-0.8,0.6,1.6),"blocks_projectiles":true},{"rect":Rect2(1.7,-0.8,0.6,1.6),"blocks_projectiles":true},{"rect":Rect2(-0.8,2.2,1.6,0.45),"blocks_projectiles":false},{"rect":Rect2(-0.8,-2.65,1.6,0.45),"blocks_projectiles":false}]
var failures:=0
var checks:=0
func ck(condition:bool,message:String)->void:
	checks+=1
	if not condition:failures+=1;printerr("FAIL: ",message)
func _initialize():call_deferred("run")
func run():
	var path="res://scripts/arena_environment.gd"
	ck(ResourceLoader.exists(path),"reusable visual component exists")
	if not ResourceLoader.exists(path):finish();return
	var arena=load(path).new();root.add_child(arena)
	# Face winding and normals are checked from the actual generated mesh.
	var probe:=Node3D.new();root.add_child(probe)
	arena._begin();arena._box(Vector3(2,2,2),Vector3.ZERO,"concrete");arena._flush(probe,"Probe")
	var probe_arrays=probe.get_child(0).mesh.surface_get_arrays(0)
	for triangle in range(0,probe_arrays[Mesh.ARRAY_VERTEX].size(),3):
		var a:Vector3=probe_arrays[Mesh.ARRAY_VERTEX][triangle]
		var b:Vector3=probe_arrays[Mesh.ARRAY_VERTEX][triangle+1]
		var c:Vector3=probe_arrays[Mesh.ARRAY_VERTEX][triangle+2]
		var n:Vector3=probe_arrays[Mesh.ARRAY_NORMAL][triangle]
		ck(n.dot((a+b+c)/3.0)>0.0,"box normal points outwards")
		ck((c-a).cross(b-a).normalized().dot(n)>0.9999,"clockwise winding matches normals")
	probe.queue_free()
	arena.configure(EXPECTED)
	ck(arena.get_meta("playable_bounds")==Rect2(-6.6,-6.6,13.2,13.2),"exact 13.2-unit playable square")
	var original=EXPECTED.duplicate(true)
	ck(arena.get_node("Cover").get_child_count()==4,"exactly four visual cover nodes")
	for index in range(EXPECTED.size()):
		var cover=arena.get_node("Cover").get_child(index)
		var r:Rect2=EXPECTED[index].rect
		var h:float=1.05 if EXPECTED[index].blocks_projectiles else 0.42
		ck(cover.get_meta("rect")==r,"cover rectangle retained "+str(index))
		ck(cover.get_meta("blocks_projectiles")==EXPECTED[index].blocks_projectiles,"projectile flag retained "+str(index))
		var bounds=mesh_bounds(cover)
		ck(bounds.position.is_equal_approx(Vector3(r.position.x,0.0,r.position.y)),"cover lower bounds exact "+str(index))
		ck(bounds.size.is_equal_approx(Vector3(r.size.x,h,r.size.y)),"cover size and height exact "+str(index))
		ck(int(cover.get_meta("primitive_count"))>=4,"cover deliberately shaped and detailed "+str(index))
	var floor=arena.get_node("Ground/PlayableSurface")
	ck(floor.get_aabb().position.is_equal_approx(Vector3(-6.6,-0.09,-6.6)),"surface lower bound exact")
	ck(floor.get_aabb().size.is_equal_approx(Vector3(13.2,0.09,13.2)),"surface top at ground zero")
	for scenery in arena.get_node("Scenery").get_children():
		var b:AABB=mesh_bounds(scenery)
		ck(b.end.x<=-6.6 or b.position.x>=6.6 or b.end.z<=-6.6 or b.position.z>=6.6,"scenery wholly outside gameplay: "+str(scenery.name))
		ck(not (b.position.x<0 and b.end.z>0 and b.size.y>0.15),"no tall southwest foreground prop")
	var stats=collect(arena)
	ck(stats.physics_nodes==0,"environment never owns collision")
	ck(stats.cameras==0 and stats.lights==0,"environment does not replace Stage camera or lighting")
	ck(stats.meshes<=30,"at most 30 render meshes")
	ck(stats.surfaces<=30,"at most 30 material surfaces / theoretical one-pass draws")
	ck(stats.triangles<=3000,"at most 3000 triangles")
	ck(stats.process_nodes==0,"no per-frame environment update")
	arena.configure(EXPECTED)
	ck(collect(arena)==stats,"repeat configure does not leak render nodes")
	ck(EXPECTED==original,"input obstacles not mutated")
	arena.configure([])
	ck(arena.get_node("Cover").get_child_count()==0,"configure clears stale cover")
	arena.configure(EXPECTED)
	ck(collect(arena)==stats,"full reconfigure deterministic")
	print("ARENA STATS=",stats)
	arena.queue_free();await process_frame
	finish()
func mesh_bounds(node:Node)->AABB:
	var result:=AABB();var first:=true
	for child in node.get_children():
		if child is MeshInstance3D:
			var b:AABB=child.transform*child.get_aabb()
			result=b if first else result.merge(b);first=false
	return result
func collect(node:Node)->Dictionary:
	var stats={"meshes":0,"surfaces":0,"triangles":0,"physics_nodes":0,"cameras":0,"lights":0,"process_nodes":0}
	if node is MeshInstance3D:
		stats.meshes=1;stats.surfaces=node.mesh.get_surface_count()
		for index in node.mesh.get_surface_count():
			var arrays=node.mesh.surface_get_arrays(index)
			stats.triangles+=arrays[Mesh.ARRAY_VERTEX].size()/3
	if node is CollisionObject3D or node is CollisionShape3D:stats.physics_nodes=1
	if node is Camera3D:stats.cameras=1
	if node is Light3D:stats.lights=1
	if node.is_processing() or node.is_physics_processing():stats.process_nodes=1
	for child in node.get_children():
		var nested=collect(child)
		for key in stats:stats[key]+=nested[key]
	return stats
func finish():
	print("ARENA ENVIRONMENT CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
