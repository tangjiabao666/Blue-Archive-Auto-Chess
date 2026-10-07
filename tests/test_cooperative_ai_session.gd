extends SceneTree
const Session=preload("res://core/game_session.gd")
var checks:=0
var failures:=0
func ck(value:bool,label:String):
 checks+=1
 if not value:failures+=1;printerr("FAIL ",label)
func make_game():
 var game=Session.new();ck(game.new_game(17).ok,"new game")
 game.rules._prepare_ai(game.rules._player_ref("p0"));return game
func ticks(game)->Array:
 var values:Array=[]
 for entry in game._ai_jobs:values.append(-1 if entry.job.is_complete() else entry.job._simulation.tick)
 return values
func _initialize():
 var game=make_game()
 ck(game.has_method("_pump_ai_jobs"),"session owns cooperative budgeted execution")
 if failures:game=null;finish();return
 ck(game.command({"type":"start_battle"}).ok,"battle starts")
 var status:Dictionary=game.ai_battle_status()
 ck(status.execution_mode=="cooperative" and status.pending==3,"three queued cooperative jobs")
 ck(ticks(game)==[0,0,0],"start queues without running ticks")
 for entry in game._ai_jobs:ck(not entry.has("task_id"),"no worker task handles")
 var before:Dictionary=game.rules.snapshot();var visible:Dictionary=game.clock.sim.snapshot()
 ck(game._pump_ai_jobs(1000000,5)==5,"step cap obeyed")
 ck(ticks(game)==[2,2,1],"round robin is fair")
 ck(game.rules.snapshot()==before and game.clock.sim.snapshot()==visible,"pumping never changes visible battle or economy")
 ck(game._pump_ai_jobs(0,5)==0 and game._pump_ai_jobs(1000000,0)==0,"zero budgets do no work")
 for i in range(3):
  ck(game._pump_ai_jobs(1,128)==1,"tiny elapsed budget stops after one indivisible source tick")
 ck(ticks(game)==[3,3,2],"cursor remains fair across tiny-budget calls")
 var fixed:Array=ticks(game);game.paused=true
 ck(game.advance(10).is_empty() and ticks(game)==fixed,"pause freezes all jobs")
 game.paused=false
 for delta in [-1.0,0.0,NAN,INF]:
  ck(game.advance(delta).is_empty() and ticks(game)==fixed,"invalid or nonpositive delta leaves jobs untouched")
 ck(game._collect_ai_outcomes().get("pending",false),"pending collect returns immediately")
 ck(game.ai_battle_status().scheduled==3,"pending collect preserves jobs")
 # Finish only the visible clock; session still must await real AI results.
 while game.clock.sim.phase=="running":game.clock.advance(1.0)
 ck(game.clock.sim.phase=="finished" and game.phase()=="battle","visible completion alone is not settlement")
 var loops:=0
 while game.phase()=="battle" and loops<5000:
  game.advance(0.05);loops+=1
  ck(game.ai_battle_status().last_pump_steps<=128,"each pump respects hard step limit")
 ck(game.phase() in ["result","finished"],"all results eventually settle")
 var settled:Dictionary=game.rules.snapshot();game.advance(1)
 ck(game.rules.snapshot()==settled,"settlement occurs once")
 ck(game.ai_battle_status().pending==0 and game.ai_battle_status().last_completed.execution_mode=="cooperative","completed diagnostics retain execution mode")
 var total_steps:int=game.ai_battle_status().last_completed.total_steps
 ck(total_steps>0,"diagnostics report actual cooperative progress")
 game=make_game();game.command({"type":"start_battle"});game._pump_ai_jobs(1000000,7)
 var old=weakref(game._ai_jobs[0].job)
 ck(game.command({"type":"restart","seed":23}).ok,"restart cancels partial work")
 ck(old.get_ref()==null and game.ai_battle_status().pending==0,"cancelled job references released")
 game=make_game();game._sync_positions()
 var checkpoint:Dictionary=game.export_save()
 ck(checkpoint.ok,"prebattle checkpoint available")
 game.command({"type":"start_battle"});game._pump_ai_jobs(1000000,7);old=weakref(game._ai_jobs[0].job)
 ck(game.restore_save(checkpoint.data).ok,"load cancels partially advanced jobs")
 ck(old.get_ref()==null and game.ai_battle_status().pending==0 and game.phase()=="preparation","load releases partial jobs and restores preparation")
 ck(game.export_save().data==checkpoint.data,"load preserves exact checkpoint after partial AI work")
 game=make_game();game.command({"type":"start_battle"});game._pump_ai_jobs(1000000,4);old=weakref(game._ai_jobs[0].job);game=null
 ck(old.get_ref()==null,"owner destruction releases partial jobs without joins")
 finish()
func finish():print("COOPERATIVE SESSION ",checks," checks; ",failures," failures");quit(1 if failures else 0)
