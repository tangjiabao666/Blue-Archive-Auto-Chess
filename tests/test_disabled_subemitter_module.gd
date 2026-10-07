extends SceneTree
var failures:=0
func ck(ok:bool,message:String):
	if not ok:failures+=1;printerr(message)
func _initialize():call_deferred("run")
func anchor(_binding:Dictionary,_event:Dictionary,_at:float)->Transform3D:return Transform3D.IDENTITY
func run():
	var player=load("res://vfx/native_effect_player.gd").new();root.add_child(player)
	var path="res://data/effects/nonomi/visual-templates.json#FX_Nonomi_Original_Ex01_Hit_Start"
	var handle:int=player.spawn(path,1,0.0,anchor,1.0);player.update_time(0.2)
	ck(handle>0,"Nonomi native hit prefab resolves")
	ck(player.diagnostics().scheduled_particles>0,"disabled SubModule must not suppress referenced ordinary Core emitter")
	ck(player.snapshot().particles.size()>0,"original Nonomi Core particles become visible")
	player.queue_free();await process_frame
	print("DISABLED SUBEMITTER FAILURES=",failures);quit(1 if failures else 0)
