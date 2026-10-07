extends SceneTree
## Real imported actors and authoritative Core events; only particle allocation is recorded.
const Clock=preload("res://core/character_clock.gd")
const View=preload("res://scripts/unit_view.gd")
const Glue=preload("res://scripts/native_combat_vfx.gd")
const Props=preload("res://scripts/native_skill_props.gd")
var checks:=0
var failures:=0
var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
class RecordingPlayer extends Node3D:
 var stretch_camera_at:Callable
 var _effects:Array=[]
 var next_id:=0
 func reset(_generation):_effects.clear()
 func spawn(template,seed,at,resolver):
  next_id+=1;_effects.append({"id":next_id,"prefab":template,"seed":seed,"start":at,"end":at+10,"resolver":resolver});return next_id
 func release(_id):pass
 func update_time(_time):pass
class QuietConsumer extends Node3D:
 func consume(_event,_units):pass
 func update_time(_time):pass
class TestStage extends "res://scripts/battle_stage.gd":
 func _ready():pass
 func _update_camera(_at):pass
 func _update_actors(at:float,_tick:int=-1):
  for unit in units:views[unit.id].update_time(at,unit)
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize():call_deferred("run")
func make_stage(roster:Array):
 var stage=TestStage.new();root.add_child(stage);stage.generation=1
 var glue=Glue.new();stage.add_child(glue);stage.native_vfx=glue
 glue._player=RecordingPlayer.new();glue.add_child(glue._player);glue.reset(1)
 var props=Props.new();stage.add_child(props);stage.native_props=props;props.reset(1)
 stage.native_mines=QuietConsumer.new();stage.add_child(stage.native_mines)
 var roots={"hoshino":"Hoshino_Original","aris":"Aris_Original","shiroko":"Shiroko_Original"}
 for unit in roster:
  var actor=View.new();stage.add_child(actor)
  var shown:Dictionary=unit.duplicate(true);shown.presentation=profiles[unit.character_id];actor.setup(shown,{},1)
  stage.views[unit.id]=actor;glue._views[unit.id]=actor;glue._characters[unit.id]=unit.character_id
  glue._profiles[unit.character_id]=profiles[unit.character_id];glue._source_roots[unit.character_id]=roots[unit.character_id]
  glue._source_paths[unit.character_id]=[roots[unit.character_id]+"/Ex_Root"]
  glue._weapons[unit.character_id]="SG";glue._indices[unit.id]=glue._index_view(actor)
  props._views[unit.id]=actor;props._characters[unit.id]=unit.character_id
 glue._weapon_families={"SG":{"muzzlePrefab":"muzzle","hitPrefab":"hit"}}
 stage.update_display(roster,[],0,0)
 return stage
func core_trace(delta:float)->Dictionary:
 var clock=Clock.new();clock.generation=1
 var roster=[{"id":1,"team":0,"cell":Vector2(0,.75),"character_id":"hoshino","star":1},{"id":2,"team":1,"cell":Vector2(0,-.75),"character_id":"aris","star":1},{"id":3,"team":1,"cell":Vector2(2,-.75),"character_id":"aris","star":1}]
 ck(clock.sim.configure(roster,{"random_damage":false}).is_empty(),"native fixture configures");clock.sim.start()
 clock.sim.units[1].hp=1;clock.sim.units[1].busy_until=100000;clock.sim.units[2].hp=1000000;clock.sim.units[2].max_hp=1000000;clock.sim.units[2].busy_until=100000
 var stage=make_stage(clock.sim.units)
 var result:Dictionary={}
 if delta>.06:
  var initial:Array=clock.advance(.03);stage.update_display(clock.sim.units,initial,.03,clock.sim.tick)
 for i in 600:
  var events:Array=clock.advance(delta)
  var contact:Dictionary={}
  for event in events:
   if event.type=="damage" and event.actor_id==1 and event.target_id==3 and event.ability=="normal":contact=event
  var at:float=clock.sim.tick*.05+clock.accumulator
  stage.update_display(clock.sim.units,events,at,clock.sim.tick)
  if not contact.is_empty():
   var origin:Transform3D=stage.native_vfx._sample_anchor(1,"@muzzle",contact.tick*.05)
   for effect in stage.native_vfx._player._effects:
    if str(effect.prefab).ends_with("#muzzle") and is_equal_approx(effect.start,3.30):
     result={"anchor":origin,"birth":effect.resolver.call({"_native_anchor_query":"birth"}, {}, effect.start),"start":effect.start,"contact_tick":contact.tick,"render_time":at}
   break
 stage.free();return result
func boundary_trace(batched:bool,same_tick:bool=false,turn_first:bool=false)->Dictionary:
 var sim=Clock.new().sim
 ck(sim.configure([{"id":1,"team":0,"cell":Vector2(0,.75),"character_id":"hoshino","star":1},{"id":2,"team":1,"cell":Vector2(0,-1),"character_id":"shiroko","star":1}],{}).is_empty(),"boundary fixture configures")
 var units:Array=sim.units.duplicate(true)
 var stage=make_stage(units)
 stage.update_display(units,[],.95,19)
 var damage={"generation":1,"event_id":"contact","tick":20,"type":"damage","ability":"normal","actor_id":1,"target_id":2,"hit_index":0}
 var transition_tick:int=20 if same_tick else 21
 var turn={"generation":1,"event_id":"turn","tick":transition_tick,"type":"attack","actor_id":1,"target_cell":Vector2(2,0),"impact_tick":transition_tick+1,"recovery_ticks":37,"burst_ticks":17}
 var movement={"generation":1,"event_id":"move","tick":transition_tick,"type":"move","actor_id":2,"from":Vector2(0,-1),"to":Vector2(.16,-1),"duration":.05}
 var events:Array=[turn,movement,damage] if turn_first else [damage,turn,movement]
 var expected_muzzle:Variant=null
 var expected_hit:Variant=null
 if not batched:
  for event in events:
   stage.update_display(units,[event],float(event.tick)*.05,event.tick)
   if event==damage:
    expected_muzzle=stage.native_vfx._live_muzzle(1)
    var model=stage.views[2]._model
    expected_hit=Transform3D(Basis.IDENTITY.scaled(model.global_basis.get_scale().abs()),stage.views[2].hit_position())
 units[1].cell=Vector2(.16,-1)
 stage.update_display(units,events if batched else [],1.08,21)
 var result:Dictionary={"stage":stage,"units":units,"events":events,"muzzle":Transform3D.IDENTITY,"hit":Transform3D.IDENTITY,"expected_muzzle":expected_muzzle,"expected_hit":expected_hit}
 for effect in stage.native_vfx._player._effects:
  if str(effect.prefab).ends_with("#muzzle"):result.muzzle=effect.resolver.call({"_native_anchor_query":"birth"}, {}, 1.0)
  if str(effect.prefab).ends_with("#hit"):result.hit=effect.resolver.call({}, {}, 1.0)
 result.prop_before=stage.native_props._sample_anchor(2,.99)
 return result
func check_transform(a:Transform3D,b:Transform3D,label:String,position_tolerance:float=.005,angle_tolerance:float=.005):
 var distance:float=a.origin.distance_to(b.origin)
 var angle:float=a.basis.orthonormalized().get_rotation_quaternion().angle_to(b.basis.orthonormalized().get_rotation_quaternion())
 print(label," position_error=",distance," angle_error=",angle)
 ck(distance<position_tolerance and angle<angle_tolerance,label)
func lifecycle_checks()->void:
 var fixture=boundary_trace(true,true,false)
 var stage=fixture.stage
 var glue=stage.native_vfx
 var props=stage.native_props
 var frozen:Dictionary=glue._history.duplicate(true)
 var prop_frozen:Dictionary=props._history.duplicate(true)
 var count:int=glue._player._effects.size()
 stage.update_display(fixture.units,fixture.events,1.08,21)
 ck(glue._player._effects.size()==count,"duplicate stage batch does not respawn effects")
 ck(glue._history==frozen and props._history==prop_frozen,"frozen update preserves both histories")
 var stale:Dictionary=fixture.events[1].duplicate(true);stale.generation=0;stale.event_id="stale";stale.target_cell=Vector2(-5,0)
 stage.update_display(fixture.units,[stale],1.08,21)
 ck(glue._history==frozen and props._history==prop_frozen,"stale generation cannot record a boundary")
 var now:Transform3D=glue._live_muzzle(1)
 for effect in glue._player._effects:
  if str(effect.prefab).ends_with("#muzzle"):
   check_transform(now,effect.resolver.call({}, {},1.08),"local-space current resolver still follows live actor",.0001,.001)
 var left:Transform3D=glue._sample_anchor(1,"@muzzle",.95)
 var before:Transform3D=glue._history[1].filter(func(x):return absf(float(x.time)-1.0)<.000001)[0].anchors["@muzzle"]
 check_transform(left.interpolate_with(before,.5),glue._sample_anchor(1,"@muzzle",.975),"ordinary interpolation before boundary remains",.0001,.001)
 ck(glue._sample_anchor(1,"absent",1.0)==null,"missing sampled anchor fails closed")
 ck(glue._resolve_history({"_native_anchor_query":"birth"}, {},1.0,1,"@muzzle",1.0,{})==null,"missing pinned origin never uses a later socket")
 glue.update_time(.5);props.update_time(.5)
 ck(glue._history==frozen and props._history==prop_frozen,"rewind does not append unsorted historical poses")
 ck(glue._issues.any(func(x):return x.code=="rewind_requires_reset") and props._issues.any(func(x):return x.code=="rewind_requires_reset"),"rewind retains explicit reset diagnostic")
 glue.max_history_samples=4;props.max_history_samples=4
 for n in 12:
  stage.views[1].position.x+=.01;stage.views[2].position.x+=.01
  glue.capture_event_pose(2.0+n*.01,[1,2]);props.capture_event_pose(2.0+n*.01,[2])
 ck(glue._history[1].size()<=4 and props._history[2].size()<=4,"ordered event samples obey both history budgets")
 glue.max_history_samples=-1;props.max_history_samples=-1
 glue.capture_event_pose(3.0,[1,2]);props.capture_event_pose(3.0,[2])
 ck(glue._history[1].size()==2 and props._history[2].size()==2,"negative history cap retains safe minimum")
 var queued_order:Array=[]
 for n in 24:
  var key:String="ordered-"+str(n);queued_order.append(key)
  glue.consume({"type":"damage","ability":"normal","actor_id":1,"target_id":2,"tick":1000,"hit_index":n,"generation":1,"event_id":key},fixture.units)
  props.consume({"type":"skill","ability":"ex","actor_id":2,"tick":1000,"generation":1,"event_id":key},fixture.units)
 glue.update_time(3.0);props.update_time(3.0)
 ck(glue._pending.map(func(x):return x.event_id)==queued_order,"equal-time VFX events keep received causal order")
 ck(props._pending.map(func(x):return x.event_id)==queued_order,"equal-time prop events keep received causal order")
 glue.reset(2);props.reset(2)
 ck(glue._history.is_empty() and props._history.is_empty() and glue._pending.is_empty() and props._pending.is_empty(),"generation reset clears ordered history and origins")
 stage.free()

func continuous_movement_check()->void:
 var sim=Clock.new().sim
 ck(sim.configure([{"id":1,"team":0,"cell":Vector2(0,.75),"character_id":"hoshino","star":1},{"id":2,"team":1,"cell":Vector2(0,-1),"character_id":"shiroko","star":1}],{}).is_empty(),"continuous native movement fixture configures")
 var units:Array=sim.units.duplicate(true)
 var stage=make_stage(units)
 var reference=View.new();root.add_child(reference)
 var shown:Dictionary=units[1].duplicate(true);shown.presentation=profiles[shown.character_id];reference.setup(shown,{},1)
 for tick in range(1,21):
  var event={"generation":1,"event_id":"continuous-move-"+str(tick),"tick":tick,"type":"move","actor_id":2,"from":Vector2((tick-1)*.16,-1),"to":Vector2(tick*.16,-1),"duration":.05}
  units[1].cell=event.to
  var at:float=tick*.05+.02
  stage.update_display(units,[event],at,tick)
  reference.consume(event);reference.update_time(at,units[1])
  var actor=stage.views[2]
  ck(actor._clip_revision==reference._clip_revision,"continuous movement does not restart WALK at tick"+str(tick))
  ck(absf(actor.animation_player.current_animation_position-reference.animation_player.current_animation_position)<.00001,"continuous native walk phase matches reference at tick"+str(tick))
 stage.free();reference.free()

func continuous_core_movement_check()->void:
 var clock=Clock.new();clock.generation=1
 ck(clock.sim.configure([{"id":1,"team":0,"cell":Vector2(0,4),"character_id":"hoshino","star":1},{"id":2,"team":1,"cell":Vector2(0,-4),"character_id":"shiroko","star":1}],{"random_damage":false}).is_empty(),"real-core walk fixture configures")
 clock.sim.start();clock.sim.units[0].busy_until=10000
 var stage=make_stage(clock.sim.units)
 var reference=View.new();root.add_child(reference)
 var shown:Dictionary=clock.sim.units[1].duplicate(true);shown.presentation=profiles.shiroko;reference.setup(shown,{},1)
 var moves:int=0
 for frame in 20:
  var events:Array=clock.advance(.05)
  var at:float=clock.sim.tick*.05+clock.accumulator
  stage.update_display(clock.sim.units,events,at,clock.sim.tick)
  for event in events:
   reference.consume(event)
   if event.type=="move" and event.actor_id==2:moves+=1
  reference.update_time(at,clock.sim.units[1])
  var actor=stage.views[2]
  ck(actor._clip_revision==reference._clip_revision and absf(actor.player.current_animation_position-reference.player.current_animation_position)<.00001,"real-core movement phase/revision matches at tick"+str(clock.sim.tick))
 ck(moves>=10,"real Core emitted repeated continuous moves")
 stage.free();reference.free()

func native_same_time_space_check(character:String)->void:
 var sim=Clock.new().sim
 ck(sim.configure([{"id":1,"team":0,"cell":Vector2(0,.75),"character_id":character,"star":1},{"id":2,"team":1,"cell":Vector2(0,-1),"character_id":"aris","star":1}],{}).is_empty(),"native space fixture configures")
 var units:Array=sim.units.duplicate(true)
 var stage=make_stage(units)
 var glue=stage.native_vfx
 glue._player.free();glue._player=load("res://vfx/native_effect_player.gd").new();glue.add_child(glue._player);glue._player.reset(1);glue.configure(profiles)
 stage.update_display(units,[],.95,19)
 stage.views[1].advance_event_time(1.0)
 var contact_anchor:Transform3D=glue._live_muzzle(1)
 var damage={"generation":1,"event_id":"native-contact","tick":20,"type":"damage","ability":"normal","actor_id":1,"target_id":2,"hit_index":0}
 var turn={"generation":1,"event_id":"native-turn","tick":20,"type":"attack","actor_id":1,"target_cell":Vector2(2,0),"impact_tick":21,"recovery_ticks":37,"burst_ticks":17}
 stage.update_display(units,[damage,turn],1.0,20)
 var live:Transform3D=glue._live_muzzle(1)
 var native_particles=load("res://vfx/native_particles.gd")
 var visible:int=0
 for effect in glue._player._effects:
  if not str(effect.prefab).contains("Muzzle"):continue
  for layer in effect.layers:
   for item in layer.particles:
    if not item.node.visible:continue
    visible+=1
    var sample:Dictionary=native_particles.state(layer.params,item.sample,0.0)
    var world:bool=int(layer.params.get("moveWithTransform",0))==1
    var anchor:Transform3D=contact_anchor if world else live
    var expected:Vector3=anchor*layer.base_transform*sample.position+sample.world_offset*glue._player.world_gravity_scale
    ck(expected.distance_to(item.node.global_position)<.0001,"native "+character+" particle respects "+("world birth" if world else "local current")+" at the exact contact timestamp")
 ck(visible>0,"source "+character+" muzzle has visible particles at origin")
 stage.free()

func run():
 var ticked=core_trace(.05);var batched=core_trace(.08)
 ck(not ticked.is_empty() and not batched.is_empty(),"real-core second SG contact found")
 if not ticked.is_empty() and not batched.is_empty():
  ck(ticked.contact_tick==66 and batched.contact_tick==66 and is_equal_approx(batched.start,3.30),"authoritative SG contact stays at tick66 / 3.30s")
  check_transform(ticked.anchor,batched.anchor,"real SG retarget historical socket")
  check_transform(ticked.birth,batched.birth,"real SG world-space particle birth")
 var fixed=boundary_trace(false);var delayed=boundary_trace(true)
 check_transform(fixed.hit,delayed.hit,"fixed impact before victim movement",.0001,.0001)
 check_transform(fixed.muzzle,delayed.muzzle,"contact before following-tick source switch",.0001,.0001)
 check_transform(fixed.prop_before,delayed.prop_before,"source prop root before movement",.0001,.0001)
 fixed.stage.free();delayed.stage.free()
 for turn_first in [false,true]:
  var ordered=boundary_trace(false,true,turn_first);var queued=boundary_trace(true,true,turn_first)
  check_transform(ordered.expected_muzzle,queued.muzzle,"same-time muzzle ordering turn_first="+str(turn_first),.0001,.0001)
  check_transform(ordered.expected_hit,queued.hit,"same-time impact ordering turn_first="+str(turn_first),.0001,.0001)
  ordered.stage.free();queued.stage.free()
 lifecycle_checks()
 continuous_movement_check()
 continuous_core_movement_check()
 native_same_time_space_check("shiroko")
 native_same_time_space_check("hoshino")
 print("CONTACT_ANCHOR_BOUNDARIES ",checks," checks; ",failures," failures");quit(1 if failures else 0)
