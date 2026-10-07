extends SceneTree
const Clock=preload('res://core/character_clock.gd')
var checks:=0
var failures:=0
func ck(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;printerr('FAIL '+label)
func _initialize()->void:
 var c=Clock.new();ck(c.has_method('use_combat_mode'),'clock can select tactical simulation')
 if failures:finish();return
 ck(c.use_combat_mode('tactical_v1'),'choose tactical clock');c.generation=7
 var roster:Array=[{'id':10,'team':0,'cell':Vector2(0,2),'character_id':'serika','star':1},{'id':20,'team':1,'cell':Vector2(0,-2),'character_id':'serika','star':1}]
 ck(c.sim.configure(roster,{'seed':17,'combat_mode':'tactical_v1'}).is_empty(),'configure tactical roster')
 ck(c.sim.start(),'start')
 var command:Dictionary={'generation':7,'team':0,'sequence':1,'tick':1,'type':'move','actor_id':10,'target_id':-1,'point':Vector2(1,2)}
 ck(c.sim.queue_tactical_command(command).ok,'queue for first tick')
 var events:Array=c.advance(0.05)
 var result_count:=0
 for event in events:
  if event.type in ['command_accepted','command_rejected']:
   result_count+=1;ck(event.generation==7 and event.tick==1 and event.sequence==1,'result bound to exact battle tick')
 ck(result_count==1,'one queued command produces exactly one execution result')
 ck(not c.sim.queue_tactical_command(command).ok,'cannot replay consumed command')
 ck(not c.use_combat_mode('legacy'),'running clock cannot change simulation')
 c.reset();ck(c.generation==8,'clock reset changes generation')
 ck(c.sim.snapshot().tactical.queue.generation==8,'queue follows clock generation')
 ck(c.sim.snapshot().tactical.queue.pending.is_empty(),'reset clears pending input')
 var legacy=Clock.new();ck(legacy.use_combat_mode('legacy'),'legacy remains default')
 ck(legacy.sim.configure(roster,{'seed':17}).is_empty(),'legacy configure')
 ck(not legacy.sim.snapshot().has('tactical'),'legacy snapshot shape unchanged')
 finish()
func finish()->void:
 print('TACTICAL_CLOCK checks=',checks,' failures=',failures);quit(1 if failures else 0)
