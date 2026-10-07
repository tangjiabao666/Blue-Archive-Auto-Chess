extends SceneTree
var checks:=0
var failures:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func touch(at:Vector2,down:bool,index:int=0,cancelled:bool=false)->void:
 var e:=InputEventScreenTouch.new();e.position=at;e.pressed=down;e.index=index;e.canceled=cancelled;Input.parse_input_event(e)
func drag(at:Vector2,index:int=0)->void:
 var e:=InputEventScreenDrag.new();e.position=at;e.index=index;e.relative=Vector2(20,0);Input.parse_input_event(e)
func _initialize():call_deferred('run')
func run():
 root.size=Vector2i(1980,900);Input.emulate_mouse_from_touch=true
 var app=load('res://scripts/gameplay.tscn').instantiate();app.mobile_ui=true;app.persistence_enabled=false;root.add_child(app);await process_frame;app.set_process(false)
 var p:Dictionary=app.session.rules._player_ref('p0')
 for i in range(3):app.session.rules._acquire_one_star(p,'yuuka')
 app.session.preview_roster();app.act({'type':'deploy_unit','unit_id':p.bench[0]});app.act({'type':'start_battle'});await process_frame
 var button:Button=app.tactical_hud.buttons[0];var point:Vector2=button.get_global_rect().get_center()
 touch(point,true);await process_frame
 ck(app.mobile_gestures.is_pending() and app.tactical_input.armed_actor==0,'raw touch on EX reaches GUI gesture')
 touch(Vector2(610,360),true,1);drag(Vector2(620,360),1);touch(Vector2(620,360),false,1);await process_frame
 ck(app.mobile_gestures.is_pending() and not app.tactical_input.is_pending(),'secondary touch cannot finish primary gesture')
 drag(Vector2(600,360));touch(Vector2(600,360),false,0,true);await process_frame
 ck(not app.tactical_input.is_pending() and app.tactical_input.armed_actor==-1,'raw cancelled release never casts')
 ck(not button.is_pressed(),'cancel releases visual button state')
 touch(point,true);touch(point,false);await process_frame
 ck(not button.is_pressed() and app.tactical_input.armed_actor==0,'EX tap arms and releases visual button state')
 app._cancel_mobile_aim()
 touch(point,true);await process_frame;drag(Vector2(600,360));touch(Vector2(600,360),false);await process_frame
 ck(app.tactical_input.is_pending(),'raw touch EX drag queues command')
 ck(not button.is_pressed(),'completed drag releases visual button state')
 var events:Array=app.session.advance(0.15)
 ck(events.filter(func(e):return e.get('type')=='command_accepted' and e.get('team')==0).size()==1,'emulated touch commits exactly once')
 app.queue_free();await process_frame;Engine.max_fps=0;Input.emulate_mouse_from_touch=false
 print('MOBILE_TOUCH_DISPATCH checks=',checks,' failures=',failures);quit(1 if failures else 0)
