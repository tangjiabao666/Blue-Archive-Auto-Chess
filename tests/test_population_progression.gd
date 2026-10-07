extends SceneTree
const Rules=preload("res://core/prototype_match.gd")
var failures:=0
func ck(ok:bool,message:String):
	if not ok:failures+=1;printerr("FAIL: "+message)
func _initialize():
	var rules=Rules.new();ck(rules.new_match(17,[],{"starting_gold":1000}).ok,"new match")
	ck(rules.snapshot().config.max_level==6,"maximum is six")
	var player=rules._player_ref("p0");ck(player.level==4,"start with four slots")
	var ids:Array=[]
	for i in range(7):
		var id="u%06d"%rules._state.next_unit_id
		rules._state.next_unit_id+=1;ids.append(id)
		player.units.append({"id":id,"character_id":rules.snapshot().catalog[i].id,"star":1,"base_enabled":true,"passive_enabled":true,"ex_enabled":false})
		player.bench.append(id)
	for i in range(4):ck(rules.execute({"type":"deploy_unit","unit_id":ids[i]}).ok,"initial slot %d"%i)
	var before=rules.snapshot()
	ck(rules.execute({"type":"deploy_unit","unit_id":ids[4]}).error=="deployment_full","fifth requires upgrade")
	ck(rules.snapshot()==before,"initial cap failure atomic")
	ck(rules.execute({"type":"buy_xp"}).ok and rules.get_player().level==4,"four XP does not unlock fifth yet")
	ck(rules.execute({"type":"buy_xp"}).ok and rules.get_player().level==5,"eight XP unlocks fifth")
	ck(rules.execute({"type":"deploy_unit","unit_id":ids[4]}).ok,"deploy fifth after upgrade")
	ck(rules.execute({"type":"deploy_unit","unit_id":ids[5]}).error=="deployment_full","sixth requires next upgrade")
	for i in range(3):ck(rules.execute({"type":"buy_xp"}).ok,"buy experience toward six")
	ck(rules.get_player().level==6,"twelve more XP unlocks six")
	ck(rules.execute({"type":"deploy_unit","unit_id":ids[5]}).ok,"deploy sixth")
	before=rules.snapshot()
	ck(rules.execute({"type":"buy_xp"}).error=="max_level","upgrade stops at six")
	ck(rules.snapshot()==before,"rejected upgrade atomic")
	ck(rules.execute({"type":"deploy_unit","unit_id":ids[6]}).error=="deployment_full","seventh rejected")
	ck(rules.snapshot()==before,"rejected seventh atomic")
	ck(rules.snapshot().config.bench_capacity==9 and rules.snapshot().catalog.size()==7,"bench and roster retained")
	ck(rules.restore(rules.snapshot()).ok,"valid six-unit snapshot restores")
	var invalid=rules.snapshot();invalid.config.max_level=7
	ck(not rules.restore(invalid).ok,"seven-slot config rejected")
	ck(not Rules.new().new_match(17,[],{"max_level":7}).ok,"cannot bypass six-unit cap")
	for round_index in range(1,16):
		rules._state.round=round_index
		for i in range(1,8):
			var ai=rules._player_ref("p%d"%i);ai.gold=1000;rules._prepare_ai(ai)
			ck(ai.level<=6 and ai.deployed.size()<=6,"AI cap round%d player%d"%[round_index,i])
	print("POPULATION PROGRESSION FAILURES=",failures);quit(1 if failures else 0)
