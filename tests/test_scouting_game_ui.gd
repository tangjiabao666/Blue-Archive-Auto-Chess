extends SceneTree
var fails:=0
func ck(ok:bool,label:String):
	if not ok:fails+=1;printerr(label)
func _initialize():call_deferred("run")
func run():
	var app=load("res://scripts/gameplay.tscn").instantiate();root.add_child(app);await process_frame;app.set_process(false)
	ck(app.act({"type":"restart","seed":17}).ok,"deterministic UI scenario")
	var preview=app.session.opponent_preview()
	var enemies=app.stage.units.filter(func(u):return u.team==1)
	ck(enemies.size()==preview.units.size() and enemies.size()>0,"preparation renders locked enemy army")
	ck(app.status.text.contains(preview.name),"preparation identifies next opponent")
	var bought=app.act({"type":"buy_offer","slot":0});ck(bought.ok,"buy from scout view")
	ck(app.act({"type":"deploy_unit","unit_id":bought.unit_id}).ok,"deploy alongside enemy preview")
	var own=app.session.rules.get_player().deployed[0]
	ck(app.session.place(own,Vector2(0,4.7)),"free positioning remains available")
	app._place(0,Vector2(0.5,4.7))
	ck(app.session.positions[own]==Vector2(0.5,4.7),"dragging commits a legal position on current terrain")
	ck(app.stage.units.filter(func(u):return u.team==1).size()==preview.units.size(),"dragging preserves enemy preview")
	ck(app.act({"type":"start_battle"}).ok,"scouted battle starts")
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
	ck(app.has_method("show_battle_report"),"battle report can be opened")
	if app.has_method("show_battle_report"):
		app.show_battle_report();ck(app.report_panel.visible,"report panel visible")
		ck(app.report_text.text.contains("输出") and app.report_text.text.contains("EX"),"report exposes factual counters")
	app.queue_free();await process_frame
	print("SCOUTING UI FAILURES=",fails);quit(1 if fails else 0)
