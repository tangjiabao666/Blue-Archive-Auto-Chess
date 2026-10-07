extends SceneTree
const Sim=preload('res://core/tactical_sim.gd')
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize()->void:
 var probe=Sim.new();ck(probe.snapshot().tactical.has('resources'),'manual EX resources integrated')
 if failures:finish();return
 for key in probe.active_character_keys():
  var s=Sim.new();s.set_command_generation(7)
  ck(s.configure([{'id':10,'team':0,'cell':Vector2(0,2),'character_id':key,'star':2},{'id':20,'team':1,'cell':Vector2(0,-2),'character_id':'serika','star':2}],{'seed':17}).is_empty(),'configure '+key)
  if s.units.is_empty():continue
  for unit in s.units:unit.hp=1000000000;unit.max_hp=1000000000
  s.start()
  for i in range(120):s.step()
  var u:Dictionary=s.units[0];var enemy:Dictionary=s.units[1];var ex:Dictionary=s.character_data(key).ex
  var target_id:=-1;var point:Vector2=enemy.cell
  if ex.kind in ['self_barrier','reload_and_self_buff','self_defense_buff_and_aoe_taunt']:
   target_id=u.id;point=u.cell
  elif ex.kind=='directional_dash_and_self_buffs':point=u.cell+Vector2(1,0)
  elif ex.kind in ['drone_damage','direct_shot_then_explosion','three_shot_target_then_rear_fan']:target_id=enemy.id
  var before:Dictionary=s.snapshot().tactical.resources
  var command:Dictionary={'generation':7,'team':0,'sequence':1,'tick':121,'type':'cast_ex','actor_id':10,'target_id':target_id,'point':point}
  ck(s.queue_tactical_command(command).ok,'queue '+key)
  var batch:Array=s.step()
  ck(batch.any(func(e):return e.type=='command_accepted' and e.actor_id==10),'manual EX accepted '+key)
  ck(batch.any(func(e):return e.type=='skill' and e.actor_id==10 and e.cast_start_tick==121),'source skill emitted '+key)
  ck(s.snapshot().tactical.resources.teams[0].energy==before.teams[0].energy-int(ex.originalCost),'exact source energy '+key)
  if target_id==-1:
   var skills:Array=batch.filter(func(e):return e.type=='skill' and e.actor_id==10)
   if not skills.is_empty():ck(skills[0].target_cell.distance_to(point)<0.00001,'selected position retained '+key)
 finish()
func finish()->void:
 print('TACTICAL_EX_TARGETS checks=',checks,' failures=',failures);quit(1 if failures else 0)
