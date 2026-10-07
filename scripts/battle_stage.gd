extends Node3D
signal ordinary_audio_state(record:Dictionary)
signal selected(unit_id:int)
signal inspected(unit_id:int)
signal tactical_actor_pressed(unit_id:int)
signal placement_requested(unit_id:int,point:Vector2)
const StatusStrip=preload("res://scripts/combat_status_strip.gd")
const OverlayLayout=preload("res://core/status_overlay_layout.gd")
var field_input_rect:=Rect2(0,65,1000,585)
var _status_bounds:Rect2=STATUS_BOUNDS
var _wide_layout:=false
var _placement_marker:MeshInstance3D
var _overlay_layout=OverlayLayout.new()
const STATUS_OFFSET=Vector2(-16,-70)
const STATUS_SIZE=Vector2(92,75)
const STATUS_BOUNDS=Rect2(8,112,984,530)
const STATUS_LAYOUT_INTERVAL:=0.1
var local_team:int=0
var inspection_id:=-1
var _status_layout_rects:Dictionary={}
var _status_layout_anchors:Dictionary={}
var _status_layout_time:=-INF
var _status_layout_from_offsets:Dictionary={}
var _status_display_time:=-INF
var _status_layout_priority:=-1
var _status_layout_viewport:=Vector2.ZERO
var status_definitions:Dictionary={}
const UnitView=preload("res://scripts/unit_view.gd")
const ArenaEnvironment=preload("res://scripts/arena_environment.gd")
const CombatVFX=preload("res://scripts/native_combat_vfx.gd")
var native_vfx:Node3D
const SkillProps=preload("res://scripts/native_skill_props.gd")
var native_props:Node3D
const GroundMines=preload("res://scripts/native_ground_mines.gd")
var native_mines:Node3D
var views:Dictionary={}
var bars:Dictionary={}
var profiles:Dictionary={}
# Frozen setup inputs, not references into mutable roster/profile dictionaries.
var _view_setups:Dictionary={}
var dead_at:Dictionary={}
var units:Array=[]
var seen:Dictionary={}
var camera:Camera3D
var hud:CanvasLayer
var terrain:Node3D
var arena_half_size:=6.6
var _terrain_signature:=""
var preparation:=true
var tactical_input_enabled:=false
var selected_id:=-1
var dragging:=false
var generation:=0
var camera_focus:=Vector3(0,0.2,0)
var camera_time:=0.0
var _pose_time:=0.0
# Frozen current-frame camera state, consumed only by explicitly opted-in VFX.
var _stretch_camera_frame:Dictionary={}
var _attack_telegraphs:Node3D
func _ready()->void:
	_build_world()
	hud=CanvasLayer.new();add_child(hud)
	native_vfx=CombatVFX.new();add_child(native_vfx)
	native_props=SkillProps.new();add_child(native_props)
	native_mines=GroundMines.new();add_child(native_mines)
func configure(character_profiles:Dictionary,obstacles:Array)->void:
	profiles=character_profiles
	_view_setups.clear()
	status_definitions.clear()
	var definitions=preload("res://core/character_sim.gd").new()
	for key in profiles:status_definitions[key]=definitions.character_data(key)
	native_vfx.configure(profiles)
	native_props.configure(profiles)
	native_mines.configure(profiles)
	terrain.configure(obstacles)
func configure_arena(config:Dictionary)->void:
	var signature:String=str(config.get("id","legacy"))+str(config.half_size)+str(config.obstacles)
	if signature==_terrain_signature:return
	_terrain_signature=signature;arena_half_size=float(config.half_size)
	terrain.configure(config.obstacles,arena_half_size)
	if preparation:camera.size=16.0*arena_half_size/6.6
func _build_world()->void:
	var world:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("cad7e0");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("dfeaf0");env.ambient_light_energy=0.6;world.environment=env;add_child(world)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-48,-30,0);light.light_energy=0.8;light.shadow_enabled=false;add_child(light)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=16.0;camera.position=Vector3(-11,8,14);camera.near=0.05;add_child(camera);camera.look_at(Vector3(0,0.2,0));camera.h_offset=2.35;camera.v_offset=-1.1;camera.current=true
	terrain=ArenaEnvironment.new();add_child(terrain)
func set_roster(roster:Array,new_generation:int,is_preparation:bool)->void:
	# Only untouched preparation actors may survive. Battle/replay/generation
	# boundaries retain the full reset contract, including every event consumer.
	var reuse:bool=preparation and is_preparation and generation==new_generation and seen.is_empty() and dead_at.is_empty()
	var next_setups:Dictionary={}
	for unit in roster:next_setups[unit.id]=_view_setup(unit)
	for id in views.keys():
		if not reuse or not next_setups.has(id) or not _can_reuse_preparation_view(id,next_setups[id]):
			remove_child(views[id]);views[id].queue_free();views.erase(id)
			hud.remove_child(bars[id].root);bars[id].root.queue_free();bars.erase(id)
	dead_at.clear();seen.clear();selected_id=-1;inspection_id=-1;_status_layout_rects.clear();_status_layout_anchors.clear();_status_layout_from_offsets.clear();_status_layout_time=-INF;_status_display_time=-INF;generation=new_generation;preparation=is_preparation;units=roster.duplicate(true)
	for unit in units:
		if not views.has(unit.id):
			_create_roster_entry(unit)
		else:
			# update_time resets its logical clock, but native animation advance is
			# forward-only. Seek the unchanged idle clip to its original pose too.
			var view=views[unit.id]
			view.visible=true;view.rotation.y=0.0 if unit.team==0 else PI
			if is_instance_valid(view.animation_player) and view.animation_player.current_animation_position!=0.0:view.animation_player.seek(0.0,true)
			var reset_unit:Dictionary=unit.duplicate()
			reset_unit.shield=unit.get("shield",0);reset_unit.shield_until=unit.get("shield_until",0);reset_unit.aimed=unit.get("aimed",false)
			view.update_time(0.0,reset_unit)
		_update_roster_caption(unit)
	_view_setups=next_setups
	if preparation:native_vfx.reset(generation);native_props.reset(generation)
	else:native_vfx.begin_roster(views,units,generation);native_props.begin_roster(views,units,generation)
	native_mines.reset(generation)
	camera_time=0.0;_pose_time=0.0;_stretch_camera_frame.clear()
	if is_instance_valid(_attack_telegraphs):_attack_telegraphs.reset()
	if preparation:
		camera_focus=Vector3(0,0.2,0);camera.position=camera_focus+Vector3(-11 if local_team==0 else 11,7.8,14 if local_team==0 else -14);camera.look_at(camera_focus);camera.size=16.0*arena_half_size/6.6;camera.h_offset=0.0 if _wide_layout else camera.size*132.0/900.0;camera.v_offset=-camera.size*52.0/900.0-0.18
	if not preparation and local_team==1:
		camera.position=camera_focus+Vector3(11,7.8,-14);camera.look_at(camera_focus)
	_update_actors(0.0)
func _view_setup(unit:Dictionary)->Dictionary:
	# Range and attack cadence are setup-only UnitView inputs. Other combat
	# stats/positions are refreshed from the current snapshot by _update_actors.
	return {"character_id":unit.character_id,"star":unit.star,"team":unit.team,
		"roster_unit_id":unit.get("roster_unit_id",null),"range":unit.range,
		"attack_ticks":unit.get("attack_ticks",20),
		"presentation":profiles.get(unit.character_id,unit.get("presentation",{})).duplicate(true)}
func _can_reuse_preparation_view(id:int,setup:Dictionary)->bool:
	if not _view_setups.has(id) or _view_setups[id]!=setup:return false
	var view=views[id]
	# A direct presentation event or a snapshot-driven ready/idle transition
	# also requires fresh playback state; never try to rewind an action in place.
	return is_instance_valid(view) and not view.is_queued_for_deletion() and view.actor_id==id and view.generation==generation and not view.is_dead and not view.is_moving and view.state=="idle" and view._seen_events.is_empty() and view._clip_started_at==0.0
func _create_roster_entry(unit:Dictionary)->void:
	var shown:Dictionary=unit.duplicate(true);shown.presentation=profiles.get(unit.character_id,unit.get("presentation",{}))
	var view=UnitView.new()
	view.ordinary_audio_state.connect(func(record:Dictionary):ordinary_audio_state.emit(record))
	view.local_team=local_team
	add_child(view);view.setup(shown,{},generation);views[unit.id]=view
	var root:=Control.new();root.mouse_filter=Control.MOUSE_FILTER_IGNORE;hud.add_child(root)
	var name_label:=Label.new();name_label.position=Vector2(-12,-70);name_label.size.x=84;name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;name_label.add_theme_font_size_override("font_size",11);name_label.add_theme_color_override("font_color",Color("263d51"));root.add_child(name_label)
	name_label.mouse_filter=Control.MOUSE_FILTER_PASS
	var hp_bg:=ColorRect.new();hp_bg.size=Vector2(60,5);hp_bg.color=Color("506070");hp_bg.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(hp_bg)
	var hp:=ColorRect.new();hp.size=Vector2(60,5);hp.color=Color("3aaadc") if unit.team==local_team else Color("e47891");hp.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(hp)
	var status_strip=StatusStrip.new();root.add_child(status_strip);status_strip.position=Vector2(-16,-49)
	var leader:=Line2D.new();leader.width=1.0;leader.default_color=Color(0.18,0.3,0.4,0.38);leader.show_behind_parent=true;leader.antialiased=true;root.add_child(leader)
	var hit:=Control.new();hit.position=STATUS_OFFSET;hit.size=STATUS_SIZE;hit.mouse_filter=Control.MOUSE_FILTER_STOP;root.add_child(hit)
	hit.gui_input.connect(func(event:InputEvent):_status_input(event,int(unit.id),hit))
	bars[unit.id]={"root":root,"hp":hp,"label":name_label,"status":status_strip,"leader":leader,"hit":hit}
func _update_roster_caption(unit:Dictionary)->void:
	var name_label:Label=bars[unit.id].label
	var display_name:String=profiles.get(unit.character_id,{}).get("display_name",unit.character_id)
	name_label.text=display_name+(" ★★" if unit.star==2 else "")
	var types:Dictionary={"Explosion":"爆发","Pierce":"贯穿","Mystic":"神秘","Sonic":"振动","LightArmor":"轻装甲","HeavyArmor":"重装甲","Unarmed":"特殊装甲","ElasticArmor":"弹性装甲"}
	name_label.tooltip_text="%s\n武器 %s · 攻击 %s · 防御 %s"%[display_name,str(unit.get("weapon","")),types.get(str(unit.get("damage_type","")),str(unit.get("damage_type",""))),types.get(str(unit.get("armor_type","")),str(unit.get("armor_type","")))]
func set_selected(id:int)->void:
	selected_id=id if preparation or tactical_input_enabled else -1
	for unit_id in views:views[unit_id].set_selected((preparation or tactical_input_enabled) and unit_id==selected_id)
func update_display(snapshot_units:Array,events:Array,battle_time:float,simulation_tick:int=-1)->void:
	units=snapshot_units
	for event in events:
		if event.get("generation",generation)!=generation:continue
		# Legacy untagged events must not hide a later authoritative same-ID event.
		var key:String=str(generation)+":"+("tagged:" if event.has("generation") else "untagged:")+str(event.event_id)
		if seen.has(key):continue
		seen[key]=true
		var at:float=float(event.get("tick",0))*0.05
		# Only authoritative, in-order events have a reconstructable visual pose.
		# Standalone/late consumer calls retain the existing sampled fallback.
		var event_pose:bool=event.get("generation",-1)==generation and at>=_pose_time-0.0000001 and at<=battle_time+0.0000001
		var affected:Array=[]
		for id in [event.get("actor_id",-1),event.get("target_id",-1)]:
			if views.has(id) and not affected.has(id):affected.append(id)
		if event_pose:
			for id in affected:views[id].advance_event_time(at)
			native_vfx.capture_event_pose(at,affected)
			native_props.capture_event_pose(at,affected)
		if event.type=="knockback" and views.has(event.get("target_id",-1)):
			var displacement:Dictionary=event.duplicate(true);displacement.type="displacement";displacement.actor_id=event.target_id
			views[event.target_id].consume(displacement)
		if views.has(event.get("actor_id",-1)):
			# EX-driven reload should not replace its native EX clip.
			if not(event.type=="reload" and event.get("via_ex",false)):views[event.actor_id].consume(event)
		if event.type=="death":dead_at[event.actor_id]=float(event.tick)*0.05
		if event_pose:
			for id in affected:views[id].advance_event_time(at)
			native_vfx.capture_event_pose(at,affected)
			native_props.capture_event_pose(at,affected)
			_pose_time=at
		native_vfx.consume(event,units,event_pose)
		native_props.consume(event,units)
		if event.get("generation",-1)==generation:native_mines.consume(event,units)
	_update_camera(battle_time)
	_stretch_camera_frame=_capture_stretch_camera(battle_time)
	if is_instance_valid(native_vfx) and is_instance_valid(native_vfx._player):
		native_vfx._player.stretch_camera_at=_resolve_stretch_camera
	_update_actors(battle_time,simulation_tick)
	_pose_time=maxf(_pose_time,battle_time)
	native_vfx.update_time(battle_time)
	native_props.update_time(battle_time)
	native_mines.update_time(battle_time)

func _capture_stretch_camera(at:float)->Dictionary:
	if not is_finite(at) or not is_instance_valid(camera):return {}
	var projection:String=""
	if camera.projection==Camera3D.PROJECTION_ORTHOGONAL:projection="orthographic"
	elif camera.projection==Camera3D.PROJECTION_PERSPECTIVE:projection="perspective"
	else:return {} # Off-center frustum semantics require their own verified treatment.
	# Include the camera's h/v offsets rather than just the owning node transform.
	var transform:Transform3D=camera.get_camera_transform()
	if not transform.is_finite():return {}
	return {"time":at,"transform":transform,"projection":projection}

func _resolve_stretch_camera(at:float)->Dictionary:
	if not is_finite(at) or _stretch_camera_frame.get("time")!=at:return {}
	return _stretch_camera_frame.duplicate()

func _update_camera(at:float)->void:
	var delta:=maxf(0.0,at-camera_time);camera_time=at
	if preparation or delta==0:return
	var min_world:=Vector2(INF,INF);var max_world:=Vector2(-INF,-INF)
	var min_screen:=Vector2(INF,INF);var max_screen:=Vector2(-INF,-INF);var count:=0
	for unit in units:
		if unit.hp<=0:continue
		count+=1;min_world=min_world.min(unit.cell);max_world=max_world.max(unit.cell)
		var point:=Vector3(unit.cell.x,0,unit.cell.y)
		var projected:=Vector2(camera.global_basis.x.dot(point),camera.global_basis.y.dot(point))
		min_screen=min_screen.min(projected);max_screen=max_screen.max(projected)
	if count==0:return
	var middle:Vector2=(min_world+max_world)*0.5
	var span:=max_screen-min_screen
	var target_size:=clampf(maxf((span.x+2.4)*900.0/(1264.0 if _wide_layout else 980.0),(span.y+2.8)*900.0/510.0),11.8,16.0*arena_half_size/6.6)
	var blend:=1.0-exp(-delta*2.5)
	camera_focus=camera_focus.lerp(Vector3(middle.x,0.2,middle.y),blend)
	camera.size=lerpf(camera.size,target_size,blend)
	camera.position=camera_focus+Vector3(-11 if local_team==0 else 11,7.8,14 if local_team==0 else -14);camera.look_at(camera_focus)
	camera.h_offset=0.0 if _wide_layout else camera.size*132.0/900.0;camera.v_offset=-camera.size*52.0/900.0-0.18

func _update_actors(at:float,simulation_tick:int=-1)->void:
	# Cosmetic animation may continue after combat ends; status never advances
	# past the authoritative simulation. Time-only preview callers retain fallback.
	var status_tick:int=simulation_tick if simulation_tick>=0 else int(floor(at/0.05+0.000001))
	var anchors:Dictionary={}
	for unit in units:
		if not views.has(unit.id):continue
		var view=views[unit.id];view.update_time(at,unit);view.set_selected((preparation or tactical_input_enabled) and selected_id==unit.id)
		if dead_at.has(unit.id) and at-float(dead_at[unit.id])>3.0:view.visible=false
		var bar:Dictionary=bars[unit.id];bar.root.visible=unit.hp>0;bar.hp.size.x=60.0*clampf(float(unit.hp)/maxf(float(unit.max_hp),1.0),0.0,1.0)
		bar.status.update_unit(unit,status_tick,status_definitions.get(unit.character_id,{}),preparation)
		var hint:String=bar.label.tooltip_text+"\n"+bar.status.tooltip_text
		if bar.hit.tooltip_text!=hint:bar.hit.tooltip_text=hint
		if unit.hp>0:anchors[unit.id]=camera.unproject_position(view.global_position+Vector3(0,1.65,0))-Vector2(30,0)
	_layout_status_overlays(anchors,at)
func _unhandled_input(event:InputEvent)->void:
	if tactical_input_enabled and not preparation:return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if not event.pressed:dragging=false;return
		var point=_mouse_ground(event.position)
		if point==null:return
		var picked:=-1;var nearest:=0.65
		for unit in units:
			if int(unit.get("hp",1))<=0:continue
			var distance:float=point.distance_to(unit.cell)
			if distance<nearest:nearest=distance;picked=unit.id
		if picked>=0:
			var ally:bool=false
			for unit in units:
				if unit.id==picked:ally=unit.team==0;break
			if not preparation or not ally:
				dragging=false;set_selected(-1);inspected.emit(picked);return
			set_selected(picked);selected.emit(picked);dragging=true
		elif preparation and selected_id>=0:placement_requested.emit(selected_id,point)
	elif preparation and event is InputEventMouseMotion and dragging and selected_id>=0:
		var point=_mouse_ground(event.position)
		if point!=null:placement_requested.emit(selected_id,point)
func _mouse_ground(event_position:Variant=null):
	# Window-bound input can carry a valid position without moving the OS pointer.
	var mouse:Vector2=get_viewport().get_mouse_position() if event_position==null else event_position
	if not field_input_rect.has_point(mouse):return null
	var origin:=camera.project_ray_origin(mouse);var direction:=camera.project_ray_normal(mouse)
	if absf(direction.y)<0.001:return null
	var hit:=origin+direction*(-origin.y/direction.y);return Vector2(hit.x,hit.z)

func _layout_status_overlays(anchors:Dictionary,at:float)->void:
	var priority:int=inspection_id if anchors.has(inspection_id) else selected_id
	var viewport:Vector2=get_viewport().get_visible_rect().size
	var ids:Array=anchors.keys();ids.sort()
	var old_ids:Array=_status_layout_rects.keys();old_ids.sort()
	var structural:bool=ids!=old_ids or priority!=_status_layout_priority or viewport!=_status_layout_viewport or at<_status_display_time
	if structural or (anchors!=_status_layout_anchors and at-_status_layout_time>=STATUS_LAYOUT_INTERVAL-0.000001):
		var previous_offsets:Dictionary={}
		if not structural:
			for id in ids:previous_offsets[id]=_status_tracking_offset(id,at)
		var items:Array=[]
		for id in ids:
			var item:Dictionary={"id":id,"rect":Rect2(anchors[id]+STATUS_OFFSET,STATUS_SIZE)}
			if not structural and _status_layout_rects.has(id) and _status_layout_anchors.has(id):
				var previous:Rect2=_status_layout_rects[id]
				item.preferred=Rect2(previous.position+anchors[id]-_status_layout_anchors[id],previous.size)
			items.append(item)
		_status_layout_rects=_overlay_layout.arrange(items,_status_bounds,priority)
		_status_layout_anchors=anchors.duplicate();_status_layout_time=at;_status_layout_priority=priority;_status_layout_viewport=viewport
		_status_layout_from_offsets.clear()
		for id in ids:
			_status_layout_from_offsets[id]=_status_layout_rects[id].position-anchors[id]-STATUS_OFFSET if structural else previous_offsets[id]
	# Actor/camera anchors already move each visual frame. Track those directly;
	# only a changed collision offset eases over one solver interval. Absolute
	# battle time keeps paused/repeated calls and frame partitioning consistent.
	var rendered:Dictionary={}
	for id in ids:rendered[id]=Rect2(anchors[id]+STATUS_OFFSET+_status_tracking_offset(id,at),STATUS_SIZE)
	# A safe pair of endpoint layouts can still cross during interpolation.
	# Only conflicting HUDs fall back; unrelated labels keep frame-rate tracking.
	if not _status_tracking_is_safe(rendered,ids):_settle_status_tracking(rendered,ids)
	_status_display_time=at
	for id in ids:
		var bar:Dictionary=bars[id]
		bar.root.position=rendered[id].position-STATUS_OFFSET
		var source:Vector2=anchors[id]+Vector2(30,0)-bar.root.position
		bar.leader.points=PackedVector2Array([Vector2(30,0),source])
		bar.leader.visible=source.distance_to(Vector2(30,0))>4.0

func _status_tracking_offset(id:int,at:float)->Vector2:
	var target:Vector2=_status_layout_rects[id].position-_status_layout_anchors[id]-STATUS_OFFSET
	var blend:float=clampf((at-_status_layout_time)/STATUS_LAYOUT_INTERVAL,0.0,1.0)
	return _status_layout_from_offsets[id].lerp(target,blend)

func _status_tracking_is_safe(rects:Dictionary,ids:Array)->bool:
	for i in ids.size():
		var rect:Rect2=rects[ids[i]]
		if not _status_bounds.encloses(rect):return false
		for j in range(i+1,ids.size()):
			if rect.intersects(rects[ids[j]]):return false
	return true

func _settle_status_tracking(rects:Dictionary,ids:Array)->void:
	var fallback_ids:Dictionary={}
	for i in ids.size():
		var id:int=ids[i]
		if not _status_bounds.encloses(rects[id]):fallback_ids[id]=true
		for j in range(i+1,ids.size()):
			if rects[id].intersects(rects[ids[j]]):
				fallback_ids[id]=true;fallback_ids[ids[j]]=true
	var pending:Array=fallback_ids.keys()
	# Restoring a cached slot can collide with another moving HUD. Queue that
	# HUD too, but restore each ID at most once. Even a full-roster cascade is
	# O(n²), and converges to the existing solved layout without another search.
	while not pending.is_empty():
		var id:int=pending.pop_back()
		rects[id]=_status_layout_rects[id]
		for other in ids:
			if not fallback_ids.has(other) and rects[id].intersects(rects[other]):
				fallback_ids[other]=true;pending.append(other)

func _status_input(event:InputEvent,id:int,hit:Control)->void:
	if not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT or not event.pressed:return
	dragging=false
	for unit in units:
		if unit.id!=id or unit.hp<=0:continue
		if tactical_input_enabled and not preparation:tactical_actor_pressed.emit(id)
		elif preparation and unit.team==0:set_selected(id);selected.emit(id)
		else:set_selected(-1);inspected.emit(id)
		hit.accept_event();return

func set_reduce_smoke(enabled:bool)->void:
	native_vfx.set_reduce_smoke(enabled)
	native_props.set_reduce_smoke(enabled)

func update_attack_telegraphs(volumes:Array,at:float)->void:
	if not is_instance_valid(_attack_telegraphs):
		if volumes.is_empty() or preparation:return
		_attack_telegraphs=preload("res://scripts/attack_telegraphs.gd").new()
		add_child(_attack_telegraphs)
	_attack_telegraphs.local_team=local_team
	_attack_telegraphs.update_volumes([] if preparation else volumes,at)

func tactical_input_hit(screen_position:Vector2)->Dictionary:
	var point=_mouse_ground(screen_position)
	if point==null:return {"point":null,"picked_actor":-1}
	var picked:=-1;var nearest:=0.65;var screen_nearest:=40.0
	for unit in units:
		if unit.hp<=0:continue
		var distance:float=point.distance_to(unit.cell)
		if distance<nearest:nearest=distance;picked=unit.id
	for unit in units:
		if unit.hp<=0 or not views.has(unit.id):continue
		var center:Vector2=camera.unproject_position(views[unit.id].global_position+Vector3(0,0.85,0))
		var distance:float=center.distance_to(screen_position)
		if distance<screen_nearest:screen_nearest=distance;picked=unit.id
	return {"point":point,"picked_actor":picked}

func set_tactical_layout(tactical:bool,wide:bool)->void:
	var next_bounds:Rect2=Rect2(0,65,1280,640) if wide else Rect2(0,65,1000,540 if tactical else 585)
	if field_input_rect==next_bounds:return
	field_input_rect=next_bounds;_wide_layout=wide
	_status_bounds=Rect2(8,112,1264,550) if wide else Rect2(8,112,984,488) if tactical else STATUS_BOUNDS
	_status_layout_time=-INF
	camera.h_offset=0.0 if wide else camera.size*132.0/900.0
func show_deployment_marker(point:Variant,valid:bool)->void:
	if point==null:
		if is_instance_valid(_placement_marker):_placement_marker.hide()
		return
	if not is_instance_valid(_placement_marker):
		_placement_marker=MeshInstance3D.new();var ring:=TorusMesh.new();ring.inner_radius=0.31;ring.outer_radius=0.39;ring.rings=24;ring.ring_segments=8;_placement_marker.mesh=ring
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;_placement_marker.material_override=material;_placement_marker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(_placement_marker)
	_placement_marker.position=Vector3(point.x,0.035,point.y);_placement_marker.material_override.albedo_color=Color(0.1,0.75,1,0.8) if valid else Color(1,0.22,0.3,0.8);_placement_marker.show()

func set_mobile_layout(width:float,combat:bool)->void:
	var usable:float=maxf(1000.0,width if combat else width-280.0)
	field_input_rect=Rect2(0,65,usable,640 if combat else 540)
	_status_bounds=Rect2(8,112,usable-16,550 if combat else 488)
	_status_layout_time=-INF
