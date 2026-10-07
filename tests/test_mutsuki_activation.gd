extends SceneTree
## Source-proven Mutsuki ActivationTrack + lifecycle; no combat state edits.
const View=preload("res://scripts/unit_view.gd")
const BAG="Mutsuki_Original_Bomb_Weapon"
var failures:=0
var profiles:Dictionary
func check(ok:bool,label:String):
	if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize():call_deferred("run")
func unit(key:String="mutsuki",id:int=0)->Dictionary:
	return {"id":id,"team":0,"cell":Vector2.ZERO,"range":3,"presentation":profiles[key]}
func event(view,kind:String,id:String,tick:int):
	view.consume({"type":kind,"actor_id":view.actor_id,"generation":view.generation,"event_id":id,"tick":tick,"recovery_ticks":106,"duration_ticks":40})
func bag(view):return view._model.find_child(BAG,true,false)
func sample(view,u:Dictionary,time:float,visible:bool,label:String):
	view.update_time(time,u);check(bag(view).visible==visible,label)
	check(view._model.find_child("Mutsuki_Original_Body",true,false).visible,label+" body unaffected")
	check(view._model.find_child("Mutsuki_Original_Weapon",true,false).visible,label+" gun unaffected")
func run():
	profiles=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	check(profiles.mutsuki.get("activation_windows",{}).get("ex",[]).size()==1,"one source EX activation record")
	check(profiles.mutsuki.get("activation_windows",{}).get("basic",[]).is_empty(),"no invented basic activation")
	var u=unit();var v=View.new();root.add_child(v);v.setup(u,{},1)
	var other=View.new();root.add_child(other);var other_u=unit("mutsuki",1);other.setup(other_u,{},1)
	check(bag(v).visible and bag(other).visible,"native baseline active")
	event(v,"skill","first",20)
	sample(v,u,3.26,true,"before 68/30 release")
	sample(v,u,3.28,false,"after 68/30 release")
	check(bag(other).visible,"independent actor untouched")
	for i in range(3):sample(v,u,3.28,false,"paused/repeated sample")
	sample(v,u,3.26,true,"seek backward while source action active")
	sample(v,u,1.0+68.0/30.0,false,"exact release boundary inactive")
	event(v,"skill","first",20);check(not bag(v).visible,"duplicate event ignored")
	sample(v,u,6.5,false,"LeaveAsIs normal completion")
	event(v,"basic","basic_after",140);sample(v,u,7.1,false,"basic does not reset bag")
	event(v,"reload","reload_after",200);sample(v,u,10.1,false,"reload does not reset bag")
	event(v,"skill","second",260);sample(v,u,13.1,true,"next EX reactivates")
	event(v,"basic","interrupt_before",280);sample(v,u,15.5,true,"early interruption leaves current active state")
	sample(v,u,30.0,true,"interrupted old track cannot fire later")
	event(v,"skill","third",620)
	# Consume-only interruption evaluates source time even without an intervening frame.
	event(v,"basic","interrupt_after",680);sample(v,u,34.1,false,"late interruption retains inactive state")
	v.setup(u,{},2);check(bag(v).visible,"new generation restores native baseline")
	event(v,"skill","death_before",20);event(v,"death","dead_before",40)
	sample(v,u,10.0,true,"death before release preserves LeaveAsIs active")
	v.setup(u,{},3);event(v,"skill","death_after",20);event(v,"death","dead_after",80)
	sample(v,u,10.0,false,"death after release preserves LeaveAsIs inactive")
	v.setup(u,{},4);event(v,"skill","jump",20)
	sample(v,u,50.0,false,"jump over interval and completion samples inactive")
	for i in range(4):
		v.setup(u,{},5+i);check(bag(v).visible,"rapid setup baseline")
		v.consume({"type":"death","actor_id":0,"generation":4,"event_id":"old","tick":2000})
		check(bag(v).visible and not v.is_dead,"stale generation cannot hide new model")
		event(v,"skill","rapid",20);sample(v,u,3.28,false,"rapid setup rebinds new mesh")
	var h=unit("hoshino");v.setup(h,{},10)
	check(v._model.find_child(BAG,true,false)==null,"new roster has no stale Mutsuki node")
	var shield=v._model.find_child("Hoshino_Original_Shield_Weapon",true,false)
	event(v,"skill","shield",20);check(shield.visible,"existing Revert activation preserved")
	event(v,"death","shield_death",40);check(not shield.visible,"existing Revert interruption preserved")
	v.setup(u,{},11);check(bag(v).visible,"roster switch back restores baseline")
	# AnimationPlayableAsset speed/clipIn do not change Timeline seconds.
	var rate_u=unit();rate_u.presentation=rate_u.presentation.duplicate(true)
	rate_u.presentation.action_windows.ex.speed=2.0;rate_u.presentation.action_windows.ex.clipIn=0.5
	v.setup(rate_u,{},12);event(v,"skill","clip_rate",20)
	sample(v,rate_u,2.5,true,"per-clip speed is not Timeline speed")
	sample(v,rate_u,3.28,false,"Timeline activation end is not shifted by clipIn")
	v.queue_free();other.queue_free();await process_frame
	print("MUTSUKI ACTIVATION FAILURES=",failures);quit(1 if failures else 0)
