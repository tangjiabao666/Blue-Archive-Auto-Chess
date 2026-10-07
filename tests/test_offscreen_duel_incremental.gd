extends SceneTree
const Duel=preload("res://core/offscreen_duel.gd")
var fails:=0
var checks:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:fails+=1;printerr(label)
func army(character:String="shiroko")->Array:
 return [{"id":"owned_"+character,"character_id":character,"star":1}]
func configured(settings:Dictionary={}):
 var job=Duel.new()
 ck(job.configure(army(),army("yuuka"),"p1","p2",173,settings).is_empty(),"incremental job configures")
 return job
func callbacks_released(simulation)->bool:
 return not simulation.position_free.is_valid() and not simulation.segment_free.is_valid() and not simulation.line_of_sight.is_valid() and not simulation.path_step.is_valid() and not simulation.cover_query.is_valid()
func test_cancel_is_immediate()->void:
 var job=configured()
 var simulation=job._simulation
 job.cancel()
 ck(job.result=={"ok":false,"error":"cancelled"},"cancel publishes its terminal result without needing run or advance")
 ck(callbacks_released(simulation),"cancel immediately clears every simulator callback")
 ck(job._simulation==null and job._arena==null and job._navigation==null,"cancel immediately releases its simulator and arena references")
 job.run()
 ck(job.result=={"ok":false,"error":"cancelled"},"run cannot overwrite cancellation")
func test_budget_and_lazy_start()->void:
 var job=configured({"max_ticks":18})
 var simulation=job._simulation
 ck(not job.is_complete() and job.result.is_empty(),"configured duel has no result before execution")
 ck(not job._started and simulation.phase=="prepare" and simulation.tick==0,"configure queues a duel without starting it")
 for budget in [0,-1,-100]:
  ck(not job.advance(budget),"nonpositive budget does not complete a queued duel")
  ck(not job._started and simulation.phase=="prepare" and simulation.tick==0,"nonpositive budget does not start or step a queued duel")
 ck(not job.advance(),"default single-tick budget leaves a longer duel unfinished")
 ck(job._started and simulation.phase=="running" and simulation.tick==1,"default advance starts and runs exactly one whole tick")
 ck(not job.advance(7) and simulation.tick==8,"seven-step budget advances exactly seven ticks")
 var snapshot:Dictionary=simulation.snapshot()
 for budget in [0,-7]:
  ck(not job.advance(budget) and simulation.snapshot()==snapshot,"nonpositive budget preserves all running state and RNG")
 ck(job.advance(128),"large budget stops at the terminal tick")
 ck(job.is_complete() and simulation.tick==18 and job.result.outcome.duration_ticks==18,"completion is visible in the same call as the last tick")
 ck(callbacks_released(simulation),"normal completion clears every simulator callback")
 ck(job._simulation==null and job._arena==null and job._navigation==null,"normal completion releases its simulator and arena references")
 var result:Dictionary=job.result
 for budget in [0,-1,1,7,128]:
  ck(job.advance(budget) and job.result==result,"completed advance is terminal and does not reroll")
 job.run();job.cancel();job.run()
 ck(job.is_complete() and job.result==result,"run and cancellation preserve an already completed result")
 ck(not job.configure(army(),army("yuuka"),"p1","p2",173).is_empty(),"completed job cannot be reconfigured")
 job=configured({"max_ticks":1})
 ck(job.advance(9223372036854775807) and job.result.outcome.duration_ticks==1,"maximum integer budget stops at completion without allocating a budget-sized range")
func test_run_drains_partial_job()->void:
 var expected=configured({"max_ticks":45})
 expected.run()
 var job=configured({"max_ticks":45})
 ck(not job.advance(7),"duel is partially advanced before synchronous drain")
 job.run()
 ck(job.is_complete() and job.result==expected.result,"run drains the remaining ticks without restarting or rerolling")
func test_cancel_lifecycle()->void:
 var job=Duel.new()
 job.cancel()
 ck(job.is_complete() and job.result=={"ok":false,"error":"cancelled"},"unconfigured cancellation is immediately terminal")
 ck(job.advance() and job.advance(0),"cancelled unconfigured job stays terminal for every budget")
 ck(not job.configure(army(),army("yuuka"),"p1","p2",173).is_empty(),"cancelled unconfigured job cannot be configured")
 job=configured()
 var simulation_ref=weakref(job._simulation)
 var arena_ref=weakref(job._arena)
 var navigation_ref=weakref(job._navigation)
 job.cancel()
 ck(job.is_complete(),"cancel before the first tick completes immediately")
 ck(simulation_ref.get_ref()==null and arena_ref.get_ref()==null and navigation_ref.get_ref()==null,"cancel releases queued simulator, arena and navigation objects without a reference cycle")
 job=configured()
 ck(not job.advance(7),"cancellation case has a partially simulated duel")
 var simulation=job._simulation
 var tick:int=simulation.tick
 job.cancel()
 ck(job.is_complete() and job.result=={"ok":false,"error":"cancelled"},"cancel during a duel immediately publishes failure")
 ck(callbacks_released(simulation),"cancel during a duel clears callbacks immediately")
 ck(job.advance(128) and simulation.tick==tick,"cancelled duel never executes further ticks")
 job.cancel();job.run()
 ck(job.result=={"ok":false,"error":"cancelled"},"repeated cancel and run preserve the cancellation result")
func test_unconfigured_and_empty()->void:
 var job=Duel.new()
 ck(not job.is_complete() and job.result.is_empty(),"fresh job is not complete before an execution attempt")
 ck(not job.advance(0) and not job.advance(-1) and not job._started,"nonpositive budgets do not even start an unconfigured job")
 ck(job.advance() and job.is_complete() and job.result=={"ok":false,"error":"unconfigured"},"positive advance completes unconfigured job immediately")
 job.cancel();job.run()
 ck(job.result=={"ok":false,"error":"unconfigured"},"later cancellation cannot overwrite an unconfigured terminal result")
 for sides in [[[],[]],[army(),[]],[[],army("yuuka")]]:
  job=Duel.new()
  ck(job.configure(sides[0],sides[1],"p1","p2",173).is_empty(),"empty incremental duel configures")
  var simulation=job._simulation
  ck(not job.advance(0) and simulation.tick==0 and simulation.phase=="prepare","empty duel is also lazy with a zero budget")
  ck(job.advance() and job.is_complete(),"empty duel completes on the first positive advance")
  ck(job.result.ok and job.result.outcome.duration_ticks==0 and job.result.outcome.finish_reason=="empty","empty duel does not fabricate simulation ticks")
  ck(job.result.outcome.left_remaining==sides[0].size() and job.result.outcome.right_remaining==sides[1].size(),"empty incremental duel retains real survivor counts")
  ck(simulation.phase=="prepare" and callbacks_released(simulation),"empty duel never starts the sentinel simulation and releases its callbacks")
func test_interleaved_jobs_keep_independent_rng()->void:
 var options={"max_ticks":220,"random_damage":true}
 var first=Duel.new();var second=Duel.new()
 var first_expected=Duel.new();var second_expected=Duel.new()
 for job in [first,first_expected]:job.configure(army("serika"),army("iori"),"p1","p2",308,options)
 for job in [second,second_expected]:job.configure(army("iori"),army("shiroko"),"p3","p4",777,options)
 first_expected.run();second_expected.run()
 while not first.is_complete() or not second.is_complete():
  first.advance(1);second.advance(7)
 ck(first.result==first_expected.result and second.result==second_expected.result,"interleaving unequal partitions preserves independent per-duel RNG and outcomes")
func test_detached_input_and_results()->void:
 var options={"max_ticks":220,"normal_target_policies":["wounded","nearest"],"random_damage":true}
 var left=army();var right=army("yuuka")
 var expected=Duel.new();expected.configure(left,right,"p1","p2",173,options);expected.run()
 var job=Duel.new();job.configure(left,right,"p1","p2",173,options)
 left[0].character_id="serika";left[0].star=2;right.clear()
 options.max_ticks=1;options.normal_target_policies[0]="nearest"
 var complete:bool=job.advance(7)
 while not complete:complete=job.advance(7)
 ck(job.result==expected.result,"nested caller roster and settings mutations cannot change partitioned simulation")
 var copied:Dictionary=job.result;copied.outcome.winner="changed";copied.outcome.left_remaining=100
 ck(job.result==expected.result,"nested returned result mutation cannot change terminal state")
func _initialize()->void:
 test_cancel_is_immediate()
 var probe=Duel.new()
 ck(probe.has_method("advance"),"duel exposes advance(max_steps=1)")
 ck(probe.has_method("is_complete"),"duel exposes is_complete()")
 if probe.has_method("advance") and probe.has_method("is_complete"):
  test_budget_and_lazy_start()
  test_run_drains_partial_job()
  test_cancel_lifecycle()
  test_unconfigured_and_empty()
  test_detached_input_and_results()
  test_interleaved_jobs_keep_independent_rng()
 print("OFFSCREEN DUEL INCREMENTAL ",checks," checks FAILURES=",fails)
 quit(1 if fails else 0)
