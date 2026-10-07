extends RefCounted
const Volumes=preload("res://core/attack_volumes.gd")
## Reads only published units/resources. No player cursor or pending-input access.
var _teams:Array=[]
var _generation:=0
var _definitions:Dictionary={}
var _scale:=100.0
var _last_decision:=-1
var _sequence:Dictionary={}
var _cursor:Dictionary={}
var _cover_planner:Callable
var _cover_retry:Dictionary={}
func configure(teams:Array,generation:int,definitions:Dictionary,scale:float)->void:
 _teams=teams.duplicate();_generation=generation;_definitions=definitions.duplicate(true);_scale=scale
 _last_decision=-1;_sequence={0:0,1:0};_cursor={0:0,1:0};_cover_retry.clear()
func bind_cover_planner(planner:Callable)->void:_cover_planner=planner
func decide(view:Dictionary,at:int)->Array:
 if at<0 or at%10!=0 or at<=_last_decision:return []
 _last_decision=at
 var commands:Array=[]
 var resources:Dictionary=view.tactical.resources
 for team in _teams:
  var actors:Array=view.units.filter(func(u):return u.team==team and u.hp>0)
  actors.sort_custom(func(a,b):return a.id<b.id)
  if actors.is_empty():continue
  var dodge:Dictionary=_dodge(team,actors,view,at)
  if not dodge.is_empty():
   commands.append(dodge);_sequence[team]+=1;continue
  var cast_selected:=false
  for offset in range(actors.size()):
   var index:int=(_cursor[team]+offset)%actors.size();var u:Dictionary=actors[index]
   if u.star!=2 or at<u.stun_until or at<view.tactical.get('ex_busy_until',{}).get(u.id,0):continue
   var skill:Dictionary=_definitions[u.character_id].ex
   if resources.teams[team].energy<int(skill.originalCost) or at<resources.ready.get(str(team)+':'+str(u.id),0):continue
   var selected:Dictionary=_target(u,skill,view.units)
   if selected.is_empty():continue
   commands.append({'generation':_generation,'team':team,'sequence':_sequence[team],'tick':at+1,'type':'cast_ex','actor_id':u.id,'target_id':selected.target_id,'point':selected.point})
   _sequence[team]+=1;_cursor[team]=(index+1)%actors.size();cast_selected=true
   break
  if not cast_selected:
   var cover:Dictionary=_seek_cover(team,actors,view,at)
   if not cover.is_empty():commands.append(cover);_sequence[team]+=1
 return commands
func _target(u:Dictionary,skill:Dictionary,units:Array)->Dictionary:
 var enemies:Array=units.filter(func(v):return v.team!=u.team and v.hp>0)
 if enemies.is_empty():return {}
 enemies.sort_custom(func(a,b):
  var da:float=u.cell.distance_squared_to(a.cell);var db:float=u.cell.distance_squared_to(b.cell)
  return a.id<b.id if is_equal_approx(da,db) else da<db)
 var enemy:Dictionary=enemies[0]
 var reach:float=skill.get('targetingRangeSourceUnits',_definitions[u.character_id].statsLevel50ThreeStar.Range)/_scale
 if skill.kind=='directional_dash_and_self_buffs':
  var direction:Vector2=u.cell.direction_to(enemy.cell)
  return {'target_id':-1,'point':u.cell+direction*minf(1.9,reach)}
 if skill.kind=='circle_heal_and_damage':
  var allies:Array=units.filter(func(v):return v.team==u.team and v.hp>0 and v.hp/float(v.max_hp)<0.75 and u.cell.distance_to(v.cell)<=reach)
  allies.sort_custom(func(a,b):
   var ha:float=a.hp/float(a.max_hp);var hb:float=b.hp/float(b.max_hp)
   return a.id<b.id if is_equal_approx(ha,hb) else ha<hb)
  if not allies.is_empty():return {'target_id':-1,'point':allies[0].cell}
 if u.cell.distance_to(enemy.cell)>reach:return {}
 if skill.kind in ['self_barrier','reload_and_self_buff','self_defense_buff_and_aoe_taunt','self_buff']:return {'target_id':u.id,'point':u.cell}
 if skill.kind in ['drone_damage','single_target_burst','direct_shot_then_explosion','three_shot_target_then_rear_fan']:return {'target_id':enemy.id,'point':enemy.cell}
 return {'target_id':-1,'point':enemy.cell}
func snapshot()->Dictionary:
 return {'teams':_teams.duplicate(),'last_decision':_last_decision,'sequence':_sequence.duplicate(),'cursor':_cursor.duplicate()}

func _dodge(team:int,actors:Array,view:Dictionary,at:int)->Dictionary:
 if view.tactical.resources.teams[team].moves<=0:return {}
 var dangers:Array=view.get('telegraphs',[]).filter(func(v):return v.team!=team and v.ability!='normal' and at-v.cast_start_tick>=12 and not v.impacts.is_empty() and v.impacts[0].due>at and v.impacts[0].due<=at+80)
 if dangers.is_empty():return {}
 for actor in actors:
  if actor.hp<=0 or at<actor.stun_until or at<view.tactical.get('ex_busy_until',{}).get(actor.id,0) or view.tactical.get('orders',{}).has(actor.id):continue
  if not dangers.any(func(v):return Volumes.contains(v,actor.cell,0.35,actor.id)):continue
  for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP,Vector2(1,1).normalized(),Vector2(-1,1).normalized(),Vector2(1,-1).normalized(),Vector2(-1,-1).normalized()]:
   var point:Vector2=actor.cell+direction*2.5
   var half:float=view.get('arena_half',6.6)-0.35
   if absf(point.x)>half or absf(point.y)>half:continue
   if view.units.any(func(u):return u.id!=actor.id and u.hp>0 and u.cell.distance_to(point)<0.7):continue
   if dangers.any(func(v):return Volumes.contains(v,point,0.35,actor.id)):continue
   return {'generation':_generation,'team':team,'sequence':_sequence[team],'tick':at+1,'type':'move','actor_id':actor.id,'target_id':-1,'point':point}
 return {}

func _seek_cover(team:int,actors:Array,view:Dictionary,at:int)->Dictionary:
 # Voluntary repositioning retains the final shared charge for a dodge.
 if not _cover_planner.is_valid() or view.tactical.resources.teams[team].moves<=1:return {}
 for offset in range(actors.size()):
  var index:int=(_cursor[team]+offset)%actors.size();var actor:Dictionary=actors[index]
  if at<_cover_retry.get(actor.id,0) or at<actor.stun_until or at<view.tactical.get('ex_busy_until',{}).get(actor.id,0) or view.tactical.get('orders',{}).has(actor.id):continue
  if not _definitions[actor.character_id].normalAttack.enabled:continue
  _cover_retry[actor.id]=at+40
  var selected:Dictionary=_cover_planner.call(actor,view,at)
  if selected.is_empty():continue
  _cover_retry[actor.id]=at+120;_cursor[team]=(index+1)%actors.size()
  return {'generation':_generation,'team':team,'sequence':_sequence[team],'tick':at+1,'type':'move','actor_id':actor.id,'target_id':-1,'point':selected.point}
 return {}

func enable_team(team:int)->void:
 if team in [0,1] and team not in _teams:_teams.append(team)
