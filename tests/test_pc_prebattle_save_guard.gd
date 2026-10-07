extends SceneTree
class FailedSaveApp extends "res://scripts/game_app.gd":
 var fail_writes:=false
 func _save_checkpoint(show_message:bool=false)->Dictionary:
  if fail_writes:_checkpoint_dirty=true;return {'ok':false,'error':'injected write failure'}
  return super._save_checkpoint(show_message)
var failures:=0
var exits:=0
func ck(ok:bool,label:String):
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():call_deferred('run')
func run():
 var game=FailedSaveApp.new();game.managed_startup=true;game.new_game_mode='tactical_v1';game.persistence_enabled=true;game.save_path='user://prebattle-guard-'+str(Time.get_ticks_usec())+'.json';root.add_child(game);game.set_process(false)
 game.return_to_title_requested.connect(func():exits+=1)
 ck(game._save_checkpoint().ok,'earlier same-round checkpoint exists')
 var old:Dictionary=game.session.export_save().data
 game.fail_writes=true
 var bought:Dictionary=game.act({'type':'buy_offer','slot':0});game.act({'type':'deploy_unit','unit_id':bought.unit_id})
 ck(game.act({'type':'start_battle'}).ok and game._checkpoint_dirty,'battle starts with visibly reported save failure')
 game.request_return_to_title();game.confirm_return_to_title()
 ck(exits==0 and game._return_discard_allowed,'stale same-round checkpoint requires explicit discard')
 game.return_dialog.canceled.emit();ck(exits==0 and not game._return_pending,'cancel keeps unsaved game alive')
 game.request_return_to_title();game.confirm_return_to_title();game.confirm_return_to_title(true)
 ck(exits==1,'explicit discard alone may leave failed-save battle')
 game.queue_free();await process_frame
 var second=FailedSaveApp.new();second.managed_startup=true;second.new_game_mode='tactical_v1';second.persistence_enabled=true;second.save_path='user://prebattle-change-'+str(Time.get_ticks_usec())+'.json';root.add_child(second);second.set_process(false)
 second.return_to_title_requested.connect(func():exits+=1)
 old=second.session.export_save().data
 bought=second.act({'type':'buy_offer','slot':0});second.act({'type':'deploy_unit','unit_id':bought.unit_id});second.act({'type':'start_battle'})
 ck(not second._checkpoint_dirty,'current prebattle checkpoint saved')
 preload('res://core/session_save_store.gd').write_save(old,second.save_path)
 second.request_return_to_title();second.confirm_return_to_title()
 ck(exits==1 and second._return_discard_allowed,'replacement same-seed same-round checkpoint is not treated as current')
 second.queue_free();await process_frame;print('PC_PREBATTLE_SAVE_GUARD failures=',failures);quit(1 if failures else 0)
