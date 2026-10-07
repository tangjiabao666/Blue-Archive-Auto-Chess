extends SceneTree
## Exercise real Session settlement and managed UI progression with bounded combat fixtures.
## This is a navigation test, not a pacing measurement.
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():call_deferred('run')
func run():
 var app=load('res://scripts/game_app.gd').new();app.new_game_mode='tactical_v1';app.managed_startup=true;app.persistence_enabled=false;root.add_child(app);app.set_process(false)
 for round_index in range(1,7):
  app.session.rules._prepare_ai(app.session.rules._player_ref('p0'));app.session.preview_roster();app._refresh(true)
  ck(app.act({'type':'start_battle'}).ok,'start round '+str(round_index))
  for entry in app.session._ai_jobs:
   entry.job.advance(1)
   entry.job._simulation.tick=1799
   for unit in entry.job._simulation.units:unit.attack_ready=99999;unit.basic_ready=99999;unit.sub_ready=99999;unit.skill_ready=99999
   entry.job.run()
  app.session.clock.sim.tick=1799
  for unit in app.session.clock.sim.units:unit.attack_ready=99999;unit.basic_ready=99999;unit.sub_ready=99999;unit.skill_ready=99999
  app._process(0.05)
  ck(app.session.phase()==('finished' if round_index==6 else 'result'),'settle round '+str(round_index))
  ck(app.round_result_panel.visible,'result visible '+str(round_index))
  ck(app.session.rules.league.snapshot().rounds.size()==round_index,'exactly one ledger entry')
  if round_index<6:
   app.round_result_panel.next_button.pressed.emit();var gold:int=app.session.rules.get_player().gold
   app.round_result_panel.next_button.pressed.emit()
   ck(app.session.phase()=='preparation' and app.session.rules.snapshot().round==round_index+1,'next round once')
   ck(app.session.rules.get_player().gold==gold,'duplicate press cannot grant income twice')
  else:ck(app.round_result_panel.new_button.visible and not app.round_result_panel.next_button.visible,'six rounds lead to final options')
 app.queue_free();await process_frame;print('PC_SIX_ROUND_FLOW checks=',checks,' failures=',failures);quit(1 if failures else 0)
