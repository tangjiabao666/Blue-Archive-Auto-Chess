extends SceneTree
const Session=preload('res://core/game_session.gd')
const Duel=preload('res://core/offscreen_duel.gd')
const SyntheticSettlement=preload('res://tests/synthetic_league_settlement.gd')
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize()->void:
 var game=Session.new();game.new_game(23,'tactical_v1')
 ck(game.has_method('arena_config'),'session exposes authoritative arena')
 if failures:finish();return
 var arena:Dictionary=game.arena_config()
 ck(arena.half_size==9.0 and arena.obstacles.size()>=6,'new tactical terrain enabled')
 var roster:Array=[]
 for slot in [0,1,2,3]:
  var bought:Dictionary=game.command({'type':'buy_offer','slot':slot})
  ck(bought.ok,'buy test unit')
  if bought.ok:ck(game.command({'type':'deploy_unit','unit_id':bought.unit_id}).ok,'deploy test unit')
 ck(game.place(game.rules.get_player().deployed[0],Vector2(8,7)),'placement uses enlarged player territory')
 var save:Dictionary=game.export_save();ck(save.ok and save.data.arena_version==1,'terrain version pinned in save')
 var loaded=Session.new();ck(loaded.restore_save(JSON.parse_string(JSON.stringify(save.data))).ok,'terrain save reloads with independent navigation')
 ck(loaded.arena_config()==arena and loaded.positions==game.positions,'loaded map and placements agree')
 var bad:Dictionary=save.data.duplicate(true);bad.arena_version=2
 var before:Dictionary=loaded.export_save().data
 ck(not loaded.restore_save(bad).ok and loaded.export_save().data==before,'unknown terrain version rejected atomically')
 var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/tactical_legacy_session_v5.json'))
 old.version=6;old.combat_mode='tactical_v1'
 ck(loaded.restore_save(old).ok and loaded.arena_config().half_size==6.6,'old tactical save6 keeps original terrain')
 ck(game.command({'type':'start_battle'}).ok,'visible and background battles configure same map')
 ck(game.clock.sim.options.arena_half==9.0,'visible simulation gets large bounds')
 for entry in game._ai_jobs:
  ck(entry.job._navigation._half_size==9.0,'background simulation gets large bounds')
  ck(entry.job._arena.obstacles==arena.obstacles,'background simulation gets identical obstacles')
 # Resolve only the rules layer here: this test covers terrain transitions,
 # not battle scoring or combat simulation correctness.
 var battle:Dictionary=game.rules.snapshot().battle
 ck(game.rules.execute(SyntheticSettlement.command(game,battle)).ok,'advance rules with explicitly synthetic timeout evidence')
 game.showing_result=true;game._normal_target_policy="wounded"
 var old_map:Dictionary=game.arena_config()
 var checkpoint:Dictionary=game.export_save()
 ck(checkpoint.ok and game.arena_config()==old_map,'result autosave preserves rendered old terrain')
 ck(checkpoint.data.normal_target_policy=='wounded','result checkpoint keeps target policy')
 var next_session=Session.new()
 ck(next_session.restore_save(checkpoint.data).ok,'result checkpoint reloads next terrain')
 ck(next_session.arena_config().id!=old_map.id,'new round rotates terrain deterministically')
 ck(game.command({'type':'next_round'}).ok and game.arena_config()==next_session.arena_config(),'continue matches restored next preparation')
 ck(game.positions==next_session.positions,'continue and checkpoint share relocated placements')
 var legacy=Session.new();legacy.new_game(23)
 ck(legacy.arena_config().half_size==6.6 and legacy.arena_config().obstacles==Session.OBSTACLES,'new legacy retains exact geometry')
 finish()
func finish()->void:print('TACTICAL_MAP_SESSION checks=',checks,' failures=',failures);quit(1 if failures else 0)
