extends SceneTree
class QuietApp:
	extends "res://scripts/game_app.gd"
	# Do not write benchmark artifacts from lifecycle regression tests.
	func _save_battle_performance()->void:pass
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize()->void:call_deferred("run")
func finish_battle(app)->void:
	for _step in range(1300):
		if app.session.phase()!="battle":return
		if app.session.clock.sim.phase=="finished":break
		app._process(0.1)
	ck(app.session.clock.sim.phase=="finished","visible battle terminates within simulation duration")
	if app.session.clock.sim.phase!="finished":return
	# A synthetic 100ms frame is not one second of CPU time. Give the
	# bounded scheduler further frames instead of requiring a blocking drain.
	# Every positive pump advances at least one unfinished job tick.
	var limit:int=int(app.session.ai_battle_status().scheduled)*int(app.session.clock.sim.options.max_ticks)+1
	for _slice in range(limit):
		if app.session.phase()!="battle":return
		app._process(0.05)
	ck(false,"cooperative settlement terminates within total remaining tick bound")
func run()->void:
	var app=QuietApp.new();root.add_child(app);await process_frame;app.set_process(false)
	ck(app.act({"type":"restart","seed":17}).ok,"deterministic match starts")
	var player=app.session.rules._player_ref("p0");player.gold=100
	for slot in range(5):ck(app.act({"type":"buy_offer","slot":slot}).ok,"buy actual offer")
	for id in player.bench.duplicate():
		if player.deployed.size()<4:ck(app.act({"type":"deploy_unit","unit_id":id}).ok,"deploy actual owned unit")
	ck(app.act({"type":"start_battle"}).ok,"battle starts")
	app._process(0.6)
	app.session.paused=true
	var paused_tick:int=app.session.clock.sim.tick
	var paused_status:Dictionary=app.stage.bars[0].status.status.duplicate(true)
	app._process(2.0)
	ck(app.session.clock.sim.tick==paused_tick and app.stage.bars[0].status.status==paused_status,"pause freezes authoritative status")
	app.session.paused=false;finish_battle(app)
	ck(app.session.phase()=="result","actual battle reaches nonterminal result")
	var ended_tick:int=app.session.clock.sim.tick
	var ended_time:float=app.visual_time
	var statuses:Dictionary={}
	var active_cooldowns:=0
	for unit in app.session.clock.sim.units:
		if unit.hp<=0:continue
		statuses[unit.id]=app.stage.bars[unit.id].status.status.duplicate(true)
		if statuses[unit.id].basic.remaining_seconds>0:active_cooldowns+=1
	ck(active_cooldowns>0,"real result fixture has an unfinished cooldown")
	app._process(3.0)
	ck(app.session.clock.sim.tick==ended_tick,"result screen does not advance combat")
	ck(app.visual_time>ended_time,"result cosmetic animations can continue")
	for id in statuses:ck(app.stage.bars[id].status.status==statuses[id],"result HUD stays at actual last simulation tick")
	app.show_battle_report();var report:String=app.report_text.text
	ck(app.report_panel.visible and not report.is_empty(),"completed report opens")
	app.show_battle_report();ck(app.report_text.text==report,"repeated report clicks do not duplicate content")
	ck(not app.act({"type":"restart","seed":"bad"}).ok and app.report_panel.visible and app.report_text.text==report,"failed restart preserves current report")
	ck(app.act({"type":"next_round"}).ok,"result acknowledgement succeeds")
	ck(not app.report_panel.visible,"next round dismisses report for deployment")
	ck(not app.report_button.disabled,"previous report remains available in preparation")
	app.show_battle_report();ck(app.report_panel.visible and app.report_text.text==report,"previous report can reopen during preparation")
	ck(app.act({"type":"start_battle"}).ok,"next battle starts with report open")
	ck(not app.report_panel.visible and app.report_text.text.is_empty(),"new battle clears stale visible report")
	ck(app.report_button.disabled,"incomplete new report cannot open")
	app.show_battle_report();ck(not app.report_panel.visible,"repeated open during battle cannot revive old report")
	finish_battle(app);app.show_battle_report()
	ck(app.report_panel.visible,"second completed report opens")
	ck(app.act({"type":"restart","seed":18}).ok,"restart with report open succeeds")
	ck(not app.report_panel.visible and app.report_text.text.is_empty(),"restart clears stale report panel and text")
	ck(app.session.battle_feedback().is_empty() and app.report_button.disabled,"restart clears report authority and availability")
	var bought:Dictionary=app.act({"type":"buy_offer","slot":0})
	# One owned fixture character makes its real stationary passive observable.
	app.session.rules._player_ref("p0").units[0].character_id="haruna"
	ck(app.act({"type":"deploy_unit","unit_id":bought.unit_id}).ok,"preparation passive fixture deploys")
	var prep_status:Dictionary=app.stage.bars[0].status.status.duplicate(true)
	ck(not prep_status.effects.is_empty(),"stationary preparation passive is visible")
	app._process(121.0)
	ck(app.stage.bars[0].status.status==prep_status,"waiting in preparation cannot expire preview passives")
	app._place(0,Vector2(0,4))
	ck(app.stage.bars[0].status.status==prep_status,"placement uses preparation state rather than cosmetic age")
	app.queue_free();await process_frame
	print("GAME APP LIFECYCLE ",checks," checks; ",failures," failures");quit(1 if failures else 0)
