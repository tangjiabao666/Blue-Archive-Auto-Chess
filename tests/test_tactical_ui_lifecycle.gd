extends SceneTree
var failures:=0
var checks:=0
func ck(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize()->void:call_deferred('run')
func run()->void:
 var app=load('res://scripts/game_app.gd').new();app.new_game_mode='tactical_v1';app.persistence_enabled=false;root.add_child(app);app.set_process(false);await process_frame
 ck(app.has_method('_bench_gui_input'),'bench drag input integrated')
 if failures:app.queue_free();await process_frame;finish();return
 app.act({'type':'restart','seed':29});var bought:Dictionary=app.act({'type':'buy_offer','slot':0});var id:String=bought.unit_id
 ck(app.bench[0].text.is_empty() and app.bench[0].tooltip_text.contains('椿'),'bench has no permanent name, detail remains available')
 var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.global_position=app.bench[0].position+Vector2(20,20)
 app._bench_gui_input(press,0)
 var point:=Vector2(0,4.7);var screen:Vector2=app.stage.camera.unproject_position(Vector3(point.x,0,point.y))
 var motion:=InputEventMouseMotion.new();motion.position=screen;motion.global_position=screen;app._input(motion)
 ck(app.bench_drag.is_dragging() and app.bench_ghost.visible,'drag preview appears')
 var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;release.position=screen;release.global_position=screen;app._input(release)
 ck(id in app.session.rules.get_player().deployed and app.session.positions[id].distance_to(point)<0.001,'actual input pipeline atomically deploys at ground point')
 ck(not app.bench_drag.is_pending() and not app.bench_ghost.visible,'release clears ghost and drag')
 app.act({'type':'buy_offer','slot':1});app._bench_gui_input(press,0);app._input(motion)
 var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;app._input(escape)
 ck(not app.bench_drag.is_pending() and not app.game_menu.visible,'Esc cancels drag without opening menu')
 app._bench_gui_input(press,0);app._input(motion);app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
 ck(not app.bench_drag.is_pending(),'window focus loss cancels pending placement')
 ck(app.act({'type':'start_battle'}).ok,'battle starts');app._process(0.0)
 ck(app.shop.all(func(button):return not button.visible) and app.bench.all(func(button):return not button.visible),'battle hides recruitment and bench controls')
 ck(app.tactical_hud.visible and app.stage.field_input_rect.size.x>1200,'battle exposes wide playable field and skill HUD')
 app.act({'type':'restart','seed':29})
 ck(app.shop.all(func(button):return button.visible) and not app.tactical_hud.visible,'restart restores preparation layout')
 app.queue_free();await process_frame;finish()
func finish()->void:print('TACTICAL_UI_LIFECYCLE checks=',checks,' failures=',failures);quit(1 if failures else 0)
