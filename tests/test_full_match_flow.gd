extends SceneTree
var failures:=0
func check(ok:bool,message:String):
	if not ok:failures+=1;printerr(message)
func _initialize():
	for seed_value in [17,20261002]:
		var game=load("res://core/game_session.gd").new();check(game.new_game(seed_value).ok,"new match")
		var rounds:=0;var timeouts:=0;var leaks:=0
		while game.phase()!="finished" and rounds<40:
			# Exercise the same budget/merge/deploy rules with a deterministic AI buyer.
			game.rules._prepare_ai(game.rules._player_ref("p0"))
			var start:Dictionary=game.command({"type":"start_battle"});check(start.ok,"start round")
			if not start.ok:break
			for participant in game.rules.snapshot().players:
				check(participant.level<=6 and participant.deployed.size()<=6,"all participants respect six-unit cap")
			check(game.clock.sim.units.size()<=12,"combat contains at most twelve characters")
			while game.phase()=="battle":
				for event in game.advance(0.05):
					if event.type=="skill":
						for unit in game.clock.sim.units:
							if unit.id==event.actor_id and unit.star==1:leaks+=1
					if event.type=="finished" and event.reason=="timeout":timeouts+=1
			rounds+=1
			if game.phase()=="result":check(game.command({"type":"next_round"}).ok,"next round")
		check(game.phase()=="finished","full match must reach terminal standings")
		check(leaks==0,"one-star EX must stay locked")
		check(timeouts==0,"seeded full matches have no stalled timeout rounds")
		print("FULL MATCH seed=",seed_value," rounds=",rounds," timeouts=",timeouts," one_star_ex=",leaks," placement=",game.rules.snapshot().placement)
	print("FULL MATCH FAILURES=",failures);quit(1 if failures else 0)
