extends SceneTree
var checks:=0
var failures:=0
var audio_script:Script
const UNITS=[{"id":1,"character_id":"shiroko"},{"id":2,"character_id":"hoshino"},{"id":3,"character_id":"hina"},{"id":4,"character_id":"aru"},{"id":5,"character_id":"yuuka"},{"id":6,"character_id":"aris"},{"id":7,"character_id":"serika"},{"id":8,"character_id":"shiroko"}]
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func near(a:float,b:float)->bool:return absf(a-b)<0.00001
func event(actor:int,tick:int=100,kind:String="ex",gen:int=8,id:String="")->Dictionary:
 return {"type":"skill" if kind=="ex" else "basic","ability":kind,"actor_id":actor,"tick":tick,"generation":gen,"event_id":id if not id.is_empty() else "%d:%d:%s"%[actor,tick,kind],"recovery_ticks":1}
func make_player(enabled:bool=false):
 var p=audio_script.new();p.output_enabled=enabled;root.add_child(p);p.begin_roster(UNITS,8);return p
func _initialize()->void:call_deferred("run")
func run()->void:
 ck(ResourceLoader.exists("res://scripts/native_combat_audio.gd"),"native combat audio module exists")
 if failures:print("COMBAT_AUDIO_TESTS ",checks," checks; ",failures," failures");quit(1);return
 audio_script=load("res://scripts/native_combat_audio.gd")
 test_onset_and_natural_duration()
 test_late_catchup_and_skips()
 test_exact_source_parameters()
 test_only_safe_live_bindings()
 test_generation_death_and_reset()
 test_pause_and_rewind()
 test_detach_and_death_budget()
 test_budgets_and_real_output()
 # Allow the threaded AudioServer to retire stopped playback under loaded CI.
 # One rendered frame or a 0.1s timer is insufficient during software rendering.
 await create_timer(1.0).timeout
 print("COMBAT_AUDIO_TESTS ",checks," checks; ",failures," failures");quit(1 if failures else 0)
func test_onset_and_natural_duration()->void:
 var p=make_player();var e=event(1)
 p.consume(e);p.consume(e);e.event_id="different-id-same-action";p.consume(e)
 var d:Dictionary=p.diagnostics()
 ck(d.scheduled_count==1 and d.duplicates==2,"duplicate IDs and duplicate action identity schedule only once")
 ck(d.player_nodes==0 and d.played_count==0,"silent mode and consume never start audio")
 ck(near(d.scheduled[0].start,5.033333333333333),"source onset uses tick plus source start, independent of recovery")
 p.update_time(5.02,false);ck(p.diagnostics().played_count==0,"audio does not start early")
 p.update_time(5.033333333333333,false);d=p.diagnostics()
 ck(d.played_count==1 and near(d.played[0].seek_seconds,0),"source onset starts at clip zero")
 p.update_time(6.0,false);ck(p.diagnostics().active_voices==1,"short native track window is not forced sample stop")
 p.update_time(10.3,false);ck(p.diagnostics().active_voices==0,"natural sample end releases virtual voice")
 p.consume(event(1));p.update_time(10.3,false);ck(p.diagnostics().played_count==1,"expired duplicate never replays")
 p.free()
func test_late_catchup_and_skips()->void:
 var p=make_player();p.consume(event(1));p.update_time(6.2,false)
 var d:Dictionary=p.diagnostics()
 ck(d.played_count==1 and near(d.played[0].seek_seconds,1.166666666666667),"late frame starts at elapsed sample position")
 p.free();p=make_player();p.consume(event(1));p.update_time(50,false);d=p.diagnostics()
 ck(d.played_count==0 and d.skipped_ended==1 and d.queued_events==0,"late frame skips already ended sample")
 p.free();p=make_player();p.consume(event(6,20,"basic"));p.update_time(2.0,false);d=p.diagnostics()
 ck(d.played_count==1 and near(d.played[0].seek_seconds,1.1399999698003134),"late seeking scales by native Aris pitch")
 p.free()
func test_exact_source_parameters()->void:
 var p=make_player();var e=event(7)
 e.clipIn=2.0;e.action_window={"start":2.0,"clipIn":2.0};p.consume(e);p.update_time(5.033333333333333,false)
 var d:Dictionary=p.diagnostics()
 ck(d.played_count==1 and near(d.played[0].seek_seconds,0),"Serika audio clipIn remains zero independently of body clipIn two")
 ck(near(d.played[0].volume_linear,0.800000011920929),"Serika native gain preserved")
 p.update_time(6.5,false);ck(p.diagnostics().active_voices==1,"Serika sample outlives track window and recovery ticks")
 p.free();p=make_player();p.consume(event(3));p.update_time(5.8,false);d=p.diagnostics()
 ck(d.played_count==2,"Hina preserves two exact source cues")
 ck(near(d.played[0].pitch_scale,1.100000023841858) and near(d.played[1].volume_linear,0.20000000298023224),"Hina native pitch and quiet secondary gain preserved")
 p.free()
func test_only_safe_live_bindings()->void:
 var p=make_player()
 for id in range(1,8):p.consume(event(id));p.consume(event(id,100,"basic"))
 for kind in ["damage","miss","reload","attack","cutin"]:
  var e=event(1,101);e.type=kind;p.consume(e)
 p.consume(event(6,101,"basic_enhanced"))
 var d:Dictionary=p.diagnostics()
 ck(d.manifest_events==JSON.parse_string(FileAccess.get_file_as_string("res://data/audio/native-skill-sfx.json")).records.size() and d.scheduled_count==12,"exact live coverage: eleven EX and Aris basic, no voices, gun, pools, cutins, enhanced or negative-pitch cues")
 p.update_time(5.05,false);ck(p.diagnostics().played_count==4,"only Shiroko, Hoshino, Hina and Serika immediate cues start")
 p.update_time(11.567,false);d=p.diagnostics()
 ck(d.played.any(func(x):return x.clip_name=="SFX_Skill_Hoshino_Ex_Shield_Drop"),"delayed Hoshino EX cue not cut off by short sim recovery")
 p.free()
func test_generation_death_and_reset()->void:
 var p=make_player();p.consume(event(1,100,"ex",7));p.consume({"type":"death","actor_id":1,"tick":100,"generation":7});p.update_time(5.1,false)
 ck(p.diagnostics().played_count==0 and p.diagnostics().stale_events==2,"stale cast and stale death both rejected")
 p.consume(event(1));p.update_time(5.2,false);ck(p.diagnostics().active_voices==1,"stale death did not poison current roster")
 p.consume({"type":"death","actor_id":1,"tick":105,"generation":8});p.update_time(5.2,false)
 ck(p.diagnostics().active_voices==1,"future death does not stop sound before death tick")
 p.update_time(5.25,false);ck(p.diagnostics().active_voices==0,"death stops active audio at its tick")
 p.consume(event(1,106));p.update_time(5.4,false);ck(p.diagnostics().played_count==1,"dead actor cannot start new audio")
 p.free();p=make_player();p.consume(event(2));p.consume({"type":"death","actor_id":2,"tick":100,"generation":8});p.update_time(20,false)
 ck(p.diagnostics().played_count==0 and p.diagnostics().queued_events==0,"death batch suppresses all late phantom and future cast sounds")
 p.reset(9);ck(p.diagnostics().active_voices==0 and p.diagnostics().scheduled_count==0,"reset clears playback and diagnostic generation")
 p.consume(event(2,0,"ex",9));p.update_time(1,false);ck(p.diagnostics().played_count==0,"reset alone clears old roster")
 p.begin_roster(UNITS,10);p.consume(event(1,0,"ex",8));p.update_time(1,false)
 ck(p.diagnostics().played_count==0,"new generation prevents old events from leaking")
 p.free()
func test_pause_and_rewind()->void:
 var p=make_player();p.consume(event(1));p.update_time(5.0,false);p.update_time(8.0,true)
 ck(p.diagnostics().played_count==0 and near(p.diagnostics().time,5.0),"paused update freezes logical time and does not drain pending clips")
 p.update_time(5.1,false);var d:Dictionary=p.diagnostics();ck(d.played_count==1,"resume starts pending clip once")
 p.update_time(5.1,true);p.update_time(5.1,true);p.update_time(5.1,false)
 ck(p.diagnostics().played_count==1,"repeated pause and resume never replay active sound")
 p.update_time(1,false);ck(near(p.diagnostics().time,5.1) and p.diagnostics().rewinds_rejected==1,"rewind is rejected until explicit generation reset")
 p.update_time(NAN,false);ck(near(p.diagnostics().time,5.1),"invalid time cannot poison scheduler")
 p.free()
func test_budgets_and_real_output()->void:
 var p=make_player();p.max_queued_events=1;p.consume(event(2));ck(p.diagnostics().queued_events==1 and p.diagnostics().queue_budget_drops==2,"pending sound budget caps delayed cues")
 p.free();p=make_player(true);p.max_voices=1
 p.consume(event(1));p.consume(event(8));p.update_time(5.1,false)
 var d:Dictionary=p.diagnostics();ck(d.player_nodes==1 and d.active_voices==1 and d.voice_budget_drops==1,"real audio node and active-voice budget enforced")
 var player=p.get_child(0) as AudioStreamPlayer
 ck(player!=null and player.stream is AudioStreamWAV and player.playing,"packaged imported WAV actually reaches AudioStreamPlayer")
 var first_stream=player.stream
 ck(near(player.pitch_scale,1) and near(player.volume_linear,1),"player receives unprocessed native parameters")
 p.update_time(5.1,true);ck(player.stream_paused,"pause suspends real audio output")
 p.update_time(1,false);ck(player.stream_paused and p.diagnostics().paused,"rejected backwards unpause keeps actual voice paused")
 p.update_time(5.1,false);ck(not player.stream_paused,"resume unsuspends same voice")
 p.update_time(20,false);ck(not player.playing,"natural end stops actual player")
 p.consume(event(8,400));p.update_time(20.1,false)
 ck(p.get_child_count()==1 and player.stream==first_stream,"player is pooled and immutable stream shared between plays")
 p.output_enabled=false;ck(not player.playing,"disabling output stops real sound immediately")
 p.reset(9);ck(not player.playing and p.diagnostics().active_voices==0,"reset cannot leak pooled audio")
 p.free();p=make_player();p.max_seen_actions=1;p.consume(event(1));p.consume(event(2));p.consume(event(1));p.update_time(5.1,false)
 ck(p.diagnostics().scheduled_count==1 and p.diagnostics().seen_budget_drops==1 and p.diagnostics().duplicates==1,"bounded dedup never evicts identities into replay")
 p.free();p=make_player();p.max_voices=-1;p.max_queued_events=-1;p.consume(event(1));p.update_time(6,false)
 ck(p.diagnostics().active_voices==0 and p.diagnostics().queued_events==0,"negative budgets safely disable work")
 p.free()

func test_detach_and_death_budget()->void:
 var p=make_player(true);p.consume(event(2));p.update_time(5.1,false)
 var player=p.get_child(0) as AudioStreamPlayer
 root.remove_child(p)
 ck(not player.playing and p.diagnostics().queued_events==0 and p.diagnostics().active_voices==0,"tree exit stops actual voice and cancels delayed cues")
 root.add_child(p);p.update_time(10,false)
 ck(p.diagnostics().played_count==0,"reattached node cannot play old battle audio")
 p.free();p=make_player();p.max_queued_events=1;p.consume(event(2))
 p.consume({"type":"death","actor_id":2,"tick":0,"generation":8})
 p.consume(event(1));p.update_time(5.1,false)
 ck(p.diagnostics().played_count==1 and p.diagnostics().played[0].character=="shiroko","due death releases pending capacity before next live cast")
 p.reset(8);p.update_time(30,false)
 ck(p.diagnostics().queued_events==0 and p.diagnostics().active_voices==0 and p.diagnostics().played_count==0,"same-generation reset cancels all past and future cues")
 p.free()
