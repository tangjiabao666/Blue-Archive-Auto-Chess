extends SceneTree
class MalformedManifest extends "res://scripts/ordinary_combat_audio.gd":
 var fixture:Dictionary={}
 func _read_manifest_data()->Variant:return fixture
var checks:=0
var failures:=0
var Audio
var manifest:Dictionary
func ck(value:bool,label:String):
 checks+=1
 if not value:failures+=1;printerr("FAIL: ",label)
func entry(character:String="shiroko",state:String="Base Layer.Normal.AttackIng",at:float=1.0,speed:float=1.0,ending:float=4.0,token:String="attack:20")->Dictionary:
 var rows:Array=manifest.bindings.filter(func(r):return r.character==character and r.state_name==state)
 return {"type":"enter","actor_id":0,"character_id":character,"generation":4,"token":token,"action_id":token,"state_name":state,"native_clip":rows[0].native_clip,"start_time":at,"source_offset":0.0,"speed":speed,"planned_end_time":ending}
func fresh(character:String="shiroko",seed:int=77):
 var audio=Audio.new();root.add_child(audio);audio.output_enabled=false;audio.begin_battle([{"id":0,"character_id":character,"hp":100}],4,seed);return audio
func _initialize():call_deferred("run")
func run():
 ck(ResourceLoader.exists("res://scripts/ordinary_combat_audio.gd"),"ordinary scheduler exists")
 if failures:quit(1);return
 Audio=load("res://scripts/ordinary_combat_audio.gd");manifest=JSON.parse_string(FileAccess.get_file_as_string("res://data/audio/native-ordinary-sfx.json"))
 var audio=fresh();var e:Dictionary=entry();var before:Dictionary=e.duplicate(true);audio.consume_state(e)
 ck(e==before,"entry input unchanged")
 var d:Dictionary=audio.diagnostics();ck(d.manifest_events==28,"all Normal bindings loaded")
 ck(d.scheduled_count==1 and d.scheduled[0].start==1.0,"zero raw delay anchored to state")
 ck(d.scheduled[0].pitch_scale==1.0 and is_equal_approx(d.scheduled[0].volume_linear,0.57),"neutral pitch and declared raw gain")
 audio.consume_state(e);ck(audio.diagnostics().scheduled_count==1,"duplicate state cannot replay")
 audio.update_time(1.1);ck(audio.diagnostics().played_count==1 and is_equal_approx(audio.diagnostics().played[0].seek_seconds,0.1),"late update seeks into original sample")
 audio.update_time(1.1);ck(audio.diagnostics().played_count==1,"same clock does not replay")
 var selected:Dictionary=audio.diagnostics().choices[0]
 ck(selected.pool_index==0,"SHA256 pool choice matches independent golden vector")
 audio.free()
 var peer=fresh();peer.max_voices=0;peer.consume_state(e);peer.update_time(1.1)
 ck(peer.diagnostics().choices[0]==selected,"voice budget does not alter pool choice")
 ck(peer.diagnostics().voice_budget_drops==1,"bounded voice drop")
 peer.free()
 audio=fresh("aru");e=entry("aru","Base Layer.Normal.AttackIng",2.0,2.0,4.0)
 audio.consume_state(e);ck(is_equal_approx(audio.diagnostics().scheduled[0].start,2.33),"explicit source-time delay divided by phase speed once")
 audio.update_time(2.5,true);ck(audio.diagnostics().played_count==0 and audio.diagnostics().time==0.0,"pause does not advance or start sound")
 audio.update_time(2.5,false);ck(audio.diagnostics().played_count==1 and is_equal_approx(audio.diagnostics().played[0].seek_seconds,0.17),"resume late-seeks without second contact delay")
 audio.update_time(2.0);ck(audio.diagnostics().rewinds_rejected==1 and audio.diagnostics().time==2.5,"rewind requires reset")
 audio.reset(4);ck(audio.diagnostics().active_voices==0 and audio.diagnostics().queued_events==0 and audio.diagnostics().choices.is_empty(),"reused generation resets all states")
 audio.free()
 audio=fresh("hina");e=entry("hina","Base Layer.Normal.Reload",1.0,1.0,3.0,"reload:20")
 audio.consume_state(e);audio.consume_state({"type":"exit","actor_id":0,"generation":4,"token":"reload:20","at":1.0,"reason":"same_tick_basic"});audio.update_time(1.1)
 ck(audio.diagnostics().played_count==0 and audio.diagnostics().cancelled_state==1,"same-tick Hina reload is silent")
 audio.free()
 audio=fresh("aru");e=entry("aru","Base Layer.Normal.AttackIng",1.0,1.0,1.5)
 audio.consume_state(e);audio.update_time(1.7);ck(audio.diagnostics().played_count==0,"planned phase end cancels onset outside phase even without exit signal")
 audio.free()
 audio=fresh();e=entry();audio.consume_state(e);audio.consume_state({"type":"exit","actor_id":0,"generation":4,"token":e.token,"at":1.05,"reason":"ordinary_exit"});audio.update_time(1.1)
 ck(audio.diagnostics().played_count==1,"a logically fired cue keeps natural tail after state exit")
 audio.consume({"type":"death","actor_id":0,"generation":4,"tick":23});audio.update_time(23.0*0.05)
 ck(audio.diagnostics().active_voices==0,"death stops active tails")
 audio.free()
 audio=fresh();e=entry();e.generation=3;audio.consume_state(e)
 ck(audio.diagnostics().scheduled_count==0,"stale generation ignored")
 e=entry();e.native_clip="wrong";audio.consume_state(e);ck(audio.diagnostics().scheduled_count==0,"wrong rendered clip cannot use source binding")
 for field in ["speed","source_offset","start_time","planned_end_time"]:
  e=entry();e[field]=NAN;audio.consume_state(e)
 ck(audio.diagnostics().scheduled_count==0,"invalid numeric state fails closed")
 e=entry();e.source_offset=0.2;audio.consume_state(e);ck(audio.diagnostics().scheduled_count==0,"unsupported source offset remains silent")
 audio.free()
 for character in ["shiroko","hoshino","hina","aru","yuuka","aris","serika","iori","tsubaki","nonomi","mutsuki","haruna","koharu","asuna"]:
  audio=fresh(character)
  for state in ["Base Layer.Normal.AttackIng","Base Layer.Normal.Reload"]:
   e=entry(character,state,1.0,1.0,5.0,state);audio.consume_state(e)
  ck(audio.diagnostics().scheduled_count==2,character+" two source states resolve")
  ck(audio.diagnostics().issues.is_empty(),character+" no missing source resources")
  audio.free()
 # Exit may arrive before its entry; known cancellation still wins.
 audio=fresh("aru");e=entry("aru","Base Layer.Normal.AttackIng",1.0,1.0,4.0)
 audio.consume_state({"type":"exit","actor_id":0,"generation":4,"token":e.token,"at":1.2,"reason":"interrupted"});audio.consume_state(e);audio.update_time(2.0)
 ck(audio.diagnostics().played_count==0 and audio.diagnostics().cancelled_state==1,"early exit ledger prevents delayed replay")
 audio.free()
 audio=fresh();e=entry();audio.consume_state(e);audio.consume_state({"type":"exit","actor_id":0,"generation":4,"token":e.token,"at":2.0,"reason":"future"});audio.update_time(1.1)
 ck(audio.diagnostics().played_count==1 and audio.diagnostics().active_voices==1,"future exit does not stop an already valid tail early")
 audio.free()
 audio=fresh("aru");e=entry("aru");audio.consume_state(e);audio.consume({"type":"death","actor_id":0,"generation":4,"tick":25});audio.update_time(2.0)
 ck(audio.diagnostics().played_count==0,"death before delayed onset remains silent")
 audio.free()
 audio=fresh();audio.max_queued_events=0;audio.consume_state(entry());ck(audio.diagnostics().choices[0]==selected and audio.diagnostics().queue_budget_drops==1,"queue drop retains the same deterministic choice")
 audio.free()
 audio=fresh();audio.max_seen_actions=0;audio.consume_state(entry());ck(audio.diagnostics().state_records==0 and audio.diagnostics().scheduled_count==0,"state budget fails closed")
 audio.free()
 audio=fresh();audio.consume_state(entry());var choice:Dictionary=audio.diagnostics().choices[0]
 audio.begin_battle([{"id":0,"character_id":"shiroko","hp":100}],5,77);e=entry();e.generation=5;e.token="new-generation-token";audio.consume_state(e)
 ck(audio.diagnostics().choices[0]==choice,"generation/token changes do not perturb same replay action choice")
 audio.free()
 var sim=load("res://core/character_sim.gd").new();sim.configure([{"id":0,"team":0,"character_id":"shiroko","star":1,"cell":Vector2(0,1)},{"id":1,"team":1,"character_id":"yuuka","star":1,"cell":Vector2(0,-1)}],{"seed":77});sim.start()
 var snapshot:Dictionary=sim.snapshot();audio=fresh()
 for i in range(10):audio.consume_state(entry("shiroko","Base Layer.Normal.AttackIng",i+1.0,1.0,i+3.0,"attack:%d"%i));audio.update_time(i+1.1)
 ck(sim.snapshot()==snapshot,"audio cannot mutate authoritative state or combat RNG")
 audio.free()
 for invalid in [{},[],true,1.5,-1,INF,1.0e30,null]:
  var malformed=MalformedManifest.new();malformed.fixture=manifest.duplicate(true);malformed.fixture.assets.SFX_Common_AR_01.frames=invalid;root.add_child(malformed);malformed.output_enabled=false;malformed.begin_battle([{"id":0,"character_id":"shiroko","hp":100}],4,77)
  ck(malformed.diagnostics().issues.has("invalid_ordinary_asset_metadata:SFX_Common_AR_01"),"malformed frames diagnosed without exception")
  ck(malformed.diagnostics().manifest_events==25,"bad AR asset only disables its three dependent pools")
  malformed.free()
 var duplicate=MalformedManifest.new();duplicate.fixture=manifest.duplicate(true);duplicate.fixture.bindings.append(duplicate.fixture.bindings[0].duplicate(true));duplicate.fixture.bindings.append(duplicate.fixture.bindings[0].duplicate(true));root.add_child(duplicate);duplicate.output_enabled=false;duplicate.begin_battle([{"id":0,"character_id":"shiroko","hp":100}],4,77)
 ck(duplicate.diagnostics().manifest_events==27,"any duplicate binding count fails closed")
 duplicate.free()
 print("ORDINARY_COMBAT_AUDIO ",checks," checks; ",failures," failures");quit(1 if failures else 0)
