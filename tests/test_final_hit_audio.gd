extends SceneTree
class App extends "res://scripts/game_app.gd":
 func _save_battle_performance():pass
 func _fresh_seed()->int:return 23
var failures:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():call_deferred('run')
func run():
 var app=App.new();app.persistence_enabled=false;root.add_child(app);app.set_process(false)
 var p:Dictionary=app.session.rules._player_ref('p0');app.session.rules._acquire_one_star(p,'shiroko');app.session.preview_roster();app.act({'type':'deploy_unit','unit_id':p.bench[0]});app.act({'type':'start_battle'})
 var sim=app.session.clock.sim
 for u in sim.units:
  if u.team==0:u.cell=Vector2(0,0.2);u.aimed=true;u.attack_ready=0;u.basic_ready=99999;u.skill_ready=99999
  else:u.cell=Vector2(0,-0.2);u.hp=1;u.busy_until=99999
 # End via real events, not manually fabricated sound callbacks.
 for i in range(300):
  app._process(0.05)
  if sim.phase=='finished':break
 ck(sim.phase=='finished','real combat finishes')
 ck(app.ordinary_audio.diagnostics().played_count>0,'last fighting frames still consume shot cues')
 ck(app.ordinary_audio.diagnostics().tail_draining and app.combat_audio.diagnostics().tail_draining,'visible battle end enters bounded tail phase immediately')
 var at:float=app.ordinary_audio.diagnostics().time
 app.session.paused=true;app._process(1.0)
 ck(app.ordinary_audio.diagnostics().time==at,'pause freezes result tail')
 app.session.paused=false
 for _frame in range(9):app._process(0.09)
 ck(app.ordinary_audio.diagnostics().active_voices==0 and app.ordinary_audio.diagnostics().queued_events==0,'tail drains within bound independent of NPC settlement')
 app.queue_free();await process_frame;print('FINAL_HIT_AUDIO checks=',checks,' failures=',failures);quit(1 if failures else 0)
