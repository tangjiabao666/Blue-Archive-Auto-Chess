extends SceneTree
## Deliberately separate from ordinary test_* suites. Predeclared policies: docs/funded-reroll-study.md.
const Session=preload("res://core/game_session.gd")
const Rules=preload("res://core/prototype_match.gd")
const OUT="res://evidence/funded-reroll-study/"
const SEEDS=[73,101,257]
const POLICIES=["rush_population","funded_reroll"]
const MAX_ROUNDS=40
const BATTLE_WALL_MS=60000
const MATCH_WALL_MS=300000
const PURCHASE_LIMIT=8
const REFRESH_LIMIT=2
var failures:Array=[]
var round_log:FileAccess
var matches:Array=[]
var source_hashes:Dictionary={}
var study_started:int

func _initialize()->void:
	study_started=Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(OUT)
	round_log=FileAccess.open(OUT+"rounds.jsonl",FileAccess.WRITE)
	if round_log==null:printerr("Cannot create evidence log");quit(2);return
	for path in ["core/game_session.gd","core/prototype_match.gd","core/shop_odds.gd","core/character_sim.gd","core/character_clock.gd","core/offscreen_duel.gd","core/obstacle_navigation.gd","core/combat_arena_hooks.gd","core/opponent_formations.gd","data/character_skills.json","data/native-skill-contacts.json","data/character-presentations.json","project.godot","evidence/funded-reroll-study/frozen-source-identity.json","tests/probe_shop_strategy_study.gd","tests/probe_funded_reroll_study.gd","evidence/funded-reroll-study/predeclared-method.md"]:
		source_hashes[path]=FileAccess.get_sha256("res://"+path)
	_write_json("manifest.json",{"started_utc":Time.get_datetime_string_from_system(true),"source_identity":JSON.parse_string(FileAccess.get_file_as_string(OUT+"frozen-source-identity.json")),"godot":Engine.get_version_info(),"rules_version":Rules.VERSION,"seeds":SEEDS,"modes":[1],"policies":POLICIES,"planned_matches":6,"bounds":{"battle_wall_ms":BATTLE_WALL_MS,"match_wall_ms":MATCH_WALL_MS,"rounds":MAX_ROUNDS,"purchase_limit":PURCHASE_LIMIT,"refresh_limit":REFRESH_LIMIT},"source_sha256":source_hashes})
	for mode in [1]:
		for policy in POLICIES:
			for seed_value in SEEDS:
				var result:Dictionary=_play_match(mode,policy,seed_value)
				matches.append(result)
				_write_json("match-%s-mode%d-seed%d.json"%[policy,mode,seed_value],result)
				_write_results(false)
				print("STUDY_MATCH ",JSON.stringify(_summary(result)))
	for path in source_hashes:
		if FileAccess.get_sha256("res://"+path)!=source_hashes[path]:failures.append("Source changed during study: "+path)
	_write_results(true)
	print("FUNDED_REROLL_STUDY matches=",matches.size()," failures=",failures.size()," wall_seconds=",(Time.get_ticks_msec()-study_started)/1000.0)
	quit(0 if failures.is_empty() else 1)

func _write_json(filename:String,value:Variant)->void:
	var file=FileAccess.open(OUT+filename,FileAccess.WRITE)
	if file==null:
		failures.append("Unable to write "+filename);return
	file.store_string(JSON.stringify(value,"\t"));file.close()

func _write_results(completed:bool)->void:
	var summaries:Array=[]
	for item in matches:summaries.append(_summary(item))
	_write_json("results.json",{"completed":completed,"planned_matches":6,"actual_matches":matches.size(),"failures":failures,"wall_seconds":(Time.get_ticks_msec()-study_started)/1000.0,"matches":summaries,"source_sha256":source_hashes})

func _summary(item:Dictionary)->Dictionary:
	var value:Dictionary=item.duplicate(true)
	for key in ["rounds","shops","actions","decisions","initial_state","final_state"]:value.erase(key)
	value["round_count"]=item.rounds.size()
	return value

func _play_match(mode:int,policy:String,seed_value:int)->Dictionary:
	var started:int=Time.get_ticks_msec()
	var run={"mode":mode,"policy":policy,"seed":seed_value,"terminal":false,"error":"","first_two_star_round":null,"first_deployed_two_star_round":null,"first_ex_round":null,"first_four_cost_offer_round":null,"first_four_cost_deployment_round":null,"level5_round":null,"level6_round":null,"empty_slot_rounds":0,"empty_slot_total":0,"visible_timeouts":0,"npc_timeouts":0,"npc_duels":0,"visible_wins":0,"visible_losses":0,"visible_draws":0,"gold_spent_xp":0,"gold_spent_refresh":0,"gold_spent_units":0,"funded_target":"","target_selected_round":null,"target_two_star_round":null,"target_events":[],"rounds":[],"shops":[],"actions":[],"decisions":[]}
	var game=Session.new()
	# Initialize from the real session catalog with only the treatment mode changed.
	var init:Dictionary=game.rules.new_match(seed_value,game.catalog,{"level_shop_odds":mode})
	game.seed=seed_value;game._reset_session()
	if not init.ok:_fail(run,"new_match: "+str(init));return run
	run["initial_state"]=game.rules.snapshot()
	while game.phase()!="finished" and run.rounds.size()<MAX_ROUNDS:
		if Time.get_ticks_msec()-started>MATCH_WALL_MS:_fail(run,"match wall-clock limit");break
		var state:Dictionary=game.rules.snapshot()
		var before_preparation:Dictionary=state
		var round_number:int=int(state.round)
		var player:Dictionary=game.rules.get_player()
		_mark_milestones(run,player,round_number)
		_observe_shop(run,player,round_number,"free")
		var prep:Dictionary=_prepare_human(game,policy,run,round_number)
		if not prep.ok:_fail(run,prep.error);break
		player=game.rules.get_player();state=game.rules.snapshot()
		var restored=Rules.new()
		if not restored.restore(state).ok:_fail(run,"invalid post-preparation rules snapshot");break
		for participant in state.players:
			if participant.deployed.size()>participant.level or participant.level>6 or participant.bench.size()>9:
				_fail(run,"illegal population or bench");break
		if not run.error.is_empty():break
		var row={"mode":mode,"policy":policy,"seed":seed_value,"round":round_number,"hp_before":player.hp,"level":player.level,"xp":player.xp,"gold":player.gold,"deployed":_roster(game.rules,player),"bench":player.bench,"empty_slots":int(player.level)-player.deployed.size(),"purchases":prep.purchases,"paid_refreshes":prep.refreshes,"paid_xp_buys":prep.xp_buys,"player_after_preparation":player,"state_before_preparation":before_preparation,"state_after_preparation":state}
		run.empty_slot_total+=row.empty_slots
		if row.empty_slots>0:run.empty_slot_rounds+=1
		var battle_started:int=Time.get_ticks_msec()
		var launch:Dictionary=game.command({"type":"start_battle"})
		if not launch.ok:_fail(run,"start_battle: "+str(launch));break
		var battle:Dictionary=launch.battle
		row["battle"]=battle
		row["opponent_id"]=battle.opponent_id;row["opponent_units"]=battle.opponent_units
		var battle_error:String=_play_battle(game,run,round_number,battle_started,started)
		if not battle_error.is_empty():
			row["error"]=battle_error;run.rounds.append(row);_log_round(row);_fail(run,battle_error);break
		state=game.rules.snapshot();var result:Dictionary=state.last_result
		var feedback:Dictionary=game.battle_feedback()
		if not feedback.completed:_fail(run,"missing completed visible feedback");break
		if result.ai_results.size()!=battle.ai_pairs.size():_fail(run,"NPC result count mismatch");break
		for duel in result.ai_results:
			if duel.resolution!="simulation":_fail(run,"non-simulated NPC outcome")
			run.npc_duels+=1
			if duel.finish_reason=="timeout":run.npc_timeouts+=1
			if int(duel.duration_ticks)>int(game.clock.sim.options.max_ticks):_fail(run,"NPC exceeded simulator tick cap")
		if not run.error.is_empty():break
		if feedback.finish_reason=="timeout":run.visible_timeouts+=1
		if result.winner=="player":run.visible_wins+=1
		elif result.winner=="opponent":run.visible_losses+=1
		else:run.visible_draws+=1
		row["hp_after"]=game.rules.get_player().hp
		row["visible_ticks"]=game.clock.sim.tick;row["visible_finish_reason"]=feedback.finish_reason
		row["simulator_options"]=game.clock.sim.options.duplicate(true)
		row["visible_final_units"]=[]
		for unit in game.clock.sim.units:
			row.visible_final_units.append({"id":unit.id,"team":unit.team,"character_id":unit.character_id,"star":unit.star,"hp":unit.hp})
		row["result"]=result;row["feedback"]=feedback;row["state_after_settlement"]=state
		row["wall_seconds"]=(Time.get_ticks_msec()-battle_started)/1000.0
		run.rounds.append(row);_log_round(row)
		if game.phase()=="result":
			var next:Dictionary=game.command({"type":"next_round"})
			if not next.ok:_fail(run,"next_round: "+str(next));break
	if game.phase()!="finished" and run.error.is_empty():_fail(run,"round limit before terminal standings")
	game._cancel_ai_jobs()
	var final:Dictionary=game.rules.snapshot()
	run.terminal=game.phase()=="finished"
	run["final_placement"]=final.placement if run.terminal else null
	run["final_hp"]=game.rules.get_player().hp
	run["final_state"]=final
	run["wall_seconds"]=(Time.get_ticks_msec()-started)/1000.0
	return run

func _play_battle(game,run:Dictionary,round_number:int,battle_started:int,match_started:int)->String:
	var sim=game.clock.sim
	var iterations:=0
	# Advance the same authoritative clock, but defer the blocking session join until jobs are done.
	while sim.phase=="running":
		if Time.get_ticks_msec()-battle_started>BATTLE_WALL_MS:return "visible battle wall-clock limit"
		if Time.get_ticks_msec()-match_started>MATCH_WALL_MS:return "match wall-clock limit in battle"
		if iterations>int(sim.options.max_ticks):return "visible battle exceeded tick cap"
		var events:Array=game.clock.advance(0.05)
		game._record_feedback(events)
		for event in events:
			if event.type=="skill":
				for unit in sim.units:
					if unit.id==event.actor_id and unit.team==0:
						if unit.star!=2:return "one-star player cast EX"
						if run.first_ex_round==null:run.first_ex_round=round_number
		iterations+=1
	while game.ai_battle_status().pending>0:
		if Time.get_ticks_msec()-battle_started>BATTLE_WALL_MS:return "NPC battle wall-clock limit"
		if Time.get_ticks_msec()-match_started>MATCH_WALL_MS:return "match wall-clock limit awaiting NPC"
		OS.delay_msec(1)
	# Visible and all offscreen fights are finished; settle through the unmodified session.
	game.advance(0.0)
	if game.phase() not in ["result","finished"]:return "session failed settlement: "+game.last_error
	return ""

func _prepare_prior(game,policy:String,run:Dictionary,round_number:int)->Dictionary:
	var purchases:=0;var refreshes:=0;var xp_buys:=0
	game.rules._auto_deploy(game.rules._player_ref("p0"));game._sync_positions()
	# Common bootstrap avoids spending starting money on XP with no legal army.
	while game.rules.get_player().deployed.size()<3 and purchases<PURCHASE_LIMIT:
		var player:Dictionary=game.rules.get_player()
		var choice:Dictionary=_best_offer(player)
		if choice.is_empty():break
		var error:String=_buy(game,int(choice.slot),run,round_number)
		if not error.is_empty():return {"ok":false,"error":error}
		purchases+=1
	if policy=="rush_population":
		while game.rules.get_player().level<6 and game.rules.get_player().gold>=6:
			var result:Dictionary=game.command({"type":"buy_xp"})
			if not result.ok:return {"ok":false,"error":"buy_xp: "+str(result)}
			xp_buys+=1;run.gold_spent_xp+=4
			run.actions.append({"round":round_number,"type":"buy_xp","level":game.rules.get_player().level,"gold_after":game.rules.get_player().gold})
			_mark_milestones(run,game.rules.get_player(),round_number)
	while purchases<PURCHASE_LIMIT:
		var player:Dictionary=game.rules.get_player()
		var choice:Dictionary=_best_offer(player)
		var chase:bool=player.deployed.size()==player.level and _has_low_pair(player) and (choice.is_empty() or not choice.low_match)
		var fill:bool=choice.is_empty() and player.deployed.size()<player.level
		var reserve:int=2 if chase else 1
		if (chase or fill) and refreshes<REFRESH_LIMIT and player.gold>=2+reserve:
			var result:Dictionary=game.command({"type":"refresh_shop"})
			if not result.ok:return {"ok":false,"error":"refresh_shop: "+str(result)}
			refreshes+=1;run.gold_spent_refresh+=2
			run.actions.append({"round":round_number,"type":"refresh_shop","reason":"low_cost_pair" if chase else "empty_slot","gold_after":game.rules.get_player().gold})
			_observe_shop(run,game.rules.get_player(),round_number,"paid");continue
		if choice.is_empty():break
		var error:String=_buy(game,int(choice.slot),run,round_number)
		if not error.is_empty():return {"ok":false,"error":error}
		purchases+=1
	game.rules._auto_deploy(game.rules._player_ref("p0"));game._sync_positions()
	_mark_milestones(run,game.rules.get_player(),round_number)
	return {"ok":true,"purchases":purchases,"refreshes":refreshes,"xp_buys":xp_buys}

func _copies(player:Dictionary,character:String)->int:
	var result:=0
	for unit in player.units:
		if unit.character_id==character and unit.star==1:result+=1
	return result

func _best_offer(player:Dictionary)->Dictionary:
	var weakest_one_star:=999
	for unit in player.units:
		if unit.id in player.deployed and unit.star==1:weakest_one_star=mini(weakest_one_star,Session.COSTS[unit.character_id])
	var best:Dictionary={};var best_score:=-1
	for slot in range(player.shop.size()):
		var offer:Dictionary=player.shop[slot]
		if offer.is_empty() or offer.cost>player.gold:continue
		var copies:int=_copies(player,offer.character_id)
		if player.bench.size()>=9 and copies<2:continue
		var category:=0
		if copies>=2:category=6 if offer.cost<=2 else 5
		elif copies==1:category=4 if offer.cost<=2 else 3
		elif player.deployed.size()<player.level:category=2
		elif offer.cost>weakest_one_star:category=1
		else:continue
		var score:int=category*100+int(offer.cost)*3
		if score>best_score:
			best_score=score;best={"slot":slot,"low_match":copies>0 and offer.cost<=2}
	return best

func _has_low_pair(player:Dictionary)->bool:
	for character in Session.COSTS:
		if Session.COSTS[character]<=2 and _copies(player,character)>=2:return true
	return false

func _buy(game,slot:int,run:Dictionary,round_number:int)->String:
	var before:Dictionary=game.rules.get_player()
	var offer:Dictionary=before.shop[slot]
	var result:Dictionary=game.command({"type":"buy_offer","slot":slot})
	if not result.ok:return "buy_offer: "+str(result)
	game.rules._auto_deploy(game.rules._player_ref("p0"));game._sync_positions()
	run.gold_spent_units+=int(offer.cost)
	run.actions.append({"round":round_number,"type":"buy_offer","slot":slot,"offer":offer,"merged_ids":result.merged_ids,"gold_after":game.rules.get_player().gold,"player_before":before,"player_after":game.rules.get_player()})
	_mark_milestones(run,game.rules.get_player(),round_number)
	return ""

func _mark_milestones(run:Dictionary,player:Dictionary,round_number:int)->void:
	if player.level>=5 and run.level5_round==null:run.level5_round=round_number
	if player.level>=6 and run.level6_round==null:run.level6_round=round_number
	for unit in player.units:
		if unit.star==2 and run.first_two_star_round==null:run.first_two_star_round=round_number
		if unit.id in player.deployed:
			if unit.star==2 and run.first_deployed_two_star_round==null:run.first_deployed_two_star_round=round_number
			if Session.COSTS[unit.character_id]==4 and run.first_four_cost_deployment_round==null:run.first_four_cost_deployment_round=round_number

func _observe_shop(run:Dictionary,player:Dictionary,round_number:int,source:String)->void:
	run.shops.append({"round":round_number,"source":source,"level":player.level,"offers":player.shop.duplicate(true),"gold":player.gold,"units":player.units})
	for offer in player.shop:
		if not offer.is_empty() and offer.cost==4 and run.first_four_cost_offer_round==null:run.first_four_cost_offer_round=round_number

func _roster(rules,player:Dictionary)->Array:
	return rules._deployed_units(player)

func _log_round(row:Dictionary)->void:
	round_log.store_line(JSON.stringify(row));round_log.flush()

func _fail(run:Dictionary,error:String)->void:
	run.error=error
	var context:String="mode%d %s seed%d: %s"%[run.mode,run.policy,run.seed,error]
	failures.append(context);printerr("STUDY_FAILURE ",context)


func _prepare_human(game,policy:String,run:Dictionary,round_number:int)->Dictionary:
	if policy=="rush_population":return _prepare_prior(game,policy,run,round_number)
	return _prepare_funded(game,run,round_number)

func _prepare_funded(game,run:Dictionary,round_number:int)->Dictionary:
	var purchases:=0;var refreshes:=0
	game.rules._auto_deploy(game.rules._player_ref("p0"));game._sync_positions()
	while purchases<PURCHASE_LIMIT:
		var player:Dictionary=game.rules.get_player()
		_update_target(run,player,round_number)
		var decision:Dictionary=_funded_decision(player,run,refreshes)
		run.decisions.append({"round":round_number,"purchases_before":purchases,"refreshes_before":refreshes,"player_before":player,"target":run.funded_target,"target_complete":run.target_two_star_round!=null,"decision":decision})
		if decision.kind=="stop":break
		if decision.kind=="refresh":
			var result:Dictionary=game.command({"type":"refresh_shop"})
			if not result.ok:return {"ok":false,"error":"funded refresh_shop: "+str(result)}
			refreshes+=1;run.gold_spent_refresh+=2
			run.actions.append({"round":round_number,"type":"refresh_shop","reason":decision.reason,"target":run.funded_target,"target_copies":_copies(player,run.funded_target),"gold_after":game.rules.get_player().gold,"player_before":player,"player_after":game.rules.get_player()})
			_observe_shop(run,game.rules.get_player(),round_number,"paid")
			continue
		var error:String=_buy(game,int(decision.slot),run,round_number)
		if not error.is_empty():return {"ok":false,"error":error}
		run.actions[-1]["reason"]=decision.reason
		run.actions[-1]["target"]=run.funded_target
		purchases+=1
	game.rules._auto_deploy(game.rules._player_ref("p0"));game._sync_positions()
	_update_target(run,game.rules.get_player(),round_number)
	_mark_milestones(run,game.rules.get_player(),round_number)
	return {"ok":true,"purchases":purchases,"refreshes":refreshes,"xp_buys":0}

func _update_target(run:Dictionary,player:Dictionary,round_number:int)->void:
	if not run.funded_target.is_empty():
		if run.target_two_star_round==null:
			for unit in player.units:
				if unit.character_id==run.funded_target and unit.star==2:
					run.target_two_star_round=round_number
					run.target_events.append({"type":"completed","round":round_number,"target":run.funded_target,"player":player})
		return
	if player.level>4:return
	var best_copies:=0
	for character in Session.ACTIVE:
		var count:int=_copies(player,character)
		if Session.COSTS[character]==2 and count>best_copies:
			best_copies=count;run.funded_target=character
	if not run.funded_target.is_empty():
		run.target_selected_round=round_number
		run.target_events.append({"type":"selected","round":round_number,"target":run.funded_target,"player":player})

func _funded_decision(player:Dictionary,run:Dictionary,refreshes:int)->Dictionary:
	# After one completed target or passive level 5, use the exact shared buyer,
	# without XP or refreshes. This phase never selects a new target.
	if player.level>4 or run.target_two_star_round!=null:
		var common:Dictionary=_best_offer(player)
		return {"kind":"stop","reason":"shared_buyer_exhausted"} if common.is_empty() else {"kind":"buy","slot":common.slot,"reason":"shared_non_xp_buyer"}
	var target:String=run.funded_target
	# Target copies take priority even if they merge and reduce deployed bodies.
	for slot in range(player.shop.size()):
		var offer:Dictionary=player.shop[slot]
		if _eligible(player,offer) and offer.character_id==target:
			return {"kind":"buy","slot":slot,"reason":"target_offer"}
	if player.deployed.size()<player.level:
		var cheapest_slot:=-1;var cheapest_cost:=999
		for slot in range(player.shop.size()):
			var offer:Dictionary=player.shop[slot]
			if _eligible(player,offer) and offer.cost<cheapest_cost:
				cheapest_slot=slot;cheapest_cost=offer.cost
		return {"kind":"stop","reason":"cannot_fill_affordably"} if cheapest_slot<0 else {"kind":"buy","slot":cheapest_slot,"reason":"cheapest_empty_slot"}
	var copies:int=_copies(player,target)
	var chase:bool=not target.is_empty() and copies in [1,2]
	if chase and refreshes<REFRESH_LIMIT and player.gold>=4 and (player.bench.size()<9 or copies>=2):
		return {"kind":"refresh","reason":"funded_target_chase"}
	# The roll-plus-target reserve remains protected even at the per-round cap.
	# Any optional purchase must leave four gold; filling above is higher priority.
	var budget_player:Dictionary=player.duplicate(true)
	if chase:budget_player.gold=maxi(0,int(player.gold)-4)
	var choice:Dictionary=_best_offer(budget_player)
	return {"kind":"stop","reason":"reserved_or_no_eligible_offer"} if choice.is_empty() else {"kind":"buy","slot":choice.slot,"reason":"discretionary_surplus"}

func _eligible(player:Dictionary,offer:Dictionary)->bool:
	return not offer.is_empty() and offer.cost<=player.gold and (player.bench.size()<9 or _copies(player,offer.character_id)>=2)
