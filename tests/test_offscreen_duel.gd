extends SceneTree
var fails:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:fails+=1;printerr(label)
func army(character:String,star:int=1)->Array:
 return [{"id":"owned_"+character,"character_id":character,"star":star}]
func reference(left:Array,right:Array,seed_value:int,settings:Dictionary)->Dictionary:
 var sim=load("res://core/character_sim.gd").new()
 var nav=load("res://core/obstacle_navigation.gd").new()
 var baseline=load("res://tests/fixtures/game_session_before_offscreen.gd").new()
 nav.configure(baseline.HALF_SIZE,baseline.OBSTACLES)
 var hooks=load("res://core/combat_arena_hooks.gd").new();hooks.bind(sim,nav,baseline.OBSTACLES)
 var defs:Dictionary={}
 for unit in left+right:defs[unit.character_id]=sim.character_data(unit.character_id)
 var policy=load("res://core/opponent_formations.gd").new();var roster:Array=[]
 for team in range(2):
  var input:Array=left if team==0 else right
  var cells:Array=policy.positions(input,defs,policy.style_for("p1" if team==0 else "p2"),nav)
  for i in range(input.size()):roster.append({"id":team*7+i,"team":team,"character_id":input[i].character_id,"star":input[i].star,"cell":-cells[i] if team==0 else cells[i]})
 var options:Dictionary=settings.duplicate(true);options.seed=seed_value;options.arena_half=baseline.HALF_SIZE
 ck(sim.configure(roster,options).is_empty(),"reference configures")
 sim.start();var reason:=""
 while sim.phase=="running":
  for e in sim.step():
   if e.type=="finished":reason=e.reason
 var alive=[0,0]
 for unit in sim.units:
  if unit.hp>0:alive[unit.team]+=1
 sim.position_free=Callable();sim.segment_free=Callable();sim.line_of_sight=Callable();sim.path_step=Callable();sim.cover_query=Callable()
 return {"left_id":"p1","right_id":"p2","winner":"left" if alive[0]>0 and alive[1]==0 else "right" if alive[1]>0 and alive[0]==0 else "draw","left_remaining":alive[0],"right_remaining":alive[1],"duration_ticks":sim.tick,"finish_reason":reason}
func partitioned(script,left:Array,right:Array,seed_value:int,settings:Dictionary,partitions:Array,expected:Dictionary)->void:
 var job=script.new()
 ck(job.configure(left,right,"p1","p2",seed_value,settings).is_empty(),"partitioned duel configures")
 if not job.has_method("advance") or not job.has_method("is_complete"):
  ck(false,"partitioned simulation requires advance and is_complete")
  job.cancel();job.run();return
 var calls:=0
 while not job.is_complete():
  var tick_before:int=job._simulation.tick
  var budget:int=partitions[calls%partitions.size()]
  var done:bool=job.advance(budget)
  var tick_after:int=job.result.outcome.duration_ticks if done else job._simulation.tick
  ck(tick_after-tick_before<=budget,"partition never exceeds its tick budget")
  ck(done==job.is_complete(),"advance and completion query agree")
  if not done:ck(job.result.is_empty(),"partial simulation exposes no outcome")
  calls+=1
  if calls>72000:ck(false,"partitioned duel must terminate");job.cancel();break
 ck(job.result.ok and job.result.outcome==expected,"partitioned duel exactly matches independent source simulation: "+str(partitions))
 var before:Dictionary=job.result
 job.advance(128);job.run()
 ck(job.result==before,"completed partitioned duel cannot reroll")
func _initialize():
 ck(ResourceLoader.exists("res://core/offscreen_duel.gd"),"scene-free offscreen duel exists")
 if fails:quit(1);return
 var script=load("res://core/offscreen_duel.gd")
 var options={"random_damage":false,"initial_basic_delay_cap_seconds":5.0,"overtime_enabled":true}
 for pair in [["serika","iori",false],["aris","yuuka",false],["koharu","hoshino",false],["serika","iori",true]]:
  options.random_damage=pair[2]
  var left=army(pair[0],2);var right=army(pair[1],2);var expected=reference(left,right,771,options)
  var job=script.new();ck(job.configure(left,right,"p1","p2",771,options).is_empty(),"duel configures")
  var before_left=left.duplicate(true);var before_options=options.duplicate(true)
  job.run();ck(job.result.ok and job.result.outcome==expected,"duel matches independent real source simulation: "+pair[0])
  ck(left==before_left and options==before_options,"caller armies and settings untouched")
  var result=job.result;result.outcome.winner="tampered"
  ck(job.result.outcome==expected,"returned outcome is an owned copy")
  job.run();ck(job.result.outcome==expected,"duplicate run does not reroll battle")
  for partitions in [[1],[7],[128],[1,7,128,3]]:partitioned(script,left,right,771,options,partitions,expected)
 var mixed_left:Array=army("shiroko",2)+army("serika");var mixed_right:Array=army("yuuka",2)+army("iori")
 var mixed_options={"random_damage":true,"normal_target_policies":["wounded","nearest"],"max_ticks":220}
 var mixed_expected=reference(mixed_left,mixed_right,3099,mixed_options)
 for partitions in [[1],[7],[128],[1,7,128,3]]:partitioned(script,mixed_left,mixed_right,3099,mixed_options,partitions,mixed_expected)
 var job=script.new();var left=army("serika");var right=army("iori")
 var expected=reference(left,right,17,options);job.configure(left,right,"p1","p2",17,options)
 left[0].character_id="yuuka";options.random_damage=true;job.run()
 ck(job.result.outcome==expected,"later caller mutation cannot alter isolated job")
 for sides in [[[],[]],[army("iori"),[]],[[],army("yuuka")]]:
  job=script.new();ck(job.configure(sides[0],sides[1],"p1","p2",17).is_empty(),"empty army configures explicitly")
  job.run();var outcome=job.result.outcome
  ck(job.result.ok and outcome.duration_ticks==0 and outcome.finish_reason=="empty","empty duel ends without fabricated fight")
  ck(outcome.left_remaining==sides[0].size() and outcome.right_remaining==sides[1].size(),"empty duel preserves actual full survivors")
  ck(outcome.winner==("left" if not sides[0].is_empty() else "right" if not sides[1].is_empty() else "draw"),"empty winner is consistent")
 job=script.new();job.configure(army("shiroko"),army("yuuka"),"p1","p2",17);job.cancel();job.run()
 ck(not job.result.ok and job.result.error=="cancelled","cancelled job cannot yield a normal outcome")
 job=script.new();job.run();ck(not job.result.ok and job.result.error=="unconfigured","unconfigured job fails closed")
 for invalid in [[{"character_id":"does_not_exist","star":1}],[{"character_id":"shiroko","star":3}],[{"character_id":"shiroko","star":1.5}],[{"character_id":"shiroko","star":true}]]:
  job=script.new();ck(not job.configure(invalid,army("yuuka"),"p1","p2",17).is_empty(),"invalid source army rejected")
 var too_many:Array=[]
 for i in range(7):too_many.append(army("shiroko")[0])
 job=script.new();ck(not job.configure(too_many,army("yuuka"),"p1","p2",17).is_empty(),"offscreen armies honor six-unit cap")
 job=script.new();ck(not job.configure(army("shiroko"),army("yuuka"),"p1","p1",17).is_empty(),"duplicate participant rejected")
 job=script.new();ck(not job.configure(army("shiroko"),army("yuuka"),"p0","p2",17).is_empty(),"human cannot be an offscreen rival")
 job=script.new();ck(not job.configure(army("shiroko"),army("yuuka"),"p1","p2",17,{"unknown_setting":1}).is_empty(),"invalid simulation option fails closed")
 ck(script.derive_seed(17,3,"p1","p2")==script.derive_seed(17,3,"p1","p2"),"pair seed deterministic")
 ck(script.derive_seed(17,3,"p1","p2")!=script.derive_seed(17,3,"p2","p1"),"ordered pair seed independent")
 print("OFFSCREEN DUEL ",checks," checks FAILURES=",fails);quit(1 if fails else 0)
