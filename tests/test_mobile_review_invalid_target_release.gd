extends SceneTree
var failures := 0
var checks := 0
func ck(ok:bool,label:String)->void:
 checks += 1
 print(('PASS ' if ok else 'FAIL ') + label)
 if not ok:failures += 1
func touch(at:Vector2,down:bool)->void:
 var event := InputEventScreenTouch.new()
 event.position=at;event.pressed=down;event.index=0
 Input.parse_input_event(event)
func drag(at:Vector2)->void:
 var event := InputEventScreenDrag.new()
 event.position=at;event.index=0;event.relative=Vector2(20,0)
 Input.parse_input_event(event)
func _initialize()->void:call_deferred('run')
func run()->void:
 root.size=Vector2i(1980,900);Input.emulate_mouse_from_touch=true
 var app=load('res://scripts/gameplay.tscn').instantiate()
 app.mobile_ui=true;app.persistence_enabled=false
 root.add_child(app);await process_frame;app.set_process(false)
 var player:Dictionary=app.session.rules._player_ref('p0')
 for i in range(3):app.session.rules._acquire_one_star(player,'shiroko')
 app.session.preview_roster()
 ck(app.act({'type':'deploy_unit','unit_id':player.bench[0]}).ok,'deploy enemy-target EX actor')
 ck(app.act({'type':'start_battle'}).ok,'start tactical battle')
 await process_frame
 var button:Button=app.tactical_hud.buttons[0]
 var origin:Vector2=button.get_global_rect().get_center()
 var empty_field:=Vector2(100,200)
 ck(app._tactical_context(empty_field).picked_actor==-1,'release point is empty field')
 ck(app.stage.field_input_rect.has_point(empty_field),'release point is inside field input')
 touch(origin,true);await process_frame
 ck(button.is_pressed() and app.mobile_gestures.is_pending(),'real touch begins EX button press')
 ck(app._tactical_modes.get(app.tactical_input.armed_actor)=='enemy','EX actually requires an enemy target')
 drag(empty_field);await process_frame
 touch(empty_field,false);await process_frame
 ck(not app.tactical_input.is_pending(),'invalid target does not queue command')
 ck(app.tactical_input.last_error=='invalid_enemy_target','invalid-target rejection reaches player')
 ck(not app.mobile_gestures.is_pending(),'gesture finishes')
 ck(not button.is_pressed(),'invalid-target drop releases EX button state')
 touch(origin,true);touch(origin,false);await process_frame
 ck(not button.is_pressed() and app.tactical_input.armed_actor==0,'subsequent tap works and clears button state')
 app.queue_free();await process_frame;Engine.max_fps=0;Input.emulate_mouse_from_touch=false
 print('MOBILE_REVIEW_INVALID_TARGET_RELEASE checks=',checks,' failures=',failures)
 quit(1 if failures else 0)
