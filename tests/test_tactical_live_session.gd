extends SceneTree
const App=preload('res://scripts/game_app.gd')
var checks:=0
var failures:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize()->void:call_deferred('run')
func run()->void:
 var app=App.new()
 ck(app.get_property_list().any(func(p):return p.name=='new_game_mode'),'app exposes explicit new-game mode')
 if failures:app.free();finish();return
 app.new_game_mode='tactical_v1';app.persistence_enabled=false;root.add_child(app);app.set_process(false);await process_frame
 ck(app.session.combat_mode()=='tactical_v1','actual app starts tactical session')
 ck(app.act({'type':'restart','seed':23}).ok,'restart deterministic recruit scenario')
 var merged:=''
 for slot in [1,3,4]:
  var result:Dictionary=app.act({'type':'buy_offer','slot':slot});ck(result.ok,'natural Asuna recruit');merged=str(result.get('unit_id',merged))
 ck(app.act({'type':'deploy_unit','unit_id':merged}).ok,'deploy merged character')
 ck(app.act({'type':'start_battle'}).ok,'start actual tactical battle');app._process(0.0)
 ck(app.tactical_hud.visible and app.stage.tactical_input_enabled,'battle HUD and input enabled')
 app.tactical_hud.slot_selected.emit(0)
 ck(app.tactical_input.armed_actor>=0 and not app.session.paused,'HUD click arms EX without pause')
 app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
 ck(app.tactical_input.armed_actor==-1 and not app.session.paused,'focus loss cancels only unconfirmed aim')
 app.tactical_hud.slot_selected.emit(0)
 var before:int=app.session.clock.sim.tick;app._process(0.1);app._process(0.1)
 ck(app.session.clock.sim.tick==before+4,'time continues while targeting')
 var actor:Dictionary=app.session.clock.sim.units.filter(func(u):return u.team==0)[0]
 var goal:Vector2=actor.cell+Vector2(0.5,0)
 var screen:Vector2=app.stage.camera.unproject_position(Vector3(goal.x,0,goal.y))
 var right:=InputEventMouseButton.new();right.button_index=MOUSE_BUTTON_RIGHT;right.pressed=true;right.position=screen
 app._unhandled_input(right)
 ck(app.tactical_input.armed_actor==-1 and app.session.clock.sim.snapshot().tactical.resources.teams[0].moves==2,'right cancellation does not move or spend')
 app.tactical_hud.slot_selected.emit(0)
 var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=screen
 app._unhandled_input(click);app._process(0.05)
 ck(app.session.clock.sim.snapshot().tactical.resources.teams[0].energy==2,'real mouse confirmation spends native Asuna cost2')
 ck(app.tactical_input.armed_actor==-1 and not app.tactical_input.is_pending(),'authoritative ack clears pending input')
 app.session.clock.sim.phase='finished'
 var visual_before:float=app.visual_time;var measured_before:int=app.battle_frame_times.size()
 app._process(0.2)
 ck(app.visual_time>visual_before and app.battle_frame_times.size()==measured_before,'settlement clears visual tails but is excluded from battle FPS')
 app._refresh_tactical_hud()
 ck(not app.tactical_hud.visible and not app.stage.tactical_input_enabled,'finished visible duel hides tactical input during background settlement')
 ck('结算' in app._battle_status_text(),'finished duel explains settlement instead of requesting commands')
 ck(not app._handle_tactical_event(click),'settlement cannot enqueue more commands')
 var legacy:Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://tests/fixtures/tactical_legacy_session_v5.json'))
 ck(app.session.restore_save(legacy).ok and app.session.combat_mode()=='legacy','old save remains legacy')
 ck(app.act({'type':'restart','seed':23}).ok and app.session.combat_mode()=='tactical_v1','new game after legacy load uses chosen new mode')
 app.queue_free();await process_frame;finish()
func finish()->void:
 print('TACTICAL_LIVE_SESSION checks=',checks,' failures=',failures);quit(1 if failures else 0)
