extends SceneTree
var checks:=0
var failures:=0
func ck(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr(label)
func _initialize():call_deferred("run")
func click_at(point:Vector2):
 for down in [true,false]:
  var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=point;root.push_input(event,true)
func report_data()->Dictionary:
 return {"completed":true,"round":1,"duration_seconds":3.0,"units":[],"normal_target_policies":["wounded","nearest"]}
func run():
 var app=load("res://scripts/game_app.gd").new();app.persistence_enabled=true;app.save_path="user://report-modal-%d.json"%Time.get_ticks_usec();app.settings_path="user://report-modal-%d.cfg"%Time.get_ticks_usec();root.add_child(app);app.set_process(false)
 ck(app.has_method("_close_battle_report"),"report has a modal lifecycle")
 if not app.has_method("_close_battle_report"):app.free();finish();return
 await process_frame
 app.refresh_button.grab_focus()
 app.session._feedback=report_data();app.show_battle_report()
 var keyboard_before:Dictionary=app.session.rules.snapshot()
 for down in [true,false]:
  var space:=InputEventKey.new();space.keycode=KEY_SPACE;space.pressed=down;root.push_input(space,true)
 await process_frame
 ck(app.session.rules.snapshot()==keyboard_before,"report prevents previously focused background keyboard activation")
 if not app.report_panel.visible:app.show_battle_report()
 ck(app.report_panel.visible and app.report_backdrop.visible,"opening report shows matching backdrop")
 ck(app.refresh_button.disabled and app.start_button.disabled and app.menu_button.disabled,"background controls are also keyboard-inert")
 ck(app.report_backdrop.mouse_filter==Control.MOUSE_FILTER_STOP,"backdrop intercepts background input")
 ck(app.report_panel.get_rect().end.x<1016,"report does not slice sidebar labels")
 ck(app.report_backdrop.color.a>0.2,"backdrop clearly dims inactive board")
 var before:Dictionary=app.session.rules.snapshot()
 click_at(app.refresh_button.get_global_rect().get_center());await process_frame
 ck(app.session.rules.snapshot()==before,"click through report cannot spend refresh gold")
 click_at(app.menu_button.get_global_rect().get_center());await process_frame
 ck(not app.game_menu.visible,"report blocks background menu button")
 ck(app.report_text.text.contains("我方残血优先"),"report retains frozen tactic label")
 var close:Button=app.report_panel.get_node("CloseReport")
 ck(close.has_theme_stylebox_override("normal"),"close control uses game button styling")
 click_at(close.get_global_rect().get_center());await process_frame
 ck(not app.report_panel.visible and not app.report_backdrop.visible,"close removes full modal")
 for i in range(3):app.show_battle_report();app._close_battle_report()
 ck(not app.report_backdrop.visible,"repeated report cycles leave no backdrop")
 app.show_battle_report()
 var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;root.push_input(escape,true);await process_frame
 ck(not app.report_panel.visible and not app.report_backdrop.visible and not app.game_menu.visible,"escape closes report without opening menu")
 app.show_battle_report();app.act({"type":"restart","seed":17})
 ck(not app.report_panel.visible and not app.report_backdrop.visible,"restart clears report backdrop")
 app.session._feedback=report_data();app.show_battle_report();app.report_panel.hide()
 ck(not app.report_backdrop.visible,"direct lifecycle hide clears backdrop")
 ck(app._save_checkpoint(false).ok,"isolated preparation checkpoint saved")
 app.session._feedback=report_data();app.show_battle_report();app._open_menu()
 ck(app.game_menu.visible and app.report_panel.visible,"menu can overlay an open report")
 root.push_input(escape,true);await process_frame
 ck(not app.game_menu.visible and app.report_panel.visible and app.report_backdrop.visible,"escape closes top menu while report remains modal")
 app._open_menu();app._load_checkpoint()
 ck(not app.game_menu.visible and not app.report_panel.visible and not app.report_backdrop.visible,"load clears menu and report backdrop")
 app.free();finish()
func finish():print("REPORT MODAL ",checks," checks; ",failures," failures");quit(1 if failures else 0)
