extends SceneTree
var failures:=0
func ck(ok:bool,label:String):
 if not ok:failures+=1;printerr('FAIL '+label)
func _initialize():call_deferred('run')
func run():
 var app=load('res://game.tscn').instantiate();app.save_path='user://lan-ui-'+str(Time.get_ticks_usec())+'.json';root.add_child(app)
 ck(app.title_menu.get('lan_button')!=null,'title exposes LAN entry')
 if failures:app.queue_free();await process_frame;quit(1);return
 app.title_menu.lan_button.pressed.emit()
 for i in range(10):await process_frame
 ck(app.flow_state=='lan' and app.game==null and app.lan_lobby.visible,'LAN lobby opens without single-player game')
 ck(app.lan_room.phase=='idle' and app.lan_room.wire.peer==null,'opening lobby does not create network connection')
 app._show_title();await process_frame
 ck(app.flow_state=='title' and not FileAccess.file_exists(app.save_path),'return does not create single-player checkpoint')
 app.queue_free();await process_frame;print('LAN_LOBBY_UI failures=',failures);quit(1 if failures else 0)
