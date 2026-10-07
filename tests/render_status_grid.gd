extends SceneTree
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(900,520);root.content_scale_size=Vector2i(900,520)
	var canvas=Control.new();root.add_child(canvas)
	var bg=ColorRect.new();bg.size=Vector2(900,520);bg.color=Color("e8f1f6");canvas.add_child(bg)
	var sim=load("res://core/character_sim.gd").new()
	var keys=["shiroko","hoshino","hina","aris","yuuka","serika"]
	for i in range(keys.size()):
		var x:float=35+(i%3)*290;var y:float=30+(i/3)*240
		var unit=sim.preview_unit(keys[i],1 if i==1 else 2)
		if i==0:unit.buffs={"speed":{"stat":"AttackSpeed","fraction":0.3,"until":300}};unit.sub_ready=150
		if i==3:unit.charges=2
		if i==4:unit.shield=1200;unit.shield_until=200
		var label=Label.new();label.position=Vector2(x,y);label.text=keys[i];label.add_theme_color_override("font_color",Color("234050"));label.add_theme_font_size_override("font_size",18);canvas.add_child(label)
		var strip=load("res://scripts/combat_status_strip.gd").new();canvas.add_child(strip);strip.position=Vector2(x,y+34);strip.update_unit(unit,40,sim.character_data(keys[i]),false)
		var hint=Label.new();hint.position=Vector2(x,y+70);hint.size=Vector2(258,140);hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;hint.text=strip.tooltip_text;hint.add_theme_color_override("font_color",Color("234050"));hint.add_theme_font_size_override("font_size",13);canvas.add_child(hint)
	if DisplayServer.get_name()=="headless":quit();return
	await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence"))
	root.get_texture().get_image().save_png("res://evidence/status-grid.png");quit()
