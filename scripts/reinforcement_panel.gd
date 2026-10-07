extends Control
## Presentation only; rules own the offer and app owns transactions/persistence.
signal claim_requested(round:int,slot:int)
signal skip_requested(round:int)
signal closed
var claim_buttons:Array[Button]=[]
var close_button:Button
var skip_button:Button
var confirm_skip_button:Button
var cancel_skip_button:Button
var title_label:Label
var subtitle_label:Label
var message:Label
var _names:Array[Label]=[]
var _progress:Array[Label]=[]
var _descriptions:Array[Label]=[]
var _portraits:Array[TextureRect]=[]
var _event:Dictionary={}
var _cards:Array=[]
var _submitted:=false
var _confirming:=false
func _ready()->void:
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP
 var shade:=ColorRect.new();shade.color=Color(0.06,0.1,0.15,0.62);add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var panel:=Panel.new();add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER);panel.position-=Vector2(434,270);panel.size=Vector2(868,540)
 var style:=StyleBoxFlat.new();style.bg_color=Color("edf5fa");style.set_corner_radius_all(14);panel.add_theme_stylebox_override("panel",style)
 title_label=_label(panel,"增援招募",Rect2(26,18,610,34),24)
 subtitle_label=_label(panel,"",Rect2(26,59,810,48),15)
 close_button=_button(panel,"稍后选择",Rect2(706,20,136,34),close_panel)
 for index in range(3):
  var slot:=index
  var x:float=26+index*276
  var card:=Panel.new();card.position=Vector2(x,119);card.size=Vector2(264,299);panel.add_child(card)
  var card_style:=StyleBoxFlat.new();card_style.bg_color=Color("ffffff");card_style.set_corner_radius_all(10);card.add_theme_stylebox_override("panel",card_style)
  var art:=TextureRect.new();art.position=Vector2(12,12);art.size=Vector2(240,126);art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.mouse_filter=Control.MOUSE_FILTER_IGNORE;card.add_child(art);_portraits.append(art)
  _names.append(_label(card,"",Rect2(12,142,240,27),20))
  _progress.append(_label(card,"",Rect2(12,173,240,23),15))
  var description:=_label(card,"",Rect2(12,201,240,44),13);description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_descriptions.append(description)
  claim_buttons.append(_button(card,"免费招募",Rect2(12,252,240,35),func():_claim(slot)))
 message=_label(panel,"",Rect2(26,429,816,40),15);message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 skip_button=_button(panel,"放弃本次增援",Rect2(638,482,204,34),_ask_skip)
 confirm_skip_button=_button(panel,"确认放弃",Rect2(638,482,204,34),_confirm_skip)
 cancel_skip_button=_button(panel,"返回选择",Rect2(422,482,204,34),_cancel_skip)
 _label(panel,"每局两次 · 三合一升星规则不变",Rect2(26,482,380,34),14)
 visibility_changed.connect(func():
  if visible and close_button:close_button.grab_focus()
 )
 hide()
func configure(event:Dictionary,cards:Array)->void:
 _event=event.duplicate(true);_cards=cards.duplicate(true);_submitted=false;_confirming=false
 if _event.get("status","")!="pending" or cards.size()!=3 or _event.get("offers",[]).size()!=3:
  hide();_event.clear();return
 title_label.text="第 %d 回合 · 增援招募"%int(_event.round)
 subtitle_label.text="从 3 名 %d 费角色中免费选择 1 名一星角色。\n可先关闭查看敌阵或整理备战席；开战前需要选择或明确放弃。"%int(_event.cost)
 for i in range(3):
  _names[i].text=str(_cards[i].get("name",""));_progress[i].text=str(_cards[i].get("progress",""));_descriptions[i].text=str(_cards[i].get("description",""))
  _descriptions[i].tooltip_text=str(_cards[i].get("tooltip",_descriptions[i].text));_portraits[i].texture=_cards[i].get("portrait")
  claim_buttons[i].tooltip_text=_descriptions[i].tooltip_text
  claim_buttons[i].text="免费招募" if _cards[i].get("can_claim",false) else "备战席已满"
 set_message("选择会立即加入备战席；集齐 3 个一星副本会自动合成二星。")
 for card in _cards:
  if not card.get("can_claim",false):set_message("备战席已满：可直接合成的角色仍可领取；也可稍后选择，先上阵或出售角色。",true);break
 _sync_controls()
func set_message(text:String,failed:bool=false)->void:
 message.text=text;message.add_theme_color_override("font_color",Color("a43d53") if failed else Color("36566b"))
func _claim(slot:int)->void:
 if not visible or _submitted or _confirming or _event.is_empty() or slot<0 or slot>=_cards.size() or not _cards[slot].get("can_claim",false):return
 _submitted=true;_sync_controls();claim_requested.emit(int(_event.round),slot)
func _ask_skip()->void:
 if not visible or _submitted or _event.is_empty():return
 _confirming=true;set_message("确认放弃这一次免费增援？放弃后，本次机会无法恢复。",true);_sync_controls();cancel_skip_button.grab_focus()
func _cancel_skip()->void:
 if not visible or _submitted:return
 _confirming=false;set_message("可以继续选择，也可以关闭后先整理阵容。");_sync_controls();close_button.grab_focus()
func _confirm_skip()->void:
 if not visible or _submitted or not _confirming or _event.is_empty():return
 _submitted=true;_sync_controls();skip_requested.emit(int(_event.round))
func close_panel()->void:
 if not visible:return
 hide();_confirming=false;closed.emit()
func _sync_controls()->void:
 for i in range(claim_buttons.size()):claim_buttons[i].disabled=_submitted or _confirming or not _cards[i].get("can_claim",false)
 skip_button.visible=not _confirming;skip_button.disabled=_submitted
 confirm_skip_button.visible=_confirming;cancel_skip_button.visible=_confirming
 confirm_skip_button.disabled=_submitted;cancel_skip_button.disabled=_submitted
 var focusable:Array[Control]=[close_button]
 for button in claim_buttons:
  if not button.disabled:focusable.append(button)
 if not _submitted:
  if _confirming:focusable.append(cancel_skip_button);focusable.append(confirm_skip_button)
  else:focusable.append(skip_button)
 for i in range(focusable.size()):
  focusable[i].focus_next=focusable[i].get_path_to(focusable[(i+1)%focusable.size()]);focusable[i].focus_previous=focusable[i].get_path_to(focusable[(i-1+focusable.size())%focusable.size()])
func _label(parent:Control,text:String,rect:Rect2,font_size:int)->Label:
 var label:=Label.new();label.text=text;label.position=rect.position;label.size=rect.size;label.mouse_filter=Control.MOUSE_FILTER_IGNORE;label.add_theme_font_size_override("font_size",font_size);label.add_theme_color_override("font_color",Color("25455a"));parent.add_child(label);return label
func _button(parent:Control,text:String,rect:Rect2,callback:Callable)->Button:
 var button:=Button.new();button.text=text;button.position=rect.position;button.size=rect.size;button.add_theme_font_size_override("font_size",16)
 for kind in ["normal","hover","pressed","disabled"]:
  var style:=StyleBoxFlat.new();style.bg_color=Color("dfeef5") if kind=="normal" else Color("bfdfef") if kind=="hover" else Color("a9d5e8") if kind=="pressed" else Color("e7ecef");style.set_corner_radius_all(7);button.add_theme_stylebox_override(kind,style)
 for kind in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:button.add_theme_color_override(kind,Color("244c66"))
 button.add_theme_color_override("font_disabled_color",Color("94a4af"));parent.add_child(button);button.pressed.connect(callback);return button
