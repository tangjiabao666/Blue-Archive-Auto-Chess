extends SceneTree
class FastSession extends 'res://core/game_session.gd':
 func _battle_options(seed_value:int,left:String,right:String)->Dictionary:
  var settings:Dictionary=super._battle_options(seed_value,left,right);settings.max_ticks=40;return settings
var failures:=0
var checks:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func ready_game():
 var game=FastSession.new();game.process_ai_enabled=true;game.new_game(23)
 game.rules._prepare_ai(game.rules._player_ref('p0'));game.preview_roster();ck(game.command({'type':'start_battle'}).ok,'native-worker eligible battle starts');return game
func _initialize()->void:
 var probe=FastSession.new();ck(probe.get_property_list().any(func(p):return p.name=='process_ai_enabled'),'process backend opt-in exists')
 if failures:finish();return
 var game=ready_game();ck(game.ai_battle_status().execution_mode=='process','background batch uses process backend')
 var start:int=Time.get_ticks_msec()
 while game._ai_jobs.any(func(e):return not e.job.is_complete()) and Time.get_ticks_msec()-start<15000:
  game._pump_ai_jobs(2000);OS.delay_msec(5)
 ck(game._ai_jobs.all(func(e):return e.job.is_complete()),'nonblocking polls finish actual jobs')
 for entry in game._ai_jobs:
  var input:Dictionary=entry.worker_input;var reference=load('res://core/offscreen_duel.gd').new()
  reference.configure(input.left_army,input.right_army,input.left_id,input.right_id,input.seed,input.settings,input.arena_config);reference.run()
  ck(entry.job.result==reference.result,'process NPC result exactly matches cooperative source result')
 game=ready_game();var batch=game._process_batch;batch.cancel()
 for step in range(200):
  game._pump_ai_jobs(100000,128)
  if game._ai_jobs.all(func(e):return e.job.is_complete()):break
 ck(game._ai_jobs.all(func(e):return e.job.is_complete()) and game.ai_battle_status().execution_mode=='cooperative','worker failure falls back without losing source jobs')
 ck(game.last_error.is_empty(),'recovered worker failure does not poison visible battle')
 game=ready_game();batch=game._process_batch;var pid:int=batch.snapshot().pid
 ck(game.command({'type':'restart','seed':24}).ok,'restart succeeds during worker execution')
 ck(batch.snapshot().pid<0 and batch.snapshot().status!='running' and game._ai_jobs.is_empty(),'restart cancels owned worker and stale jobs')
 game=ready_game();batch=game._process_batch;pid=batch.snapshot().pid;game=null
 ck(batch.snapshot().pid<0 and batch.snapshot().status!='running','session deletion cancels owned worker')
 finish()
func finish()->void:print('PROCESS_AI_SESSION checks=',checks,' failures=',failures);quit(1 if failures else 0)
