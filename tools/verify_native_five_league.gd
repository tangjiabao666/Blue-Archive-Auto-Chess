extends SceneTree
## End-to-end native rendering run; player commands automated, not human input QA.
const App=preload('res://scripts/game_app.gd')
class AutomatedSession extends 'res://core/game_session.gd':
 func _battle_options(value:int,left:String,right:String)->Dictionary:
  var result:Dictionary=super._battle_options(value,left,right)
  result.tactical_ai_teams=[0,1]
  return result
class AcceptanceApp extends App:
 func _evidence_root()->String:return 'res://evidence/five-unit-native-league'
var app
var report:Dictionary={'scope':'Six actual native rendered rounds with automated legal player commands, real offscreen process battles and App disk save/load. Not human input, Windows, audio-listening or FPS-target acceptance.','rounds':[],'passed':false}
func _initialize():call_deferred('run')
func stop_with(error:String)->void:
 report.error=error
 if app:report.failure_state={'phase':app.session.phase(),'tick':app.session.clock.sim.tick,'error':app.session.last_error,'ai':app.session.ai_battle_status()}
 write_report();printerr(error)
 if app:app.session._cancel_ai_jobs()
 quit(1)
func write_report()->void:
 DirAccess.make_dir_recursive_absolute('res://evidence/five-unit-native-league')
 var file=FileAccess.open('res://evidence/five-unit-native-league/result.json',FileAccess.WRITE)
 file.store_string(JSON.stringify(report,'  ',true,true));file.close()
func run()->void:
 if DisplayServer.get_name()=='headless':stop_with('Native display required');return
 app=AcceptanceApp.new();app.session=AutomatedSession.new();app.new_game_mode='tactical_v1';app.persistence_enabled=false;root.add_child(app)
 root.title='Blue-A · Five-unit full league verification'
 while app.warming:await process_frame
 app.set_process(false);app.act({'type':'restart','seed':23})
 app.persistence_enabled=true;app.save_path='user://five-unit-native-acceptance.json';app.session.process_ai_enabled=true
 for number in range(1,7):
  if app.session.phase()!='preparation':stop_with('Expected preparation');return
  app.session.rules._prepare_ai(app.session.rules._player_ref('p0'));app.session.preview_roster();app._refresh(true)
  var players:Array=app.session.rules.snapshot().players
  if players.any(func(p):return p.level>5 or p.deployed.size()>5):stop_with('Population overflow');return
  if not app.act({'type':'start_battle'}).ok:stop_with('Could not start battle');return
  if app.session.ai_battle_status().execution_mode!='process':stop_with('Worker failed to launch');return
  app.set_process(true)
  var begun:int=Time.get_ticks_msec()
  var deadline:int=begun+600000
  while app.session.phase()=='battle' and Time.get_ticks_msec()<deadline:await process_frame
  app.set_process(false)
  if app.session.phase() not in ['result','finished']:stop_with('Battle failed or exceeded wall-time bound');return
  var ai:Dictionary=app.session.ai_battle_status()
  var done:Dictionary=ai.get('last_completed',{})
  if done.get('execution_mode')!='process' or done.get('process',{}).get('status')!='complete' or done.get('total_steps',-1)!=0:stop_with('NPC process did not complete without fallback');return
  app._refresh_ui();app._refresh_tactical_hud()
  var state:Dictionary=app.session.rules.snapshot()
  var row:Dictionary={'round':number,'wall_ms':Time.get_ticks_msec()-begun,'phase':app.session.phase(),'ticks':app.session.clock.sim.tick,'player_level':app.session.rules.get_player().level,'deployed':app.session.rules.get_player().deployed.size(),'header':app.economy.text,'status':app.status.text,'ai':app.session.ai_battle_status(),'result':state.last_result}
  if app.tactical_hud.visible:stop_with('Tactical inputs remain visible after result');return
  await RenderingServer.frame_post_draw
  DirAccess.make_dir_recursive_absolute('res://evidence/five-unit-native-league')
  root.get_texture().get_image().save_png('res://evidence/five-unit-native-league/round-%d.png'%number)
  if not app._save_checkpoint(false).ok:stop_with('App save failed');return
  if not app._load_checkpoint().ok or app.session.rules.snapshot()!=state:stop_with('App reload drift');return
  row.checkpoint_roundtrip=true;report.rounds.append(row);write_report()
  print('NATIVE_LEAGUE_ROUND ',number,' ',row.phase,' ticks=',row.ticks)
 if app.session.phase()!='finished' or app.session.rules.snapshot().round!=6:stop_with('Final screen missing');return
 if app.act({'type':'start_battle'}).ok:stop_with('Unexpected seventh round');return
 report.passed=true;report.adapter=RenderingServer.get_video_adapter_name();report.final_status=app.status.text;write_report()
 app.session._cancel_ai_jobs();app.queue_free();await process_frame
 print('NATIVE_FIVE_LEAGUE_COMPLETE');quit()
