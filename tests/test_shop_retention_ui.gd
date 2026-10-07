extends SceneTree
var checks:=0
var failures:=0
func ck(ok:bool,msg:String):
 checks+=1
 if not ok:failures+=1;printerr(msg)
func _initialize():call_deferred("run")
func run():
 var app=load("res://scripts/game_app.gd").new();app.persistence_enabled=true
 app.save_path="user://shop-retention-ui-%d.json"%Time.get_ticks_usec();app.settings_path="user://shop-retention-ui-settings-%d.cfg"%Time.get_ticks_usec()
 root.add_child(app);app.set_process(false)
 ck(app.has_method("_toggle_shop_retention"),"shop retention control exists")
 if not app.has_method("_toggle_shop_retention"):app.free();finish();return
 app.act({"type":"restart","seed":17})
 var p:Dictionary=app.session.rules._player_ref("p0")
 var offers:Array=p.shop.duplicate(true);var gold:int=p.gold
 ck(not app.shop_lock_button.disabled and app.shop_lock_button.text.contains("保留至下回合"),"unlocked preparation offers retention")
 app.shop_lock_button.pressed.emit()
 var disk:Dictionary=app.SaveStore.read_save(app.save_path)
 ck(disk.ok and disk.data.rules.players[0].shop_locked,"button signal reaches the disk checkpoint")
 ck(p.shop_locked and p.shop==offers and p.gold==gold,"retention preserves offers and gold")
 ck(app.shop_lock_button.text.contains("取消") and app.shop_odds_label.text.contains("已保留"),"pending retention stays visible")
 ck(app.shop_lock_button.tooltip_text.contains("空位") and app.shop_lock_button.tooltip_text.contains("自动解除"),"tooltip explains holes and one-round consumption")
 app._toggle_shop_retention();ck(not p.shop_locked,"second click cancels")
 app._toggle_shop_retention();app.act({"type":"refresh_shop"})
 ck(not p.shop_locked and app.shop_lock_button.text.contains("保留至下回合"),"paid refresh clears lock UI")
 p.shop=[{},{},{},{},{}];app._refresh_ui()
 ck(app.shop_lock_button.disabled,"empty shop cannot be retained")
 p.shop[0]={"character_id":"shiroko","cost":2};p.gold=10;app._refresh_ui();app._toggle_shop_retention()
 var bought:Dictionary=app.act({"type":"buy_offer","slot":0})
 ck(bought.ok and not p.shop_locked and app.shop_lock_button.disabled,"buying final offer clears useless lock")
 app.act({"type":"deploy_unit","unit_id":bought.unit_id})
 p.shop[0]={"character_id":"serika","cost":1};app._refresh_ui();app._toggle_shop_retention()
 var saved:Dictionary=app.session.export_save()
 ck(saved.ok and saved.data.rules.players[0].shop_locked,"save retains pending flag")
 app._toggle_shop_retention();ck(app.session.restore_save(saved.data).ok,"load accepted checkpoint");app._refresh(true)
 p=app.session.rules._player_ref("p0")
 ck(p.shop_locked and app.shop_lock_button.text.contains("取消"),"load restores retention control")
 ck(app.act({"type":"start_battle"}).ok,"battle starts with pending retention")
 var before:Dictionary=app.session.rules.snapshot();app._toggle_shop_retention()
 ck(app.shop_lock_button.disabled and app.session.rules.snapshot()==before,"battle toggle is inert")
 var retained:Array=app.session.rules.get_player().shop.duplicate(true)
 var ticks:=0
 while app.session.phase()=="battle" and ticks<2500:
  app.session.advance(0.05);ticks+=1
 app._refresh(false)
 ck(app.session.phase()=="result" and app.session.rules.get_player().shop==retained,"real round retains exact remaining offers")
 ck(not app.session.rules.get_player().shop_locked and app.shop_lock_button.disabled,"result consumes lock once but controls stay disabled")
 ck(app.act({"type":"next_round"}).ok,"result acknowledgment succeeds")
 ck(not app.shop_lock_button.disabled and app.session.rules.get_player().shop==retained,"next preparation exposes retained offers without another refresh")

 ck(app.shop_lock_button.position==Vector2(990,721) and app.shop_lock_button.size==Vector2(252,30),"control fits existing shop header")
 ck(app.shop_lock_button.position.y+app.shop_lock_button.size.y<app.refresh_button.position.y,"control does not cover paid refresh")
 app.act({"type":"restart","seed":17});ck(not app.session.rules.get_player().shop_locked,"restart clears lock")
 app.free();finish()
func finish():print("SHOP RETENTION UI ",checks," checks; ",failures," failures");quit(1 if failures else 0)
