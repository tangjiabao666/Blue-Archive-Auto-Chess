extends SceneTree
var fails:=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func _initialize():call_deferred("run")
func run():
	var path="res://scripts/native_impact.gd"
	ck(ResourceLoader.exists(path),"native impact renderer exists")
	if not ResourceLoader.exists(path):quit(1);return
	var effect=load(path).new();root.add_child(effect)
	effect.begin(Vector3(1,0.8,1),1.0,77,1.3)
	effect.update_time(0.99);ck(effect.visible_layers()==0,"no impact before contact")
	effect.update_time(1.01);ck(effect.visible_layers()==1,"ring first, delayed star/sparks not yet visible")
	effect.update_time(1.07);ck(effect.visible_layers()>=3,"ring star and sparks at authored delay")
	effect.update_time(1.4);ck(effect.visible_layers()==0,"all native impact particles expire")
	ck(effect.particles.size()>=3 and effect.particles.size()<=4,"disabled root omitted and spark burst bounded")
	effect.queue_free();await process_frame
	print("NATIVE IMPACT FAILURES=",fails);quit(1 if fails else 0)
