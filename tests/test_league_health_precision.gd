extends SceneTree
const League=preload('res://core/tactical_league.gd')
var failed:=0
func ck(ok:bool,label:String)->void:
 if not ok:failed+=1;printerr('FAIL '+label)
func rows(left:float,right:float)->Array:
 var result:Array=[]
 for index in range(0,8,2):
  result.append({'participant_id':'p'+str(index),'opponent_id':'p'+str(index+1),'result':'win','remaining_hp_ratio':left if index==0 else right if index==2 else 0.5})
  result.append({'participant_id':'p'+str(index+1),'opponent_id':'p'+str(index),'result':'loss','remaining_hp_ratio':0.0})
 return result
func _initialize()->void:
 var league=League.new();league.record_round(1,rows(35232.0/81293.0,0.2))
 var peer=League.new();ck(peer.restore(JSON.parse_string(JSON.stringify(league.snapshot(),'',true,true))).ok and peer.snapshot()==league.snapshot(),'real source HP ratio survives actual JSON precision')
 league=League.new()
 for index in range(3):league.record_round(index+1,rows([0.1,0.2,0.3][index],[0.3,0.2,0.1][index]))
 var table:Array=league.standings();var a:Dictionary=table.filter(func(r):return r.participant_id=='p0')[0];var b:Dictionary=table.filter(func(r):return r.participant_id=='p2')[0]
 ck(a.rank==b.rank and a.remaining_hp_ratio==b.remaining_hp_ratio,'equal cumulative health shares rank regardless of addition order')
 print('LEAGUE_HEALTH_PRECISION failures=',failed);quit(1 if failed else 0)
