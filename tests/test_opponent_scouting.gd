extends SceneTree
const Rules=preload("res://core/prototype_match.gd")
const Session=preload("res://core/game_session.gd")
var failures:=0
var assertions:=0
func ck(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: "+message)
func _initialize()->void:
	var game=Session.new();ck(game.new_game(17).ok,"new game")
	ck(game.has_method("opponent_preview"),"session exposes locked opponent scouting")
	ck(game.rules.has_method("get_opponent_preview"),"rules expose a copy-only prepared encounter")
	if not game.has_method("opponent_preview") or not game.rules.has_method("get_opponent_preview"):
		print("OPPONENT SCOUTING FAILURES=",failures);quit(1);return
	var initial:Dictionary=game.rules.snapshot()
	var preview:Dictionary=game.opponent_preview()
	ck(preview.round==1 and not preview.units.is_empty(),"opponent has an army before player buys or deploys")
	ck(preview.name==game.rules.get_player(preview.opponent_id).name,"scouting names the actual rival")
	for actor in preview.units:
		ck(actor.team==1 and actor.cell.y<0 and game.navigation.is_free(actor.cell,0.35),"scouted cell is legal enemy territory")
		ck(actor.star in [1,2] and actor.roster_unit_id!="","scouting includes actual star and roster identity")
	for _i in range(5):
		ck(game.opponent_preview()==preview,"repeated scouting is stable")
		game.preview_roster();game.rules.get_player();game.rules.snapshot()
	ck(game.rules.snapshot()==initial,"harmless UI reads consume no economy, RNG, IDs or AI turns")
	var borrowed:Dictionary=game.opponent_preview();borrowed.units[0].star=99;borrowed.name="mutated"
	ck(game.opponent_preview()==preview,"scouting result is detached")
	ck(not game.command({"type":"start_battle"}).ok,"empty army still rejected")
	ck(game.rules.snapshot()==initial,"failed start keeps locked rival and all state atomic")
	ck(not game.command({"type":"buy_offer","slot":-1}).ok,"bad offer rejected")
	ck(game.rules.snapshot()==initial,"bad purchase cannot reroll the encounter")
	var bought:Dictionary=game.command({"type":"buy_offer","slot":0})
	ck(bought.ok and game.command({"type":"deploy_unit","unit_id":bought.unit_id}).ok,"prepare player army")
	game.command({"type":"refresh_shop"});game.command({"type":"buy_xp"})
	ck(game.place(bought.unit_id,Vector2(0,4)),"player can react with placement")
	ck(game.opponent_preview()==preview,"shopping, XP and placement never alter opponent")
	var prepared:Dictionary=game.rules.snapshot();var restored=Rules.new()
	ck(restored.restore(JSON.parse_string(JSON.stringify(prepared))).ok,"prepared snapshot round-trips through JSON")
	ck(restored.get_opponent_preview()==game.rules.get_opponent_preview(),"restore preserves exact encounter")
	var start:Dictionary=game.command({"type":"start_battle"});var replay:Dictionary=restored.execute({"type":"start_battle"})
	ck(start.ok and replay.ok and start.battle==replay.battle,"restored encounter launches identical battle without reroll")
	ck(start.battle.opponent_id==preview.opponent_id,"battle opponent is scout target")
	for scouted in preview.units:
		var found:=false
		for actor in game.clock.sim.units:
			if actor.id==scouted.id:
				found=true;ck(actor.character_id==scouted.character_id and actor.star==scouted.star and actor.cell==scouted.cell,"battle actor exactly matches preview character, star and cell")
		ck(found,"all scouted actors enter battle")
	var battle_state:Dictionary=game.rules.snapshot()
	ck(battle_state.rng_state==prepared.rng_state,"launch consumes no matchup RNG")
	ck(restored.restore(JSON.parse_string(JSON.stringify(battle_state))).ok,"battle snapshot round-trips")
	while game.phase()=="battle":game.advance(0.25)
	ck(game.phase()=="result","first battle reaches result")
	var result:Dictionary=game.rules.snapshot().last_result
	var ai_outcomes:Array=[]
	for row in result.ai_results:
		var outcome:Dictionary=row.duplicate(true)
		for key in ["left_damage","right_damage","resolution"]:outcome.erase(key)
		ai_outcomes.append(outcome)
	ck(restored.execute({"ai_outcomes":ai_outcomes,"type":"resolve_battle","battle_id":result.battle_id,"winner":result.winner,"player_remaining":result.player_remaining,"opponent_remaining":result.opponent_remaining}).ok,"restored battle accepts the same real outcome")
	ck(restored.snapshot()==game.rules.snapshot(),"restored resolution exactly reproduces next-round schedule, AI armies, income, RNG and IDs")
	var next:Dictionary=game.opponent_preview()
	ck(next.round==2 and next.opponent_id!=preview.opponent_id,"new round locks next living rival once and avoids immediate repeat")
	var next_state:Dictionary=game.rules.snapshot()
	ck(game.command({"type":"next_round"}).ok,"result acknowledgment")
	ck(game.opponent_preview()==next and game.rules.snapshot()==next_state,"acknowledgment does not prepare AI or choose rival again")
	ck(game.command({"type":"restart","seed":17}).ok,"seeded restart")
	ck(game.rules.snapshot()==initial and game.opponent_preview()==preview,"restart reproduces initial locked army and RNG")
	var invalid:Dictionary=game.rules.snapshot();invalid.next_opponent.opponent_units[0].star=99
	ck(not game.rules.restore(invalid).ok and game.rules.snapshot()==initial,"tampered scout army rejected atomically")
	invalid=game.rules.snapshot();invalid.next_opponent.ai_pairs[0][0]=invalid.next_opponent.opponent_id
	ck(not game.rules.restore(invalid).ok and game.rules.snapshot()==initial,"duplicate participant in locked pairing rejected atomically")
	invalid=game.rules.snapshot();invalid.next_opponent.opponent_id="p0"
	ck(not game.rules.restore(invalid).ok and game.rules.snapshot()==initial,"invalid scout identity rejected atomically")
	print("OPPONENT SCOUTING ASSERTIONS=",assertions," FAILURES=",failures);quit(1 if failures else 0)
