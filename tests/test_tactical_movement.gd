extends SceneTree
const Sim=preload('res://core/tactical_sim.gd')
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func make_sim():
 var s=Sim.new();s.set_command_generation(7)
 ck(s.configure([{'id':10,'team':0,'cell':Vector2(0,2),'character_id':'serika','star':2},{'id':20,'team':1,'cell':Vector2(0,-2),'character_id':'yuuka','star':2}],{'seed':17}).is_empty(),'configure')
 for unit in s.units:unit.hp=1000000000;unit.max_hp=1000000000
 s.start();return s
func command(s,sequence:int=1)->Dictionary:return {'generation':7,'team':0,'sequence':sequence,'tick':s.tick+1,'type':'move','actor_id':10,'target_id':-1,'point':Vector2(2,2)}
func _initialize()->void:
 var s=make_sim();ck(s.snapshot().tactical.has('orders'),'movement orders integrated')
 if failures:finish();return
 s.queue_tactical_command(command(s));var attacks:=0;var moves:=0
 for i in range(16):
  for event in s.step():
   if event.get('actor_id')==10:
    if event.type=='attack':attacks+=1
    if event.type=='move':moves+=1
 ck(attacks==0 and moves==16,'ordered movement suppresses firing throughout travel')
 ck(s.units[0].cell.distance_to(Vector2(2,2))<0.00001,'arrives at chosen point')
 ck(s.snapshot().tactical.resources.teams[0].moves==1,'one shared order charge consumed')
 for i in range(90):
  for event in s.step():
   if event.type=='attack' and event.actor_id==10:attacks+=1
 ck(attacks>0,'ordinary attacks resume after arrival')
 s=make_sim();s.units[0].stun_until=10;s.queue_tactical_command(command(s))
 var batch:Array=s.step();ck(batch.any(func(e):return e.type=='command_rejected' and e.error=='actor_stunned'),'stunned order rejected')
 ck(s.snapshot().tactical.resources.teams[0].moves==2,'invalid order free')
 s=make_sim();var ex:Dictionary=command(s);ex.type='cast_ex';ex.target_id=10;ex.point=Vector2(0,2)
 s.queue_tactical_command(ex);s.queue_tactical_command(command(s,2))
 batch=s.step();ck(batch.any(func(e):return e.type=='command_rejected' and e.error=='ex_in_progress'),'move cannot cancel current EX')
 ck(s.snapshot().tactical.resources.teams[0].moves==2,'EX lock does not consume order')
 s=make_sim();s.units[0].ammo=0;s.units[0].reload_until=100;s.units[0].reload_at=0;s.queue_tactical_command(command(s))
 var early_reload:=false;var eventual_reload:=false
 for i in range(180):
  for event in s.step():
   if event.type=='reload_complete' and event.actor_id==10:
    eventual_reload=true
    if i<16:early_reload=true
 ck(not early_reload and eventual_reload,'interrupted reload resumes only after move')
 s=make_sim();s._normal_attack(s.units[0],s.units[1]);s.queue_tactical_command(command(s))
 batch=s.step()
 ck(not batch.any(func(e):return e.type=='damage' and e.get('actor_id',e.get('source_id',-1))==10),'move cancels same-tick unfired ordinary contact')
 ck(not s._pending.any(func(hit):return hit.source==10 and hit.ability=='normal'),'future ordinary burst contacts canceled')
 s=make_sim();s.options.random_damage=false;s._normal_attack(s.units[0],s.units[1])
 var launched:Dictionary=s._pending[0].duplicate(true);launched.emitted=true;launched.due=3
 s._pending=[launched];s.queue_tactical_command(command(s));var damaged:=false
 for i in range(3):
  for event in s.step():
   if event.type=='damage' and event.actor_id==10:damaged=true
 ck(damaged,'already emitted projectile survives action cancellation')
 finish()
func finish()->void:
 print('TACTICAL_MOVEMENT checks=',checks,' failures=',failures);quit(1 if failures else 0)
