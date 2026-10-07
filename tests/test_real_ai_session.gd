extends SceneTree
const Session=preload("res://core/game_session.gd")
const Rules=preload("res://core/prototype_match.gd")
const Duel=preload("res://core/offscreen_duel.gd")
var fails:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:fails+=1;printerr(label)
func ready(seed_value:int=17):
 var game=Session.new();ck(game.new_game(seed_value).ok,"real AI session initializes")
 game.rules._prepare_ai(game.rules._player_ref("p0"));return game
func play(game,delta:float=0.25)->Array:
 var events:Array=[]
 for i in range(10000):
  if game.phase()!="battle":break
  events.append_array(game.advance(delta))
  if not game.last_error.is_empty():ck(false,"live resolution error: "+game.last_error);break
 ck(game.phase() in ["result","finished"],"real AI round reaches result")
 return events
func bare(rows:Array)->Array:
 var result:Array=[]
 for row in rows:
  var entry:Dictionary={}
  for key in ["left_id","right_id","winner","left_remaining","right_remaining","duration_ticks","finish_reason"]:entry[key]=row[key]
  result.append(entry)
 return result
func _initialize():
 var game=ready()
 ck(game.has_method("ai_battle_status"),"playable session schedules real offscreen battles")
 if fails:quit(1);return
 var start:Dictionary=game.command({"type":"start_battle"});ck(start.ok,"player combat starts")
 var battle:Dictionary=start.battle
 ck(game.ai_battle_status().scheduled==battle.ai_pairs.size() and battle.ai_pairs.size()==3,"all three locked AI pairings scheduled")
 var snapshot:Dictionary=game.rules.snapshot();var reference_outcomes:Array=[]
 for pair in battle.ai_pairs:
  var duel=Duel.new();var left:Array=game.rules._deployed_units(game.rules._player_ref(pair[0]));var right:Array=game.rules._deployed_units(game.rules._player_ref(pair[1]))
  var options={"area_ex_coverage_targeting":true,"arena_half":Session.HALF_SIZE,"initial_basic_delay_cap_seconds":Session.INITIAL_BASIC_DELAY_CAP_SECONDS,"overtime_enabled":true,"overtime_start_seconds":75.0,"overtime_ramp_seconds":30.0,"overtime_min_sustain_multiplier":0.2}
  ck(duel.configure(left,right,pair[0],pair[1],Duel.derive_seed(17,battle.round,pair[0],pair[1]),options).is_empty(),"independent pair configures")
  duel.run();reference_outcomes.append(duel.result.outcome)
 var state_before:Dictionary=game.rules.snapshot();var sim_before:Dictionary=game.clock.sim.snapshot()
 for i in range(10):game.ai_battle_status();game.opponent_preview()
 ck(game.rules.snapshot()==state_before and game.clock.sim.snapshot()==sim_before,"job status reads never change gameplay or RNG")
 game.paused=true;ck(game.advance(20).is_empty() and game.rules.snapshot()==state_before and game.clock.sim.snapshot()==sim_before,"pause freezes visible authoritative battle")
 game.paused=false;var events:Array=play(game)
 var result:Dictionary=game.rules.snapshot().last_result
 ck(bare(result.ai_results)==reference_outcomes,"all offscreen results equal independent same-engine battles in locked order")
 for row in result.ai_results:ck(row.resolution=="simulation","playable app never estimates AI winner")
 ck(game.ai_battle_status().pending==0,"all cooperative jobs completed at result")
 var restored=Rules.new();ck(restored.restore(JSON.parse_string(JSON.stringify(snapshot))).ok,"current battle snapshot restores")
 var resolved:Dictionary=restored.execute({"type":"resolve_battle","battle_id":result.battle_id,"winner":result.winner,"player_remaining":result.player_remaining,"opponent_remaining":result.opponent_remaining,"ai_outcomes":bare(result.ai_results)})
 ck(resolved.ok and restored.snapshot()==game.rules.snapshot(),"replaying exact real results preserves next-round RNG, armies and economics")
 var a=ready(42);var b=ready(42);a.command({"type":"start_battle"});b.command({"type":"start_battle"})
 var ea:Array=play(a,0.05);var eb:Array=play(b,0.4)
 ck(ea==eb and a.rules.snapshot()==b.rules.snapshot() and a.battle_feedback()==b.battle_feedback(),"cooperative partition order and frame batching cannot affect results")
 game=ready(17);game.command({"type":"start_battle"});state_before=game.rules.snapshot();sim_before=game.clock.sim.snapshot()
 var old_job=weakref(game._ai_jobs[0].job)
 ck(not game.command({"type":"restart","seed":2147483648}).ok,"invalid restart rejected")
 ck(game.rules.snapshot()==state_before and game.clock.sim.snapshot()==sim_before and game.ai_battle_status().scheduled==3,"failed restart does not disturb active jobs or player state")
 ck(game.command({"type":"restart","seed":23}).ok,"restart with active jobs succeeds")
 ck(game.phase()=="preparation" and game.ai_battle_status().scheduled==0 and game.battle_feedback().is_empty(),"restart cancels and discards old offscreen results")
 ck(old_job.get_ref()==null,"cancelled cooperative job and its source state are released")
 game=ready();game.command({"type":"start_battle"});old_job=weakref(game._ai_jobs[0].job);game=null
 ck(old_job.get_ref()==null,"session destruction releases pending jobs")
 # Force a real completed cancellation result without relying on a timing race.
 game=ready();game.command({"type":"start_battle"});state_before=game.rules.snapshot()
 var record:Dictionary=game._ai_jobs[0]
 record.job.cancel()
 var cancelled=Duel.new();ck(cancelled.configure([],[],"p1","p2",17).is_empty(),"cancellation fixture configures")
 cancelled.cancel();cancelled.run();ck(cancelled.result.error=="cancelled","injected result is genuinely cancelled");record.job=cancelled
 for i in range(10000):
  if game.phase()!="battle":break
  game.advance(0.25)
 ck(game.phase()=="error" and not game.last_error.is_empty(),"cancelled outcome halts settlement visibly")
 ck(game.rules.snapshot()==state_before and game.ai_battle_status().scheduled==0,"failed outcome neither changes HP/economy nor leaves queued jobs")
 ck(game.command({"type":"restart","seed":17}).ok and game.phase()=="preparation" and game.last_error.is_empty(),"failed settlement recovers by fresh restart")
 # Generic economy snapshots can contain a known-catalog name absent from source assets.
 game=ready();var bad:Dictionary=game.rules.snapshot();bad.catalog.append({"id":"unavailable_source","name":"Unavailable","cost":1,"ex_cooldown":8.0})
 var other_id:String=bad.next_opponent.ai_pairs[0][0]
 var other:Dictionary=bad.players[int(other_id.substr(1))]
 for unit in other.units:
  if unit.id==other.deployed[0]:unit.character_id="unavailable_source";break
 ck(game.rules.restore(bad).ok,"missing-source fixture remains valid generic economy state")
 state_before=game.rules.snapshot();sim_before=game.clock.sim.snapshot();var positions_before=game.positions.duplicate(true);var ids_before=game.id_to_unit.duplicate(true)
 var failed:Dictionary=game.command({"type":"start_battle"})
 ck(not failed.ok,"offscreen unknown source fails start instead of guessing winner")
 ck(game.rules.snapshot()==state_before and game.clock.sim.snapshot()==sim_before and game.positions==positions_before and game.id_to_unit==ids_before and game.ai_battle_status().scheduled==0,"failed job preparation rolls back whole start without launching tasks")
 print("REAL AI SESSION ",checks," checks FAILURES=",fails);quit(1 if fails else 0)
