extends SceneTree
const Rules=preload("res://core/prototype_match.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func fresh(config:Dictionary={}):
	var rules=Rules.new();ck(rules.new_match(123,[],config).ok,"fixture initializes");return rules
func offer(id:String="aru",cost:int=3)->Dictionary:
	return {"character_id":id,"cost":cost}
func unit(id:String,character:String="aru",star:int=1)->Dictionary:
	return {"id":id,"character_id":character,"star":star,"base_enabled":true,"passive_enabled":true,"ex_enabled":star==2}
func ready(rules)->void:
	var bought:Dictionary=rules.execute({"type":"buy_offer","slot":0})
	ck(bought.ok and rules.execute({"type":"deploy_unit","unit_id":bought.unit_id}).ok,"fixture deploys")
func resolve(rules,winner:String="player")->Dictionary:
	var start:Dictionary=rules.execute({"type":"start_battle"});ck(start.ok,"round starts")
	return rules.execute({"type":"resolve_battle","battle_id":start.battle.id,"winner":winner,"player_remaining":1 if winner=="player" else 0,"opponent_remaining":1 if winner=="opponent" else 0})
func reject(rules,command:Dictionary,error:String,label:String)->void:
	var before:Dictionary=rules.snapshot();var result:Dictionary=rules.execute(command)
	ck(not result.ok and result.error==error,label+" rejects")
	ck(rules.snapshot()==before,label+" preserves all state and RNG")
func install(rules,state:Dictionary)->void:
	ck(rules.restore(state).ok,"controlled valid snapshot restores")
func _initialize()->void:
	var rules=fresh()
	ck(Rules.VERSION==6,"canonical rules version is 6")
	ck(rules.get_player().get("shop_locked")==false,"new local shop starts unlocked")
	var locked:Dictionary=rules.execute({"type":"set_shop_locked","locked":true})
	ck(locked.ok,"strict retention command exists")
	if failures:quit(1);return
	var before:Dictionary=rules.snapshot()
	ck(rules.execute({"type":"set_shop_locked","locked":true}).ok and rules.snapshot()==before,"repeated lock is idempotent and free")
	for value in [null,0,1,"true",[],{}]:
		reject(rules,{"type":"set_shop_locked","locked":value},"invalid_shop_lock","non-Boolean lock "+str(value))
	reject(rules,{"type":"set_shop_locked"},"invalid_shop_lock","missing lock")
	var view:Dictionary=rules.get_player();view.shop_locked=false;view.shop[0].cost=99
	ck(rules.snapshot()==before,"returned lock and shop are detached")
	reject(rules,{"type":"buy_offer","slot":-1},"invalid_slot","failed purchase keeps lock")
	ready(rules)
	var partial:Array=rules.get_player().shop
	ck(partial[0].is_empty() and rules.get_player().shop_locked,"purchase preserves nonempty retention and holes")
	var start:Dictionary=rules.execute({"type":"start_battle"});ck(start.ok,"retained shop starts battle")
	reject(rules,{"type":"set_shop_locked","locked":false},"wrong_phase","combat unlock")
	for key in ["id","opponent_id","player_units","opponent_units","round"]:
		var invalid_battle:Dictionary=rules.snapshot();invalid_battle.battle[key]=true
		var original_battle:Dictionary=rules.snapshot()
		ck(not rules.restore(invalid_battle).ok and rules.snapshot()==original_battle,"malformed battle field rejects atomically: "+key)
	ck(rules.execute({"type":"resolve_battle","battle_id":start.battle.id,"winner":"player","player_remaining":1,"opponent_remaining":0}).ok,"retained round resolves")
	ck(rules.get_player().shop==partial and not rules.get_player().shop_locked,"next round preserves exact offers and holes once")
	ck(resolve(rules).ok,"following round resolves")
	ck(not rules.get_player().shop_locked and not rules.get_player().shop[0].is_empty(),"following unlocked round receives free refresh")
	ck(rules.execute({"type":"set_shop_locked","locked":true}).ok and rules.execute({"type":"set_shop_locked","locked":false}).ok,"explicit release succeeds")
	var state:Dictionary=rules.snapshot();state.players[0].gold=0;install(rules,state)
	ck(rules.execute({"type":"set_shop_locked","locked":true}).ok,"retention costs no gold")
	reject(rules,{"type":"refresh_shop"},"insufficient_gold","failed refresh keeps lock")
	reject(rules,{"type":"buy_offer","slot":0},"insufficient_gold","unaffordable purchase keeps lock")
	state=rules.snapshot();state.players[0].gold=100;install(rules,state)
	before=rules.snapshot();ck(rules.execute({"type":"refresh_shop"}).ok,"paid refresh succeeds")
	ck(not rules.get_player().shop_locked and rules.get_player().gold==before.players[0].gold-2 and rules.snapshot().rng_state!=before.rng_state,"paid refresh clears retention and spends normal gold and RNG")
	# One-star merge preserves the board ID; XP and sales leave offers and lock alone.
	state=rules.snapshot();var p:Dictionary=state.players[0]
	var serial:int=state.next_unit_id;p.units=[unit("u%06d"%serial),unit("u%06d"%(serial+1))]
	p.deployed=[p.units[0].id];p.bench=[p.units[1].id];state.next_unit_id+=2
	p.shop=[offer(),{},offer("serika",1),{},{}];p.shop_locked=true;p.gold=100;p.level=4;p.xp=0
	install(rules,state);var survivor:String=p.deployed[0]
	ck(rules.execute({"type":"buy_xp"}).ok and rules.get_player().shop==p.shop and rules.get_player().shop_locked,"XP leaves exact retained offers")
	var merge:Dictionary=rules.execute({"type":"buy_offer","slot":0})
	ck(merge.ok and merge.unit_id==survivor and merge.merged_ids.size()==2 and rules.get_player().shop_locked,"merge retains remaining shop and deployed identity")
	partial=rules.get_player().shop
	ck(rules.execute({"type":"sell_unit","unit_id":survivor}).ok and rules.get_player().shop==partial and rules.get_player().shop_locked,"sale preserves retained shop")
	ck(rules.execute({"type":"buy_offer","slot":2}).ok and not rules.get_player().shop_locked,"buying last offer clears empty lock")
	reject(rules,{"type":"set_shop_locked","locked":true},"empty_shop","empty shop lock")
	ck(rules.execute({"type":"set_shop_locked","locked":false}).ok,"empty shop can be unlocked")
	state=rules.snapshot();state.players[0].shop_locked=true
	before=rules.snapshot();ck(not rules.restore(state).ok and rules.snapshot()==before,"canonical empty locked snapshot rejects atomically")
	for value in [null,0,"false"]:
		state=rules.snapshot();state.players[0].shop_locked=value
		ck(not rules.restore(state).ok and rules.snapshot()==before,"canonical lock type is strict")
	state=rules.snapshot();state.players[0].shop_locked=true;state.players[0].shop[0]=42
	ck(not rules.restore(state).ok and rules.snapshot()==before,"malformed locked offer rejects without type error or mutation")
	state=rules.snapshot();state.players[0].erase("shop_locked")
	ck(not rules.restore(state).ok,"canonical partial player schema rejects")
	var terminal=fresh({"starting_hp":1});ready(terminal);terminal.execute({"type":"set_shop_locked","locked":true})
	before=terminal.snapshot();ck(resolve(terminal,"opponent").ok,"terminal round resolves")
	ck(terminal.snapshot().phase=="finished" and terminal.get_player().shop==before.players[0].shop and terminal.get_player().shop_locked,"terminal round neither rolls nor consumes retention")
	reject(terminal,{"type":"set_shop_locked","locked":false},"wrong_phase","finished retention")
	ck(terminal.execute({"type":"restart"}).ok and not terminal.get_player().shop_locked,"restart resets local retention")
	_test_ai()
	_test_determinism()
	print("SHOP RETENTION ",checks," checks FAILURES=",failures);quit(1 if failures else 0)
func _test_ai()->void:
	var rules=fresh()
	var npc:Dictionary=rules.get_player("p1")
	npc.units=[unit("u900001"),unit("u900002")];npc.bench=[];npc.deployed=["u900001","u900002"];npc.gold=0
	npc.shop=[{},offer(),{},offer("shiroko",2),{}];npc.shop_locked=false
	var rng:int=rules.snapshot().rng_state
	rules._prepare_ai(npc)
	ck(npc.shop_locked and npc.shop[1]==offer() and rules.snapshot().rng_state==rng,"NPC retains unaffordable third copy without extra RNG")
	var other:Dictionary=npc.duplicate(true);other.shop_locked=false
	var state:Dictionary=rules.snapshot();state.players[0].gold=999;state.players[0].shop=[offer(),offer(),offer(),offer(),offer()];install(rules,state)
	rules._prepare_ai(other);ck(other==npc,"NPC retention depends only on own inventory shop and gold")
	other=npc.duplicate(true);other.units[1].star=2;other.units[1].ex_enabled=true;rules._prepare_ai(other)
	ck(not other.shop_locked,"two-star unit is not a one-star pair")
	other=npc.duplicate(true);other.shop=[offer("shiroko",2),{},{},{},{}];rules._prepare_ai(other)
	ck(not other.shop_locked,"NPC does not retain unrelated unaffordable offer")
	other=npc.duplicate(true);other.gold=3;other.shop=[offer(),{},{},{},{}];rules._prepare_ai(other)
	ck(other.units.size()==1 and other.units[0].star==2 and not other.shop_locked,"NPC buys affordable third copy under existing purchase policy")
	# Surviving NPC consumes its exact retained holes before the next purchase policy.
	var no_income=fresh({"income":0,"interest_cap":0,"round_xp":0});ready(no_income)
	state=no_income.snapshot();var id:String="p1" if state.next_opponent.opponent_id!="p1" else "p2"
	var index:int=int(id.substr(1));var p:Dictionary=state.players[index]
	var serial:int=state.next_unit_id;p.units=[unit("u%06d"%serial),unit("u%06d"%(serial+1))];state.next_unit_id+=2
	p.deployed=[p.units[0].id,p.units[1].id];p.bench=[];p.gold=0;p.shop=[{},offer(),{},{},{}];p.shop_locked=true
	install(no_income,state);ck(resolve(no_income).ok,"NPC retention transition resolves")
	ck(no_income.get_player(id).shop==p.shop and no_income.get_player(id).shop_locked,"NPC retained unaffordable pair may deliberately rearm after one consumption")
func _test_determinism()->void:
	var first=fresh();ready(first);first.execute({"type":"set_shop_locked","locked":true})
	var second=Rules.new();ck(second.restore(first.snapshot()).ok,"locked snapshot restores")
	for round_index in range(3):
		ck(resolve(first).ok and resolve(second).ok and first.snapshot()==second.snapshot(),"identical lock commands and shared RNG continue deterministically")
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/shop_retention_legacy_unlocked_v4.json"))
	var control=Rules.new();control.new_match(42120908,[],{"starting_gold":100,"income":0,"ai_purchase_limit":1});ready(control)
	for index in range(fixture.snapshots.size()):
		var actual:Dictionary=control.snapshot();actual.version=4;actual.config.erase("reinforcement_recruitment")
		for p in actual.players:
			ck(not p.shop_locked,"legacy RNG control never selects retention");p.erase("shop_locked");p.erase("reinforcement")
		ck(control._normalize_json(actual)==control._normalize_json(fixture.snapshots[index]),"all-unlocked shop opponent ID and RNG sequence matches real v4 baseline")
		if index<fixture.snapshots.size()-1:ck(resolve(control).ok,"legacy control round resolves")
