extends SceneTree
## Native real-frame benchmark. Launch through the desktop; headless is rejected.
const App=preload('res://scripts/game_app.gd')
class ProfileSession extends 'res://core/game_session.gd':
 var audit:Array=[]
 func _battle_options(seed_value:int,left:String,right:String)->Dictionary:
  var value:Dictionary=super._battle_options(seed_value,left,right);value.tactical_ai_teams=[0,1];return value
 func advance(delta:float)->Array:
  var events:Array=super.advance(delta)
  for event in events:
   if event.tick<=600:
    var copy:Dictionary=event.duplicate(true);copy.erase('generation');audit.append(copy)
  return events
class ProfileApp extends App:
 var recording:=false
 var samples:Array=[]
 func _process(delta:float)->void:
  super._process(delta)
  if recording and session.phase()=='battle' and session.clock.sim.phase=='running' and session.clock.sim.tick>=200 and session.clock.sim.tick<=600 and delta>0:
   var cpu:Vector2=cpu_samples.back()
   samples.append({'frame_ms':delta*1000.0,'simulation_cpu_ms':cpu.x/1000.0,'presentation_cpu_ms':cpu.y/1000.0,'draw_calls':Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),'primitives':Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),'memory_bytes':Performance.get_monitor(Performance.MEMORY_STATIC),'living_actors':session.clock.sim.units.filter(func(u):return u.hp>0).size()})
 func _evidence_root()->String:return 'res://evidence/tactical-performance'
var app
func _initialize()->void:call_deferred('run')
func run()->void:
 if DisplayServer.get_name()=='headless':printerr('Native rendered benchmark required');quit(2);return
 app=ProfileApp.new();app.session=ProfileSession.new();app.new_game_mode='tactical_v1';app.persistence_enabled=false;root.add_child(app)
 root.title='Blue-A · Native frame benchmark'
 while app.warming:await process_frame
 var cases:Array=[{'id':'4v4-cooperative-100','round':1,'process':false,'scale':1.0},{'id':'4v4-process-100','round':1,'process':true,'scale':1.0},{'id':'6v6-process-100','round':5,'process':true,'scale':1.0},{'id':'6v6-process-85','round':5,'process':true,'scale':0.85}]
 DirAccess.make_dir_recursive_absolute('res://evidence/tactical-performance')
 for config in cases:
  app.recording=false;app.set_process(false);app.act({'type':'restart','seed':23});app.session.process_ai_enabled=config.process
  root.scaling_3d_scale=config.scale
  for round_number in range(1,int(config.round)):
   app.session.rules._prepare_ai(app.session.rules._player_ref('p0'));app.session.preview_roster()
   var battle:Dictionary=app.session.rules.execute({'type':'start_battle'}).battle
   var rows:Array=[];var ai:Array=[];app.session._append_league_pair(rows,'p0',battle.opponent_id,'draw',[0.5,0.5])
   for pair in battle.ai_pairs:
    app.session._append_league_pair(rows,pair[0],pair[1],'draw',[0.5,0.5]);ai.append({'left_id':pair[0],'right_id':pair[1],'winner':'draw','left_remaining':app.session.rules.get_player(pair[0]).deployed.size(),'right_remaining':app.session.rules.get_player(pair[1]).deployed.size(),'duration_ticks':3000,'finish_reason':'timeout'})
   var settled:Dictionary=app.session.rules.execute({'type':'resolve_battle','battle_id':battle.id,'winner':'draw','player_remaining':battle.player_units.size(),'opponent_remaining':battle.opponent_units.size(),'ai_outcomes':ai,'league_outcomes':rows})
   if not settled.ok:printerr(settled);quit(1);return
   app.session.showing_result=true;app.session.command({'type':'next_round'})
  app.session.rules._prepare_ai(app.session.rules._player_ref('p0'));app.session.preview_roster();app._refresh(true);app.session.audit.clear();app.samples.clear()
  var started:Dictionary=app.act({'type':'start_battle'})
  if not started.ok:printerr(started);quit(1);return
  app.recording=true;app.set_process(true)
  while app.session.phase()=='battle' and app.session.clock.sim.tick<700:await process_frame
  app.recording=false;app.set_process(false)
  var samples:Array=app.samples;var frames:Array=samples.map(func(s):return s.frame_ms);frames.sort()
  if frames.is_empty():printerr('no native frame samples');quit(1);return
  var total:float=frames.reduce(func(sum,value):return sum+value,0.0)
  var report:Dictionary={'case':config,'scope':'Real native frame deltas, simulation ticks200–600 after source shader warmup; full native characters/effects. Prior rounds for six-unit setup use declared synthetic economy fixtures, not gameplay evidence. No Windows/4060 claim.','adapter':RenderingServer.get_video_adapter_name(),'display_server':DisplayServer.get_name(),'viewport':root.get_visible_rect().size,'engine':Engine.get_version_info().string,'samples':samples,'frames':samples.size(),'seconds':total/1000.0,'average_fps':samples.size()*1000.0/total,'p50_frame_ms':frames[int(frames.size()*0.5)],'p95_frame_ms':frames[mini(frames.size()-1,int(frames.size()*0.95))],'p99_frame_ms':frames[mini(frames.size()-1,int(frames.size()*0.99))],'simulation_event_digest':JSON.stringify(app.session.audit,'',true,true).sha256_text(),'ai_status':app.session.ai_battle_status(),'native_vfx':app.stage.native_vfx.diagnostics()}
  for metric in ['simulation_cpu_ms','presentation_cpu_ms','draw_calls','primitives','memory_bytes']:report['mean_'+metric]=samples.reduce(func(sum,row):return sum+float(row[metric]),0.0)/samples.size()
  var file=FileAccess.open('res://evidence/tactical-performance/'+config.id+'.json',FileAccess.WRITE);file.store_string(JSON.stringify(report,'  ',true,true));file.close()
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png('res://evidence/tactical-performance/'+config.id+'.png')
  print('NATIVE_PROFILE ',JSON.stringify({'case':config.id,'fps':report.average_fps,'p95_ms':report.p95_frame_ms,'frames':report.frames,'event_digest':report.simulation_event_digest}))
 app.session._cancel_ai_jobs();app.queue_free();await process_frame;print('NATIVE_PROFILE_COMPLETE');quit()
