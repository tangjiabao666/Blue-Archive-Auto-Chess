extends SceneTree
const Session=preload("res://core/game_session.gd")
const Duel=preload("res://core/offscreen_duel.gd")
const FIXTURE:="res://tests/fixtures/normal_target_legacy_session_v2.json"
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func ready():
	var game=Session.new()
	ck(game.restore_save(JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))).ok,"genuine preparation fixture restores")
	return game
func live(game)->Dictionary:
	return {"rules":game.rules.snapshot(),"positions":game.positions.duplicate(true),"manual":game.manual_positions.duplicate(true),"ids":game.id_to_unit.duplicate(true),"seed":game.seed,"phase":game.phase(),"paused":game.paused,"error":game.last_error,"generation":game.clock.generation,"accumulator":game.clock.accumulator,"clock":game.clock,"navigation":game.navigation,"arena":game.arena_hooks,"completed_jobs":game._ai_last_status.duplicate(true),"simulation":game.clock.sim.snapshot(),"feedback":game.battle_feedback(),"jobs":game._ai_jobs.duplicate(),"policy":game.normal_target_policy()}
func reject(game,input:Dictionary,label:String)->void:
	var before:Dictionary=live(game);var original:Dictionary=input.duplicate(true)
	var result:Dictionary=game.command(input)
	ck(result.get("ok")==false and not result.get("error","").is_empty(),"reject "+label)
	ck(live(game)==before and input==original,"rejected "+label+" is atomic")
func play(game)->Array:
	var events:Array=[]
	for step in range(1200):
		if game.phase()!="battle":break
		events.append_array(game.advance(0.4))
	ck(game.phase() in ["result","finished"],"real round settles")
	for event in events:event.erase("generation")
	return events
func _initialize()->void:
	var game=ready()
	ck(game.has_method("normal_target_policy"),"session exposes scalar normal target policy")
	if failures:quit(1);return
	ck(game.normal_target_policy()=="nearest","legacy default is nearest")
	game.preview_roster();game.clock.accumulator=0.031
	var before:Dictionary=live(game)
	ck(game.command({"type":"set_normal_target_policy","policy":"wounded"}).ok,"preparation accepts wounded")
	var after:Dictionary=live(game);after.policy=before.policy
	ck(game.normal_target_policy()=="wounded" and after==before,"policy changes no economy RNG placement selection clock or report")
	before=live(game)
	ck(game.command({"type":"set_normal_target_policy","policy":"wounded"}).ok and live(game)==before,"same-value command is harmless")
	var cases:Array=[{}, {"policy":"nearest"}, {"type":"set_normal_target_policy"}, {"type":"set_normal_target_policy","policy":"nearest","extra":true}]
	for value in [null,true,false,0,1,1.0,[],{},["nearest","nearest"],"","WOUNDED","lowest_hp",&"nearest"]:
		cases.append({"type":"set_normal_target_policy","policy":value})
	for value in [null,true,0,[],{}]:cases.append({"type":value,"policy":"nearest"})
	for input in cases:reject(game,input,"strict command "+str(input))
	var blank=Session.new();reject(blank,{"type":"set_normal_target_policy","policy":"wounded"},"uninitialized phase")
	# Only phase is relevant to this command guard; no battle is simulated here.
	var guarded=ready();guarded.rules._state.phase="finished"
	reject(guarded,{"type":"set_normal_target_policy","policy":"wounded"},"finished phase")
	game.showing_result=true;reject(game,{"type":"set_normal_target_policy","policy":"nearest"},"result guard")
	ck(game.command({"type":"next_round"}).ok and game.normal_target_policy()=="wounded","next-round acknowledgment preserves choice")
	var preview:Dictionary=game.opponent_preview()
	ck(preview.get("normal_target_policy")=="nearest","scouting declares fixed NPC nearest")
	preview.normal_target_policy="wounded"
	ck(game.opponent_preview().get("normal_target_policy")=="nearest","scouting result is detached")
	for left in range(8):
		for right in range(8):
			if left==right:continue
			var options:Dictionary=game.call("_battle_options",71,"p%d"%left,"p%d"%right)
			var expected:Array=["wounded" if left==0 else "nearest","wounded" if right==0 else "nearest"]
			ck(options.get("normal_target_policies")==expected,"explicit participant policies p%d vs p%d"%[left,right])
			options.normal_target_policies[0]="tampered"
			ck(game.call("_battle_options",71,"p%d"%left,"p%d"%right).normal_target_policies==expected,"participant options detached")
	for invalid in ["","p8","p-1","P0","unknown"]:
		var options:Dictionary=game.call("_battle_options",71,invalid,"p1")
		ck(options.get("normal_target_policies",[]).size()!=2 or options.normal_target_policies[0] not in ["nearest","wounded"],"unknown participant never silently nearest")
	reject(game,{"type":"restart","seed":2147483648},"invalid restart in preparation")
	before=live(game)
	ck(not game.new_game(2147483648).ok and live(game)==before,"failed new game preserves choice and all state")
	ck(game.command({"type":"restart"}).ok and game.normal_target_policy()=="nearest","successful restart resets nearest")
	ck(game.command({"type":"set_normal_target_policy","policy":"wounded"}).ok,"select before new game")
	ck(game.new_game(17).ok and game.normal_target_policy()=="nearest","successful new game resets nearest")
	if "--validation-only" in OS.get_cmdline_user_args():
		print("NORMAL TARGET SESSION VALIDATION ",checks," checks FAILURES=",failures);quit(1 if failures else 0);return
	game=ready();game.command({"type":"set_normal_target_policy","policy":"wounded"})
	var checkpoint:Dictionary=game.export_save().data
	var peer=Session.new();ck(peer.restore_save(checkpoint).ok,"wounded checkpoint restores")
	var start:Dictionary=game.command({"type":"start_battle"})
	ck(start.ok,"wounded real visible and offscreen battles start")
	if not start.ok:quit(1);return
	ck(game.clock.sim.options.normal_target_policies==["wounded","nearest"],"visible policies resolve p0 versus actual NPC")
	var report:Dictionary=game.battle_feedback()
	ck(report.get("normal_target_policies")==["wounded","nearest"],"battle feedback freezes actual policies")
	report.normal_target_policies[0]="nearest"
	ck(game.battle_feedback().normal_target_policies==["wounded","nearest"],"feedback nested policies detached")
	var status:Dictionary=game.ai_battle_status()
	ck(status.get("jobs",[]).size()==start.battle.ai_pairs.size(),"each NPC job has diagnostics")
	for index in range(status.get("jobs",[]).size()):
		var row:Dictionary=status.jobs[index];var pair:Array=start.battle.ai_pairs[index]
		ck(row.left_id==pair[0] and row.right_id==pair[1] and row.normal_target_policies==["nearest","nearest"],"real NPC pair explicitly nearest on both sides")
		row.normal_target_policies[0]="wounded"
		ck(game.ai_battle_status().jobs[index].normal_target_policies==["nearest","nearest"],"job diagnostics nested data detached")
	# Inspect actual, configured source simulations before worker execution.
	# Cancel/run these additional jobs afterwards to release their bound hooks.
	var prepared:Dictionary=game._prepare_ai_jobs(start.battle)
	ck(prepared.ok,"real NPC job preparations configure")
	for entry in prepared.get("jobs",[]):
		ck(entry.job._simulation.options.normal_target_policies==["nearest","nearest"],"actual offscreen simulation never inherits player wounded")
		entry.diagnostics.normal_target_policies[0]="wounded"
		ck(entry.job._simulation.options.normal_target_policies==["nearest","nearest"],"diagnostics cannot mutate configured simulator")
		entry.job.cancel();entry.job.run()
	reject(game,{"type":"set_normal_target_policy","policy":"nearest"},"battle phase")
	reject(game,{"type":"restart","seed":2147483648},"invalid active restart")
	var malformed:Dictionary=checkpoint.duplicate(true);malformed.normal_target_policy=[]
	before=live(game);ck(not game.restore_save(malformed).ok and live(game)==before,"invalid active restore cancels nothing")
	ck(peer.command({"type":"start_battle"}).ok,"restored wounded battle starts")
	var first:Array=play(game);var second:Array=play(peer)
	ck(first==second and game.rules.snapshot()==peer.rules.snapshot() and game.battle_feedback()==peer.battle_feedback(),"restored wounded visible/offscreen continuations deterministic")
	var completed:Dictionary=game.ai_battle_status().last_completed
	ck(completed.get("jobs",[]).size()==3,"completed NPC diagnostics retained")
	for row in completed.get("jobs",[]):
		ck(row.normal_target_policies==["nearest","nearest"],"completed NPC policies frozen")
		row.normal_target_policies[0]="wounded"
	for row in game.ai_battle_status().last_completed.get("jobs",[]):ck(row.normal_target_policies==["nearest","nearest"],"completed diagnostics detached")
	var frozen:Dictionary=game.battle_feedback()
	ck(game.command({"type":"next_round"}).ok and game.normal_target_policy()=="wounded","real next round preserves policy")
	ck(game.command({"type":"set_normal_target_policy","policy":"nearest"}).ok and game.battle_feedback()==frozen,"later preparation never rewrites earlier report")
	# A missing source in an actual NPC army rejects the entire prospective start.
	var failed=ready();failed.command({"type":"set_normal_target_policy","policy":"wounded"})
	var bad:Dictionary=failed.rules.snapshot();bad.catalog.append({"id":"unavailable_source","name":"Unavailable","cost":1,"ex_cooldown":8.0})
	var npc:Dictionary=bad.players[int(str(bad.next_opponent.ai_pairs[0][0]).substr(1))]
	for unit in npc.units:
		if unit.id==npc.deployed[0]:unit.character_id="unavailable_source";break
	ck(failed.rules.restore(bad).ok,"missing-source fixture valid in generic economy")
	reject(failed,{"type":"start_battle"},"failed offscreen start")
	var interrupted=ready();interrupted.command({"type":"set_normal_target_policy","policy":"wounded"});interrupted.command({"type":"start_battle"})
	var old_job=weakref(interrupted._ai_jobs[0].job)
	ck(interrupted.restore_save(checkpoint).ok and interrupted.normal_target_policy()=="wounded","valid restore installs saved policy after reset")
	ck(old_job.get_ref()==null and interrupted.ai_battle_status().scheduled==0 and interrupted.battle_feedback().is_empty(),"restore cancels and discards old battle metadata")
	interrupted.command({"type":"start_battle"});old_job=weakref(interrupted._ai_jobs[0].job)
	ck(interrupted.command({"type":"restart","seed":23}).ok and interrupted.normal_target_policy()=="nearest" and old_job.get_ref()==null,"active successful restart resets policy and releases jobs")
	# Failed settlement keeps its choice and rejects changes until a valid reset.
	var cancelled=ready();cancelled.command({"type":"set_normal_target_policy","policy":"wounded"});cancelled.command({"type":"start_battle"})
	var record:Dictionary=cancelled._ai_jobs[0]
	record.job.cancel()
	var stopped=Duel.new();ck(stopped.configure([],[],"p1","p2",17).is_empty(),"cancelled-result source job configures")
	stopped.cancel();stopped.run();record.job=stopped
	before=live(cancelled)
	for step in range(1200):
		if cancelled.phase()!="battle":break
		cancelled.advance(0.4)
	ck(cancelled.phase()=="error" and cancelled.normal_target_policy()=="wounded" and cancelled.rules.snapshot()==before.rules,"cancelled settlement preserves policy and economy")
	reject(cancelled,{"type":"set_normal_target_policy","policy":"nearest"},"error phase")
	ck(cancelled.command({"type":"restart"}).ok and cancelled.normal_target_policy()=="nearest","error restart resets nearest")
	# Actual retained legacy2 and its canonical save settle identical nearest battles.
	var old=ready();var canonical=Session.new();canonical.restore_save(old.export_save().data)
	var retained:Array=old.rules.get_player().shop.duplicate(true)
	ck(old.command({"type":"start_battle"}).ok and canonical.command({"type":"start_battle"}).ok,"legacy and canonical real continuations start")
	first=play(old);second=play(canonical)
	ck(first==second and old.rules.snapshot()==canonical.rules.snapshot() and old.battle_feedback()==canonical.battle_feedback(),"real legacy2 and v3 continuation identical including NPC settlement")
	ck(old.rules.get_player().shop==retained and not old.rules.get_player().shop_locked,"real next round preserves retained offers and consumes flag once")
	print("NORMAL TARGET SESSION ",checks," checks FAILURES=",failures);quit(1 if failures else 0)
