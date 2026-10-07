extends SceneTree
## Preparation reuse keeps each shipped native rig at the same reset pose/time.
const Sim=preload("res://core/character_sim.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize()->void:call_deferred("run")
func pose(view:Node3D)->Array:
	var result:Array=[]
	for node in view._model.find_children("*","Node3D",true,false):
		# NativeMaterials may assign unique generated node names per instance.
		# Imported hierarchy order and class are stable across fresh instances.
		result.append({"class":node.get_class(),"transform":node.transform,"visible":node.visible,"bones":[]})
		if node is Skeleton3D:
			for index in node.get_bone_count():result[-1].bones.append(node.get_bone_pose(index))
	return result
func same_pose(before:Array,after:Array)->bool:
	if before.size()!=after.size():return false
	for path in before.size():
		if before[path]["class"]!=after[path]["class"] or before[path].visible!=after[path].visible or not before[path].transform.is_equal_approx(after[path].transform):return false
		if before[path].bones.size()!=after[path].bones.size():return false
		for index in before[path].bones.size():
			if not before[path].bones[index].is_equal_approx(after[path].bones[index]):return false
	return true
func run()->void:
	var script_path:String="res://scripts/battle_stage.gd"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--stage-script="):script_path=argument.trim_prefix("--stage-script=")
	var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	var stage=load(script_path).new();root.add_child(stage);stage.configure(profiles,[])
	var sim=Sim.new()
	for character in profiles:
		var unit:Dictionary=sim.preview_unit(character,2,0,0,Vector2(1,2))
		if unit.is_empty():
			# Cover inactive native rigs too, without pretending they have a
			# playable combat definition. These values only populate view/HUD inputs.
			unit={"id":0,"character_id":character,"team":0,"star":2,
				"cell":Vector2(1,2),"range":3.0,"attack_ticks":60,"hp":100,"max_hp":100}
		stage.set_roster([unit],50,true)
		var original:Array=pose(stage.views[0])
		var actor_id:int=stage.views[0].get_instance_id()
		var model_id:int=stage.views[0]._model.get_instance_id()
		stage.update_display([unit],[],0.35,0)
		var forward:Array=pose(stage.views[0])
		stage.set_roster([unit],50,true)
		ck(stage.views[0].get_instance_id()==actor_id and stage.views[0]._model.get_instance_id()==model_id,character+" retains exact native actor/model")
		ck(same_pose(original,pose(stage.views[0])),character+" reset preserves all native transforms, bones and visibility")
		ck(stage.views[0].player.current_animation_position==0.0,character+" reset preserves native clip origin")
		stage.update_display([unit],[],0.35,0)
		ck(same_pose(forward,pose(stage.views[0])),character+" replay preserves native pose at the same subsequent time")
		await process_frame
	stage.free();await process_frame
	print("PREPARATION_POSE_PARITY ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)
