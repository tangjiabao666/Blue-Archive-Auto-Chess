extends RefCounted
## Exact integer health witnesses for the versioned absolute-HP timeout rule.
const HEALTH_KEYS=['remaining_hp_totals','maximum_hp_totals']
static func totals(units:Array)->Dictionary:
 var hp:Array=[0,0];var maximum:Array=[0,0]
 for unit in units:
  hp[int(unit.team)]+=maxi(0,int(unit.hp));maximum[int(unit.team)]+=int(unit.max_hp)
 return {'remaining_hp_totals':hp,'maximum_hp_totals':maximum}
static func winner(hp:Array)->String:
 return 'left' if hp[0]>hp[1] else 'right' if hp[1]>hp[0] else 'draw'
static func whole(value:Variant,limit:int=2147483647)->bool:
 return (value is int or value is float) and is_finite(float(value)) and value>=0 and value<=limit and value==floor(value)
static func valid(duel:Dictionary,left_limit:int,right_limit:int,cap:int)->bool:
 if duel.get('winner') not in ['left','right','draw']:return false
 if not whole(duel.get('left_remaining'),left_limit) or not whole(duel.get('right_remaining'),right_limit) or not whole(duel.get('duration_ticks'),cap):return false
 for key in HEALTH_KEYS:
  if not duel.get(key) is Array or duel[key].size()!=2:return false
  for value in duel[key]:
   if not whole(value):return false
 var hp:Array=duel.remaining_hp_totals;var maximum:Array=duel.maximum_hp_totals;var alive:Array=[duel.left_remaining,duel.right_remaining]
 for team in range(2):
  if hp[team]>maximum[team] or ((hp[team]>0)!=(alive[team]>0)) or hp[team]<alive[team]:return false
 var reason:Variant=duel.get('finish_reason')
 if not reason is String or reason not in ['timeout','elimination','empty']:return false
 if reason=='timeout':
  if duel.duration_ticks!=cap or alive[0]<=0 or alive[1]<=0:return false
 elif reason=='elimination':
  if duel.duration_ticks<=0 or (alive[0]>0 and alive[1]>0):return false
 elif reason=='empty':
  if duel.duration_ticks!=0 or (alive[0]>0 and alive[1]>0) or hp!=maximum:return false
 else:return false
 return duel.winner==winner(hp)
static func player_duel(value:Dictionary)->Dictionary:
 if not value.get('combat') is Dictionary:return {}
 var result:Dictionary=value.combat.duplicate(true)
 result.winner='left' if value.get('winner')=='player' else 'right' if value.get('winner')=='opponent' else 'draw'
 result.left_remaining=value.get('player_remaining');result.right_remaining=value.get('opponent_remaining')
 return result

static func ratios(duel:Dictionary)->Array:
 var values:Array=[]
 for team in range(2):values.append(float(duel.remaining_hp_totals[team])/float(duel.maximum_hp_totals[team]) if duel.maximum_hp_totals[team]>0 else 0.0)
 return values
