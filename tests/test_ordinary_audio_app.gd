extends SceneTree
## Live-app lifecycle coverage; no device audio or benchmark artifact writes.
class QuietApp extends "res://scripts/game_app.gd":
 func _save_battle_performance()->void:pass
const Warmup=preload("res://scripts/render_warmup.gd")
var checks:=0
var failures:=0
var records:Array=[]
func ck(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func silent(audio)->bool:
 var d:Dictionary=audio.diagnostics()
 return d.scheduled_count==0 and d.played_count==0 and d.queued_events==0 and d.active_voices==0 and d.seen_actions==0
func start_battle(app)->void:
 ck(app.act({"type":"restart","seed":17}).ok,"deterministic restart succeeds")
 var buy:Dictionary=app.act({"type":"buy_offer","slot":0})
 ck(buy.ok,"actual shop offer can be bought")
 if not buy.ok:return
 ck(app.act({"type":"deploy_unit","unit_id":buy.unit_id}).ok,"actual owned unit can be deployed")
 ck(app.act({"type":"start_battle"}).ok,"actual session starts battle")
func finish_battle(app)->void:
 for _step in range(160):
  if app.session.phase()!="battle" or app.session.clock.sim.phase=="finished":break
  app._process(1.0)
 ck(app.session.clock.sim.phase=="finished","visible battle reaches its simulation bound")
 var limit:int=int(app.session.ai_battle_status().scheduled)*int(app.session.clock.sim.options.max_ticks)+1
 for _slice in range(limit):
  if app.session.phase()!="battle":break
  app._process(0.05)
 ck(app.session.phase() in ["result","finished"],"cooperative settlement reaches result")
func wait_for_sound(app)->void:
 for _step in range(200):
  if app.ordinary_audio.diagnostics().active_voices>0:return
  app._process(0.05)
 ck(false,"fixture reaches an active ordinary sound")
func test_load_error_and_detach(app)->void:
 app.persistence_enabled=true
 app.save_path="/tmp/ordinary-audio-app-"+str(Time.get_ticks_usec())+".json"
 start_battle(app);wait_for_sound(app)
 var generation:int=app.session.clock.generation
 app._open_menu();app._process(0.0)
 ck(app._load_checkpoint().ok,"actual preparation checkpoint loads during paused battle")
 ck(app.session.phase()=="preparation" and app.session.clock.generation!=generation and not app.session.paused and not app.game_menu.visible,"checkpoint load replaces battle epoch and safely closes pause menu")
 ck(silent(app.ordinary_audio) and silent(app.combat_audio),"checkpoint load clears both ordinary and EX/basic audio")
 app._process(5.0)
 ck(silent(app.ordinary_audio),"loaded preparation cannot replay old scheduled sounds")
 ck(app.act({"type":"start_battle"}).ok,"restored roster can start a fresh battle")
 wait_for_sound(app)
 # Model the actual session error boundary without corrupting its rules or clock.
 app.session.last_error="ordinary_audio_lifecycle_fixture"
 app._process(0.0)
 ck(app.session.phase()=="error" and silent(app.ordinary_audio) and silent(app.combat_audio),"session error transition flushes both audio managers")
 app._process(3.0)
 ck(silent(app.ordinary_audio),"error-screen cosmetics cannot revive ordinary audio")
 start_battle(app);wait_for_sound(app)
 root.remove_child(app)
 ck(silent(app.ordinary_audio) and silent(app.combat_audio),"removing live GameApp from tree tears down all audio")
 # Persistence fixtures live in the explicitly writable temporary directory.
 for suffix in ["",".bak",".tmp",".bak.tmp"]:
  if FileAccess.file_exists(app.save_path+suffix):DirAccess.remove_absolute(app.save_path+suffix)
func run()->void:
 var app=QuietApp.new();app.persistence_enabled=false;root.add_child(app);app.set_process(false)
 ck("ordinary_audio" in app,"GameApp owns ordinary audio")
 if failures:app.free();quit(1);return
 app.stage.ordinary_audio_state.connect(func(record:Dictionary):records.append(record.duplicate(true)))
 ck(app.ordinary_audio.get_parent()==app and not app.ordinary_audio.output_enabled,"ordinary manager is outside Stage and headless output is disabled")
 ck(app.combat_audio.get_parent()==app and app.combat_audio!=app.ordinary_audio,"EX/basic retains its separate app-owned manager")
 app._process(20.0)
 ck(silent(app.ordinary_audio),"waiting in preparation cannot schedule ordinary audio")
 app._open_menu();app._process(2.0)
 ck(app.game_menu.visible and silent(app.ordinary_audio),"preparation menu remains silent")
 app._close_menu()
 var warmup=Warmup.new();app.add_child(warmup)
 var before:Dictionary=app.ordinary_audio.diagnostics()
 await warmup.run(app.session.profiles)
 ck(warmup.get_child_count()==0 and warmup.report.is_empty() and app.ordinary_audio.diagnostics()==before,"headless render warmup neither creates audio consumers nor mutates live audio")
 warmup.free()
 start_battle(app)
 ck(app.ordinary_audio.generation==app.session.clock.generation,"ordinary epoch starts after actual roster setup")
 for _step in range(200):
  if app.ordinary_audio.diagnostics().played_count>0:break
  app._process(0.05)
 var d:Dictionary=app.ordinary_audio.diagnostics()
 ck(d.scheduled_count>0 and d.played_count>0,"actual rendered normal states schedule official waveforms")
 ck(d.issues.is_empty() and d.invalid_state_records==0,"actual state bindings and PCM resources resolve")
 ck(d.player_nodes==0 and app.combat_audio.diagnostics().player_nodes==0,"headless app has no device output nodes")
 var at:float=d.time;var count:int=d.played_count;var queued:int=d.queued_events;var voices:int=d.active_voices
 var tick:int=app.session.clock.sim.tick
 app._open_menu();app._process(1.0);app._process(1.0)
 d=app.ordinary_audio.diagnostics()
 ck(app.game_menu.visible and app.session.paused and d.paused,"battle menu propagates pause to ordinary manager")
 ck(d.time==at and d.played_count==count and d.queued_events==queued and d.active_voices==voices and app.session.clock.sim.tick==tick,"repeated menu frames freeze simulation, audio queue and natural tails")
 app._close_menu();app._process(0.0)
 ck(not app.session.paused and not app.ordinary_audio.diagnostics().paused and app.ordinary_audio.diagnostics().played_count==count,"closing menu resumes the same sounds without replay at unchanged time")
 app._process(0.05)
 ck(app.ordinary_audio.diagnostics().time>at and app.session.clock.sim.tick>tick,"ordinary clock advances again after menu resume")
 app.session.paused=true;app._open_menu();app._close_menu();app._process(0.5)
 ck(app.session.paused and app.ordinary_audio.diagnostics().paused,"closing a menu opened while already paused preserves pause")
 app.session.paused=false
 # Force the app refresh path to rebuild actors under the same epoch.
 var generation:int=app.session.clock.generation
 var stale:Dictionary={}
 for record in records:
  if record.type=="enter":stale=record.duplicate(true);break
 ck(not stale.is_empty(),"real battle supplies a captured ordinary state for replay tests")
 app._refresh(true)
 ck(app.session.clock.generation==generation and silent(app.ordinary_audio) and app.ordinary_audio.diagnostics().state_records==0,"same-generation roster replacement flushes ordinary ledger, queues and voices")
 ck(silent(app.combat_audio),"same-generation refresh also retains EX/basic reset behavior")
 if not stale.is_empty():
  app.stage.ordinary_audio_state.emit(stale)
  ck(app.ordinary_audio.diagnostics().scheduled_count==1,"same-generation refresh permits a formerly seen real state in the new roster")
  if not app.ordinary_audio.diagnostics().scheduled.is_empty():
   app.ordinary_audio.update_time(float(app.ordinary_audio.diagnostics().scheduled[0].start))
  ck(app.ordinary_audio.diagnostics().played_count==1,"replayed real state starts at its authored onset after same-generation reset")
 var old_generation:int=generation
 ck(app.act({"type":"restart","seed":17}).ok,"restart after an active sound succeeds")
 ck(silent(app.ordinary_audio) and app.ordinary_audio.diagnostics().state_records==0,"restart flushes all ordinary state and voices")
 if not stale.is_empty():app.stage.ordinary_audio_state.emit(stale)
 app._process(3.0)
 ck(silent(app.ordinary_audio),"late battle callback and preparation frames cannot revive audio")
 start_battle(app)
 if not stale.is_empty():app.stage.ordinary_audio_state.emit(stale)
 ck(app.session.clock.generation!=old_generation and app.ordinary_audio.diagnostics().stale_events==1 and app.ordinary_audio.diagnostics().scheduled_count==0,"new battle rejects previous-generation state callback")
 finish_battle(app)
 app._process(0.81) # Result permits an already-started tail, bounded to 0.8 seconds.
 ck(silent(app.ordinary_audio) and app.ordinary_audio.diagnostics().state_records==0,"battle result tears down ordinary pending sounds, tails and ledger")
 ck(silent(app.combat_audio),"battle result still tears down the EX/basic manager")
 app._process(5.0)
 if not stale.is_empty():
  stale.generation=app.session.clock.generation;app.stage.ordinary_audio_state.emit(stale)
 ck(silent(app.ordinary_audio),"result cosmetics and even current-generation callback stay silent")
 if app.session.phase()=="result":
  ck(app.act({"type":"next_round"}).ok and app.stage.preparation,"next round returns to preparation")
  app._process(5.0)
  ck(silent(app.ordinary_audio),"next-round preparation remains silent")
 test_load_error_and_detach(app)
 app.free();await process_frame
 print("ORDINARY_AUDIO_APP ",checks," checks; ",failures," failures");quit(1 if failures else 0)
