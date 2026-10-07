extends Control
signal slot_selected(index:int)
const Icons=preload('res://scripts/native_skill_icons.gd')
var buttons:Array[Button]=[]
var energy_bar:ProgressBar
var energy_text:Label
var moves_text:Label
var hint_text:Label
var instructions:Label
var _icons=Icons.new()
func _ready()->void:
 position=Vector2(14,715);size=Vector2(1252,173);z_index=20;mouse_filter=Control.MOUSE_FILTER_STOP
 var panel:=Panel.new();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
 var background:=StyleBoxFlat.new();background.bg_color=Color('eef7fc');background.set_corner_radius_all(12);background.border_color=Color('8bc9e9');background.set_border_width_all(1);panel.add_theme_stylebox_override('panel',background);add_child(panel)
 energy_text=_label(Vector2(20,20),Vector2(215,26),19)
 energy_bar=ProgressBar.new();energy_bar.position=Vector2(20,56);energy_bar.size=Vector2(200,14);energy_bar.min_value=0;energy_bar.max_value=10;energy_bar.show_percentage=false
 var energy_background:=StyleBoxFlat.new();energy_background.bg_color=Color('c9dde8');energy_background.set_corner_radius_all(5);energy_bar.add_theme_stylebox_override('background',energy_background)
 var energy_fill:=StyleBoxFlat.new();energy_fill.bg_color=Color('39a8d5');energy_fill.set_corner_radius_all(5);energy_bar.add_theme_stylebox_override('fill',energy_fill);add_child(energy_bar)
 moves_text=_label(Vector2(20,83),Vector2(212,30),16)
 instructions=_label(Vector2(20,119),Vector2(225,48),12);instructions.text='左键选人 · 右键走位\n1–6 选EX · Esc取消'
 for index in range(6):
  var slot:int=index;var button:=Button.new();button.position=Vector2(254+index*162,14);button.size=Vector2(150,118);button.add_theme_font_size_override('font_size',15);button.add_theme_constant_override("icon_max_width",34);button.expand_icon=true;button.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER;button.vertical_icon_alignment=VERTICAL_ALIGNMENT_TOP
  for mode in ['normal','hover','pressed','disabled']:
   var style:=StyleBoxFlat.new();style.bg_color=Color('2b7195') if mode=='normal' else Color('378cb4') if mode!='disabled' else Color('526b7b');style.set_corner_radius_all(9);style.border_color=Color('88c7e9');style.set_border_width_all(1);button.add_theme_stylebox_override(mode,style)
  for mode in ['font_color','font_hover_color','font_pressed_color','font_focus_color']:button.add_theme_color_override(mode,Color.WHITE)
  button.add_theme_color_override('font_disabled_color',Color.WHITE);button.add_theme_color_override('icon_disabled_color',Color.WHITE)
  button.pressed.connect(func():slot_selected.emit(slot));buttons.append(button);add_child(button)
 hint_text=_label(Vector2(254,139),Vector2(975,26),14);hint_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 visible=false
func refresh(state:Dictionary)->void:
 visible=state.get('active',false)
 if not visible:return
 var energy:int=int(state.energy);energy_bar.value=energy
 energy_text.text='共享能量 %d/10'%energy
 moves_text.text='战术转移 %d/2'%int(state.moves)
 if state.moves<2:moves_text.text+=' · %.1fs'%float(state.get('move_next',0))
 hint_text.text=str(state.get('hint','实时选择与释放，不暂停战斗'))
 var slots:Array=state.get('slots',[])
 instructions.text='左键选人 · 右键走位\n1–%d 选EX · Esc取消'%slots.size()
 for index in range(buttons.size()):
  var button:Button=buttons[index];button.visible=index<slots.size()
  if not button.visible:continue
  var slot:Dictionary=slots[index];var actor:int=slot.get('actor_id',-1)
  button.set_meta('actor_id',actor)
  if actor<0:button.text='%d 空位'%(index+1);button.icon=null;button.disabled=true;continue
  button.icon=_icons.texture(_icons.skill_key(slot.character_id,'ex'))
  var status:String='就绪'
  if slot.hp<=0:status='已退场'
  elif slot.star<2:status='二星解锁'
  elif slot.cooldown>0:status='%.1fs'%slot.cooldown
  elif energy<slot.cost:status='能量不足'
  button.text='%d %s\n%d费 · %s'%[index+1,slot.name,slot.cost,status]
  button.disabled=slot.hp<=0 or slot.star<2 or state.get('pending',false)
  button.modulate=Color('b7e6ff') if actor==state.get('armed_actor',-1) else Color.WHITE
  button.tooltip_text='%s EX｜消耗%d共享能量｜%s'%[slot.name,slot.cost,status]
func _label(at:Vector2,extent:Vector2,font_size:int)->Label:
 var label:=Label.new();label.position=at;label.size=extent;label.add_theme_font_size_override('font_size',font_size);label.add_theme_color_override('font_color',Color('23516a'));label.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(label);return label
