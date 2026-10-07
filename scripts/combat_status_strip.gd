extends Control
const Presenter=preload("res://core/combat_status_presenter.gd")
const Icons=preload("res://scripts/native_skill_icons.gd")
var icons=Icons.new()
var skill_icon_keys:Array[String]=[]
var effect_icon_keys:Array[String]=[]
const STRIP_SIZE:=Vector2(92,44)
var presenter=Presenter.new()
var status:Dictionary={}
# Presentation-only slots. The full authoritative projection and tooltip keep
# every effect, in the presenter's original order.
var display_effects:Array=[]
var revisions:=0
var _styles:Dictionary={}
var _input_values:Array=[]
var _input_buffs:Dictionary={}
var _input_basic_trigger:Dictionary={}
var _input_sub_trigger:Dictionary={}
func _ready()->void:
	custom_minimum_size=STRIP_SIZE;size=custom_minimum_size
	mouse_filter=Control.MOUSE_FILTER_PASS
func update_unit(unit:Dictionary,tick:int,definition:Dictionary,preparation:bool=false)->void:
	# Cache only the presenter's actual inputs, not a mutable unit reference or
	# a lossy hash. Same-tick shield/buff/definition edits must still refresh.
	var values:Array=[str(unit.get("character_id","")),tick,preparation,int(unit.get("hp",0))>0,int(unit.get("star",1)),int(unit.get("skill_ready",0)),int(unit.get("skill_cooldown_ticks",1)),int(unit.get("basic_ready",0)),int(unit.get("basic_activations",0)),int(unit.get("sub_ready",0)),int(unit.get("cover_ready",0)),int(unit.get("shield",0)),int(unit.get("shield_until",0)),int(unit.get("stun_until",0)),int(unit.get("taunt_until",0)),int(unit.get("charges",0)),str(unit.get("charges",0)),str(unit.get("cover_status",{}).get("state","none")),float(unit.get("cover_status",{}).get("multiplier",1.0))]
	var buffs:Dictionary=unit.get("buffs",{})
	var basic_trigger:Dictionary=definition.get("basic",{}).get("trigger",{})
	var sub_trigger:Dictionary=definition.get("sub",{}).get("trigger",{})
	if values==_input_values and buffs==_input_buffs and basic_trigger==_input_basic_trigger and sub_trigger==_input_sub_trigger:return
	_input_values=values
	if buffs!=_input_buffs:_input_buffs=buffs.duplicate(true)
	if basic_trigger!=_input_basic_trigger:_input_basic_trigger=basic_trigger.duplicate(true)
	if sub_trigger!=_input_sub_trigger:_input_sub_trigger=sub_trigger.duplicate(true)
	var fresh:Dictionary=presenter.present(unit,tick,definition,preparation)
	var fresh_skill_keys:Array[String]=[]
	for slot in ["ex","basic","sub"]:fresh_skill_keys.append(icons.skill_key(str(unit.get("character_id","")),slot))
	var fresh_effect_keys:Array[String]=[]
	var fresh_display:Array=_make_display_effects(fresh.effects)
	for effect in fresh_display:fresh_effect_keys.append(icons.effect_key(effect,buffs,int(unit.get("charges",0))))
	if fresh==status and fresh_skill_keys==skill_icon_keys and fresh_effect_keys==effect_icon_keys:return
	skill_icon_keys=fresh_skill_keys;effect_icon_keys=fresh_effect_keys
	var effects_changed:bool=fresh.effects!=status.get("effects",[])
	status=fresh;revisions+=1;visible=bool(status.visible)
	if effects_changed:display_effects=_make_display_effects(status.effects)
	var tips:Array[String]=[status.ex.hint,status.basic.hint,status.sub.hint]
	for effect in status.effects:tips.append(effect.hint)
	tooltip_text="\n".join(tips)
	mouse_filter=Control.MOUSE_FILTER_IGNORE if preparation else Control.MOUSE_FILTER_PASS
	queue_redraw()
func _make_display_effects(effects:Array)->Array:
	var ordered:Array=effects.duplicate(true)
	ordered.sort_custom(func(a:Dictionary,b:Dictionary):
		var a_priority:int=_effect_priority(a);var b_priority:int=_effect_priority(b)
		return str(a.get("id",""))<str(b.get("id","")) if a_priority==b_priority else a_priority<b_priority
	)
	if ordered.size()>3:
		var hidden:int=ordered.size()-3
		ordered=ordered.slice(0,3)
		ordered.append({"id":"overflow","label":"+%d"%hidden,"kind":"overflow","hidden_count":hidden})
	return ordered
func _effect_priority(effect:Dictionary)->int:
	match str(effect.get("id","")):
		"stun":return 0
		"taunt":return 1
		"shield":return 2
		"terrain_cover":return 2
	match str(effect.get("kind","")):
		"debuff":return 3
		"charge":return 4
	return 5
func _skill_rect(index:int)->Rect2:
	return Rect2(index*31,0,30,26)
func _effect_center(index:int)->Vector2:
	return Vector2((STRIP_SIZE.x-display_effects.size()*18)*0.5+9+index*18,36)
func _draw()->void:
	if status.is_empty() or not status.visible:return
	var font:Font=get_theme_default_font()
	for i in range(3):
		var skill:Dictionary=status.ex if i==0 else status.basic if i==1 else status.sub
		var box:Rect2=_skill_rect(i)
		var tint:=Color("64ccef") if i==0 else Color("a1d99e") if i==1 else Color("c5a0f1")
		if skill.kind in ["locked","used","preparation"]:tint=Color("8d9ca8")
		draw_style_box(_box(Color("243847"),tint),box)
		if skill.kind=="cooldown":
			draw_rect(Rect2(box.position+Vector2(2,24),Vector2(26,1)),Color(tint,0.15))
			draw_rect(Rect2(box.position+Vector2(2,24),Vector2(26*float(skill.progress),1)),tint)
		var icon_key:String=skill_icon_keys[i] if i<skill_icon_keys.size() else ""
		if _has_icon(icon_key):
			_draw_icon(icon_key,Rect2(box.position+Vector2(9,2),Vector2(17,13)),Color(tint,0.45) if skill.kind in ["locked","used","preparation"] else Color.WHITE)
			draw_string(font,box.position+Vector2(2,9),str(skill.label),HORIZONTAL_ALIGNMENT_LEFT,12,7,tint)
		else:draw_string(font,box.position+Vector2(2,10),str(skill.label),HORIZONTAL_ALIGNMENT_CENTER,26,10,tint)
		draw_string(font,box.position+Vector2(2,22),str(skill.text),HORIZONTAL_ALIGNMENT_CENTER,26,11,Color.WHITE)
	for i in display_effects.size():
		var effect:Dictionary=display_effects[i]
		var tint:=Color("77d7b7")
		if effect.kind=="shield":tint=Color("68cfff")
		elif effect.kind in ["debuff","exposed"]:tint=Color("f59e8e")
		elif effect.kind=="charge":tint=Color("c5a0f1")
		elif effect.kind=="overflow":tint=Color("c8d5de")
		var center:Vector2=_effect_center(i)
		draw_circle(center,7.5,Color("263c4c"));draw_arc(center,7.5,0,TAU,20,tint,1,true)
		var icon_key:String=effect_icon_keys[i] if i<effect_icon_keys.size() else ""
		if _has_icon(icon_key):
			if effect.kind=="charge":
				_draw_icon(icon_key,Rect2(center-Vector2(6,5),Vector2(8,10)),Color.WHITE)
				draw_string(font,center+Vector2(2,3),str(effect.label),HORIZONTAL_ALIGNMENT_CENTER,5,8,Color.WHITE)
			else:_draw_icon(icon_key,Rect2(center-Vector2(6,6),Vector2(12,12)),Color.WHITE)
		else:draw_string(font,center+Vector2(-7,3),str(effect.label),HORIZONTAL_ALIGNMENT_CENTER,14,8 if effect.kind=="overflow" else 10,tint)
func _box(background:Color,border:Color)->StyleBoxFlat:
	var key:int=border.to_rgba32()
	if _styles.has(key):return _styles[key]
	var style:=StyleBoxFlat.new();style.bg_color=background;style.border_color=border;style.set_border_width_all(1);style.set_corner_radius_all(3);_styles[key]=style;return style

func _has_icon(key:String)->bool:
	return not key.is_empty() and icons.texture(key)!=null and icons.region(key).has_area()
func _draw_icon(key:String,box:Rect2,tint:Color)->void:
	var texture:Texture2D=icons.texture(key)
	var source:Rect2=icons.region(key)
	if texture==null or not source.has_area():return
	var factor:float=minf(box.size.x/source.size.x,box.size.y/source.size.y)
	var fitted:Vector2=source.size*factor
	draw_texture_rect_region(texture,Rect2(box.position+(box.size-fitted)*0.5,fitted),source,tint)
