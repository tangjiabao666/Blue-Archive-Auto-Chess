extends Control
## Modal presentation only. The app owns pause, persistence and applying settings.
signal closed
signal save_requested
signal continue_requested
signal settings_requested(values:Dictionary)
signal return_to_title_requested
signal quit_requested
var volume:HSlider
var muted:CheckBox
var fullscreen:CheckBox
var reduce_smoke:CheckBox
var mobile_mode:bool=false
var quality_preset:OptionButton
var render_scale:OptionButton
var fps_limit:OptionButton
var save_button:Button
var continue_button:Button
var apply_button:Button
var close_button:Button
var title_button:Button
var quit_button:Button
var message:Label
var _volume_label:Label
var _panel:Panel
var _heading:Label
var _description:Label
var _mobile_controls:Array[Control]=[]
const QUALITY_PRESETS:Array[String]=["performance","balanced","high"]
const RENDER_SCALES:Array[float]=[0.5,0.67,0.85,1.0]
const FPS_LIMITS:Array[int]=[30,60,90,120]
func _ready()->void:
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter=Control.MOUSE_FILTER_STOP
 var shade=ColorRect.new();shade.color=Color(0.06,0.1,0.15,0.55);add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shade.mouse_filter=Control.MOUSE_FILTER_STOP
 _panel=Panel.new();add_child(_panel)
 var panel:Panel=_panel;panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER);panel.position-=Vector2(290,268);panel.size=Vector2(580,536)
 var style=StyleBoxFlat.new();style.bg_color=Color("edf5fa");style.set_corner_radius_all(12);panel.add_theme_stylebox_override("panel",style)
 _heading=_label(panel,"游戏菜单",Rect2(24,16,530,35),24)
 _description=_label(panel,"存档保留回合准备进度；战斗中读取会回到开战前。",Rect2(24,55,530,30),14)
 _label(panel,"总音量",Rect2(24,103,100,30),17)
 volume=HSlider.new();volume.position=Vector2(130,104);volume.size=Vector2(330,30);volume.min_value=0;volume.max_value=100;volume.step=1;panel.add_child(volume)
 _volume_label=_label(panel,"100%",Rect2(484,103,70,30),17)
 volume.value_changed.connect(func(value):_volume_label.text="%d%%"%int(value))
 muted=CheckBox.new();muted.text="静音";muted.position=Vector2(24,148);muted.size=Vector2(230,34);panel.add_child(muted)
 fullscreen=CheckBox.new();fullscreen.text="全屏显示";fullscreen.position=Vector2(292,148);fullscreen.size=Vector2(240,34);panel.add_child(fullscreen)
 reduce_smoke=CheckBox.new();reduce_smoke.text="减弱烟雾遮挡";reduce_smoke.position=Vector2(24,194);reduce_smoke.size=Vector2(532,34);reduce_smoke.focus_mode=Control.FOCUS_ALL;panel.add_child(reduce_smoke)
 reduce_smoke.tooltip_text="仅影响画面：将已识别的浓烟粒子的 Alpha 乘以 55%；默认关闭，保留原始效果。不改变伤害或战斗规则。"
 for checkbox in [muted,fullscreen,reduce_smoke]:
  checkbox.add_theme_font_size_override("font_size",17)
  checkbox.add_theme_color_override("font_color",Color("25455a"))
  checkbox.add_theme_color_override("font_hover_color",Color("173c56"))
  checkbox.add_theme_color_override("font_pressed_color",Color("173c56"))
  checkbox.add_theme_color_override("font_focus_color",Color("173c56"))
 _mobile_controls.append(_label(panel,"画质预设",Rect2(24,260,160,32),17))
 quality_preset=_option(panel,Rect2(194,254,362,44),["流畅","均衡","高清"],QUALITY_PRESETS)
 quality_preset.item_selected.connect(_select_quality_preset)
 _mobile_controls.append(_label(panel,"3D 分辨率",Rect2(24,314,160,32),17))
 render_scale=_option(panel,Rect2(194,308,362,44),["50%","67%","85%","100%"],RENDER_SCALES)
 render_scale.tooltip_text="仅调整 3D 渲染分辨率，原生 UI 清晰度与触控区域不变。"
 _mobile_controls.append(_label(panel,"帧率上限",Rect2(24,368,160,32),17))
 fps_limit=_option(panel,Rect2(194,362,362,44),["30 FPS","60 FPS","90 FPS","120 FPS（目标上限）"],FPS_LIMITS)
 _mobile_controls.append(_label(panel,"原生 UI 不变；帧率为目标上限，实际表现取决于设备与场景。",Rect2(24,416,532,30),14))
 _restore_quality({})
 apply_button=_button(panel,"应用设置",Rect2(24,248,252,40),func():settings_requested.emit(read_preferences()))
 close_button=_button(panel,"返回游戏",Rect2(304,248,252,40),func():closed.emit())
 save_button=_button(panel,"保存回合进度",Rect2(24,309,252,40),func():save_requested.emit())
 continue_button=_button(panel,"读取上次存档",Rect2(304,309,252,40),func():continue_requested.emit())
 quit_button=_button(panel,"退出游戏",Rect2(24,370,532,40),func():quit_requested.emit())
 title_button=_button(panel,"返回主菜单",Rect2(24,370,252,40),func():return_to_title_requested.emit());title_button.hide()
 message=_label(panel,"",Rect2(24,428,532,80),15);message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 configure_mobile(mobile_mode)
 hide()
func configure_mobile(enabled:bool)->void:
 mobile_mode=enabled
 if not is_instance_valid(_panel):return
 fullscreen.visible=not enabled
 for control in _mobile_controls:control.visible=enabled
 var height:float=730.0 if enabled else 536.0
 _panel.offset_left=-290;_panel.offset_right=290
 _panel.offset_top=-height/2.0;_panel.offset_bottom=height/2.0
 volume.position.y=100 if enabled else 104;volume.size.y=44 if enabled else 30
 muted.size.y=44 if enabled else 34
 reduce_smoke.position.y=200 if enabled else 194;reduce_smoke.size.y=44 if enabled else 34
 for button in [apply_button,close_button,save_button,continue_button,quit_button]:button.size.y=44 if enabled else 40
 apply_button.position.y=462 if enabled else 248;close_button.position.y=apply_button.position.y
 save_button.position.y=526 if enabled else 309;continue_button.position.y=save_button.position.y
 quit_button.position.y=590 if enabled else 370
 message.position.y=654 if enabled else 428;message.size.y=60 if enabled else 80
func open_menu(values:Dictionary,can_save:bool,can_continue:bool,note:String)->void:
 volume.value=roundf(float(values.get("volume",1.0))*100)
 muted.button_pressed=bool(values.get("muted",false));fullscreen.button_pressed=bool(values.get("fullscreen",false))
 reduce_smoke.button_pressed=bool(values.get("reduce_smoke",false))
 if mobile_mode:_restore_quality(values)
 save_button.disabled=not can_save;continue_button.disabled=not can_continue
 save_button.tooltip_text="战斗中保留开战前的准备存档" if not can_save else "保存当前准备进度，保留商店和已锁定的对手"
 set_message(note);show();close_button.grab_focus()
func read_preferences()->Dictionary:
 var values:Dictionary={"volume":float(volume.value)/100.0,"muted":muted.button_pressed,"fullscreen":fullscreen.button_pressed,"reduce_smoke":reduce_smoke.button_pressed}
 if mobile_mode:
  values.merge({"quality_preset":quality_preset.get_selected_metadata(),"render_scale":render_scale.get_selected_metadata(),"fps_limit":fps_limit.get_selected_metadata()})
 return values
func _restore_quality(values:Dictionary)->void:
 # select() restores the independent values without emitting item_selected or Apply.
 var preset_index:int=QUALITY_PRESETS.find(values.get("quality_preset","balanced"))
 var scale_index:int=RENDER_SCALES.find(values.get("render_scale",0.85))
 var fps_index:int=FPS_LIMITS.find(values.get("fps_limit",60))
 quality_preset.select(preset_index if preset_index>=0 else 1)
 render_scale.select(scale_index if scale_index>=0 else 2)
 fps_limit.select(fps_index if fps_index>=0 else 1)
func _select_quality_preset(index:int)->void:
 if index<0 or index>=QUALITY_PRESETS.size():return
 # Presets propose only scale and frame cap; smoke remains a separate manual choice.
 render_scale.select([1,2,3][index]);fps_limit.select(3 if index==2 else 1)
func _option(parent:Control,rect:Rect2,labels:Array,values:Array)->OptionButton:
 var node=OptionButton.new();node.position=rect.position;node.size=rect.size;node.custom_minimum_size.y=44
 node.add_theme_font_size_override("font_size",17)
 for index in range(labels.size()):
  node.add_item(labels[index]);node.set_item_metadata(index,values[index])
 node.get_popup().add_theme_font_size_override("font_size",17)
 node.get_popup().add_theme_constant_override("v_separation",24)
 _style_button(node);parent.add_child(node);_mobile_controls.append(node);return node
func set_message(text:String,failed:bool=false)->void:
 message.text=text;message.add_theme_color_override("font_color",Color("a43d53") if failed else Color("36566b"))
func _label(parent:Control,text:String,rect:Rect2,size:int)->Label:
 var node=Label.new();node.text=text;node.position=rect.position;node.size=rect.size;node.add_theme_font_size_override("font_size",size);node.add_theme_color_override("font_color",Color("25455a"));node.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(node);return node
func _button(parent:Control,text:String,rect:Rect2,callback:Callable)->Button:
 var node=Button.new();node.text=text;node.position=rect.position;node.size=rect.size;node.add_theme_font_size_override("font_size",17)
 _style_button(node);parent.add_child(node);node.pressed.connect(callback);return node
func _style_button(node:Button)->void:
 for kind in ["normal","hover","pressed","disabled"]:
  var style=StyleBoxFlat.new();style.bg_color=Color("dfeef5") if kind=="normal" else Color("bfdfef") if kind=="hover" else Color("a9d5e8") if kind=="pressed" else Color("e7ecef");style.set_corner_radius_all(7);node.add_theme_stylebox_override(kind,style)
 node.add_theme_color_override("font_color",Color("244c66"));node.add_theme_color_override("font_hover_color",Color("173c56"));node.add_theme_color_override("font_pressed_color",Color("173c56"));node.add_theme_color_override("font_disabled_color",Color("8296a3"))
 node.add_theme_color_override("font_focus_color",Color("173c56"))

func configure_frontend()->void:
 _heading.text="设置";_description.text="调整声音与显示选项。"
 save_button.hide();continue_button.hide();quit_button.hide()
 close_button.text="返回主菜单"
 _panel.offset_top=-205;_panel.offset_bottom=205
 message.position.y=310;message.size.y=76

func configure_title_navigation()->void:
 title_button.show();quit_button.size.x=252;quit_button.position.x=304
