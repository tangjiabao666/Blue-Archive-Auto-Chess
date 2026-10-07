extends SceneTree
var checks:=0
var failures:=0
func ck(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;printerr("FAIL: ",label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var app=load("res://scripts/game_app.gd").new();app.persistence_enabled=false;root.add_child(app);app.set_process(false)
 app.act({"type":"restart","seed":17})
 var p:Dictionary=app.session.rules._player_ref("p0");p.shop[0]={"character_id":"shiroko","cost":2}
 var purchase:Dictionary=app.act({"type":"buy_offer","slot":0});app.act({"type":"deploy_unit","unit_id":purchase.unit_id});app.select_owned(purchase.unit_id)
 ck(app.detail.text.contains("出售返还") and app.detail.text.contains("生命"),"preparation keeps owned-unit preview and management explanation")
 app.act({"type":"start_battle"});app.session.paused=true
 ck(app.inspected_id==-1 and app.selected_owned==purchase.unit_id,"battle does not silently change the user's saved owned selection")
 ck(app.detail.text.contains("点击") and app.detail.text.contains("实时"),"uninspected battle prompts actual live inspection")
 ck(not app.detail.text.contains("生命 %d"%app.session.clock.sim.units[0].max_hp) and not app.detail.text.contains("出售返还") and app.detail.tooltip_text.is_empty(),"battle placeholder does not present static preview stats as live values")
 var unit:Dictionary=app.session.clock.sim.units[0]
 unit.hp=unit.max_hp-123;unit.shield=321;unit.shield_until=200
 unit.buffs["inspector_fixture"]={"stat":"AttackSpeed","fraction":0.15,"until":200}
 app.stage.update_display(app.session.clock.sim.units,[],0.0,0)
 var before:Dictionary=app.session.clock.sim.snapshot()
 app.inspect_actor(0)
 var text:String=app.detail.text;var strip=app.stage.bars[0].status
 var hp_at:int=text.find("生命 %d / %d · 护盾 321"%[unit.hp,unit.max_hp])
 var details_at:int=text.find("攻击属性")
 var compact:String="EX %s · 小 %s · 子 %s"%[strip.status.ex.text,strip.status.basic.text,strip.status.sub.text]
 ck(text.find(compact)>hp_at and text.find(compact)<text.find(strip.status.ex.hint),"compact live cooldown summary is visible before expanded trigger explanations")
 ck(hp_at>=0 and details_at>hp_at,"live current HP and shield appear before reference details")
 for slot in ["ex","basic","sub"]:
  var hint:String=strip.status[slot].hint;var at:int=text.find(hint)
  ck(at>hp_at and at<details_at,"live "+slot+" status appears before matchup/reference text")
 for effect in strip.status.effects:
  var at:int=text.find(effect.hint)
  ck(at>hp_at and at<details_at,"active effect precedes reference information: "+effect.id)
 ck(text.contains("射程") and text.contains("防御装甲") and text.contains("属性倍率") and text.contains(app._character_hint("shiroko")),"weapon, matchup, caveat and character reference information remain available")
 ck(app.detail.tooltip_text.contains("非最终伤害"),"matchup tooltip retains its limitation")
 ck(app.session.clock.sim.snapshot()==before,"read-only live ordering cannot mutate combat")
 app.detail_scroll.scroll_vertical=90
 var scroll:int=app.detail_scroll.scroll_vertical
 app._refresh_inspector(true)
 ck(app.detail_scroll.scroll_vertical==scroll,"refreshing live information does not reset reader scroll")
 app._process(1.0)
 ck(app.detail.text==text and app.session.clock.sim.snapshot()==before,"paused inspector remains stable")
 unit.hp-=10;app._refresh_inspector()
 ck(app.detail.text.contains("生命 %d / %d"%[unit.hp,unit.max_hp]),"HP changes update current values")
 unit.hp=0;app._refresh_inspector()
 ck(app.inspected_id==-1 and app.detail.text.contains("实时") and not app.detail.text.contains("出售返还"),"dead inspected actor returns to live-selection prompt, not static stats")
 app.free();await process_frame
 print("LIVE_INSPECTOR_PRIORITY ",checks," checks; ",failures," failures");quit(1 if failures else 0)
