extends SceneTree
## Real Asuna CharacterClock -> UnitView native clip selection -> unchanged audio schedulers.
const Clock=preload("res://core/character_clock.gd")
const View=preload("res://scripts/unit_view.gd")
const Ordinary=preload("res://scripts/ordinary_combat_audio.gd")
const Skills=preload("res://scripts/native_combat_audio.gd")
var failures:int=0
var checks:int=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",label)
func near(a:float,b:float)->bool:return absf(a-b)<0.000001
func new_clock(star:int=1):
 var clock=Clock.new();clock.generation=11
 clock.sim.configure([{"id":0,"team":0,"character_id":"asuna","star":star,"cell":Vector2(0,0.7)},{"id":1,"team":1,"character_id":"yuuka","star":1,"cell":Vector2(0,-0.7)}],{"seed":77,"random_damage":false})
 clock.sim.start();var target:Dictionary=clock.sim.units[1];target.hp=10000000;target.max_hp=10000000;target.busy_until=100000;target.basic_ready=100000;target.skill_ready=100000
 return clock
func _initialize()->void:call_deferred("run")
func run()->void:
 var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
 var clock=new_clock();var actor:Dictionary=clock.sim.units[0];actor.ammo=1;actor.aimed=true;actor.basic_ready=100000;actor.skill_ready=100000
 var display:Dictionary=actor.duplicate(true);display.presentation=profiles.asuna
 var view=View.new();root.add_child(view);view.setup(display,{},11)
 ck(view.player!=null and view.player.has_animation("Asuna_Original_Normal_Attack_Ing") and view.player.has_animation("Asuna_Original_Normal_Reload"),"actual native Asuna fire/reload animations available")
 var ordinary=Ordinary.new();ordinary.output_enabled=false;root.add_child(ordinary);ordinary.begin_battle(clock.sim.units,11,77)
 var skills=Skills.new();skills.output_enabled=false;root.add_child(skills);skills.begin_roster(clock.sim.units,11)
 ck(ordinary.diagnostics().manifest_events==28,"activation loads exact 28 ordinary state bindings")
 ck(skills.diagnostics().manifest_events==48,"activation loads exact 48 base skill bindings")
 var records:Array=[];view.ordinary_audio_state.connect(func(r):records.append(r.duplicate(true));ordinary.consume_state(r))
 var attack:Dictionary={};var reload_tick:int=-1;var repeated:bool=false;var snapshot_unchanged:bool=true
 for _i in range(300):
  var events:Array=clock.advance(0.05);var before:PackedByteArray=var_to_bytes(clock.sim.snapshot())
  for event in events:
   if event.type=="attack" and event.actor_id==0 and attack.is_empty():attack=event.duplicate(true)
   if event.type=="reload" and event.actor_id==0:reload_tick=event.tick
   view.consume(event);ordinary.consume(event);skills.consume(event)
  var at:float=clock.sim.tick*0.05+clock.accumulator
  view.update_time(at,actor);ordinary.update_time(at);skills.update_time(at)
  snapshot_unchanged=snapshot_unchanged and before==var_to_bytes(clock.sim.snapshot())
  if not repeated and not attack.is_empty():
   var count:int=ordinary.diagnostics().scheduled_count;view.consume(attack);view.update_time(at,actor);ck(ordinary.diagnostics().scheduled_count==count,"duplicate real Asuna attack batch never schedules again");repeated=true
  if reload_tick>=0 and clock.sim.tick>=reload_tick+5:break
 ck(not attack.is_empty() and reload_tick>=0,"actual simulation emits attack and empty-magazine reload")
 ck(snapshot_unchanged,"native view/audio consumption preserves authoritative combat state and RNG")
 var entries:Array=records.filter(func(r):return r.type=="enter")
 var fire:Array=entries.filter(func(r):return r.state_name=="Base Layer.Normal.AttackIng")
 var reloads:Array=entries.filter(func(r):return r.state_name=="Base Layer.Normal.Reload")
 ck(fire.size()==1 and reloads.size()==1,"actual selected Asuna fire and reload each emit one qualified state")
 var played:Array=ordinary.diagnostics().played
 ck(played.size()==2,"actual Asuna state path plays two source waveforms virtually")
 if played.size()==2:
  ck(near(played[0].volume_linear,0.75) and near(played[1].volume_linear,0.9),"source fire/reload gains 0.75 and 0.9")
  ck(played.all(func(c):return near(c.pitch_scale,1.0) and c.raw_delay==0),"unchanged neutral pitch and zero source delay adaptation")
  ck(played[0].action_id==attack.event_id and fire[0].native_clip==profiles.asuna.clips.attack_fire and reloads[0].native_clip==profiles.asuna.clips.reload,"cue joins exact actual native clips and authoritative action ID")
  ck(near(played[0].start,fire[0].start_time) and near(played[1].start,reloads[0].start_time),"ordinary onsets originate from actual selected states")
 ck(ordinary.diagnostics().issues.is_empty() and ordinary.diagnostics().invalid_state_records==0,"Asuna ordinary state bridge has no missing assets or invalid entries")
 var count:int=ordinary.diagnostics().played_count;var now:float=ordinary.diagnostics().time
 ordinary.update_time(now+5,true);ck(ordinary.diagnostics().played_count==count and near(ordinary.diagnostics().time,now),"ordinary pause freezes state time and playback")
 ordinary.update_time(now,false);ck(ordinary.diagnostics().played_count==count,"ordinary resume does not replay")
 ordinary.reset(11);ck(ordinary.diagnostics().queued_events==0 and ordinary.diagnostics().active_voices==0 and ordinary.diagnostics().state_records==0,"same-generation ordinary reset clears all old state")
 if not fire.is_empty():
  ordinary.begin_battle(clock.sim.units,12,77);ordinary.consume_state(fire[0]);ck(ordinary.diagnostics().scheduled_count==0,"stale actual Asuna state is rejected")
 ck(ordinary.diagnostics().player_nodes==0,"headless ordinary test creates no device player")
 view.free();ordinary.free()
 # Generate a real EX event; skill scheduling must not depend on body/damage time.
 clock=new_clock(2);actor=clock.sim.units[0];actor.aimed=true;actor.attack_ready=100000;actor.basic_ready=100000;actor.skill_ready=0
 var cast:Dictionary={}
 for _i in range(10):
  for event in clock.advance(0.05):
   if event.type=="skill" and event.actor_id==0:cast=event.duplicate(true)
  if not cast.is_empty():break
 ck(not cast.is_empty() and cast.get("ability","")=="ex","actual Asuna simulation supplies the base EX trigger")
 skills.begin_roster(clock.sim.units,11)
 var before:PackedByteArray=var_to_bytes(clock.sim.snapshot());skills.consume(cast);skills.consume(cast)
 ck(before==var_to_bytes(clock.sim.snapshot()),"EX scheduler cannot mutate actual combat/RNG snapshot")
 var d:Dictionary=skills.diagnostics();ck(d.scheduled_count==3 and d.duplicates==1,"real EX cast schedules three exact cues once")
 if d.scheduled.size()==3:
  var origin:float=cast.tick*0.05;var ex2:Dictionary={};var early:int=0;var late:int=0
  for cue in d.scheduled:
   if near(cue.start-origin,0.2666666666667):early+=1
   if near(cue.start-origin,1.8333333333333):late+=1
   if cue.clip_name=="SFX_Skill_Asuna_Ex_02":ex2=cue
  ck(early==1 and late==2,"EX has one early and two simultaneous exact source onsets")
  ck(not ex2.is_empty() and near(ex2.pitch_scale,0.699999988079071) and near(ex2.volume_linear,0.5),"Ex02 source positive pitch and linear gain preserved")
  ck(not ex2.is_empty() and near(ex2.end-origin,3.158697787391036),"natural adapted Ex02 tail survives source track end2.7")
  skills.update_time(origin+1.9);d=skills.diagnostics();ck(d.played_count==2 and d.skipped_ended==1,"late update skips ended early cue and starts both later cues")
  for cue in d.played:ck(near(cue.seek_seconds,(origin+1.9-cue.start)*cue.pitch_scale),"late seek follows source pitch")
  count=d.played_count;skills.update_time(origin+2.0,true);skills.update_time(origin+1.9,false);ck(skills.diagnostics().played_count==count,"EX pause/resume never replays")
  skills.consume({"type":"death","actor_id":0,"tick":int(ceil((origin+2.0)/0.05)),"generation":11});skills.update_time(origin+2.1);ck(skills.diagnostics().active_voices==0,"death stops both active EX tails")
 skills.reset(11);ck(skills.diagnostics().queued_events==0 and skills.diagnostics().active_voices==0,"EX reset clears all cues")
 skills.begin_roster(clock.sim.units,11);skills.consume(cast);skills.consume({"type":"death","actor_id":0,"tick":cast.get("tick",0),"generation":11});skills.update_time(20);ck(skills.diagnostics().played_count==0,"death before EX onset cancels all three")
 skills.begin_roster(clock.sim.units,12);skills.consume(cast);ck(skills.diagnostics().scheduled_count==0,"stale EX event is rejected")
 skills.begin_roster(clock.sim.units,11)
 for kind in ["basic","damage","GetMouthTile","reload","cutin"]:skills.consume({"type":kind,"ability":"basic","actor_id":0,"tick":0,"generation":11})
 ck(skills.diagnostics().scheduled_count==0,"basic prefab secondary reload cutin mouth damage remain unscheduled")
 ck(skills.diagnostics().player_nodes==0,"headless EX test creates no device player")
 skills.free();await process_frame
 print("ASUNA_AUDIO_ACTIVATION ",checks," checks; ",failures," failures");quit(1 if failures else 0)
