extends SceneTree
const Sim=preload('res://core/tactical_sim.gd')
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func make_sim(star:int=2):
 var s=Sim.new();s.set_command_generation(7)
 ck(s.configure([{'id':10,'team':0,'cell':Vector2(-1,2),'character_id':'yuuka','star':star},{'id':11,'team':0,'cell':Vector2(1,2),'character_id':'serika','star':2},{'id':20,'team':1,'cell':Vector2(0,-2),'character_id':'serika','star':2}],{'seed':17}).is_empty(),'configure')
 s.start();return s
func cmd(s,id:int,seq:int=1,target:int=-1,point:Vector2=Vector2.ZERO)->Dictionary:
 return {'generation':7,'team':0,'sequence':seq,'tick':s.tick+1,'type':'cast_ex','actor_id':id,'target_id':target,'point':point}
func _initialize()->void:
 var s=make_sim()
 ck(s.snapshot().tactical.has('resources'),'tactical simulation exposes shared resources')
 if failures:finish();return
 var count:=0
 for i in range(20):
  for event in s.step():
   if event.type=='skill':count+=1
 ck(count==0,'two-star actors never automatically cast in manual mode')
 s=make_sim()
 ck(s.queue_tactical_command(cmd(s,10,1,10,Vector2(-1,2))).ok,'queue shield EX')
 ck(s.queue_tactical_command(cmd(s,11,2,11,Vector2(1,2))).ok,'queue same tick second EX')
 var batch:Array=s.step();var accepted:=0;var rejected:=0;var skills:=0
 for event in batch:
  if event.type=='command_accepted':accepted+=1
  if event.type=='command_rejected':rejected+=1
  if event.type=='skill':skills+=1;ck(event.tick==1 and event.cast_start_tick==1,'source EX event uses actual execution tick')
 ck(accepted==1 and rejected==1 and skills==1,'shared energy serializes concurrent casts')
 ck(s.snapshot().tactical.resources.teams[0].energy==1,'deduct source cost3 exactly once')
 ck(s.units[0].skill_ready==121,'EX cooldown120ticks')
 ck(s.units[0].shield>0,'original shield semantics executed')
 var resources:Dictionary=s.snapshot().tactical.resources
 ck(not s.queue_tactical_command(cmd(s,10,1,10,Vector2(-1,2))).ok and s.snapshot().tactical.resources==resources,'duplicate never double spends')
 s=make_sim(1);s.queue_tactical_command(cmd(s,10,1,10,Vector2(-1,2)))
 batch=s.step();ck(batch.any(func(e):return e.type=='command_rejected' and e.error=='ex_locked'),'one-star EX rejected')
 ck(s.snapshot().tactical.resources.teams[0].energy==4,'locked EX free rejection')
 s=make_sim();s.units[0].stun_until=20;s.queue_tactical_command(cmd(s,10,1,10,Vector2(-1,2)))
 batch=s.step();ck(batch.any(func(e):return e.type=='command_rejected' and e.error=='actor_stunned'),'stun rejects EX')
 ck(s.snapshot().tactical.resources.teams[0].energy==4,'stun rejection preserves resources')
 s=make_sim();s.queue_tactical_command(cmd(s,10,1,10,Vector2(99,99)))
 batch=s.step();ck(batch.any(func(e):return e.type=='command_rejected' and e.error=='invalid_self_target'),'bad self target rejected')
 ck(s.snapshot().tactical.resources.teams[0].energy==4,'bad target spends nothing')
 s=make_sim();s.queue_tactical_command(cmd(s,10,1,10,Vector2(-1,2)));s.units[0].hp=0
 batch=s.step();ck(batch.any(func(e):return e.type=='command_rejected' and e.error=='actor_dead'),'queued actor death checked again on execution')
 ck(s.snapshot().tactical.resources.teams[0].energy==4,'dead queued actor spends nothing')
 s=make_sim()
 for unit in s.units:unit.hp=1000000000;unit.max_hp=1000000000
 s.units[0].ammo=0;s.units[0].reload_until=100;s.units[0].reload_at=0
 s.queue_tactical_command(cmd(s,10,1,10,Vector2(-1,2)))
 var reloaded:=false
 for i in range(180):
  for event in s.step():
   if event.type=='reload_complete' and event.actor_id==10:reloaded=true
 ck(reloaded,'EX interrupting empty reload eventually resumes reload rather than leaving actor stuck')
 finish()
func finish()->void:
 print('TACTICAL_EX checks=',checks,' failures=',failures);quit(1 if failures else 0)
