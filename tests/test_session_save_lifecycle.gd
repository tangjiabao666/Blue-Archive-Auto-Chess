extends SceneTree
const Session=preload("res://core/game_session.gd")
# Isolate navigation lifecycle from unrelated background duel execution. The
# full test_session_save.gd separately exercises real cooperative offscreen jobs.
class LocalSession extends Session:
	func _prepare_ai_jobs(_battle:Dictionary)->Dictionary:
		return {"ok":true,"jobs":[]}
var failures:=0
func ck(ok:bool,message:String)->void:
	if not ok:failures+=1;printerr("FAIL: "+message)
func prime(game)->Vector2:
	return game.navigation.next_crowd_waypoint(Vector2(-3,4),Vector2(3,4),0.35,[Vector2(0,4)],0,11)
func query(game)->Vector2:
	return game.navigation.next_crowd_waypoint(Vector2(-3,4),Vector2(3,4),0.35,[Vector2(1,4)],0,12)
func clean_route()->Vector2:
	var nav=Session.Navigation.new();nav.configure(Session.HALF_SIZE,Session.OBSTACLES)
	return nav.next_crowd_waypoint(Vector2(-3,4),Vector2(3,4),0.35,[Vector2(1,4)],0,12)
func ready():
	var game=LocalSession.new();ck(game.new_game(17).ok,"fixture initializes")
	var bought:Dictionary=game.command({"type":"buy_offer","slot":0})
	ck(bought.ok and game.command({"type":"deploy_unit","unit_id":bought.unit_id}).ok,"fixture prepares a legal army")
	return game
func _initialize()->void:
	var game=ready();var checkpoint:Dictionary=game.export_save().data
	var detour:Vector2=prime(game)
	ck(detour!=Vector2(3,4) and detour!=Vector2(-3,4),"fixture produces an actual cached detour")
	ck(game.command({"type":"start_battle"}).ok,"battle starts")
	ck(query(game)==clean_route(),"new battle discards prior-round cached detours")
	ck(game.restore_save(checkpoint).ok,"load ends active battle")
	prime(game)
	ck(game.command({"type":"restart"}).ok and query(game)==clean_route(),"restart discards old navigation routes")
	prime(game)
	ck(game.new_game(17).ok and query(game)==clean_route(),"new game discards old navigation routes")
	game=ready()
	var invalid:Dictionary=game.rules.snapshot()
	invalid.catalog.append({"id":"missing_source","name":"Missing source","cost":1,"ex_cooldown":8.0})
	invalid.players[0].units[0].character_id="missing_source"
	ck(game.rules.restore(invalid).ok,"generic rules accept the source-missing fixture")
	var prior_rules:Dictionary=game.rules.snapshot();var prior_navigation=game.navigation
	prime(game)
	ck(not game.command({"type":"start_battle"}).ok,"missing source rejects battle before commit")
	ck(game.rules.snapshot()==prior_rules and game.navigation==prior_navigation and query(game)!=clean_route(),"failed battle start preserves rules and existing navigation state")
	print("SESSION SAVE LIFECYCLE FAILURES=",failures);quit(1 if failures else 0)
