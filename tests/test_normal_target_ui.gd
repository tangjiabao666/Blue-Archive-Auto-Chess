extends SceneTree
var checks:=0
var failures:=0
func ck(ok:bool,msg:String):
 checks+=1
 if not ok:failures+=1;printerr(msg)
func _initialize():call_deferred("run")
func run():
 var app=load("res://scripts/game_app.gd").new();app.persistence_enabled=true
 app.save_path="user://target-ui-%d.json"%Time.get_ticks_usec();app.settings_path="user://target-ui-%d.cfg"%Time.get_ticks_usec()
 root.add_child(app);app.set_process(false)
 ck(app.has_method("_choose_normal_target_policy"),"preparation target selector must exist")
 if not app.has_method("_choose_normal_target_policy"):app.free();finish();return
 app.act({"type":"restart","seed":17})
 var selector:OptionButton=app.normal_target_selector
 ck(selector.item_count==2 and selector.selected==0 and not selector.disabled,"nearest default and both options available")
 var enemy:Dictionary={}
 for unit in app.stage.units:
  if unit.team==1:enemy=unit;break
 ck(not enemy.is_empty(),"preparation enemy preview exists")
 if not enemy.is_empty():app.inspect_actor(enemy.id)
 var inspected:int=app.inspected_id
 var before:Dictionary=app.session.rules.snapshot()
 selector.item_selected.emit(1)
 ck(app.session.normal_target_policy()=="wounded" and selector.selected==1,"selection signal applies wounded and synchronizes")
 ck(app.session.rules.snapshot()==before,"tactic costs no gold and consumes no economy RNG")
 ck(app.inspected_id==inspected and app.detail.text.contains("敌方"),"metadata-only tactic change preserves enemy inspection")
 var disk:Dictionary=app.SaveStore.read_save(app.save_path)
 ck(disk.ok and disk.data.normal_target_policy=="wounded","selection signal reaches persistent checkpoint")
 selector.item_selected.emit(1)
 ck(app.session.rules.snapshot()==before,"repeat selection is harmless")
 app._open_menu();selector.item_selected.emit(0)
 ck(app.session.normal_target_policy()=="wounded" and selector.disabled,"modal blocks selection signal")
 ck(not selector.get_popup().visible,"menu closes dropdown")
 app._close_menu();ck(not selector.disabled,"closing menu restores prep selector")
 app.report_panel.show();selector.item_selected.emit(0)
 ck(app.session.normal_target_policy()=="wounded","report blocks selection signal")
 app.report_panel.hide()
 for invalid in [-1,2,999]:app._choose_normal_target_policy(invalid)
 ck(app.session.normal_target_policy()=="wounded","invalid selection index rejected")
 app.warming=true;app._refresh_ui();selector.item_selected.emit(0)
 ck(selector.disabled and app.session.normal_target_policy()=="wounded","warmup prevents selection")
 app.warming=false;app._refresh_ui()
 ck(selector.tooltip_text.contains("护盾") and selector.tooltip_text.contains("嘲讽"),"tooltip discloses targeting limitations")
 ck(selector.position.y+selector.size.y<=app.detail_scroll.position.y,"selector and inspector do not overlap")
 ck(app.detail_scroll.position.y+app.detail_scroll.size.y==355,"inspector preserves lower boundary")
 app.act({"type":"restart","seed":17})
 ck(selector.selected==0 and app.session.normal_target_policy()=="nearest","restart restores nearest")
 if "--prep-only" in OS.get_cmdline_user_args():app.free();finish();return
 var player:Dictionary=app.session.rules._player_ref("p0")
 player.shop[0]={"character_id":"shiroko","cost":2}
 var bought:Dictionary=app.act({"type":"buy_offer","slot":0})
 ck(bought.ok and app.act({"type":"deploy_unit","unit_id":bought.unit_id}).ok,"legal army deployed")
 selector.item_selected.emit(1)
 ck(app.act({"type":"start_battle"}).ok,"battle starts with chosen tactic")
 selector.item_selected.emit(0)
 ck(selector.disabled and app.session.normal_target_policy()=="wounded","battle disallows changes")
 var ticks:=0
 while app.session.phase()=="battle" and ticks<2500:
  app.session.advance(0.05);ticks+=1
 app._refresh(false)
 ck(app.session.phase()=="result" and selector.disabled,"result keeps selector disabled")
 app.show_battle_report()
 ck(app.report_text.text.contains("我方残血优先") and app.report_text.text.contains("对手就近优先"),"report describes actual frozen policies")
 ck(app.act({"type":"next_round"}).ok,"next preparation available")
 selector.item_selected.emit(0)
 app.show_battle_report()
 ck(app.report_text.text.contains("我方残血优先"),"later selection does not relabel old report")
 app.report_panel.hide();app._refresh_ui()
 var saved:Dictionary=app.session.export_save()
 selector.item_selected.emit(1)
 ck(app.session.restore_save(saved.data).ok,"saved tactic restores")
 app._refresh(true)
 ck(selector.selected==0,"load synchronizes selector")
 app.free();finish()
func finish():print("NORMAL TARGET UI ",checks," checks; ",failures," failures");quit(1 if failures else 0)
