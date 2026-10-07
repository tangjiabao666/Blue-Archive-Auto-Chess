extends SceneTree
const OBSTACLES=[{"rect":Rect2(-2.3,-0.8,0.6,1.6),"blocks_projectiles":true},{"rect":Rect2(1.7,-0.8,0.6,1.6),"blocks_projectiles":true},{"rect":Rect2(-0.8,2.2,1.6,0.45),"blocks_projectiles":false},{"rect":Rect2(-0.8,-2.65,1.6,0.45),"blocks_projectiles":false}]
var failures:=0
var checks:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var path:="res://base/arena_environment.gd" if "--base" in OS.get_cmdline_user_args() else "res://scripts/arena_environment.gd"
	var arena=load(path).new();root.add_child(arena)
	var source:=OBSTACLES.duplicate(true);arena.configure(source)
	ck(source==OBSTACLES,"configure preserves exact obstacle input")
	ck(arena.has_node("Ground/ContactShadows"),"cheap flat contact-shadow batch exists")
	if arena.has_node("Ground/ContactShadows"):
		var shadow=arena.get_node("Ground/ContactShadows")
		ck(shadow.get_aabb().size.y<0.008,"contact shadows remain flat paint")
		ck(shadow.material_override.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,"shadow batch avoids transparent overdraw")
	var paint:Color=arena.PALETTE["concrete"]
	var blue:Color=arena.PALETTE["blue"]
	ck(paint.get_luminance()-blue.get_luminance()>0.27,"cover body and inset retain strong material contrast")
	check_solid_geometry(arena)
	var nav=load("res://core/obstacle_navigation.gd").new();nav.configure(6.6,source)
	var sim=load("res://core/character_sim.gd").new()
	var hooks=load("res://core/combat_arena_hooks.gd").new();hooks.bind(sim,nav,source)
	ck(sim.configure([{"id":0,"team":0,"character_id":"shiroko","star":1,"cell":Vector2(-3.0,3.8)},{"id":1,"team":1,"character_id":"yuuka","star":1,"cell":Vector2(3.0,-3.8)}]).is_empty(),"copied gameplay fixture configures")
	for free in [Vector2(-1.234,2.789),Vector2(2.731,3.119),Vector2(-4.192,1.807)]:
		ck(sim.place(0,free),"arbitrary continuous position accepted")
		ck(sim.units[0].cell==free,"continuous coordinates remain exact, unsnapped")
	for o in OBSTACLES:
		ck(not nav.is_free(o.rect.get_center(),0.0),"same obstacle footprint blocks movement")
		var c:Vector2=o.rect.get_center()
		ck(nav.has_line_of_sight(c-Vector2(1.0,0.0),c+Vector2(1.0,0.0))==not o.blocks_projectiles,"same projectile occlusion footprint and flag")
	ck(not nav.is_free(Vector2(6.601,0.0),0.0),"exact arena exterior remains blocked")
	ck(nav.is_free(Vector2(6.599,0.0),0.0),"exact arena interior remains open")
	print("POLISH CONTRACT CHECKS=",checks," FAILURES=",failures)
	arena.queue_free();await process_frame
	quit(1 if failures else 0)
func check_solid_geometry(node:Node)->void:
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			var arrays=node.mesh.surface_get_arrays(surface)
			for vertex in arrays[Mesh.ARRAY_VERTEX]:
				var v:Vector3=node.global_transform*vertex
				if v.y<=0.008 or absf(v.x)>=6.6-0.00001 or absf(v.z)>=6.6-0.00001:continue
				var allowed:=false
				for o in OBSTACLES:
					if o.rect.grow(0.00001).has_point(Vector2(v.x,v.z)) and v.y<=(1.05 if o.blocks_projectiles else 0.42)+0.00001:allowed=true
				ck(allowed,"solid visual stays inside existing collider and cover height")
	for child in node.get_children():check_solid_geometry(child)
