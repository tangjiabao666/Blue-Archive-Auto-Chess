extends SceneTree
const Navigation=preload('res://core/obstacle_navigation.gd')
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize()->void:
 var path:='res://core/tactical_orders.gd';ck(FileAccess.file_exists(path),'tactical orders exists')
 if failures:finish();return
 var o=load(path).new();var nav=Navigation.new();nav.configure(6.6,[])
 var actor:Dictionary={'id':10,'team':0,'cell':Vector2(-1,2),'hp':100,'stun_until':0}
 var other:Dictionary={'id':20,'team':1,'cell':Vector2(0,-2),'hp':100,'stun_until':0}
 var context:Dictionary={'navigation':nav,'units':[actor,other],'tick':1}
 ck(o.request(actor,Vector2(1,2),context).ok,'accept reachable order')
 var before:Dictionary=o.snapshot()
 ck(not o.request(actor,Vector2(1,2),context).ok and o.snapshot()==before,'duplicate destination does not replace or spend')
 for point in [Vector2(9,2),Vector2(NAN,2),Vector2(-1,2),other.cell]:
  ck(not o.request(actor,point,context).ok and o.snapshot()==before,'invalid request preserves existing order')
 var moved:=0
 for i in range(16):
  context.tick=i+1
  var r:Dictionary=o.step(actor,context)
  if r.moved:
   ck(r.from.distance_to(r.to)<=0.125001,'speed bounded')
   actor.cell=r.to;moved+=1
 ck(moved==16 and actor.cell.distance_to(Vector2(1,2))<0.000001 and not o.has_order(10),'arrives and finishes exactly')
 nav.configure(6.6,[{'rect':Rect2(-0.2,1.5,0.4,1.0),'blocks_projectiles':true}])
 actor.cell=Vector2(-2,2)
 ck(not o.request(actor,Vector2(2,2),context).ok,'route longer than4 rejected despite Euclidean4')
 actor.cell=Vector2(-1,2)
 var routed:Dictionary=o.request(actor,Vector2(1,2),context)
 ck(routed.ok and routed.path.size()>2 and routed.distance<=4,'short route goes around cover')
 o.cancel(10,'test');ck(not o.has_order(10),'explicit cancel')
 nav.configure(6.6,[]);actor.cell=Vector2(-1,2)
 ck(o.request(actor,Vector2(1,2),context).ok,'new clear route')
 other.cell=Vector2(-0.3,2)
 var stopped:Dictionary=o.step(actor,context)
 ck(not stopped.moved and stopped.reason=='blocked' and not o.has_order(10),'new blocker stops safely')
 finish()
func finish()->void:
 print('TACTICAL_ORDERS checks=',checks,' failures=',failures);quit(1 if failures else 0)
