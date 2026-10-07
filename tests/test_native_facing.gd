extends SceneTree
var fails:=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func _initialize():call_deferred("run")
func run():
	var scene=load("res://battle.tscn").instantiate();root.add_child(scene);scene.set_process(false)
	var view=scene.views[0]
	var skeleton=view._model.find_children("*","Skeleton3D",true,false)[0]
	var weapon=skeleton.find_bone("Bip001_Weapon")
	ck(view.has_method("muzzle_transform"),"native muzzle anchor available to effects")
	ck(weapon>=0,"original weapon bone exists")
	view.player.play("CH0331_Normal_Attack_Delay");view.player.advance(0.2)
	# Native fire_01 socket is authored along the weapon's +Z barrel axis.
	for direction in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT]:
		view._face_point(view.position+direction*3.0)
		var barrel=(skeleton.global_transform*skeleton.get_bone_global_pose(weapon)).basis.z.normalized()
		var muzzle=view.muzzle_transform()
		ck(muzzle.basis.z.normalized().dot(direction)>0.98,"native muzzle socket follows target direction")
		ck(muzzle.origin.y>0.1 and muzzle.origin.distance_to(view.global_position)<2.0,"muzzle position stays on character weapon")
		ck(barrel.dot(direction)>0.98,"native barrel points at target: "+str(direction)+" actual="+str(barrel))
	scene.queue_free();await process_frame
	print("NATIVE FACING FAILURES=",fails);quit(1 if fails else 0)
