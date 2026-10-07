extends SceneTree
const Strip=preload("res://scripts/combat_status_strip.gd")
const Presenter=preload("res://core/combat_status_presenter.gd")
var checks:=0
var failures:=0
func ck(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func _initialize():call_deferred("run")
func run():
	var strip=Strip.new();root.add_child(strip)
	# Restoring the previous 130px one-row strip must fail these layout checks.
	ck(strip.size==Vector2(92,44),"status strip reserves a compact 92 by 44 area")
	ck(strip.custom_minimum_size==Vector2(92,44),"buff row remains reserved even without active effects")
	var has_layout:bool=strip.has_method("_skill_rect") and strip.has_method("_effect_center")
	ck(has_layout,"drawing exposes the geometry it actually uses")
	if has_layout:
		for i in 3:
			ck(strip._skill_rect(i)==Rect2(i*31,0,30,26),"skill tile has room for its label and countdown")
		ck(strip._skill_rect(2).end.x==92.0,"three skill tiles exactly fill the centered row")
		var font:Font=strip.get_theme_default_font()
		for text in ["27s","100s","就绪","待战","换弹","已用","低血","队友","常驻"]:
			ck(font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x<=26,"11px state text fits: "+text)
	var has_display:bool=strip.get_property_list().any(func(property):return property.name=="display_effects")
	ck(has_display,"strip has a separate cached effect display projection")
	var sim=load("res://core/character_sim.gd").new()
	var unit:Dictionary=sim.preview_unit("shiroko",2)
	var definition:Dictionary=sim.character_data("shiroko")
	unit.buffs={"z_buff":{"stat":"AttackPower","fraction":0.2,"until":200},"a_buff":{"stat":"AttackSpeed","fraction":0.3,"until":200}}
	unit.shield=420;unit.shield_until=200;unit.stun_until=100;unit.taunt_until=120
	strip.update_unit(unit,40,definition,false)
	var expected:Dictionary=Presenter.new().present(unit,40,definition,false)
	ck(strip.status==expected,"visual ordering never changes presenter data")
	ck(strip.status.effects[0].id=="a_buff","original presenter ordering is preserved")
	for effect in expected.effects:ck(strip.tooltip_text.contains(effect.hint),"full tooltip retains "+effect.id)
	if has_display:
		var shown:Array=strip.display_effects
		ck(shown.size()==4,"overflow uses three effects plus one count")
		if shown.size()==4:
			ck(shown[0].id=="stun" and shown[1].id=="taunt" and shown[2].id=="shield","crowd control and shield precede ordinary buffs")
			ck(shown[3].kind=="overflow" and shown[3].label=="+2","overflow count includes every hidden effect")
		if has_layout:
			ck(strip._effect_center(0)==Vector2(19,36) and strip._effect_center(3)==Vector2(73,36),"four small effects are centered on their own row")
		var revisions:int=strip.revisions;var child_count:int=strip.get_child_count()
		for i in 6:strip.update_unit(unit,40,definition,false)
		ck(strip.revisions==revisions,"identical input does not rebuild visual projection")
		ck(strip.get_child_count()==child_count,"status updates never rebuild UI controls")
		unit.stun_until=0;unit.taunt_until=0;unit.shield=0;unit.charges=2
		unit.buffs={"z_debuff":{"stat":"AttackPower","fraction":-0.2,"until":200},"a_debuff":{"stat":"AttackSpeed","fraction":-0.3,"until":200},"buff":{"stat":"DefensePower","fraction":0.3,"until":200}}
		strip.update_unit(unit,40,definition,false)
		shown=strip.display_effects
		ck(shown.map(func(effect):return effect.id)==["a_debuff","z_debuff","charge","overflow"],"other debuffs sort by stable ID before charges and ordinary buffs")
		ck(shown.back().label=="+1","only three individual effects precede the overflow badge")
		unit.buffs={"z_buff":{"stat":"AttackPower","fraction":0.2,"until":200},"a_buff":{"stat":"AttackSpeed","fraction":0.3,"until":200}};unit.charges=0
		strip.update_unit(unit,40,definition,false)
		ck(strip.display_effects.map(func(effect):return effect.id)==["a_buff","z_buff"],"ordinary buffs also have stable ID ordering")
		if has_layout:ck(strip._effect_center(0)==Vector2(37,36) and strip._effect_center(1)==Vector2(55,36),"short effect rows remain centered")
		unit.buffs.clear();strip.update_unit(unit,40,definition,false)
		ck(strip.display_effects.is_empty() and strip.size==Vector2(92,44),"expired effects clear without moving the skill row")
		unit.hp=0;strip.update_unit(unit,40,definition,false)
		ck(not strip.visible,"dead unit still hides compact status")
	strip.free()
	print("COMPACT STATUS LAYOUT ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)
