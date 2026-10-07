extends SceneTree
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok: failures.append(label)
func _initialize() -> void:
 var path := "res://core/directional_dash.gd"
 check(FileAccess.file_exists(path), "directional dash helper exists")
 if not FileAccess.file_exists(path):
  finish(); return
 var helper = load(path)
 var empty: Array = []
 var start := Vector2.ZERO
 var goal := Vector2(2,0)
 check(helper.legal_prefix(start,goal,0,empty,6.6,0.35).is_equal_approx(goal), "clear path full length")
 var actors := [{"id":1,"hp":100,"cell":Vector2(1,0)}]
 var stop: Vector2 = helper.legal_prefix(start,goal,0,actors,6.6,0.35)
 check(stop.x >= 0.2999 and stop.x <= 0.300001, "cannot tunnel through actor")
 check(helper.legal_prefix(start,goal,1,actors,6.6,0.35).is_equal_approx(goal), "self ignored")
 actors[0].hp=0
 check(helper.legal_prefix(start,goal,0,actors,6.6,0.35).is_equal_approx(goal), "dead actor ignored")
 actors[0].hp=1; actors[0].cell=Vector2(1,0.7)
 check(helper.legal_prefix(start,goal,0,actors,6.6,0.35).is_equal_approx(goal), "tangent is legal")
 actors[0].cell=Vector2(1,0.699)
 check(helper.legal_prefix(start,goal,0,actors,6.6,0.35).x < 1.0, "near tangent blocks")
 var edge: Vector2 = helper.legal_prefix(Vector2(6,0),Vector2(9,0),0,empty,6.6,0.35)
 check(edge.x <= 6.25 and edge.x >= 6.2499, "boundary clips whole radius")
 var sweep := func(a: Vector2,b: Vector2,r: float) -> bool: return maxf(a.x,b.x)+r <= 1.0
 var free := func(p: Vector2,r: float) -> bool: return p.x+r <= 1.0
 stop=helper.legal_prefix(start,goal,0,empty,6.6,0.35,free,sweep)
 check(stop.x <= 0.650001 and stop.x >= 0.6499, "terrain clips whole radius")
 var bind := sweep.bind()
 check(helper.legal_prefix(start,goal,0,empty,6.6,0.35,free,bind).is_equal_approx(stop), "bound callable valid")
 var position_without_radius := func(p: Vector2) -> bool: return p.x <= 0.65
 check(helper.legal_prefix(start,goal,0,empty,6.6,0.35,position_without_radius.unbind(1),sweep).is_equal_approx(stop), "unbound callable valid")
 check(helper.legal_prefix(start,start,0,empty,6.6,0.35)==start, "zero length stable")
 check(helper.legal_prefix(start,Vector2(INF,0),0,empty,6.6,0.35)==start, "nonfinite goal rejected")
 check(helper.legal_prefix(start,goal,0,empty,6.6,-1.0)==start, "negative radius rejected")
 actors[0].cell=start
 check(helper.legal_prefix(start,goal,0,actors,6.6,0.35)==start, "overlap at origin rejected")
 var direction:=Vector2.RIGHT.rotated(156*TAU/256.0)
 var center:=Vector2(-5,2)
 actors[0].cell=center+Vector2(-direction.y,direction.x)*0.6999987
 stop=helper.legal_prefix(center-direction,center+direction,0,actors,6.6,0.35)
 check(not stop.is_equal_approx(center+direction),"scalar precision does not admit below-epsilon grazing")
 for angle in range(32):
  var dir := Vector2.RIGHT.rotated(angle*TAU/32.0)
  actors[0].cell=dir
  stop=helper.legal_prefix(start,dir*2,0,actors,6.6,0.35)
  check(absf(stop.length()-0.3)<0.0001, "rotationally symmetric obstacle %d"%angle)
  check(stop.distance_to(actors[0].cell)>=0.699999, "nonoverlap %d"%angle)
 finish()
func finish() -> void:
 print("DASH GEOMETRY: %d checks; failures: %s"%[checks,failures])
 quit(0 if failures.is_empty() else 1)
