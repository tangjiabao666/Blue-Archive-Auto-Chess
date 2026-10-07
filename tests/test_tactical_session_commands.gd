extends SceneTree
const Session=preload('res://core/game_session.gd')
var checks:=0
var failures:=0
func ck(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;printerr('FAIL '+label)
func _initialize()->void:
 var s=Session.new();ck(s.new_game(23,'tactical_v1').ok,'create tactical session')
 var bought:Dictionary=s.command({'type':'buy_offer','slot':0});ck(bought.ok,'buy')
 ck(s.command({'type':'deploy_unit','unit_id':bought.unit_id}).ok,'deploy')
 ck(s.command({'type':'start_battle'}).ok,'start real session')
 ck(s.clock.sim.has_method('queue_tactical_command'),'session selects tactical simulator')
 if failures:finish();return
 var actor:int=s.clock.sim.units.filter(func(u):return u.team==0)[0].id
 var enemy:int=s.clock.sim.units.filter(func(u):return u.team==1)[0].id
 var command:Dictionary={'type':'move','actor_id':actor,'target_id':-1,'point':Vector2(1,3),'sequence':1,'generation':s.clock.generation}
 ck(s.command(command).ok,'local input queued')
 var before:Dictionary=s.clock.sim.snapshot()
 ck(not s.command(command).ok and s.clock.sim.snapshot()==before,'repeat local input atomic')
 var spoof:Dictionary=command.duplicate(true);spoof.sequence=2;spoof.actor_id=enemy
 ck(not s.command(spoof).ok,'enemy cannot be ordered')
 spoof=command.duplicate(true);spoof.sequence=3;spoof.generation-=1
 ck(not s.command(spoof).ok,'stale UI generation rejected')
 for job in s._ai_jobs:
  ck(job.job._simulation.has_method('queue_tactical_command'),'background duel uses same tactical simulator')
 var result_count:=0
 for event in s.advance(0.05):
  if event.type in ['command_accepted','command_rejected']:result_count+=1
 ck(result_count==1,'one authoritative input outcome')
 finish()
func finish()->void:
 print('TACTICAL_SESSION_COMMANDS checks=',checks,' failures=',failures);quit(1 if failures else 0)
