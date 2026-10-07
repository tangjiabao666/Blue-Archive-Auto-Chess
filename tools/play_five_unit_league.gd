extends SceneTree
const Store=preload('res://core/session_save_store.gd')
class AutomatedSession extends 'res://core/game_session.gd':
 func _battle_options(battle_seed:int,left_id:String,right_id:String)->Dictionary:
  var value:Dictionary=super._battle_options(battle_seed,left_id,right_id)
  if combat_mode()=='tactical_v1':value.tactical_ai_teams=[0,1]
  return value
func _initialize()->void:
 var game=AutomatedSession.new();var first:Dictionary=game.new_game(23,'tactical_v1')
 if not first.ok:printerr(first);quit(1);return
 var rounds:Array=[]
 for round_number in range(1,7):
  game.rules._prepare_ai(game.rules._player_ref('p0'));game.preview_roster()
  var started:Dictionary=game.command({'type':'start_battle'})
  if not started.ok:printerr(started);quit(1);return
  var wall_start:int=Time.get_ticks_usec();var slices:=0
  while game.phase()=='battle':
   game.advance(0.25);slices+=1
   if slices>20000:printerr('cooperative settlement failed to terminate');quit(1);return
  if game.phase() not in ['result','finished']:printerr(game.last_error);quit(1);return
  var saved:Dictionary=game.export_save()
  if not saved.ok:printerr(saved);quit(1);return
  var stored:Dictionary=Store.write_save(saved.data,'user://tactical-full-source-checkpoint.json')
  if not stored.ok:printerr(stored);quit(1);return
  var disk:Dictionary=Store.read_save('user://tactical-full-source-checkpoint.json')
  var reloaded=AutomatedSession.new();var restored:Dictionary=reloaded.restore_save(disk.data)
  if not restored.ok or reloaded.rules.snapshot()!=game.rules.snapshot():
   var drift=FileAccess.open('/tmp/tactical-league-restore-drift.json',FileAccess.WRITE);drift.store_string(JSON.stringify({'before':game.rules.snapshot(),'saved':saved.data.rules,'after':reloaded.rules.snapshot()},'  ',true,true));drift.close()
   printerr('round restore drift ',restored);quit(1);return
  var state:Dictionary=game.rules.snapshot()
  if state.config.max_level!=5 or state.players.any(func(p):return p.level>5 or p.deployed.size()>5):printerr('population cap failed');quit(1);return
  var row:Dictionary={'round':round_number,'phase':game.phase(),'seconds':game.clock.sim.tick*0.05,'cpu_ms':(Time.get_ticks_usec()-wall_start)/1000.0,'player_level':game.rules.get_player().level,'player_count':game.rules.get_player().deployed.size(),'result':state.last_result,'standings':game.rules.league.standings(),'feedback':game.battle_feedback(),'checkpoint_roundtrip':true,'ai_status':game.ai_battle_status()}
  rounds.append(row);print('FULL_LEAGUE_ROUND ',JSON.stringify({'round':round_number,'phase':row.phase,'seconds':row.seconds,'winner':row.result.winner,'cpu_ms':row.cpu_ms}))
  if round_number<6:
   if not game.command({'type':'next_round'}).ok:printerr('next round rejected');quit(1);return
  elif game.phase()!='finished':printerr('sixth round did not finish');quit(1);return
 var report:Dictionary={'scope':'Actual visible and three NPC source simulations for all6rounds, headless; declared player AI uses the same public-information commands and resource costs. No GUI/FPS/human-play claim. JSON checkpoints restored after every round.','seed':23,'rounds':rounds,'final_state':game.rules.snapshot()}
 DirAccess.make_dir_recursive_absolute('res://evidence/five-unit-cover')
 var file=FileAccess.open('res://evidence/five-unit-cover/full-source-seed23.json',FileAccess.WRITE);file.store_string(JSON.stringify(report,'  '));file.close()
 print('FULL_LEAGUE_COMPLETE 6rounds 24actualduels 6checkpoint_roundtrips');quit()
