extends Node3D
const Session=preload("res://core/game_session.gd")
const Stage=preload("res://tests/profiling/startup_stage.gd")
const CombatAudio=preload("res://scripts/native_combat_audio.gd")
const RenderWarmup=preload("res://scripts/render_warmup.gd")
var warming:=false
var session=Session.new()
var combat_audio:Node
var stage:Node3D
var canvas:CanvasLayer
var title:Label
var economy:Label
var detail:Label
var standings:Label
var notice:Label
var status:Label
var shop:Array=[]
var shop_cards:Array=[]
var portrait_cache:Dictionary={}
var bench:Array=[]
var report_button:Button
var report_panel:Panel
var report_text:RichTextLabel
var start_button:Button
var deploy_button:Button
var sell_button:Button
var refresh_button:Button
var xp_button:Button
var selected_owned:=""
var previous_phase:=""
var visual_time:=0.0
var roster_signature:=""
var frame_times:Array[float]=[]
var metrics:Label
var cpu_samples:Array[Vector2]=[]
var battle_frame_times:Array[float]=[]
var battle_cpu_samples:Array[Vector2]=[]
func _ready()->void:
	combat_audio=CombatAudio.new();combat_audio.name="NativeCombatAudio"
	combat_audio.output_enabled=DisplayServer.get_name()!="headless";add_child(combat_audio)
	stage=Stage.new();add_child(stage);stage.configure(session.profiles,Session.OBSTACLES)
	stage.selected.connect(func(id:int):select_owned(session.id_to_unit.get(id,"")))
	stage.placement_requested.connect(_place)
	_build_ui();session.new_game(_fresh_seed());_refresh(true)
	if DisplayServer.get_name()!="headless" and not RenderWarmup.completed:
		warming=true;_refresh_ui();status.text="正在准备原始角色与技能着色器…"
		await RenderingServer.frame_post_draw
		var warmup=RenderWarmup.new();add_child(warmup)
		await warmup.run(session.profiles)
		warmup.queue_free();warming=false;_refresh_ui()
func _process(delta:float)->void:
	var frame_start:=Time.get_ticks_usec()
	var was_battle:bool=session.phase()=="battle" and not session.paused
	if delta>0:
		frame_times.append(delta)
		if frame_times.size()>600:frame_times.pop_front()
	var events:Array=[]
	if session.phase()=="battle":
		events=session.advance(delta)
		visual_time=float(session.clock.sim.tick)*0.05+session.clock.accumulator
	elif not session.paused:visual_time+=delta
	var after_sim:=Time.get_ticks_usec()
	if session.phase() in ["battle","result","finished","error"]:
		stage.update_display(session.clock.sim.units,events,visual_time,session.clock.sim.tick)
	else:stage.update_display(stage.units,[],visual_time,0)
	if session.phase()=="battle":
		for event in events:combat_audio.consume(event)
		combat_audio.update_time(visual_time,session.paused)
	elif previous_phase=="battle":combat_audio.reset(session.clock.generation)
	cpu_samples.append(Vector2(after_sim-frame_start,Time.get_ticks_usec()-after_sim))
	if cpu_samples.size()>600:cpu_samples.pop_front()
	if was_battle and delta>0:
		battle_frame_times.append(delta);battle_cpu_samples.append(cpu_samples.back())
		if battle_frame_times.size()>7200:battle_frame_times.pop_front();battle_cpu_samples.pop_front()
	if previous_phase!=session.phase():
		if previous_phase=="battle":_save_battle_performance()
		_refresh(false)
	if session.phase()=="battle":status.text=_battle_status_text()
	if metrics:metrics.text="%d FPS" % Engine.get_frames_per_second()
func act(command:Dictionary)->Dictionary:
	var result:Dictionary=session.command(command)
	if not result.ok:notice.text=_error_text(str(result.get("error","操作失败")));return result
	notice.text=""
	if command.type=="buy_offer":selected_owned=result.get("unit_id",selected_owned)
	if command.type=="restart":selected_owned="";roster_signature="";visual_time=0
	if command.type in ["start_battle","next_round","restart"]:report_panel.hide()
	if command.type in ["start_battle","restart"]:report_text.text=""
	_refresh(command.type in ["start_battle","next_round","restart"])
	return result
func select_owned(id:String)->void:
	selected_owned=id
	stage.set_selected(-1)
	for combat_id in session.id_to_unit:
		if session.id_to_unit[combat_id]==id:stage.set_selected(combat_id);break
	_refresh_ui()
func _place(id:int,point:Vector2)->void:
	if session.place(session.id_to_unit.get(id,""),point):
		stage.units=_preparation_roster();stage.update_display(stage.units,[],visual_time,0)
func _preparation_roster()->Array:
	var roster:Array=session.preview_roster()
	roster.append_array(session.opponent_preview().get("units",[]))
	return roster
func _refresh(force:bool)->void:
	var phase:String=session.phase()
	if phase=="preparation":
		combat_audio.reset(session.clock.generation)
		var roster:Array=_preparation_roster();var signature:=""
		for u in roster:signature+="%s:%s:%d;"%[u.roster_unit_id,u.character_id,u.star]
		if force or signature!=roster_signature or previous_phase!="preparation":
			stage.set_roster(roster,session.clock.generation,true);roster_signature=signature;visual_time=0
	elif phase=="battle" and (force or previous_phase!="battle"):
		stage.set_roster(session.clock.sim.units,session.clock.generation,false);visual_time=0
		combat_audio.begin_roster(session.clock.sim.units,session.clock.generation)
		battle_frame_times.clear();battle_cpu_samples.clear()
	previous_phase=phase
	select_owned(selected_owned)
func _battle_status_text()->String:
	var overtime:Dictionary=session.clock.sim.overtime_state()
	if overtime.active:return "加时 · 治疗及新护盾 %d%% · 技能自动释放"%int(round(overtime.healing_multiplier*100.0))
	return "自动战斗  /  技能随战斗自动释放"
func _refresh_ui()->void:
	var p:Dictionary=session.rules.get_player();var state:Dictionary=session.rules.snapshot();var phase:String=session.phase();var prep:bool=phase=="preparation" and not warming
	if p.is_empty():return
	title.text="BLUE / A     自走棋"
	var displayed_round:int=int(state.last_result.get("round",state.round)) if phase in ["result","finished"] else int(state.round)
	economy.text="第 %d 回合     生命 %d     金币 %d     等级 %d   ·   上阵 %d/%d"%[displayed_round,p.hp,p.gold,p.level,p.deployed.size(),p.level]
	status.text="准备阶段  /  拖动角色自由布阵" if prep else _battle_status_text() if phase=="battle" else "战斗结算失败 · 请重新开始" if phase=="error" else "回合结束"
	if prep:
		var incoming:Dictionary=session.opponent_preview()
		status.text="准备 · %s / %s · 敌阵已锁定，可针对布阵"%[incoming.get("name","未知"),incoming.get("formation_name","横向阵列")]
	var owned:Dictionary=session._owned(p,selected_owned)
	if owned.is_empty():
		selected_owned="";detail.text="选择角色\n\n招募角色后点击上阵\n\n3 个相同一星 → 二星\n二星解锁自动 EX\n\n拖动场上角色自由布阵\n进入射程自动攻击\n障碍物影响走位与射线"
	else:
		var stats:Dictionary=session.clock.sim.preview_unit(owned.character_id,owned.star)
		detail.text="%s  %s\n生命 %d  ·  攻击 %d\n射程 %.1f  ·  %s\n\n%s\n\n%s\n出售返还 %d 金币"%[_name(owned.character_id),"★★" if owned.star==2 else "★",stats.max_hp,stats.get("stats",{}).get("AttackPower",0),stats.get("range",0.0),stats.get("weapon",""),_character_hint(owned.character_id),"EX 已解锁 · 自动释放" if owned.star==2 else "升为二星解锁 EX",Session.COSTS[owned.character_id]*(3 if owned.star==2 else 1)]
	deploy_button.text="移至备战席" if selected_owned in p.deployed else "上阵"
	deploy_button.disabled=not prep or owned.is_empty();sell_button.disabled=not prep or owned.is_empty()
	refresh_button.disabled=not prep or p.gold<2;xp_button.disabled=not prep or p.gold<4 or p.level>=state.config.max_level
	for i in range(5):
		var offer:Dictionary=p.shop[i];var button:Button=shop[i]
		var card:Dictionary=shop_cards[i]
		var portrait:Texture2D=null
		if not offer.is_empty():
			var path:String="res://assets/ui/portraits/"+offer.character_id+".png"
			if not portrait_cache.has(path) and ResourceLoader.exists(path):portrait_cache[path]=load(path)
			portrait=portrait_cache.get(path)
		card.art.texture=portrait;card.art.visible=portrait!=null
		card.name.visible=portrait!=null;card.price.visible=portrait!=null
		card.name.text="" if offer.is_empty() else _name(offer.character_id)
		card.price.text="" if offer.is_empty() else "%d 金币"%offer.cost
		button.text="已招募" if offer.is_empty() else "" if portrait!=null else "%s\n\n%d 金币"%[_name(offer.character_id),offer.cost]
		card.art.modulate=Color(1,1,1,1.0 if prep else 0.5)
		button.disabled=not prep or offer.is_empty() or p.gold<int(offer.get("cost",9999))
	for i in range(9):
		var button:Button=bench[i]
		if i<p.bench.size():
			var unit:Dictionary=session._owned(p,p.bench[i]);button.text=_name(unit.character_id)+(" ★★" if unit.star==2 else " ★");button.disabled=not prep
		else:button.text="·";button.disabled=true
	report_button.disabled=not session.battle_feedback().get("completed",false)
	start_button.disabled=warming or (prep and p.deployed.is_empty())
	start_button.text="开始战斗" if prep else ("继续战斗" if session.paused else "暂停") if phase=="battle" else "下一回合" if phase=="result" else "重新开始"
	standings.text="对局排名"
	var ranked:Array=state.players.duplicate();ranked.sort_custom(func(a,b):return a.hp>b.hp)
	for player in ranked:standings.text+="\n%s   %d"%["你" if player.id=="p0" else player.name,player.hp]
	if phase in ["result","finished"]:
		var result:Dictionary=state.last_result
		if phase=="finished":status.text="获得第 %d 名 · %s"%[state.placement,"胜利" if state.outcome=="victory" else "本局结束"]
		else:status.text="%s  ·  本回合生命 -%d  ·  收入 +%d"%["回合胜利" if result.winner=="player" else "回合落败" if result.winner=="opponent" else "平局",result.player_damage,result.income_by_player.get("p0",0)]
	if warming:status.text="正在准备原始角色与技能着色器…";start_button.text="准备中…"
func _name(key:String)->String:return session.profiles.get(key,{}).get("display_name",key)
func _start_pressed()->void:
	match session.phase():
		"preparation":act({"type":"start_battle"})
		"battle":session.paused=not session.paused;_refresh_ui()
		"result":act({"type":"next_round"})
		"finished","error":act({"type":"restart","seed":_fresh_seed()})
func _deploy_pressed()->void:
	var p:Dictionary=session.rules.get_player()
	act({"type":"bench_unit" if selected_owned in p.deployed else "deploy_unit","unit_id":selected_owned})
func _build_ui()->void:
	canvas=CanvasLayer.new();canvas.layer=5;add_child(canvas)
	_panel(Rect2(0,0,1280,64),Color("f3f8fb"))
	_panel(Rect2(1016,78,250,630),Color("eff5f8"))
	_panel(Rect2(14,713,1252,175),Color("f3f8fb"))
	title=_label("",Rect2(24,16,240,36),22)
	economy=_label("",Rect2(310,22,855,30),17)
	status=_label("",Rect2(24,76,900,35),18)
	detail=_label("",Rect2(1034,100,214,265),15);detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	deploy_button=_button("上阵",Rect2(1034,363,101,36),_deploy_pressed)
	sell_button=_button("出售",Rect2(1143,363,103,36),func():act({"type":"sell_unit","unit_id":selected_owned}))
	standings=_label("",Rect2(1034,408,214,180),12)
	report_button=_button("上回合战报",Rect2(1034,596,212,30),show_battle_report)
	start_button=_button("开始战斗",Rect2(1034,636,212,48),_start_pressed)
	_label("备战席",Rect2(24,666,70,28),14)
	for i in range(9):
		var index:=i
		bench.append(_button("·",Rect2(99+i*98,659,92,40),func():
			var p:Dictionary=session.rules.get_player()
			if index<p.bench.size():select_owned(p.bench[index])
		))
	_label("招募",Rect2(30,726,100,25),17)
	for i in range(5):
		var index:=i
		shop.append(_button("",Rect2(30+i*187,761,175,105),func():act({"type":"buy_offer","slot":index})))
		_decorate_card(shop.back())
	refresh_button=_button("刷新  ·  2 金币",Rect2(990,761,252,45),func():act({"type":"refresh_shop"}))
	xp_button=_button("购买经验  ·  4 金币",Rect2(990,820,252,45),func():act({"type":"buy_xp"}))
	notice=_label("",Rect2(136,723,820,28),15);notice.add_theme_color_override("font_color",Color("a43d53"))
	metrics=_label("",Rect2(1170,22,95,25),14)
	report_panel=Panel.new();report_panel.position=Vector2(218,138);report_panel.size=Vector2(824,536);report_panel.z_index=20;canvas.add_child(report_panel)
	var report_style=StyleBoxFlat.new();report_style.bg_color=Color("edf5fa");report_style.set_corner_radius_all(12);report_panel.add_theme_stylebox_override("panel",report_style)
	report_text=RichTextLabel.new();report_text.position=Vector2(22,46);report_text.size=Vector2(780,468);report_text.add_theme_color_override("default_color",Color("25455a"));report_text.add_theme_font_size_override("normal_font_size",15);report_panel.add_child(report_text)
	var close=Button.new();close.text="关闭战报";close.position=Vector2(688,8);close.size=Vector2(114,30);report_panel.add_child(close);close.pressed.connect(func():report_panel.hide())
	report_panel.hide()
func _label(text:String,rect:Rect2,size:int)->Label:
	var node:=Label.new();node.text=text;node.position=rect.position;node.size=rect.size;node.add_theme_font_size_override("font_size",size);node.add_theme_color_override("font_color",Color("25455a"));node.mouse_filter=Control.MOUSE_FILTER_IGNORE;canvas.add_child(node);return node
func _panel(rect:Rect2,color:Color)->void:
	var node:=Panel.new();node.position=rect.position;node.size=rect.size;var style:=StyleBoxFlat.new();style.bg_color=color;style.set_corner_radius_all(10);node.add_theme_stylebox_override("panel",style);canvas.add_child(node)
func _button(text:String,rect:Rect2,callback:Callable)->Button:
	var node:=Button.new();node.text=text;node.position=rect.position;node.size=rect.size;node.add_theme_font_size_override("font_size",16)
	for kind in ["normal","hover","pressed","disabled"]:
		var style:=StyleBoxFlat.new();style.bg_color=Color("dfeef5") if kind=="normal" else Color("bfdfef") if kind=="hover" else Color("a9d5e8") if kind=="pressed" else Color("e7ecef");style.set_corner_radius_all(7);style.content_margin_left=8;style.content_margin_right=8;node.add_theme_stylebox_override(kind,style)
	node.add_theme_color_override("font_color",Color("244c66"));node.add_theme_color_override("font_hover_color",Color("173c56"));node.add_theme_color_override("font_pressed_color",Color("173c56"));node.add_theme_color_override("font_disabled_color",Color("94a4af"));node.pressed.connect(callback);canvas.add_child(node);return node
func _unhandled_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and not warming:
		if event.keycode==KEY_F12:_capture()
		elif event.keycode==KEY_F11 and OS.is_debug_build() and ResourceLoader.exists("res://tests/render_character_portraits.tscn"):
			get_tree().change_scene_to_file("res://tests/render_character_portraits.tscn")
		elif event.keycode==KEY_F10 and OS.is_debug_build() and ResourceLoader.exists("res://tests/six_combat_preview.tscn"):
			get_tree().change_scene_to_file("res://tests/six_combat_preview.tscn")
func _capture()->void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_evidence_root()+"/screenshots"))
	get_viewport().get_texture().get_image().save_png(_evidence_root()+"/screenshots/08-playable-match.png")
	var sorted:=frame_times.duplicate();sorted.sort();var total:=0.0
	for sample in sorted:total+=sample
	var report={"scope":"cloud rendered game, not local Windows acceptance","phase":session.phase(),"actors":stage.views.size(),"frames":sorted.size(),"average_fps":sorted.size()/maxf(total,0.001),"p95_frame_ms":sorted[int(sorted.size()*0.95)]*1000.0 if not sorted.is_empty() else 0.0,"adapter":RenderingServer.get_video_adapter_name(),"engine_fps":Engine.get_frames_per_second()}
	var cpu_total:=Vector2.ZERO
	for sample in cpu_samples:cpu_total+=sample
	report["mean_simulation_cpu_ms"]=cpu_total.x/maxi(cpu_samples.size(),1)/1000.0
	report["mean_presentation_cpu_ms"]=cpu_total.y/maxi(cpu_samples.size(),1)/1000.0
	report["draw_calls"]=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	report["rendered_primitives"]=Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var file:=FileAccess.open(_evidence_root()+"/match-performance.json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"  "))

func _error_text(code:String)->String:
	if code=="deployment_full" and session.rules.get_player().level>=session.rules.snapshot().config.max_level:
		return "每方最多上阵 %d 人，请先将一名角色移至备战席"%session.rules.snapshot().config.max_level
	return {"insufficient_gold":"金币不足","bench_full":"备战席已满，请先上阵或出售角色","deployment_full":"上阵人数已满，升级可增加人口","empty_army":"请先至少上阵一名角色","empty_slot":"这个角色已经招募过了","max_level":"已达到最高等级","unknown_unit":"角色已合成或出售，请重新选择","wrong_phase":"当前阶段不能执行这个操作"}.get(code,code)

func _save_battle_performance()->void:
	if battle_frame_times.is_empty():return
	var samples:=battle_frame_times.duplicate();samples.sort();var total:=0.0;var cpu:=Vector2.ZERO
	for value in samples:total+=value
	for value in battle_cpu_samples:cpu+=value
	var report={"scope":"actual battle frames only; cloud renderer, not Windows acceptance","display_server":DisplayServer.get_name(),"adapter":RenderingServer.get_video_adapter_name(),"frames":samples.size(),"seconds":total,"average_fps":samples.size()/maxf(total,0.001),"p95_frame_ms":samples[int(samples.size()*0.95)]*1000.0,"mean_simulation_cpu_ms":cpu.x/maxi(samples.size(),1)/1000.0,"mean_presentation_cpu_ms":cpu.y/maxi(samples.size(),1)/1000.0,"actor_count":stage.views.size(),"round":session.rules.snapshot().last_result.get("round",0)}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_evidence_root()))
	var file:=FileAccess.open(_evidence_root()+"/battle-performance-"+DisplayServer.get_name().to_lower()+".json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"  "))

func _evidence_root()->String:
	return "res://evidence" if OS.has_feature("editor") else "user://evidence"

func _decorate_card(button:Button)->void:
	var art:=TextureRect.new();art.position=Vector2(2,2);art.size=Vector2(85,101);art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(art)
	var name_label:=Label.new();name_label.position=Vector2(90,20);name_label.size=Vector2(80,28);name_label.add_theme_font_size_override("font_size",18);name_label.add_theme_color_override("font_color",Color("25455a"));name_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(name_label)
	var price:=Label.new();price.position=Vector2(90,57);price.size=Vector2(80,24);price.add_theme_font_size_override("font_size",15);price.add_theme_color_override("font_color",Color("587385"));price.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(price)
	shop_cards.append({"art":art,"name":name_label,"price":price})

func _character_hint(key:String)->String:
	return {"shiroko":"定时投掷手榴弹\n普攻有概率提升攻速\nEX：无人机连射","hoshino":"低血量触发持续回复\nEX：扇形连射与护盾","hina":"换弹后提高攻击\nEX：扇形穿透扫射","aru":"定时狙击，有概率爆炸\nEX：爆破狙击","yuuka":"定时单体射击\n进入掩体可触发回复\nEX：自身护盾","aris":"定时蓄能，最多两层\nEX：蓄能强化贯穿光束","serika":"定时连射\nEX：换弹并强化攻击/攻速","iori":"定时单体射击\n未在掩体中时追加伤害\nEX：三连射，波及目标后方","tsubaki":"低血量时回复一次\n换弹期间受到伤害降低\nEX：提高防御并嘲讽周围敌人","nonomi":"定时提高攻击\nEX：大范围扇形扫射","mutsuki":"定时布置三枚触发地雷\n普攻有概率提高命中\nEX：轰炸三处圆形区域","haruna":"定时单体狙击\n静止时提高攻击\nEX：直线贯穿，逐目标递减","koharu":"友军低于半血时治疗\n定时提高治疗力\nEX：范围治疗与伤害"}.get(key,"")

func _fresh_seed()->int:
	return randi_range(1,2147483646)

func show_battle_report()->void:
	var data:Dictionary=session.battle_feedback()
	if not data.get("completed",false):return
	var lines:Array[String]=["第 %d 回合 · 战斗 %.1f 秒"%[data.round,data.duration_seconds],"输出/承伤为实际生命损失；破盾单独统计。EX 命中人数按每次施法去重后累加。",""]
	var overtime:Dictionary=data.get("overtime",{})
	if overtime.get("active",false):lines.append("本场进入加时：治疗及新护盾效果降至 %d%%；已有护盾和技能伤害不变"%int(round(overtime.healing_multiplier*100.0)))
	var first:Dictionary=data.get("first_death",{})
	if not first.is_empty():lines.append("首个阵亡：%s方 %s（%.1f 秒）"%["我" if first.team==0 else "敌",_name(first.character_id),first.seconds])
	for team in range(2):
		lines.append("\n我方" if team==0 else "\n敌方")
		for unit in data.units:
			if unit.team!=team:continue
			lines.append("%s %s  输出 %d · 承伤 %d · 破盾 %d · 护盾吸收 %d\n    EX %d 次，累计命中 %d 人次"%[_name(unit.character_id),"★★" if unit.star==2 else "★",unit.damage_dealt,unit.damage_taken,unit.shield_damage_dealt,unit.shield_damage_taken,unit.ex_casts,unit.ex_unique_hits])
	report_text.text="\n".join(lines);report_panel.show()
