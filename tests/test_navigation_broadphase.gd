extends SceneTree
class CountedNav extends 'res://core/obstacle_navigation.gd':
 var narrow_calls:=0
 func _segment_rect_distance_squared(a:Vector2,b:Vector2,rect:Rect2)->float:
  narrow_calls+=1
  return super._segment_rect_distance_squared(a,b,rect)
var failures:=0
func ck(ok:bool,label:String)->void:
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize()->void:
 var nav=CountedNav.new()
 ck(nav.configure(10,[{'rect':Rect2(3,3,1,1),'blocks_projectiles':true}]).is_empty(),'configure')
 ck(nav.is_segment_free(Vector2(-5,-5),Vector2(-2,-2),0.35),'far segment free')
 ck(nav.narrow_calls==0,'far obstacle skips expensive narrow phase')
 ck(not nav.is_segment_free(Vector2(2,3.5),Vector2(5,3.5),0.35),'crossing still blocked')
 ck(not nav.is_segment_free(Vector2(2,2.8),Vector2(5,2.8),0.35),'radius clearance still blocked')
 ck(nav.is_segment_free(Vector2(2,2.65),Vector2(5,2.65),0.35),'tangent clearance stays free')
 print('NAVIGATION_BROADPHASE failures=',failures);quit(1 if failures else 0)
