extends Node3D
signal return_to_title_requested
signal new_game_requested
signal startup_completed(result:Dictionary)
var managed_startup:bool=false
var startup_intent:Dictionary={"action":"new"}
const MobileGestures=preload("res://scripts/mobile_drag_gestures.gd")
const RenderQuality=preload("res://core/render_quality_profile.gd")
const TacticalInput=preload("res://scripts/tactical_input.gd")
const TacticalHUD=preload("res://scripts/tactical_hud.gd")
const Session=preload("res://core/game_session.gd")
const OffscreenWorker=preload("res://core/offscreen_process_worker.gd")
const BenchModels=preload("res://scripts/bench_model_preview.gd")
const BenchDrag=preload("res://scripts/bench_drag_controller.gd")
const Stage=preload("res://scripts/battle_stage.gd")
const OrdinaryAudio=preload("res://scripts/ordinary_combat_audio.gd")
const CombatAudio=preload("res://scripts/native_combat_audio.gd")
const RenderWarmup=preload("res://scripts/render_warmup.gd")
const UserSettings=preload("res://core/user_settings.gd")
const SaveStore=preload("res://core/session_save_store.gd")
const GameMenu=preload("res://scripts/game_menu.gd")
const RecruitmentHints=preload("res://core/recruitment_hints.gd")
const RecruitmentPreview=preload("res://scripts/recruitment_preview_panel.gd")
const RecruitmentSkills=preload("res://core/recruitment_skill_presenter.gd")
const ReinforcementPanel=preload("res://scripts/reinforcement_panel.gd")
const Matchups=preload("res://core/matchup_presenter.gd")
@export_enum("legacy","tactical_v1") var new_game_mode:String="legacy"
@export var mobile_ui:bool=false
var mobile_gestures=MobileGestures.new()
var mobile_cancel_button:Button
var _mobile_suspended:=false
var _mobile_resume_paused:=false
var _previous_quit_on_go_back:=true
var _top_panel:Panel
var tactical_input=TacticalInput.new()
var tactical_hud:Control
var _tactical_generation:=-1
var _tactical_metadata:Dictionary={}
var _tactical_modes:Dictionary={}
var persistence_enabled:bool=DisplayServer.get_name()!="headless"
var save_path:String=SaveStore.DEFAULT_PATH
var settings_path:String=UserSettings.DEFAULT_PATH
var settings_values:Dictionary=UserSettings.DEFAULTS.duplicate()
var game_menu:Control
var menu_button:Button
var _menu_was_paused:bool=false
var _menu_generation:int=-1
var _autosave_pending:bool=false
var _autosave_delay:float=0.0
var _checkpoint_dirty:bool=false
var _prebattle_checkpoint_hash:String=""
var _save_error_notice:String=""
var round_result_panel:Control
var return_dialog:ConfirmationDialog
var _return_discard_allowed:=false
var _return_restart:=false
var _return_was_paused:=false
var _return_pending:=false
var quit_dialog:ConfirmationDialog
var _previous_auto_quit:bool=true
var warming:=false
var session=Session.new()
var combat_audio:Node
var _audio_tail_started:=false
var _audio_tail_flushed:=false
var _audio_tail_end:=0.0
var _presenting_combat_events:=false
var ordinary_audio:Node
var stage:Node3D
var canvas:CanvasLayer
var title:Label
var economy:Label
var detail:Label
var detail_scroll:ScrollContainer
var normal_target_selector:OptionButton
var reinforcement_button:Button
var reinforcement_panel:Control
var recruitment_preview:Control
var shop_preview_buttons:Array[Button]=[]
var _preview_slot:=-1
var _preview_offer_key:=""
var inspected_id:=-1
var _inspector_inputs:Array=[]
var _matchup_damage_types:Array=[]
var _matchup_armor_types:Array=[]
var standings:Label
var notice:Label
var status:Label
var shop:Array=[]
var shop_odds_label:Label
var shop_cards:Array=[]
var portrait_cache:Dictionary={}
var bench:Array=[]
var bench_previews
var bench_drag=BenchDrag.new()
var bench_ghost:TextureRect
var _sidebar_panel:Panel
var _shop_panel:Panel
var _bench_label:Label
var _shop_label:Label
var report_button:Button
var report_panel:Panel
var report_backdrop:ColorRect
var report_text:RichTextLabel
var start_button:Button
var deploy_button:Button
var sell_button:Button
var refresh_button:Button
var shop_lock_button:Button
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
	var user_args:PackedStringArray=OS.get_cmdline_user_args()
	if OffscreenWorker.is_worker_request(user_args):
		set_process(false);set_physics_process(false);set_process_input(false);set_process_unhandled_input(false)
		get_tree().quit(OffscreenWorker.run_worker(user_args));return
	# Headless deterministic tests use reference cooperative stepping; native
	# play isolates background CPU work in a separate engine process.
	mobile_ui=mobile_ui or OS.has_feature("android") or OS.has_feature("ios")
	if mobile_ui:
		get_window().content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
		_previous_quit_on_go_back=get_tree().quit_on_go_back;get_tree().quit_on_go_back=false
	session.process_ai_enabled=DisplayServer.get_name()!="headless" and not mobile_ui
	combat_audio=CombatAudio.new();combat_audio.name="NativeCombatAudio"
	combat_audio.output_enabled=DisplayServer.get_name()!="headless";add_child(combat_audio)
	ordinary_audio=OrdinaryAudio.new();ordinary_audio.name="OrdinaryCombatAudio";ordinary_audio.output_enabled=DisplayServer.get_name()!="headless";add_child(ordinary_audio)
	stage=Stage.new();add_child(stage);stage.configure(session.profiles,Session.OBSTACLES)
	stage.selected.connect(func(id:int):select_owned(session.id_to_unit.get(id,"")))
	stage.placement_requested.connect(_place)
	stage.inspected.connect(inspect_actor)
	stage.tactical_actor_pressed.connect(_tactical_actor_click)
	stage.ordinary_audio_state.connect(_consume_ordinary_state)
	for key in Session.ACTIVE:
		var unit:Dictionary=session.clock.sim.preview_unit(key)
		if unit.damage_type not in _matchup_damage_types:_matchup_damage_types.append(unit.damage_type)
		if unit.armor_type not in _matchup_armor_types:_matchup_armor_types.append(unit.armor_type)
	_build_ui()
	bench_previews=BenchModels.new();add_child(bench_previews);bench_previews.configure(session.profiles);bench_previews.texture_ready.connect(_bench_texture_ready)
	bench_drag.configure(Callable(self,"_commit_bench_drop"),Callable(session,"deployment_preview"),Callable(self,"_bench_generation"))
	bench_ghost=TextureRect.new();bench_ghost.size=Vector2(96,112);bench_ghost.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;bench_ghost.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;bench_ghost.mouse_filter=Control.MOUSE_FILTER_IGNORE;bench_ghost.z_index=100;canvas.add_child(bench_ghost);bench_ghost.hide()
	tactical_hud=TacticalHUD.new();canvas.add_child(tactical_hud);tactical_hud.slot_selected.connect(func(index):
		if not mobile_ui:_arm_tactical_slot(index)
	)
	game_menu.configure_mobile(mobile_ui)
	if mobile_ui:settings_values=UserSettings.with_quality_defaults(settings_values,true)
	if mobile_ui:
		for index in range(tactical_hud.buttons.size()):
			var slot:int=index
			tactical_hud.buttons[index].gui_input.connect(func(event):_mobile_ex_gui(event,slot))
		mobile_cancel_button=_button("取消EX",Rect2(0,76,150,44),_cancel_mobile_aim)
		get_viewport().size_changed.connect(func():_apply_tactical_layout(session.phase()))
	var started:Dictionary=session.restore_save(startup_intent.get("payload",{})) if managed_startup and startup_intent.get("action")=="continue" else session.new_game(_fresh_seed(),new_game_mode)
	if not started.ok:
		set_process(false);startup_completed.emit(started);return
	_refresh(true)
	if DisplayServer.get_name()!="headless":
		_previous_auto_quit=get_tree().auto_accept_quit;get_tree().auto_accept_quit=false
	if persistence_enabled:
		var preferences:Dictionary=UserSettings.read_settings(settings_path,mobile_ui)
		settings_values=UserSettings.with_quality_defaults(preferences.values,true) if mobile_ui else preferences.values;_apply_runtime_settings()
		if not preferences.ok:notice.text=preferences.error;shop_odds_label.hide()
	if DisplayServer.get_name()!="headless" and not RenderWarmup.completed:
		warming=true;_refresh_ui();status.text="正在准备原始角色与技能着色器…"
		await RenderingServer.frame_post_draw
		var warmup=RenderWarmup.new();add_child(warmup)
		await warmup.run(session.profiles)
		warmup.queue_free();warming=false;_refresh_ui()
	if mobile_ui:_apply_runtime_settings()
	if persistence_enabled and not managed_startup:
		var existing_save:Dictionary=SaveStore.read_save(save_path)
		if existing_save.ok:
			_open_menu()
			game_menu.set_message("发现上一局存档。可读取继续；返回后开始新局的首次操作会更新存档。")
		elif FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path+".bak"):
			notice.text="原存档无法读取，尚未覆盖。可先检查存档文件。";shop_odds_label.hide()
	if is_inside_tree():startup_completed.emit({"ok":true,"error":""})
# Realtime play drops excess wall time after a loading/driver/OS hitch instead
# of replaying seconds of simulation and VFX in a single frame. The deterministic
# clock API remains unrestricted for offline simulation and replay tests.
const MAX_REALTIME_DELTA:float=0.1
func _process(delta:float)->void:
	var wall_delta:float=delta
	delta=clampf(delta,0.0,MAX_REALTIME_DELTA) if is_finite(delta) else 0.0
	_sync_tactical_controls()
	var frame_start:=Time.get_ticks_usec()
	var was_battle:bool=session.phase()=="battle" and session.clock.sim.phase=="running" and not session.paused
	if delta>0:
		frame_times.append(wall_delta)
		if frame_times.size()>600:frame_times.pop_front()
	var events:Array=[]
	if session.phase()=="battle":
		events=session.advance(delta)
		if was_battle or session.clock.sim.phase=="running":visual_time=float(session.clock.sim.tick)*0.05+session.clock.accumulator
		elif not session.paused:visual_time+=delta
	elif not session.paused:visual_time+=delta
	for event in events:
		tactical_input.acknowledge(event)
		ordinary_audio.consume(event)
	var after_sim:=Time.get_ticks_usec()
	_presenting_combat_events=was_battle
	if session.phase() in ["battle","result","finished","error"]:
		stage.update_display(session.clock.sim.units,events,visual_time,session.clock.sim.tick)
	else:stage.update_display(stage.units,[],visual_time,0)
	_presenting_combat_events=false
	var telegraphs:Array=[]
	if session.phase()=="battle" and session.clock.sim.phase=="running" and session.clock.sim.has_method("attack_telegraphs"):telegraphs=session.clock.sim.attack_telegraphs()
	stage.update_attack_telegraphs(telegraphs,visual_time)
	if session.phase()=="error":
		_audio_tail_started=false;combat_audio.reset(session.clock.generation);ordinary_audio.reset(session.clock.generation)
	elif was_battle or session.phase()=="battle":
		for event in events:combat_audio.consume(event)
		combat_audio.update_time(visual_time,session.paused)
		ordinary_audio.update_time(visual_time,session.paused)
		if session.clock.sim.phase=="finished" and not _audio_tail_started:
			_audio_tail_started=true;_audio_tail_flushed=false;_audio_tail_end=visual_time+0.8
			combat_audio.begin_tail_drain(visual_time,0.8);ordinary_audio.begin_tail_drain(visual_time,0.8)
	elif _audio_tail_started:
		combat_audio.update_time(visual_time,session.paused);ordinary_audio.update_time(visual_time,session.paused)
	if _audio_tail_started and not _audio_tail_flushed and not session.paused and visual_time>=_audio_tail_end:
		_audio_tail_flushed=true;combat_audio.reset(session.clock.generation);ordinary_audio.reset(session.clock.generation)
	if inspected_id>=0:_refresh_inspector()
	cpu_samples.append(Vector2(after_sim-frame_start,Time.get_ticks_usec()-after_sim))
	if cpu_samples.size()>600:cpu_samples.pop_front()
	if was_battle and delta>0:
		battle_frame_times.append(wall_delta);battle_cpu_samples.append(cpu_samples.back())
		if battle_frame_times.size()>7200:battle_frame_times.pop_front();battle_cpu_samples.pop_front()
	if previous_phase!=session.phase():
		if previous_phase=="battle":_save_battle_performance()
		_refresh(false)
		if session.phase()=="result" or (session.phase()=="finished" and session.match_format()=="six_round_league"):_checkpoint_dirty=true;_save_checkpoint(false)
	if _autosave_pending:
		_autosave_delay-=delta
		if _autosave_delay<=0:_save_checkpoint(false)
	if session.phase()=="battle":status.text=_battle_status_text()
	if metrics:metrics.text="%d FPS" % Engine.get_frames_per_second()
	_refresh_tactical_hud()
func act(command:Dictionary)->Dictionary:
	var checkpoint_error:String=""
	if persistence_enabled and command.get("type","")=="start_battle" and session.phase()=="preparation":
		_prebattle_checkpoint_hash=""
		var checkpoint:Dictionary=_save_checkpoint(false)
		if not checkpoint.ok:checkpoint_error=str(checkpoint.error)
		else:_prebattle_checkpoint_hash=FileAccess.get_sha256(save_path)
	if command.get("type","") in ["start_battle","next_round","restart"]:_cancel_bench_drag()
	var result:Dictionary=session.command(command)
	if result.ok and command.get("type","")=="restart" and (session.combat_mode()!=new_game_mode or (new_game_mode=="tactical_v1" and (session.match_format()!="six_round_league" or session.rules_profile()!=Session.RULES_PROFILE_PC_SHORT))):result=session.new_game(session.seed,new_game_mode)
	if not result.ok:notice.text=_error_text(str(result.get("error","操作失败")));shop_odds_label.hide();return result
	notice.text=""
	_dismiss_recruitment_preview()
	if command.type in ["buy_offer","claim_reinforcement"]:selected_owned=result.get("unit_id",selected_owned)
	if command.type=="restart":selected_owned="";roster_signature="";visual_time=0
	if command.type in ["start_battle","next_round","restart"]:report_panel.hide();reinforcement_panel.hide()
	if command.type in ["start_battle","restart"]:report_text.text=""
	if command.type=="set_normal_target_policy":_refresh_ui()
	else:_refresh(command.type in ["start_battle","next_round","restart"])
	_refresh_tactical_hud()
	if session.phase()=="preparation":_checkpoint_dirty=true;_save_checkpoint(false)
	if not checkpoint_error.is_empty():
		_save_error_notice="开战前进度未能保存："+checkpoint_error;notice.text=_save_error_notice;shop_odds_label.hide()
	return result
func select_owned(id:String)->void:
	if recruitment_preview.visible:return
	inspected_id=-1;stage.inspection_id=-1;_inspector_inputs.clear()
	if detail_scroll:detail_scroll.scroll_vertical=0
	selected_owned=id
	stage.set_selected(-1)
	for combat_id in session.id_to_unit:
		if session.id_to_unit[combat_id]==id:stage.set_selected(combat_id);break
	_refresh_ui()
func _place(id:int,point:Vector2)->void:
	if inspected_id>=0 or reinforcement_panel.visible or game_menu.visible or report_panel.visible or recruitment_preview.visible:return
	if session.place(session.id_to_unit.get(id,""),point):
		stage.units=_preparation_roster();stage.update_display(stage.units,[],visual_time,0)
		if persistence_enabled:_checkpoint_dirty=true;_autosave_pending=true;_autosave_delay=0.35
func _preparation_roster()->Array:
	var roster:Array=session.preview_roster()
	roster.append_array(session.opponent_preview().get("units",[]))
	return roster
func _refresh(force:bool)->void:
	var phase:String=session.phase()
	stage.configure_arena(session.arena_config())
	if phase=="preparation":
		_audio_tail_started=false
		combat_audio.reset(session.clock.generation)
		var roster:Array=_preparation_roster();var signature:=""
		for u in roster:signature+="%s:%s:%d;"%[u.roster_unit_id,u.character_id,u.star]
		if force or signature!=roster_signature or previous_phase!="preparation":
			stage.set_roster(roster,session.clock.generation,true);roster_signature=signature;visual_time=0
		ordinary_audio.reset(session.clock.generation)
	elif phase=="battle" and (force or previous_phase!="battle"):
		_audio_tail_started=false
		stage.set_roster(session.clock.sim.units,session.clock.generation,false);visual_time=0
		combat_audio.begin_roster(session.clock.sim.units,session.clock.generation)
		ordinary_audio.begin_battle(session.clock.sim.units,session.clock.generation,int(session.clock.sim.options.seed))
		battle_frame_times.clear();battle_cpu_samples.clear()
	elif phase=="finished" and force:
		# Final checkpoints contain league state, not a live combat replay.
		# Never leave the previous game's preview actors on the restored board.
		stage.set_roster([],session.clock.generation,false);visual_time=0
		combat_audio.reset(session.clock.generation);ordinary_audio.reset(session.clock.generation)
	previous_phase=phase
	_sync_round_result()
	select_owned(selected_owned)
	_refresh_tactical_hud()
func _battle_status_text()->String:
	var cap:float=float(session.clock.sim.options.max_ticks)*0.05
	var timer:String="%.1f / %d 秒 · "%[minf(float(session.clock.sim.tick)*0.05,cap),int(cap)]
	if session.clock.sim.phase=="finished":return timer+"我方战斗结束 · 正在结算其他对局"
	var overtime:Dictionary=session.clock.sim.overtime_state()
	if overtime.active:return timer+"加时 · 治疗及新护盾 %d%% · %s"%[int(round(overtime.healing_multiplier*100.0)),"EX实时选择释放" if session.combat_mode()=="tactical_v1" else "技能自动释放"]
	if session.combat_mode()=="tactical_v1":return timer+"左键选人 / 右键走位 · 1–%d 选择 EX"%int(session.rules.snapshot().config.max_level)
	return timer+"自动战斗 / 技能随战斗自动释放"
func _refresh_ui()->void:
	if recruitment_preview.visible and (session.phase()!="preparation" or _preview_slot<0 or _preview_slot>=session.rules.get_player().shop.size() or str(session.rules.get_player().shop[_preview_slot].get("character_id",""))!=_preview_offer_key):_dismiss_recruitment_preview()
	var p:Dictionary=session.rules.get_player();var state:Dictionary=session.rules.snapshot();var phase:String=session.phase();var prep:bool=phase=="preparation" and not warming
	if p.is_empty():return
	if menu_button:menu_button.disabled=warming
	var pending:bool=prep and not _pending_reinforcement().is_empty()
	reinforcement_button.visible=pending
	reinforcement_button.disabled=not pending or game_menu.visible or report_panel.visible or reinforcement_panel.visible or recruitment_preview.visible
	status.size.x=760 if pending else 900
	normal_target_selector.select(1 if session.normal_target_policy()=="wounded" else 0)
	normal_target_selector.disabled=not prep or game_menu.visible or report_panel.visible or reinforcement_panel.visible or recruitment_preview.visible
	normal_target_selector.tooltip_text="普攻只选择射程内、视线可达的敌人；嘲讽优先。残血优先按生命百分比，不考虑装甲、护盾或已发射攻击。走位、基础技能与 EX 保持原规则。仅准备阶段可切换；对手固定就近优先。"
	var odds_parts:PackedStringArray=[]
	for row in session.rules.get_shop_odds():odds_parts.append("%d费 %.0f%%"%[row.cost,row.percent])
	shop_odds_label.text=("已保留 · 下轮不自动刷新  /  " if p.get("shop_locked",false) else "")+"%d级 · 下次刷新  "%p.level+" / ".join(odds_parts)
	shop_odds_label.visible=notice.text.is_empty()
	shop_odds_label.tooltip_text="每个招募格按费用概率抽取，同费角色均分。升级不会刷新当前商店，概率只影响后续新抽的角色。玩家与 AI 使用相同规则。"
	if p.level<state.config.max_level:
		var next_parts:PackedStringArray=[]
		for row in preload("res://core/shop_odds.gd").describe(state.catalog,int(p.level)+1,state.config.level_shop_odds==1):next_parts.append("%d费 %.0f%%"%[row.cost,row.percent])
		shop_odds_label.tooltip_text+="\n升至 %d 级："%(int(p.level)+1)+" / ".join(next_parts)
	xp_button.tooltip_text=shop_odds_label.tooltip_text if p.level<state.config.max_level else "已达人口上限：每方最多上阵 %d 人"%int(state.config.max_level)
	title.text="BLUE / A     自走棋"
	var displayed_round:int=int(state.last_result.get("round",state.round)) if phase in ["result","finished"] else int(state.round)
	economy.text="第 %d 回合     生命 %d     金币 %d     等级 %d   ·   上阵 %d/%d"%[displayed_round,p.hp,p.gold,p.level,p.deployed.size(),p.level]
	if session.match_format()=="six_round_league":
		var player_score:Dictionary=session.rules.league.standings().filter(func(row):return row.participant_id=="p0")[0]
		economy.text="第 %d/6 回合     积分 %d     金币 %d     等级 %d   ·   上阵 %d/%d"%[displayed_round,player_score.points,p.gold,p.level,p.deployed.size(),p.level]
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
	deploy_button.disabled=not prep or owned.is_empty() or inspected_id>=0;sell_button.disabled=not prep or owned.is_empty() or inspected_id>=0
	refresh_button.text="刷新  ·  %d 金币"%state.config.refresh_cost
	refresh_button.tooltip_text=RecruitmentHints.refresh_hint(p,state.catalog,state.config,selected_owned if inspected_id<0 else "")
	refresh_button.disabled=not prep or p.gold<state.config.refresh_cost
	var remaining_offers:int=0
	for offer in p.shop:
		if not offer.is_empty():remaining_offers+=1
	shop_lock_button.text="已保留 · 点击取消" if p.get("shop_locked",false) else "保留至下回合"
	shop_lock_button.disabled=not prep or remaining_offers==0
	shop_lock_button.tooltip_text="保留当前剩余招募位，放弃下回合自动刷新。已购买的空位不会补充。生效一次后自动解除；付费刷新也会解除。"
	xp_button.disabled=not prep or p.gold<4 or p.level>=state.config.max_level
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
		var hint:Dictionary={"label":"","tooltip":""} if offer.is_empty() else RecruitmentHints.card_hint(p,offer.character_id,_name(offer.character_id))
		card.progress.text=hint.label;card.progress.visible=portrait!=null
		button.tooltip_text=hint.tooltip
		if not offer.is_empty():
			var matchup:Dictionary=_matchup(session.clock.sim.preview_unit(offer.character_id))
			button.tooltip_text+="\n攻击属性 "+matchup.attack_name+" · 装甲 "+matchup.armor_name+"\n"+matchup.outgoing_text+"\n"+matchup.caveat
		button.text="已招募" if offer.is_empty() else "" if portrait!=null else "%s\n%d 金币\n%s"%[_name(offer.character_id),offer.cost,hint.label]
		shop_preview_buttons[i].disabled=not prep or offer.is_empty() or warming or game_menu.visible or report_panel.visible or reinforcement_panel.visible or recruitment_preview.visible
		card.art.modulate=Color(1,1,1,1.0 if prep else 0.5)
		button.disabled=not prep or offer.is_empty() or p.gold<int(offer.get("cost",9999))
	for i in range(9):
		var button:Button=bench[i]
		var tactical_bench:bool=session.combat_mode()=="tactical_v1"
		button.icon=null;button.get_node("StarBadge").text=""
		if i<p.bench.size():
			var unit:Dictionary=session._owned(p,p.bench[i]);button.disabled=not prep
			button.tooltip_text="%s · %s\n从备战席拖到己方区域部署"%[_name(unit.character_id),"二星 · EX已解锁" if unit.star==2 else "一星"]
			button.text="" if tactical_bench else _name(unit.character_id)+(" ★★" if unit.star==2 else " ★")
			if tactical_bench:
				button.icon=bench_previews.get_texture(unit.character_id,unit.star,Vector2i(160,192));button.expand_icon=true;button.add_theme_constant_override("icon_max_width",76)
				button.get_node("StarBadge").text="★★" if unit.star==2 else ""
		else:button.text="" if tactical_bench else "·";button.tooltip_text="空备战位";button.disabled=true
	report_button.disabled=not session.battle_feedback().get("completed",false)
	start_button.disabled=warming or (prep and p.deployed.is_empty())
	start_button.text="开始战斗" if prep else ("继续战斗" if session.paused else "暂停") if phase=="battle" else "下一回合" if phase=="result" else "重新开始"
	standings.text="对局排名"
	var ranked:Array=state.players.duplicate();ranked.sort_custom(func(a,b):return a.hp>b.hp)
	for player in ranked:standings.text+="\n%s   %d"%["你" if player.id=="p0" else player.name,player.hp]
	standings.tooltip_text=""
	if session.match_format()=="six_round_league":
		standings.text="积分排名"
		standings.tooltip_text="共六轮，不提前淘汰。胜2分、平1分、负0分。\n依次比较积分、胜场、累计剩余生命比例；完全相同则并列。"
		for row in session.rules.league.standings():
			var participant:Dictionary=session.rules.get_player(row.participant_id)
			standings.text+="\n%d. %s   %d分"%[row.rank,"你" if row.participant_id=="p0" else participant.name,row.points]
	if phase in ["result","finished"]:
		var result:Dictionary=state.last_result
		if phase=="finished":status.text="获得第 %d 名 · %s"%[state.placement,"胜利" if state.outcome=="victory" else "本局结束"]
		else:status.text="%s  ·  本回合生命 -%d  ·  收入 +%d"%["回合胜利" if result.winner=="player" else "回合落败" if result.winner=="opponent" else "平局",result.player_damage,result.income_by_player.get("p0",0)]
		if phase=="result" and session.match_format()=="six_round_league":status.text="%s  ·  积分 +%d  ·  收入 +%d"%["回合胜利" if result.winner=="player" else "回合落败" if result.winner=="opponent" else "平局",2 if result.winner=="player" else 1 if result.winner=="draw" else 0,result.income_by_player.get("p0",0)]
	if inspected_id>=0:_refresh_inspector(true)
	elif phase=="battle":
		detail.text="点击战场角色或头顶图标\n查看实时生命、护盾、\n技能冷却与增益状态"
		detail.tooltip_text=""
	elif not owned.is_empty():
		var matchup:Dictionary=_matchup(session.clock.sim.preview_unit(owned.character_id,owned.star))
		detail.text+="\n攻击属性 "+matchup.attack_name+"\n防御装甲 "+matchup.armor_name+"\n"+_relation_details(matchup,false)+"\n"+matchup.caveat
		detail.tooltip_text=matchup.text
	else:detail.tooltip_text=""
	if session.combat_mode()=="tactical_v1":detail.text=detail.text.replace("二星解锁自动 EX","二星解锁手动 EX").replace("EX 已解锁 · 自动释放","EX 已解锁 · 手动释放")
	_apply_tactical_layout(phase)
	if warming:status.text="正在准备原始角色与技能着色器…";start_button.text="准备中…"
	if report_panel.visible or reinforcement_panel.visible or recruitment_preview.visible:
		for control in shop+bench+shop_preview_buttons+[deploy_button,sell_button,refresh_button,shop_lock_button,xp_button,report_button,start_button,menu_button,reinforcement_button]:control.disabled=true
func _name(key:String)->String:return session.profiles.get(key,{}).get("display_name",key)
func _start_pressed()->void:
	if warming or game_menu.visible or report_panel.visible or reinforcement_panel.visible or recruitment_preview.visible:return
	match session.phase():
		"preparation":
			if not _pending_reinforcement().is_empty():_open_reinforcement()
			else:act({"type":"start_battle"})
		"battle":session.paused=not session.paused;_refresh_ui()
		"result":act({"type":"next_round"})
		"finished","error":act({"type":"restart","seed":_fresh_seed()})
func _deploy_pressed()->void:
	if inspected_id>=0 or recruitment_preview.visible:return
	var p:Dictionary=session.rules.get_player()
	act({"type":"bench_unit" if selected_owned in p.deployed else "deploy_unit","unit_id":selected_owned})
func _build_ui()->void:
	canvas=CanvasLayer.new();canvas.layer=5;add_child(canvas)
	_top_panel=_panel(Rect2(0,0,1280,64),Color("f3f8fb"))
	_sidebar_panel=_panel(Rect2(1016,78,250,630),Color("eff5f8"))
	_shop_panel=_panel(Rect2(14,713,1252,175),Color("f3f8fb"))
	title=_label("",Rect2(24,16,240,36),22)
	economy=_label("",Rect2(310,22,730,30),17)
	status=_label("",Rect2(24,76,900,35),18);status.clip_text=true
	reinforcement_button=_button("增援待选 · 三选一",Rect2(798,77,204,32),_open_reinforcement)
	normal_target_selector=OptionButton.new();normal_target_selector.position=Vector2(1034,91);normal_target_selector.size=Vector2(214,32);normal_target_selector.add_theme_font_size_override("font_size",15)
	normal_target_selector.add_item("我方普攻：就近优先");normal_target_selector.add_item("我方普攻：残血优先")
	for kind in ["normal","hover","pressed","disabled"]:
		var style:=StyleBoxFlat.new();style.bg_color=Color("dfeef5") if kind=="normal" else Color("e7ecef") if kind=="disabled" else Color("bfdfef");style.set_corner_radius_all(7);style.content_margin_left=8;style.content_margin_right=24;normal_target_selector.add_theme_stylebox_override(kind,style)
	for kind in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:normal_target_selector.add_theme_color_override(kind,Color("244c66"))
	normal_target_selector.add_theme_color_override("font_disabled_color",Color("94a4af"))
	normal_target_selector.item_selected.connect(_choose_normal_target_policy);canvas.add_child(normal_target_selector)
	detail_scroll=ScrollContainer.new();detail_scroll.position=Vector2(1034,131);detail_scroll.size=Vector2(214,224);detail_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;canvas.add_child(detail_scroll)
	detail=Label.new();detail.custom_minimum_size=Vector2(194,0);detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL;detail.add_theme_font_size_override("font_size",15);detail.add_theme_color_override("font_color",Color("25455a"));detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;detail_scroll.add_child(detail)
	deploy_button=_button("上阵",Rect2(1034,363,101,36),_deploy_pressed)
	sell_button=_button("出售",Rect2(1143,363,103,36),_sell_pressed)
	standings=_label("",Rect2(1034,404,214,184),12)
	report_button=_button("上回合战报",Rect2(1034,596,212,30),show_battle_report)
	start_button=_button("开始战斗",Rect2(1034,636,212,48),_start_pressed)
	_bench_label=_label("备战席",Rect2(24,666,70,28),14)
	for i in range(9):
		var index:=i
		bench.append(_button("·",Rect2(99+i*98,659,92,40),func():
			var p:Dictionary=session.rules.get_player()
			if index<p.bench.size():select_owned(p.bench[index])
		))
		bench.back().gui_input.connect(func(event:InputEvent):_bench_gui_input(event,index))
		var stars:=Label.new();stars.name="StarBadge";stars.position=Vector2(63,5);stars.size=Vector2(27,20);stars.add_theme_font_size_override("font_size",13);stars.add_theme_color_override("font_color",Color("9b6912"));stars.mouse_filter=Control.MOUSE_FILTER_IGNORE;bench.back().add_child(stars)
	_shop_label=_label("招募",Rect2(30,726,100,25),17)
	shop_odds_label=_label("",Rect2(136,726,820,25),15);shop_odds_label.mouse_filter=Control.MOUSE_FILTER_PASS
	for i in range(5):
		var index:=i
		shop.append(_button("",Rect2(30+i*187,761,175,105),func():act({"type":"buy_offer","slot":index})))
		_decorate_card(shop.back())
		var preview_button:=_button("查看技能",Rect2(120+i*187,763,80,18),func():_preview_shop_offer(index))
		preview_button.add_theme_font_size_override("font_size",11);preview_button.size=Vector2(80,18);preview_button.tooltip_text="只查看角色技能，不花费金币";shop_preview_buttons.append(preview_button)
	shop_lock_button=_button("",Rect2(990,721,252,30),_toggle_shop_retention)
	refresh_button=_button("",Rect2(990,761,252,45),func():act({"type":"refresh_shop"}))
	xp_button=_button("购买经验  ·  4 金币",Rect2(990,820,252,45),func():act({"type":"buy_xp"}))
	notice=_label("",Rect2(136,723,820,28),15);notice.add_theme_color_override("font_color",Color("a43d53"))
	metrics=_label("",Rect2(1170,22,95,25),14)
	menu_button=_button("菜单",Rect2(1050,15,96,34),_open_menu)
	var preview_layer:=CanvasLayer.new();preview_layer.layer=26;add_child(preview_layer)
	recruitment_preview=RecruitmentPreview.new();preview_layer.add_child(recruitment_preview);recruitment_preview.closed.connect(_close_recruitment_preview)
	var reinforcement_layer:=CanvasLayer.new();reinforcement_layer.layer=25;add_child(reinforcement_layer)
	reinforcement_panel=ReinforcementPanel.new();reinforcement_layer.add_child(reinforcement_panel)
	reinforcement_panel.claim_requested.connect(_claim_reinforcement)
	reinforcement_panel.skip_requested.connect(_skip_reinforcement)
	reinforcement_panel.closed.connect(_refresh_ui)
	var menu_layer=CanvasLayer.new();menu_layer.layer=30;add_child(menu_layer)
	game_menu=GameMenu.new();menu_layer.add_child(game_menu)
	game_menu.closed.connect(_close_menu)
	game_menu.save_requested.connect(func():_save_checkpoint(true))
	game_menu.continue_requested.connect(_load_checkpoint)
	game_menu.settings_requested.connect(_apply_settings)
	game_menu.quit_requested.connect(_request_quit)
	if managed_startup:
		game_menu.configure_title_navigation()
		game_menu.return_to_title_requested.connect(request_return_to_title)
		var result_layer:=CanvasLayer.new();result_layer.layer=28;add_child(result_layer)
		round_result_panel=preload("res://scripts/round_result_panel.gd").new();result_layer.add_child(round_result_panel)
		round_result_panel.next_round_requested.connect(_next_result_round)
		round_result_panel.title_requested.connect(request_return_to_title)
		round_result_panel.new_game_requested.connect(func():_return_restart=true;request_return_to_title())
		return_dialog=ConfirmationDialog.new();return_dialog.title="返回主菜单";return_dialog.cancel_button_text="留在游戏";add_child(return_dialog)
		return_dialog.confirmed.connect(func():confirm_return_to_title(_return_discard_allowed))
		return_dialog.canceled.connect(_cancel_return_to_title)
	quit_dialog=ConfirmationDialog.new();quit_dialog.title="存档未能写入";quit_dialog.ok_button_text="仍然退出";quit_dialog.cancel_button_text="返回游戏";add_child(quit_dialog)
	quit_dialog.confirmed.connect(_exit_application)
	quit_dialog.canceled.connect(func():quit_dialog.hide())
	report_backdrop=ColorRect.new();report_backdrop.color=Color(0.06,0.1,0.15,0.55);report_backdrop.z_index=19;report_backdrop.mouse_filter=Control.MOUSE_FILTER_STOP;canvas.add_child(report_backdrop);report_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);report_backdrop.hide()
	report_panel=Panel.new();report_panel.position=Vector2(96,138);report_panel.size=Vector2(824,536);report_panel.z_index=20;canvas.add_child(report_panel)
	var report_style=StyleBoxFlat.new();report_style.bg_color=Color("edf5fa");report_style.set_corner_radius_all(12);report_panel.add_theme_stylebox_override("panel",report_style)
	report_text=RichTextLabel.new();report_text.position=Vector2(22,46);report_text.size=Vector2(780,468);report_text.add_theme_color_override("default_color",Color("25455a"));report_text.add_theme_font_size_override("normal_font_size",15);report_panel.add_child(report_text)
	var close:=_button("关闭战报",Rect2(0,0,114,30),_close_battle_report);close.reparent(report_panel);close.name="CloseReport";close.position=Vector2(688,8)
	report_panel.visibility_changed.connect(_sync_report_modal)
	report_panel.hide()
func _label(text:String,rect:Rect2,size:int)->Label:
	var node:=Label.new();node.text=text;node.position=rect.position;node.size=rect.size;node.add_theme_font_size_override("font_size",size);node.add_theme_color_override("font_color",Color("25455a"));node.mouse_filter=Control.MOUSE_FILTER_IGNORE;canvas.add_child(node);return node
func _panel(rect:Rect2,color:Color)->Panel:
	var node:=Panel.new();node.position=rect.position;node.size=rect.size;var style:=StyleBoxFlat.new();style.bg_color=color;style.set_corner_radius_all(10);node.add_theme_stylebox_override("panel",style);canvas.add_child(node);return node
func _button(text:String,rect:Rect2,callback:Callable)->Button:
	var node:=Button.new();node.text=text;node.position=rect.position;node.size=rect.size;node.add_theme_font_size_override("font_size",16)
	for kind in ["normal","hover","pressed","disabled"]:
		var style:=StyleBoxFlat.new();style.bg_color=Color("dfeef5") if kind=="normal" else Color("bfdfef") if kind=="hover" else Color("a9d5e8") if kind=="pressed" else Color("e7ecef");style.set_corner_radius_all(7);style.content_margin_left=8;style.content_margin_right=8;node.add_theme_stylebox_override(kind,style)
	node.add_theme_color_override("font_color",Color("244c66"));node.add_theme_color_override("font_hover_color",Color("173c56"));node.add_theme_color_override("font_pressed_color",Color("173c56"));node.add_theme_color_override("font_disabled_color",Color("94a4af"));node.add_theme_color_override("font_focus_color",Color("173c56"));node.pressed.connect(callback);canvas.add_child(node);return node
func _unhandled_input(event:InputEvent)->void:
	if _handle_tactical_event(event):return
	if event is InputEventKey and event.pressed and not warming:
		if event.keycode==KEY_ESCAPE and not event.echo:
			if game_menu.visible:_close_menu()
			elif recruitment_preview.visible:recruitment_preview.close_panel()
			elif reinforcement_panel.visible:reinforcement_panel.close_panel()
			elif report_panel.visible:_close_battle_report()
			else:_open_menu()
			get_viewport().set_input_as_handled();return
		if game_menu.visible or reinforcement_panel.visible or recruitment_preview.visible:return
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
	var tactical_errors:Dictionary={"unit_not_on_bench":"角色已不在备战席，请重新选择","population_full":"上阵人数已满，升级可增加人口","invalid_deployment_point":"请放在己方空地，避开掩体与其他角色","deployment_requires_preparation":"当前不能部署角色","stale_deployment":"战场已变化，请重新拖动","ex_locked":"二星后解锁EX","actor_dead":"角色已退场","actor_stunned":"眩晕中，暂时无法执行","ex_in_progress":"当前EX动作尚未结束","energy_or_cooldown":"共享能量不足，或EX仍在冷却","invalid_enemy_target":"请选择敌方角色","invalid_self_target":"请确认自身技能","target_out_of_range":"目标超出技能范围","target_obstructed":"目标被高掩体遮挡","invalid_direction":"请选择角色前方的方向","invalid_destination":"请选择战场内的有效位置","occupied_destination":"落点被角色占据","unreachable_destination":"无法到达这个位置","move_too_far":"这次转移的路线超过4米","already_moving":"正在前往这个位置","already_at_destination":"已经在这个位置","no_move_charges":"战术转移次数正在恢复","duplicate_command":"这个指令已经提交","stale_generation":"战斗已更新，请重新选择"}
	if tactical_errors.has(code):return tactical_errors[code]
	if code=="deployment_full" and session.rules.get_player().level>=session.rules.snapshot().config.max_level:
		return "每方最多上阵 %d 人，请先将一名角色移至备战席"%session.rules.snapshot().config.max_level
	return {"reinforcement_pending":"请先选择或放弃本回合增援","stale_reinforcement":"这次增援已经处理，请重新打开查看","invalid_reinforcement_round":"增援回合已变化，请重新打开查看","insufficient_gold":"金币不足","bench_full":"备战席已满，请先上阵或出售角色","deployment_full":"上阵人数已满，升级可增加人口","empty_army":"请先至少上阵一名角色","empty_slot":"这个角色已经招募过了","empty_shop":"商店已空，没有可保留的招募位","invalid_shop_lock":"商店保留状态无效","max_level":"已达到最高等级","unknown_unit":"角色已合成或出售，请重新选择","wrong_phase":"当前阶段不能执行这个操作"}.get(code,code)

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
	var progress:=Label.new();progress.position=Vector2(90,82);progress.add_theme_font_size_override("font_size",13);progress.add_theme_color_override("font_color",Color("587385"));progress.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(progress);progress.size=Vector2(80,20)
	shop_cards.append({"art":art,"name":name_label,"price":price,"progress":progress})

func _character_hint(key:String)->String:
	return {"shiroko":"定时投掷手榴弹\n普攻有概率提升攻速\nEX：无人机连射","hoshino":"低血量触发持续回复\nEX：扇形连射与护盾","hina":"换弹后提高攻击\nEX：扇形穿透扫射","aru":"定时狙击，有概率爆炸\nEX：爆破狙击","yuuka":"定时单体射击\n进入掩体可触发回复\nEX：自身护盾","aris":"定时蓄能，最多两层\nEX：蓄能强化贯穿光束","serika":"定时连射\nEX：换弹并强化攻击/攻速","iori":"定时单体射击\n未在掩体中时追加伤害\nEX：三连射，波及目标后方","tsubaki":"低血量时回复一次\n换弹期间受到伤害降低\nEX：提高防御并嘲讽周围敌人","nonomi":"定时提高攻击\nEX：大范围扇形扫射","mutsuki":"定时布置三枚触发地雷\n普攻有概率提高命中\nEX：轰炸三处圆形区域","haruna":"定时单体狙击\n静止时提高攻击\nEX：直线贯穿，逐目标递减","koharu":"友军低于半血时治疗\n定时提高治疗力\nEX：范围治疗与伤害","asuna":"每 20 秒单体 11 连射\nEX：向前冲刺，攻击速度 +57.37%，持续 30 秒\n子技能：施放 EX 时攻击速度额外 +38.31%，持续 30 秒\nEX 闪避值 +43.41%，仅冲刺位移期间"}.get(key,"")

func _fresh_seed()->int:
	return randi_range(1,2147483646)

func show_battle_report()->void:
	if reinforcement_panel.visible or recruitment_preview.visible:return
	var data:Dictionary=session.battle_feedback()
	if not data.get("completed",false):return
	var lines:Array[String]=["第 %d 回合 · 战斗 %.1f 秒"%[data.round,data.duration_seconds],"输出/承伤为实际生命损失；破盾单独统计。EX 命中人数按每次施法去重后累加。",""]
	var policies:Array=data.get("normal_target_policies",["nearest","nearest"])
	lines.insert(1,"本场普攻：我方%s · 对手%s"%[_normal_target_label(policies[0]),_normal_target_label(policies[1])])
	var overtime:Dictionary=data.get("overtime",{})
	if float(overtime.get("base_damage_multiplier",1.0))<1.0:
		lines.append("战术模式适配：开局伤害 %d%%，加时逐步回升；结算时伤害 %d%%，治疗及新护盾 %d%%。角色原始技能系数未改。"%[int(round(overtime.base_damage_multiplier*100.0)),int(round(overtime.damage_multiplier*100.0)),int(round(overtime.healing_multiplier*100.0))])
	elif overtime.get("active",false):lines.append("本场进入加时：治疗及新护盾效果降至 %d%%；已有护盾和技能伤害不变"%int(round(overtime.healing_multiplier*100.0)))
	var first:Dictionary=data.get("first_death",{})
	if not first.is_empty():lines.append("首个阵亡：%s方 %s（%.1f 秒）"%["我" if first.team==0 else "敌",_name(first.character_id),first.seconds])
	for team in range(2):
		lines.append("\n我方" if team==0 else "\n敌方")
		for unit in data.units:
			if unit.team!=team:continue
			lines.append("%s %s  输出 %d · 承伤 %d · 破盾 %d · 护盾吸收 %d\n    EX %d 次，累计命中 %d 人次"%[_name(unit.character_id),"★★" if unit.star==2 else "★",unit.damage_dealt,unit.damage_taken,unit.shield_damage_dealt,unit.shield_damage_taken,unit.ex_casts,unit.ex_unique_hits])
	normal_target_selector.get_popup().hide()
	report_text.text="\n".join(lines);report_panel.show();_refresh_ui()

func _open_menu()->void:
	if warming or game_menu.visible:return
	reinforcement_panel.hide()
	_dismiss_recruitment_preview()
	normal_target_selector.get_popup().hide()
	_menu_was_paused=session.paused;_menu_generation=session.clock.generation;session.paused=true
	var saved:Dictionary=SaveStore.read_save(save_path) if persistence_enabled else {"ok":false}
	game_menu.open_menu(settings_values,persistence_enabled and (session.phase() in ["preparation","result"] or (session.phase()=="finished" and session.match_format()=="six_round_league")),saved.ok,"设置仅在点击“应用设置”后生效；Esc 返回游戏。")
	_refresh_ui()
func _close_menu()->void:
	if not game_menu.visible:return
	game_menu.hide()
	if session.clock.generation==_menu_generation:session.paused=_menu_was_paused
	_refresh_ui()
func _save_checkpoint(show_message:bool=false)->Dictionary:
	_autosave_pending=false
	if not persistence_enabled:return {"ok":false,"error":"存档未启用"}
	var exported:Dictionary=session.export_save()
	if not exported.ok:
		if show_message and game_menu.visible:game_menu.set_message("战斗中保留开战前的准备存档",true)
		return exported
	var result:Dictionary=SaveStore.write_save(exported.data,save_path)
	_checkpoint_dirty=not result.ok
	if not result.ok:
		_save_error_notice="进度未能保存："+str(result.error);notice.text=_save_error_notice;shop_odds_label.hide()
	else:
		if not _save_error_notice.is_empty() and notice.text==_save_error_notice:
			notice.text="";_refresh_ui()
		_save_error_notice=""
	if show_message and game_menu.visible:
		game_menu.set_message(("本局结算已保存" if session.phase()=="finished" else "准备进度已保存") if result.ok else "保存失败："+str(result.error),not result.ok)
		if result.ok:game_menu.continue_button.disabled=false
	return result
func _load_checkpoint()->Dictionary:
	if not persistence_enabled:return {"ok":false,"error":"存档未启用"}
	var saved:Dictionary=SaveStore.read_save(save_path)
	if not saved.ok:
		if game_menu.visible:game_menu.set_message("读取失败："+str(saved.error),true)
		return saved
	var result:Dictionary=session.restore_save(saved.data)
	if result.ok:_dismiss_recruitment_preview()
	if not result.ok:
		if game_menu.visible:game_menu.set_message("读取失败："+str(result.error),true)
		return result
	_autosave_pending=false;_checkpoint_dirty=false;selected_owned="";roster_signature="";visual_time=0;report_panel.hide();reinforcement_panel.hide();report_text.text=""
	_save_error_notice="";notice.text=str(saved.get("warning",""));_refresh(true);_close_menu()
	return result
func _apply_settings(values:Dictionary)->void:
	var result:Dictionary=UserSettings.write_settings(values,settings_path,mobile_ui)
	if not result.ok:
		if game_menu.visible:game_menu.set_message("设置未应用："+str(result.error),true)
		return
	settings_values=UserSettings.with_quality_defaults(result.values,true) if mobile_ui else result.values;_apply_runtime_settings()
	if game_menu.visible:game_menu.set_message("设置已保存")
func _apply_runtime_settings()->void:
	var quality:Dictionary=RenderQuality.resolve(settings_values,mobile_ui)
	if quality.ok:
		get_viewport().scaling_3d_scale=quality.values.rendering_scale
		Engine.max_fps=quality.values.max_fps
	stage.set_reduce_smoke(bool(settings_values.get("reduce_smoke",false)))
	if DisplayServer.get_name()=="headless":return
	var master:int=AudioServer.get_bus_index("Master")
	if master>=0:
		AudioServer.set_bus_mute(master,bool(settings_values.muted) or float(settings_values.volume)<=0)
		AudioServer.set_bus_volume_db(master,linear_to_db(maxf(float(settings_values.volume),0.0001)))
	if not mobile_ui:DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings_values.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
func _notification(what:int)->void:
	if mobile_ui and is_inside_tree():
		if what==NOTIFICATION_APPLICATION_PAUSED:_suspend_mobile()
		elif what==NOTIFICATION_APPLICATION_RESUMED:_resume_mobile()
		elif what==NOTIFICATION_WM_GO_BACK_REQUEST:
			if tactical_input.armed_actor>=0:_cancel_mobile_aim()
			elif game_menu.visible:_close_menu()
			elif recruitment_preview.visible:recruitment_preview.close_panel()
			elif reinforcement_panel.visible:reinforcement_panel.close_panel()
			elif report_panel.visible:_close_battle_report()
			else:_open_menu()
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:_cancel_bench_drag();tactical_input.cancel();mobile_gestures.cancel()
	if what==NOTIFICATION_WM_CLOSE_REQUEST and is_inside_tree() and not managed_startup:
		_request_quit()
func _request_quit()->void:
	# Merely opening and closing the app must not replace an existing save.
	if persistence_enabled and _checkpoint_dirty:
		var result:Dictionary=_save_checkpoint(false)
		if not result.ok:
			_open_menu()
			game_menu.set_message("最新进度未能保存。返回后可重试保存。",true)
			quit_dialog.dialog_text="最新进度未能保存，退出可能丢失尚未保存的操作。\n是否仍然退出？"
			if DisplayServer.get_name()=="headless":quit_dialog.show()
			else:quit_dialog.popup_centered(Vector2i(470,180))
			return
	_exit_application()
func _exit_application()->void:
	get_tree().quit()
func _exit_tree()->void:
	if mobile_ui and get_tree():get_tree().quit_on_go_back=_previous_quit_on_go_back
	if session:session._cancel_ai_jobs()
	if DisplayServer.get_name()!="headless" and get_tree():get_tree().auto_accept_quit=_previous_auto_quit

func _sell_pressed()->void:
	if inspected_id<0 and not recruitment_preview.visible:act({"type":"sell_unit","unit_id":selected_owned})
func _matchup(unit:Dictionary)->Dictionary:
	return Matchups.describe(session.clock.sim,unit,_matchup_damage_types,_matchup_armor_types)
func _inspected_unit()->Dictionary:
	var roster:Array=stage.units if session.phase()=="preparation" else session.clock.sim.units
	for unit in roster:
		if int(unit.id)==inspected_id and int(unit.get("hp",0))>0:return unit
	return {}
func inspect_actor(id:int)->void:
	if warming or game_menu.visible or report_panel.visible or reinforcement_panel.visible or recruitment_preview.visible:return
	if session.phase() not in ["preparation","battle"]:return
	inspected_id=id;_inspector_inputs.clear()
	if _inspected_unit().is_empty():inspected_id=-1;stage.inspection_id=-1;_refresh_ui();return
	stage.dragging=false;stage.set_selected(-1);stage.inspection_id=id
	detail_scroll.scroll_vertical=0
	_refresh_ui()
func _refresh_inspector(force:bool=false)->void:
	if inspected_id<0:return
	var unit:Dictionary=_inspected_unit()
	if unit.is_empty():
		inspected_id=-1;stage.inspection_id=-1;_inspector_inputs.clear();_refresh_ui();return
	var strip:Control=stage.bars.get(inspected_id,{}).get("status")
	var revision:int=strip.revisions if strip else -1
	var inputs:Array=[inspected_id,unit.hp,unit.get("shield",0),revision,session.phase()]
	if not force and inputs==_inspector_inputs:return
	_inspector_inputs=inputs
	var matchup:Dictionary=_matchup(unit)
	var lines:PackedStringArray=["%s %s · %s"%[_name(unit.character_id),"★★" if unit.star==2 else "★","己方" if unit.team==0 else "敌方"],
		"生命 %d / %d · 护盾 %d"%[unit.hp,unit.max_hp,unit.get("shield",0)]]
	if strip and not strip.status.is_empty():
		lines.append("EX %s · 小 %s · 子 %s"%[strip.status.ex.text,strip.status.basic.text,strip.status.sub.text])
		for effect in strip.status.effects:lines.append(effect.hint)
		lines.append("\n技能触发")
		for key in ["ex","basic","sub"]:lines.append(strip.status[key].hint)
	lines.append_array(PackedStringArray(["", "%s · 射程 %.1f"%[unit.get("weapon",""),unit.get("range",0.0)],
		"攻击属性 "+matchup.attack_name+"\n防御装甲 "+matchup.armor_name,
		_relation_details(matchup,unit.team==1),matchup.caveat,"",_character_hint(unit.character_id)]))
	detail.text="\n".join(lines);detail.tooltip_text=matchup.text

func _relation_details(matchup:Dictionary,incoming:bool)->String:
	var lines:PackedStringArray=["承伤属性倍率：" if incoming else "对装甲属性倍率："]
	for row in matchup.incoming if incoming else matchup.outgoing:
		lines.append("%s ×%s"%[row.label,str(row.multiplier).trim_suffix(".0")])
	return "\n".join(lines)

func _toggle_shop_retention()->void:
	if warming or session.phase()!="preparation":return
	var player:Dictionary=session.rules.get_player()
	act({"type":"set_shop_locked","locked":not bool(player.get("shop_locked",false))})

func _choose_normal_target_policy(index:int)->void:
	if warming or session.phase()!="preparation" or game_menu.visible or report_panel.visible or reinforcement_panel.visible or recruitment_preview.visible:return
	if index not in [0,1]:return
	act({"type":"set_normal_target_policy","policy":"nearest" if index==0 else "wounded"})

func _normal_target_label(policy:String)->String:
	return "残血优先" if policy=="wounded" else "就近优先"

func _close_battle_report()->void:
	report_panel.hide();_refresh_ui()

func _sync_report_modal()->void:
	report_backdrop.visible=report_panel.visible
	_refresh_ui()
	if report_panel.visible:report_panel.get_node("CloseReport").grab_focus()

func _pending_reinforcement()->Dictionary:
	var event:Dictionary=session.rules.get_reinforcement()
	return event if event.get("status","")=="pending" else {}

func _reinforcement_cards(event:Dictionary)->Array:
	var cards:Array=[]
	var player:Dictionary=session.rules.get_player()
	for key in event.get("offers",[]):
		var path:String="res://assets/ui/portraits/"+str(key)+".png"
		if not portrait_cache.has(path) and ResourceLoader.exists(path):portrait_cache[path]=load(path)
		var copies:=0
		for unit in player.units:
			if unit.character_id==key and unit.star==1:copies+=1
		var hint:String=_character_hint(key)
		var lines:PackedStringArray=hint.split("\n")
		var short_hint:String=lines[0] if not lines.is_empty() else ""
		if lines.size()>1:short_hint+="\n"+lines[-1]
		var allowed:bool=player.bench.size()<session.rules.snapshot().config.bench_capacity or copies>=2
		cards.append({"name":_name(key),"portrait":portrait_cache.get(path),"progress":"%d/3 一星副本%s"%[copies," · 领取即升星" if copies>=2 else ""],"description":short_hint,"tooltip":hint+"\n免费领取一星；二星才解锁 EX。"+("\n备战席已满，请关闭后整理阵容。" if not allowed else ""),"can_claim":allowed})
	return cards

func _open_reinforcement()->void:
	if warming or session.phase()!="preparation" or game_menu.visible or report_panel.visible or recruitment_preview.visible:return
	var event:Dictionary=_pending_reinforcement()
	if event.is_empty():return
	normal_target_selector.get_popup().hide()
	stage.dragging=false
	reinforcement_panel.configure(event,_reinforcement_cards(event));reinforcement_panel.show();_refresh_ui()

func _claim_reinforcement(round_number:int,slot:int)->void:
	_resolve_reinforcement({"type":"claim_reinforcement","round":round_number,"slot":slot})

func _skip_reinforcement(round_number:int)->void:
	_resolve_reinforcement({"type":"skip_reinforcement","round":round_number})

func _resolve_reinforcement(command:Dictionary)->void:
	if warming or session.phase()!="preparation" or game_menu.visible or report_panel.visible or not reinforcement_panel.visible:return
	var event:Dictionary=_pending_reinforcement()
	if event.is_empty() or int(event.round)!=int(command.round):return
	var result:Dictionary=act(command)
	if result.ok:reinforcement_panel.hide();_refresh_ui()
	else:
		reinforcement_panel.configure(event,_reinforcement_cards(event));reinforcement_panel.set_message(_error_text(str(result.error)),true)

func _preview_shop_offer(index:int)->void:
	if warming or session.phase()!="preparation" or game_menu.visible or report_panel.visible or reinforcement_panel.visible or recruitment_preview.visible:return
	var player:Dictionary=session.rules.get_player()
	if index<0 or index>=player.shop.size() or player.shop[index].is_empty():return
	var offer:Dictionary=player.shop[index];var key:String=str(offer.character_id)
	var data:Dictionary=RecruitmentSkills.describe(session.clock.sim,key,_name(key),int(offer.cost),Session.INITIAL_BASIC_DELAY_CAP_SECONDS)
	if session.combat_mode()=="tactical_v1":
		for skill in data.skills:
			if skill.slot=="ex":skill.text+="\n实时手动释放 · 消耗%d共享能量 · 动作结束后可再次释放"%int(session.clock.sim.character_data(key).ex.originalCost)
	var path:String="res://assets/ui/portraits/"+key+".png"
	if not portrait_cache.has(path) and ResourceLoader.exists(path):portrait_cache[path]=load(path)
	if not recruitment_preview.configure(data,portrait_cache.get(path)):return
	_preview_slot=index;_preview_offer_key=key
	normal_target_selector.get_popup().hide();stage.dragging=false
	recruitment_preview.show();_refresh_ui()
func _dismiss_recruitment_preview()->void:
	if recruitment_preview:recruitment_preview.hide()
	_preview_slot=-1;_preview_offer_key=""
func _close_recruitment_preview()->void:
	var previous_slot:int=_preview_slot
	_dismiss_recruitment_preview();_refresh_ui()
	if previous_slot>=0 and previous_slot<shop_preview_buttons.size() and not shop_preview_buttons[previous_slot].disabled:shop_preview_buttons[previous_slot].grab_focus()

func _consume_ordinary_state(record:Dictionary)->void:
	if session.phase()=="battle" or _presenting_combat_events:ordinary_audio.consume_state(record)

func _sync_tactical_controls()->void:
	var active:bool=session.phase()=="battle" and session.clock.sim.phase=="running" and session.combat_mode()=="tactical_v1"
	stage.tactical_input_enabled=active
	if not active:
		if _tactical_generation!=-1:tactical_input.begin_battle(-1,[]);_tactical_generation=-1
		if is_instance_valid(tactical_hud):tactical_hud.hide()
		return
	if _tactical_generation!=session.clock.generation:
		_tactical_generation=session.clock.generation;_tactical_metadata.clear();_tactical_modes.clear()
		var slots:Array=[]
		for unit in session.clock.sim.units:
			if unit.team!=0:continue
			slots.append(unit.id)
			var ex:Dictionary=session.clock.sim.character_data(unit.character_id).ex
			var mode:String="point"
			if ex.kind in ["self_barrier","reload_and_self_buff","self_defense_buff_and_aoe_taunt","self_buff"]:mode="self"
			elif ex.kind in ["drone_damage","single_target_burst","direct_shot_then_explosion","three_shot_target_then_rear_fan"]:mode="enemy"
			_tactical_modes[unit.id]=mode
			_tactical_metadata[unit.id]={"name":_name(unit.character_id),"character_id":unit.character_id,"cost":int(ex.originalCost)}
		while slots.size()<clampi(session.rules.get_player().level,4,6):slots.append(-1)
		tactical_input.begin_battle(_tactical_generation,slots)
	tactical_input.sync(_tactical_context())
	stage.set_selected(tactical_input.selected_actor)
func _tactical_context(screen_position:Variant=null)->Dictionary:
	var hit:Dictionary={"point":null,"picked_actor":-1}
	if screen_position is Vector2:hit=stage.tactical_input_hit(screen_position)
	return {"phase":session.phase(),"generation":session.clock.generation,"tick":session.clock.sim.tick,"units":session.clock.sim.units,"target_modes":_tactical_modes,"point":hit.point,"picked_actor":hit.picked_actor}
func _handle_tactical_event(event:InputEvent,context_override:Dictionary={},consume_event:bool=true)->bool:
	if session.phase()!="battle" or session.clock.sim.phase!="running" or session.combat_mode()!="tactical_v1" or session.paused or warming:return false
	if game_menu.visible or recruitment_preview.visible or reinforcement_panel.visible or report_panel.visible:return false
	_sync_tactical_controls()
	var point:Variant=event.position if event is InputEventMouseButton or event is InputEventMouseMotion else null
	var context:Dictionary=_tactical_context(point) if context_override.is_empty() else context_override
	var commands:Array=tactical_input.handle(event,context)
	for command in commands:
		var queued:Dictionary=act(command)
		if not queued.ok:tactical_input.acknowledge({"type":"command_rejected","team":0,"generation":command.generation,"sequence":command.sequence,"error":queued.error})
	stage.set_selected(tactical_input.selected_actor)
	_refresh_tactical_hud()
	if tactical_input.last_handled:
		if consume_event:get_viewport().set_input_as_handled()
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and context.picked_actor>=0:
		inspect_actor(context.picked_actor)
		if consume_event:get_viewport().set_input_as_handled()
		return true
	return false
func _arm_tactical_slot(index:int)->bool:
	_sync_tactical_controls()
	if _tactical_generation<0:return false
	var armed:bool=tactical_input.arm_slot(index,_tactical_context());stage.set_selected(tactical_input.selected_actor);_refresh_tactical_hud()
	return armed
func _tactical_actor_click(id:int)->void:
	var unit=session.clock.sim._unit(id)
	if unit==null:return
	var context:Dictionary=_tactical_context();context.point=unit.cell;context.picked_actor=id
	var event:=InputEventMouseButton.new();event.pressed=true;event.button_index=MOUSE_BUTTON_LEFT
	_handle_tactical_event(event,context)
func _refresh_tactical_hud()->void:
	if not is_instance_valid(tactical_hud):return
	_sync_tactical_controls()
	if _tactical_generation<0:return
	var state:Dictionary=session.clock.sim.tactical_controls();var resources:Dictionary=state.resources
	var slots:Array=[]
	for id in tactical_input.slots():
		var unit=session.clock.sim._unit(id)
		if unit==null:slots.append({"actor_id":-1});continue
		var row:Dictionary=_tactical_metadata[id].duplicate()
		row.actor_id=id;row.hp=unit.hp;row.star=unit.star;row.cooldown=maxf(0.0,(maxi(unit.skill_ready,state.ex_busy_until.get(id,0))-session.clock.sim.tick)*0.05);slots.append(row)
	var hint:String="实时选择与释放，不暂停战斗 · 普攻和小技能自动执行"
	if tactical_input.armed_actor>=0:
		var mode:String=_tactical_modes[tactical_input.armed_actor]
		hint="已选择 %s EX · %s · 右键或Esc取消"%[_tactical_metadata[tactical_input.armed_actor].name,"点击确认自身技能" if mode=="self" else "点击敌方角色" if mode=="enemy" else "点击战场选择落点/方向"]
	if not tactical_input.last_error.is_empty():hint=_error_text(tactical_input.last_error)
	tactical_hud.refresh({"active":true,"slots":slots,"energy":resources.teams[0].energy,"moves":resources.teams[0].moves,"energy_next":(40-resources.tick%40)*0.05,"move_next":maxf(0,(resources.teams[0].move_ready-resources.tick)*0.05),"armed_actor":tactical_input.armed_actor,"pending":tactical_input.is_pending(),"hint":hint})
	if mobile_ui:
		tactical_hud.instructions.text="点选／拖动角色走位\n点EX选目标，或拖EX释放"
		tactical_hud.hint_text.text=hint.replace("右键或Esc取消","点取消EX按钮取消")
		if is_instance_valid(mobile_cancel_button):mobile_cancel_button.disabled=tactical_input.armed_actor<0 and not mobile_gestures.is_pending()

func _bench_generation()->int:return session.clock.generation
func _bench_texture_ready(character_id:String,star:int,_size:Vector2i,texture:Texture2D)->void:
	if not is_inside_tree():return
	var player:Dictionary=session.rules.get_player()
	for index in range(mini(bench.size(),player.bench.size())):
		var unit:Dictionary=session._owned(player,player.bench[index])
		if unit.character_id==character_id and unit.star==star:bench[index].icon=texture
	if bench_drag.is_pending():
		var unit:Dictionary=session._owned(player,bench_drag.unit_id)
		if not unit.is_empty() and unit.character_id==character_id and unit.star==star:bench_ghost.texture=texture
func _bench_gui_input(event:InputEvent,index:int)->void:
	if session.combat_mode()!="tactical_v1" or session.phase()!="preparation" or warming:return
	if game_menu.visible or report_panel.visible or recruitment_preview.visible or reinforcement_panel.visible:return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		var player:Dictionary=session.rules.get_player()
		if index>=player.bench.size():return
		if bench_drag.begin(player.bench[index],event.global_position):bench_ghost.texture=bench[index].icon
func _input(event:InputEvent)->void:
	if mobile_ui and _handle_mobile_event(event):
		get_viewport().set_input_as_handled();return
	if not bench_drag.is_pending():return
	if session.phase()!="preparation" or game_menu.visible or report_panel.visible or recruitment_preview.visible or reinforcement_panel.visible:
		_cancel_bench_drag();return
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		_cancel_bench_drag();get_viewport().set_input_as_handled();return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		_cancel_bench_drag();get_viewport().set_input_as_handled();return
	if event is InputEventMouseMotion:
		bench_drag.update(event.position)
		if bench_drag.is_dragging():
			var point:Variant=stage._mouse_ground(event.position);var checked:Dictionary=bench_drag.preview(point)
			bench_ghost.position=event.position-Vector2(48,80);bench_ghost.modulate=Color(1,1,1,0.85) if checked.ok else Color(1,0.45,0.45,0.65);bench_ghost.show()
			stage.show_deployment_marker(point,checked.ok);get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var dragged:bool=bench_drag.is_dragging();var result:Dictionary=bench_drag.drop(stage._mouse_ground(event.position))
		bench_ghost.hide();stage.show_deployment_marker(null,false)
		if dragged:
			if not result.ok:notice.text=_error_text(str(result.error));shop_odds_label.hide()
			get_viewport().set_input_as_handled()
func _cancel_bench_drag()->void:
	mobile_gestures.cancel()
	bench_drag.cancel()
	if is_instance_valid(bench_ghost):bench_ghost.hide()
	if is_instance_valid(stage):stage.show_deployment_marker(null,false)
func _commit_bench_drop(unit_id:String,point:Vector2)->Dictionary:
	var result:Dictionary=session.deploy_at(unit_id,point)
	if result.ok:
		selected_owned=unit_id;notice.text="";_refresh(true);_refresh_ui();_checkpoint_dirty=true
		if persistence_enabled:_save_checkpoint(false)
	return result
func _apply_tactical_layout(phase:String)->void:
	var tactical:bool=session.combat_mode()=="tactical_v1"
	var combat:bool=tactical and phase in ["battle","result","finished","error"]
	stage.set_tactical_layout(tactical,combat)
	_sidebar_panel.visible=not combat or inspected_id>=0 or phase in ["result","finished","error"]
	_shop_panel.visible=not combat;_bench_label.visible=not combat;_shop_label.visible=not combat
	for control in shop+bench+shop_preview_buttons+[refresh_button,shop_lock_button,xp_button,normal_target_selector,deploy_button,sell_button]:control.visible=not combat
	shop_odds_label.visible=not combat and notice.text.is_empty()
	detail_scroll.visible=not combat or inspected_id>=0
	standings.visible=not combat or phase in ["result","finished","error"]
	report_button.visible=phase!="battle" or not tactical
	start_button.position=Vector2(1108,76) if combat and phase=="battle" else Vector2(1034,636)
	start_button.size=Vector2(144,34) if combat and phase=="battle" else Vector2(212,48)
	notice.position=Vector2(24,114) if combat else Vector2(136,723)
	for index in range(bench.size()):
		bench[index].position=Vector2(99+index*98,610 if tactical else 659);bench[index].size=Vector2(92,92 if tactical else 40)
	_bench_label.position.y=642 if tactical else 666
	if mobile_ui:_apply_mobile_layout(phase)

func _apply_mobile_layout(phase:String)->void:
	if not is_instance_valid(tactical_hud):return
	var width:float=maxf(1280.0,get_viewport().get_visible_rect().size.x)
	var extra:float=width-1280.0
	var combat:bool=phase in ["battle","result","finished","error"]
	_top_panel.size.x=width;_shop_panel.size.x=width-28
	_sidebar_panel.position.x=1016+extra
	for control in [normal_target_selector,detail_scroll,deploy_button,standings,report_button]:control.position.x=1034+extra
	sell_button.position.x=1143+extra
	start_button.position.x=(1108 if combat and phase=="battle" else 1034)+extra
	for control in [shop_lock_button,refresh_button,xp_button]:control.position.x=990+extra
	menu_button.position.x=1050+extra;metrics.position.x=1170+extra
	economy.size.x=730+extra
	status.size.x=width-390 if combat else width-310
	for index in range(shop.size()):
		shop[index].position.x=30+index*187+extra*0.5
		shop_preview_buttons[index].position.x=120+index*187+extra*0.5
	for index in range(bench.size()):bench[index].position.x=99+index*98+extra*0.5
	_shop_label.position.x=30+extra*0.5;_bench_label.position.x=24+extra*0.5
	shop_odds_label.position.x=136+extra*0.5
	if not combat:notice.position.x=136+extra*0.5
	report_panel.position.x=96+extra*0.5
	stage.set_mobile_layout(width,combat)
	tactical_hud.size.x=width-28
	tactical_hud.instructions.text="点选／拖动角色走位\n点EX后点目标，或拖EX释放"
	for index in range(tactical_hud.buttons.size()):tactical_hud.buttons[index].position.x=254+index*162+extra*0.5
	tactical_hud.hint_text.size.x=width-310
	if is_instance_valid(mobile_cancel_button):
		mobile_cancel_button.position=Vector2(width-340,76)
		mobile_cancel_button.visible=phase=="battle"
		mobile_cancel_button.disabled=tactical_input.armed_actor<0 and not mobile_gestures.is_pending()
func _cancel_mobile_aim()->void:
	mobile_gestures.cancel();tactical_input.cancel();stage.show_deployment_marker(null,false);_refresh_tactical_hud()
func _mobile_ex_gui(event:InputEvent,slot:int)->void:
	if not mobile_ui or session.phase()!="battle" or session.paused or mobile_gestures.is_pending():return
	if slot<0 or slot>=tactical_hud.buttons.size() or tactical_hud.buttons[slot].disabled:return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		if not _arm_tactical_slot(slot):return
		if tactical_input.armed_actor>=0:mobile_gestures.begin("ex",slot,event.global_position,session.clock.generation)
func _handle_mobile_event(event:InputEvent)->bool:
	if event is InputEventMouseButton and event.canceled:
		_cancel_bench_drag();_cancel_mobile_aim();stage.dragging=false;return false
	if session.phase()!="battle" or session.clock.sim.phase!="running" or session.paused or warming or game_menu.visible or report_panel.visible or recruitment_preview.visible or reinforcement_panel.visible:
		mobile_gestures.cancel();return false
	if event is InputEventMouseMotion and mobile_gestures.is_pending():
		mobile_gestures.update(event.position)
		if mobile_gestures.is_dragging():stage.show_deployment_marker(stage._mouse_ground(event.position),true)
		return true
	if not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT:return false
	if not event.pressed and mobile_gestures.is_pending():
		var before:Dictionary=mobile_gestures.snapshot()
		var request:Dictionary=mobile_gestures.finish(event.position,stage.field_input_rect.has_point(event.position),session.clock.generation)
		stage.show_deployment_marker(null,false)
		if request.is_empty():
			if before.kind=="ex":tactical_input.cancel()
			_refresh_tactical_hud();return before.kind!="ex"
		if request.action=="arm":_arm_tactical_slot(request.identity)
		elif request.action=="move" or request.action=="cast":
			if request.action=="cast":
				if not _arm_tactical_slot(request.identity):tactical_input.cancel();return false
			else:tactical_input.selected_actor=request.identity
			var synthetic:=InputEventMouseButton.new();synthetic.pressed=true;synthetic.position=request.screen
			synthetic.button_index=MOUSE_BUTTON_LEFT if request.action=="cast" else MOUSE_BUTTON_RIGHT
			_handle_tactical_event(synthetic,{},false)
		return before.kind!="ex"
	if event.pressed and tactical_input.armed_actor<0 and stage.field_input_rect.has_point(event.position):
		for control in [menu_button,start_button,mobile_cancel_button]:
			if is_instance_valid(control) and control.visible and control.get_global_rect().has_point(event.position):return false
		var context:Dictionary=_tactical_context(event.position)
		var actor=session.clock.sim._unit(context.picked_actor)
		if actor!=null and actor.team==0 and actor.hp>0:
			_handle_tactical_event(event,context)
			mobile_gestures.begin("actor",actor.id,event.position,session.clock.generation);return true
	return false
func _suspend_mobile()->void:
	if _mobile_suspended:return
	_mobile_suspended=true;_mobile_resume_paused=session.paused;session.paused=true
	_cancel_bench_drag();_cancel_mobile_aim()
	if persistence_enabled and _checkpoint_dirty and session.phase() in ["preparation","result","finished"]:_save_checkpoint(false)
func _resume_mobile()->void:
	if not _mobile_suspended:return
	_mobile_suspended=false;session.paused=_mobile_resume_paused or game_menu.visible

func _sync_round_result()->void:
	if not is_instance_valid(round_result_panel):return
	if session.phase() not in ["result","finished"] or session.match_format()!="six_round_league":round_result_panel.hide();return
	var snapshot:Dictionary=session.rules.snapshot();snapshot["standings"]=session.rules.league.standings()
	round_result_panel.present(snapshot,session.battle_feedback())
	_cancel_bench_drag();tactical_input.cancel();mobile_gestures.cancel()
func _next_result_round()->void:
	if session.phase()!="result":return
	var result:Dictionary=act({"type":"next_round"})
	if not result.ok:round_result_panel.release_action()
func request_return_to_title()->void:
	if not managed_startup or _return_pending:return
	_return_pending=true;_return_was_paused=session.paused;session.paused=true
	_cancel_bench_drag();tactical_input.cancel();mobile_gestures.cancel()
	if session.phase()=="battle":
		_show_return_dialog("返回后将结束当前战斗；继续游戏会回到开战前的准备阶段。是否返回？",false);return
	confirm_return_to_title()
func _show_return_dialog(message:String,discard:bool)->void:
	_return_discard_allowed=discard;return_dialog.dialog_text=message;return_dialog.ok_button_text="放弃未保存进度并返回" if discard else "返回主菜单"
	if DisplayServer.get_name()=="headless":return_dialog.show()
	else:return_dialog.popup_centered(Vector2i(550,200))
func confirm_return_to_title(discard_unsaved:bool=false)->void:
	if not managed_startup or not _return_pending:return
	if discard_unsaved and not _return_discard_allowed:return
	if not discard_unsaved and persistence_enabled:
		var saved:Dictionary
		if session.phase()=="battle":
			saved=SaveStore.read_save(save_path)
			if _checkpoint_dirty or _prebattle_checkpoint_hash.is_empty():saved={"ok":false,"error":"本场开战前进度未能保存"}
			elif saved.ok and FileAccess.get_sha256(str(saved.source_path))!=_prebattle_checkpoint_hash:saved={"ok":false,"error":"开战前存档已变更"}
			if saved.ok:
				var check=Session.new();var restored:Dictionary=check.restore_save(saved.data)
				saved={"ok":restored.ok and check.seed==session.seed and check.phase()=="preparation" and check.rules.snapshot().round==session.rules.snapshot().round,"error":"开战前存档不可用"}
		else:saved=_save_checkpoint(false)
		if not saved.ok:
			_show_return_dialog("进度未能保存，返回会丢失尚未保存的操作。可以留在游戏重试，或明确放弃后返回。",true);return
	return_dialog.hide();game_menu.hide();report_panel.hide();reinforcement_panel.hide();_dismiss_recruitment_preview()
	session._cancel_ai_jobs();combat_audio.reset(session.clock.generation);ordinary_audio.reset(session.clock.generation)
	set_process(false)
	if _return_restart:new_game_requested.emit()
	else:return_to_title_requested.emit()
func _cancel_return_to_title()->void:
	return_dialog.hide();session.paused=_return_was_paused;_return_pending=false;_return_discard_allowed=false;_return_restart=false
	if is_instance_valid(round_result_panel):round_result_panel.release_action()
