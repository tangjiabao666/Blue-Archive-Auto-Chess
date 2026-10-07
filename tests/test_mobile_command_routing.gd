extends SceneTree
var fails:=0
var checks:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:fails+=1;printerr('FAIL '+label)
func mouse(at:Vector2,pressed:bool)->InputEventMouseButton:
 var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;e.position=at;e.global_position=at;return e
func _initialize():call_deferred('run')
func run():
 root.size=Vector2i(1980,900)
 var app=load('res://scripts/gameplay.tscn').instantiate();app.mobile_ui=true;app.persistence_enabled=false;root.add_child(app);await process_frame;app.set_process(false)
 var p:Dictionary=app.session.rules._player_ref('p0')
 for i in range(3):app.session.rules._acquire_one_star(p,'yuuka')
 app.session.preview_roster();app.act({'type':'deploy_unit','unit_id':p.bench[0]});app.act({'type':'start_battle'})
 var origin:Vector2=app.tactical_hud.buttons[0].global_position+Vector2(20,20)
 app._arm_tactical_slot(0)
 app._mobile_ex_gui(mouse(origin+Vector2(162,0),true),1)
 ck(not app.mobile_gestures.is_pending(),'disabled slot cannot borrow previously armed EX')
 app._cancel_mobile_aim()
 app._mobile_ex_gui(mouse(origin,true),0)
 ck(app.tactical_input.armed_actor==0 and app.mobile_gestures.is_pending(),'touch EX press arms without spending')
 ck(app.session.clock.sim.tactical_controls().resources.teams[0].energy==4,'aiming is free')
 var motion:=InputEventMouseMotion.new();motion.position=Vector2(600,360);app._handle_mobile_event(motion)
 app._handle_mobile_event(mouse(motion.position,false))
 ck(app.tactical_input.is_pending(),'EX gesture routes to authoritative queue')
 app._handle_mobile_event(mouse(motion.position,false))
 var events:Array=app.session.advance(0.15)
 ck(events.filter(func(e):return e.get('type')=='command_accepted' and e.get('team')==0).size()==1,'one gesture causes exactly one accepted command')
 ck(app.session.clock.sim.tactical_controls().resources.teams[0].energy==1,'native Yuuka EX cost spent once')
 for e in events:app.tactical_input.acknowledge(e)
 app._mobile_ex_gui(mouse(origin,true),0);motion.position=Vector2(-40,-40);app._handle_mobile_event(motion);app._handle_mobile_event(mouse(motion.position,false))
 ck(app.tactical_input.armed_actor==-1 and not app.tactical_input.is_pending(),'off-field EX drag cancels without queueing')
 ck(app.session.clock.sim.tactical_controls().resources.teams[0].energy==1,'cancel keeps energy')
 app._mobile_ex_gui(mouse(origin,true),0);motion.position=Vector2(600,360);app._handle_mobile_event(motion)
 var cancelled:InputEventMouseButton=mouse(motion.position,false);cancelled.canceled=true;app._handle_mobile_event(cancelled)
 ck(not app.tactical_input.is_pending() and app.tactical_input.armed_actor==-1,'cancelled touch release never casts at valid field')
 app._mobile_ex_gui(mouse(origin,true),0);app._suspend_mobile()
 ck(not app.mobile_gestures.is_pending() and app.tactical_input.armed_actor==-1,'background cancels in-flight touch')
 app._resume_mobile();app.queue_free();await process_frame;Engine.max_fps=0
 print('MOBILE_COMMAND_ROUTING checks=',checks,' failures=',fails);quit(1 if fails else 0)
