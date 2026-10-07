extends SceneTree
var checks:=0
var failures:=0
func ck(value:bool,label:String):
 checks+=1
 if not value:failures+=1;printerr("FAIL: ",label)
func _initialize():call_deferred("run")
func run():
 var app=load("res://scripts/game_app.gd").new();app.persistence_enabled=false;root.add_child(app);app.set_process(false)
 ck(app.has_method("_preview_shop_offer"),"shop preview entry exists")
 if failures:app.free();quit(1);return
 app.act({"type":"restart","seed":17});app.session._sync_positions()
 await process_frame;await process_frame
 for i in app.shop.size():ck(not app.shop_preview_buttons[i].get_global_rect().intersects(app.shop_cards[i].name.get_global_rect()),"preview button does not obscure character name")
 var before:Dictionary=app.session.export_save();var selected:String=app.selected_owned
 app._checkpoint_dirty=false;app._autosave_pending=false
 app._preview_shop_offer(0)
 ck(app.recruitment_preview.visible,"occupied offer opens preview")
 ck(app.session.export_save()==before and app.selected_owned==selected,"preview changes no match or selected unit")
 ck(not app._checkpoint_dirty and not app._autosave_pending,"preview does not schedule a save")
 for button in app.shop:ck(button.disabled,"purchase blocked behind preview")
 ck(app.start_button.disabled,"start blocked behind preview")
 app._start_pressed();ck(app.session.phase()=="preparation" and app.session.export_save()==before,"start handler cannot leak through preview")
 var escape=InputEventKey.new();escape.pressed=true;escape.keycode=KEY_ESCAPE;app._unhandled_input(escape)
 ck(not app.recruitment_preview.visible and not app.game_menu.visible,"Escape closes preview without opening menu")
 ck(app.shop_preview_buttons[0].has_focus(),"focus returns to originating preview button")
 for index in [-1,5,999]:app._preview_shop_offer(index);ck(not app.recruitment_preview.visible,"invalid slot ignored")
 var snapshot:Dictionary=app.session.rules.snapshot();snapshot.players[0].gold=0;ck(app.session.rules.restore(snapshot).ok,"unaffordable fixture accepted")
 app._refresh_ui();ck(app.shop[0].disabled and not app.shop_preview_buttons[0].disabled,"preview available without gold")
 before=app.session.export_save();app._preview_shop_offer(0);ck(app.recruitment_preview.visible and app.session.export_save()==before,"unaffordable preview read-only")
 app._open_menu();ck(app.game_menu.visible and not app.recruitment_preview.visible,"menu dismisses preview")
 app._preview_shop_offer(0);ck(not app.recruitment_preview.visible,"menu blocks preview reopening");app._close_menu()
 app._preview_shop_offer(0);app.act({"type":"restart","seed":23});ck(not app.recruitment_preview.visible,"restart dismisses old offer")
 var p:Dictionary=app.session.rules.get_player();var cost:int=p.shop[0].cost;var gold:int=p.gold
 app.shop[0].pressed.emit()
 ck(app.session.rules.get_player().gold==gold-cost and app.session.rules.get_player().shop[0].is_empty(),"ordinary purchase unchanged")
 app._preview_shop_offer(0);ck(not app.recruitment_preview.visible and app.shop_preview_buttons[0].disabled,"empty offer cannot be previewed")
 app._preview_shop_offer(1);app.recruitment_preview.close_panel();app.recruitment_preview.close_panel()
 ck(not app.recruitment_preview.visible,"repeated close safe")
 # Hidden/other modal flows, stale snapshots, and actual checkpoint restore.
 app.report_panel.show();app._preview_shop_offer(1);ck(not app.recruitment_preview.visible,"report blocks preview");app.report_panel.hide()
 app.reinforcement_panel.show();app._preview_shop_offer(1);ck(not app.recruitment_preview.visible,"reinforcement blocks preview");app.reinforcement_panel.hide();app._refresh_ui()
 app._preview_shop_offer(1);before=app.session.export_save();app._sell_pressed();app._deploy_pressed()
 ck(app.session.export_save()==before,"sell/deploy handlers do not leak")
 app._open_reinforcement();ck(not app.reinforcement_panel.visible and app.recruitment_preview.visible,"reinforcement cannot stack over preview")
 snapshot=app.session.rules.snapshot();snapshot.players[0].shop[1]={};ck(app.session.rules.restore(snapshot).ok,"stale offer fixture accepted")
 app._refresh_ui();ck(not app.recruitment_preview.visible,"changed offer dismisses stale preview")
 app._preview_shop_offer(2);app.persistence_enabled=true;app.save_path="user://preview-checkpoint-test.json"
 var checkpoint:Dictionary=app.session.export_save();ck(app.SaveStore.write_save(checkpoint.data,app.save_path).ok,"checkpoint fixture written")
 ck(app._load_checkpoint().ok and not app.recruitment_preview.visible,"successful read dismisses preview")
 app._preview_shop_offer(2);before=app.session.export_save();app.save_path="user://preview-missing-%d.json"%Time.get_ticks_usec()
 ck(not app._load_checkpoint().ok and app.recruitment_preview.visible and app.session.export_save()==before,"failed read preserves preview and match")
 app.persistence_enabled=false
 app.free();await process_frame;print("RECRUITMENT_PREVIEW_APP ",checks," checks; ",failures," failures");quit(1 if failures else 0)
