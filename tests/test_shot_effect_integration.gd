extends SceneTree
var fails:=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func _initialize():call_deferred("run")
func run():
	var scene=load("res://battle.tscn").instantiate();root.add_child(scene);scene.set_process(false)
	ck(scene.get("shot_effects")!=null,"battle exposes active presentation effects")
	if scene.get("shot_effects")==null:scene.queue_free();await process_frame;quit(1);return
	ck(scene.shot_effects.is_empty(),"no muzzle in preparation")
	scene.start_battle()
	var saw=false
	for i in range(100):
		var batch=scene.advance_battle(0.05)
		var shot=false
		for e in batch:
			if e.type=="damage" and e.get("kind","")=="attack":shot=true
		if shot:
			ck(not scene.shot_effects.is_empty(),"real shot contact spawns original muzzle")
			saw=true;break
	ck(saw,"battle produced shot")
	var count=scene.shot_effects.size()
	scene.toggle_pause();scene.advance_battle(0.2)
	ck(scene.shot_effects.size()==count,"pause freezes native effect lifetime")
	scene.toggle_pause();scene.advance_battle(0.4)
	ck(scene.shot_effects.is_empty(),"native muzzle and impact expire after lifetime")
	scene.restart_battle();ck(scene.shot_effects.is_empty(),"restart clears old generation effects")
	scene.queue_free();await process_frame
	print("SHOT EFFECT INTEGRATION FAILURES=",fails);quit(1 if fails else 0)
