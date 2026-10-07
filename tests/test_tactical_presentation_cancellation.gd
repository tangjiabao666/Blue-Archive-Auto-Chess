extends SceneTree
## Tactical interruption is adapter policy; native art/timing remains untouched.
const View=preload("res://scripts/unit_view.gd")
const VFX=preload("res://scripts/native_combat_vfx.gd")
const Audio=preload("res://scripts/native_combat_audio.gd")
const Player=preload("res://vfx/native_effect_player.gd")
const Props=preload("res://scripts/native_skill_props.gd")
const EVENTS="res://data/effects/battle-events-compact.json"
var checks:=0
var failures:=0
var profiles:Dictionary
class AnchorView extends Node3D:
 var _model:Node3D
 func _init()->void:
  _model=Node3D.new();_model.name="Shiroko_Original";add_child(_model)
  var ex:=Node3D.new();ex.name="Ex_Root";_model.add_child(ex)
  var dm:=Node3D.new();dm.name="FX_Local_DM";ex.add_child(dm)
  var muzzle:=Node3D.new();muzzle.name="fire_01";_model.add_child(muzzle)
 func muzzle_transform()->Transform3D:return _model.global_transform
 func hit_position()->Vector3:return global_position
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: "+label)
func cast(actor:int,tick:int=0,ability:String="basic",gen:int=7)->Dictionary:
 return {"type":"basic" if ability=="basic" else "skill","ability":ability,"actor_id":actor,"tick":tick,"cast_start_tick":tick,"generation":gen,"event_id":"%s:%d:%d:%d"%[ability,actor,tick,gen],"recovery_ticks":100,"target_cell":Vector2.ZERO}
func cancel(actor:int,tick:int,gen:int=7)->Dictionary:
 return {"type":"action_cancelled","actor_id":actor,"tick":tick,"generation":gen,"event_id":"cancel:%d:%d:%d"%[actor,tick,gen],"abilities":["normal","basic"],"reason":"tactical_move"}
func anchor(_binding:Dictionary,_event:Dictionary,_time:float)->Transform3D:return Transform3D.IDENTITY
func _initialize()->void:call_deferred("run")
func run()->void:
 profiles=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
 test_particle_cutoff()
 test_vfx_cast_cancellation()
 test_audio_cancellation()
 test_unit_action_cancellation()
 test_ex_props_preserved()
 await process_frame
 print("TACTICAL PRESENTATION CANCELLATION CHECKS=",checks," FAILURES=",failures)
 quit(1 if failures else 0)
func test_particle_cutoff()->void:
 var p:=Player.new();root.add_child(p)
 var baseline:=Player.new();root.add_child(baseline);baseline.play_timeline(EVENTS,"aris","basic",0.0,anchor)
 var handle:int=p.play_timeline(EVENTS,"aris","basic",0.0,anchor)
 ck(p.has_method("stop_emission"),"effect player supports interruption without deleting born tails")
 if not p.has_method("stop_emission"):p.free();baseline.free();return
 p.update_time(0.12)
 var before:Dictionary=p.snapshot()
 ck(not before.particles.is_empty(),"real basic source has born particles before cutoff")
 p.stop_emission(handle,0.15);p.update_time(0.12)
 ck(p.snapshot()==before,"cutoff preserves exact already-born particle state")
 var retained:=0;var suppressed:=0;var unchanged:=true
 for at in [0.16,0.4,0.7,1.2]:
  p.update_time(at);baseline.update_time(at)
  for effect_index in p._effects.size():
   var effect:Dictionary=p._effects[effect_index]
   for layer_index in effect.layers.size():
    var layer:Dictionary=effect.layers[layer_index]
    for item_index in layer.particles.size():
     var item:Dictionary=layer.particles[item_index]
     var original:Dictionary=baseline._effects[effect_index].layers[layer_index].particles[item_index]
     var born:float=effect.start+(item.birth-effect.clip_in)/effect.speed
     if born<0.15 and effect.node.visible and item.node.visible:
      unchanged=unchanged and original.node.visible and item.node.global_transform==original.node.global_transform and item.material.get_shader_parameter("particle_color")==original.material.get_shader_parameter("particle_color")
  for effect in p._effects:
   for layer in effect.layers:
    for item in layer.particles:
     var born:float=effect.start+(item.birth-effect.clip_in)/effect.speed
     if born>=0.15 and item.node.visible and effect.node.visible:suppressed-=10000
     elif born>=0.15:suppressed+=1
     elif effect.node.visible and item.node.visible:retained+=1
 ck(suppressed>0,"future effect starts and future births never become visible after cutoff")
 ck(retained>0,"already-born transient particles retain tails after interruption")
 ck(unchanged,"born tails retain exact transforms and colors against uncancelled source playback")
 p.stop_emission(handle,0.5);p.update_time(1.0)
 ck(p.snapshot().particles.is_empty(),"repeated later cancellation cannot extend original cutoff")
 p.free();baseline.free()
func test_vfx_cast_cancellation()->void:
 var view:=AnchorView.new();root.add_child(view)
 var other:=AnchorView.new();root.add_child(other)
 var units:Array=[{"id":1,"character_id":"shiroko"},{"id":2,"character_id":"shiroko"}]
 var v:=VFX.new();root.add_child(v);v.configure(profiles);v.begin_roster({1:view,2:other},units,7)
 v.consume(cast(1),units);v.consume(cast(2),units);v.consume(cancel(1,2,6),units);v.update_time(0.1)
 ck(v.diagnostics().timelines_spawned==2,"stale generation cancellation leaves both timelines")
 v.consume(cancel(1,3),units);v.consume(cast(1,3,"ex"),units);v.update_time(0.5)
 var stopped:=0;var peers:=0;var ex:=0
 for handle in v.handle_deadlines():
  for effect in v._player._effects:
   if effect.id!=handle.id:continue
   for layer in effect.layers:
    for item in layer.particles:
     if not effect.node.visible or not item.node.visible:continue
     var born:float=effect.start+(item.birth-effect.clip_in)/effect.speed
     if handle.actor_id==2:peers+=1
     elif handle.start==0.0 and born>=0.15:stopped+=1
     elif is_equal_approx(handle.start,0.15):ex+=1
 ck(stopped==0,"actor's old basic cannot emit particles after cancellation")
 ck(peers>0 and ex>0,"other actor and replacement EX keep emitting")
 v.consume(cast(1,10),units);v.consume(cancel(1,4),units);v.update_time(0.7)
 var newer_visible:=false
 for handle in v.handle_deadlines():
  if handle.actor_id!=1 or not is_equal_approx(handle.start,0.5):continue
  for effect in v._player._effects:
   if effect.id==handle.id and effect.node.visible:
    for layer in effect.layers:
     for item in layer.particles:if item.node.visible:newer_visible=true
 ck(newer_visible,"late cancellation cannot stop a newer basic cast")
 v.reset(8);ck(v.diagnostics().active_handles==0,"reset discards cancellation and old tails")
 v.free();view.free();other.free()
func test_audio_cancellation()->void:
 var a:=Audio.new();a.output_enabled=false;root.add_child(a)
 var units:Array=[{"id":1,"character_id":"aris"},{"id":2,"character_id":"aris"}]
 a.begin_roster(units,7)
 a.consume(cast(1));a.consume(cast(2));a.consume(cancel(1,2));a.consume(cast(1,2,"ex"))
 a.update_time(0.5)
 var d:Dictionary=a.diagnostics()
 ck(not d.played.any(func(row):return row.actor_id==1 and row.kind=="basic"),"basic cancelled before delayed onset never plays")
 ck(d.played.any(func(row):return row.actor_id==2 and row.kind=="basic"),"other actor's delayed basic still plays")
 ck(d.scheduled.any(func(row):return row.actor_id==1 and row.kind=="ex"),"new EX audio remains scheduled")
 a.begin_roster(units,7);a.consume(cast(1));a.update_time(0.4)
 ck(a.diagnostics().active_voices==1,"real basic manifest starts a voice before interruption")
 a.consume(cancel(1,10));a.update_time(0.45)
 ck(a.diagnostics().active_voices==1,"future cancellation does not stop audio early")
 a.update_time(0.5)
 ck(a.diagnostics().active_voices==0,"due cancellation stops active basic sample")
 a.consume(cast(1,12));a.consume(cancel(1,10));a.consume(cancel(1,13,6));a.update_time(1.0)
 ck(a.diagnostics().active_voices==1,"newer basic survives repeated and stale cancellation")
 a.begin_roster(units,8);a.consume(cast(1,0,"basic",8));a.update_time(0.4)
 ck(a.diagnostics().active_voices==1,"reset does not carry cancellation across generations")
 a.begin_roster(units,7);a.output_enabled=true;a.consume(cast(1));a.update_time(0.4)
 var voice:AudioStreamPlayer=a.get_child(0)
 ck(voice.playing,"basic source starts actual output player")
 a.consume(cancel(1,9));a.update_time(0.45)
 ck(not voice.playing,"cancellation stops actual AudioStreamPlayer output")
 a.output_enabled=false
 a.begin_roster(units,7);a.max_queued_events=1;a.consume(cast(1));a.consume(cancel(1,2));a.consume(cast(1,2,"ex"))
 ck(a.diagnostics().queue_budget_drops==0 and a.diagnostics().scheduled.any(func(row):return row.kind=="ex"),"cancelled delayed basic frees pending capacity for same-tick EX")
 a.free()
func test_unit_action_cancellation()->void:
 var v:=View.new();root.add_child(v)
 var u:Dictionary={"id":1,"team":0,"character_id":"aris","range":3.0,"cell":Vector2.ZERO,"presentation":profiles.aris}
 v.setup(u,{},7);v.consume(cast(1));v.consume(cancel(1,2));v.advance_event_time(0.1,true)
 ck(v._action_kind.is_empty() and v.state=="idle","cancel event ends basic body action without needing a move event")
 v.consume(cast(1,3,"ex"));v.consume(cancel(1,4));v.advance_event_time(0.2)
 ck(v._action_kind=="skill","ordinary cancellation cannot interrupt current EX")
 v.consume(cast(1,20));v.consume(cancel(1,5));v.advance_event_time(1.0)
 ck(v._action_kind=="basic","late cancellation cannot interrupt newer basic body action")
 v.consume(cancel(1,21,6));ck(v._action_kind=="basic","stale generation cannot interrupt body action")
 var ordinary:Array=[]
 v.ordinary_audio_state.connect(func(record:Dictionary):ordinary.append(record.duplicate(true)))
 u.presentation=profiles.shiroko;u.character_id="shiroko";v.setup(u,{},7)
 v.consume({"type":"attack","actor_id":1,"generation":7,"tick":0,"event_id":"ordinary-fire","target_cell":Vector2.ZERO,"burst_ticks":14,"recovery_ticks":54,"impact_tick":1})
 v.consume(cancel(1,2));v.consume(cancel(1,2))
 ck(v._action_kind.is_empty() and ordinary.filter(func(row):return row.type=="exit").size()==1,"cancellation closes active ordinary state exactly once")
 v.consume({"type":"reload","actor_id":1,"generation":7,"tick":3,"event_id":"ordinary-reload","duration_ticks":40})
 v.consume(cancel(1,4))
 ck(v._action_kind.is_empty() and ordinary.filter(func(row):return row.type=="exit").size()==2,"cancellation also closes active reload state")
 v.free()
func test_ex_props_preserved()->void:
 var view:=AnchorView.new();root.add_child(view)
 var p:=Props.new();root.add_child(p)
 var units:Array=[{"id":1,"character_id":"shiroko"}]
 p.configure(profiles);p.begin_roster({1:view},units,7)
 p.consume(cast(1,0,"ex"),units);p.update_time(1.0)
 p.consume(cancel(1,21),units);p.update_time(1.1)
 ck(p.diagnostics().active_props==1,"ordinary cancellation preserves native Shiroko EX drone")
 p.free();view.free()
