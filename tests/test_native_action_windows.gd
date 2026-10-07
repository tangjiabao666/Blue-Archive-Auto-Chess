extends SceneTree
var failed:=0
func ck(b:bool,msg:String):
	if not b:failed+=1;printerr(msg)
func _initialize():call_deferred("run")
func run():
	var profiles=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
	for key in ["serika","shiroko","yuuka"]:
		var view=load("res://scripts/unit_view.gd").new();root.add_child(view)
		var u={"id":0,"team":0,"cell":Vector2.ZERO,"range":3,"presentation":profiles[key]};view.setup(u,{},1)
		view.consume({"type":"skill","ability":"ex","actor_id":0,"generation":1,"event_id":"ex","tick":20,"recovery_ticks":120})
		var window:Dictionary=profiles[key].action_windows.ex
		ck(is_equal_approx(view._skill_speed,1.0),key+" native EX must not be stretched to gameplay duration")
		view.update_time(1.1,u)
		ck(absf(view.player.current_animation_position-(float(window.clipIn)+0.1))<0.002,key+" clipIn preserved")
		ck(is_equal_approx(view._action_ends_at,1.0+float(window.duration)),key+" source EX window preserved")
		view.queue_free();await process_frame
	print("NATIVE ACTION WINDOW FAILURES=",failed);quit(1 if failed else 0)
