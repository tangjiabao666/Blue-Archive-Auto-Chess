extends SceneTree
var fails:=0
func ck(b:bool,s:String):
	if not b:fails+=1;printerr(s)
func _initialize():call_deferred("run")
func run():
	var p=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"));var view=load("res://scripts/unit_view.gd").new();root.add_child(view)
	var u={"id":0,"team":0,"cell":Vector2.ZERO,"range":3,"presentation":p.hoshino};view.setup(u,{},1)
	var shield=view._model.find_child("Hoshino_Original_Shield_Weapon",true,false)
	ck(shield!=null,"source shield exists")
	if shield==null:quit(1);return
	ck(not shield.visible,"source shield hidden initially")
	view.consume({"type":"skill","actor_id":0,"event_id":"ex","generation":1,"tick":20,"recovery_ticks":153})
	view.update_time(1.01,u);ck(shield.visible,"canonical EX activation shows actual shield")
	view.update_time(8.7,u);ck(not shield.visible,"Revert hides shield after native7.633s window")
	view.consume({"type":"skill","actor_id":0,"event_id":"ex2","generation":1,"tick":200,"recovery_ticks":153})
	view.update_time(10.1,u);ck(shield.visible,"second EX reactivates")
	view.consume({"type":"death","actor_id":0,"event_id":"death","generation":1,"tick":203})
	ck(not shield.visible,"death cancellation reverts visibility")
	view.queue_free();await process_frame;print("ACTIVATION FAILURES=",fails);quit(1 if fails else 0)
