extends SceneTree
var failures:=0
var count:=0
func ck(ok:bool,message:String):
 count+=1
 if not ok:failures+=1;printerr('FAIL '+message)
func _initialize():call_deferred('run')
func run():
 ck(ResourceLoader.exists('res://scripts/title_menu.gd'),'title component exists')
 if failures:quit(1);return
 var menu=load('res://scripts/title_menu.gd').new();root.add_child(menu);await process_frame
 for key in ['new_button','continue_button','settings_button','exit_button']:ck(menu.get(key) is Button,'button exists '+key)
 menu.configure({'ok':false,'error':'save_not_found'},{});ck(menu.continue_button.disabled,'no save disables continue')
 menu.configure({'ok':false,'error':'invalid_save'},{});ck(menu.continue_button.disabled and menu.checkpoint_label.text.contains('保留'),'invalid save is preserved and explained')
 menu.configure({'ok':true,'data':{'rules':{'phase':'preparation','round':3}},'recovered':true},{});ck(not menu.continue_button.disabled and menu.checkpoint_label.text.contains('3') and menu.checkpoint_label.text.contains('备份'),'valid backup round shown')
 menu.configure({'ok':true,'data':{'rules':{'phase':'finished','round':6}}},{});ck(menu.continue_button.text=='查看上局结果','completed checkpoint opens result')
 var received:Array=[]
 menu.new_game_requested.connect(func():received.append('new'));menu.continue_requested.connect(func():received.append('continue'));menu.settings_requested.connect(func():received.append('settings'));menu.exit_requested.connect(func():received.append('exit'))
 for key in ['new_button','continue_button','settings_button','exit_button']:menu.get(key).pressed.emit()
 ck(received==['new','continue','settings','exit'],'four actions emitted once')
 menu.free();print('TITLE_MENU checks=',count,' failures=',failures);quit(1 if failures else 0)
