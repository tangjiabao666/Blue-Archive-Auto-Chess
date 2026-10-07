extends SceneTree
var fails:=0
func ck(b:bool,s:String)->void:
	if not b:fails+=1;printerr("FAIL: "+s)
func _initialize():
	var path="res://core/game_session.gd"
	ck(ResourceLoader.exists(path),"integrated match session exists")
	if not ResourceLoader.exists(path):quit(1);return
	var game=load(path).new();ck(game.new_game(17).ok,"new session initializes")
	ck(game.catalog.size()==game.ACTIVE.size(),"catalog contains every active character")
	var keys=[]
	for entry in game.catalog:keys.append(entry.id)
	ck("serika" in keys and "serina" not in keys,"Serika replaces support Serina in active shop")
	var bought=game.command({"type":"buy_offer","slot":0})
	ck(bought.ok,"buy original character")
	ck(game.command({"type":"deploy_unit","unit_id":bought.unit_id}).ok,"deploy bought unit")
	ck(game.preview_roster().size()==1,"preparation shows own deployed unit")
	ck(not game.place(bought.unit_id,Vector2(0,-1)),"reject opponent placement")
	ck(not game.place(bought.unit_id,Vector2(-2,0.5)),"reject obstacle placement")
	ck(game.place(bought.unit_id,Vector2(0,4)),"free formation position accepted")
	ck(game.command({"type":"start_battle"}).ok,"start actual source-character battle")
	ck(game.clock.sim.units[0].cell==Vector2(0,4),"starting battle preserves chosen free position")
	ck(game.phase()=="battle","battle phase active")
	var tick=game.clock.sim.tick;game.paused=true;game.advance(0.2);ck(game.clock.sim.tick==tick,"pause respects simulation")
	game.paused=false
	for i in range(160):
		game.advance(1.0)
		if game.phase()!="battle":break
	ck(game.clock.sim.phase=="finished","visible battle ends within simulated duration")
	# Synthetic frame delta is not elapsed CPU time for cooperative AI jobs.
	# Every positive scheduler slice advances at least one pending job tick.
	var settlement_bound:int=int(game.ai_battle_status().scheduled)*int(game.clock.sim.options.max_ticks)+1
	for _slice in range(settlement_bound):
		if game.phase()!="battle":break
		game.advance(0.05)
	ck(game.phase() in ["result","finished"],"combat resolves into match result")
	ck(not game.command({"type":"start_battle"}).ok,"cannot skip result acknowledgement")
	if game.phase()=="result":ck(game.command({"type":"next_round"}).ok and game.phase()=="preparation","continue next shopping round")
	print("GAME SESSION FAILURES=",fails);quit(1 if fails else 0)
