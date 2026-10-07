extends SceneTree
## Verify real combat contact and one rendered firing waveform share a clock.
## Source parameters remain inspectable; multi-hit and echoes do not duplicate bursts.
const Clock=preload("res://core/character_clock.gd")
const View=preload("res://scripts/unit_view.gd")
const Ordinary=preload("res://scripts/ordinary_combat_audio.gd")
var checks:=0
var failures:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",label)
func _initialize():call_deferred("run")
func run():
 var profiles=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
 var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://data/audio/native-ordinary-sfx.json"))
 for character in ["aru","aris","iori","haruna","koharu","shiroko","hina"]:
  var clock=Clock.new();clock.use_combat_mode("tactical_v1");clock.generation=91
  ck(clock.sim.configure([{"id":0,"team":0,"character_id":character,"star":1,"cell":Vector2(0,0.7)},{"id":1,"team":1,"character_id":"yuuka","star":1,"cell":Vector2(0,-0.7)}],{"seed":77,"random_damage":false,"tactical_ai_teams":[],"tactical_damage_scale":0.4,"timeout_total_hp":true,"max_ticks":1800}).is_empty(),character+" tactical fixture")
  clock.sim.start()
  var actor=clock.sim.units[0];var target=clock.sim.units[1]
  actor.aimed=true;actor.basic_ready=100000;actor.skill_ready=100000
  target.hp=10000000;target.max_hp=10000000;target.busy_until=100000;target.basic_ready=100000;target.skill_ready=100000
  var shown=actor.duplicate(true);shown.presentation=profiles[character]
  var view=View.new();root.add_child(view);view.setup(shown,{},91)
  var audio=Ordinary.new();audio.output_enabled=false;root.add_child(audio);audio.begin_battle(clock.sim.units,91,77)
  view.ordinary_audio_state.connect(func(record):audio.consume_state(record))
  var first_attack:Dictionary={};var first_hit:Dictionary={};var contact_count:=0
  for step in range(28):
   var events=clock.advance(0.05)
   # Proposed GameApp ordering: record existing combat event metadata BEFORE rendering.
   for event in events:audio.consume(event)
   for event in events:
    if event.actor_id!=0:continue
    if event.type=="attack" and first_attack.is_empty():first_attack=event.duplicate(true)
    if event.type=="damage" and event.ability=="normal":
     contact_count+=1
     if event.get("component","")!="echo" and first_hit.is_empty():first_hit=event.duplicate(true)
    view.advance_event_time(event.tick*0.05);view.consume(event)
   var at=clock.sim.tick*0.05+clock.accumulator
   view.update_time(at,actor);audio.update_time(at)
  var cues=audio.diagnostics().scheduled.filter(func(c):return c.actor_id==0 and c.state_name=="Base Layer.Normal.AttackIng")
  ck(not first_attack.is_empty() and not first_hit.is_empty(),character+" real attack and authoritative contact exist")
  ck(cues.size()==1,character+" exactly one burst waveform despite "+str(contact_count)+" damage/echo events")
  if cues.size()==1 and not first_hit.is_empty():
   var cue=cues[0];var source=manifest.bindings.filter(func(row):return row.character==character and row.state_name==cue.state_name)[0]
   var contact=first_hit.tick*0.05
   print("CONTACT_SYNC ",character," contact=",contact," audio=",cue.start," delta_ms=",(cue.start-contact)*1000)
   ck(absf(cue.start-contact)<0.00001,character+" firing cue shares the damage/muzzle clock")
   ck(is_equal_approx(cue.raw_delay,source.raw_delay) and cue.pitch_scale==1.0 and is_equal_approx(cue.volume_linear,source.raw_volume),character+" source raw delay/gain and neutral pitch preserved")
   ck(cue.action_id==str(first_attack.event_id),character+" authoritative attack identity retained")
   var count=audio.diagnostics().scheduled_count
   audio.consume(first_attack);view.consume(first_attack);audio.update_time(audio.diagnostics().time)
   ck(audio.diagnostics().scheduled_count==count,character+" duplicate attack cannot replay")
  var prior=audio.diagnostics();audio.update_time(prior.time+2.0,true)
  ck(audio.diagnostics().time==prior.time and audio.diagnostics().played_count==prior.played_count,character+" pause freezes clock without replay")
  audio.reset(92);audio.consume(first_attack);audio.update_time(10.0)
  ck(audio.diagnostics().queued_events==0 and audio.diagnostics().active_voices==0,character+" reset clears cues; stale prior-generation attack cannot revive")
  view.free();audio.free()
 await process_frame
 print("CONTACT_AUDIO_SYNC checks=",checks," failures=",failures)
 quit(1 if failures else 0)
