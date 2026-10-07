extends SceneTree
var fails:=0
func ck(ok:bool,message:String):
	if not ok:fails+=1;printerr(message)
func _initialize():call_deferred("run")
func run():
	var app=load("res://scripts/gameplay.tscn").instantiate();root.add_child(app);await process_frame
	app.set_process(false)
	ck(app.act({"type":"restart","seed":17}).ok,"deterministic UI scenario")
	if not "combat_audio" in app:
		ck(false,"GameApp must own combat audio independently from Stage/warmup")
		app.queue_free();await process_frame;print("GAME AUDIO FAILURES=",fails);quit(1);return
	ck(app.combat_audio.get_parent()==app,"audio is owned by live GameApp")
	ck(not app.combat_audio.output_enabled,"headless test must not emit device audio")
	var buy:Dictionary=app.act({"type":"buy_offer","slot":0})
	app.act({"type":"deploy_unit","unit_id":buy.unit_id})
	app.act({"type":"start_battle"})
	ck(app.combat_audio.generation==app.session.clock.generation,"audio begins current epoch")
	var actor:Dictionary=app.session.clock.sim.units[0]
	app.combat_audio.consume({"type":"skill","ability":"ex","actor_id":actor.id,"character_id":actor.character_id,"tick":0,"event_id":"fixture","generation":app.session.clock.generation})
	app.session.paused=true;app._process(0.1)
	ck(app.combat_audio.diagnostics().played_count==0,"paused app does not launch scheduled SFX")
	app.session.paused=false
	for _frame in range(8):app._process(0.1)
	ck(app.combat_audio.diagnostics().played_count>0,"unpaused live app advances scheduled SFX")
	for i in range(1600):
		app._process(0.1)
		if app.session.phase()!="battle":break
	ck(app.session.clock.sim.phase=="finished","visible battle ends within simulated duration")
	# Synthetic frame delta is not elapsed CPU time for cooperative AI jobs.
	# Every positive scheduler slice advances at least one pending job tick.
	var settlement_bound:int=int(app.session.ai_battle_status().scheduled)*int(app.session.clock.sim.options.max_ticks)+1
	for _slice in range(settlement_bound):
		if app.session.phase()!="battle":break
		app._process(0.05)
	ck(app.session.phase() in ["result","finished"],"audio-integrated battle terminates")
	for _tail_frame in range(9):app._process(0.1)
	ck(app.combat_audio.diagnostics().queued_events==0,"battle result cancels delayed cues after bounded audio tail")
	ck(app.combat_audio.diagnostics().active_voices==0,"battle result stops skill audio")
	app.act({"type":"restart"})
	ck(app.combat_audio.diagnostics().queued_events==0,"restart flushes audio queue")
	ck(app.combat_audio.diagnostics().active_voices==0,"restart flushes active audio")
	app.queue_free();await process_frame
	print("GAME AUDIO FAILURES=",fails);quit(1 if fails else 0)
