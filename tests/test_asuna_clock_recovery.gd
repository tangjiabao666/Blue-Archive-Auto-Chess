extends SceneTree
## Independent recovery tests: all events/state come from the real combat core.
const Sim=preload("res://core/character_sim.gd")
const Clock=preload("res://core/character_clock.gd")
const Offscreen=preload("res://core/offscreen_duel.gd")
const Navigation=preload("res://core/obstacle_navigation.gd")
const ArenaHooks=preload("res://core/combat_arena_hooks.gd")
const EX_ID="asuna_ex_attack_speed"
const SUB_ID="asuna_sub_attack_speed"
const EVADE_ID="asuna_ex_dash_evasion"
var checks:=0
var failures:Array=[]
var records:Array=[]
var metrics:Dictionary={}
var group:="all"
func ck(ok:bool,label:String)->void:
 checks+=1;records.append({"ok":ok,"label":label})
 if not ok:failures.append(label);printerr("FAIL: ",label)
func _initialize()->void:
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--group="):group=argument.trim_prefix("--group=")
 if group not in ["all","clock","expiry","simultaneous","reset","lifecycle","offscreen"]:
  printerr("Unknown group: ",group);quit(2);return
 if group in ["all","clock"]:test_clock()
 if group in ["all","expiry"]:test_expiry()
 if group in ["all","simultaneous"]:test_simultaneous()
 if group in ["all","reset"]:test_reset()
 if group in ["all","lifecycle"]:test_lifecycle()
 if group in ["all","offscreen"]:test_offscreen()
 var report={"checks":checks,"failures":failures,"metrics":metrics,"records":records,"group":group,"core_sha256":FileAccess.get_sha256("res://core/character_sim.gd"),"helper_sha256":FileAccess.get_sha256("res://core/directional_dash.gd"),"clock_sha256":FileAccess.get_sha256("res://core/character_clock.gd"),"offscreen_sha256":FileAccess.get_sha256("res://core/offscreen_duel.gd")}
 var output:String="user://asuna-clock-result-"+group+".json"
 var file=FileAccess.open(output,FileAccess.WRITE)
 if file!=null:file.store_string(JSON.stringify(report,"  "));file.close()
 print("ASUNA CLOCK RECOVERY group=",group," checks=",checks," failures=",failures.size()," result=",output)
 quit(0 if failures.is_empty() else 1)
func fixture(quiet:bool=false,star:int=2,auto_first:int=-1):
 var s=Sim.new()
 ck(s.configure([{"id":0,"team":0,"character_id":"asuna","star":star,"cell":Vector2(0,3)},{"id":7,"team":1,"character_id":"yuuka","star":1,"cell":Vector2(0,-3)}],{"seed":711,"max_ticks":1600,"random_damage":true}).is_empty(),"fixture configures")
 s.units[1].hp=1000000;s.units[1].max_hp=1000000;s.units[1].busy_until=100000
 if quiet:
  s.units[0].attack_ready=100000;s.units[0].aim_ready=100000;s.units[0].aimed=true;s.units[0].basic_ready=100000;s.units[0].skill_ready=100000
 if auto_first>=0:s.units[0].skill_ready=auto_first
 s._refresh_stats();ck(s.start(),"fixture starts")
 return s
func to_tick(s,until:int)->Array:
 var events:Array=[]
 while s.tick<until and s.phase=="running":events.append_array(s.step())
 return events
func normalized(events:Array)->Array:
 var result:Array=events.duplicate(true)
 for event in result:event.erase("generation")
 return result
func cast_count(events:Array,actor:int=0)->int:
 return events.filter(func(e):return e.type=="skill" and e.actor_id==actor).size()
func clock_stream(deltas:Array)->Dictionary:
 var clock=Clock.new();clock.sim=fixture();clock.generation=19
 var events:Array=[]
 for elapsed in deltas:events.append_array(clock.advance(elapsed))
 return {"state":clock.sim.snapshot(),"events":events,"accumulator":clock.accumulator}
func repeated(value:float,count:int)->Array:
 var result:Array=[]
 for i in range(count):result.append(value)
 return result
func test_clock()->void:
 ck(Sim.new().active_character_keys().size()==14 and Sim.new().active_character_keys().back()=="asuna","Asuna appended to fourteen-character active roster")
 var reference:Dictionary=clock_stream(repeated(0.05,400))
 var patterns:Dictionary={"0.4s":repeated(0.4,50),"60Hz":repeated(1.0/60.0,1200),"12.5Hz":repeated(0.08,250)}
 var irregular:Array=[]
 for i in range(57):irregular.append_array([0.013,0.137,0.004,0.196])
 irregular.append(0.05);patterns.irregular=irregular
 for name in patterns:
  var candidate:Dictionary=clock_stream(patterns[name])
  ck(candidate.state==reference.state,"clock complete snapshot/RNG parity "+name)
  ck(candidate.events==reference.events,"clock complete event-stream parity "+name)
  ck(absf(candidate.accumulator-reference.accumulator)<1e-8,"clock remainder parity "+name)
 ck(reference.state.tick==400 and cast_count(reference.events)>0 and reference.events.any(func(e):return e.type=="dash_move"),"partition reference exercises actual EX and dash")
 metrics.clock={"ticks":reference.state.tick,"events":reference.events.size(),"snapshot_sha256":JSON.stringify(reference.state).sha256_text(),"events_sha256":JSON.stringify(reference.events).sha256_text(),"partitions":patterns.keys()}
 for at in [7,8,39,40]:
  var clock=Clock.new();clock.sim=fixture(true);clock.generation=7
  clock.sim._try_skill(clock.sim.units[0],"ex");clock.sim.units[0].skill_ready=100000
  clock.advance(at*0.05)
  var before:Dictionary=clock.sim.snapshot();var remainder:float=clock.accumulator
  for delta in [0.0,-0.1,NAN,INF,-INF]:
   ck(clock.advance(delta).is_empty() and clock.sim.snapshot()==before and clock.accumulator==remainder,"invalid/paused time freezes full state at dash boundary %d (%s)"%[at,str(delta)])
  ck(clock.sim.stat(clock.sim.units[0],"DodgePoint")== (1116 if at in [8,39] else 778),"exclusive evasion boundary tick %d"%at)
 var one=fixture(false,1);var events:Array=to_tick(one,800)
 ck(cast_count(events)==0,"one-star real scheduler never casts EX")
 var two=fixture();events=to_tick(two,800)
 var casts:Array=events.filter(func(e):return e.type=="skill" and e.actor_id==0)
 ck(casts.size()>=2 and casts[0].tick==61,"automatic EX waits through acquisition/burst lock to tick61")
 for i in range(1,casts.size()):ck(casts[i].tick-casts[i-1].tick>=300,"automatic independent EX cooldown")
 ck(events.any(func(e):return e.type=="basic" and e.actor_id==0),"basic remains scheduled alongside EX/reload")
 for mode in ["busy","stun","reload"]:
  var s=fixture(true,2,1);var a:Dictionary=s.units[0]
  if mode=="busy":a.busy_until=70
  elif mode=="stun":a.stun_until=70
  else:a.reload_until=70;a.ammo=0
  ck(cast_count(to_tick(s,69))==0,"scheduler respects "+mode+" gate")
  var ready:Array=s.step();ck(cast_count(ready)==1,"scheduler casts at exclusive "+mode+" boundary")
 var priority=fixture(true,2,1);priority.units[0].basic_ready=1
 events=priority.step()
 ck(cast_count(events)==1 and not events.any(func(e):return e.type=="basic" and e.actor_id==0),"EX wins simultaneous basic readiness")
 ck(not to_tick(priority,53).any(func(e):return e.type in ["attack","basic","reload"] and e.actor_id==0),"53-tick EX lock prevents new attacks/basic/reload")
func test_expiry()->void:
 var s=fixture(true);var a:Dictionary=s.units[0];a.ammo=6
 ck(s._try_skill(a,"ex"),"expiry fixture casts")
 a.skill_ready=100000
 to_tick(s,599)
 ck(s.stat(a,"AttackSpeed")==19568 and a.ammo==6,"both speed buffs last through T+599 without refill")
 var end_events:Array=s.step()
 ck(s.stat(a,"AttackSpeed")==10000 and not a.buffs.has(EX_ID) and not a.buffs.has(SUB_ID),"both speed buffs expire before T+600 damage")
 ck(end_events.filter(func(e):return e.type=="buff_expired" and e.buff_id in [EX_ID,SUB_ID]).size()==2,"one expiry event for each distinct speed buff")
 s=fixture(true);a=s.units[0];s._try_skill(a,"ex");a.skill_ready=100000;a.buffs[SUB_ID].until=601
 to_tick(s,600)
 ck(not a.buffs.has(EX_ID) and a.buffs.has(SUB_ID) and s.stat(a,"AttackSpeed")==13831,"EX/sub remain independently expirable")
 s.step();ck(s.stat(a,"AttackSpeed")==10000,"remaining sub expires on its own boundary")
 s=fixture(true);a=s.units[0];s._try_skill(a,"ex")
 var recast_events:Array=to_tick(s,300)
 ck(cast_count(recast_events)==1 and a.buffs[EX_ID].until==900 and a.buffs[SUB_ID].until==900,"automatic recast refreshes both IDs once")
 ck(s.stat(a,"AttackSpeed")==19568 and a.buffs.keys().filter(func(id):return id in [EX_ID,SUB_ID]).size()==2,"recast never accumulates another speed stack")
 a.skill_ready=100000;to_tick(s,600)
 ck(s.stat(a,"AttackSpeed")==19568,"old expiry cannot remove refreshed speed buffs")
 to_tick(s,900);ck(s.stat(a,"AttackSpeed")==10000,"refreshed expiry remains exclusive")
 s=fixture(true);a=s.units[0];s._buff(a,"fixture_unrelated_speed","AttackSpeed",0.25,650,"fixture");s._try_skill(a,"ex");a.skill_ready=100000
 ck(s.stat(a,"AttackSpeed")==22068 and s.stat(a,"CriticalDamageRate")==25320,"unrelated speed adds normally; enhanced crit damage is independent")
 to_tick(s,600);ck(s.stat(a,"AttackSpeed")==12500,"Asuna expiry preserves unrelated speed buff")
 to_tick(s,650);ck(s.stat(a,"AttackSpeed")==10000,"unrelated buff keeps its own expiry")
 # Use actual pending normal-attack records and a seed separating the two hit probabilities.
 s=fixture(true);a=s.units[0]
 var base_probability:float=s.hit_probability(s.stat(s.units[1],"AccuracyPoint"),778)
 var moving_probability:float=s.hit_probability(s.stat(s.units[1],"AccuracyPoint"),1116)
 var chosen_seed:=-1
 for candidate in range(1,10000):
  var rng:=RandomNumberGenerator.new();rng.seed=candidate;var roll:float=rng.randf()
  if roll>=moving_probability and roll<base_probability:chosen_seed=candidate;break
 ck(chosen_seed>=0 and moving_probability>0,"evasion changes hit chance without invulnerability")
 for boundary in [7,8,39,40]:
  s=fixture(true);a=s.units[0];s._try_skill(a,"ex");a.skill_ready=100000;to_tick(s,boundary)
  s._normal_attack(s.units[1],a)
  var hit:Dictionary=s._pending[0].duplicate(true);hit.can_crit=false
  s.events=[];s._rng.seed=chosen_seed;s._resolve_hit(hit)
  ck(s.events.any(func(e):return e.type=="miss")== (boundary in [8,39]),"real random hit respects evasion boundary %d"%boundary)
 metrics.hit_boundary={"seed":chosen_seed,"base_probability":base_probability,"moving_probability":moving_probability}
func exact_segment_gap(point:Vector2,origin:Vector2,destination:Vector2)->float:
 var dx:float=float(destination.x)-origin.x;var dy:float=float(destination.y)-origin.y
 var px:float=float(point.x)-origin.x;var py:float=float(point.y)-origin.y
 var length_squared:float=dx*dx+dy*dy
 var along:float=clampf((px*dx+py*dy)/length_squared,0,1) if length_squared>0 else 0.0
 return sqrt(pow(px-dx*along,2)+pow(py-dy*along,2))
func simultaneous_stream(reverse:bool)->Dictionary:
 var s=Sim.new();var roster:Array=[{"id":0,"team":0,"character_id":"asuna","star":2,"cell":Vector2(0,1.6)},{"id":7,"team":1,"character_id":"asuna","star":2,"cell":Vector2(0,-1.6)}]
 if reverse:roster.reverse()
 ck(s.configure(roster,{"seed":904,"random_damage":true}).is_empty(),"opposing simultaneous fixture configures")
 for u in s.units:u.attack_ready=100000;u.aim_ready=100000;u.aimed=true;u.basic_ready=100000;u.skill_ready=1
 s.start();var events:Array=[];var steps:=0;var cancelled:=0
 for t in range(60):
  var positions:Dictionary={}
  for u in s.units:positions[u.id]=u.cell
  var last_actor:=-1
  var batch:Array=s.step();events.append_array(batch)
  for event in batch:
   if event.type=="dash_move":
    ck(event.actor_id>last_actor,"simultaneous dash order follows canonical IDs")
    last_actor=event.actor_id
    ck(event.from==positions[event.actor_id],"dash sweep starts at last authoritative cell")
    for other in positions:
     if other!=event.actor_id:ck(exact_segment_gap(positions[other],event.from,event.to)>=0.699999,"sequential simultaneous sweep preserves actor clearance")
    positions[event.actor_id]=event.to;steps+=1
   if event.type=="dash_finished" and event.reason=="blocked":cancelled+=1
  ck(s.units[0].cell.distance_to(s.units[1].cell)>=0.699999,"simultaneous final cells never overlap")
 ck(cast_count(events,0)==1 and cast_count(events,7)==1,"both opposing EX casts accepted on same readiness")
 ck(steps>0 and cancelled>0,"simultaneous fixture exercises actual movement and dynamic cancellation")
 for id in [0,7]:ck(events.any(func(e):return e.type=="dash_move" and e.actor_id==id),"both opposing dashes actually begin before collision")
 for u in s.units:ck(u.dash.is_empty() and not u.buffs.has(EVADE_ID) and s.stat(u,"AttackSpeed")==19568,"collision cleanup retains accepted speed buffs")
 return {"state":s.snapshot(),"events":events,"steps":steps,"cancelled":cancelled}
func test_simultaneous()->void:
 var forward:Dictionary=simultaneous_stream(false);var reversed:Dictionary=simultaneous_stream(true)
 ck(forward==reversed,"reordered input roster preserves full simultaneous dash state/events")
 metrics.simultaneous={"dash_steps":forward.steps,"blocked_finishes":forward.cancelled,"events_sha256":JSON.stringify(forward.events).sha256_text()}
func test_reset()->void:
 for at in [5,12,41]:
  var clock=Clock.new();clock.sim=fixture(true,2,1);clock.generation=30
  clock.advance(at*0.05);clock.sim.units[0].ammo=3;clock.sim.units[0].hp-=17
  clock.reset()
  ck(clock.generation==31 and clock.accumulator==0 and clock.sim.tick==0 and clock.sim.phase=="prepare","reset clears clock and advances generation at tick%d"%at)
  var a:Dictionary=clock.sim.units[0]
  ck(a.cell==Vector2(0,3) and a.ammo==15 and a.hp==a.max_hp and a.dash.is_empty() and a.buffs.is_empty() and clock.sim._pending.is_empty(),"reset restores original actor and removes transient dash/buffs at tick%d"%at)
  ck(clock.sim.start(),"reset simulation restarts")
  var replay_events:Array=clock.advance(3.0)
  var reference=Clock.new();reference.sim=fixture(true,2,1);reference.generation=30
  var expected_events:Array=[]
  for i in range(60):expected_events.append_array(reference.advance(0.05))
  ck(clock.sim.snapshot()==reference.sim.snapshot() and normalized(replay_events)==normalized(expected_events),"reset replay exactly reproduces full state/RNG/events modulo generation at tick%d"%at)
  ck(replay_events.all(func(e):return e.generation==31),"reset replay emits only the new generation")
 var s=fixture(true);s._try_skill(s.units[0],"ex");to_tick(s,12);s._end(-1,"fixture")
 var stopped:Dictionary=s.snapshot()
 ck(s.step().is_empty() and s.snapshot()==stopped,"finished simulation cannot advance dash or mutate state")
func test_offscreen()->void:
 var army:Array=[{"character_id":"asuna","star":2},{"character_id":"hoshino","star":2}]
 var enemy:Array=[{"character_id":"aris","star":2},{"character_id":"iori","star":2}]
 var results:Array=[];var event_count:=0;var dash_count:=0;var ex_count:=0;var comparisons:=0
 for budget in [1,7,128]:
  var job=Offscreen.new();ck(job.configure(army,enemy,"p1","p3",715,{"max_ticks":400}).is_empty(),"offscreen fixture configures budget%d"%budget)
  var actual=job._simulation
  var reference=Sim.new();var nav=Navigation.new();var hooks=ArenaHooks.new()
  ck(nav.configure(6.6,ArenaHooks.OBSTACLES).is_empty(),"offscreen reference arena configures")
  hooks.bind(reference,nav,ArenaHooks.OBSTACLES)
  ck(reference.configure(job._roster.duplicate(true),actual.options.duplicate(true)).is_empty() and reference.start(),"same-engine reference uses exact offscreen roster/options/hooks")
  var pre:Dictionary=actual.snapshot()
  ck(not job.advance(0) and not job.advance(-1) and actual.snapshot()==pre,"nonpositive offscreen budgets do not start or mutate")
  while not job.is_complete():
   job.advance(budget)
   var last_events:Array=[]
   while reference.tick<actual.tick:last_events=reference.step()
   ck(actual.snapshot()==reference.snapshot(),"offscreen full state/RNG checkpoint parity budget%d tick%d"%[budget,actual.tick]);comparisons+=1
   ck(actual.events==last_events,"offscreen actual final-step event parity budget%d tick%d"%[budget,actual.tick])
   if budget==1:
    event_count+=actual.events.size();dash_count+=actual.events.filter(func(e):return e.type=="dash_move").size()
    ex_count+=actual.events.filter(func(e):return e.type=="skill" and e.character_id=="asuna").size()
  results.append(job.result)
  reference.position_free=Callable();reference.segment_free=Callable();reference.path_step=Callable();reference.line_of_sight=Callable();reference.cover_query=Callable()
  ck(job.result.ok and job._simulation==null and job._arena==null and job._navigation==null,"completed offscreen job releases simulation and callbacks")
 var drain=Offscreen.new();drain.configure(army,enemy,"p1","p3",715,{"max_ticks":400});drain.run()
 ck(results[0]==results[1] and results[1]==results[2] and results[2]==drain.result,"budgets1/7/128 and synchronous drain have identical outcomes")
 ck(ex_count>0 and dash_count>0,"real offscreen fixture exercises Asuna EX and movement")
 var cancelled=Offscreen.new();cancelled.configure(army,enemy,"p1","p3",715,{"max_ticks":400});cancelled.advance(90)
 var captured=cancelled._simulation;cancelled.cancel();var snapshot:Dictionary=captured.snapshot()
 ck(cancelled.is_complete() and cancelled.result.error=="cancelled" and cancelled._simulation==null and cancelled._arena==null and cancelled._navigation==null,"cancel releases all offscreen ownership")
 ck(not captured.position_free.is_valid() and not captured.segment_free.is_valid() and not captured.path_step.is_valid() and not captured.cover_query.is_valid(),"cancel clears bound callbacks even when a test retains simulation reference")
 ck(cancelled.advance(128) and captured.snapshot()==snapshot,"cancelled job cannot resume retained simulation")
 var restart=Offscreen.new();restart.configure(army,enemy,"p1","p3",715,{"max_ticks":400});restart.run()
 ck(restart.result==drain.result,"fresh job after cancellation deterministically reproduces outcome")
 metrics.offscreen={"checkpoint_comparisons":comparisons,"one_tick_events":event_count,"asuna_ex_casts":ex_count,"dash_steps":dash_count,"result":drain.result}

func test_lifecycle()->void:
 var s=fixture(true);var a:Dictionary=s.units[0];s._try_skill(a,"ex");a.skill_ready=100000
 var frozen:Vector2=a.dash.destination;s.units[1].cell=Vector2(4,-3)
 to_tick(s,40)
 ck(a.cell.is_equal_approx(frozen),"enemy movement does not rotate or extend cast-frozen destination")
 s=fixture(true);a=s.units[0];s._try_skill(a,"ex");a.skill_ready=100000;to_tick(s,7)
 a.stun_until=30;var origin:Vector2=a.cell
 var batch:Array=s.step()
 ck(a.dash.is_empty() and s.stat(a,"DodgePoint")==778 and a.cell==origin,"pre-start stun cancels before movement/evasion")
 ck(not batch.any(func(e):return e.type=="buff" and e.buff_id==EVADE_ID),"windup stun emits no temporary evade insertion")
 to_tick(s,40);ck(a.cell==origin and s.stat(a,"AttackSpeed")==19568,"windup-stunned cast never resumes and keeps accepted speed")
 for boundary in [8,39,40]:
  s=fixture(true);a=s.units[0];s._try_skill(a,"ex");a.skill_ready=100000;to_tick(s,boundary)
  s.options.random_damage=false;s._normal_attack(s.units[1],a)
  var hit:Dictionary=s._pending[0].duplicate(true);hit.stun_seconds=0.5
  var before:Vector2=a.cell;s._resolve_hit(hit)
  ck(a.dash.is_empty() and not a.buffs.has(EVADE_ID) and s.stat(a,"DodgePoint")==778,"landed stun clears dash/evasion immediately at boundary%d"%boundary)
  s.step();ck(a.cell==before,"landed stun prevents later movement at boundary%d"%boundary)
 s=fixture(true);a=s.units[0];s._try_skill(a,"ex");a.skill_ready=100000;to_tick(s,10)
 var before_push:Vector2=a.cell;s._knockback(s.units[1],a,0.8)
 ck(a.dash.is_empty() and not a.buffs.has(EVADE_ID) and a.cell.distance_to(before_push)>0.79,"legal external knockback cancels dash before displacement")
 var after_push:Vector2=a.cell;to_tick(s,40)
 ck(a.cell==after_push and s.stat(a,"AttackSpeed")==19568,"knockback never snaps back onto the old trajectory")
 s=fixture(true);a=s.units[0];s._try_skill(a,"ex");a.skill_ready=100000;to_tick(s,10)
 before_push=a.cell;s.position_free=func(_point,_radius):return false
 s._knockback(s.units[1],a,0.8)
 ck(not a.dash.is_empty() and a.cell==before_push and a.buffs.has(EVADE_ID),"blocked knockback alone does not cancel the dash")
 s.position_free=Callable();s.step()
 ck(a.cell!=before_push and a.buffs.has(EVADE_ID),"dash continues after a failed external push")
