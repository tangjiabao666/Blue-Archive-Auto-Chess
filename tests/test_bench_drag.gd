extends SceneTree
var failures:=0
var checks:=0
var generation:=1
var calls:Array=[]
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func deploy(id:String,point:Vector2)->Dictionary:calls.append([id,point]);return {'ok':true,'error':''}
func preview(_id:String,point:Vector2)->Dictionary:return {'ok':point.y>0,'error':'' if point.y>0 else 'invalid_point'}
func gen()->int:return generation
func _initialize()->void:
 ck(ResourceLoader.exists('res://scripts/bench_drag_controller.gd'),'drag controller exists')
 if failures:finish();return
 var drag=load('res://scripts/bench_drag_controller.gd').new();drag.configure(Callable(self,'deploy'),Callable(self,'preview'),Callable(self,'gen'))
 ck(drag.begin('u1',Vector2(10,10)) and drag.is_pending() and not drag.is_dragging(),'press creates potential drag')
 drag.update(Vector2(13,12));ck(not drag.is_dragging(),'small mouse jitter remains click')
 ck(not drag.drop(Vector2(0,4)).ok and calls.is_empty(),'click-only release never deploys')
 drag.begin('u1',Vector2.ZERO);drag.update(Vector2(10,0));ck(drag.is_dragging(),'movement threshold starts drag')
 ck(drag.preview(Vector2(0,4)).ok and calls.is_empty(),'preview never deploys')
 ck(drag.drop(Vector2(0,4)).ok and calls.size()==1 and not drag.is_pending(),'release commits exactly once')
 ck(not drag.drop(Vector2(1,4)).ok and calls.size()==1,'duplicate release harmless')
 drag.begin('u2',Vector2.ZERO);drag.update(Vector2(20,0));drag.cancel()
 ck(not drag.is_pending() and not drag.drop(Vector2(0,4)).ok and calls.size()==1,'Esc/right/focus cancellation rolls back')
 drag.begin('u2',Vector2.ZERO);drag.update(Vector2(20,0));generation+=1
 ck(not drag.drop(Vector2(0,4)).ok and calls.size()==1,'new battle/game generation invalidates pending drag')
 drag.begin('u3',Vector2.ZERO);drag.update(Vector2(20,0));ck(not drag.drop(null).ok and calls.size()==1,'outside battlefield rejects')
 drag.begin('u3',Vector2.ZERO);drag.update(Vector2(20,0));ck(not drag.drop(Vector2(0,-4)).ok and calls.size()==1,'invalid preview rejects before transaction')
 finish()
func finish()->void:print('BENCH_DRAG checks=',checks,' failures=',failures);quit(1 if failures else 0)
