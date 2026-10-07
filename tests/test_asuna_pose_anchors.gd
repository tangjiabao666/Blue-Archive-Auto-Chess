extends SceneTree
## Actual UnitView must use Asuna's authored weapon socket, not the legacy fallback.
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var profile:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json")).asuna
	ck(profile.anchors.size()==6,"six structured source anchors")
	for anchor in profile.anchors:
		ck(anchor is Dictionary,"source anchor has runtime structure")
		if not anchor is Dictionary:quit(1);return
		ck(anchor.path.ends_with("/"+anchor.name),"anchor path preserves source name")
	var view=load("res://scripts/unit_view.gd").new();root.add_child(view)
	view.setup({"id":71,"character_id":"asuna","team":0,"cell":Vector2(2,3),"range":3.0,"attack_ticks":60,"presentation":profile},{},4)
	ck(view.player!=null,"consumer animation player is available")
	if view.player==null:view.free();quit(1);return
	var skeleton:Skeleton3D=view._anchor_skeleton
	ck(skeleton!=null,"source skeleton found")
	var bone:int=skeleton.find_bone("Bip001_Weapon")
	ck(bone>=0 and view._muzzle_bone==bone,"socket attached to authored weapon bone")
	# Independent literals decoded from the locked GLB fire_01 node, not the profile under test.
	var socket:=Transform3D(Basis(Quaternion(2.384186075232139e-7,-1.5631941541971115e-13,-6.556510356857185e-7,0.9999999999997566)),Vector3(1.0455463694825085e-7,0.011999511159956455,0.3842805027961731))
	ck(view._muzzle_socket.is_equal_approx(socket),"exact source socket, not generic fallback")
	var first:=Vector3.ZERO
	for row in [["idle",0.3],["attack_fire",0.2],["reload",0.9],["ex",0.2583333333],["ex",1.2]]:
		var clip:String=profile.clips[row[0]]
		view.player.play(clip,0.0);view.player.seek(row[1],true);view.player.advance(0.0);view.player.pause()
		var expected:Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(bone)*socket
		var actual:Transform3D=view.muzzle_transform()
		ck(actual.origin.is_finite(),"finite muzzle for "+clip)
		ck(actual.is_equal_approx(expected),"current animated pose drives socket for "+clip)
		if row[0]=="idle":first=actual.origin
		else:ck(actual.origin.distance_to(first)>0.01,"muzzle follows changed pose for "+clip)
	ck(view.diagnostics().warnings.is_empty(),"no animation or anchor diagnostic warnings")
	view.free()
	print("ASUNA POSE ANCHORS CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
