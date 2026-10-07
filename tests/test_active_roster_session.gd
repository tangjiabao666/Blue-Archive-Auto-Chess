extends SceneTree
const Session=preload("res://core/game_session.gd")
const Sim=preload("res://core/character_sim.gd")
var failures:=0
func ck(ok:bool,label:String)->void:
	if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize()->void:
	var seen:Dictionary={}
	var shop_game=Session.new();ck(shop_game.new_game(17).ok,"expanded seeded match starts")
	for iteration in range(80):
		for participant in shop_game.rules.snapshot().players:
			for offer in participant.shop:
				if not offer.is_empty():seen[offer.character_id]=true
		shop_game.rules._roll_shop(shop_game.rules._player_ref("p0"))
	ck(seen.size()==Session.ACTIVE.size(),"real seeded shop roll can offer every active character")
	for key in Session.ACTIVE:
		var game=Session.new();ck(game.new_game(17).ok,"new session: "+key)
		var player:Dictionary=game.rules._player_ref("p0")
		player.gold=100
		# Controlled offers preserve the real source catalog, buy/merge/deploy pipeline.
		for slot in range(3):player.shop[slot]={"character_id":key,"cost":Session.COSTS[key]}
		var first:Dictionary=game.command({"type":"buy_offer","slot":0})
		ck(first.ok,"first copy buys: "+key)
		if not first.ok:continue
		ck(game.command({"type":"deploy_unit","unit_id":first.unit_id}).ok,"first copy deploys: "+key)
		ck(game.place(first.unit_id,Vector2(0,4)),"first copy free placement: "+key)
		ck(game.rules.get_player().units[0].star==1 and not game.rules.get_player().units[0].ex_enabled,"one copy cannot unlock EX: "+key)
		ck(game.command({"type":"buy_offer","slot":1}).ok,"second copy buys: "+key)
		for unit in game.rules.get_player().units:ck(unit.star==1 and not unit.ex_enabled,"two copies cannot unlock EX: "+key)
		var merged:Dictionary=game.command({"type":"buy_offer","slot":2})
		ck(merged.ok and merged.merged_ids.size()==2 and merged.unit_id==first.unit_id,"third copy merges into deployed survivor: "+key)
		player=game.rules.get_player()
		ck(player.units.size()==1 and player.units[0].star==2 and player.units[0].ex_enabled,"single three-copy merge enables EX: "+key)
		ck(player.gold==100-Session.COSTS[key]*3,"three copies deduct adapted gold price: "+key)
		ck(game.positions[first.unit_id]==Vector2(0,4),"merge preserves player formation: "+key)
		var saved:Dictionary=game.rules.snapshot();var restored=Session.new()
		ck(restored.rules.restore(JSON.parse_string(JSON.stringify(saved))).ok,"expanded roster save restores: "+key)
		ck(restored.rules.get_player().units==player.units,"restored merge star/EX preserved: "+key)
		ck(game.command({"type":"start_battle"}).ok,"source-native merged character starts combat: "+key)
		ck(game.clock.sim.units[0].character_id==key and game.clock.sim.units[0].star==2,"merged identity reaches real simulation: "+key)
		# Durable targets keep this an automatic-cast test, independent of random kill time.
		for unit in game.clock.sim.units:unit.max_hp=10000000;unit.hp=10000000
		var casts:=0
		for tick in range(600):
			for event in game.advance(0.05):
				if event.type=="skill" and event.actor_id==0:casts+=1
		ck(casts>0,"merged character automatically casts EX: "+key)
		var one_star=Sim.new()
		ck(one_star.configure([{"id":0,"team":0,"cell":Vector2(0,1),"character_id":key,"star":1},{"id":7,"team":1,"cell":Vector2(0,-1),"character_id":"yuuka","star":1}],{"random_damage":false}).is_empty(),"one-star fixture: "+key)
		one_star.start()
		for unit in one_star.units:unit.max_hp=10000000;unit.hp=10000000
		for tick in range(600):
			for event in one_star.step():ck(event.type!="skill","one-star EX remains locked: "+key)
	print("ACTIVE ROSTER SESSION FAILURES=",failures);quit(1 if failures else 0)
