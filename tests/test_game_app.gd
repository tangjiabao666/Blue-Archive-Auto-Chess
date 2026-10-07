extends SceneTree
var fails:=0
func ck(ok:bool,message:String):
	if not ok:fails+=1;printerr(message)
func _initialize():call_deferred("run")
func run():
	ck(ResourceLoader.exists("res://scripts/gameplay.tscn"),"playable scene must exist")
	if fails:quit(1);return
	var app=load("res://scripts/gameplay.tscn").instantiate();root.add_child(app);await process_frame
	app.set_process(false)
	ck(app.session.phase()=="preparation","starts in shop")
	app.session.rules._player_ref("p0").gold=100
	while app.session.rules.get_player().level<5:ck(app.act({"type":"buy_xp"}).ok,"upgrade toward five slots")
	ck(app.xp_button.disabled,"XP button disabled at five")
	ck(app.economy.text.contains("上阵 0/5"),"five-slot counter")
	ck(app._error_text("deployment_full").contains("5"),"full-board error states five-person maximum")
	ck(not app._error_text("deployment_full").contains("升级"),"full-board error must not promise another slot")
	ck(app.act({"type":"restart","seed":17}).ok,"deterministic restart after cap check")
	var result=app.act({"type":"buy_offer","slot":0})
	ck(result.ok,"UI buy delegates to session")
	app.select_owned(result.unit_id)
	ck(app.act({"type":"deploy_unit","unit_id":result.unit_id}).ok,"UI deploy works")
	ck(app.stage.units.filter(func(u):return u.team==0).size()==1,"stage displays purchased character alongside scouted enemy")
	ck(app.act({"type":"start_battle"}).ok,"UI starts battle")
	ck(not app.stage.preparation,"placement disabled in battle")
	app.session.paused=true;var tick=app.session.clock.sim.tick;app._process(0.1)
	ck(app.session.clock.sim.tick==tick,"UI pause freezes simulation")
	app.session.paused=false
	for i in range(160):
		app.session.advance(1.0)
		if app.session.phase()!="battle":break
	ck(app.session.clock.sim.phase=="finished","visible battle ends within simulated duration")
	# Synthetic frame delta is not elapsed CPU time for cooperative AI jobs.
	# Every positive scheduler slice advances at least one pending job tick.
	var settlement_bound:int=int(app.session.ai_battle_status().scheduled)*int(app.session.clock.sim.options.max_ticks)+1
	for _slice in range(settlement_bound):
		if app.session.phase()!="battle":break
		app.session.advance(0.05)
	app._process(0.0)
	ck(app.session.phase() in ["result","finished"],"actual battle ends")
	if app.session.phase()=="result":
		ck(app.economy.text.begins_with("第 %d/6 回合"%app.session.rules.snapshot().last_result.round),"result header names the round just completed")
		ck(app.act({"type":"next_round"}).ok,"next round works")
		ck(app.stage.preparation,"free placement restored")
	ck(app.act({"type":"restart"}).ok,"restart works")
	ck(app.stage.units.filter(func(u):return u.team==0).is_empty(),"restart clears old friendly combatants")
	app.queue_free();await process_frame
	print("GAME APP FAILURES=",fails);quit(1 if fails else 0)
