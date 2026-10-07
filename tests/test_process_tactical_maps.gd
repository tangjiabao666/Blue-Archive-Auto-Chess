extends SceneTree
const Session=preload('res://core/game_session.gd')
const Batch=preload('res://core/offscreen_process_batch.gd')
const Duel=preload('res://core/offscreen_duel.gd')
var failures:=0
var checks:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():call_deferred('run')
func run():
 for seed_value in [21,22,23]:
  var game=Session.new();game.new_game(seed_value,'tactical_v1');game.process_ai_enabled=true
  game.rules._prepare_ai(game.rules._player_ref('p0'));game.preview_roster()
  ck(game.command({'type':'start_battle'}).ok,'real map battle starts')
  var diag:Dictionary=game.ai_battle_status()
  ck(diag.execution_mode=='process' and diag.process.launches==1 and diag.process.error.is_empty(),'real tactical map launches worker instead of silently falling back')
  if diag.execution_mode!='process':game._cancel_ai_jobs();continue
  var inputs:Array=[]
  for entry in game._ai_jobs:
   var item:Dictionary=entry.worker_input.duplicate(true);item.settings.max_ticks=40;inputs.append(item)
  var arena:Dictionary=game.arena_config();game._cancel_ai_jobs()
  var batch=Batch.new();ck(batch.start(inputs,1).status=='running','bounded full-map fixture launches')
  var deadline:int=Time.get_ticks_msec()+15000
  var state:Dictionary=batch.poll()
  while state.status=='running' and Time.get_ticks_msec()<deadline:
   await create_timer(0.01).timeout;state=batch.poll()
  ck(state.status=='complete','three real-map NPC duels complete')
  if state.status=='complete':
   for index in range(inputs.size()):
    var item:Dictionary=inputs[index];var source=Duel.new()
    ck(source.configure(item.left_army,item.right_army,item.left_id,item.right_id,item.seed,item.settings,arena).is_empty(),'reference retains complete arena input')
    source.run();ck(source.result==state.results[index],'projected worker arena preserves exact source result')
  batch.cancel()
 print('PROCESS_TACTICAL_MAPS checks=',checks,' failures=',failures);quit(1 if failures else 0)
