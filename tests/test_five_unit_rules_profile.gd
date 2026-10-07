extends SceneTree
## Rules-only synthetic settlement tests: these do not claim live combat results.
const Session=preload('res://core/game_session.gd')
const Match=preload('res://core/tactical_match.gd')
const SyntheticSettlement=preload('res://tests/synthetic_league_settlement.gd')
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func profile(game)->int:return int(game.call('rules_profile')) if game.has_method('rules_profile') else -1
func _initialize()->void:
 test_new_population()
 test_ai_upgrade_budget()
 test_save_profiles()
 test_profile_reinforcement_contract()
 test_detached_checkpoints()
 print('FIVE_UNIT_RULES_PROFILE checks=',checks,' failures=',failures)
 quit(1 if failures else 0)
func test_new_population()->void:
 var game=Session.new();ck(game.new_game(23,'tactical_v1').ok,'new tactical game starts')
 ck(profile(game)==3,'new tactical game pins short-round five-unit rules profile')
 ck(game.match_format()=='six_round_league','population profile retains six rounds')
 var state:Dictionary=game.rules.snapshot()
 ck(state.config.initial_level==4 and state.config.max_level==5,'initial four with maximum five')
 for player in state.players:ck(player.level==4 and player.deployed.size()<=4,'all participants begin with four slots')
 var player:Dictionary=game.rules._player_ref('p0');player.gold=100
 for character in ['shiroko','hoshino','hina','aru','yuuka','aris']:ck(game.rules._acquire_one_star(player,character).ok,'acquire distinct roster member '+character)
 for ignored in range(2):ck(game.command({'type':'buy_xp'}).ok,'buy XP reaches five normally')
 ck(game.rules.get_player().level==5,'level five reached')
 var before:Dictionary=game.rules.snapshot()
 var denied:Dictionary=game.command({'type':'buy_xp'})
 ck(not denied.ok and denied.error=='max_level' and game.rules.snapshot()==before,'XP purchase at five is atomic rejection')
 for ignored in range(5):ck(game.command({'type':'deploy_unit','unit_id':game.rules.get_player().bench[0]}).ok,'five deployments accepted')
 var sixth:String=game.rules.get_player().bench[0];before=game.rules.snapshot()
 denied=game.command({'type':'deploy_unit','unit_id':sixth})
 ck(not denied.ok and denied.error=='deployment_full' and game.rules.snapshot()==before,'sixth deployment rejected without deleting roster')
 ck(not game.deployment_preview(sixth,Vector2(0,6)).ok,'drag preview rejects sixth')
 ck(not game.deploy_at(sixth,Vector2(0,6)).ok and game.rules.snapshot()==before,'atomic board drop rejects sixth')
 ck(game.rules.get_player().units.size()==6 and game.rules.get_player().bench==[sixth],'sixth member stays on bench')
 var opts:Dictionary=game._battle_options(23,'p0','p1')
 ck(opts.get('tactical_cover_distance')==1.0 and opts.get('tactical_cover_multiplier')==0.7 and opts.get('tactical_cover_ai')==true,'new profile opts into new cover mechanics')
 var ai_opts:Dictionary=game._battle_options(23,'p1','p2')
 ck(ai_opts.get('tactical_cover_ai')==true and ai_opts.tactical_ai_teams==[0,1],'offscreen teams receive same new cover profile')
 for round_number in range(1,7):
  game.rules._prepare_ai(game.rules._player_ref('p0'))
  for entry in game.rules.snapshot().players:
   ck(entry.level<=5 and entry.deployed.size()<=5 and entry.units.size()==entry.bench.size()+entry.deployed.size(),'both sides stay at or below five in round '+str(round_number))
   if round_number>=3:ck(entry.level==5,'AI reaches five without losing initial-four progression')
  settle(game)
 ck(game.phase()=='finished' and game.rules.snapshot().round==6,'five-unit game ends after six rounds')
func test_ai_upgrade_budget()->void:
 for maximum in [5,6]:
  var rules=Match.new();ck(rules.new_match(23,Session.new().catalog,{'max_level':maximum}).ok,'standalone configurable league starts')
  rules._state.round=4
  var player:Dictionary=rules._player_ref('p0');player.level=5;player.xp=0;player.gold=4
  player.shop=[{'character_id':'hina','cost':4},{},{},{},{}]
  rules._prepare_ai(player)
  if maximum==5:ck(player.gold==0 and player.units.size()==1 and player.units[0].character_id=='hina','max-five AI spends recruit budget instead of reserving unreachable level six')
  else:ck(player.gold==4 and player.units.is_empty(),'old max-six AI keeps historical level-six reserve')
func old_save(seed_value:int=23)->Dictionary:
 var source=Session.new();source.new_game(seed_value)
 var old_rules=Match.new();old_rules.new_match(seed_value,source.catalog,{'level_shop_odds':1,'reinforcement_recruitment':1})
 var old:Dictionary=source.export_save().data
 old.version=8;old.erase('rules_profile');old.rules=old_rules.snapshot();old.combat_mode='tactical_v1';old.arena_version=1;old.match_format='six_round_league'
 return old
func test_save_profiles()->void:
 var game=Session.new();game.new_game(23,'tactical_v1')
 var saved:Dictionary=game.export_save();ck(saved.ok,'new profile exports')
 var original:Dictionary=saved.data
 ck(original.version==10 and original.get('rules_profile')==3 and original.rules.league.version==2,'Save10 pins short-round rules profile and HP ledger')
 var peer=Session.new();ck(peer.restore_save(JSON.parse_string(JSON.stringify(original))).ok and peer.export_save().data==original and profile(peer)==3,'Save10 JSON roundtrip retains profile and exact state')
 var malformed:Array=[]
 var bad:Dictionary=original.duplicate(true);bad.erase('rules_profile');malformed.append(bad)
 bad=original.duplicate(true);bad.extra=true;malformed.append(bad)
 for value in [-1,4,'3',true,null,1.5]:
  bad=original.duplicate(true);bad.rules_profile=value;malformed.append(bad)
 for patch in [{'rules_profile':0},{'rules_profile':1},{'rules_profile':2},{'version':8},{'version':9},{'match_format':'survival'},{'combat_mode':'legacy'},{'arena_version':0}]:
  bad=original.duplicate(true);bad.merge(patch,true);malformed.append(bad)
 bad=original.duplicate(true);bad.rules.config.max_level=6;malformed.append(bad)
 bad=original.duplicate(true);bad.version=8;bad.erase('rules_profile');malformed.append(bad)
 for candidate in malformed:ck(not peer.restore_save(candidate).ok and peer.export_save().data==original,'malformed or hybrid profile fails atomically')
 var five:Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/tactical_five_unit_v9.json'))
 var frozen_five:Dictionary=five.duplicate(true)
 ck(peer.restore_save(five).ok and profile(peer)==2 and peer.rules._normalize_json(peer.rules.snapshot())==peer.rules._normalize_json(five.rules) and five==frozen_five,'actual Save9 profile two preserves exact rules and input')
 var five_opts:Dictionary=peer._battle_options(23,'p0','p1')
 ck(five_opts.max_ticks==3000 and five_opts.overtime_start_seconds==75.0 and five_opts.tactical_damage_scale==0.12 and not five_opts.get('timeout_total_hp',false),'actual profile two retains 150 seconds and historical timeout semantics')
 ck(five_opts.tactical_cover_ai and five_opts.tactical_cover_distance==1.0 and five_opts.tactical_cover_multiplier==0.7,'actual profile two retains five-unit cover')
 var migrated_five:Dictionary=peer.export_save().data
 ck(migrated_five.version==10 and migrated_five.rules_profile==2 and peer.rules._normalize_json(migrated_five.rules)==peer.rules._normalize_json(five.rules) and migrated_five.rules.league.version==1,'Save9 re-export labels unchanged old five-unit ledger')
 ck(peer.command({'type':'restart','seed':24}).ok and profile(peer)==2,'rules restart retains historical five-unit profile')
 var old:Dictionary=old_save();var frozen:Dictionary=old.duplicate(true)
 ck(peer.restore_save(JSON.parse_string(JSON.stringify(old))).ok and profile(peer)==1,'Save8 league loads old max-six profile')
 ck(old==frozen and peer.rules.snapshot()==old.rules and peer.rules.snapshot().config.max_level==6,'Save8 load neither mutates nor reinterprets saved rules')
 var migrated:Dictionary=peer.export_save().data
 ck(migrated.version==10 and migrated.get('rules_profile')==1 and migrated.rules==old.rules,'Save8 re-export labels old rules without changing roster or RNG')
 var again=Session.new();ck(again.restore_save(migrated).ok and again.export_save().data==migrated,'migrated six-unit profile Save10 roundtrips')
 var old_opts:Dictionary=peer._battle_options(23,'p0','p1')
 ck(not old_opts.has('tactical_cover_distance') and not old_opts.has('tactical_cover_multiplier') and not old_opts.has('tactical_cover_ai'),'Save8 keeps historical cover options')
 var player:Dictionary=peer.rules._player_ref('p0');player.gold=100
 for character in ['shiroko','hoshino','hina','aru','yuuka','aris']:peer.rules._acquire_one_star(player,character)
 while player.level<6:ck(peer.rules.execute({'type':'buy_xp'}).ok,'old profile can buy level six')
 for ignored in range(6):ck(peer.command({'type':'deploy_unit','unit_id':peer.rules.get_player().bench[0]}).ok,'old profile retains sixth deployment')
 var six_save:Dictionary=peer.export_save().data;six_save.version=8;six_save.erase('rules_profile')
 ck(again.restore_save(six_save).ok and again.rules.get_player().deployed.size()==6 and again.rules.snapshot()==six_save.rules,'Save8 six deployed units survive load intact')
 ck(again.command({'type':'restart','seed':24}).ok and profile(again)==1 and again.rules.snapshot().config.max_level==6,'rules restart preserves old max-six profile')
 ck(again.new_game(24,'tactical_v1').ok and profile(again)==3 and again.rules.snapshot().config.max_level==5,'explicit new game promotes old profile to short-round max five')
 for fixture in ['shop_retention_legacy_session_v1.json','normal_target_legacy_session_v2.json','reinforcement_legacy_session_v3.json','asuna_legacy_session_v4_pending.json','tactical_legacy_session_v5.json']:
  var legacy:Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/'+fixture))
  ck(again.restore_save(legacy).ok and profile(again)==0 and again.rules.snapshot().config.max_level==6,'survival fixture retains profile zero '+fixture)
  var exported:Dictionary=again.export_save().data
  ck(exported.version==10 and exported.get('rules_profile')==0 and peer.restore_save(exported).ok,'survival fixture migrates into exact Save10 envelope')
 var legacy:Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/tactical_legacy_session_v5.json'))
 for version in [6,7,8]:
  var old_survival:Dictionary=legacy.duplicate(true);old_survival.version=version;old_survival.combat_mode='tactical_v1'
  if version>=7:old_survival.arena_version=1
  if version>=8:old_survival.match_format='survival'
  ck(again.restore_save(old_survival).ok and profile(again)==0 and again.match_format()=='survival','old tactical survival retains its rules '+str(version))
  ck(not again._battle_options(23,'p0','p1').has('tactical_cover_ai'),'old tactical survival keeps old cover '+str(version))
 var canonical:Dictionary=again.export_save().data
 ck(not again.new_game(2147483647,'tactical_v1').ok and again.export_save().data==canonical,'invalid new game preserves profile and state')
func test_profile_reinforcement_contract()->void:
 var game=Session.new();game.new_game(23,'tactical_v1')
 var original:Dictionary=game.export_save().data
 var tampered:Dictionary=original.duplicate(true);tampered.rules.config.reinforcement_recruitment=0
 var result:Dictionary=game.restore_save(tampered)
 ck(not result.ok and result.error=='unsupported_save_config','profile three rejects disabled reinforcement recruitment')
 ck(game.export_save().data==original,'rejected recruitment profile tampering is atomic')
 for historical_profile in [0,1]:
  for enabled in [0,1]:
   for version in [8,9,10]:
    var historical:Dictionary
    if historical_profile==1:historical=old_save()
    else:
     var survival=Session.new();survival.new_game(23);historical=survival.export_save().data
    historical.version=version;historical.rules.config.reinforcement_recruitment=enabled
    if version>=9:historical.rules_profile=historical_profile
    else:historical.erase('rules_profile')
    var peer=Session.new()
    ck(peer.restore_save(historical).ok and profile(peer)==historical_profile and peer.rules.snapshot()==historical.rules,'historical profile preserves recruitment '+str([historical_profile,enabled,version]))
func test_detached_checkpoints()->void:
 for expected in [1,2,3]:
  var game=Session.new()
  if expected==1:ck(game.restore_save(old_save(7)).ok,'old max-six profile checkpoint setup')
  elif expected==2:ck(game.restore_save(JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/tactical_five_unit_v9.json'))).ok,'actual historical five-unit checkpoint setup')
  else:game.new_game(7,'tactical_v1')
  for round_number in range(1,7):
   game.rules._prepare_ai(game.rules._player_ref('p0'));game.preview_roster();settle(game);game.showing_result=true
   var live_before:Dictionary=game.rules.snapshot();var opts_before:Dictionary=game._battle_options(7,'p0','p1')
   var saved:Dictionary=game.export_save();ck(saved.ok and saved.data.get('rules_profile')==expected,'detached result/final checkpoint keeps profile')
   ck(game.rules.snapshot()==live_before and game._battle_options(7,'p0','p1')==opts_before,'checkpoint export leaves live rules and options intact')
   var peer=Session.new();ck(saved.ok and peer.restore_save(JSON.parse_string(JSON.stringify(saved.data))).ok and profile(peer)==expected,'result/final profile reload')
   if round_number<6:ck(game.command({'type':'next_round'}).ok,'continue next preparation')
  ck(game.phase()=='finished','profile finishes six rounds')
func settle(game)->void:
 var opened:Dictionary=game.rules.execute({'type':'start_battle'});ck(opened.ok,'synthetic round starts')
 if not opened.ok:return
 ck(game.rules.execute(SyntheticSettlement.command(game,opened.battle)).ok,'synthetic round settles with versioned outcome evidence')
