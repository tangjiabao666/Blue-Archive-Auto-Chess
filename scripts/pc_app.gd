extends Node
const TitleMenu=preload('res://scripts/title_menu.gd')
const SaveStore=preload('res://core/session_save_store.gd')
const UserSettings=preload('res://core/user_settings.gd')
const OffscreenWorker=preload('res://core/offscreen_process_worker.gd')
var flow_state:String='title'
var game:Node=null
var title_menu:Control
var save_path:String=SaveStore.DEFAULT_PATH
var settings_path:String=UserSettings.DEFAULT_PATH
var checkpoint:Dictionary={}
var preferences:Dictionary={}
var lan_room:Node
var lan_lobby:Control
var lan_game:Node3D
var _lan_warmup:Node
func _ready()->void:
 if _dispatch_worker_if_requested():return
 title_menu=TitleMenu.new();add_child(title_menu)
 var loaded:Dictionary=UserSettings.read_settings(settings_path)
 preferences=loaded.values
 _refresh_checkpoint()
 _setup_navigation()
func _dispatch_worker_if_requested()->bool:
 var args:PackedStringArray=OS.get_cmdline_user_args()
 if not OffscreenWorker.is_worker_request(args):return false
 get_tree().quit(OffscreenWorker.run_worker(args));return true
func _refresh_checkpoint()->Dictionary:
 checkpoint=SaveStore.read_save(save_path)
 if is_instance_valid(title_menu):title_menu.configure(checkpoint,preferences)
 return checkpoint

var replace_dialog:ConfirmationDialog
var settings_menu:Control
var _loading_panel:Control
var _loading_label:Label
var _load_generation:int=0
var _pending_replace_fingerprint:String=''
var _start_fingerprint:String=''
var _start_action:String=''
var _previous_auto_quit:bool=true
func _setup_navigation()->void:
 _previous_auto_quit=get_tree().auto_accept_quit;get_tree().auto_accept_quit=false
 title_menu.new_game_requested.connect(request_new_game)
 title_menu.continue_requested.connect(request_continue)
 title_menu.settings_requested.connect(_open_settings)
 title_menu.lan_requested.connect(_open_lan)
 title_menu.exit_requested.connect(request_exit)
 replace_dialog=ConfirmationDialog.new();replace_dialog.title='开始新游戏';replace_dialog.ok_button_text='确认新游戏';replace_dialog.cancel_button_text='取消';add_child(replace_dialog)
 replace_dialog.confirmed.connect(confirm_new_game)
 replace_dialog.canceled.connect(func():_pending_replace_fingerprint='';replace_dialog.hide())
 var loading_layer:=CanvasLayer.new();loading_layer.layer=100;add_child(loading_layer)
 _loading_panel=ColorRect.new();_loading_panel.color=Color('10283e');loading_layer.add_child(_loading_panel);_loading_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var center:=CenterContainer.new();_loading_panel.add_child(center);center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var box:=VBoxContainer.new();box.custom_minimum_size=Vector2(560,180);box.add_theme_constant_override('separation',28);center.add_child(box)
 _loading_label=Label.new();_loading_label.text='正在准备战场…';_loading_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_loading_label.add_theme_font_size_override('font_size',28);box.add_child(_loading_label)
 var cancel:=Button.new();cancel.text='返回主菜单';cancel.custom_minimum_size=Vector2(200,50);box.add_child(cancel);cancel.pressed.connect(_show_title)
 _loading_panel.hide()
 _apply_preferences()
func _checkpoint_fingerprint()->String:
 var values:Array[String]=[]
 for path in [save_path,save_path+'.bak']:
  if not FileAccess.file_exists(path):values.append('absent');continue
  var file=FileAccess.open(path,FileAccess.READ)
  if file==null:values.append('unreadable:'+str(FileAccess.get_modified_time(path)));continue
  var size:int=file.get_length()
  if size>SaveStore.MAX_BYTES:values.append('oversize:'+str(size)+':'+str(FileAccess.get_modified_time(path)))
  else:values.append(str(size)+':'+file.get_buffer(size).hex_encode().sha256_text())
  file.close()
 return '|'.join(values).sha256_text()
func _has_checkpoint_files()->bool:
 return FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path+'.bak')
func request_new_game()->void:
 if flow_state!='title' or (is_instance_valid(settings_menu) and settings_menu.visible):return
 _refresh_checkpoint()
 if _has_checkpoint_files():
  _pending_replace_fingerprint=_checkpoint_fingerprint()
  replace_dialog.dialog_text='新游戏会替换当前对局进度，是否继续？' if checkpoint.ok else '当前存档无法读取。新游戏将替换它；取消可保留原文件。'
  if DisplayServer.get_name()=='headless':replace_dialog.show()
  else:replace_dialog.popup_centered(Vector2i(520,180))
  return
 _start_game({'action':'new'})
func confirm_new_game()->void:
 if flow_state!='title' or _pending_replace_fingerprint.is_empty():return
 if _checkpoint_fingerprint()!=_pending_replace_fingerprint:
  _pending_replace_fingerprint='';request_new_game();title_menu.set_message('存档发生变化，请重新确认。');return
 _pending_replace_fingerprint='';replace_dialog.hide();_start_game({'action':'new'})
func request_continue()->void:
 if flow_state!='title' or replace_dialog.visible or (is_instance_valid(settings_menu) and settings_menu.visible):return
 var saved:Dictionary=_refresh_checkpoint()
 if not saved.ok:title_menu.set_message('无法继续：存档不可用，原文件已保留。');return
 _start_game({'action':'continue','payload':saved.data.duplicate(true)})
func _start_game(intent:Dictionary)->void:
 if flow_state!='title':return
 flow_state='loading';_load_generation+=1;_start_fingerprint=_checkpoint_fingerprint();_start_action=str(intent.action)
 title_menu.hide();_loading_panel.show();_loading_label.text='正在准备角色与战场…'
 call_deferred('_load_gameplay',intent,_load_generation)
func _instantiate_gameplay()->Node:
 var scene=load('res://scripts/gameplay.tscn')
 return scene.instantiate() if scene is PackedScene else null
func _load_gameplay(intent:Dictionary,generation:int)->void:
 await get_tree().process_frame
 if DisplayServer.get_name()!='headless':await RenderingServer.frame_post_draw
 if generation!=_load_generation or flow_state!='loading':return
 var instance:Node=_instantiate_gameplay()
 if instance==null:_finish_start({'ok':false,'error':'无法加载游戏场景'},generation,null);return
 game=instance;game.managed_startup=true;game.startup_intent=intent;game.persistence_enabled=true;game.save_path=save_path;game.settings_path=settings_path
 game.return_to_title_requested.connect(func():call_deferred("_finish_return",false))
 game.new_game_requested.connect(func():call_deferred("_finish_return",true))
 game.process_mode=Node.PROCESS_MODE_DISABLED
 game.startup_completed.connect(func(result):_finish_start(result,generation,instance),CONNECT_ONE_SHOT)
 add_child(game)
func _finish_start(result:Dictionary,generation:int,instance:Node)->void:
 if generation!=_load_generation or flow_state!='loading':return
 if not result.get('ok',false) or not is_instance_valid(instance):
  _show_title();title_menu.set_message('加载失败：'+str(result.get('error','游戏场景不可用')));return
 # Give queued cancellation input a full turn after synchronous scene allocation.
 # Do not save/publish the new runtime in the same frame as startup_completed.
 await get_tree().process_frame
 await get_tree().process_frame
 if generation!=_load_generation or flow_state!='loading' or not is_instance_valid(instance):return
 if _checkpoint_fingerprint()!=_start_fingerprint:
  _show_title();title_menu.set_message('加载期间存档发生变化，请重新选择。');return
 if _start_action=='new':
  var saved:Dictionary=game._save_checkpoint(false)
  if not saved.ok:
   _show_title();title_menu.set_message('新游戏未开始，进度保存失败：'+str(saved.error));return
 flow_state='game';_loading_panel.hide();title_menu.hide();game.process_mode=Node.PROCESS_MODE_INHERIT
func _show_title()->void:
 _clear_lan()
 _load_generation+=1
 if is_instance_valid(game):
  var old=game;game=null;old.process_mode=Node.PROCESS_MODE_DISABLED;remove_child(old);old.queue_free()
 flow_state='title';_start_action='';_pending_replace_fingerprint=''
 if is_instance_valid(_loading_panel):_loading_panel.hide()
 if is_instance_valid(settings_menu):settings_menu.hide()
 if is_instance_valid(replace_dialog):replace_dialog.hide()
 preferences=UserSettings.read_settings(settings_path).values
 title_menu.show();title_menu.set_message('');_refresh_checkpoint();title_menu.new_button.grab_focus()
func _open_settings()->void:
 if flow_state!='title' or replace_dialog.visible:return
 if not is_instance_valid(settings_menu):
  settings_menu=load('res://scripts/game_menu.gd').new();add_child(settings_menu);settings_menu.configure_frontend()
  settings_menu.closed.connect(_close_settings);settings_menu.settings_requested.connect(_save_preferences)
 settings_menu.open_menu(preferences,false,false,'设置仅在点击“应用设置”后保存。')
func _close_settings()->void:
 if is_instance_valid(settings_menu):settings_menu.hide()
 title_menu.settings_button.grab_focus()
func _save_preferences(values:Dictionary)->void:
 var result:Dictionary=UserSettings.write_settings(values,settings_path)
 if not result.ok:settings_menu.set_message('设置保存失败：'+str(result.error),true);return
 preferences=result.values;_apply_preferences();settings_menu.set_message('设置已保存')
func _apply_preferences()->void:
 if DisplayServer.get_name()=='headless':return
 var bus:int=AudioServer.get_bus_index('Master')
 if bus>=0:
  AudioServer.set_bus_mute(bus,bool(preferences.get('muted',false)) or float(preferences.get('volume',1.0))<=0)
  AudioServer.set_bus_volume_db(bus,linear_to_db(maxf(float(preferences.get('volume',1.0)),0.0001)))
 DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if preferences.get('fullscreen',false) else DisplayServer.WINDOW_MODE_WINDOWED)
func request_exit()->void:
 if flow_state=='lan' and is_instance_valid(lan_game):lan_game.request_close();return
 if flow_state=='game' and is_instance_valid(game):game._request_quit();return
 if flow_state=='loading':_show_title()
 get_tree().quit()
func _unhandled_input(event:InputEvent)->void:
 if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
  if flow_state in ['loading','lan_loading']:_show_title();get_viewport().set_input_as_handled()
  elif is_instance_valid(settings_menu) and settings_menu.visible:_close_settings();get_viewport().set_input_as_handled()
func _notification(what:int)->void:
 if what==NOTIFICATION_WM_CLOSE_REQUEST and is_inside_tree():request_exit()
func _exit_tree()->void:
 _load_generation+=1
 if get_tree():get_tree().auto_accept_quit=_previous_auto_quit

func _finish_return(restart:bool)->void:
 if flow_state!='game':return
 _show_title()
 if restart:request_new_game()

func _open_lan()->void:
 if flow_state!='title' or replace_dialog.visible:return
 flow_state='lan_loading';_load_generation+=1
 var generation:int=_load_generation
 title_menu.hide();_loading_label.text='正在准备联机角色资源…';_loading_panel.show()
 await get_tree().process_frame
 if generation!=_load_generation or flow_state!='lan_loading':return
 if DisplayServer.get_name()!='headless':
  _lan_warmup=load('res://scripts/render_warmup.gd').new();add_child(_lan_warmup)
  var catalog=load('res://core/game_session.gd').new()
  await _lan_warmup.run(catalog.profiles)
  if is_instance_valid(_lan_warmup):_lan_warmup.queue_free();_lan_warmup=null
 await get_tree().process_frame
 if generation!=_load_generation or flow_state!='lan_loading':return
 lan_room=load('res://scripts/lan/room_controller.gd').new();lan_room.name='LanRoom';add_child(lan_room)
 lan_lobby=load('res://scripts/lan/lobby.gd').new();add_child(lan_lobby);lan_lobby.bind_room(lan_room);lan_lobby.back_requested.connect(_show_title)
 lan_lobby.start_requested.connect(func():lan_room.start_match(int(Time.get_unix_time_from_system())%2147483646))
 lan_room.view_received.connect(_lan_view_received)
 lan_room.room_closed.connect(func(reason):call_deferred('_lan_failed',reason))
 _loading_panel.hide();flow_state='lan'
func _clear_lan()->void:
 if is_instance_valid(lan_game):remove_child(lan_game);lan_game.queue_free();lan_game=null
 if is_instance_valid(lan_lobby):lan_lobby.queue_free();lan_lobby=null
 if is_instance_valid(lan_room):lan_room.leave_room();lan_room.queue_free();lan_room=null
 if is_instance_valid(_lan_warmup):_lan_warmup.queue_free();_lan_warmup=null

func _lan_view_received(_view:Dictionary)->void:
 if is_instance_valid(lan_game):return
 lan_lobby.hide();lan_game=load('res://scripts/lan/game_client.gd').new();lan_game.settings_values=preferences;add_child(lan_game);lan_game.bind_room(lan_room)
 lan_game.leave_requested.connect(_show_title)
 lan_game.exit_requested.connect(func():_clear_lan();get_tree().quit())
func _lan_failed(reason:String)->void:
 if flow_state!='lan':return
 _show_title();title_menu.set_message('房间已结束：'+reason)
