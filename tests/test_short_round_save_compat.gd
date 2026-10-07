extends SceneTree
const Session=preload('res://core/game_session.gd')
const Store=preload('res://core/session_save_store.gd')
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():
 var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/tactical_five_unit_v9.json'))
 var legacy=Session.new();ck(legacy.restore_save(old).ok,'actual frozen version9 checkpoint restores')
 ck(legacy.rules_profile()==2 and legacy._battle_options(1,'p0','p1').max_ticks==3000 and not legacy._battle_options(1,'p0','p1').get('timeout_total_hp',false),'old save keeps old pacing and outcome')
 var session=Session.new();ck(session.new_game(23,'tactical_v1').ok,'new short match begins')
 var player:Dictionary=session.rules._player_ref('p0')
 for name in ['yuuka','serika','hoshino','koharu']:session.rules._acquire_one_star(player,name)
 session.preview_roster()
 for id in player.bench.duplicate():ck(session.command({'type':'deploy_unit','unit_id':id}).ok,'deploy test roster')
 ck(session.command({'type':'start_battle'}).ok,'real tactical battle starts')
 for entry in session._ai_jobs:entry.job.run()
 session.clock.sim.tick=1799
 for unit in session.clock.sim.units:
  unit.hp=10000 if unit.team==0 else 5000;unit.max_hp=100000 if unit.team==0 else 10000
  unit.attack_ready=99999;unit.basic_ready=99999;unit.sub_ready=99999;unit.skill_ready=99999
 session.advance(0.05)
 ck(session.last_error.is_empty(),'positive-HP losing team can settle legally')
 ck(session.phase()=='result','timeout enters round result')
 if session.phase()!='result':printerr(session.last_error);finish();return
 var result:Dictionary=session.rules.snapshot().last_result
 ck(result.winner=='player' and result.player_remaining>0 and result.opponent_remaining>0,'90second winner uses totalHP without erasing loser survivors')
 ck(result.combat.duration_ticks==1800 and result.combat.finish_reason=='timeout','timeout witness persisted')
 var saved:Dictionary=session.export_save();ck(saved.ok,'short result exports as next preparation')
 if saved.ok:
  var restored=Session.new();ck(restored.restore_save(JSON.parse_string(JSON.stringify(saved.data,'',true,true))).ok,'new HP ledger survives JSON roundtrip')
  var wrong:Dictionary=saved.data.duplicate(true);wrong.rules.last_result.combat.remaining_hp_totals[0]+=1;ck(not restored.restore_save(wrong).ok,'mismatched saved witness rejected')
  wrong=saved.data.duplicate(true);wrong.version=9;ck(not restored.restore_save(wrong).ok,'new profile cannot masquerade as version9')
  wrong=saved.data.duplicate(true);wrong.rules_profile=2;ck(not restored.restore_save(wrong).ok,'new timeout ledger cannot masquerade as old profile')
 finish()
func finish():print('SHORT_ROUND_SAVE_COMPAT checks=',checks,' failures=',failures);quit(1 if failures else 0)
