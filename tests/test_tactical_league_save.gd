extends SceneTree
const Session=preload('res://core/game_session.gd')
const Match=preload('res://core/tactical_match.gd')
const SyntheticSettlement=preload('res://tests/synthetic_league_settlement.gd')
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize()->void:
 var game=Session.new();game.new_game(23,'tactical_v1')
 ck(game.match_format()=='six_round_league' and game.rules is Match,'new tactical games choose league explicitly')
 var saved:Dictionary=game.export_save()
 ck(saved.ok and saved.data.version==10 and saved.data.rules_profile==3 and saved.data.rules.league.version==2 and saved.data.match_format=='six_round_league' and saved.data.rules.league.rounds.is_empty(),'Save10 pins short-round league format and empty HP ledger')
 var peer=Session.new();ck(peer.restore_save(JSON.parse_string(JSON.stringify(saved.data))).ok and peer.export_save().data==saved.data,'initial league JSON checkpoint roundtrips')
 for field in ['match_format','league']:
  var bad:Dictionary=saved.data.duplicate(true)
  if field=='league':bad.rules.erase('league')
  else:bad.erase(field)
  ck(not peer.restore_save(bad).ok and peer.export_save().data==saved.data,'missing '+field+' fails atomically')
 for value in ['survival','future',0,true,null]:
  var bad:Dictionary=saved.data.duplicate(true);bad.match_format=value
  ck(not peer.restore_save(bad).ok and peer.export_save().data==saved.data,'cross-format or malformed format rejected')
 var legacy:Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/tactical_legacy_session_v5.json'))
 for version in [5,6,7]:
  var old:Dictionary=legacy.duplicate(true);old.version=version
  if version>=6:old.combat_mode='tactical_v1'
  if version>=7:old.arena_version=0
  ck(peer.restore_save(old).ok and peer.match_format()=='survival' and not peer.rules is Match,'old mode/save pairing retains survival '+str(version))
 ck(peer.new_game(23,'tactical_v1').ok and peer.match_format()=='six_round_league','explicit new game upgrades old tactical save to league')
 var before:Dictionary=peer.export_save().data
 ck(not peer.new_game(2147483647,'tactical_v1').ok and peer.export_save().data==before,'invalid new game does not replace rules ledger or profile')
 ck(game._battle_options(23,'p0','p1').max_ticks==1800,'new league battle limit is 90 seconds')
 # Produce legal rules history without claiming this fixture is a combat run.
 for round_number in range(1,7):
  game.rules._prepare_ai(game.rules._player_ref('p0'));game.preview_roster()
  var battle:Dictionary=game.rules.execute({'type':'start_battle'}).battle
  var synthetic:Dictionary=SyntheticSettlement.command(game,battle,'right','left')
  ck(synthetic.player_remaining>0 and synthetic.opponent_remaining>0,'fabricated timeout retains the losing survivors')
  ck(game.rules.execute(synthetic).ok,'synthetic evidence round settles')
  game.showing_result=true
  var checkpoint:Dictionary=game.export_save();ck(checkpoint.ok,'result/final checkpoint export')
  ck(peer.restore_save(JSON.parse_string(JSON.stringify(checkpoint.data))).ok,'result/final JSON reload')
  ck(peer.rules.league.snapshot()==game.rules.league.snapshot(),'score ledger restored without replaying reward')
  var before_rejection:Dictionary=peer.export_save().data
  for field in ['remaining_hp_total','maximum_hp_total','duration_ticks']:
   var fractional:Dictionary=checkpoint.data.duplicate(true)
   var outcome:Dictionary=fractional.rules.league.rounds[0].outcomes[0]
   outcome[field]+=0.5
   if field=='duration_ticks':
    for row in fractional.rules.league.rounds[0].outcomes:
     if row.participant_id==outcome.opponent_id:row[field]+=0.5
   var unchanged:Dictionary=fractional.duplicate(true)
   ck(not peer.restore_save(fractional).ok,'fractional '+field+' is rejected rather than truncated')
   ck(peer.export_save().data==before_rejection and fractional==unchanged,'fractional '+field+' rejection preserves complete state and input')
  if round_number<6:ck(game.command({'type':'next_round'}).ok,'next preparation continues')
 ck(game.phase()=='finished' and peer.phase()=='finished' and peer.rules.snapshot().round==6,'finished game stays finished after reload')
 ck(not peer.command({'type':'next_round'}).ok and not peer.command({'type':'start_battle'}).ok,'loaded final cannot play extra round')
 print('TACTICAL_LEAGUE_SAVE checks=',checks,' failures=',failures);quit(1 if failures else 0)
