extends SceneTree
const Session=preload("res://core/game_session.gd")
const LEFT=["hoshino","shiroko","aru","koharu","aris","hina"]
const RIGHT=["tsubaki","iori","serika","yuuka","haruna","nonomi"]
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr(label)
func _initialize()->void:
 var results:Array=[]
 for fixture in [{"count":4,"seed":17},{"count":5,"seed":73},{"count":6,"seed":257}]:
  for policy in ["nearest","wounded"]:
   var first:Dictionary=run_case(fixture,policy)
   var second:Dictionary=run_case(fixture,policy)
   ck(first==second,"deterministic repeated legal roster %d/%s"%[fixture.count,policy])
   results.append(first)
 print("NORMAL TARGET ROSTER RESULTS ",JSON.stringify(results))
 print("NORMAL TARGET ROSTERS ",checks," checks; ",failures," failures")
 quit(1 if failures else 0)
func run_case(fixture:Dictionary,policy:String)->Dictionary:
 var game=Session.new();var sim=game.clock.sim;var roster:Array=[]
 for team in range(2):
  for i in range(fixture.count):
   var point:=Vector2((i-(fixture.count-1)*0.5)*1.6,4.7 if team==0 else -4.7)
   ck(game.navigation.is_free(point,0.35),"declared placement valid")
   roster.append({"id":team*10+i,"team":team,"cell":point,"character_id":LEFT[i] if team==0 else RIGHT[i],"star":2 if i%2==0 else 1})
 var error:String=sim.configure(roster,{"seed":fixture.seed,"initial_basic_delay_cap_seconds":5.0,"overtime_enabled":true,"normal_target_policies":[policy,"nearest"]})
 ck(error.is_empty(),"legal roster configures: "+error)
 if not error.is_empty():return {"error":error}
 ck(sim.start(),"legal battle starts")
 var all_events:Array=[];var reason:=""
 while sim.phase=="running":
  var events:Array=sim.step();all_events.append_array(events)
  for event in events:
   if event.type=="finished":reason=event.reason
 ck(reason in ["elimination","timeout"],"battle reaches explicit terminal condition")
 ck(sim.tick<=2400 and sim.winner in [-1,0,1],"bounded legal result")
 for unit in sim.units:ck(unit.cell.is_finite() and unit.hp>=0,"finite positions and health")
 return {"count":fixture.count,"seed":fixture.seed,"policy":policy,"winner":sim.winner,"ticks":sim.tick,"reason":reason,"event_count":all_events.size(),"trace_hash":var_to_bytes(all_events).hex_encode().sha256_text(),"snapshot_hash":var_to_bytes(sim.snapshot()).hex_encode().sha256_text()}
