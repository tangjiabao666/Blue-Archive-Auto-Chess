extends SceneTree
const Session=preload("res://core/game_session.gd")
var failures:=0
func ck(ok:bool,message:String):
	if not ok:failures+=1;printerr(message)
func _initialize():
	var game=Session.new();game.new_game(17)
	var player=game.rules._player_ref("p0");player.level=4
	var ids:Array=[]
	for i in range(4):
		var id="u%06d"%game.rules._state.next_unit_id
		game.rules._state.next_unit_id+=1;ids.append(id)
		player.units.append({"id":id,"character_id":game.ACTIVE[i],"star":1,"base_enabled":true,"passive_enabled":true,"ex_enabled":false})
		player.deployed.append(id)
		var roster=game.preview_roster();var sum_x:=0.0
		for unit in roster:sum_x+=unit.cell.x
		ck(absf(sum_x)<0.001,"automatic formation centered for %d units"%(i+1))
	ck(game.place(ids[0],Vector2(0,3)),"manual placement accepted")
	player.deployed.erase(ids[3]);player.bench.append(ids[3])
	game.preview_roster()
	ck(game.positions[ids[0]]==Vector2(0,3),"reflow preserves manual position")
	player.bench.erase(ids[3]);player.deployed.append(ids[3])
	var units=game.preview_roster()
	ck(game.positions[ids[0]]==Vector2(0,3),"redeploy preserves manual position")
	for a in units:
		for b in units:
			if a.id!=b.id:ck(a.cell.distance_to(b.cell)>=0.7,"formation does not overlap")
	var army=game.rules._deployed_units(player)
	for count in range(1,5):
		var roster=game._battle_roster({"player_units":[],"opponent_units":army.slice(0,count)});var sum_x:=0.0
		for unit in roster:sum_x+=unit.cell.x;ck(unit.id>=7,"actor stride retained")
		ck(absf(sum_x)<0.001,"enemy centered for %d units"%count)
	player.deployed.erase(ids[0]);player.bench.append(ids[0])
	ck(game.place(ids[1],Vector2(0,3)),"active unit may use benched unit former position")
	player.bench.erase(ids[0]);player.deployed.append(ids[0])
	game.preview_roster()
	ck(game.positions[ids[1]]==Vector2(0,3),"existing manually placed unit wins redeploy conflict")
	ck(game.positions[ids[0]].distance_to(game.positions[ids[1]])>=0.7,"returning unit gets free fallback")
	game.new_game(17);ck(game.positions.is_empty(),"restart clears placements")
	print("FOUR FORMATION FAILURES=",failures);quit(1 if failures else 0)
