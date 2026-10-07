extends Control
signal new_game_requested
signal continue_requested
signal lan_requested
signal settings_requested
signal exit_requested
var new_button:Button
var continue_button:Button
var lan_button:Button
var settings_button:Button
var exit_button:Button
var checkpoint_label:Label
var message:Label
func _ready()->void:
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var background:=ColorRect.new();background.color=Color('10283e');background.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(background);background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var accent:=ColorRect.new();accent.color=Color('36bfe0');accent.position=Vector2(0,0);accent.size=Vector2(8,900);accent.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(accent)
 var center:=CenterContainer.new();add_child(center);center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var columns:=HBoxContainer.new();columns.add_theme_constant_override('separation',100);center.add_child(columns)
 var identity:=VBoxContainer.new();identity.custom_minimum_size=Vector2(420,420);identity.add_theme_constant_override('separation',20);columns.add_child(identity)
 _label(identity,'BLUE / A',58,Color('eaf7ff'))
 _label(identity,'战术自走棋',30,Color('5fd8ee'))
 _label(identity,'自由布阵  ·  实时指挥\n六轮对抗，争夺最终排名',20,Color('aac6d8'))
 var space:=Control.new();space.size_flags_vertical=Control.SIZE_EXPAND_FILL;identity.add_child(space)
 _label(identity,'PC 试玩版',16,Color('819eaf'))
 var actions:=VBoxContainer.new();actions.custom_minimum_size=Vector2(340,420);actions.add_theme_constant_override('separation',14);columns.add_child(actions)
 new_button=_button(actions,'新游戏',func():new_game_requested.emit())
 continue_button=_button(actions,'继续游戏',func():continue_requested.emit())
 checkpoint_label=_label(actions,'',16,Color('abc7d8'));checkpoint_label.custom_minimum_size.y=44
 lan_button=_button(actions,'局域网联机',func():lan_requested.emit())
 settings_button=_button(actions,'设置',func():settings_requested.emit())
 exit_button=_button(actions,'退出',func():exit_requested.emit())
 message=_label(actions,'',16,Color('f3cf95'));message.custom_minimum_size.y=50
 configure({'ok':false,'error':'save_not_found'}, {})
 new_button.grab_focus()
func configure(checkpoint:Dictionary,_preferences:Dictionary)->void:
 if not is_instance_valid(continue_button):return
 continue_button.disabled=not checkpoint.get('ok',false)
 continue_button.text='继续游戏'
 if checkpoint.get('ok',false):
  var state:Dictionary=checkpoint.get('data',{}).get('rules',{})
  var finished:bool=state.get('phase')=='finished'
  continue_button.text='查看上局结果' if finished else '继续游戏'
  checkpoint_label.text=('已完成对局' if finished else '第 %d 回合 · 继续备战'%int(state.get('round',1)))+(' · 备份恢复' if checkpoint.get('recovered',false) else '')
 else:
  checkpoint_label.text='暂无可继续的对局' if checkpoint.get('error','save_not_found')=='save_not_found' else '存档无法读取，原文件已保留'
func set_message(value:String)->void:
 message.text=value
func set_actions_enabled(enabled:bool,can_continue:bool=false)->void:
 for button in [new_button,lan_button,settings_button,exit_button]:button.disabled=not enabled
 continue_button.disabled=not enabled or not can_continue
func _label(parent:Node,value:String,size:int,color:Color)->Label:
 var label:=Label.new();label.text=value;label.add_theme_font_size_override('font_size',size);label.add_theme_color_override('font_color',color);parent.add_child(label);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;return label
func _button(parent:Node,value:String,callback:Callable)->Button:
 var button:=Button.new();button.text=value;button.custom_minimum_size=Vector2(340,58);button.add_theme_font_size_override('font_size',23)
 for key in ['normal','hover','pressed','focus','disabled']:
  var style:=StyleBoxFlat.new();style.bg_color=Color('21465f') if key=='normal' else Color('326682') if key=='hover' else Color('12374e') if key=='pressed' else Color('19374b') if key=='disabled' else Color(0,0,0,0)
  style.set_corner_radius_all(7)
  if key=='focus':style.set_border_width_all(2);style.border_color=Color('73e3f4')
  button.add_theme_stylebox_override(key,style)
 button.add_theme_color_override('font_color',Color('f1fbff'));button.add_theme_color_override('font_disabled_color',Color('748e9d'));button.pressed.connect(callback);parent.add_child(button);return button
