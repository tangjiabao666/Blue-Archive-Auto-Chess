extends SceneTree
var fails:=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func _initialize():call_deferred("run")
func run():
	var path="res://scripts/native_muzzle.gd"
	ck(ResourceLoader.exists(path),"native muzzle renderer exists")
	if not ResourceLoader.exists(path):quit(1);return
	var fx=load(path).new();root.add_child(fx)
	fx.begin(Transform3D(Basis.IDENTITY,Vector3(1,1,1)),2.0,42,1.3)
	fx.update_time(1.99);ck(not fx.visible,"no muzzle before impact")
	fx.update_time(2.0);ck(fx.visible,"muzzle visible on contact")
	ck(fx.lifetime<0.101 and fx.lifetime>0.099,"original 0.1 second lifetime")
	ck(fx.material_override.shader!=null,"native alpha-blend shader bound")
	ck(fx.global_position.distance_to(Vector3(1,1,1.065))<0.0001,"native forward socket offset respected")
	fx.update_time(2.05);ck(fx.visible,"muzzle survives within native lifetime")
	fx.update_time(2.11);ck(not fx.visible,"muzzle expires without wall-clock timer")
	fx.queue_free();await process_frame
	print("NATIVE MUZZLE FAILURES=",fails);quit(1 if fails else 0)
