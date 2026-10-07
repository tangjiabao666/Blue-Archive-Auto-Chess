extends SceneTree
const Sim=preload("res://core/character_sim.gd")
const Clock=preload("res://core/character_clock.gd")
const Session=preload("res://core/game_session.gd")
var fails:=0
func ck(ok:bool,label:String):
	if not ok:fails+=1;printerr("FAIL: "+label)
func roster()->Array:
	return [{"id":0,"team":0,"cell":Vector2(0,2),"character_id":"koharu","star":2},{"id":1,"team":0,"cell":Vector2(2,2),"character_id":"yuuka","star":2},{"id":7,"team":1,"cell":Vector2(0,-2),"character_id":"hoshino","star":2}]
func frozen(settings:Dictionary={}):
	var sim=Sim.new();ck(sim.configure(roster(),settings).is_empty(),"overtime fixture configures")
	for unit in sim.units:
		unit.busy_until=100000;unit.basic_ready=100000;unit.skill_ready=100000;unit.sub_ready=100000;unit.basic_activations=1
	sim.start();return sim
func old_seven(settings:Dictionary)->Dictionary:
	var rows:Array=[];var keys=["shiroko","hoshino","hina","aru","yuuka","aris","serika"]
	for team in range(2):
		for i in range(7):rows.append({"id":team*7+i,"team":team,"cell":Vector2(-4.8+i*1.6,3.8 if team==0 else -3.8),"character_id":keys[(i+team*2)%7],"star":2})
	var sim=Sim.new();settings=settings.duplicate(true);settings.seed=101
	ck(sim.configure(rows,settings).is_empty(),"legacy roster configures")
	sim.start();var batches:Array=[]
	while sim.phase=="running":batches.append(sim.step())
	return {"units":sim.units,"events":batches,"tick":sim.tick,"winner":sim.winner,"rng":sim.snapshot().rng_state}
func _initialize():
	var sim=Sim.new()
	var error:String=sim.configure(roster(),{"overtime_enabled":true})
	ck(error.is_empty(),"explicit game-level overtime must be configurable")
	if not error.is_empty():print("OVERTIME FAILURES=",fails);quit(1);return
	ck(sim.has_method("overtime_state"),"overtime exposes honest state")
	if not sim.has_method("overtime_state"):quit(1);return
	var baseline:Dictionary=old_seven({})
	ck(JSON.stringify(baseline).sha256_text()=="f88dee1f3418323e21ef0cd2d593d95fc86063e76c1e5bc1aa0b2a5f149a5222","default isolated Sim reproduces pre-overtime old-seven golden events, units and RNG")
	ck(old_seven({"overtime_enabled":false,"overtime_start_seconds":0.05})==baseline,"explicit disabled option preserves legacy battle exactly")
	sim=frozen({"overtime_enabled":true})
	ck(not sim.overtime_state().active,"overtime inactive at battle start")
	sim.tick=1498;var batch:Array=sim.step()
	ck(not sim.overtime_state().active and batch.filter(func(e):return e.type=="overtime_started").is_empty(),"overtime cannot start before 75 simulation seconds")
	batch=sim.step();var starts:Array=batch.filter(func(e):return e.type=="overtime_started")
	ck(starts.size()==1 and sim.overtime_state().active,"overtime starts once at exact 75-second boundary")
	ck(sim.overtime_state().healing_multiplier==1.0 and sim.overtime_state().shield_multiplier==1.0,"first overtime tick preserves full sustain")
	if not starts.is_empty():ck(starts[0].start_tick==1500 and starts[0].ramp_ticks==600,"overtime event reports actual quantized rule")
	for i in range(299):
		batch=sim.step();ck(batch.filter(func(e):return e.type=="overtime_started").is_empty(),"overtime start event never repeats")
	sim.step();ck(is_equal_approx(sim.overtime_state().healing_multiplier,0.6),"halfway through ramp healing is 60 percent")
	ck(sim.snapshot().overtime==sim.overtime_state(),"snapshot exposes actual overtime state")
	sim.tick=2100;ck(is_equal_approx(sim.overtime_state().healing_multiplier,0.2),"105-second boundary reaches 20 percent")
	sim.tick=2399;ck(is_equal_approx(sim.overtime_state().shield_multiplier,0.2),"sustain cannot fall below configured floor")
	var quantized=frozen({"overtime_enabled":true,"overtime_start_seconds":0.076,"overtime_ramp_seconds":0.076})
	ck(quantized.overtime_state().start_tick==2 and quantized.overtime_state().ramp_ticks==2,"fractional durations quantize upward to the next fixed tick")
	quantized.step();ck(not quantized.overtime_state().active,"quantized overtime cannot start early")
	quantized.step();ck(quantized.overtime_state().active and quantized.overtime_state().healing_multiplier==1.0,"quantized start still begins at full sustain")
	quantized.step();ck(is_equal_approx(quantized.overtime_state().healing_multiplier,0.6),"quantized ramp uses simulation ticks")
	for floor_value in [0.0,1.0]:
		var edge=frozen({"overtime_enabled":true,"overtime_min_sustain_multiplier":floor_value,"overtime_start_seconds":0.05,"overtime_ramp_seconds":0.05})
		edge.tick=2;edge.units[1].hp=1;edge._heal(edge.units[0],edge.units[1],1.0,"basic")
		ck(edge.events.back().amount==int(floor(5035*floor_value)),"sustain floor endpoints 0 and 1 are supported exactly")
	var upper=Sim.new();ck(upper.configure(roster(),{"overtime_start_seconds":3600.0,"overtime_ramp_seconds":3600.0}).is_empty(),"maximum supported durations accepted")
	# Scale resolved sustain only; preserve skills, stats, cast metadata and lifetime.
	sim=frozen({"overtime_enabled":true});sim.tick=1800
	var source:Dictionary=sim.units[0];var target:Dictionary=sim.units[1]
	target.hp=1
	var native_heal:=int(floor(sim.stat(source,"HealPower")*1.9275))
	var context={"cast_start_tick":1490,"target_cell":Vector2(2,2),"origin":Vector2.ZERO,"component":"circle","hit_index":0,"hit_count":1}
	sim._heal(source,target,1.9275,"ex",context)
	var event:Dictionary=sim.events.back()
	ck(event.amount==int(floor(native_heal*0.6)) and target.hp==1+event.amount,"healing uses resolution-time multiplier after native truncation")
	ck(event.native_raw_amount==native_heal and is_equal_approx(event.overtime_multiplier,0.6),"healing discloses native amount and explicit game-level multiplier")
	ck(event.cast_start_tick==1490 and event.cast_target_cell==context.target_cell and event.component=="circle","heal retains native cast metadata")
	ck(sim.stat(source,"HealPower")==5035 and sim.character_data("koharu").ex.healPowerRatio==1.9275,"overtime leaves source coefficient and HealPower unchanged")
	target.hp=target.max_hp-1;sim._heal(source,target,1.9275,"ex")
	ck(sim.events.back().amount==1 and target.hp==target.max_hp,"overtime healing still respects max HP")
	target.hp=0;var count:int=sim.events.size();sim._heal(source,target,1.9275,"ex")
	ck(target.hp==0 and sim.events.size()==count,"overtime healing never resurrects")
	target.hp=target.max_hp
	sim.tick=1499;sim._shield(target,2.5,2200,"ex");var old_shield:int=target.shield
	sim.tick=1799;sim.step();ck(target.shield==old_shield and target.shield_until==2200,"existing shields do not shrink as overtime advances")
	var native_shield:=int(floor(sim.stat(target,"HealPower")*2.5))
	sim._shield(target,2.5,2300,"ex");event=sim.events.back()
	ck(target.shield==int(floor(native_shield*0.6)) and target.shield_until==2300,"only newly created shield strength scales; duration is unchanged")
	ck(event.native_raw_amount==native_shield and is_equal_approx(event.overtime_multiplier,0.6),"shield discloses separated adaptation metadata")
	# The permanent floor must use the exact configured factor, not a lerp endpoint
	# slightly below it that loses another HP to final integer truncation.
	sim.tick=2100;target.hp=1;sim._heal(source,target,1.0,"basic")
	ck(sim.events.back().amount==1007,"105-second floor heals exactly 20 percent of native 5035")
	sim._shield(target,5.0,2300,"ex")
	ck(target.shield==int(sim.stat(target,"HealPower")),"105-second floor shields exactly 20 percent of a native amount divisible by five")
	sim.tick=1800
	# All attack paths remain native when the sustain-only rule is selected.
	var plain=frozen();plain.tick=1800
	var hit={"source":0,"target":7,"effect":"damage","atk_ratio":1.234,"can_crit":false,"kind":"skill","ability":"ex","component":"circle","hit_index":0,"hit_count":1,"origin":Vector2.ZERO,"target_cell":Vector2(0,-2),"cast_start_tick":1740}
	plain.options.random_damage=false;sim.options.random_damage=false
	plain.events=[];sim.events=[];plain._resolve_hit(hit);sim._resolve_hit(hit)
	ck(plain.events.back()==sim.events.back(),"sustain-only overtime leaves damage values and metadata exactly unchanged")
	# Pausing cannot consume any overtime simulation time.
	var game=Session.new();game.new_game(17);game.rules._prepare_ai(game.rules._player_ref("p0"));game.command({"type":"start_battle"})
	ck(game.clock.sim.options.overtime_enabled and game.clock.sim.options.overtime_start_seconds==75.0 and game.clock.sim.options.overtime_ramp_seconds==30.0 and game.clock.sim.options.overtime_min_sustain_multiplier==0.2,"GameSession opts into the explicit sustain-only rule")
	game.clock.sim.tick=1499;game.paused=true
	var before:Dictionary=game.clock.sim.snapshot();ck(game.advance(10.0).is_empty() and game.clock.sim.snapshot()==before,"pause preserves tick, overtime state and RNG")
	# Frame batching and reset/replay retain exact ordering across the boundary.
	var a=Clock.new();var b=Clock.new()
	a.sim=frozen({"overtime_enabled":true,"overtime_start_seconds":0.1,"overtime_ramp_seconds":0.2})
	b.sim=frozen({"overtime_enabled":true,"overtime_start_seconds":0.1,"overtime_ramp_seconds":0.2})
	var ea:Array=[];var eb:Array=[]
	for i in range(10):ea.append_array(a.advance(0.05))
	eb=b.advance(0.5);ck(a.sim.snapshot()==b.sim.snapshot() and ea==eb,"overtime is invariant to render frame batching")
	a.reset();ck(not a.sim.overtime_state().active,"reset clears overtime state");a.sim.start();var replay:Array=a.advance(0.5)
	for item in replay:item.generation=0
	ck(ea==replay,"reset exactly replays overtime start event")
	# Invalid settings are rejected atomically, even if overtime is disabled.
	var invalids={"overtime_enabled":[1,"yes"],"overtime_start_seconds":[-1.0,0.0,NAN,INF,3601.0,"bad"],"overtime_ramp_seconds":[-1.0,0.0,NAN,INF,3601.0,"bad"],"overtime_min_sustain_multiplier":[-0.01,1.01,NAN,INF,"bad"]}
	for key in invalids:
		for value in invalids[key]:
			sim=Sim.new();sim.configure(roster());before=sim.snapshot()
			ck(not sim.configure(roster(),{key:value}).is_empty(),"invalid overtime option rejected: "+key+"="+str(value))
			ck(sim.snapshot()==before,"rejected overtime option cannot mutate configuration")
	print("OVERTIME FAILURES=",fails);quit(1 if fails else 0)
