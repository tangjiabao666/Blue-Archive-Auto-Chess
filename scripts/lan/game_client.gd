extends Node3D
signal leave_requested
signal exit_requested
var settings_values:Dictionary={}
var _exit_after_leave:=false
var _combat_feedback:=''
var _feedback_until:=0
var _render_frames:Array=[]
var _render_events:Array=[]
var _render_event_sequence:=0
const PRESENTATION_DELAY_SECONDS:=0.1
const View=preload('res://core/lan/session_view.gd')
const Catalog=preload('res://core/game_session.gd')
const Stage=preload('res://scripts/battle_stage.gd')
var room:Node
var view=View.new()
var catalog=Catalog.new() # Definition/preview access only. Never starts or advances a match.
var stage:Node3D
var canvas:CanvasLayer
var header:Label
var info:Label
var notice:Label
var shops:Array=[]
var units_box:VBoxContainer
var ready_button:Button
var next_button:Button
var refresh_button:Button
var xp_button:Button
var lock_button:Button
var reinforcement_box:HBoxContainer
var combat_audio:Node
var ordinary_audio:Node
var selected_owned:=''
var selected_actor:=-1
var armed_actor:=-1
var _signature:=''
var _ui_signature:=''
var _loaded_round:=-1
var _visual_time:=0.0
var _last_battle:=''
var _unit_map:Dictionary={}
var _tail:=false
var tactical_hud:Control
var leave_dialog:ConfirmationDialog
var _bottom:Panel
var _side:Panel
var preview_panel:Control
func _ready()->void:
 stage=Stage.new();add_child(stage);stage.configure(catalog.profiles,Catalog.OBSTACLES)
 stage.selected.connect(func(id):selected_owned=_unit_map.get(id,''))
 stage.placement_requested.connect(func(id,point):_command({'type':'place_unit','unit_id':_unit_map.get(id,''),'point':point}))
 combat_audio=load('res://scripts/native_combat_audio.gd').new();combat_audio.output_enabled=DisplayServer.get_name()!='headless';add_child(combat_audio)
 ordinary_audio=load('res://scripts/ordinary_combat_audio.gd').new();ordinary_audio.output_enabled=DisplayServer.get_name()!='headless';add_child(ordinary_audio)
 stage.ordinary_audio_state.connect(func(record):ordinary_audio.consume_state(record))
 stage.tactical_actor_pressed.connect(_actor_pressed)
 stage.set_reduce_smoke(bool(settings_values.get('reduce_smoke',false)))
 canvas=CanvasLayer.new();add_child(canvas)
 var top:=Panel.new();top.position=Vector2(0,0);top.size=Vector2(1280,62);canvas.add_child(top)
 header=_label(top,Vector2(16,12),Vector2(1020,40),'局域网对局',22)
 var leave=_button(top,'离开房间',_ask_leave);leave.position=Vector2(1120,10);leave.size=Vector2(145,40)
 var side:=Panel.new();_side=side;side.position=Vector2(1005,70);side.size=Vector2(265,575);canvas.add_child(side)
 info=_label(side,Vector2(10,8),Vector2(245,165),'',17)
 var scroll:=ScrollContainer.new();scroll.position=Vector2(8,180);scroll.size=Vector2(250,380);side.add_child(scroll)
 units_box=VBoxContainer.new();units_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(units_box)
 var bottom:=Panel.new();_bottom=bottom;bottom.position=Vector2(10,655);bottom.size=Vector2(1260,235);canvas.add_child(bottom)
 notice=_label(bottom,Vector2(12,8),Vector2(1220,28),'拖动场上角色布阵；三人都准备后开战。',16)
 var shoprow:=HBoxContainer.new();shoprow.position=Vector2(12,45);bottom.add_child(shoprow)
 for i in range(5):
  var slot:int=i;var column:=VBoxContainer.new();shoprow.add_child(column)
  var button=_button(column,'招募',func():_command({'type':'buy_offer','slot':slot}));button.custom_minimum_size=Vector2(185,62);shops.append(button)
  _button(column,'技能详情',func():_preview(slot))
 var actions:=HBoxContainer.new();actions.position=Vector2(12,145);bottom.add_child(actions)
 refresh_button=_button(actions,'刷新 2 金',func():_command({'type':'refresh_shop'}))
 xp_button=_button(actions,'升级经验 4 金',func():_command({'type':'buy_xp'}))
 lock_button=_button(actions,'保留商店',func():_command({'type':'set_shop_locked','locked':not view.state.player.shop_locked}))
 ready_button=_button(actions,'准备',func():_command({'type':'ready','value':not view.state.ready[view.state.participant_id]}))
 next_button=_button(actions,'下一回合',func():room.request_next());next_button.hide()
 reinforcement_box=HBoxContainer.new();reinforcement_box.position=Vector2(12,195);bottom.add_child(reinforcement_box)
 preview_panel=load('res://scripts/recruitment_preview_panel.gd').new();canvas.add_child(preview_panel)
 preview_panel.closed.connect(func():preview_panel.hide())
 tactical_hud=load('res://scripts/tactical_hud.gd').new();canvas.add_child(tactical_hud)
 tactical_hud.slot_selected.connect(_arm_slot)
 leave_dialog=ConfirmationDialog.new();leave_dialog.title='离开联机对局';leave_dialog.ok_button_text='确认离开';leave_dialog.cancel_button_text='继续游戏';canvas.add_child(leave_dialog)
 leave_dialog.confirmed.connect(func():
  if _exit_after_leave:exit_requested.emit()
  else:leave_requested.emit())
func request_close()->void:
 _exit_after_leave=true;_ask_leave()
func _ask_leave()->void:
 leave_dialog.dialog_text='你是房主，离开会结束所有人的本局。' if room.is_host else '离开后由 AI 接管，本局不能重新接回控制。'
 leave_dialog.popup_centered(Vector2i(520,180))
 if not leave_dialog.canceled.is_connected(_cancel_leave):leave_dialog.canceled.connect(_cancel_leave)
func _cancel_leave()->void:_exit_after_leave=false
func _arm_slot(index:int)->void:
 var units:Array=view.state.get('battle',{}).get('units',[]).filter(func(u):return u.team==view.local_team())
 if index<units.size():armed_actor=units[index].id;notice.text='EX 已选中，请点击目标或地面。'
func bind_room(value:Node)->void:
 room=value;room.view_received.connect(_receive)
 room.command_ack.connect(func(result):
  if not result.ok:_show_feedback(str(result.get('error',''))))
 if not room.local_view.is_empty():_receive(room.local_view)
func _receive(state:Dictionary)->void:_apply_received(state)
func _apply_received(state:Dictionary)->void:
 if not view.accept(state,room.local_participant_id).ok:return
 if state.phase!='preparation':preview_panel.hide()
 _refresh()
func _command(command:Dictionary)->void:
 if room!=null:room.submit_command(command)
func _refresh()->void:
 var state:Dictionary=view.state;var player:Dictionary=state.player
 var phase:String=state.phase
 var waiting:bool=phase=='battle' and state.get('battle',{}).get('phase')=='finished'
 _bottom.visible=phase!='battle' or waiting
 _side.visible=phase!='battle' or waiting
 if phase!='battle':tactical_hud.hide()
 var prep:bool=phase=='preparation';var unlocked:bool=prep and not state.ready[state.participant_id]
 header.text='好友房 · 第 %d / 6 回合 · %s · %d 金币 · 人口 %d/%d'%[state.round,{'preparation':'备战','loading':'等待三端加载','battle':'战斗','result':'本轮结算','finished':'最终排名'}.get(phase,phase),player.gold,player.deployed.size(),player.level]
 var lines:Array[String]=[]
 for i in range(0,state.standings.size(),2):
  var left:Dictionary=state.standings[i];var right:Dictionary=state.standings[i+1] if i+1<state.standings.size() else {}
  lines.append('%s %d分   %s %d分'%[_participant_name(left.participant_id).left(5),left.points,_participant_name(right.get('participant_id','')).left(5),right.get('points',0)])
 info.text='你：'+_participant_name(state.participant_id)+'\n对手：'+_participant_name(state.opponent_id)+'\n'+ '\n'.join(lines)
 ready_button.visible=prep;ready_button.text='取消准备' if state.ready[state.participant_id] else '准备开战'
 next_button.visible=phase=='result'
 next_button.disabled=state.has('battle') and (_render_event_sequence<int(state.battle.get('event_sequence',0)) or _visual_time<state.battle.tick*0.05)
 for button in [refresh_button,xp_button,lock_button]:button.disabled=not unlocked
 lock_button.text='取消保留' if player.shop_locked else '保留商店'
 for i in range(shops.size()):
  var offer:Dictionary=player.shop[i];shops[i].disabled=not unlocked or offer.is_empty()
  shops[i].text='已招募' if offer.is_empty() else _name(offer.character_id)+'\n'+str(offer.cost)+' 金币'
  if not offer.is_empty():
   var path:String='res://assets/ui/portraits/'+offer.character_id+'.png'
   if ResourceLoader.exists(path):shops[i].icon=load(path);shops[i].expand_icon=true;shops[i].add_theme_constant_override('icon_max_width',52)
  else:shops[i].icon=null
 var ui_key:String=str(player.units)+str(player.deployed)+str(unlocked)+str(player.reinforcement)
 if ui_key!=_ui_signature:
  _ui_signature=ui_key
  for child in units_box.get_children():units_box.remove_child(child);child.queue_free()
  for unit in player.units:
   var id:String=unit.id
   var row:=VBoxContainer.new();units_box.add_child(row)
   var select=_button(row,_name(unit.character_id)+(' ★★' if unit.star==2 else ' ★')+(' · 场上' if id in player.deployed else ' · 备战'),func():selected_owned=id)
   select.disabled=not unlocked
   var actions:=HBoxContainer.new();row.add_child(actions)
   var deploy=_button(actions,'下阵' if id in player.deployed else '上阵',func():_command({'type':'bench_unit' if id in view.state.player.deployed else 'deploy_unit','unit_id':id}));deploy.disabled=not unlocked
   var sell=_button(actions,'出售',func():_command({'type':'sell_unit','unit_id':id}));sell.disabled=not unlocked
  for child in reinforcement_box.get_children():reinforcement_box.remove_child(child);child.queue_free()
  if player.reinforcement.get('status')=='pending':
   for i in range(player.reinforcement.offers.size()):
    var slot:int=i;var offer:Dictionary=player.reinforcement.offers[i]
    var b=_button(reinforcement_box,'增援 '+_name(offer.character_id),func():_command({'type':'claim_reinforcement','round':view.state.round,'slot':slot}));b.disabled=not unlocked
   var skip=_button(reinforcement_box,'跳过增援',func():_command({'type':'skip_reinforcement','round':view.state.round}));skip.disabled=not unlocked
 stage.configure_arena(state.arena)
 if prep:
  stage.local_team=0;_render_frames.clear();_render_events.clear();_render_event_sequence=0
  var roster:Array=[];_unit_map.clear()
  for unit in player.units:
   if unit.id not in player.deployed:continue
   var id:int=roster.size();var preview:Dictionary=catalog.clock.sim.preview_unit(unit.character_id,unit.star,id,0,state.positions[unit.id]);preview['roster_unit_id']=unit.id;roster.append(preview);_unit_map[id]=unit.id
  for unit in state.opponent_army:
   var id:int=7+roster.filter(func(u):return u.team==1).size();roster.append(catalog.clock.sim.preview_unit(unit.character_id,unit.star,id,1,-state.opponent_positions[unit.id]))
  var signature:String='prep'+str(state.round)+str(roster.map(func(u):return [u.id,u.character_id,u.star]))
  if signature!=_signature:_signature=signature;stage.set_roster(roster,state.round*10,true);_visual_time=0;combat_audio.reset(-1);ordinary_audio.reset(-1)
  stage.set_tactical_layout(true,false)
  stage.preparation=unlocked;stage.tactical_input_enabled=false;stage.update_display(roster,[],0,0)
 elif state.has('battle'):
  var battle:Dictionary=state.battle
  stage.local_team=view.local_team()
  var signature:String=battle.battle_id
  if signature!=_signature:
   _signature=signature;stage.set_roster(battle.units,battle.generation,false);stage.set_tactical_layout(true,true);_visual_time=0;_tail=false;selected_actor=-1;armed_actor=-1
   _render_frames.clear();_render_events.clear();_render_event_sequence=0
   combat_audio.begin_roster(battle.units,battle.generation);ordinary_audio.begin_battle(battle.units,battle.generation,int(state.round))
  _render_events.append_array(view.drain_events())
  if _render_frames.is_empty() or int(_render_frames[-1].tick)<battle.tick:_render_frames.append(battle.duplicate(true))
  elif int(_render_frames[-1].tick)==battle.tick:_render_frames[-1]=battle.duplicate(true)
  while _render_frames.size()>64:
   var expired:Dictionary=_render_frames.pop_front();_visual_time=maxf(_visual_time,expired.tick*0.05)
  stage.tactical_input_enabled=phase=='battle' and battle.phase=='running'
  if phase=='battle':
   _refresh_hud(battle)
  if phase=='battle':header.text+=' · %.1f/90秒'%minf(battle.tick*0.05,90.0)
  if phase=='battle':notice.text='%.1f / 90 秒 · 左键选己方，右键移动 · 1–5 选择 EX 后点击目标'%minf(battle.tick*0.05,90.0)
 if phase=='preparation':
  var ready_count:int=0
  for id in state.ready:
   if state.controllers[id]=='human' and state.ready[id]:ready_count+=1
  notice.text='真人已准备 %d/%d · 场上角色可拖动布阵 · 掉线席位由 AI 接管'%[ready_count,state.controllers.values().count('human')]
 if phase=='loading' and _loaded_round!=state.round:_loaded_round=state.round;call_deferred('_loaded',state.round)
 if waiting:header.text+=' · 本场结束，等待其他对局';notice.text='你的这场已结束，其他对局结束后统一结算。'
 if phase=='result':notice.text=_result_summary()+' · 三名真人点击“下一回合”后继续。'
 if phase=='finished':notice.text=_result_summary()+' · 六回合结束，最终排名见右侧。'
func _loaded(round_number:int)->void:
 if is_instance_valid(room) and view.state.get('phase')=='loading' and view.state.round==round_number:room.mark_loaded()
func _process(delta:float)->void:
 if view.state.is_empty() or not view.state.has('battle') or view.state.phase=='preparation' or _render_frames.is_empty():return
 var battle:Dictionary=view.state.battle
 var end:float=float(battle.tick)*0.05
 var limit:float=end+0.8 if battle.phase=='finished' else maxf(0,end-PRESENTATION_DELAY_SECONDS)
 # Continuous delayed cursor. Catch up gently after a burst; never predict
 # past the latest authoritative tick while the battle is running.
 var rate:float=clampf((limit-_visual_time)/0.15,1.0,2.0) if battle.phase!='finished' else 1.0
 _visual_time=minf(_visual_time+maxf(0,delta)*rate,maxf(_visual_time,limit))
 var events:Array=[]
 while not _render_events.is_empty() and float(_render_events[0].get('tick',0))*0.05<=_visual_time+0.000001:
  var event:Dictionary=_render_events.pop_front();events.append(event);_render_event_sequence=int(event.wire_sequence)
  combat_audio.consume(event);ordinary_audio.consume(event)
  if event.type=='command_rejected' and event.get('team',-1)==view.local_team():_show_feedback(str(event.get('error','操作未生效')))
 while _render_frames.size()>1 and float(_render_frames[1].tick)*0.05<=_visual_time:_render_frames.pop_front()
 var before:Dictionary=_render_frames[0]
 var shown:Array=before.units.duplicate(true)
 if _render_frames.size()>1:
  var after:Dictionary=_render_frames[1];var duration:float=(after.tick-before.tick)*0.05
  var fraction:float=clampf((_visual_time-before.tick*0.05)/maxf(0.05,duration),0,1)
  for unit in shown:
   for later in after.units:
    if later.id==unit.id:unit.cell=unit.cell.lerp(later.cell,fraction);break
 stage.update_attack_telegraphs(before.get('telegraphs',[]),_visual_time)
 stage.update_display(shown,events,_visual_time,mini(battle.tick,int(_visual_time/0.05)))
 if battle.phase=='finished' and _visual_time>=end and not _tail:
  combat_audio.begin_tail_drain(end,0.8);ordinary_audio.begin_tail_drain(end,0.8);_tail=true
 combat_audio.update_time(_visual_time);ordinary_audio.update_time(_visual_time)
 if view.state.phase=='result':next_button.disabled=_render_event_sequence<int(battle.get('event_sequence',0)) or _visual_time<end
func _select_actor(id:int)->void:
 if view.owns_actor(id):selected_actor=id;stage.set_selected(id)
func _unhandled_input(event:InputEvent)->void:
 if leave_dialog.visible or preview_panel.visible:return
 if view.state.get('phase')!='battle' or not stage.tactical_input_enabled:return
 if event is InputEventKey and event.pressed and not event.echo:
  if event.keycode==KEY_ESCAPE:armed_actor=-1;return
  if event.keycode>=KEY_1 and event.keycode<=KEY_5:
   var units:Array=view.state.battle.units.filter(func(u):return u.team==view.local_team())
   var index:int=event.keycode-KEY_1
   if index<units.size():armed_actor=units[index].id;notice.text='EX 已选中，请点击目标或地面。'
   return
 if not event is InputEventMouseButton or not event.pressed:return
 var hit:Dictionary=stage.tactical_input_hit(event.position)
 if not hit.point is Vector2:return
 if event.button_index==MOUSE_BUTTON_RIGHT and selected_actor>=0:_command({'type':'move','actor_id':selected_actor,'point':hit.point});get_viewport().set_input_as_handled()
 elif event.button_index==MOUSE_BUTTON_LEFT:
  if armed_actor>=0:
   _cast_at(hit.point,hit.picked_actor)
  else:_select_actor(hit.picked_actor)
  get_viewport().set_input_as_handled()
func _name(id:String)->String:return catalog.profiles.get(id,{}).get('display_name',id)
func _label(parent:Node,at:Vector2,extent:Vector2,text:String,size:int)->Label:
 if parent is Panel:_style_panel(parent)
 var label:=Label.new();label.position=at;label.size=extent;label.text=text;label.add_theme_font_size_override('font_size',size);label.add_theme_color_override('font_color',Color('244c66'));parent.add_child(label);return label
func _button(parent:Node,text:String,callback:Callable)->Button:
 var button:=Button.new();button.text=text
 for mode in ['normal','hover','pressed','disabled']:
  var style:=StyleBoxFlat.new();style.bg_color=Color('dfeef5') if mode=='normal' else Color('bfdfef') if mode!='disabled' else Color('e4e9ed');style.set_corner_radius_all(7);button.add_theme_stylebox_override(mode,style)
 for mode in ['font_color','font_hover_color','font_pressed_color','font_focus_color']:button.add_theme_color_override(mode,Color('244c66'))
 button.add_theme_color_override('font_disabled_color',Color('81949f'))
 button.custom_minimum_size=Vector2(100,35);parent.add_child(button);button.pressed.connect(callback);return button

func _refresh_hud(battle:Dictionary)->void:
 var team:int=view.local_team();var resources:Dictionary=battle.controls.resources
 var slots:Array=[]
 for unit in battle.units:
  if unit.team!=team:continue
  var ex:Dictionary=catalog.clock.sim.character_data(unit.character_id).ex
  slots.append({'actor_id':unit.id,'character_id':unit.character_id,'name':_name(unit.character_id),'hp':unit.hp,'star':unit.star,'cost':int(ex.originalCost),'cooldown':maxf(0,(resources.ready.get(str(team)+':'+str(unit.id),0)-battle.tick)*0.05)})
 var resource:Dictionary=resources.teams[team]
 tactical_hud.refresh({'active':battle.phase=='running','energy':resource.energy,'moves':resource.moves,'move_next':maxf(0,(resource.move_ready-battle.tick)*0.05),'slots':slots,'armed_actor':armed_actor,'hint':_combat_feedback if Time.get_ticks_msec()<_feedback_until else '%s · %.1f/90秒 · 断线后由 AI 接管'%[view.state.participant_id,battle.tick*0.05]})

func _preview(slot:int)->void:
 if view.state.get('phase')!='preparation':return
 var offer:Dictionary=view.state.player.shop[slot]
 if offer.is_empty():return
 var key:String=offer.character_id
 var data:Dictionary=load('res://core/recruitment_skill_presenter.gd').describe(catalog.clock.sim,key,_name(key),int(offer.cost),5.0)
 for skill in data.skills:
  if skill.slot=='ex':skill.text+='\n实时手动释放 · 共享能量与冷却以战斗面板为准'
 var path:String='res://assets/ui/portraits/'+key+'.png'
 if preview_panel.configure(data,load(path) if ResourceLoader.exists(path) else null):preview_panel.show()

func _actor_pressed(id:int)->void:
 if leave_dialog.visible or preview_panel.visible or view.state.get('phase')!='battle':return
 if armed_actor<0:_select_actor(id);return
 for unit in view.state.battle.units:
  if unit.id==id:_cast_at(unit.cell,id);return
func _cast_at(point:Vector2,target:int)->void:
 var actor:Dictionary={}
 for unit in view.state.battle.units:
  if unit.id==armed_actor:actor=unit;break
 if not actor.is_empty():
  var ex:Dictionary=catalog.clock.sim.character_data(actor.character_id).ex
  if ex.kind in ['self_barrier','reload_and_self_buff','self_defense_buff_and_aoe_taunt','self_buff']:target=armed_actor;point=actor.cell
  _command({'type':'cast_ex','actor_id':armed_actor,'point':point,'target_id':target})
 armed_actor=-1

func _style_panel(panel:Panel)->void:
 var style:=StyleBoxFlat.new();style.bg_color=Color('eef7fc');style.set_corner_radius_all(9);style.border_color=Color('95cbe3');style.set_border_width_all(1);panel.add_theme_stylebox_override('panel',style)

func _participant_name(id:String)->String:
 return str(view.state.get('names',{}).get(id,id))+('（AI）' if id in ['p1','p2'] and view.state.controllers.get(id)=='ai' else '')

func _show_feedback(reason:String)->void:
 var labels:Dictionary={'move_too_far':'走位目标太远，请选近一点的位置','no_move_charges':'战术移动次数不足，等待恢复','invalid_destination':'该位置无法落脚','occupied_destination':'目标位置被其他角色占据','unreachable_destination':'无法抵达该位置','already_at_destination':'角色已在目标位置','already_moving':'正在向该位置移动','destination_blocked':'目标位置被阻挡','invalid_enemy_target':'请选择存活的敌方目标','invalid_self_target':'此技能只对自身释放','invalid_direction':'请选择有效方向','energy_or_cooldown':'能量不足或技能冷却中','ex_locked':'升至二星后解锁 EX','actor_dead':'该角色已退场','actor_stunned':'角色被控制，暂时无法行动','ex_in_progress':'角色正在释放技能','invalid_target':'目标无效','target_out_of_range':'目标超出射程','target_obstructed':'障碍物挡住了目标','out_of_range':'目标超出射程','invalid_point':'该位置不可用','already_ready':'先取消准备才能操作','empty_army':'请先上阵至少一名角色','reinforcement_pending':'请先选择或跳过增援'}
 _combat_feedback='操作未生效：'+str(labels.get(reason,reason));_feedback_until=Time.get_ticks_msec()+3500;notice.text=_combat_feedback
 if is_instance_valid(tactical_hud) and tactical_hud.visible:tactical_hud.hint_text.text=_combat_feedback

func _result_summary()->String:
 var outcome:Dictionary=view.state.get('battle',{}).get('result',{}).get('outcome',{})
 if outcome.is_empty():return '本轮已结算'
 var team:int=view.local_team()
 var win:bool=outcome.winner==('left' if team==0 else 'right')
 var verdict:String='平局' if outcome.winner=='draw' else '本轮胜利' if win else '本轮失利'
 var hp:Array=outcome.get('remaining_hp_totals',[0,0])
 return '%s · 剩余总 HP %d : %d'%[verdict,hp[team],hp[1-team]]
