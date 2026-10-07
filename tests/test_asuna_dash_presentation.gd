extends SceneTree
const Sim=preload("res://core/character_sim.gd")
const View=preload("res://scripts/unit_view.gd")
var checks:=0
var fails:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:fails+=1;printerr("FAIL: "+label)
func _initialize():call_deferred("run")
func run():
 var s=Sim.new()
 ck(s.configure([{"id":0,"team":0,"cell":Vector2(0,3),"character_id":"asuna","star":2},{"id":1,"team":1,"cell":Vector2(0,-3),"character_id":"yuuka","star":1}],{"random_damage":false}).is_empty(),"fixture configures")
 s.start()
 for u in s.units:
  u.attack_ready=100000;u.aim_ready=100000;u.aimed=true;u.basic_ready=100000;u.skill_ready=100000
  if u.id==1:u.busy_until=100000
 var v=View.new();root.add_child(v)
 var shown:Dictionary=s.units[0].duplicate(true)
 shown.presentation=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json")).asuna
 v.setup(shown,{},1)
 ck(v._warnings.is_empty(),"native model and twelve clips load cleanly")
 s._try_skill(s.units[0],"ex")
 for event in s.events:
  event.generation=1;v.consume(event)
 var revision:int=v._clip_revision
 for i in range(8):
  for event in s.step():event.generation=1;v.consume(event)
 ck(v.is_moving,"dash event begins interpolated movement")
 ck(v._action_kind=="skill" and v.current_clip==v.SKILL and v._clip_revision==revision,"dash preserves native EX phase and does not restart clip")
 var a:Vector3=v.cell_position(Vector2(0,3));var b:Vector3=v.cell_position(s.units[0].cell)
 v.advance_event_time(0.425)
 ck(v.position.distance_to(a.lerp(b,0.5))<0.00001,"half-frame interpolation follows authoritative dash segment")
 var death:={"type":"death","actor_id":0,"tick":8,"event_id":"death-test","generation":1}
 v.consume(death)
 ck(v.position.distance_to(b)<0.00001,"same-tick death settles current authoritative dash endpoint")
 ck(v.is_dead and not v.is_moving and v.current_clip==v.DEATH,"native death interrupts dash without walk state")
 var frozen:Vector3=v.position;v.advance_event_time(0.9)
 ck(v.position==frozen,"dead actor never resumes sliding")
 ck(v._warnings.is_empty(),"no native clip warnings after EX/death")
 v.free()
 print("ASUNA DASH PRESENTATION CHECKS=",checks," FAILURES=",fails);quit(1 if fails else 0)
