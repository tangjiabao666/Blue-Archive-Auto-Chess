extends SceneTree
var fails:=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func _initialize():call_deferred("run")
func run():
	var v=load("res://scripts/unit_view.gd").new();root.add_child(v)
	var u={"id":0,"team":0,"cell":Vector2(0,1),"range":2.4,"attack_ticks":54,"aimed":true,"presentation":{"native_burst_cycle":true}}
	v.setup(u,JSON.parse_string(FileAccess.get_file_as_string("res://data/verified-durations.json")),1)
	v.consume({"type":"aim","generation":1,"event_id":"aim1","actor_id":0,"tick":0,"duration_ticks":13,"target_cell":Vector2(0,-1)})
	v.update_time(0.2,u);ck(v.current_clip=="CH0331_Normal_Attack_Start","one native raise on target acquisition")
	v.update_time(0.9,u);ck(v.current_clip=="CH0331_Normal_Attack_Delay","hold native ready pose after aim")
	for tick in [20,74]:
		v.consume({"type":"attack","generation":1,"event_id":str(tick),"actor_id":0,"tick":tick,"impact_tick":tick+1,"burst_ticks":14,"recovery_ticks":54,"target_cell":Vector2(0,-1)})
		v.update_time(tick*0.05+0.01,u)
		ck(v.current_clip=="CH0331_Normal_Attack_Ing","ongoing bursts never squeeze repeated raise into50ms")
	v.queue_free();await process_frame
	print("NATIVE BURST CYCLE FAILURES=",fails);quit(1 if fails else 0)
