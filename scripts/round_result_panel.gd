extends Control
## Read-only presenter. Session remains the only owner of score and progression.
signal next_round_requested
signal new_game_requested
signal title_requested
const League=preload('res://core/tactical_league.gd')
var heading:Label
var summary:Label
var ranking:Label
var next_button:Button
var new_button:Button
var title_button:Button
var _submitted:=false
func _ready():
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var shade:=ColorRect.new();shade.color=Color(0.025,0.06,0.10,0.9);add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var center:=CenterContainer.new();add_child(center);center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var panel:=PanelContainer.new();panel.custom_minimum_size=Vector2(660,580);center.add_child(panel)
 var style:=StyleBoxFlat.new();style.bg_color=Color('123049');style.set_corner_radius_all(16);style.content_margin_left=36;style.content_margin_right=36;style.content_margin_top=28;style.content_margin_bottom=28;panel.add_theme_stylebox_override('panel',style)
 var box:=VBoxContainer.new();box.add_theme_constant_override('separation',18);panel.add_child(box)
 heading=_label(box,34);heading.add_theme_color_override('font_color',Color('74dbf4'))
 summary=_label(box,18);summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;summary.custom_minimum_size.x=588
 ranking=_label(box,19);ranking.size_flags_vertical=Control.SIZE_EXPAND_FILL
 var actions:=HBoxContainer.new();actions.add_theme_constant_override('separation',14);box.add_child(actions)
 next_button=_button(actions,'下一回合',func():_submit('next'))
 new_button=_button(actions,'再来一局',func():_submit('new'))
 title_button=_button(actions,'返回主菜单',func():_submit('title'))
 hide()
func _label(parent:Node,font_size:int)->Label:
 var label:=Label.new();label.add_theme_font_size_override('font_size',font_size);label.add_theme_color_override('font_color',Color('e5f0f7'));parent.add_child(label);return label
func _button(parent:Node,text:String,action:Callable)->Button:
 var button:=Button.new();button.text=text;button.custom_minimum_size=Vector2(180,48);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(button);button.pressed.connect(action);return button
func present(snapshot:Dictionary,report:Dictionary)->void:
 _submitted=false
 var result:Dictionary=snapshot.get('last_result',{})
 var final:bool=snapshot.get('phase')=='finished'
 var winner:String=str(result.get('winner','draw'))
 var outcome:String='win' if winner=='player' else 'loss' if winner=='opponent' else 'draw'
 var caption:String='胜利' if outcome=='win' else '失败' if outcome=='loss' else '平局'
 heading.text='本局结束 · 第 %d 名'%int(snapshot.get('placement',0)) if final else '第 %d 回合 · %s'%[int(result.get('round',1)),caption]
 summary.text='%s  ·  本轮积分 +%d'%[caption,League.RESULT_POINTS[outcome]]
 var combat:Dictionary=result.get('combat',{})
 var seconds:float=float(combat.get('duration_ticks',0))*0.05 if not combat.is_empty() else float(report.get('duration_seconds',0.0))
 if seconds>0:summary.text+='  ·  %.1f 秒'%seconds
 if combat.get('finish_reason')=='timeout':summary.text+='\n90 秒到时 · 剩余总血量：我方 %d / 对手 %d'%[combat.remaining_hp_totals[0],combat.remaining_hp_totals[1]]
 var names:Dictionary={'p0':'你'}
 for player in snapshot.get('players',[]):
  if player.id!='p0':names[player.id]=player.name
 var lines:Array[String]=['最终排名' if final else '当前积分']
 for row in snapshot.get('standings',[]):lines.append('%d.  %s    %d 分'%[row.rank,names.get(row.participant_id,row.participant_id),row.points])
 ranking.text='\n'.join(lines)
 next_button.visible=not final;new_button.visible=final
 for button in [next_button,new_button,title_button]:button.disabled=false
 show()
 if final:new_button.grab_focus()
 else:next_button.grab_focus()
func _submit(action:String)->void:
 if _submitted:return
 _submitted=true
 for button in [next_button,new_button,title_button]:button.disabled=true
 if action=='next':next_round_requested.emit()
 elif action=='new':new_game_requested.emit()
 else:title_requested.emit()
func release_action()->void:
 _submitted=false
 for button in [next_button,new_button,title_button]:button.disabled=false
