extends SceneTree
## Real CharacterClock -> BattleStage/UnitView -> scheduler integration.
## Each student exhausts a real one-burst magazine; Hina's same-tick basic
## intentionally replaces her reload state before its sound can start.
const Clock=preload("res://core/character_clock.gd")
const Stage=preload("res://scripts/battle_stage.gd")
const Ordinary=preload("res://scripts/ordinary_combat_audio.gd")
const Skills=preload("res://scripts/native_combat_audio.gd")
const Session=preload("res://core/game_session.gd")
var checks:=0
var failures:=0
var records:Array=[]
func ck(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
 var stage=Stage.new();root.add_child(stage);stage.configure(profiles,[])
 var ordinary=Ordinary.new();ordinary.output_enabled=false;root.add_child(ordinary)
 var skills=Skills.new();skills.output_enabled=false;root.add_child(skills)
 var isolated_skills=Skills.new();isolated_skills.output_enabled=false;root.add_child(isolated_skills)
 stage.ordinary_audio_state.connect(func(record:Dictionary):records.append(record.duplicate(true));ordinary.consume_state(record))
 ck(Session.ACTIVE.size()==14,"all fourteen supported characters are covered")
 ck(Session.ACTIVE.slice(0,13)==["shiroko","hoshino","hina","aru","yuuka","aris","serika","iori","tsubaki","nonomi","mutsuki","haruna","koharu"],"original thirteen roster order preserved")
 ck(Session.ACTIVE[13]=="asuna","Asuna is the only appended audio lifecycle character")
 for character in Session.ACTIVE:
  records.clear()
  var clock=Clock.new();clock.generation=11
  clock.sim.configure([
   {"id":0,"team":0,"character_id":character,"star":1,"cell":Vector2(0,0.7)},
   {"id":1,"team":1,"character_id":"yuuka","star":1,"cell":Vector2(0,-0.7)}
  ],{"seed":77,"random_damage":false})
  clock.sim.start()
  var actor:Dictionary=clock.sim.units[0];var target:Dictionary=clock.sim.units[1]
  actor.ammo=1;actor.aimed=true;actor.basic_ready=100000;actor.skill_ready=100000
  target.hp=10000000;target.max_hp=10000000;target.busy_until=100000;target.basic_ready=100000;target.skill_ready=100000
  stage.set_roster(clock.sim.units,clock.generation,false)
  ordinary.begin_battle(clock.sim.units,clock.generation,77)
  skills.begin_roster(clock.sim.units,clock.generation);isolated_skills.begin_roster(clock.sim.units,clock.generation)
  var attack_event:Dictionary={};var reload_tick:=-1;var replayed:=false
  for _step in range(400):
   var events:Array=clock.advance(0.05)
   for event in events:
    if event.type=="attack" and event.actor_id==0 and attack_event.is_empty():attack_event=event.duplicate(true)
    if event.type=="reload" and event.actor_id==0:
     reload_tick=event.tick;actor.attack_ready=100000
   var at:float=float(clock.sim.tick)*0.05+clock.accumulator
   stage.update_display(clock.sim.units,events,at,clock.sim.tick)
   for event in events:isolated_skills.consume(event);ordinary.consume(event);skills.consume(event)
   ordinary.update_time(at);skills.update_time(at);isolated_skills.update_time(at)
   if not replayed and not attack_event.is_empty():
    var prior:int=ordinary.diagnostics().scheduled_count
    stage.update_display(clock.sim.units,[attack_event],at,clock.sim.tick)
    ck(ordinary.diagnostics().scheduled_count==prior,character+" duplicate real attack batch cannot replay ordinary cue")
    replayed=true
   if reload_tick>=0 and clock.sim.tick>=reload_tick+60:break
  ck(not attack_event.is_empty() and reload_tick>=0,character+" actual simulation produces attack and magazine reload")
  var d:Dictionary=ordinary.diagnostics()
  var entered:Array=records.filter(func(r:Dictionary):return r.type=="enter" and r.actor_id==0)
  var fire:Array=entered.filter(func(r:Dictionary):return r.state_name=="Base Layer.Normal.AttackIng")
  var reloads:Array=entered.filter(func(r:Dictionary):return r.state_name=="Base Layer.Normal.Reload")
  ck(fire.size()==1 and reloads.size()==1,character+" actual fire/reload playback each emits one qualified state")
  var played_fire:Array=d.played.filter(func(c:Dictionary):return c.actor_id==0 and c.state_name=="Base Layer.Normal.AttackIng")
  var played_reload:Array=d.played.filter(func(c:Dictionary):return c.actor_id==0 and c.state_name=="Base Layer.Normal.Reload")
  ck(played_fire.size()==1,character+" selected native fire actually starts one source waveform")
  ck(played_reload.size()==(0 if character=="hina" else 1),character+" real reload sound respects same-tick replacement")
  if fire.size()==1 and played_fire.size()==1:
   var cue:Dictionary=played_fire[0]
   ck(cue.action_id==str(attack_event.event_id) and fire[0].native_clip==profiles[character].clips.attack_fire,character+" cue identity comes from authoritative attack and selected native clip")
   ck(is_equal_approx(cue.start,fire[0].start_time+cue.raw_delay/fire[0].speed) and cue.pitch_scale==1.0,character+" source delay follows actual render speed once with neutral audio pitch")
  if character=="hina" and reloads.size()==1:
   var reload_exits:Array=records.filter(func(r:Dictionary):return r.type=="exit" and r.get("token","")==reloads[0].token)
   ck(reload_exits.size()==1 and is_equal_approx(reload_exits[0].at,float(reload_tick)*0.05) and d.cancelled_state>=1,"Hina real automatic basic cancels reload before scheduler drain")
  ck(d.issues.is_empty() and d.invalid_state_records==0 and d.voice_budget_drops==0,character+" real state path is valid and below voice budget")
  ck(skills.diagnostics()==isolated_skills.diagnostics(),character+" ordinary state bridge leaves EX/basic consumer behavior unchanged")
  ck(d.player_nodes==0,"headless integration creates no device player for "+character)
 # Exercise both skill event categories against the same app-compatible split.
 # Shared native stream caching must not replace either manager's bindings.
 var roster:Array=[{"id":0,"character_id":"shiroko","hp":100},{"id":1,"character_id":"aris","hp":100}]
 ordinary.begin_battle(roster,12,77);skills.begin_roster(roster,12);isolated_skills.begin_roster(roster,12)
 for event in [
  {"type":"skill","ability":"ex","actor_id":0,"tick":20,"generation":12,"event_id":"explicit-ex"},
  {"type":"basic","ability":"basic","actor_id":1,"tick":20,"generation":12,"event_id":"explicit-basic"}
 ]:
  isolated_skills.consume(event);ordinary.consume(event);skills.consume(event)
 for at in [1.0,1.1,1.8,2.5]:ordinary.update_time(at);skills.update_time(at);isolated_skills.update_time(at)
 ck(ordinary.diagnostics().scheduled_count==0,"skill/basic simulation events never synthesize ordinary sounds")
 ck(skills.diagnostics().scheduled_count==2 and skills.diagnostics().played_count==2,"existing Shiroko EX and Aris basic retain their playable source cues")
 ck(skills.diagnostics()==isolated_skills.diagnostics(),"EX/basic timing, pitch, gain and seek stay identical with ordinary manager present")
 var legacy:Dictionary=skills.diagnostics()
 if legacy.played.size()==2:
  ck(legacy.played[0].clip_name=="SFX_Skill_Shiroko_Ex" and is_equal_approx(legacy.played[0].start,1.033333333333333) and legacy.played[0].pitch_scale==1.0,"existing Shiroko EX keeps its distinct source waveform and onset")
  ck(legacy.played[1].clip_name=="SFX_Public_Aris" and is_equal_approx(legacy.played[1].start,1.366666666666667) and is_equal_approx(legacy.played[1].pitch_scale,1.7999999523162842),"existing Aris basic retains source delay and pitch rather than ordinary neutral-pitch policy")
 stage.free();ordinary.free();skills.free();isolated_skills.free();await process_frame
 print("ORDINARY_AUDIO_LIFECYCLE ",checks," checks; ",failures," failures");quit(1 if failures else 0)
