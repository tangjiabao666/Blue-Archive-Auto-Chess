extends SceneTree
const Session=preload("res://core/game_session.gd")
var failures:=0
func ck(ok:bool,message:String)->void:
	if not ok:failures+=1;printerr("FAIL: "+message)
func _initialize()->void:
	var game=Session.new();game.new_game(17)
	var bought:Dictionary=game.command({"type":"buy_offer","slot":0});game.command({"type":"deploy_unit","unit_id":bought.unit_id});game.place(bought.unit_id,Vector2(0,4))
	var state:Dictionary=game.rules.snapshot();var positions:Dictionary=game.positions.duplicate(true)
	ck(not game.new_game(2147483647).ok,"out-of-range new-game seed rejected")
	ck(game.seed==17 and game.rules.snapshot()==state and game.positions==positions,"failed new game is fully atomic including session seed")
	for invalid_seed in [1.5,"17",null,2147483647]:
		var outcome:Dictionary=game.command({"type":"restart","seed":invalid_seed})
		ck(not outcome.ok,"restart rejects invalid seed "+str(invalid_seed))
		ck(game.seed==17 and game.rules.snapshot()==state and game.positions==positions,"invalid restart preserves session and rules")
	print("SESSION ATOMIC RESTART FAILURES=",failures);quit(1 if failures else 0)
