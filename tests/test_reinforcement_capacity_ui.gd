extends SceneTree
var checks:=0
var failures:=0
func ck(value:bool,label:String):
 checks+=1
 if not value:failures+=1;printerr("FAIL ",label)
func _initialize():call_deferred("run")
func run():
 var app=load("res://scripts/game_app.gd").new();app.persistence_enabled=true;app.save_path="user://reinforcement-capacity-%d.json"%Time.get_ticks_usec();app.settings_path="user://reinforcement-capacity-%d.cfg"%Time.get_ticks_usec();root.add_child(app);app.set_process(false)
 app.act({"type":"restart","seed":17})
 var first:Dictionary=app.session.command({"type":"buy_offer","slot":0});app.session.command({"type":"deploy_unit","unit_id":first.unit_id})
 for i in range(2):
  var begun:Dictionary=app.session.rules.execute({"type":"start_battle"});app.session.rules.execute({"type":"resolve_battle","battle_id":begun.battle.id,"winner":"player","player_remaining":1,"opponent_remaining":0})
 var event:Dictionary=app.session.rules.get_reinforcement()
 var player:Dictionary=app.session.rules._player_ref("p0")
 # Deliberate inventory fixture; production acquisition/UI handle later actions.
 player.units.clear();player.bench.clear();player.deployed.clear()
 var pair:Dictionary=app.session.rules._acquire_one_star(player,event.offers[0]);app.session.rules._acquire_one_star(player,event.offers[0])
 app.session.command({"type":"deploy_unit","unit_id":pair.unit_id});app.session._sync_positions()
 ck(app.session.place(pair.unit_id,Vector2(1.5,3.0)),"manual deployed placement fixture")
 for key in app.session.ACTIVE:
  if key in event.offers:continue
  for i in range(2):
   if player.bench.size()<9:app.session.rules._acquire_one_star(player,key)
  if player.bench.size()==9:break
 app.session._sync_positions();app._refresh(true)
 ck(app.session.export_save().ok,"full bench fixture is a valid canonical save")
 app._open_reinforcement()
 ck(not app.reinforcement_panel.claim_buttons[0].disabled and app.reinforcement_panel.claim_buttons[1].disabled,"only immediate merge remains claimable")
 ck(app.reinforcement_panel.message.text.contains("上阵或出售"),"make-room instruction visible")
 var before:Dictionary=app.session.rules.snapshot();app.reinforcement_panel.claim_buttons[1].pressed.emit()
 ck(app.session.rules.snapshot()==before,"blocked slot cannot mutate live state")
 app.reinforcement_panel.close_panel()
 var to_sell:String=player.bench[-1];app.select_owned(to_sell);app._sell_pressed()
 ck(app.session.rules.get_player().bench.size()==8,"closed chooser allows ordinary sale")
 app._open_reinforcement();ck(not app.reinforcement_panel.claim_buttons[1].disabled,"reopen recalculates available capacity")
 var point:Vector2=app.session.positions[pair.unit_id];app.reinforcement_panel.claim_buttons[0].pressed.emit()
 var survivor:Dictionary=app.session._owned(app.session.rules.get_player(),pair.unit_id)
 ck(survivor.star==2 and survivor.ex_enabled,"UI claim performs ordinary third-copy merge")
 ck(app.session.positions[pair.unit_id]==point and app.session.manual_positions.has(pair.unit_id),"UI merge preserves manual deployed survivor")
 ck(app.session.rules.get_reinforcement().status=="claimed","choice consumed once")
 var saved:Dictionary=app.SaveStore.read_save(app.save_path)
 ck(saved.ok and saved.data.rules.players[0].reinforcement.status=="claimed","merged claim persisted")
 app.free();print("CAPACITY UI ",checks," checks; ",failures," failures");quit(1 if failures else 0)
