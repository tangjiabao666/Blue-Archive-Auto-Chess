extends SceneTree
const Match=preload('res://core/tactical_match.gd')
const Session=preload('res://core/game_session.gd')
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize()->void:
 var catalog:Array=Session.new().catalog
 for seed_value in [1,7,13,20]:
  var rules=Match.new();rules.new_match(seed_value,catalog,{'level_shop_odds':1,'reinforcement_recruitment':1})
  for round_number in range(1,7):
   for id in range(1,8):
    var p:Dictionary=rules.get_player('p'+str(id))
    ck(p.gold>=0,'AI never spends unavailable gold')
    if round_number>=3:ck(p.level>=5,'AI buys level5 by third round')
    if round_number>=5:ck(p.level==6,'AI reserves then buys level6 by fifth round')
   rules._prepare_ai(rules._player_ref('p0'))
   var battle:Dictionary=rules.execute({'type':'start_battle'}).battle
   var rows:Array=[];var ai:Array=[]
   rows.append(row('p0',battle.opponent_id));rows.append(row(battle.opponent_id,'p0'))
   for pair in battle.ai_pairs:
    rows.append(row(pair[0],pair[1]));rows.append(row(pair[1],pair[0]))
    ai.append({'left_id':pair[0],'right_id':pair[1],'winner':'draw','left_remaining':rules.get_player(pair[0]).deployed.size(),'right_remaining':rules.get_player(pair[1]).deployed.size(),'duration_ticks':3000,'finish_reason':'timeout'})
   ck(rules.execute({'type':'resolve_battle','battle_id':battle.id,'winner':'draw','player_remaining':battle.player_units.size(),'opponent_remaining':battle.opponent_units.size(),'ai_outcomes':ai,'league_outcomes':rows}).ok,'synthetic economy-only round advances legally')
 print('TACTICAL_AI_ECONOMY checks=',checks,' failures=',failures);quit(1 if failures else 0)
func row(id:String,opponent:String)->Dictionary:return {'participant_id':id,'opponent_id':opponent,'result':'draw','remaining_hp_ratio':0.5}
