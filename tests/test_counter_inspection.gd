extends SceneTree
var checks:=0
var failures:=0
func ck(ok:bool,message:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL ",message)
func _initialize():call_deferred("run")
func run():
 var app=load("res://scripts/game_app.gd").new();app.persistence_enabled=false;root.add_child(app);app.set_process(false)
 ck(app.has_method("inspect_actor"),"read-only enemy inspection exists")
 if not app.has_method("inspect_actor"):app.free();finish();return
 app.act({"type":"restart","seed":17})
 var p:Dictionary=app.session.rules._player_ref("p0")
 p.shop[0]={"character_id":"shiroko","cost":2}
 var purchase:Dictionary=app.act({"type":"buy_offer","slot":0})
 app.act({"type":"deploy_unit","unit_id":purchase.unit_id})
 var enemy:Dictionary={}
 for unit in app.stage.units:
  if unit.team==1:enemy=unit;break
 ck(not enemy.is_empty(),"locked opponent is available")
 var before:Dictionary=app.session.export_save().data.duplicate(true)
 ck(app.stage.bars[enemy.id].has("hit"),"status block has a read-only inspection target")
 if not app.stage.bars[enemy.id].has("hit"):app.free();finish();return
 app.select_owned(purchase.unit_id)
 var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
 click.position=app.stage.bars[enemy.id].hit.get_global_rect().get_center();root.push_input(click,true)
 ck(app.inspected_id==enemy.id and app.session.export_save().data==before,"clicking displaced enemy status inspects without moving ally")

 app.inspect_actor(enemy.id)
 ck(app.inspected_id==enemy.id and app.detail.text.contains("敌方"),"enemy opens side-aware inspector")
 ck(app.detail.text.contains("承伤") and app.detail.text.contains("属性倍率"),"enemy shows effective matchup caveat")
 ck(app.deploy_button.disabled and app.sell_button.disabled,"enemy inspection disables owned actions")
 ck(app.stage.selected_id==-1 and not app.stage.dragging,"inspection clears deployment gesture")
 for i in range(5):app.inspect_actor(enemy.id);app._refresh_ui()
 ck(app.session.export_save().data==before,"repeated inspection preserves rules RNG positions and save payload")
 app.select_owned(purchase.unit_id)
 ck(app.inspected_id==-1 and not app.sell_button.disabled,"own selection restores appropriate actions")
 ck(app.detail.text.contains("攻击属性") and app.detail.tooltip_text.contains("非最终伤害"),"own unit exposes matchup without overclaim")
 app.inspect_actor(enemy.id);app.inspect_actor(999999)
 ck(app.inspected_id==-1,"stale actor cannot be inspected")
 ck(not app.detail.text.contains("敌方") and not app.sell_button.disabled,"invalid inspection restores own panel and actions")
 app.inspect_actor(enemy.id)
 app._open_menu();var held:int=app.inspected_id
 app.inspect_actor(0)
 ck(app.inspected_id==held,"modal menu blocks inspection")
 app._close_menu()
 app.act({"type":"start_battle"})
 ck(app.inspected_id==-1,"new battle clears stale preview identity")
 app.session.paused=true
 var sim_before:Dictionary=app.session.clock.sim.snapshot()
 app.inspect_actor(0);app._refresh_inspector()
 ck(app.inspected_id==0 and app.detail.text.contains("己方"),"battle own actor can be inspected")
 ck(app.deploy_button.disabled and app.sell_button.disabled,"battle inspection has no management action")
 ck(app.session.clock.sim.snapshot()==sim_before,"battle inspection cannot alter simulation")
 app.session.clock.sim.units[0].hp=0;app._refresh_inspector()
 ck(app.inspected_id==-1,"dead actor clears inspection")
 app.act({"type":"restart","seed":17})
 ck(app.inspected_id==-1,"restart clears transient inspection")
 app.free();finish()
func finish():print("COUNTER INSPECTION ",checks," checks; ",failures," failures");quit(1 if failures else 0)
