extends SceneTree
const Sim=preload('res://core/tactical_sim.gd')
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func command(s,team:int,actor:int,kind:String,seq:int,point:Vector2)->Dictionary:return {'generation':7,'team':team,'sequence':seq,'tick':s.tick+1,'type':kind,'actor_id':actor,'target_id':-1,'point':point}
func _initialize()->void:
 var s=Sim.new();s.set_command_generation(7)
 ck(s.configure([{'id':0,'team':0,'cell':Vector2(0,2),'character_id':'aris','star':2},{'id':1,'team':1,'cell':Vector2(0,-2),'character_id':'serika','star':1},{'id':2,'team':1,'cell':Vector2(3,-3),'character_id':'serika','star':1}],{'seed':17,'random_damage':false}).is_empty(),'configure Aris dodge scenario')
 ck(s.snapshot().tactical.has('volumes'),'spatial impacts integrated')
 if failures:finish();return
 for u in s.units:u.hp=1000000000;u.max_hp=1000000000;u.busy_until=10000
 s.start()
 for i in range(80):s.step()
 ck(s.queue_tactical_command(command(s,0,0,'cast_ex',1,Vector2(0,-2))).ok,'queue aimed line')
 var cast_events:Array=s.step()
 ck(cast_events.any(func(e):return e.type=='attack_telegraph'),'cast publishes authoritative warning')
 var volumes:Array=s.snapshot().tactical.volumes
 ck(volumes.size()==1 and volumes[0].shape=='line','one authoritative line volume')
 ck(s.queue_tactical_command(command(s,1,1,'move',1,Vector2(3,-2))).ok,'order initial victim to dodge')
 ck(s.queue_tactical_command(command(s,1,2,'move',2,Vector2(0,-3))).ok,'order initial outsider into line')
 var hit_ids:Array=[]
 for i in range(60):
  for event in s.step():
   if event.type=='damage' and event.actor_id==0 and event.ability=='ex':hit_ids.append(event.target_id)
 ck(1 not in hit_ids,'actual move out avoids previously targeted line')
 ck(2 in hit_ids,'actual move in takes damage despite absent cast-time victim list')
 var h=Sim.new();h.set_command_generation(7)
 ck(h.configure([{'id':0,'team':0,'cell':Vector2(0,2),'character_id':'koharu','star':2},{'id':1,'team':0,'cell':Vector2(3,2),'character_id':'serika','star':1},{'id':2,'team':1,'cell':Vector2(0,-3),'character_id':'serika','star':1}],{'seed':17,'random_damage':false}).is_empty(),'configure moving ally heal')
 for u in h.units:u.hp=100000;u.max_hp=1000000;u.busy_until=10000
 h.start();h.queue_tactical_command(command(h,0,0,'cast_ex',1,Vector2.ZERO));h.step()
 h.queue_tactical_command(command(h,0,1,'move',2,Vector2(0,1)))
 var healed:=false
 for i in range(65):
  for event in h.step():
   if event.type=='heal' and event.actor_id==0 and event.target_id==1 and event.ability=='ex':healed=true
 ck(healed,'area heal includes ally who enters after cast')
 for key in ['hina','aris']:
  var blocked=Sim.new();blocked.set_command_generation(7)
  var nav=load('res://core/obstacle_navigation.gd').new();var hooks=load('res://core/combat_arena_hooks.gd').new()
  var obstacles:Array=[{'rect':Rect2(-1,-0.2,2,0.4),'blocks_projectiles':true}]
  nav.configure(6.6,obstacles);hooks.bind(blocked,nav,obstacles)
  blocked.configure([{'id':0,'team':0,'cell':Vector2(0,2),'character_id':key,'star':2},{'id':1,'team':1,'cell':Vector2(0,-2),'character_id':'serika','star':1}],{'seed':17,'random_damage':false})
  for u in blocked.units:u.hp=1000000000;u.max_hp=1000000000;u.busy_until=10000
  blocked.start()
  for i in range(120):blocked.step()
  blocked.queue_tactical_command(command(blocked,0,0,'cast_ex',1,Vector2(0,-2)))
  var damaged:=false
  for i in range(150):
   for event in blocked.step():
    if event.type=='damage' and event.actor_id==0 and event.ability=='ex':damaged=true
  ck(damaged==(key=='aris'),'high cover blocks direct fan but tagged penetrating beam passes '+key)
  blocked.path_step=Callable();blocked.cover_query=Callable()
 finish()
func finish()->void:
 print('TACTICAL_VOLUME_COMBAT checks=',checks,' failures=',failures);quit(1 if failures else 0)
