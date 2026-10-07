extends SceneTree
## Integration regression: real tactical settings/map/armies and full native
## tick limit. Cooperative fallback must fail this test even if results match.
const Session=preload('res://core/game_session.gd')
const Duel=preload('res://core/offscreen_duel.gd')
const DEADLINE_MSEC:=90000
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize()->void:
 call_deferred('_run')
func _run()->void:
 await _run_profile(2)
 await _run_profile(3)
 print('PROCESS_TACTICAL_COMPLETION_TOTAL checks=',checks,' failures=',failures)
 quit(1 if failures else 0)
func _run_profile(profile:int)->void:
 print('PROCESS_TACTICAL_COMPLETION_START real settings, three NPC duels, then full-arena source references')
 var started_msec:int=Time.get_ticks_msec()
 var game=Session.new();game.process_ai_enabled=true
 # Frozen profile two intentionally retains the full historical 150-second
 # native-worker regression while new-profile tests cover the 90-second cap.
 var historical:Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/tactical_five_unit_v9.json'))
 var created:Dictionary=game.restore_save(historical) if profile==2 else game.new_game(23,'tactical_v1')
 ck(created.ok and game.rules_profile()==profile,'requested historical or new tactical profile initializes '+str(profile))
 if not created.ok:finish(game,started_msec);return
 game.rules._prepare_ai(game.rules._player_ref('p0'));game.preview_roster()
 var arena:Dictionary=game.arena_config()
 ck(arena.id=='staggered_cover' and arena.half_size==9.0,'seed23 uses real staggered-cover terrain')
 ck(arena.deployment_regions.has(0) and arena.deployment_points.has(1),'real arena includes integer-keyed deployment metadata that IPC must project out')
 var started:Dictionary=game.command({'type':'start_battle'})
 ck(started.ok,'unmodified legal player army starts the actual battle')
 if not started.ok:finish(game,started_msec);return
 var status:Dictionary=game.ai_battle_status()
 ck(status.execution_mode=='process','real tactical payload launches process instead of falling back')
 ck(status.process.error.is_empty() and status.process.launches==1 and status.process.status=='running','one owned process launches all NPC duels successfully')
 ck(game._ai_jobs.size()==3,'all three real NPC duels are scheduled')
 if status.execution_mode!='process':printerr(status);finish(game,started_msec);return
 var inputs:Array=[]
 for entry in game._ai_jobs:
  var input:Dictionary=entry.worker_input.duplicate(true);inputs.append(input)
  if profile==2:
   ck(input.settings.max_ticks==3000 and input.settings.overtime_start_seconds==75.0 and not input.settings.get('timeout_total_hp',false),'historical 150-second tactical limit and timeout semantics are unchanged')
  else:
   ck(input.settings.max_ticks==1800 and input.settings.overtime_start_seconds==60.0 and input.settings.timeout_total_hp,'new tactical profile uses 90-second cap and total-HP timeout')
  ck(input.settings.combat_mode=='tactical_v1' and input.settings.tactical_ai_teams==[0,1],'real shared tactical AI settings retained')
  ck(input.settings.tactical_cover_ai and input.settings.tactical_cover_distance==1.0 and input.settings.tactical_cover_multiplier==0.7,'actual five-unit cover rules retained')
  ck(input.arena_config=={'obstacles':arena.obstacles},'worker projection retains exactly the source obstacle geometry')
  ck(not input.left_army.is_empty() and not input.right_army.is_empty(),'NPC duels use nonempty actual source armies')
 var deadline:int=Time.get_ticks_msec()+DEADLINE_MSEC
 while game._ai_jobs.any(func(entry):return not entry.job.is_complete()) and Time.get_ticks_msec()<deadline:
  game._pump_ai_jobs(2000)
  status=game.ai_battle_status()
  if status.execution_mode!='process':break
  await create_timer(0.01).timeout
 status=game.ai_battle_status()
 var complete:bool=game._ai_jobs.all(func(entry):return entry.job.is_complete())
 ck(complete,'real worker completes all NPC duels before the90-second test deadline')
 ck(status.execution_mode=='process','completion did not silently switch to cooperative simulation')
 ck(status.process.status=='complete' and status.process.error.is_empty(),'worker reports terminal success')
 ck(status.process.launches==1 and status.process.pid==-1,'successful single child has exited')
 ck(not status.process.get('fallback',false) and status.total_steps==0,'no cooperative simulation ticks or fallback occurred')
 ck(status.process.cleanup_error.is_empty(),'owned process temporary files clean up successfully')
 print('PROCESS_TACTICAL_COMPLETION_WORKER ',JSON.stringify(status,'',true,true))
 if not complete or status.execution_mode!='process' or status.process.status!='complete':finish(game,started_msec);return
 var actual:Array=[]
 for entry in game._ai_jobs:actual.append(entry.job.result)
 # The independent references deliberately receive the FULL authoritative
 # arena, not the projected wire payload, to verify the projection contract.
 for index in range(inputs.size()):
  var input:Dictionary=inputs[index];var reference=Duel.new()
  var error:String=reference.configure(input.left_army,input.right_army,input.left_id,input.right_id,input.seed,input.settings,arena)
  ck(error.is_empty(),'full-arena reference configures for NPC duel '+str(index))
  if not error.is_empty():continue
  reference.run()
  ck(actual[index]==reference.result,'actual process result and HP metadata exactly match full-arena source duel '+str(index))
 var collected:Dictionary=game._collect_ai_outcomes()
 ck(collected.ok and collected.outcomes.size()==3 and collected.hp_ratios.size()==3,'normal Session collection accepts all actual worker results')
 status=game.ai_battle_status()
 ck(status.last_completed.execution_mode=='process' and status.last_completed.total_steps==0,'retained completion diagnostics identify the real process backend')
 ck(status.last_completed.process.status=='complete' and status.last_completed.process.error.is_empty(),'retained completion diagnostics contain terminal worker success')
 finish(game,started_msec)
func finish(game,started_msec:int)->void:
 game._cancel_ai_jobs()
 print('PROCESS_TACTICAL_COMPLETION profile=',game.rules_profile(),' checks=',checks,' failures=',failures,' wall_msec=',Time.get_ticks_msec()-started_msec)
