extends SceneTree
var checks:=0
var failures:=0
func ck(value:bool,label:String):
 checks+=1
 if not value:failures+=1;printerr("FAIL ",label)
func _initialize():call_deferred("run")
func reach_round(app,target:int):
 if app.session.rules.get_player().deployed.is_empty():
  var bought:Dictionary=app.session.command({"type":"buy_offer","slot":0})
  ck(bought.ok and app.session.command({"type":"deploy_unit","unit_id":bought.get("unit_id","")}).ok,"fixture owns legal deployed unit")
 while int(app.session.rules.snapshot().round)<target:
  var begun:Dictionary=app.session.rules.execute({"type":"start_battle"})
  if not begun.ok:ck(false,"fixture starts round");return
  var result:Dictionary=app.session.rules.execute({"type":"resolve_battle","battle_id":begun.battle.id,"winner":"player","player_remaining":1,"opponent_remaining":0})
  if not result.ok:ck(false,"fixture resolves round");return
 app.session._sync_positions();app._refresh(true)
func run():
 var app=load("res://scripts/game_app.gd").new();app.persistence_enabled=true;app.save_path="user://reinforcement-ui-%d.json"%Time.get_ticks_usec();app.settings_path="user://reinforcement-ui-%d.cfg"%Time.get_ticks_usec();root.add_child(app);app.set_process(false)
 ck(app.has_method("_open_reinforcement"),"app integrates chooser")
 if not app.has_method("_open_reinforcement"):app.free();finish();return
 if "--modal-only" in OS.get_cmdline_user_args():
  var player:Dictionary=app.session.rules._player_ref("p0")
  player["reinforcement"]={"round":3,"cost":2,"offers":["shiroko","yuuka","tsubaki"],"status":"pending","selected_slot":-1}
  app.refresh_button.grab_focus();app.stage.dragging=true;app._open_reinforcement()
  ck(not app.stage.dragging,"opening chooser cancels interrupted board drag")
  var state:Dictionary=app.session.rules.snapshot()
  for down in [true,false]:
   var space:=InputEventKey.new();space.keycode=KEY_SPACE;space.pressed=down;root.push_input(space,true)
  await process_frame
  ck(app.session.rules.snapshot()==state,"old keyboard focus cannot spend gold behind chooser")
  app._open_reinforcement()
  for i in range(15):
   var tab:=InputEventKey.new();tab.keycode=KEY_TAB;tab.pressed=true;root.push_input(tab,true);await process_frame
   ck(app.reinforcement_panel.is_ancestor_of(root.gui_get_focus_owner()),"actual Tab stays within chooser")
  app.reinforcement_panel.close_panel();ck(not app.stage.dragging,"closing chooser cannot resume old drag")
  app.free();finish();return
 app.act({"type":"restart","seed":17});ck(not app.reinforcement_button.visible,"no prompt before event round")
 reach_round(app,3);await process_frame
 var offer:Dictionary=app.session.rules.get_reinforcement()
 ck(offer.status=="pending" and app.reinforcement_button.visible,"event round shows pending affordance")
 var before:Dictionary=app.session.rules.snapshot()
 app.refresh_button.grab_focus();app.stage.dragging=true;app._start_pressed()
 ck(not app.stage.dragging,"real event chooser cancels interrupted drag")
 ck(app.reinforcement_panel.visible and app.session.phase()=="preparation","Start opens pending choice without starting battle")
 ck(app.refresh_button.disabled and app.start_button.disabled and app.normal_target_selector.disabled,"underlying actions keyboard inert")
 app.reinforcement_panel.close_button.pressed.emit();ck(app.session.rules.snapshot()==before and not app.reinforcement_panel.visible,"postpone never skips or rerolls")
 app._open_reinforcement();var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;root.push_input(escape,true);await process_frame
 ck(not app.reinforcement_panel.visible and not app.game_menu.visible,"Escape closes choice without opening menu")
 app._open_reinforcement();app._open_menu();ck(app.game_menu.visible and not app.reinforcement_panel.visible,"menu suspends chooser cleanly")
 app._claim_reinforcement(3,0);ck(app.session.rules.snapshot()==before,"stale chooser callback while menu open does nothing")
 app._close_menu();app._open_reinforcement();ck(app._save_checkpoint(false).ok,"pending offers saved")
 app._open_menu();app._load_checkpoint();ck(not app.reinforcement_panel.visible and not app.game_menu.visible,"load closes old chooser/menu")
 ck(app.session.rules.get_reinforcement()==offer,"load preserves exact offers")
 app._open_reinforcement();app._claim_reinforcement(6,0);ck(app.session.rules.get_reinforcement()==offer,"stale round cannot claim")
 app._open_reinforcement();var gold:int=app.session.rules.get_player().gold
 app.reinforcement_panel.claim_buttons[0].pressed.emit();ck(app.session.rules.get_reinforcement().status=="claimed","one displayed choice claims")
 ck(app.session.rules.get_player().gold==gold and not app.reinforcement_panel.visible,"claim is free and closes chooser")
 ck(not app.reinforcement_button.visible,"resolved event no longer prompts")
 var after:Dictionary=app.session.rules.snapshot();app._claim_reinforcement(3,1);ck(app.session.rules.snapshot()==after,"stale double claim has no effect")
 var disk:Dictionary=app.SaveStore.read_save(app.save_path);ck(disk.ok and disk.data.rules.players[0].reinforcement.status=="claimed","claim autosaved durably")
 app._open_menu();app._load_checkpoint();ck(app.session.rules.snapshot()==after,"reload cannot duplicate reward")
 app.act({"type":"restart","seed":17});reach_round(app,3);app._open_reinforcement()
 app.reinforcement_panel.skip_button.pressed.emit();app.reinforcement_panel.cancel_skip_button.pressed.emit();ck(app.session.rules.get_reinforcement().status=="pending","cancel explicit skip retains pending")
 app.reinforcement_panel.skip_button.pressed.emit();app.reinforcement_panel.confirm_skip_button.pressed.emit();ck(app.session.rules.get_reinforcement().status=="skipped" and not app.reinforcement_panel.visible,"confirmed skip consumes only current event")
 app.act({"type":"restart","seed":17});ck(not app.reinforcement_panel.visible and not app.reinforcement_button.visible,"restart discards stale event UI")
 var legacy:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/normal_target_legacy_session_v2.json"));ck(app.session.restore_save(legacy).ok,"real legacy fixture loads")
 app._refresh(true);ck(not app.reinforcement_button.visible,"old save has no retroactive recruitment")
 app.free();finish()
func finish():print("REINFORCEMENT APP ",checks," checks; ",failures," failures");quit(1 if failures else 0)
