extends SceneTree
var failures:=0
func ck(ok:bool,label:String):
 if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize():call_deferred("run")
func run():
 var app=load("res://scripts/gameplay.tscn").instantiate();root.add_child(app);await process_frame;app.set_process(false)
 ck(app.get("shop_odds_label") is Label,"shop displays visible current next-refresh odds")
 if failures:app.queue_free();await process_frame;print("SHOP ODDS UI FAILURES=",failures);quit(1);return
 ck(app.shop_odds_label.text.contains("4级") and app.shop_odds_label.text.contains("44%") and app.shop_odds_label.text.contains("12%"),"initial table matches level-four rule")
 ck(app.shop_odds_label.tooltip_text.contains("同费") and app.shop_odds_label.tooltip_text.contains("不会刷新"),"tooltip explains within-tier chances and XP behavior")
 var p:Dictionary=app.session.rules._player_ref("p0");p.gold=100;p.xp=4
 var shop:Array=p.shop.duplicate(true);var rng:int=app.session.rules.snapshot().rng_state
 ck(app.act({"type":"buy_xp"}).ok,"actual UI command upgrades population")
 ck(app.shop_odds_label.text.contains("5级") and app.shop_odds_label.text.contains("20%"),"odds line updates with new population")
 ck(p.shop==shop and app.session.rules.snapshot().rng_state==rng,"UI refresh does not secretly redraw existing cards")
 var state:Dictionary=app.session.rules.snapshot();app._refresh_ui();app._refresh_ui()
 ck(app.session.rules.snapshot()==state,"repainting odds is read-only")
 ck(app.xp_button.disabled and app.xp_button.tooltip_text.contains("最多上阵 5 人") and not app.xp_button.tooltip_text.contains("升至 6 级"),"maximum-five UI clearly stops upgrades without advertising a sixth slot")
 ck(not app.act({"type":"buy_offer","slot":99}).ok and not app.shop_odds_label.visible and not app.notice.text.is_empty(),"error notice replaces odds rather than overlapping it")
 ck(app.act({"type":"refresh_shop"}).ok and app.shop_odds_label.visible and app.notice.text.is_empty(),"successful action restores odds display")
 app.queue_free();await process_frame;print("SHOP ODDS UI FAILURES=",failures);quit(1 if failures else 0)
