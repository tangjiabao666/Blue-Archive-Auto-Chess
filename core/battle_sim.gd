extends RefCounted
## Pure deterministic combat. No scene, animation or rendering dependencies.
const WIDTH := 6
const HEIGHT := 6
const MAX_TICKS := 1200
const STEP_SECONDS := 0.05
const DIRECTIONS := [Vector2i(0,-1), Vector2i(-1,0), Vector2i(1,0), Vector2i(0,1)]
var units: Array = []
var phase := "prepare"
var winner := -2 # -2 unresolved, -1 draw, 0/1 team
var tick := 0
var events: Array = []
var _initial: Array = []
var _pending: Array = []

func configure(roster: Array) -> String:
	if phase == "running": return "battle is running"
	if roster.size() < 2 or roster.size() > 6: return "requires two to six units"
	var next: Array = []
	var ids := {}
	var cells := {}
	var teams := [0,0]
	for raw in roster:
		if not raw is Dictionary: return "unit must be a dictionary"
		if not raw.get("id") is int or raw.id < 0: return "invalid id"
		if not raw.get("team") is int or raw.team not in [0,1]: return "invalid team"
		if not raw.get("cell") is Vector2i or not _inside(raw.cell): return "invalid cell"
		if ids.has(raw.id) or cells.has(raw.cell): return "duplicate id or cell"
		if not _deployment(raw.team,raw.cell): return "wrong deployment zone"
		var defaults := {"hp":100,"damage":10,"range":2,"attack_ticks":20,"move_ticks":4,"skill_power":30,"attack_windup_ticks":0,"skill_cooldown_ticks":160,"skill_recovery_ticks":20}
		for key in defaults:
			var value = raw.get(key,defaults[key])
			if not value is int: return "stats must be integers"
			if value < 0 or value > 1000000: return "invalid stat range"
			if key in ["hp","range","attack_ticks","move_ticks","skill_cooldown_ticks","skill_recovery_ticks"] and value == 0: return "stat must be positive"
		if raw.get("attack_windup_ticks",0) >= raw.get("attack_ticks",20): return "windup must be shorter than cooldown"
		var skill = raw.get("skill","single")
		if not skill is String or skill not in ["single","area","shield"]: return "invalid skill"
		var u := {"id":raw.id,"team":raw.team,"cell":raw.cell,"max_hp":raw.get("hp",100),"hp":raw.get("hp",100),"damage":raw.get("damage",10),"range":raw.get("range",2),"attack_ticks":raw.get("attack_ticks",20),"move_ticks":raw.get("move_ticks",4),"skill":skill,"skill_power":raw.get("skill_power",30),"attack_windup_ticks":raw.get("attack_windup_ticks",0),"skill_cooldown_ticks":raw.get("skill_cooldown_ticks",160),"skill_recovery_ticks":raw.get("skill_recovery_ticks",20),"skill_ready":raw.get("skill_cooldown_ticks",160),"energy":0,"shield":0,"shield_until":0,"attack_ready":0,"move_ready":0}
		next.append(u)
		ids[u.id] = true; cells[u.cell] = true; teams[u.team] += 1
	if teams[0] < 1 or teams[1] < 1 or teams[0] > 3 or teams[1] > 3: return "one to three units per team required"
	next.sort_custom(func(a,b): return a.id < b.id)
	units = next
	_initial = units.duplicate(true)
	phase = "prepare"; winner = -2; tick = 0; events = []; _pending = []
	return ""

func place(id: int, cell: Vector2i) -> bool:
	if phase != "prepare" or not _inside(cell): return false
	var u = _unit(id)
	if u == null or u.team != 0 or not _deployment(0,cell): return false
	var other = _occupant(cell)
	if other != null:
		if other.team != u.team: return false
		other.cell = u.cell
	u.cell = cell
	return true

func start() -> bool:
	if phase != "prepare" or units.is_empty(): return false
	_initial = units.duplicate(true)
	phase = "running"; tick = 0; winner = -2; events = []
	return true

func step() -> Array:
	events = []
	if phase != "running": return []
	tick += 1
	for u in units:
		if u.shield > 0 and tick >= u.shield_until:
			u.shield = 0
			_emit("shield_expired",{"actor_id":u.id})
	# Sequential reservation in stable ID order prevents double occupancy.
	for u in units:
		if u.hp <= 0: continue
		var target = _target(u)
		if target == null: continue
		if _distance(u.cell,target.cell) > u.range and tick >= u.move_ready and tick >= u.attack_ready:
			var dest := _path_step(u,target.cell)
			if dest != u.cell:
				var origin: Vector2i = u.cell
				u.cell = dest; u.move_ready = tick + u.move_ticks
				_emit("move",{"actor_id":u.id,"from":origin,"to":dest,"duration":u.move_ticks * STEP_SECONDS})
	# Collect actions from all survivors before applying damage: simultaneous kills.
	var damage_queue: Array = []
	var remaining: Array = []
	for pending in _pending:
		var source = _unit(pending.source)
		var victim = _unit(pending.target)
		if source == null or victim == null or source.hp <= 0 or victim.hp <= 0: continue
		if pending.due <= tick: damage_queue.append(pending)
		else: remaining.append(pending)
	_pending = remaining
	for u in units:
		if u.hp <= 0: continue
		var target = _target(u)
		if target == null or _distance(u.cell,target.cell) > u.range: continue
		if tick < u.move_ready or tick < u.attack_ready: continue
		var skill_target = _skill_target(u) if tick >= u.skill_ready else null
		if skill_target != null:
			target = skill_target
			u.energy = 0
			u.skill_ready = tick + u.skill_cooldown_ticks
			u.attack_ready = tick + u.skill_recovery_ticks
			_emit("skill",{"actor_id":u.id,"target_id":target.id,"skill":u.skill,"recovery_ticks":u.skill_recovery_ticks,"origin":u.cell,"target_cell":target.cell})
			if u.skill == "shield":
				u.shield = u.skill_power; u.shield_until = tick + 80
				_emit("shield",{"actor_id":u.id,"amount":u.shield,"until_tick":u.shield_until})
			elif u.skill == "area":
				for victim in units:
					if victim.hp > 0 and victim.team != u.team and _distance(victim.cell,target.cell) <= 1:
						damage_queue.append({"source":u.id,"target":victim.id,"amount":u.skill_power})
			else:
				damage_queue.append({"source":u.id,"target":target.id,"amount":u.skill_power})
		elif tick >= u.attack_ready:
			u.attack_ready = tick + u.attack_ticks
			var contact: int = tick + u.attack_windup_ticks
			_emit("attack",{"actor_id":u.id,"target_id":target.id,"origin":u.cell,"target_cell":target.cell,"impact_tick":contact})
			var hit := {"source":u.id,"target":target.id,"amount":u.damage,"due":contact}
			if contact == tick: damage_queue.append(hit)
			else: _pending.append(hit)
	for hit in damage_queue:
		var victim = _unit(hit.target)
		var absorbed := mini(victim.shield,hit.amount)
		victim.shield -= absorbed
		var dealt := mini(victim.hp,hit.amount-absorbed)
		victim.hp -= dealt
		_emit("damage",{"actor_id":hit.source,"target_id":victim.id,"amount":dealt,"absorbed":absorbed,"hp":victim.hp,"shield":victim.shield})
	for u in units:
		if u.hp == 0 and not u.get("dead",false):
			u["dead"] = true
			_emit("death",{"actor_id":u.id})
	var alive := [0,0]
	var hp := [0,0]
	var maximum := [0,0]
	for u in units:
		if u.hp > 0: alive[u.team] += 1
		hp[u.team] += u.hp; maximum[u.team] += u.max_hp
	if alive[0] == 0 or alive[1] == 0:
		_end(-1 if alive[0] == 0 and alive[1] == 0 else (0 if alive[1] == 0 else 1),"elimination")
	elif tick >= MAX_TICKS:
		var compare: int = hp[0]*maximum[1] - hp[1]*maximum[0]
		_end(-1 if compare == 0 else (0 if compare > 0 else 1),"timeout")
	return events.duplicate(true)

func reset() -> void:
	units = _initial.duplicate(true)
	phase = "prepare"; winner = -2; tick = 0; events = []; _pending = []

func snapshot() -> Dictionary:
	return {"phase":phase,"winner":winner,"tick":tick,"units":units.duplicate(true),"pending_hits":_pending.duplicate(true)}

func _end(team: int, reason: String) -> void:
	phase = "finished"; winner = team; _pending = []
	_emit("finished",{"winner":winner,"reason":reason})

func _emit(kind: String, payload: Dictionary) -> void:
	payload["type"] = kind; payload["tick"] = tick
	payload["event_id"] = "%d:%d" % [tick,events.size()]
	events.append(payload)

func _unit(id: int):
	for u in units:
		if u.id == id: return u
	return null

func _occupant(cell: Vector2i):
	for u in units:
		if u.hp > 0 and u.cell == cell: return u
	return null

func _target(u: Dictionary):
	var best = null
	var distance := 100000
	for enemy in units:
		if enemy.team == u.team or enemy.hp <= 0: continue
		var d := _distance(u.cell,enemy.cell)
		if d < distance:
			distance = d; best = enemy
	return best

func _skill_target(u: Dictionary):
	var candidates: Array = []
	for enemy in units:
		if enemy.hp > 0 and enemy.team != u.team and _distance(u.cell,enemy.cell) <= u.range:
			candidates.append(enemy)
	if candidates.is_empty(): return null
	if u.skill == "shield":
		if u.shield > 0 or u.hp * 4 > u.max_hp * 3: return null
		for enemy in candidates:
			if enemy.damage > 0 and _distance(enemy.cell,u.cell) <= enemy.range: return enemy
		return null
	var best = null
	var best_score := -1
	for enemy in candidates:
		var score: int
		if u.skill == "area":
			var count := 0
			var effective := 0
			for other in units:
				if other.hp > 0 and other.team != u.team and _distance(other.cell,enemy.cell) <= 1:
					count += 1; effective += mini(other.hp,u.skill_power)
			if count < 2 and enemy.hp > u.skill_power: continue
			score = count * 10000000 + effective
		else:
			# Prefer a lethal hit, then threatening targets, tie by stable unit ID.
			score = (10000000 if enemy.hp <= u.skill_power else 0) + enemy.damage * 2 + mini(enemy.hp,u.skill_power)
		if score > best_score:
			best_score = score; best = enemy
	return best

func _path_step(u: Dictionary, target: Vector2i) -> Vector2i:
	var queue: Array[Vector2i] = [u.cell]
	var first := {u.cell:u.cell}
	var index := 0
	while index < queue.size():
		var cell := queue[index]; index += 1
		if cell != u.cell and _distance(cell,target) <= u.range: return first[cell]
		for direction in DIRECTIONS:
			var next: Vector2i = cell + direction
			if not _inside(next) or first.has(next) or _occupant(next) != null: continue
			first[next] = next if cell == u.cell else first[cell]
			queue.append(next)
	return u.cell

func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < WIDTH and cell.y >= 0 and cell.y < HEIGHT

func _deployment(team: int, cell: Vector2i) -> bool:
	return cell.y >= 3 if team == 0 else cell.y < 3

func _distance(a: Vector2i,b: Vector2i) -> int:
	return absi(a.x-b.x) + absi(a.y-b.y)
