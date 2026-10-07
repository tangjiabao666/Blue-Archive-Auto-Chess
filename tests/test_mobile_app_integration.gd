extends SceneTree
var failures:=0
var checks:=0
func ck(value:bool,label:String):
 checks+=1
 if not value:failures+=1;printerr('FAIL '+label)
func _initialize():call_deferred('run')
func run():
 root.size=Vector2i(1980,900)
 var app=load('res://scripts/gameplay.tscn').instantiate()
 ck(app.get_property_list().any(func(p):return p.name=='mobile_ui'),'app supports explicit mobile preview')
 if failures:app.free();finish();return
 app.mobile_ui=true;app.persistence_enabled=false;root.add_child(app);await process_frame;app.set_process(false)
 ck(not quit_on_go_back,'mobile Back does not auto-quit')
 root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST);ck(app.game_menu.visible,'Back is routed to game menu')
 app._close_menu()
 app.report_panel.show();root.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
 ck(not app.report_panel.visible and not app.game_menu.visible,'Back dismisses report before opening menu')
 app.report_panel.hide();app._close_menu()
 ck(not app.session.process_ai_enabled,'mobile explicitly uses cooperative backend')
 ck(app.game_menu.mobile_mode,'mobile quality menu enabled')
 ck(app.settings_values.fps_limit==60 and app.settings_values.render_scale==0.85,'mobile starts with balanced preference defaults')
 ck(app.stage.field_input_rect.size.x>1600,'wide phone uses available battlefield width')
 ck(app.menu_button.position.x>1600,'menu anchored to phone right edge')
 ck(app._sidebar_panel.position.x>1600,'preparation inspector placed at phone right edge')
 var p:Dictionary=app.session.rules._player_ref('p0');p.gold=100
 for i in range(3):app.session.rules._acquire_one_star(p,'asuna')
 app.session.preview_roster();var id:String=p.bench[0]
 ck(app.act({'type':'deploy_unit','unit_id':id}).ok,'mobile roster deploys')
 ck(app.act({'type':'start_battle'}).ok,'mobile battle starts')
 ck(app.mobile_cancel_button.visible and app.tactical_hud.visible,'touch cancel and skill controls visible')
 ck(app.stage.field_input_rect.size.x>=1900,'battle uses full phone width')
 app._arm_tactical_slot(0);var tick:int=app.session.clock.sim.tick
 app._process(0.1);ck(app.session.clock.sim.tick>tick,'mobile EX aiming does not pause simulation')
 app._suspend_mobile();tick=app.session.clock.sim.tick;app._process(0.1)
 ck(app.session.clock.sim.tick==tick and app.tactical_input.armed_actor==-1,'backgrounding pauses and cancels aim')
 app._resume_mobile();app._process(0.1);ck(app.session.clock.sim.tick>tick,'foreground resumes prior running state')
 app.settings_values.merge({'quality_preset':'high','render_scale':1.0,'fps_limit':120},true);app._apply_runtime_settings()
 ck(Engine.max_fps==120 and is_equal_approx(root.scaling_3d_scale,1.0),'requested resolution and 120FPS cap applied')
 app.queue_free();await process_frame;Engine.max_fps=0;root.scaling_3d_scale=1.0;finish()
func finish():print('MOBILE_APP_INTEGRATION checks=',checks,' failures=',failures);quit(1 if failures else 0)
