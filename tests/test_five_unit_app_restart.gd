extends SceneTree
const Session=preload('res://core/game_session.gd')
const Match=preload('res://core/tactical_match.gd')
var failures:=0
func ck(ok:bool,label:String):
 if not ok:failures+=1;printerr(label)
func _initialize():call_deferred('run')
func run():
 var app=load('res://scripts/gameplay.tscn').instantiate();app.persistence_enabled=false;root.add_child(app);await process_frame;app.set_process(false)
 var old_rules=Match.new();old_rules.new_match(23,app.session.catalog,{'level_shop_odds':1,'reinforcement_recruitment':1})
 var old:Dictionary=app.session.export_save().data
 old.version=8;old.seed=23;old.erase('rules_profile');old.rules=old_rules.snapshot()
 ck(app.session.restore_save(old).ok and app.session.rules_profile()==1,'load prior six-unit league')
 app._refresh(true)
 ck(app.act({'type':'restart','seed':24}).ok,'explicit app restart succeeds')
 ck(app.session.rules_profile()==3 and app.session.rules.snapshot().config.max_level==5,'app restart promotes historical league to short-round five-unit profile')
 ck(app.session.rules.get_player().level==4 and app.session.seed==24,'new game retains four starting slots and requested seed')
 ck(app._battle_status_text().contains('1–5'),'new game instruction uses five shortcut ceiling')
 app.queue_free();await process_frame
 print('FIVE_UNIT_APP_RESTART failures=',failures);quit(1 if failures else 0)
