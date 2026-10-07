extends SceneTree
const Session=preload('res://core/game_session.gd')
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func row(id:String,other:String,result:String,ratio:float)->Dictionary:return {'participant_id':id,'opponent_id':other,'result':result,'remaining_hp_ratio':ratio}
func _initialize()->void:
 ck(ResourceLoader.exists('res://core/tactical_match.gd'),'isolated tactical match rules exist')
 if failures:finish();return
 var Match=load('res://core/tactical_match.gd');var rules=Match.new();var source=Session.new()
 ck(rules.new_match(23,source.catalog,{'level_shop_odds':1,'reinforcement_recruitment':1}).ok,'league starts')
 for round_number in range(1,7):
  rules._prepare_ai(rules._player_ref('p0'))
  var opened:Dictionary=rules.execute({'type':'start_battle'});ck(opened.ok,'round starts '+str(round_number))
  if not opened.ok:break
  var battle:Dictionary=opened.battle;var ai:Array=[];var rows:Array=[row('p0',battle.opponent_id,'loss',0.0),row(battle.opponent_id,'p0','win',0.5)]
  for pair in battle.ai_pairs:
   var count:int=rules._player_ref(pair[0]).deployed.size()
   ai.append({'left_id':pair[0],'right_id':pair[1],'winner':'left','left_remaining':count,'right_remaining':0,'duration_ticks':400,'finish_reason':'elimination'})
   rows.append(row(pair[0],pair[1],'win',0.5));rows.append(row(pair[1],pair[0],'loss',0.0))
  var command:Dictionary={'type':'resolve_battle','battle_id':battle.id,'winner':'opponent','player_remaining':0,'opponent_remaining':battle.opponent_units.size(),'ai_outcomes':ai,'league_outcomes':rows}
  var before:Dictionary=rules.snapshot();var bad:Dictionary=command.duplicate(true);bad.league_outcomes[0].opponent_id='p0'
  ck(not rules.execute(bad).ok and rules.snapshot()==before,'malformed scoring is atomic')
  var rng_before:int=before.rng_state;var gold_before:int=before.players[0].gold
  ck(rules.execute(command).ok,'real-shaped outcomes resolve')
  var state:Dictionary=rules.snapshot()
  ck(state.players.all(func(p):return p.hp==50 and not p.eliminated),'no participant eliminated after losses')
  ck(not rules.execute(command).ok and rules.snapshot()==state,'duplicate settlement cannot grant resources or points')
  var peer=Match.new();var reloaded:Dictionary=peer.restore(JSON.parse_string(JSON.stringify(state)));ck(reloaded.ok and peer.snapshot()==state,'round snapshot roundtrip '+str(reloaded))
  var malformed:Array=[]
  var changed:Dictionary=state.duplicate(true);changed.last_result.eliminated_ids=['p0'];malformed.append(changed)
  changed=state.duplicate(true)
  for duel in changed.last_result.ai_results:duel.resolution='estimated';duel.finish_reason='estimated';duel.duration_ticks=0
  malformed.append(changed)
  if round_number>=2:
   changed=state.duplicate(true);changed.league.rounds[0].outcomes.filter(func(row):return row.participant_id=='p0')[0].remaining_hp_ratio=1.0;malformed.append(changed)
  if round_number==6:
   changed=state.duplicate(true);changed.last_result.income_by_player={'p0':5};malformed.append(changed)
  for bad_state in malformed:ck(not peer.restore(bad_state).ok and peer.snapshot()==state,'tampered historical combat semantics reject atomically')
  if round_number<6:ck(state.phase=='preparation' and state.round==round_number+1,'next round continues')
  else:
   ck(state.phase=='finished' and state.round==6,'exactly six rounds ends')
   ck(state.rng_state==rng_before and state.players[0].gold==gold_before and state.last_result.income_by_player.is_empty(),'final settlement grants no seventh-round economy or RNG')
   ck(state.next_opponent.is_empty() and state.outcome=='defeat' and state.placement>1,'final standings own outcome')
   ck(not rules.execute({'type':'start_battle'}).ok,'seventh battle impossible')
 ck(rules.execute({'type':'restart','seed':23}).ok and rules.league.snapshot().rounds.is_empty(),'restart clears league score')
 finish()
func finish()->void:print('TACTICAL_MATCH checks=',checks,' failures=',failures);quit(1 if failures else 0)
