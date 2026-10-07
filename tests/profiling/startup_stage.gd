extends Node3D
signal selected(unit_id:int)
signal placement_requested(unit_id:int,point:Vector2)
const StatusStrip=preload("res://scripts/combat_status_strip.gd")
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
var preparation:=true
var selected_id:=-1
var dragging:=false
var generation:=0
var profile_last:Dictionary={}
var camera_focus:=Vector3(0,0.2,0)
var camera_time:=0.0
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
func _build_world()->void:
	var world:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("cad7e0");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("dfeaf0");env.ambient_light_energy=0.6;world.environment=env;add_child(world)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-48,-30,0);light.light_energy=0.8;light.shadow_enabled=false;add_child(light)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=16.0;camera.position=Vector3(-11,8,14);camera.near=0.05;add_child(camera);camera.look_at(Vector3(0,0.2,0));camera.h_offset=2.35;camera.v_offset=-1.1;camera.current=true
	terrain=ArenaEnvironment.new();add_child(terrain)
func set_roster(roster:Array,new_generation:int,is_preparation:bool)->void:
	var p_start:int=Time.get_ticks_usec()
	# Only untouched preparation actors may survive. Battle/replay/generation
	# boundaries retain the full reset contract, including every event consumer.
	var reuse:bool=preparation and is_preparation and generation==new_generation and seen.is_empty() and dead_at.is_empty()
	var next_setups:Dictionary={}
	for unit in roster:next_setups[unit.id]=_view_setup(unit)
	for id in views.keys():
		if not reuse or not next_setups.has(id) or not _can_reuse_preparation_view(id,next_setups[id]):
			remove_child(views[id]);views[id].queue_free();views.erase(id)
			hud.remove_child(bars[id].root);bars[id].root.queue_free();bars.erase(id)
	dead_at.clear();seen.clear();selected_id=-1;generation=new_generation;preparation=is_preparation;units=roster.duplicate(true)
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
	var p_actors:int=Time.get_ticks_usec()
	if preparation:native_vfx.reset(generation)
	else:native_vfx.begin_roster(views,units,generation)
	var p_vfx:int=Time.get_ticks_usec()
	if preparation:native_props.reset(generation)
	else:native_props.begin_roster(views,units,generation)
	var p_props:int=Time.get_ticks_usec()
	native_mines.reset(generation)
	camera_time=0.0
	if preparation:
		camera_focus=Vector3(0,0.2,0);camera.position=camera_focus+Vector3(-11,7.8,14);camera.look_at(camera_focus);camera.size=16.0;camera.h_offset=2.35;camera.v_offset=-1.1
	_update_actors(0.0)
	profile_last={"actors_us":p_actors-p_start,"vfx_us":p_vfx-p_actors,"props_us":p_props-p_vfx,"remaining_us":Time.get_ticks_usec()-p_props,"total_us":Time.get_ticks_usec()-p_start}
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
	var view=UnitView.new();add_child(view);view.setup(shown,{},generation);views[unit.id]=view
	var root:=Control.new();root.mouse_filter=Control.MOUSE_FILTER_IGNORE;hud.add_child(root)
	var name_label:=Label.new();name_label.position=Vector2(-12,-46);name_label.size.x=84;name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;name_label.add_theme_font_size_override("font_size",11);name_label.add_theme_color_override("font_color",Color("263d51"));root.add_child(name_label)
	name_label.mouse_filter=Control.MOUSE_FILTER_PASS
	var hp_bg:=ColorRect.new();hp_bg.size=Vector2(60,5);hp_bg.color=Color("506070");hp_bg.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(hp_bg)
	var hp:=ColorRect.new();hp.size=Vector2(60,5);hp.color=Color("3aaadc") if unit.team==0 else Color("e47891");hp.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(hp)
	var status_strip=StatusStrip.new();root.add_child(status_strip);status_strip.position=Vector2(-35,-29)
	bars[unit.id]={"root":root,"hp":hp,"label":name_label,"status":status_strip}
func _update_roster_caption(unit:Dictionary)->void:
	var name_label:Label=bars[unit.id].label
	var display_name:String=profiles.get(unit.character_id,{}).get("display_name",unit.character_id)
	name_label.text=display_name+(" ★★" if unit.star==2 else "")
	var types:Dictionary={"Explosion":"爆发","Pierce":"贯穿","Mystic":"神秘","Sonic":"振动","LightArmor":"轻装甲","HeavyArmor":"重装甲","Unarmed":"特殊装甲","ElasticArmor":"弹性装甲"}
	name_label.tooltip_text="%s\n武器 %s · 攻击 %s · 防御 %s"%[display_name,str(unit.get("weapon","")),types.get(str(unit.get("damage_type","")),str(unit.get("damage_type",""))),types.get(str(unit.get("armor_type","")),str(unit.get("armor_type","")))]
func set_selected(id:int)->void:
	selected_id=id if preparation else -1
	for unit_id in views:views[unit_id].set_selected(preparation and unit_id==selected_id)
func update_display(snapshot_units:Array,events:Array,battle_time:float,simulation_tick:int=-1)->void:
	units=snapshot_units
	for event in events:
		if event.get("generation",generation)!=generation:continue
		# Legacy untagged events must not hide a later authoritative same-ID event.
		var key:String=str(generation)+":"+("tagged:" if event.has("generation") else "untagged:")+str(event.event_id)
		if seen.has(key):continue
		seen[key]=true
		if event.type=="knockback" and views.has(event.get("target_id",-1)):
			var displacement:Dictionary=event.duplicate(true);displacement.type="displacement";displacement.actor_id=event.target_id
			views[event.target_id].consume(displacement)
		if views.has(event.get("actor_id",-1)):
			# EX-driven reload should not replace its native EX clip.
			if not(event.type=="reload" and event.get("via_ex",false)):views[event.actor_id].consume(event)
		if event.type=="death":dead_at[event.actor_id]=float(event.tick)*0.05
		native_vfx.consume(event,units)
		native_props.consume(event,units)
		if event.get("generation",-1)==generation:native_mines.consume(event,units)
	_update_camera(battle_time)
	_update_actors(battle_time,simulation_tick)
	native_vfx.update_time(battle_time)
	native_props.update_time(battle_time)
	native_mines.update_time(battle_time)

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
	var target_size:=clampf(maxf((span.x+2.4)*900.0/980.0,(span.y+2.8)*900.0/510.0),11.8,16.0)
	var blend:=1.0-exp(-delta*2.5)
	camera_focus=camera_focus.lerp(Vector3(middle.x,0.2,middle.y),blend)
	camera.size=lerpf(camera.size,target_size,blend)
	camera.position=camera_focus+Vector3(-11,7.8,14);camera.look_at(camera_focus)
	camera.h_offset=camera.size*132.0/900.0;camera.v_offset=-camera.size*52.0/900.0-0.18

func _update_actors(at:float,simulation_tick:int=-1)->void:
	# Cosmetic animation may continue after combat ends; status never advances
	# past the authoritative simulation. Time-only preview callers retain fallback.
	var status_tick:int=simulation_tick if simulation_tick>=0 else int(floor(at/0.05+0.000001))
	for unit in units:
		if not views.has(unit.id):continue
		var view=views[unit.id];view.update_time(at,unit);view.set_selected(preparation and selected_id==unit.id)
		if dead_at.has(unit.id) and at-float(dead_at[unit.id])>3.0:view.visible=false
		var bar:Dictionary=bars[unit.id];bar.root.visible=unit.hp>0;bar.hp.size.x=60.0*clampf(float(unit.hp)/maxf(float(unit.max_hp),1.0),0.0,1.0)
		bar.status.update_unit(unit,status_tick,status_definitions.get(unit.character_id,{}),preparation)
		bar.root.position=camera.unproject_position(view.global_position+Vector3(0,1.65,0))-Vector2(30,0)
func _unhandled_input(event:InputEvent)->void:
	if not preparation:return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if not event.pressed:dragging=false;return
		var point=_mouse_ground(event.position)
		if point==null:return
		var picked:=-1;var nearest:=0.65
		for unit in units:
			if unit.team!=0:continue
			var distance:float=point.distance_to(unit.cell)
			if distance<nearest:nearest=distance;picked=unit.id
		if picked>=0:set_selected(picked);selected.emit(picked);dragging=true
		elif selected_id>=0:placement_requested.emit(selected_id,point)
	elif event is InputEventMouseMotion and dragging and selected_id>=0:
		var point=_mouse_ground(event.position)
		if point!=null:placement_requested.emit(selected_id,point)
func _mouse_ground(event_position:Variant=null):
	# Window-bound input can carry a valid position without moving the OS pointer.
	var mouse:Vector2=get_viewport().get_mouse_position() if event_position==null else event_position
	if mouse.x>1000 or mouse.y<65 or mouse.y>650:return null
	var origin:=camera.project_ray_origin(mouse);var direction:=camera.project_ray_normal(mouse)
	if absf(direction.y)<0.001:return null
	var hit:=origin+direction*(-origin.y/direction.y);return Vector2(hit.x,hit.z)
