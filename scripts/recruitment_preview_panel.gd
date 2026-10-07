extends Control
## Read-only recruitment information; never issues match commands.
signal closed
const Icons=preload("res://scripts/native_skill_icons.gd")
var icons=Icons.new()
var close_button:Button
var title_label:Label
var identity_label:Label
var stats_label:Label
var caveat_label:Label
var portrait:TextureRect
var scroll:ScrollContainer
var content:VBoxContainer
var skill_labels:Array[Label]=[]
func _ready()->void:
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP
 var shade=ColorRect.new();shade.color=Color(0.06,0.1,0.15,0.62);add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var panel=Panel.new();add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER);panel.position-=Vector2(450,295);panel.size=Vector2(900,590)
 var style=StyleBoxFlat.new();style.bg_color=Color("edf5fa");style.set_corner_radius_all(14);panel.add_theme_stylebox_override("panel",style)
 title_label=_label(panel,Rect2(26,18,700,36),25)
 close_button=Button.new();close_button.text="返回招募";close_button.position=Vector2(754,22);close_button.size=Vector2(120,34);close_button.add_theme_font_size_override("font_size",16);panel.add_child(close_button)
 for state in ["normal","hover","pressed","focus"]:
  var button_style=StyleBoxFlat.new();button_style.bg_color=Color("dfeef5") if state=="normal" else Color("bfdfef");button_style.set_corner_radius_all(7);close_button.add_theme_stylebox_override(state,button_style)
 for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:close_button.add_theme_color_override(state,Color("244c66"))
 close_button.pressed.connect(close_panel)
 portrait=TextureRect.new();portrait.position=Vector2(28,75);portrait.size=Vector2(212,200);portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_child(portrait)
 identity_label=_label(panel,Rect2(26,288,218,104),16)
 stats_label=_label(panel,Rect2(26,407,218,108),15)
 scroll=ScrollContainer.new();scroll.position=Vector2(266,76);scroll.size=Vector2(608,434);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.focus_mode=Control.FOCUS_ALL;panel.add_child(scroll)
 scroll.focus_next=scroll.get_path_to(close_button);scroll.focus_previous=scroll.focus_next
 close_button.focus_next=close_button.get_path_to(scroll);close_button.focus_previous=close_button.focus_next
 scroll.gui_input.connect(_scroll_key_input)
 content=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content.add_theme_constant_override("separation",10);scroll.add_child(content)
 caveat_label=_label(panel,Rect2(26,527,848,46),13)
 visibility_changed.connect(func():
  if visible:close_button.grab_focus()
 )
 hide()
func configure(data:Dictionary,art:Texture2D)->bool:
 if not data.get("ok",false) or data.get("skills",[]).size()!=3:hide();return false
 title_label.text="%s · %d 金币 · 招募前预览"%[data.name,int(data.cost)]
 portrait.texture=art
 identity_label.text="%s · %s\n攻击：%s\n装甲：%s\n普攻射程：%s"%[data.role,data.weapon,data.attack_type,data.armor_type,str(data.range).trim_suffix(".0")]
 stats_label.text=str(data.stats_text)
 caveat_label.text=str(data.caveat)
 for child in content.get_children():content.remove_child(child);child.queue_free()
 skill_labels.clear()
 for skill in data.skills:
  var card=PanelContainer.new();card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  var style=StyleBoxFlat.new();style.bg_color=Color.WHITE;style.set_corner_radius_all(10);style.content_margin_left=14;style.content_margin_right=14;style.content_margin_top=12;style.content_margin_bottom=12;card.add_theme_stylebox_override("panel",style);content.add_child(card)
  var column=VBoxContainer.new();column.add_theme_constant_override("separation",7);card.add_child(column)
  var heading=HBoxContainer.new();heading.add_theme_constant_override("separation",10);column.add_child(heading)
  var backing=PanelContainer.new();backing.custom_minimum_size=Vector2(32,32);var icon_style=StyleBoxFlat.new();icon_style.bg_color=Color("34556b");icon_style.set_corner_radius_all(6);backing.add_theme_stylebox_override("panel",icon_style);heading.add_child(backing)
  var icon=TextureRect.new();icon.custom_minimum_size=Vector2(32,32);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;backing.add_child(icon)
  var texture:Texture2D=icons.texture(str(skill.get("icon_key","")))
  if texture!=null:
   var atlas=AtlasTexture.new();atlas.atlas=texture;atlas.region=icons.region(str(skill.icon_key));icon.texture=atlas
  var title=Label.new();title.text=str(skill.label)+" · "+str(skill.name);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;title.add_theme_font_size_override("font_size",17);title.add_theme_color_override("font_color",Color("25455a"));heading.add_child(title)
  var body=Label.new();body.text=str(skill.text);body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_theme_font_size_override("font_size",15);body.add_theme_color_override("font_color",Color("36566b"));column.add_child(body);skill_labels.append(body)
 var enhanced=Label.new();enhanced.text=str(data.enhanced_text);enhanced.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;enhanced.add_theme_font_size_override("font_size",15);enhanced.add_theme_color_override("font_color",Color("36566b"));content.add_child(enhanced)
 scroll.scroll_vertical=0
 return true
func close_panel()->void:
 if not visible:return
 hide();closed.emit()
func _label(parent:Control,rect:Rect2,font_size:int)->Label:
 var label=Label.new();label.position=rect.position;label.size=rect.size;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.mouse_filter=Control.MOUSE_FILTER_IGNORE;label.add_theme_font_size_override("font_size",font_size);label.add_theme_color_override("font_color",Color("25455a"));parent.add_child(label);return label

func _scroll_key_input(event:InputEvent)->void:
 if not visible or not event is InputEventKey or not event.pressed:return
 var amount:int=0
 match event.keycode:
  KEY_DOWN:amount=36
  KEY_UP:amount=-36
  KEY_PAGEDOWN:amount=int(scroll.size.y*0.8)
  KEY_PAGEUP:amount=-int(scroll.size.y*0.8)
  KEY_HOME:scroll.scroll_vertical=0;scroll.accept_event();return
  KEY_END:scroll.scroll_vertical=int(scroll.get_v_scroll_bar().max_value);scroll.accept_event();return
  _:return
 scroll.scroll_vertical+=amount;scroll.accept_event()
