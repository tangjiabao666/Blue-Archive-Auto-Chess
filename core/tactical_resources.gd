extends RefCounted
const ENERGY_CAP:=10
const INITIAL_ENERGY:=4
const ENERGY_TICKS:=40
const EX_COOLDOWN_TICKS:=120
const MOVE_CAP:=2
const MOVE_RECHARGE_TICKS:=120
var _tick:=0
var _teams:Dictionary={}
var _ready:Dictionary={}
func _init()->void:reset()
func reset()->void:
 _tick=0;_ready.clear();_teams={}
 for team in [0,1]:_teams[team]={'energy':INITIAL_ENERGY,'moves':MOVE_CAP,'move_ready':-1}
func advance(at:int)->void:
 if at<_tick:return
 var gain:=int(at/ENERGY_TICKS)-int(_tick/ENERGY_TICKS)
 for team in [0,1]:
  var state:Dictionary=_teams[team]
  state.energy=mini(ENERGY_CAP,state.energy+gain)
  while state.move_ready>=0 and state.move_ready<=at and state.moves<MOVE_CAP:
   state.moves+=1
   state.move_ready=state.move_ready+MOVE_RECHARGE_TICKS if state.moves<MOVE_CAP else -1
 _tick=at
func can_cast(team:int,actor_id:int,cost:int,at:int)->bool:
 if not _teams.has(team) or actor_id<0 or cost<1 or cost>ENERGY_CAP or at!=_tick:return false
 return _teams[team].energy>=cost and at>=_ready.get(_key(team,actor_id),0)
func commit_cast(team:int,actor_id:int,cost:int,at:int)->bool:
 if not can_cast(team,actor_id,cost,at):return false
 _teams[team].energy-=cost;_ready[_key(team,actor_id)]=at+EX_COOLDOWN_TICKS
 return true
func can_move(team:int)->bool:return _teams.has(team) and _teams[team].moves>0
func commit_move(team:int)->bool:
 if not can_move(team):return false
 var state:Dictionary=_teams[team];state.moves-=1
 if state.move_ready<0:state.move_ready=_tick+MOVE_RECHARGE_TICKS
 return true
func snapshot()->Dictionary:return {'tick':_tick,'teams':_teams.duplicate(true),'ready':_ready.duplicate(true)}
func _key(team:int,actor_id:int)->String:return str(team)+':'+str(actor_id)
