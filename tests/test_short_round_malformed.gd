extends SceneTree
const Match=preload('res://core/tactical_match.gd')
const League=preload('res://core/tactical_league.gd')
const Health=preload('res://core/battle_outcome.gd')
var failures:=0
func _initialize():
 var rules=Match.new();rules.hp_timeout=true
 var rows:Array=[]
 for i in range(8):rows.append({'participant_id':'p'+str(i)})
 var result:Dictionary={'opponent_id':'p1','ai_results':[],'winner':'player','combat':[]}
 if rules._matching_outcomes(rows,result):failures+=1
 var league=League.new();league.hp_timeout=true
 var valid_rows:Array=[]
 for i in range(0,8,2):
  for side in range(2):valid_rows.append({'participant_id':'p'+str(i+side),'opponent_id':'p'+str(i+1-side),'result':'draw','remaining_hp_ratio':0.5,'remaining_hp_total':500,'maximum_hp_total':1000,'duration_ticks':1800,'finish_reason':'timeout'})
 for field in ['duration_ticks','finish_reason']:
  for bad in [true,[],{},null,'bad',1.5]:
   var broken:Array=valid_rows.duplicate(true);broken[0][field]=bad
   var rejected:Variant=league.record_round(1,broken)
   if not rejected is Dictionary or rejected.get('ok',true):failures+=1
   if not league.snapshot().rounds.is_empty():failures+=1
 var duel:Dictionary={'winner':'draw','left_remaining':1,'right_remaining':1,'remaining_hp_totals':[500,500],'maximum_hp_totals':[1000,1000],'duration_ticks':1800,'finish_reason':true}
 if Health.valid(duel,1,1,1800):failures+=1
 print('SHORT_ROUND_MALFORMED failures=',failures)
 quit(1 if failures else 0)
