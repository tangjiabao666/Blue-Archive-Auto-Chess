extends Node3D
## Presentation only: consumes the core timeline and never changes combat state.
const NativeMaterials = preload("res://scripts/native_material_adapter.gd")
const RangeIndicator = preload("res://scripts/range_indicator.gd")
const ClipAdapter = preload("res://core/clip_adapter.gd")
const MODEL_PATH := "res://assets/native/CH0331.fbx"
const TICK_SECONDS := 0.05
const CELL_SPACING := 1.5
const BLEND_SECONDS := 0.15
const MAX_SKILL_SPEED := 3.0
# Immutable per-source clips shared; playback state remains per AnimationPlayer.
static var _native_libraries:Dictionary={}
var _clip_offset:=0.0
var _visibility_windows:Array=[]
var IDLE: StringName = &"CH0331_Normal_Idle"
var WALK: StringName = &"CH0331_Move_Ing"
var ATTACK_START: StringName = &"CH0331_Normal_Attack_Start"
# First sharp native weapon recoil begins 5 frames into the 30fps firing clip.
const NATIVE_FIRE_CONTACT_OFFSET := 1.0 / 6.0
var ATTACK_FIRE: StringName = &"CH0331_Normal_Attack_Ing"
var ATTACK_DELAY: StringName = &"CH0331_Normal_Attack_Delay"
var SKILL: StringName = &"CH0331_Exs"
var BASIC: StringName = &"CH0331_Public01"
var RELOAD: StringName = &"CH0331_Normal_Reload"
var DEATH: StringName = &"CH0331_Vital_Death"

var generation: int = -1
var actor_id: int = -1
var player: AnimationPlayer
var animation_player: AnimationPlayer
# Diagnostics are observed by tests/inspectors, not needed to advance a frame.
# Keep both public access paths current without rebuilding dictionaries per actor.
var _diagnostic_info: Dictionary = {}
var diagnostic_info: Dictionary:
	get:
		_refresh_diagnostics()
		return _diagnostic_info
	set(value):
		_diagnostic_info = value
var _native_animation_count: int = 0
var _anchor_skeleton: Skeleton3D
var _hit_bone: int = -1
var _muzzle_bone: int = -1
var _muzzle_node: Node3D
var _muzzle_socket: Transform3D = Transform3D.IDENTITY
var _selection_applied: bool = false
var current_clip: StringName = &""
var state: String = "idle"
var is_dead: bool = false
var is_moving: bool = false

var _presentation: Dictionary = {}
var _fire_contact_offset: float = NATIVE_FIRE_CONTACT_OFFSET
var _hold_ready:=false
var _setup_generation: int = -1
var _model: Node3D
var _range_indicator: MeshInstance3D
var _disk: MeshInstance3D
var _disk_material: StandardMaterial3D
var _selected: bool = false
var _team: int = 0
var _recovery_seconds: float = 1.0
var _warnings: Array[String] = []
var _seen_events: Dictionary = {}
var _ignored_events: int = 0
var _finished_callback: Callable
var _last_time: float = 0.0
var _clip_started_at: float = 0.0
var _clip_elapsed: float = 0.0
var _clip_speed: float = 1.0
var _clip_revision: int = 0
var _movement_generation: int = -1
var _move_from: Vector3 = Vector3.ZERO
var _move_to: Vector3 = Vector3.ZERO
var _move_started_at: float = 0.0
var _move_duration: float = 0.0
var _action_generation: int = -1
var _action_kind: String = ""
var _action_started_at: float = 0.0
var _action_ends_at: float = 0.0
var _attack_start_duration: float = 0.0
var _attack_speed: float = 1.0
var _attack_fire_duration: float = 0.0
var _attack_fire_speed: float = 1.0
var _attack_delay_speed: float = 1.0
var _skill_speed: float = 1.0
var _death_started_at: float = 0.0
var _shield_amount: int = 0
var _shield_until_tick: int = 0


func setup(unit: Dictionary, durations: Dictionary, new_generation: int) -> void:
	_restore_visibility()
	_setup_generation = -1
	_presentation=unit.get("presentation",{}).duplicate(true)
	var clips:Dictionary=_presentation.get("clips",{})
	IDLE=StringName(clips.get("idle","CH0331_Normal_Idle"))
	WALK=StringName(clips.get("walk","CH0331_Move_Ing"))
	ATTACK_START=StringName(clips.get("attack_start","CH0331_Normal_Attack_Start"))
	ATTACK_FIRE=StringName(clips.get("attack_fire","CH0331_Normal_Attack_Ing"))
	ATTACK_DELAY=StringName(clips.get("attack_delay","CH0331_Normal_Attack_Delay"))
	SKILL=StringName(clips.get("ex","CH0331_Exs"))
	BASIC=StringName(clips.get("basic","CH0331_Public01"))
	RELOAD=StringName(clips.get("reload","CH0331_Normal_Reload"))
	DEATH=StringName(clips.get("death","CH0331_Vital_Death"))
	_fire_contact_offset=float(_presentation.get("fire_contact_offset",NATIVE_FIRE_CONTACT_OFFSET))
	if is_instance_valid(player) and _finished_callback.is_valid():
		if player.animation_finished.is_connected(_finished_callback):
			player.animation_finished.disconnect(_finished_callback)
	for old_node in [_model, _disk, _range_indicator]:
		if is_instance_valid(old_node):
			remove_child(old_node)
			old_node.queue_free()
	player = null
	animation_player = null
	_model = null
	_anchor_skeleton = null
	_hit_bone = -1
	_muzzle_bone = -1
	_muzzle_node = null
	_muzzle_socket = Transform3D.IDENTITY
	_native_animation_count = 0
	_selection_applied = false
	_disk = null
	_range_indicator = null
	generation = new_generation
	_setup_generation = new_generation
	actor_id = int(unit.get("id", -1))
	_team = int(unit.get("team", 0))
	_recovery_seconds = maxf(float(unit.get("attack_ticks", 20)) * TICK_SECONDS, TICK_SECONDS)
	_warnings.clear()
	_seen_events.clear()
	_ignored_events = 0
	_last_time = 0.0
	current_clip = &""
	state = "idle"
	is_dead = false
	is_moving = false
	_action_kind = ""
	_action_generation = generation
	_movement_generation = generation
	_selected = false
	_hold_ready = false
	_shield_amount = int(unit.get("shield", 0))
	_shield_until_tick = int(unit.get("shield_until", 0))
	position = cell_position(unit.get("cell", Vector2.ZERO))
	rotation.y = 0.0 if _team == 0 else PI
	_create_disk()
	_range_indicator = RangeIndicator.new()
	_range_indicator.name = "AttackRangeIndicator"
	_range_indicator.configure(float(unit.range))
	add_child(_range_indicator)
	var model_path:String=_presentation.get("model_path",MODEL_PATH)
	var packed: PackedScene = load(model_path) as PackedScene
	if packed == null:
		_warn("Cannot load native model: " + model_path)
		return
	_model = packed.instantiate() as Node3D
	add_child(_model)
	_model.scale *= float(_presentation.get("model_scale",130.0))
	# Native fire_01 muzzle socket follows weapon +Z in the attack pose.
	# Align that barrel with the actor's -Z aiming axis; preserve authored bones.
	_model.rotation.y = float(_presentation.get("model_yaw",PI))
	for mesh in _model.find_children("*", "MeshInstance3D", true, false):
		if _presentation.get("legacy_fx_filter",true) and (String(mesh.name).begins_with("FX_") or String(mesh.name).ends_with("_Outline")):
			mesh.visible = false
	for node_name in _presentation.get("initial_hidden_nodes",[]):
		for node in _model.find_children(node_name,"Node3D",true,false):node.visible=false
	if _presentation.get("model_path",MODEL_PATH)==MODEL_PATH:
		var native_hair := ShaderMaterial.new()
		native_hair.shader = load("res://shaders/native_hair.gdshader")
		native_hair.set_shader_parameter("main_texture",load("res://assets/native/CH0331_Hair.png"))
		native_hair.set_shader_parameter("mask_texture",load("res://assets/native/CH0331_Hair_Mask.png"))
		native_hair.set_shader_parameter("hair_spec_texture",load("res://assets/native/CH0331_Hair_Spec.png"))
		var face_detail := ShaderMaterial.new()
		face_detail.shader = load("res://shaders/native_eyemouth.gdshader")
		face_detail.set_shader_parameter("eye_texture",load("res://assets/native/CH0331_EyeMouth.png"))
		face_detail.set_shader_parameter("mouth_atlas",load("res://assets/native/Character_Mouth.png"))
		for mesh in _model.find_children("*", "MeshInstance3D", true, false):
			if not mesh.visible or mesh.mesh == null: continue
			for surface in range(mesh.mesh.get_surface_count()):
				var material = mesh.get_active_material(surface)
				if material != null and String(material.resource_name)=="CH0331_Hair":
					mesh.set_surface_override_material(surface,native_hair)
				if material != null and String(material.resource_name)=="CH0331_EyeMouth":
					mesh.set_surface_override_material(surface,face_detail)
	NativeMaterials.apply(_model,_presentation.get("materials",[]))
	_cache_pose_anchors()
	var players: Array[Node] = _model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		_warn("Native model has no AnimationPlayer")
		return
	player = players[0] as AnimationPlayer
	animation_player = player
	for library_name in player.get_animation_library_list():
		var original=player.get_animation_library(library_name)
		var copied:Dictionary
		if _presentation.get("normalize_durations",true):
			copied=ClipAdapter.normalized_copy(original,_presentation.get("durations",durations),[String(IDLE),String(WALK)])
		else:
			var cache_key:String=str(_presentation.get("model_path",MODEL_PATH))+":"+str(_presentation.get("source_glb_sha256",""))+":"+str(library_name)+":"+str(IDLE)+":"+str(WALK)
			if not _native_libraries.has(cache_key):
				var library:=AnimationLibrary.new()
				for clip_name in original.get_animation_list():
					var clip:Animation=original.get_animation(clip_name).duplicate(true)
					clip.loop_mode=Animation.LOOP_LINEAR if StringName(clip_name) in [IDLE,WALK] else Animation.LOOP_NONE
					library.add_animation(clip_name,clip)
				_native_libraries[cache_key]=library
			copied={"library":_native_libraries[cache_key],"warnings":[]}
		player.remove_animation_library(library_name)
		player.add_animation_library(library_name,copied.library)
		for warning in copied.get("warnings",[]):_warn(String(warning))
	_native_animation_count = player.get_animation_list().size()
	# The battle clock drives animation as well as movement. No wall-clock timers
	# or native root-motion deltas are applied to the combat position.
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_finished_callback = _on_animation_finished.bind(generation)
	player.animation_finished.connect(_finished_callback)
	_set_phase("idle", IDLE, 0.0, 1.0, true)


func consume(event: Dictionary) -> void:
	if _setup_generation != generation or int(event.get("generation", -1)) != generation:
		_ignored_events += 1
		return
	if int(event.get("actor_id", -1)) != actor_id:
		return
	var event_id: String = String(event.get("event_id", ""))
	if not event_id.is_empty() and _seen_events.has(event_id):
		return
	if not event_id.is_empty():
		_seen_events[event_id] = true
	var event_time: float = float(event.get("tick", 0)) * TICK_SECONDS
	_last_time = event_time
	_update_movement(event_time)
	_sync_action(event_time)
	var kind: String = String(event.get("type", ""))
	var native_kind:String="ex" if kind=="skill" else "basic" if kind=="basic" else ""
	var window:Dictionary=_presentation.get("action_windows",{}).get(native_kind,{})
	if not window.is_empty() and not is_dead:
		if event.has("target_cell"):_face_point(cell_position(event.target_cell))
		_action_kind=kind;_action_generation=generation
		_action_started_at=event_time+float(window.start)
		_action_ends_at=_action_started_at+float(window.duration)
		_skill_speed=maxf(float(window.speed),0.0001)
		_set_phase(kind,SKILL if kind=="skill" else BASIC,_action_started_at,_skill_speed,true,float(window.clipIn))
		_start_visibility(native_kind,event_time)
		return
	if kind == "shield":
		_shield_amount = int(event.get("amount", 0))
		_shield_until_tick = int(event.get("until_tick", 0))
	elif kind == "shield_expired":
		_shield_amount = 0
		_shield_until_tick = 0
	elif kind == "death":
		_finish_visibility(event_time)
		is_dead = true
		is_moving = false
		_action_kind = ""
		_death_started_at = event_time
		_set_phase("death", DEATH, event_time, 1.0, true)
	elif not is_dead:
		match kind:
			"displacement":
				_hold_ready=false
				if _action_kind=="aim":_action_kind=""
				_move_from=cell_position(event.get("from",Vector2.ZERO));_move_to=cell_position(event.get("to",Vector2.ZERO))
				_move_started_at=event_time;_move_duration=TICK_SECONDS;_movement_generation=generation;is_moving=true
				position=_move_from
			"move":
				if _action_kind=="aim":_action_kind=""
				_hold_ready=false
				_move_from = cell_position(event.get("from", Vector2.ZERO))
				_move_to = cell_position(event.get("to", Vector2.ZERO))
				_move_started_at = event_time
				_move_duration = maxf(float(event.get("duration", TICK_SECONDS)), TICK_SECONDS)
				_movement_generation = generation
				is_moving = true
				position = _move_from
				_face_point(_move_to)
			"aim":
				_face_point(cell_position(event.get("target_cell",Vector2.ZERO)))
				_hold_ready=true
				_action_kind="aim";_action_generation=generation;_action_started_at=event_time
				var aim_seconds:float=maxf(float(event.get("duration_ticks",13))*TICK_SECONDS,TICK_SECONDS)
				_skill_speed=_clip_length(ATTACK_START)/aim_seconds
				_action_ends_at=event_time+aim_seconds
				_set_phase("aim",ATTACK_START,event_time,_skill_speed,true)
			"attack":
				if _action_kind not in ["skill","basic","reload"]:
					_face_point(cell_position(event.get("target_cell", Vector2.ZERO)))
					_action_kind = "attack"
					_action_generation = generation
					_action_started_at = event_time
					_recovery_seconds=maxf(float(event.get("recovery_ticks",roundi(_recovery_seconds/TICK_SECONDS)))*TICK_SECONDS,TICK_SECONDS)
					_action_ends_at = event_time + _recovery_seconds
					# Start/recoil/recovery are separate native clips. Damage contact anchors firing.
					var contact_time: float = float(event.get("impact_tick",event.tick+13))*TICK_SECONDS
					_attack_start_duration = clampf(contact_time-event_time-_fire_contact_offset,0.001,_recovery_seconds-0.002)
					_attack_speed = _clip_length(ATTACK_START)/_attack_start_duration
					_attack_fire_duration = minf(_clip_length(ATTACK_FIRE),_recovery_seconds-_attack_start_duration-0.001)
					_attack_fire_speed = _clip_length(ATTACK_FIRE)/_attack_fire_duration
					_attack_delay_speed = _clip_length(ATTACK_DELAY)/maxf(0.001,_recovery_seconds-_attack_start_duration-_attack_fire_duration)
					if _presentation.get("native_burst_cycle",false):
						_attack_start_duration=0.0
						_attack_fire_duration=minf(float(event.get("burst_ticks",roundi(_clip_length(ATTACK_FIRE)/TICK_SECONDS)))*TICK_SECONDS,_recovery_seconds-0.001)
						_attack_fire_speed=_clip_length(ATTACK_FIRE)/maxf(_attack_fire_duration,0.001)
						_attack_delay_speed=_clip_length(ATTACK_DELAY)/maxf(_recovery_seconds-_attack_fire_duration,0.001)
						_set_phase("attack_fire",ATTACK_FIRE,event_time,_attack_fire_speed,true)
					else:
						_set_phase("attack_start", ATTACK_START, event_time, _attack_speed, true)
			"basic", "reload":
				if event.has("target_cell"):_face_point(cell_position(event.target_cell))
				_action_kind=kind
				_action_generation=generation
				_action_started_at=event_time
				var action_clip:StringName=BASIC if kind=="basic" else RELOAD
				var recovery:float=maxf(float(event.get("duration_ticks",event.get("recovery_ticks",20)))*TICK_SECONDS,TICK_SECONDS)
				_skill_speed=maxf(0.001,_clip_length(action_clip)/recovery)
				_action_ends_at=event_time+recovery
				_set_phase(kind,action_clip,event_time,_skill_speed,true)
			"skill":
				if _action_kind not in ["skill","basic","reload"]:
					_face_point(cell_position(event.get("target_cell", Vector2.ZERO)))
					_action_kind = "skill"
					_action_generation = generation
					_action_started_at = event_time
					_skill_speed = minf(_clip_length(SKILL) / (float(event.get("recovery_ticks",110))*TICK_SECONDS), MAX_SKILL_SPEED)
					_skill_speed = maxf(_skill_speed, 0.0001)
					_action_ends_at = event_time + _clip_length(SKILL) / _skill_speed
					_set_phase("skill", SKILL, event_time, _skill_speed, true)


func update_time(battle_time: float, unit: Dictionary) -> void:
	if _setup_generation != generation or not is_finite(battle_time):
		return
	_last_time = maxf(0.0, battle_time)
	_update_visibility(_last_time)
	_hold_ready=bool(unit.get("aimed",_hold_ready)) and _presentation.get("native_burst_cycle",false)
	_shield_amount = int(unit.get("shield", _shield_amount))
	_shield_until_tick = int(unit.get("shield_until", _shield_until_tick))
	_update_movement(_last_time)
	_sync_action(_last_time)
	if not is_dead and _action_kind.is_empty():
		if is_moving:
			_set_phase("move", WALK, _move_started_at, 1.0)
		else:
			position = cell_position(unit.get("cell", Vector2.ZERO))
			_set_phase("ready" if _hold_ready else "idle", ATTACK_DELAY if _hold_ready else IDLE, _last_time, 1.0)
	_advance_clip_to(_last_time)


func set_selected(selected: bool) -> void:
	if _setup_generation != generation:
		return
	if _selection_applied and _selected == selected:
		return
	_selected = selected
	_selection_applied = true
	if is_instance_valid(_range_indicator):
		_range_indicator.visible = selected and _team == 0
	if _disk_material != null:
		var team_color := Color("4b9ade") if _team == 0 else Color("e7767c")
		_disk_material.albedo_color = Color("f3d98b") if selected else team_color
		_disk_material.albedo_color.a = 0.92 if selected else 0.38


func diagnostics() -> Dictionary:
	return diagnostic_info.duplicate(true)


static func cell_position(cell: Vector2) -> Vector3:
	return Vector3(cell.x, 0.0, cell.y)


func _update_movement(battle_time: float) -> void:
	if not is_moving or is_dead or _movement_generation != generation:
		return
	var progress: float = clampf((battle_time - _move_started_at) / _move_duration, 0.0, 1.0)
	position = _move_from.lerp(_move_to, progress)
	if progress >= 1.0:
		is_moving = false


func _sync_action(battle_time: float) -> void:
	if is_dead:
		_set_phase("death", DEATH, _death_started_at, 1.0)
		return
	if _action_kind.is_empty() or _action_generation != generation:
		return
	if battle_time >= _action_ends_at:
		_advance_clip_to(_action_ends_at + 0.000001)
		_action_kind = ""
		return
	if _action_kind in ["skill","basic","reload","aim"]:
		var action_clip:StringName=SKILL if _action_kind=="skill" else BASIC if _action_kind=="basic" else ATTACK_START if _action_kind=="aim" else RELOAD
		_set_phase(_action_kind,action_clip,_action_started_at,_skill_speed)
	elif battle_time < _action_started_at + _attack_start_duration:
		_set_phase("attack_start", ATTACK_START, _action_started_at, _attack_speed)
	elif battle_time < _action_started_at + _attack_start_duration + _attack_fire_duration:
		_set_phase("attack_fire", ATTACK_FIRE, _action_started_at + _attack_start_duration, _attack_fire_speed)
	else:
		_set_phase("attack_delay", ATTACK_DELAY, _action_started_at + _attack_start_duration + _attack_fire_duration, _attack_delay_speed)


func _set_phase(next_state: String, clip: StringName, started_at: float, speed: float, force_restart: bool = false, source_offset:float=0.0) -> void:
	var phase_changed: bool = state != next_state
	if force_restart or phase_changed or current_clip != clip:
		_finish_visibility(started_at)
	state = next_state
	if player == null:
		return
	if not player.has_animation(clip):
		_warn("Missing native clip: " + String(clip))
		if next_state == "death":
			player.pause()
		return
	if not force_restart and not phase_changed and current_clip == clip:
		return
	current_clip = clip
	_clip_started_at = started_at
	_clip_elapsed = 0.0
	_clip_offset=source_offset
	_clip_speed = speed
	_clip_revision += 1
	player.play(clip, BLEND_SECONDS, speed)
	player.advance(0.0)
	if source_offset>0.0:player.seek(source_offset,true)


func _advance_clip_to(battle_time: float) -> void:
	if player == null or current_clip.is_empty() or _setup_generation != generation:
		return
	var elapsed: float = maxf(0.0, battle_time - _clip_started_at)
	var animation: Animation = player.get_animation(current_clip)
	if animation == null:
		return
	if animation.loop_mode == Animation.LOOP_NONE:
		elapsed = minf(elapsed, maxf(0.0,animation.length-_clip_offset) / _clip_speed + 0.000001)
	var delta: float = maxf(0.0, elapsed - _clip_elapsed)
	var revision: int = _clip_revision
	if delta > 0.0:
		player.advance(delta)
	if revision == _clip_revision:
		_clip_elapsed = elapsed


func _on_animation_finished(clip: StringName, callback_generation: int) -> void:
	if callback_generation != generation or _setup_generation != generation or clip != current_clip:
		return
	if is_dead:
		player.pause()
		return
	if _action_generation != generation:
		return
	if state == "attack_start" and _action_kind == "attack":
		_set_phase("attack_fire", ATTACK_FIRE, _action_started_at + _attack_start_duration, _attack_fire_speed)
	elif state == "attack_fire" and _action_kind == "attack":
		_set_phase("attack_delay", ATTACK_DELAY, _action_started_at + _attack_start_duration + _attack_fire_duration, _attack_delay_speed)
	elif state in ["attack_delay", "skill", "basic", "reload", "aim"]:
		var finished_at: float = _action_ends_at
		_action_kind = ""
		_set_phase("ready" if _hold_ready else "idle", ATTACK_DELAY if _hold_ready else IDLE, finished_at, 1.0)


func _face_point(point: Vector3) -> void:
	var direction: Vector3 = point - position
	direction.y = 0.0
	if direction.length_squared() > 0.000001:
		rotation.y = atan2(-direction.x, -direction.z)


func _clip_length(clip: StringName) -> float:
	if player != null and player.has_animation(clip):
		return maxf(player.get_animation(clip).length, 0.0001)
	return _recovery_seconds


func _create_disk() -> void:
	_disk = MeshInstance3D.new()
	_disk.name = "TeamSelectionDisk"
	var shape := CylinderMesh.new()
	shape.top_radius = 0.44
	shape.bottom_radius = 0.44
	shape.height = 0.022
	shape.radial_segments = 36
	_disk.mesh = shape
	_disk.position.y = 0.018
	_disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disk_material = StandardMaterial3D.new()
	_disk_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disk_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disk.material_override = _disk_material
	add_child(_disk)
	set_selected(false)


func _cache_pose_anchors() -> void:
	# Native hierarchy is immutable for this setup generation. Cache identities,
	# never poses: every contact still reads the current animated bone transform.
	var skeletons = _model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():return
	_anchor_skeleton = skeletons[0] as Skeleton3D
	_hit_bone = _anchor_skeleton.find_bone("Bip001 Spine1")
	var anchor_name:String = _presentation.get("muzzle_anchor", "")
	if not anchor_name.is_empty():
		for source_anchor in _presentation.get("anchors", []):
			if source_anchor.name != anchor_name:continue
			var parts:PackedStringArray = String(source_anchor.path).split("/")
			var parent_index:int = _anchor_skeleton.find_bone(parts[parts.size()-2])
			if parent_index >= 0:
				var p:Array = source_anchor.local_translation
				var q:Array = source_anchor.local_rotation
				_muzzle_bone = parent_index
				_muzzle_socket = Transform3D(Basis(Quaternion(q[0],q[1],q[2],q[3])),Vector3(p[0],p[1],p[2]))
				return
		for node in _model.find_children(anchor_name, "Node3D", true, false):
			_muzzle_node = node
			return
	_muzzle_bone = _anchor_skeleton.find_bone("Bip001_Weapon")
	_muzzle_socket = Transform3D(Basis(Quaternion(0.0000001686,0.0000001686,0.707106352,0.707107246)),Vector3(-0.0000000001278722,-0.000137883760,0.001284404695))


func hit_position() -> Vector3:
	# Torso presentation anchor; character-specific authored hit anchor can override later.
	if not is_instance_valid(_anchor_skeleton) or _hit_bone < 0:
		return global_position + Vector3.UP * 0.7
	return _anchor_skeleton.global_transform * _anchor_skeleton.get_bone_global_pose(_hit_bone).origin


func muzzle_transform() -> Transform3D:
	# Original source socket and live parent; setup caches identities, never poses.
	if not is_instance_valid(_anchor_skeleton):return global_transform
	if is_instance_valid(_muzzle_node):return _muzzle_node.global_transform
	if _muzzle_bone < 0:return global_transform
	return _anchor_skeleton.global_transform * _anchor_skeleton.get_bone_global_pose(_muzzle_bone) * _muzzle_socket


func _warn(message: String) -> void:
	if message not in _warnings:
		_warnings.append(message)
		push_warning(message)


func _refresh_diagnostics() -> void:
	_diagnostic_info = {
		"actor_id": actor_id, "generation": generation, "state": state,
		"clip": String(current_clip), "native_animation_count": _native_animation_count,
		"moving": is_moving, "dead": is_dead, "selected": _selected,
		"position": position, "shield": _shield_amount, "shield_until_tick": _shield_until_tick,
		"action": _action_kind, "animation_speed": _clip_speed, "skill_speed_cap": MAX_SKILL_SPEED,
		"ignored_generation_events": _ignored_events, "warnings": _warnings.duplicate(),
		"clock": _last_time, "changes_combat_state": false,
	}

func _start_visibility(kind:String,at:float)->void:
	_finish_visibility(at)
	for record in _presentation.get("activation_windows",{}).get(kind,[]):
		var mode:String=record.get("post_playback","")
		if mode not in ["revert","leave_as_is"]:continue
		var matches=_model.find_children(record.node,"Node3D",true,false)
		if matches.size()!=1:_warn("Unresolved activation node: "+str(record.node));continue
		var node:Node3D=matches[0]
		# These are Timeline seconds, independent of the AnimationPlayableAsset's
		# clipIn/speed. Keep the track after its Active clip for backward sampling.
		_visibility_windows.append({"node":node,"prior":node.visible,"start":at+float(record.start),"end":at+float(record.start)+float(record.duration),"post_playback":mode})
	_update_visibility(at)

func _update_visibility(at:float)->void:
	for index in range(_visibility_windows.size()-1,-1,-1):
		var item:Dictionary=_visibility_windows[index]
		if not is_instance_valid(item.node):_visibility_windows.remove_at(index);continue
		if item.post_playback=="leave_as_is":
			item.node.visible=at>=item.start and at<item.end
		elif at>=item.end:
			item.node.visible=item.prior
			_visibility_windows.remove_at(index)
		else:item.node.visible=true if at>=item.start else item.prior

func _finish_visibility(at:float)->void:
	# Evaluate skipped time before stopping the source track. LeaveAsIs retains
	# that state on completion/interruption; only Revert restores the prior one.
	_update_visibility(at)
	for item in _visibility_windows:
		if is_instance_valid(item.node) and item.post_playback=="revert":item.node.visible=item.prior
	_visibility_windows.clear()

func _restore_visibility()->void:
	# Setup/reset discards the old source instance, separate from Timeline stop.
	for item in _visibility_windows:
		if is_instance_valid(item.node):item.node.visible=item.prior
	_visibility_windows.clear()
