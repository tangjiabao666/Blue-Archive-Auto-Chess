extends SceneTree
## Only successful native Normal state selections are observable audio instances.
const View=preload("res://scripts/unit_view.gd")
const Stage=preload("res://scripts/battle_stage.gd")
const Bridge=preload("res://scripts/ordinary_audio_state_bridge.gd")
const GOLDEN="res://tests/fixtures/ordinary_audio_pose_baseline.json"
var checks:=0
var failures:=0
var profiles:Dictionary
var records:Array=[]
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize():call_deferred("run")
func unit(key:String)->Dictionary:
 return {"id":4,"character_id":key,"star":1,"team":0,"cell":Vector2(1,2),"range":3.0,"attack_ticks":54,"aimed":true,"hp":100,"max_hp":100,"presentation":profiles[key]}
func view_for(key:String):
 var view=View.new();root.add_child(view);view.setup(unit(key),{},7)
 if view.has_signal("ordinary_audio_state"):view.connect("ordinary_audio_state",func(record:Dictionary):records.append(record.duplicate(true)))
 return view
func event(kind:String,tick:int,id:String="")->Dictionary:
 var result:Dictionary={"type":kind,"actor_id":4,"generation":7,"tick":tick,"target_cell":Vector2(0,-2),"burst_ticks":14,"recovery_ticks":54,"duration_ticks":30,"impact_tick":tick+1}
 if not id.is_empty():result.event_id=id
 return result
func entries()->Array:return records.filter(func(r:Dictionary):return r.get("type","")=="enter")
func exits()->Array:return records.filter(func(r:Dictionary):return r.get("type","")=="exit")
func test_bursts_and_duplicates()->void:
 records.clear();var view=view_for("shiroko")
 ck(view.has_signal("ordinary_audio_state"),"UnitView exposes qualified ordinary state signal")
 var first:=event("attack",20,"shot-one")
 view.consume(first)
 for at in [1.01,1.02,1.1]:view.update_time(at,unit("shiroko"))
 view.consume(first.duplicate(true))
 ck(entries().size()==1 and exits().is_empty(),"duplicate event and repeated frames neither replay nor cancel original state")
 if entries().size()==1:
  var enter:Dictionary=entries()[0]
  for field in ["actor_id","character_id","generation","token","action_id","state_name","native_clip","start_time","source_offset","speed","planned_end_time"]:ck(enter.has(field),"entry field "+field)
  ck(enter.actor_id==4 and enter.character_id=="shiroko" and enter.generation==7,"identity preserved")
  ck(enter.state_name=="Base Layer.Normal.AttackIng" and enter.native_clip==String(view.ATTACK_FIRE),"fire qualifies by semantic phase and exact native clip")
  ck(is_equal_approx(enter.start_time,1.0) and is_equal_approx(enter.planned_end_time,1.7) and enter.source_offset==0.0,"fire bounds use logical native burst phase")
  ck(is_equal_approx(enter.speed,view.player.get_animation(view.ATTACK_FIRE).length/0.7),"reported speed is actual playback speed")
 view.update_time(8.0,unit("shiroko"))
 ck(exits().size()==1 and is_equal_approx(exits()[0].at,1.7),"large update closes at planned fire boundary, not observed frame")
 view.consume(event("attack",180,"shot-two"))
 ck(entries().size()==2,"second same-clip authoritative burst is a new instance")
 if entries().size()==2:ck(entries()[0].token!=entries()[1].token and entries()[0].action_id!=entries()[1].action_id,"tokens and action identity distinguish same clip bursts")
 view.free()
 # Legacy untagged event duplicate replay can alter presentation, but cannot replay audio.
 records.clear();view=view_for("shiroko");first=event("attack",20)
 view.consume(first);view.consume(first.duplicate(true))
 ck(entries().size()==1 and exits().is_empty(),"missing event_id uses stable fallback without cancelling original cue")
 view.free()
func test_reload_replacement_and_lifecycle()->void:
 records.clear();var view=view_for("hina")
 view.consume(event("reload",20,"hina-reload"));view.consume(event("basic",20,"hina-basic"))
 ck(entries().size()==1 and exits().size()==1,"Hina same-tick basic replaces one actual reload state")
 if entries().size()==1 and exits().size()==1:
  ck(entries()[0].state_name=="Base Layer.Normal.Reload","reload binding remains Normal.Reload")
  ck(is_equal_approx(exits()[0].at,1.0),"Hina reload ends at replacement tick, before future basic logical start")
  ck(exits()[0].token==entries()[0].token and exits()[0].reason=="replaced","replacement closes the same state token")
 ck(is_equal_approx(view._clip_started_at,1.0+float(profiles.hina.action_windows.basic.start)),"Hina source basic offset is unchanged")
 view.free()
 records.clear();view=view_for("shiroko")
 view.consume(event("reload",20,"reload"));view.update_time(9.0,unit("shiroko"))
 ck(exits().size()==1 and is_equal_approx(exits()[0].at,2.5),"skipped reload completion emits planned end")
 view.consume(event("attack",200,"death-shot"));view.consume(event("death",201,"death"))
 ck(exits().size()==2 and is_equal_approx(exits()[1].at,10.05) and exits()[1].reason=="death","death interrupts active ordinary state")
 view.consume(event("attack",220,"dead-shot"));ck(entries().size()==2,"dead actor cannot enter an ordinary state")
 view.setup(unit("shiroko"),{},7);view.consume(event("attack",20,"reload"))
 ck(entries().size()==3,"same generation setup clears old dedup state")
 view.setup(unit("shiroko"),{},7)
 ck(exits().size()==3 and exits()[2].reason=="reset","reset closes active state even when generation number repeats")
 view.consume(event("attack",20,"reload"))
 ck(entries().size()==4,"reused-generation reset permits replayed authoritative event")
 var count:int=records.size();var stale:=event("reload",22,"stale");stale.generation=6;view.consume(stale)
 ck(records.size()==count,"stale generation cannot mutate ordinary state ledger")
 view.free()
func test_missing_and_unqualified_clips()->void:
 records.clear();var view=view_for("shiroko")
 view.ATTACK_FIRE=&"Missing_Ordinary_Fire";view.RELOAD=&"Missing_Ordinary_Reload"
 view.consume(event("attack",20,"missing-fire"));view.consume(event("reload",40,"missing-reload"))
 ck(entries().is_empty(),"unavailable native clips never emit ordinary entries")
 view.free();records.clear();view=view_for("shiroko");view.player=null
 view.consume(event("attack",20,"no-player"));view.consume(event("reload",40,"no-player-reload"))
 ck(entries().is_empty(),"missing native player never emits ordinary entries")
 view.free();records.clear();view=view_for("aris")
 view.consume(event("aim",0,"aim"));view.update_time(1.6,unit("aris"))
 ck(entries().is_empty(),"aim and ready AttackDelay clip reuse remain silent")
 view.consume(event("attack",40,"fire"));view.update_time(3.0,unit("aris"));view.update_time(10.0,unit("aris"))
 ck(entries().size()==1,"AttackDelay and absent AttackEnd do not manufacture entries")
 view.free()
func timeline(key:String,steps:Array)->Array:
 records.clear();var view=view_for(key)
 view.consume(event("attack",20,"frame-independent"))
 for at in steps:view.update_time(at,unit(key))
 var result:=records.duplicate(true);view.free();return result
func test_partition_and_all_profiles()->void:
 for key in profiles:
  var small:=timeline(key,[1.1,1.4,1.7,2.0,8.0]);var large:=timeline(key,[8.0])
  ck(small==large,key+" tokens and boundaries are frame-partition independent")
  ck(small.size()==2 and small[0].native_clip==profiles[key].clips.attack_fire,key+" real ordinary fire maps to selected native clip")
  records.clear();var view=view_for(key);view.consume(event("reload",20,"reload"))
  ck(entries().size()==1 and entries()[0].native_clip==profiles[key].clips.reload,key+" real ordinary reload maps to selected native clip")
  view.free()
func interrupted_by_move(at:float)->Array:
 records.clear();var view=view_for("shiroko")
 view.consume(event("attack",20,"moving-shot"))
 var move:=event("move",22,"move");move.from=Vector2(1,2);move.to=Vector2(1,0);move.duration=1.0
 view.consume(move);view.update_time(at,unit("shiroko"))
 var result:=records.duplicate(true);view.free();return result
func test_deferred_move_interruption()->void:
 var fine:=interrupted_by_move(1.2);var coarse:=interrupted_by_move(1.8)
 ck(fine==coarse,"deferred move interruption is independent of frame partition")
 ck(coarse.size()==2 and is_equal_approx(coarse[1].at,1.1),"accepted move preempts the previous ordinary action at its event tick")
func test_stage_forwarding()->void:
 records.clear();var stage=Stage.new();root.add_child(stage);stage.configure(profiles,[])
 ck(stage.has_signal("ordinary_audio_state"),"Stage exposes and forwards ordinary state signal")
 if stage.has_signal("ordinary_audio_state"):stage.connect("ordinary_audio_state",func(record:Dictionary):records.append(record.duplicate(true)))
 var roster:Array=[unit("serika")];stage.set_roster(roster,7,false)
 var skill:=event("skill",20,"serika-ex");var reload:=event("reload",20,"serika-ex-reload");reload.via_ex=true
 stage.update_display(roster,[skill,reload],1.0)
 ck(entries().is_empty(),"Serika via_ex reload remains suppressed at Stage")
 var ordinary:=event("attack",120,"ordinary");stage.update_display(roster,[ordinary],6.0)
 stage.update_display(roster,[ordinary],6.1)
 ck(entries().size()==1 and exits().is_empty(),"Stage forwards actual ordinary selection once despite duplicate batch")
 stage.set_roster(roster,7,false)
 ck(exits().size()==1 and exits()[0].reason=="reset","Stage replacement closes old actor state even in reused generation")
 stage.update_display(roster,[ordinary],6.0);ck(entries().size()==2,"Stage reused generation permits replay after replacement")
 stage.free()
func pose_digest(view)->String:
 var pose:Array=[view.position,view.rotation,view.state,String(view.current_clip),view.is_dead,view.is_moving,view.visible,view._action_kind,view._action_started_at,view._action_ends_at,view._clip_started_at,view._clip_offset,view._clip_speed,view._clip_elapsed,view._clip_revision,view.player.current_animation_position,view.hit_position(),view.muzzle_transform()]
 for node in view._model.find_children("*","Node3D",true,false):
  pose.append([node.get_class(),node.transform,node.visible])
  if node is Skeleton3D:
   for bone in node.get_bone_count():pose.append([node.get_bone_name(bone),node.get_bone_pose(bone),node.get_bone_global_pose(bone)])
 return var_to_bytes(pose).hex_encode().sha256_text()
func test_original_pose_parity()->void:
 var actual:Dictionary={}
 for key in profiles:
  var view=view_for(key);var samples:Array=[pose_digest(view)]
  for item in [["aim",0,0.3],["attack",20,1.1],["attack",80,4.5],["reload",150,7.7],["basic",180,9.3],["skill",260,13.6],["move",450,22.7],["death",480,25.0]]:
   var message:=event(item[0],item[1],key+"-"+str(item[1]));message.from=Vector2(1,2);message.to=Vector2(1,0);message.duration=0.8
   view.consume(message);samples.append(pose_digest(view));view.update_time(item[2],unit(key));samples.append(pose_digest(view))
  actual[key]=samples;view.free()
 # Captured from untouched fbe1371 before the bridge existed; never regenerate
 # from the candidate, which would silently bless a rendering regression.
 var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(GOLDEN)).samples
 for key in expected:ck(actual[key]==expected[key],key+" unchanged state, source offset, native poses and visibility match byte-identical legacy baseline")
func test_bounded_ledger()->void:
 var bridge=Bridge.new();var emitted:Array=[]
 bridge.ordinary_audio_state.connect(func(record:Dictionary):emitted.append(record))
 bridge.reset(4,"shiroko",7,0.0)
 for i in range(Bridge.MAX_SEEN_STATES+2):bridge.selected(str(i),"attack_fire","Native_Fire",float(i),0.0,1.0,float(i)+0.5,float(i))
 ck(bridge._seen.size()==Bridge.MAX_SEEN_STATES,"state dedup has bounded lifetime storage")
 ck(emitted.filter(func(r:Dictionary):return r.type=="enter").size()==Bridge.MAX_SEEN_STATES,"budget exhaustion remains silent without evicting replay identities")
 var count:int=emitted.size();bridge.selected("0","attack_fire","Native_Fire",0.0,0.0,1.0,0.5,0.0)
 ck(emitted.size()==count,"old packet never replays after ledger limit")
 bridge.reset(4,"shiroko",7,0.0);bridge.selected("0","reload","Native_Reload",0.0,0.0,1.0,0.5,0.0)
 ck(emitted.size()==count+1,"same generation reset opens a fresh bounded ledger")
func run()->void:
 profiles=JSON.parse_string(FileAccess.get_file_as_string("res://data/character-presentations.json"))
 test_bursts_and_duplicates();test_reload_replacement_and_lifecycle();test_missing_and_unqualified_clips();test_partition_and_all_profiles();test_stage_forwarding();test_deferred_move_interruption();test_original_pose_parity();test_bounded_ledger()
 await process_frame
 print("ORDINARY AUDIO STATE BRIDGE ",checks," checks; ",failures," failures")
 quit(1 if failures else 0)
