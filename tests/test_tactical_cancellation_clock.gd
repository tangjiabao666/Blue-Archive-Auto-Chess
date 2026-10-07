extends SceneTree
## Actual tactical commands through Clock -> BattleStage/UnitView/VFX -> audio.
const Clock=preload("res://core/character_clock.gd")
const Stage=preload("res://scripts/battle_stage.gd")
const Audio=preload("res://scripts/native_combat_audio.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
 for kind in ["move","cast_ex"]:
  var character:String="aris" if kind=="move" else "shiroko"
  var c:=Clock.new();c.use_combat_mode("tactical_v1");c.generation=7
  ck(c.sim.configure([{"id":1,"team":0,"character_id":character,"star":2,"cell":Vector2(0,1)}, {"id":2,"team":1,"character_id":"yuuka","star":1,"cell":Vector2(0,-1)}],{"seed":7,"initial_basic_delay_cap_seconds":0.05,"random_damage":false}).is_empty(),kind+" core configures")
  c.sim.start()
  c.sim.units[1].hp=1000000;c.sim.units[1].max_hp=1000000;c.sim.units[1].busy_until=100000
  var stage:=Stage.new();root.add_child(stage);stage.configure(profiles,[]);stage.set_roster(c.sim.units,7,false)
  var audio:=Audio.new();audio.output_enabled=false;root.add_child(audio);audio.begin_roster(c.sim.units,7)
  var batch:Array=c.advance(0.05)
  ck(batch.any(func(e):return e.type=="basic" and e.actor_id==1),kind+" real core starts automatic basic")
  stage.update_display(c.sim.units,batch,0.05,c.sim.tick)
  for e in batch:audio.consume(e)
  audio.update_time(0.05)
  ck(c.sim.queue_tactical_command({"generation":7,"team":0,"sequence":1,"tick":2,"type":kind,"actor_id":1,"target_id":2 if kind=="cast_ex" else -1,"point":Vector2(0,-1) if kind=="cast_ex" else Vector2(1,1)}).ok,kind+" command queues")
  batch=c.advance(0.05)
  ck(batch.any(func(e):return e.type=="command_accepted") and batch.any(func(e):return e.type=="action_cancelled" and e.generation==7),kind+" core accepts and tags cancellation")
  stage.update_display(c.sim.units,batch,0.1,c.sim.tick)
  for e in batch:audio.consume(e)
  audio.update_time(0.1)
  ck(stage.views[1]._action_kind==("skill" if kind=="cast_ex" else ""),kind+" actual stage replaces basic action")
  var violations:=0
  for frame in 15:
   batch=c.advance(0.05)
   var at:float=c.sim.tick*0.05
   stage.update_display(c.sim.units,batch,at,c.sim.tick)
   for e in batch:audio.consume(e)
   audio.update_time(at)
   for h in stage.native_vfx.handle_deadlines():
    if h.actor_id!=1 or h.get("ability","")!="basic" or h.get("cast_start_tick",-1)!=1:continue
    for effect in stage.native_vfx._player._effects:
     if effect.id!=h.id or not effect.node.visible:continue
     for layer in effect.layers:
      for item in layer.particles:
       var born:float=effect.start+(item.birth-effect.clip_in)/effect.speed
       if born>=0.1 and item.node.visible:violations+=1
  ck(violations==0,kind+" actual source basic emits no post-cancel particles")
  if kind=="move":ck(not audio.diagnostics().played.any(func(row):return row.actor_id==1 and row.kind=="basic"),"move cancels actual delayed Aris basic audio")
  else:
   ck(stage.native_props.diagnostics().active_props==1,"manual EX preserves Shiroko native drone")
   ck(audio.diagnostics().played.any(func(row):return row.actor_id==1 and row.kind=="ex"),"manual EX starts native EX audio")
  stage.free();audio.free()
 await process_frame
 print("TACTICAL CANCELLATION CLOCK CHECKS=",checks," FAILURES=",failures)
 quit(1 if failures else 0)
