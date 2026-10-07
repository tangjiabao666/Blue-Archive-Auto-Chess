extends SceneTree
var fails:=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func _initialize():call_deferred("run")
func run():
	var path="res://scripts/battle_stage.gd";ck(ResourceLoader.exists(path),"integrated battle stage exists")
	if not ResourceLoader.exists(path):quit(1);return
	var stage=load(path).new();root.add_child(stage)
	var session=load("res://core/game_session.gd").new();session.new_game(17)
	var buy=session.command({"type":"buy_offer","slot":0});session.command({"type":"deploy_unit","unit_id":buy.unit_id})
	stage.configure(session.profiles,session.OBSTACLES)
	stage.set_roster(session.preview_roster(),1,true)
	ck(stage.views.size()==1,"native own character displayed in preparation")
	stage.set_selected(0);ck(stage.views[0].get_node("AttackRangeIndicator").visible,"range visible only for selected preparation unit")
	stage.update_display(session.preview_roster(),[],0.25)
	session.command({"type":"start_battle"});stage.set_roster(session.clock.sim.units,session.clock.generation,false)
	ck(stage.views.size()>1,"opponent native army displayed")
	var events=session.advance(0.5);stage.update_display(session.clock.sim.units,events,session.clock.sim.tick*0.05)
	for view in stage.views.values():ck(not view.get_node("AttackRangeIndicator").visible,"no preparation rings during combat")
	stage.queue_free();await process_frame
	print("BATTLE STAGE FAILURES=",fails);quit(1 if fails else 0)
