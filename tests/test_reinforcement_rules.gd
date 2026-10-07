extends SceneTree
const Rules=preload("res://core/prototype_match.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func roster()->Array:
	var result:Array=Rules.DEFAULT_CATALOG.duplicate(true)
	result.append({"id":"tier3_b","name":"B","cost":3})
	result.append({"id":"tier3_c","name":"C","cost":3})
	return result
func fresh(config:Dictionary={}):
	var options:Dictionary={"reinforcement_recruitment":1,"starting_hp":1000,"starting_gold":100}
	options.merge(config,true)
	var rules=Rules.new();ck(rules.new_match(123,roster(),options).ok,"enabled match initializes")
	return rules
func unit(id:String,character:String,star:int=1)->Dictionary:
	return {"id":id,"character_id":character,"star":star,"base_enabled":true,"passive_enabled":true,"ex_enabled":star==2}
func ready(rules)->void:
	var bought:Dictionary=rules.execute({"type":"buy_offer","slot":0})
	ck(bought.ok and rules.execute({"type":"deploy_unit","unit_id":bought.unit_id}).ok,"fixture deploys")
func advance(rules)->bool:
	var start:Dictionary=rules.execute({"type":"start_battle"})
	ck(start.ok,"round starts")
	if not start.ok:return false
	var result:Dictionary=rules.execute({"type":"resolve_battle","battle_id":start.battle.id,"winner":"player","player_remaining":1,"opponent_remaining":0})
	ck(result.ok,"round resolves")
	return result.ok
func reach(rules,target:int)->void:
	while rules.snapshot().round<target:
		var event:Dictionary=rules.get_reinforcement()
		if event.get("status")=="pending":ck(rules.execute({"type":"skip_reinforcement","round":event.round}).ok,"previous event explicitly skipped")
		if not advance(rules):return
func reject(rules,command:Dictionary,error:String,label:String)->void:
	var before:Dictionary=rules.snapshot();var result:Dictionary=rules.execute(command)
	ck(not result.ok and result.error==error,label+" rejects")
	ck(rules.snapshot()==before,label+" preserves state RNG IDs and offers")
func reject_snapshot(rules,state:Dictionary,label:String)->void:
	var before:Dictionary=rules.snapshot();var original:Dictionary=state.duplicate(true)
	ck(not rules.restore(state).ok,label+" rejects snapshot")
	ck(rules.snapshot()==before and state==original,label+" preserves live and caller state")
func _initialize()->void:
	ck(Rules.VERSION==6,"Rules6 declares reinforcement schema")
	var rules=fresh()
	if failures:quit(1);return
	ready(rules)
	ck(rules.get_reinforcement().is_empty() and rules.get_reinforcement("unknown").is_empty(),"no event before round3 or for unknown player")
	var second=Rules.new();ck(second.restore(rules.snapshot()).ok,"enabled initial snapshot restores")
	reach(rules,3);reach(second,3)
	ck(rules.snapshot()==second.snapshot(),"same continuation generates identical NPCs RNG and offers")
	var event:Dictionary=rules.get_reinforcement()
	ck(event.keys().size()==5 and event.round==3 and event.cost==2 and event.status=="pending" and event.selected_slot==-1,"round3 exact pending record")
	ck(event.offers.size()==3 and event.offers[0]!=event.offers[1] and event.offers[0]!=event.offers[2] and event.offers[1]!=event.offers[2],"three distinct offers")
	for id in event.offers:ck(rules._character(id).cost==2,"round3 tier2 offers")
	var before:Dictionary=rules.snapshot()
	event.offers[0]="mutated";event.status="claimed"
	ck(rules.snapshot()==before,"get_reinforcement returns detached deep copy")
	for repeat in range(3):
		rules.get_reinforcement();rules.get_opponent_preview()
		ck(second.restore(rules.snapshot()).ok and second.snapshot()==before,"repeated reads and reload do not reroll")
	rules._generate_reinforcements()
	ck(rules.snapshot()==before,"event generation is idempotent within same round")
	reject(rules,{"type":"start_battle"},"reinforcement_pending","unresolved event gates combat")
	for malformed in [{"type":"claim_reinforcement","round":3}, {"type":"claim_reinforcement","round":3,"slot":0,"player_id":"p1"}, {"type":"skip_reinforcement","round":3,"slot":0}]:
		reject(rules,malformed,"invalid_command","exact command keys")
	for value in [true,false,null,"3",[],{},3.5]:
		reject(rules,{"type":"claim_reinforcement","round":value,"slot":0},"invalid_reinforcement_round","strict round token")
	for value in [true,false,null,"0",[],{},0.5,-1,3]:
		reject(rules,{"type":"claim_reinforcement","round":3,"slot":value},"invalid_slot","strict slot")
	reject(rules,{"type":"claim_reinforcement","round":2,"slot":0},"stale_reinforcement","stale round")
	_test_claim_and_merge(rules)
	_test_npc(rules)
	_test_event_round_preview()
	_test_snapshot(rules)
	_test_config()
	print("REINFORCEMENT RULES ",checks," checks FAILURES=",failures);quit(1 if failures else 0)
func _test_claim_and_merge(rules)->void:
	var state:Dictionary=rules.snapshot();var p:Dictionary=state.players[0]
	p.gold=0;p.shop_locked=true
	ck(rules.restore(state).ok,"zero-gold retained-shop fixture restores")
	var before:Dictionary=rules.snapshot();var id:String=p.reinforcement.offers[0]
	var result:Dictionary=rules.execute({"type":"claim_reinforcement","round":3,"slot":0})
	ck(result.ok and result.unit_id==result.purchased_unit_id and result.merged_ids.is_empty(),"claim creates ordinary one-star copy")
	var acquired:Dictionary=rules._find_unit(rules.get_player(),result.unit_id)
	ck(acquired.character_id==id and acquired.star==1 and acquired.base_enabled and acquired.passive_enabled and not acquired.ex_enabled,"claim preserves normal one-star flags")
	ck(rules.get_player().gold==0 and rules.get_player().shop==before.players[0].shop and rules.get_player().shop_locked and rules.snapshot().rng_state==before.rng_state,"claim is free and preserves shop retention RNG")
	ck(rules.get_reinforcement().status=="claimed" and rules.get_reinforcement().selected_slot==0,"claim stores resolution")
	reject(rules,{"type":"claim_reinforcement","round":3,"slot":1},"stale_reinforcement","repeated claim")
	reject(rules,{"type":"skip_reinforcement","round":3},"stale_reinforcement","skip after claim")
	ck(rules.execute({"type":"sell_unit","unit_id":result.unit_id}).gold_received==2,"reinforcement copy has ordinary resale value")
	ck(rules.restore(before).ok,"pending fixture restores")
	state=rules.snapshot();p=state.players[0];p.units=[];p.bench=[];p.deployed=[]
	var serial:int=state.next_unit_id
	p.units.append(unit("u%06d"%serial,id));p.deployed.append(p.units[0].id);serial+=1
	p.units.append(unit("u%06d"%serial,id));p.bench.append(p.units[1].id);serial+=1
	for index in range(state.config.bench_capacity-1):
		var filler:Dictionary=unit("u%06d"%serial,"serika",2);serial+=1;p.units.append(filler);p.bench.append(filler.id)
	state.next_unit_id=serial
	ck(rules.restore(state).ok,"full bench pair fixture restores")
	before=rules.snapshot()
	reject(rules,{"type":"claim_reinforcement","round":3,"slot":1},"bench_full","full bench without immediate merge")
	result=rules.execute({"type":"claim_reinforcement","round":3,"slot":0})
	ck(result.ok and result.unit_id==p.deployed[0] and result.purchased_unit_id=="u%06d"%serial and result.merged_ids==[p.bench[0],"u%06d"%serial],"full bench merges preserving deployed survivor identity")
	ck(rules._find_unit(rules.get_player(),result.unit_id).star==2 and rules._find_unit(rules.get_player(),result.unit_id).ex_enabled and rules.get_player().deployed==p.deployed,"merge grants ordinary star and EX without moving board unit")
	# Buy and claim use identical acquisition/merge semantics with only payment/offer/event differences.
	var buy=Rules.new();state=before.duplicate(true);state.players[0].gold=10;state.players[0].shop[0]={"character_id":id,"cost":2}
	ck(buy.restore(state).ok,"paid comparison fixture restores")
	var bought:Dictionary=buy.execute({"type":"buy_offer","slot":0})
	ck(bought==result and buy.get_player().units==rules.get_player().units and buy.get_player().bench==rules.get_player().bench,"paid purchase and free recruitment have identical acquisition contract")
	ck(rules.restore(before).ok,"restore pending for explicit skip")
	before=rules.snapshot();ck(rules.execute({"type":"skip_reinforcement","round":3}).ok,"explicit skip resolves event")
	state=before.duplicate(true);state.players[0].reinforcement.status="skipped"
	ck(rules.snapshot()==state,"skip changes status only")
	reject(rules,{"type":"skip_reinforcement","round":3},"stale_reinforcement","repeated skip")
	reach(rules,6)
	var event:Dictionary=rules.get_reinforcement()
	ck(event.round==6 and event.cost==3 and event.status=="pending" and event.selected_slot==-1,"round6 replaces last event")
	for offer_id in event.offers:ck(rules._character(offer_id).cost==3,"round6 tier3 offers")
	ck(rules.execute({"type":"skip_reinforcement","round":6}).ok,"round6 skip")
	reach(rules,7)
	ck(rules.get_reinforcement().round==6 and rules.get_reinforcement().status=="skipped","last resolved event retained after event round")
func _test_npc(rules)->void:
	for index in range(1,8):
		var npc:Dictionary=rules.get_player("p%d"%index)
		ck(npc.reinforcement.round==6 and npc.reinforcement.status in ["claimed","skipped"],"NPC resolves finite same-tier event")
	var preview:Dictionary=rules.get_opponent_preview();var opponent:Dictionary=rules.get_player(preview.opponent_id)
	ck(preview.opponent_units==rules._deployed_units(opponent),"locked preview contains final NPC roster")
	var npc:Dictionary=rules.get_player("p1")
	npc.gold=0;npc.units=[unit("u900001","aru"),unit("u900002","aru"),unit("u900003","tier3_b")];npc.bench=[];npc.deployed=["u900001","u900002","u900003"]
	npc.shop=[{"character_id":"aru","cost":3},{},{},{},{}];npc.shop_locked=true
	npc.reinforcement={"round":6,"cost":3,"offers":["tier3_c","tier3_b","aru"],"status":"pending","selected_slot":-1}
	rules._prepare_ai(npc)
	ck(npc.reinforcement.status=="claimed" and npc.reinforcement.selected_slot==2 and npc.units[0].star==2,"NPC prefers legal third copy over pair or stable slot")
	ck(not npc.shop_locked,"NPC retention recomputed after free third-copy merge")
	npc.units=[unit("u900003","tier3_b")];npc.deployed=["u900003"];npc.bench=[];npc.reinforcement.status="pending";npc.reinforcement.selected_slot=-1
	rules._prepare_ai(npc)
	ck(npc.reinforcement.selected_slot==1,"NPC prefers making pair over stable first slot")
	npc.units=[];npc.deployed=[];npc.bench=[];npc.reinforcement.status="pending";npc.reinforcement.selected_slot=-1
	rules._prepare_ai(npc)
	ck(npc.reinforcement.selected_slot==0,"NPC uses stable first offer when copy counts tie")
	# Entire roster filled with two-star units: no legal third copy means an explicit skip.
	npc.units=[];npc.deployed=[];npc.bench=[];npc.reinforcement.status="pending";npc.reinforcement.selected_slot=-1
	for index in range(npc.level+rules.snapshot().config.bench_capacity):
		var filler:Dictionary=unit("u%06d"%(910000+index),"serika",2);npc.units.append(filler)
		if index<npc.level:npc.deployed.append(filler.id)
		else:npc.bench.append(filler.id)
	rules._prepare_ai(npc)
	ck(npc.reinforcement.status=="skipped" and npc.reinforcement.selected_slot==-1,"NPC skips only when all three offers fail capacity")
func _test_event_round_preview()->void:
	var rules=fresh({"starting_gold":0,"income":0,"interest_cap":0,"round_xp":0})
	var state:Dictionary=rules.snapshot();var p:Dictionary=state.players[0]
	p.units=[unit("u%06d"%state.next_unit_id,"serika")];p.deployed=[p.units[0].id];state.next_unit_id+=1
	ck(rules.restore(state).ok,"zero-economy event fixture restores")
	reach(rules,3)
	var preview:Dictionary=rules.get_opponent_preview()
	for index in range(1,8):
		var npc:Dictionary=rules.get_player("p%d"%index)
		ck(npc.reinforcement.status=="claimed" and npc.units.size()==1 and npc.deployed==[npc.units[0].id],"NPC free copy deployed at event-round entry without gold")
		ck(npc.units[0].character_id==npc.reinforcement.offers[npc.reinforcement.selected_slot],"NPC receives selected actual offer")
	ck(preview.opponent_units==rules.get_player(preview.opponent_id).units and preview.opponent_units.size()==1,"locked round3 preview includes newly acquired free reinforcement")
	var npc:Dictionary=rules.get_player("p1")
	npc.units=[];npc.deployed=[];npc.bench=[];npc.gold=4
	npc.shop=[{"character_id":"shiroko","cost":2},{"character_id":"shiroko","cost":2},{},{},{}]
	npc.reinforcement={"round":3,"cost":2,"offers":["nonomi","hoshino","shiroko"],"status":"pending","selected_slot":-1}
	rules._prepare_ai(npc)
	ck(npc.gold==0 and npc.units.size()==1 and npc.units[0].character_id=="shiroko" and npc.units[0].star==2 and npc.reinforcement.selected_slot==2,"NPC shops first then uses free third copy before deployment")

func _test_snapshot(rules)->void:
	var pending=fresh();ready(pending);reach(pending,3)
	var source:Dictionary=pending.snapshot()
	var mutations:Array=[]
	for value in [null,[],true,0,"event"]:
		var bad:Dictionary=source.duplicate(true);bad.players[0].reinforcement=value;mutations.append([bad,"nonobject event"])
	for key in source.players[0].reinforcement:
		var bad:Dictionary=source.duplicate(true);bad.players[0].reinforcement.erase(key);mutations.append([bad,"missing event key "+key])
	for key in ["round","cost","selected_slot"]:
		for value in [null,true,"3",3.5,{},[]]:
			var bad:Dictionary=source.duplicate(true);bad.players[0].reinforcement[key]=value;mutations.append([bad,"wrong numeric event field "+key])
	for change in [{"round":2},{"round":6},{"cost":3},{"offers":["shiroko","shiroko","nonomi"]},{"offers":["shiroko","nonomi","aru"]},{"offers":["shiroko","nonomi","unknown"]},{"offers":["shiroko","nonomi",1]},{"offers":{}},{"offers":[]},{"status":"bad"},{"status":true},{"selected_slot":0},{"status":"claimed","selected_slot":-1},{"status":"skipped","selected_slot":1},{"extra":0}]:
		var bad:Dictionary=source.duplicate(true);bad.players[0].reinforcement.merge(change,true);mutations.append([bad,"invalid event "+str(change)])
	var bad:Dictionary=source.duplicate(true);bad.players[0].reinforcement={};mutations.append([bad,"missing due event"])
	bad=source.duplicate(true);bad.config.reinforcement_recruitment=0;mutations.append([bad,"disabled nonempty event"])
	bad=source.duplicate(true);bad.players[1].reinforcement.status="pending";bad.players[1].reinforcement.selected_slot=-1;mutations.append([bad,"unresolved NPC in stable snapshot"])
	ck(pending.execute({"type":"skip_reinforcement","round":3}).ok,"snapshot fixture skips")
	ck(pending.execute({"type":"start_battle"}).ok,"snapshot fixture starts battle")
	bad=pending.snapshot();bad.players[0].reinforcement.status="pending";mutations.append([bad,"pending in battle"])
	for entry in mutations:reject_snapshot(rules,entry[0],entry[1])
	ck(rules.restore(pending.snapshot()).ok,"resolved battle snapshot valid")
func _test_config()->void:
	var rules=Rules.new();ck(rules.new_match(1).ok and rules.snapshot().config.reinforcement_recruitment==0 and rules.get_reinforcement().is_empty(),"direct rules default disabled")
	var before:Dictionary=rules.snapshot()
	for value in [true,false,-1,2,1.5,"1",null,[],{}]:
		ck(not rules.new_match(1,roster(),{"reinforcement_recruitment":value}).ok and rules.snapshot()==before,"invalid feature flag is rejected atomically")
	ck(not rules.new_match(1,[],{"reinforcement_recruitment":1}).ok and rules.snapshot()==before,"enabled catalog requires three distinct tier3 characters")
	var reduced:Array=roster();reduced[0].cost=1
	ck(not rules.new_match(1,reduced,{"reinforcement_recruitment":1}).ok,"enabled catalog requires three distinct tier2 characters")
