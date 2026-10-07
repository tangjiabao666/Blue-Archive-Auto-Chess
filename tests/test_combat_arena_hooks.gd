extends SceneTree
var fails:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:fails+=1;printerr(label)
func _initialize():
 ck(ResourceLoader.exists("res://core/combat_arena_hooks.gd"),"shared scene-free arena hooks exist")
 if fails:quit(1);return
 var script=load("res://core/combat_arena_hooks.gd")
 var Baseline=load("res://tests/fixtures/game_session_before_offscreen.gd")
 for seed_value in [17,42,771]:
  var original=Baseline.new()
  var simulation=load("res://core/character_sim.gd").new()
  var navigation=load("res://core/obstacle_navigation.gd").new();navigation.configure(original.HALF_SIZE,original.OBSTACLES)
  var hooks=script.new();hooks.bind(simulation,navigation,original.OBSTACLES)
  var roster:Array=[]
  for team in range(2):
   for i in range(4):roster.append({"id":team*7+i,"team":team,"character_id":["shiroko","hoshino","yuuka","aris"][(i+team)%4],"star":2,"cell":Vector2(-2.4+i*1.6,3.8 if team==0 else -3.8)})
  var settings={"seed":seed_value,"random_damage":true}
  ck(original.clock.sim.configure(roster,settings).is_empty() and simulation.configure(roster,settings).is_empty(),"identical arena scenarios configure")
  original.clock.sim.start();simulation.start()
  for tick in range(600):
   var expected:Array=original.clock.sim.step();var actual:Array=simulation.step()
   ck(expected==actual,"shared hooks preserve exact combat events seed%s tick%s"%[seed_value,tick])
   ck(original.clock.sim.units==simulation.units,"shared hooks preserve positions, cover and stats")
   if original.clock.sim.phase=="finished":break
  ck(original.clock.sim.snapshot()==simulation.snapshot(),"shared hooks preserve final RNG and source state")
 print("COMBAT ARENA HOOKS ",checks," checks FAILURES=",fails);quit(1 if fails else 0)
