extends SceneTree
class ReadyGame extends Node:
 signal startup_completed(result:Dictionary)
 signal return_to_title_requested
 signal new_game_requested
 var managed_startup:bool
 var startup_intent:Dictionary
 var persistence_enabled:bool
 var save_path:String
 var settings_path:String
 func _ready():
  startup_completed.emit({'ok':true})
  get_parent().call_deferred('_show_title') # Input queued while synchronous allocation was busy.
 func _save_checkpoint(_show:bool)->Dictionary:
  get_parent().checkpoint_writes+=1
  return {'ok':true}
class App extends "res://scripts/pc_app.gd":
 var checkpoint_writes:=0
 func _instantiate_gameplay()->Node:return ReadyGame.new()
var failures:=0
func _initialize():call_deferred('run')
func run():
 var app=App.new();app.save_path='user://ready-cancel-'+str(Time.get_ticks_usec())+'.json';root.add_child(app);app.request_new_game()
 for i in range(6):await process_frame
 if app.checkpoint_writes!=0:failures+=1;printerr('FAIL queued cancel must get an input turn before initial save publication')
 if app.flow_state!='title' or app.game!=null:failures+=1;printerr('FAIL cancel leaves no active game')
 app.queue_free();await process_frame;print('PC_READY_CANCEL failures=',failures);quit(1 if failures else 0)
