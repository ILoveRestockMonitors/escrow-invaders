extends Control
const Evolution = preload("res://scripts/ship_evolution.gd")
const Patterns = preload("res://scripts/combat_patterns.gd")
const Director = preload("res://scripts/encounter_director.gd")
## Finite combat objectives, genuine defeat and paused learning counters.

signal question_requested
signal enemy_killed(enemy_id: String, kind: String)
signal combat_finished(stats: Dictionary)
signal shield_hit
signal combat_cue(kind: String, intensity: float)

const NAVY := Color("080e21")
const CYAN := Color("55edff")
const LIME := Color("c6ff59")
const ORANGE := Color("ffae4b")
const PINK := Color("ff5a9f")
const PURPLE := Color("ad7aff")
const MAX_ENEMIES := 18
const MAX_FRIENDLY := 80
const MAX_HOSTILE := 48
const MAX_BULLETS := MAX_FRIENDLY + MAX_HOSTILE
const MAX_PARTICLES := 260
const PLAYER_SPEED := 290.0
const PULSE_COOLDOWN := 7.0
const PULSE_RADIUS := 165.0
const PULSE_DAMAGE := 8.0
const MAX_RINGS := 24
const MAX_TRAIL := 16
const MOB_HP := {"chaser": 8.0, "runner": 6.0, "shooter": 14.0, "charger": 12.0, "heavy": 20.0, "sniper": 16.0, "miner": 18.0, "splitter": 22.0}

var reduced_motion := false
var combat_active := false
var player_position := Vector2.ZERO
var hull := 3
var turret_count := 1
var lightning_level := 0
var overdrive_enabled := false
var _config: Dictionary = {}
var _loadout: Dictionary = {}
var _enemies: Array[Dictionary] = []
var _bullets: Array[Dictionary] = []
var _gems: Array[Dictionary] = []
var _particles: Array[Dictionary] = []
var _arcs: Array[Dictionary] = []
var _popups: Array[Dictionary] = []
var _background: Texture2D
var _ship: Texture2D
var _rng := RandomNumberGenerator.new()
var _spawn_rng := RandomNumberGenerator.new()
var _time := 0.0
var _elapsed := 0.0
var _invulnerability := 0.0
var _shake := 0.0
var _shake_offset := Vector2.ZERO
var _celebration := 0.0
var _celebration_color := CYAN
var _aim_angle := -PI / 2.0
var _orbit_angle := 0.0
var _dragging := false
var _touch_index := -1
var _touch_target := Vector2.ZERO
var _initialized := false
var _last_size := Vector2.ZERO
var _fire_cooldown := 0.0
var _turret_cooldown := 0.0
var _lightning_cooldown := 0.0
var _plasma_cooldown := 0.0
var _spawn_cooldown := 0.0
var _packet := 0
var _spawn_queue: Array[String] = []
var _spawn_serial := 0
var _question_opened := false
var _counter_applied := false
var _resolved_counter := ""
var _target_defeated := false
var _finished := false
var _encounter_cleared := false
var _revive_used := false
var _resume_remaining := 0.0
var _kills := 0
var _hits := 0
var _last_attack := ""
var _target_name := ""
var _target_max_hp := 0.0
var _glow_texture: GradientTexture2D
var _rings: Array[Dictionary] = []
var _ship_trail: Array[Dictionary] = []
var _pulse_cooldown := 0.0
var _pulse_uses := 0
var _streak := 0
var _streak_remaining := 0.0
var _shot_cue_cooldown := 0.0
var _impact_cue_cooldown := 0.0
var _trail_cooldown := 0.0
var _muzzle_flash := 0.0
var _damage_flash := 0.0
var _last_player_position := Vector2.ZERO

func _ready() -> void:
	_rng.randomize()
	_create_glow_texture()
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	if ResourceLoader.exists("res://assets/arena-background.png"):
		_background = load("res://assets/arena-background.png") as Texture2D
	if ResourceLoader.exists("res://assets/player-ship.png"):
		_ship = load("res://assets/player-ship.png") as Texture2D
	resized.connect(_on_resized)
	call_deferred("_initialize_if_needed")

func _initialize_if_needed() -> void:
	if not _initialized: reset_arena()

func launch_encounter(config: Dictionary, loadout: Dictionary, initial_hull: int = 3, resolved_counter: String = "") -> void:
	reset_arena()
	_config = Director.match_loadout(config, loadout)
	_loadout = loadout.duplicate(true)
	_ship = Evolution.texture(int(loadout.get("ship_rank", 1)))
	hull = clampi(initial_hull, 0, 3)
	turret_count = clampi(int(loadout.get("turrets", 1)), 1, 5)
	lightning_level = clampi(int(loadout.get("lightning", 0)), 0, 12)
	overdrive_enabled = float(loadout.get("overdrive", 1.0)) > 1.0
	_spawn_rng.seed = int(config.get("seed", 1))
	_target_name = str(config.get("target_name", "ORBIT ENFORCER"))
	_target_max_hp = float(_config.get("target_hp", 60.0))
	_resolved_counter = resolved_counter
	_invulnerability = 0.75
	_start_packet()
	combat_active = hull > 0
	celebrate("launch")

func set_loadout(turrets: int, lightning: int, overdrive: bool) -> void:
	turret_count = clampi(turrets, 1, 5)
	lightning_level = clampi(lightning, 0, 12)
	overdrive_enabled = overdrive
	_loadout = {"turrets": turret_count, "damage": 2.0, "fire_rate": 1.0, "lightning": lightning_level, "overdrive": 1.3 if overdrive else 1.0}

func refresh_ship(loadout: Dictionary) -> void:
	_loadout = loadout.duplicate(true)
	_ship = Evolution.texture(int(loadout.get("ship_rank", 1)))
	queue_redraw()

func freeze() -> void:
	combat_active = false
	release_steering()
	_shake = 0.0
	_shake_offset = Vector2.ZERO
	queue_redraw()

func reset_arena() -> void:
	freeze()
	_enemies.clear()
	_bullets.clear()
	_gems.clear()
	_particles.clear()
	_arcs.clear()
	_popups.clear()
	_rings.clear()
	_ship_trail.clear()
	_spawn_queue.clear()
	_config.clear()
	_elapsed = 0.0
	_time = 0.0
	_orbit_angle = 0.0
	_packet = 0
	_spawn_serial = 0
	_spawn_cooldown = 0.1
	_fire_cooldown = 0.0
	_turret_cooldown = 0.12
	_lightning_cooldown = 0.7
	_plasma_cooldown = 0.8
	_question_opened = false
	_counter_applied = false
	_target_defeated = false
	_finished = false
	_encounter_cleared = false
	_revive_used = false
	_resume_remaining = 0.0
	_resolved_counter = ""
	_kills = 0
	_hits = 0
	_last_attack = ""
	_pulse_cooldown = 0.0
	_pulse_uses = 0
	_streak = 0
	_streak_remaining = 0.0
	_shot_cue_cooldown = 0.0
	_impact_cue_cooldown = 0.0
	_trail_cooldown = 0.0
	_muzzle_flash = 0.0
	_damage_flash = 0.0
	player_position = size * Vector2(0.5, 0.65)
	_last_player_position = player_position
	_last_size = size
	_initialized = true
	queue_redraw()

func apply_counter(kind: String) -> void:
	if _counter_applied or not _question_opened or kind not in ["independent", "assisted", "solution"]: return
	_counter_applied = true
	_resolved_counter = kind
	var target_index := _target_index()
	if target_index < 0: return
	var target: Dictionary = _enemies[target_index]
	target["armored"] = false
	target["state"] = "recover"
	target["timer"] = 1.0
	target["spawn"] = 0.0
	target.guard_disabled = 1.0
	var origin: Vector2 = target["pos"]
	var damage := 22.0
	if bool(_config.get("boss", false)): damage = minf(damage, float(target["max_hp"]) * 0.1)
	if kind == "assisted": damage *= 0.5
	elif kind == "solution": damage = 0.0
	_arcs.append({"from": player_position, "to": origin, "life": 0.5, "seed": 3.0})
	_burst(origin, CYAN, 40 if not reduced_motion else 8, 220.0)
	_popup(origin + Vector2(0, -52), "ARMOR SHATTERED" if damage > 0 else "ARMOR DISABLED", CYAN)
	if damage > 0.0: _damage_enemy(target_index, damage)
	if kind == "independent":
		var hit_ids: Array[String] = []
		for enemy: Dictionary in _enemies:
			if not bool(enemy["target"]) and (enemy["pos"] as Vector2).distance_to(origin) < 240.0 and hit_ids.size() < 3:
				hit_ids.append(str(enemy["id"]))
		for enemy_id: String in hit_ids:
			var index := _enemy_index(enemy_id)
			if index >= 0:
				_arcs.append({"from": origin, "to": _enemies[index]["pos"], "life": 0.3, "seed": 1.0})
				_damage_enemy(index, 8.0)
	celebrate("correct" if kind == "independent" else "redemption")
	queue_redraw()

func resume_combat() -> void:
	if _finished or hull <= 0 or not _counter_applied: return
	release_steering()
	_resume_remaining = 0.6
	combat_active = true
	_popup(player_position + Vector2(0, -45), "GET READY", CYAN)

func revive_encounter(restored_hull: int = 3) -> bool:
	# Root commits the study reward first. This method changes only the live battle.
	if not _initialized or _config.is_empty() or _encounter_cleared or _revive_used or combat_active or hull > 0 or restored_hull <= 0:
		return false
	if not _finished and not _question_opened and _elapsed <= 0.0:
		return false
	_revive_used = true
	hull = clampi(restored_hull, 1, 3)
	_finished = false
	_invulnerability = 2.0
	_resume_remaining = 0.6
	release_steering()
	_shake = 0.0
	_shake_offset = Vector2.ZERO
	for index in range(_bullets.size() - 1, -1, -1):
		if bool(_bullets[index].get("hostile", false)):
			_bullets.remove_at(index)
	for enemy: Dictionary in _enemies:
		enemy["state"] = "recover"
		enemy["timer"] = maxf(1.2, float(enemy.get("timer", 0.0)))
	# A death before the question can continue screening normally. A fatal core
	# error must have its saved counter applied before hostile simulation resumes.
	combat_active = not _question_opened or _counter_applied
	_burst(player_position, CYAN, 32 if not reduced_motion else 8, 160.0)
	_popup(player_position + Vector2(0, -45), "REBOOT COMPLETE", CYAN)
	queue_redraw()
	return true

func encounter_status() -> Dictionary:
	var target_index := _target_index()
	var pending := _spawn_queue.size()
	var packets: Array = _config.get("packets", [])
	for index in range(_packet, packets.size()): pending += (packets[index] as Array).size()
	return {"remaining": _enemies.size() + pending + (0 if _question_opened else 1), "target_hp": float(_enemies[target_index]["hp"]) if target_index >= 0 else (0.0 if _target_defeated else _target_max_hp), "target_max_hp": _target_max_hp, "target_name": _target_name, "packet": _packet, "elapsed": _elapsed, "question_opened": _question_opened, "counter": _resolved_counter, "resume_remaining": _resume_remaining, "pulse": pulse_status(), "streak": _streak, "streak_remaining": _streak_remaining, "boss_type": _config.get("boss_type", ""), "threat": _config.get("threat", {})}

func pulse_status() -> Dictionary:
	return {"ready": combat_active and not _finished and hull > 0 and is_processing() and _resume_remaining <= 0.0 and _pulse_cooldown <= 0.0, "cooldown": _pulse_cooldown, "duration": PULSE_COOLDOWN, "charge": 1.0 - _pulse_cooldown / PULSE_COOLDOWN}

func activate_pulse() -> bool:
	# This is a combat action only. Frozen study, pause and get-ready cannot spend it.
	if not bool(pulse_status()["ready"]): return false
	_pulse_cooldown = PULSE_COOLDOWN
	_pulse_uses += 1
	_invulnerability = maxf(_invulnerability, 0.55)
	var erased := 0
	for index in range(_bullets.size() - 1, -1, -1):
		var bullet: Dictionary = _bullets[index]
		if bool(bullet["hostile"]) and (bullet["pos"] as Vector2).distance_to(player_position) <= PULSE_RADIUS:
			_burst(bullet["pos"], CYAN, 3 if not reduced_motion else 1, 85.0)
			_bullets.remove_at(index)
			erased += 1
	var affected: Array[String] = []
	for enemy: Dictionary in _enemies:
		if bool(enemy["armored"]) or float(enemy["spawn"]) > 0.0: continue
		if (enemy["pos"] as Vector2).distance_to(player_position) > PULSE_RADIUS: continue
		var direction := ((enemy["pos"] as Vector2) - player_position).normalized()
		enemy["pos"] = _clamp_position((enemy["pos"] as Vector2) + direction * (14.0 if bool(enemy["target"]) else 48.0), float(enemy["radius"]) + 3.0)
		enemy["state"] = "recover"
		enemy["timer"] = maxf(0.8, float(enemy["timer"]))
		enemy["pulse_stun"] = 0.8
		affected.append(str(enemy["id"]))
	for enemy_id: String in affected:
		_damage_enemy(_enemy_index(enemy_id), PULSE_DAMAGE)
	_add_ring(player_position, CYAN, PULSE_RADIUS, 0.55)
	_burst(player_position, CYAN, 28 if not reduced_motion else 6, 235.0)
	_popup(player_position + Vector2(0, -54), "PULSE  •  %d SHOTS CLEARED" % erased if erased > 0 else "REPULSOR PULSE", CYAN)
	if not reduced_motion: _shake = maxf(_shake, 2.5)
	combat_cue.emit("pulse", 1.0)
	queue_redraw()
	return true

func celebrate(kind: String) -> void:
	_celebration = 1.0
	_celebration_color = LIME if kind in ["bonus", "redemption", "correct"] else CYAN
	if kind in ["boss", "victory"]: _celebration_color = ORANGE
	_burst(player_position, _celebration_color, 36 if not reduced_motion else 10, 200.0)
	if not reduced_motion: _shake = 3.0
	queue_redraw()

func _on_resized() -> void:
	release_steering()
	if _initialized and _last_size.x > 0.0 and _last_size.y > 0.0:
		var factor := size / _last_size
		player_position = _clamp_position(player_position * factor, 24.0)
		for enemy: Dictionary in _enemies:
			enemy["pos"] = _clamp_position((enemy["pos"] as Vector2) * factor, float(enemy["radius"]))
		for collection in [_bullets, _gems, _particles, _popups]:
			for item: Dictionary in collection:
				if item.has("pos"): item["pos"] = _clamp_position((item["pos"] as Vector2) * factor, 8.0)
		_arcs.clear()
		_rings.clear()
		_ship_trail.clear()
		_last_player_position = player_position
	_last_size = size
	queue_redraw()

func release_steering() -> void:
	_dragging = false
	_touch_index = -1

func _gui_input(event: InputEvent) -> void:
	if not combat_active or not is_processing(): return
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_touch_target = player_position
		elif not event.pressed and event.index == _touch_index: release_steering()
		accept_event()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_touch_target = _clamp_position(_touch_target + event.relative * 1.35, 24.0)
		accept_event()
	elif event is InputEventMouseButton and _touch_index == -1 and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		accept_event()

func _process(delta: float) -> void:
	if not _initialized or size.x < 80.0 or size.y < 80.0: return
	_time += delta
	_orbit_angle = fposmod(_orbit_angle + delta * (1.3 if combat_active else 0.25), TAU)
	_update_effects(delta)
	if combat_active:
		if _resume_remaining > 0.0: _resume_remaining = maxf(0.0, _resume_remaining - delta)
		else: _simulate(minf(delta, 0.04))
	if not reduced_motion and combat_active:
		_shake = move_toward(_shake, 0.0, delta * 24.0)
		_shake_offset = Vector2(_rng.randf_range(-_shake, _shake), _rng.randf_range(-_shake, _shake))
	else: _shake_offset = Vector2.ZERO
	queue_redraw()

func _simulate(delta: float) -> void:
	if not combat_active or _finished: return
	_elapsed += delta
	if _pulse_cooldown > 0.0:
		_pulse_cooldown = maxf(0.0, _pulse_cooldown - delta)
		if _pulse_cooldown <= 0.0:
			combat_cue.emit("pulse_ready", 0.7)
			_popup(player_position + Vector2(0, -44), "PULSE READY", CYAN)
	_streak_remaining = maxf(0.0, _streak_remaining - delta)
	if _streak_remaining <= 0.0: _streak = 0
	_shot_cue_cooldown = maxf(0.0, _shot_cue_cooldown - delta)
	_impact_cue_cooldown = maxf(0.0, _impact_cue_cooldown - delta)
	_invulnerability = maxf(0.0, _invulnerability - delta)
	_move_player(delta)
	if not _question_opened and _elapsed >= float(_config.get("question_at", 4.8)):
		_arrive_target()
		return
	_spawn_cooldown -= delta
	var capacity := mini(MAX_ENEMIES, int(_config.get("max_enemies", 8))) - (0 if _question_opened else 1)
	if _spawn_cooldown <= 0.0 and not _spawn_queue.is_empty() and _enemies.size() < capacity:
		_spawn_cooldown = 0.55
		_spawn_enemy(_spawn_queue.pop_front())
	if _spawn_queue.is_empty() and _ordinary_count() <= 2: _start_packet()
	_update_weapons(delta)
	_update_enemies(delta)
	if not combat_active: return
	_update_bullets(delta)
	if not combat_active: return
	_update_gems(delta)
	var packets: Array = _config.get("packets", [])
	if _target_defeated and _enemies.is_empty() and _spawn_queue.is_empty() and _packet >= packets.size(): _finish(true)

func _move_player(delta: float) -> void:
	_last_player_position = player_position
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): direction.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): direction.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): direction.x += 1.0
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): _dragging = false
	if direction.length_squared() > 0.0: player_position += direction.normalized() * PLAYER_SPEED * delta
	elif _touch_index >= 0: player_position = player_position.move_toward(_touch_target, PLAYER_SPEED * delta)
	elif _dragging: player_position = player_position.move_toward(get_local_mouse_position(), PLAYER_SPEED * delta)
	player_position = _clamp_position(player_position, 24.0)
	_trail_cooldown = maxf(0.0, _trail_cooldown - delta)
	if not reduced_motion and _trail_cooldown <= 0.0 and player_position.distance_squared_to(_last_player_position) > 0.1:
		_trail_cooldown = 0.035
		if _ship_trail.size() >= MAX_TRAIL: _ship_trail.pop_front()
		_ship_trail.append({"pos": player_position, "life": 0.35})

func _start_packet() -> void:
	var packets: Array = _config.get("packets", [])
	if _packet >= packets.size(): return
	for kind in packets[_packet]: _spawn_queue.append(str(kind))
	_packet += 1
	if _packet > 1: _popup(size * Vector2(0.5, 0.22), "REINFORCEMENTS %d / %d" % [_packet, packets.size()], ORANGE)

func _ordinary_count() -> int:
	var count := 0
	for enemy: Dictionary in _enemies:
		if not bool(enemy["target"]): count += 1
	return count

func _spawn_enemy(kind: String) -> void:
	var side := _spawn_rng.randi_range(0, 3)
	var position := Vector2.ZERO
	match side:
		0: position = Vector2(26.0, _spawn_rng.randf_range(35.0, maxf(36.0, size.y - 35.0)))
		1: position = Vector2(size.x - 26.0, _spawn_rng.randf_range(35.0, maxf(36.0, size.y - 35.0)))
		2: position = Vector2(_spawn_rng.randf_range(30.0, maxf(31.0, size.x - 30.0)), 28.0)
		3: position = Vector2(_spawn_rng.randf_range(30.0, maxf(31.0, size.x - 30.0)), size.y - 28.0)
	if position.distance_to(player_position) < minf(185.0, minf(size.x, size.y) * 0.5): position = _clamp_position(size - position, 28.0)
	_spawn_serial += 1
	_add_enemy(position, kind, str(_spawn_serial))

func _add_enemy(position: Vector2, kind: String, enemy_id: String) -> void:
	var target := kind in ["elite", "boss"]
	var radius := 34.0 if kind == "boss" else (25.0 if kind == "elite" else (19.0 if kind == "heavy" else 14.0))
	var health := _target_max_hp if target else float(MOB_HP.get(kind, 8.0)) * float(_config.get("mob_scale", 1.0))
	var speed := {"chaser": 66.0, "runner": 104.0, "shooter": 27.0, "charger": 40.0, "heavy": 41.0, "elite": 120.0, "boss": 155.0, "sniper": 32.0, "miner": 48.0, "splitter": 60.0}
	var movement_speed := float(speed.get(kind, 40.0))
	# Pursuit must be visible even at Level 1; the player can still outrun leaders.
	if kind == "elite": movement_speed += minf(30.0, 3.0 * float(maxi(0, int(_config.get("level", 1)) - 1)))
	_enemies.append({"id": enemy_id, "pos": _clamp_position(position, radius + 3), "kind": kind, "hp": health, "max_hp": health, "radius": radius, "speed": movement_speed, "target": target, "armored": target, "spawn": 0.75, "state": "idle", "timer": 0.3 if target else _spawn_rng.randf_range(0.10, 0.35), "aim": Vector2.DOWN, "phase": _spawn_rng.randf() * TAU, "flash": 0.0, "marked": 0.0, "attack": 0})
	if kind == "boss": _enemies.back().boss_type = _config.get("boss_type", Patterns.boss_for(int(_config.get("level", 5))))

func _arrive_target() -> void:
	_question_opened = true
	_add_enemy(Vector2(size.x * 0.5, maxf(50.0, size.y * 0.17)), "boss" if bool(_config.get("boss", false)) else "elite", "target")
	freeze()
	_popup(size * Vector2(0.5, 0.34), "ARMORED TARGET INBOUND", ORANGE)
	if not _resolved_counter.is_empty():
		apply_counter(_resolved_counter)
		resume_combat()
	else: question_requested.emit()

func _update_weapons(delta: float) -> void:
	_fire_cooldown -= delta
	_turret_cooldown -= delta
	_lightning_cooldown -= delta
	_plasma_cooldown -= delta
	var cadence := clampf(float(_loadout.get("fire_rate", 1.0)), 0.5, 5.0) * clampf(float(_loadout.get("overdrive", 1.0)), 1.0, 1.4)
	var target_index := _nearest_enemy(player_position)
	if target_index < 0: return
	var target: Vector2 = _enemies[target_index]["pos"]
	_aim_angle = (target - player_position).angle()
	if _fire_cooldown <= 0.0:
		_fire_cooldown = 0.19 / cadence
		_fire_bullet(player_position + Vector2.from_angle(_aim_angle) * 22.0, target, false)
	if _turret_cooldown <= 0.0:
		_turret_cooldown = 0.38 / cadence
		for index in range(turret_count + clampi(int(_loadout.get("carrier", 0)), 0, 3)):
			var origin := _turret_position(index)
			var nearest := _nearest_enemy(origin)
			if nearest >= 0: _fire_bullet(origin, _enemies[nearest]["pos"], true, index >= turret_count)
	if lightning_level > 0 and _lightning_cooldown <= 0.0:
		_lightning_cooldown = maxf(0.65, 1.9 - float(lightning_level) * 0.1)
		_chain_lightning()
	if int(_loadout.get("plasma", 0)) > 0 and _plasma_cooldown <= 0.0:
		_plasma_cooldown = 1.1
		_plasma_sweep()

func _active_aims() -> int:
	var total := 0
	for enemy: Dictionary in _enemies:
		if str(enemy["state"]) in ["aim", "locked", "dash"]: total += 1
	return total

func _update_enemies(delta: float) -> void:
	for index in range(_enemies.size() - 1, -1, -1):
		if not combat_active: return
		var enemy: Dictionary = _enemies[index]
		enemy["flash"] = maxf(0.0, float(enemy["flash"]) - delta)
		enemy["marked"] = maxf(0.0, float(enemy["marked"]) - delta)
		enemy.guard_disabled = maxf(0.0, float(enemy.get("guard_disabled", 0)) - delta)
		if float(enemy["spawn"]) > 0.0:
			enemy["spawn"] = maxf(0.0, float(enemy["spawn"]) - delta)
			continue
		if float(enemy.get("pulse_stun", 0.0)) > 0.0:
			enemy["pulse_stun"] = maxf(0.0, float(enemy["pulse_stun"]) - delta)
			continue
		var position: Vector2 = enemy["pos"]
		var kind := str(enemy["kind"])
		# Pursuit is independent of the attack state, including the direction lock.
		# Commit the moved origin before firing so the drawn warning and shot agree.
		if kind == "boss": enemy.enraged = float(enemy.hp) <= float(enemy.max_hp) * 0.5
		if bool(enemy["target"]) and enemy.state != "dash":
			position = _clamp_position(position.move_toward(player_position, float(enemy["speed"]) * delta), float(enemy["radius"]) + 3.0)
			enemy["pos"] = position
		var toward := (player_position - position).normalized()
		var state := str(enemy["state"])
		enemy["timer"] = float(enemy["timer"]) - delta
		var attacking := kind in ["shooter", "charger", "elite", "boss", "sniper", "miner"]
		if attacking:
			if state == "idle" and float(enemy["timer"]) <= 0.0 and _active_aims() < (2 if size.y < 330.0 else 4):
				enemy["state"] = "aim"
				enemy.erase("rush")
				enemy.erase("shot_plan")
				enemy["timer"] = (0.95 if kind == "charger" else (1.1 if kind == "boss" else 0.85))
				if kind == "sniper": enemy.timer = 1.3
				enemy["aim"] = toward
			elif state == "aim":
				enemy["aim"] = toward
				if float(enemy["timer"]) <= 0.0:
					enemy["state"] = "locked"
					enemy["timer"] = 0.2
					enemy.shot_plan = Patterns.shots(enemy, size.y < 330)
					enemy.rush = Patterns.is_rush(enemy)
			elif state == "locked" and float(enemy["timer"]) <= 0.0:
				if bool(enemy.get("rush", Patterns.is_rush(enemy))):
					enemy["state"] = "dash"
					enemy["timer"] = 0.36 if kind == "boss" else 0.3
					enemy.attack = int(enemy.attack) + 1
				else:
					_enemy_fire(enemy)
					enemy["state"] = "recover"
					enemy["timer"] = 0.65 if enemy.get("boss_type", "") == "bulwark" else (0.25 if kind == "shooter" else 0.35)
			elif state == "dash":
				position += (enemy["aim"] as Vector2) * (410.0 if kind == "boss" else 570.0) * delta
				if float(enemy["timer"]) <= 0.0:
					enemy["state"] = "recover"
					enemy["timer"] = 0.65
			elif state == "recover" and float(enemy["timer"]) <= 0.0:
				enemy["state"] = "idle"
				enemy["timer"] = 1.6 if kind == "miner" else 0.55 if kind == "sniper" else 0.15 if kind == "shooter" else float(_config.get("attack_interval", 2.3)) * 0.15
				if enemy.get("enraged", false): enemy.timer *= 0.75
			if not bool(enemy["target"]) and state == "idle":
				var desired_distance := 260.0 if kind == "sniper" else 185.0 if kind in ["shooter", "miner"] else 60.0
				var advance := 1.0 if position.distance_to(player_position) > desired_distance else (-0.6 if position.distance_to(player_position) < desired_distance - 35.0 else 0.0)
				position += toward * float(enemy["speed"]) * advance * delta
		else: position += toward * float(enemy["speed"]) * delta
		enemy["pos"] = _clamp_position(position, float(enemy["radius"]) + 3.0)
		if position.distance_to(player_position) < float(enemy["radius"]) + 12.0:
			_take_hit("CHARGER DASH" if state == "dash" else kind.to_upper() + " COLLISION")
			if combat_active: enemy["pos"] = _clamp_position(position - toward * 36.0, float(enemy["radius"]) + 3.0)

func _enemy_fire(enemy: Dictionary) -> void:
	var position: Vector2 = enemy["pos"]
	var plan: Array = enemy.get("shot_plan", Patterns.shots(enemy, size.y < 330))
	for shot: Dictionary in plan:
		var direction: Vector2 = shot.direction
		_add_hostile_bullet(position + direction * float(shot.get("offset", 0)), direction, String(shot.cause), float(shot.speed), float(shot.get("arming", 0)))
	enemy.erase("shot_plan")
	enemy.attack = int(enemy.attack) + 1
	if enemy.get("boss_type", "") == "brood" and enemy.get("enraged", false) and not enemy.get("summoned", false):
		enemy.summoned = true
		_spawn_queue.append_array(["runner", "heavy"])
		_popup(position + Vector2(0,-55), "ESCORT WAVE / ONE CALL", LIME)

func _fire_bullet(origin: Vector2, target: Vector2, from_turret: bool, support: bool = false) -> void:
	if _bullet_count(false) >= MAX_FRIENDLY: return
	if not from_turret:
		_muzzle_flash = 0.065
		if _shot_cue_cooldown <= 0.0:
			_shot_cue_cooldown = 0.14
			combat_cue.emit("shot", 0.35)
	var direction := (target - origin).normalized()
	var tint := LIME if from_turret else CYAN
	if int(_loadout.get("ricochet", 0)) > 0: tint = ORANGE
	var damage := clampf(float(_loadout.get("damage", 2.0)), 1.0, 100.0) * (0.65 if support else 1.0)
	_bullets.append({"pos": _clamp_position(origin, 4.0), "previous": origin, "velocity": direction * 620.0, "life": 2.4, "damage": damage, "color": tint, "hostile": false, "bounces": mini(3, int(_loadout.get("ricochet", 0))), "visited": [], "conductive": lightning_level > 0 and (not support or int(_loadout.get("ricochet", 0)) == 0), "plasma": support and int(_loadout.get("ricochet", 0)) == 0 and lightning_level == 0 and int(_loadout.get("plasma", 0)) > 0})

func _add_hostile_bullet(origin: Vector2, direction: Vector2, cause: String = "HOSTILE FIRE", speed_multiplier: float = 1.0, arming: float = 0.0) -> void:
	if _bullet_count(true) >= MAX_HOSTILE: return
	_bullets.append({"pos": _clamp_position(origin + direction * 20.0, 8.0), "previous": origin, "velocity": direction * minf(420.0, float(_config.get("projectile_speed", 160.0)) * speed_multiplier), "life": 5.0, "color": ORANGE if arming > 0 else PINK, "hostile": true, "cause": cause, "arming": arming, "mine": speed_multiplier == 0.0})

func _bullet_count(hostile: bool) -> int:
	var total := 0
	for bullet: Dictionary in _bullets:
		if bool(bullet["hostile"]) == hostile: total += 1
	return total

func _update_bullets(delta: float) -> void:
	for index in range(_bullets.size() - 1, -1, -1):
		if not combat_active: return
		var bullet: Dictionary = _bullets[index]
		var previous: Vector2 = bullet["pos"]
		var position := previous + (bullet["velocity"] as Vector2) * delta
		bullet["previous"] = previous
		bullet["pos"] = position
		bullet["life"] = float(bullet["life"]) - delta
		if float(bullet["life"]) <= 0.0 or not Rect2(Vector2(-12, -12), size + Vector2(24, 24)).has_point(position):
			_bullets.remove_at(index)
			continue
		if bool(bullet["hostile"]):
			if float(bullet.get("arming", 0)) > 0:
				bullet.arming = maxf(0.0, float(bullet.arming) - delta)
				continue
			if Geometry2D.get_closest_point_to_segment(player_position, previous, position).distance_to(player_position) < 17.0:
				_bullets.remove_at(index)
				_take_hit(str(bullet["cause"]))
			continue
		for enemy_index in range(_enemies.size() - 1, -1, -1):
			var enemy: Dictionary = _enemies[enemy_index]
			if float(enemy["spawn"]) > 0 or bool(enemy["armored"]) or (bullet["visited"] as Array).has(enemy["id"]): continue
			var enemy_position: Vector2 = enemy["pos"]
			if Geometry2D.get_closest_point_to_segment(enemy_position, previous, position).distance_to(enemy_position) >= float(enemy["radius"]) + 4.0: continue
			(bullet["visited"] as Array).append(enemy["id"])
			if int(bullet["bounces"]) > 0 or bool(bullet.get("conductive", false)): enemy["marked"] = 3.0
			_damage_enemy(enemy_index, float(bullet["damage"]))
			if bool(bullet.get("plasma", false)):
				_burst(enemy_position, PURPLE, 6 if not reduced_motion else 2, 80.0)
				var splash := _nearest_enemy(enemy_position, 60.0, bullet["visited"])
				if splash >= 0: _damage_enemy(splash, float(bullet["damage"]) * 0.5)
			var next := _nearest_enemy(enemy_position, 250.0, bullet["visited"])
			if int(bullet["bounces"]) > 0 and next >= 0:
				bullet["bounces"] = int(bullet["bounces"]) - 1
				bullet["pos"] = enemy_position
				bullet["velocity"] = ((_enemies[next]["pos"] as Vector2) - enemy_position).normalized() * 620.0
				bullet["damage"] = float(bullet["damage"]) * 0.78
				_arcs.append({"from": enemy_position, "to": _enemies[next]["pos"], "life": 0.12, "seed": 0.0})
			else: _bullets.remove_at(index)
			break

func _nearest_enemy(origin: Vector2, maximum: float = 99999.0, excluded: Array = []) -> int:
	var result := -1
	var best := maximum * maximum
	for index in range(_enemies.size()):
		var enemy: Dictionary = _enemies[index]
		if float(enemy["spawn"]) > 0.0 or bool(enemy["armored"]) or excluded.has(enemy["id"]): continue
		var distance := origin.distance_squared_to(enemy["pos"])
		if distance < best:
			best = distance
			result = index
	return result

func _target_index() -> int:
	return _enemy_index("target")

func _enemy_index(enemy_id: String) -> int:
	for index in range(_enemies.size()):
		if str(_enemies[index]["id"]) == enemy_id: return index
	return -1

func _chain_lightning() -> void:
	var origin := player_position
	var visited: Array[String] = []
	var targets: Array[String] = []
	var energized := false
	for hop in range(mini(6, lightning_level + 2)):
		var index := _nearest_enemy(origin, 270.0 if hop == 0 else (250.0 if energized else 165.0), visited)
		if index < 0: break
		var enemy: Dictionary = _enemies[index]
		var target: Vector2 = enemy["pos"]
		energized = float(enemy["marked"]) > 0.0
		_arcs.append({"from": origin, "to": target, "life": 0.23, "seed": _rng.randf() * 8.0})
		visited.append(str(enemy["id"]))
		targets.append(str(enemy["id"]))
		origin = target
	for enemy_id: String in targets:
		var index := _enemy_index(enemy_id)
		if index >= 0:
			var marked := float(_enemies[index]["marked"]) > 0.0
			_damage_enemy(index, (2.0 + float(lightning_level) * 0.7) * (1.5 if marked else 1.0))

func _plasma_sweep() -> void:
	var rank := mini(12, int(_loadout.get("plasma", 0)))
	var targets: Array[String] = []
	for enemy: Dictionary in _enemies:
		var offset := (enemy["pos"] as Vector2) - player_position
		if offset.length() < 150.0 and absf(angle_difference(_orbit_angle, offset.angle())) < 1.35: targets.append(str(enemy["id"]))
	for enemy_id: String in targets:
		var index := _enemy_index(enemy_id)
		if index >= 0: _damage_enemy(index, 5.0 + float(rank) * 1.2)
	_arcs.append({"from": player_position + Vector2.from_angle(_orbit_angle - 1.1) * 100.0, "to": player_position + Vector2.from_angle(_orbit_angle + 1.1) * 100.0, "life": 0.35, "seed": 4.0})

func _damage_enemy(index: int, amount: float) -> void:
	if index < 0 or index >= _enemies.size(): return
	var enemy: Dictionary = _enemies[index]
	if bool(enemy["armored"]) or float(enemy["spawn"]) > 0.0: return
	if Patterns.shielded(enemy): amount *= 0.55
	enemy["hp"] = float(enemy["hp"]) - amount
	enemy["flash"] = 0.1
	var position: Vector2 = enemy["pos"]
	if _impact_cue_cooldown <= 0.0:
		_impact_cue_cooldown = 0.10
		combat_cue.emit("impact", 0.35)
	if float(enemy["hp"]) > 0.0:
		_burst(position, _enemy_color(str(enemy["kind"])), 2 if not reduced_motion else 0, 65.0)
		return
	var target := bool(enemy["target"])
	var kind := str(enemy["kind"])
	var enemy_id := str(enemy["id"])
	_enemies.remove_at(index)
	if kind == "splitter":
		for side in [-1.0, 1.0]:
			if _enemies.size() >= mini(MAX_ENEMIES, int(_config.get("max_enemies", MAX_ENEMIES))) - (0 if _question_opened else 1): break
			_spawn_serial += 1
			_add_enemy(position + Vector2(side * 28.0, 0), "runner", "%s/split/%d" % [enemy_id, _spawn_serial])
	_kills += 1
	_streak += 1
	_streak_remaining = 3.5
	_add_ring(position, _enemy_color(kind), 75.0 if target else 32.0, 0.42 if target else 0.25)
	_burst(position, _enemy_color(kind), (32 if target else 10) if not reduced_motion else 4, 150.0)
	if _gems.size() < 80: _gems.append({"pos": position, "value": 20 if target else 4, "phase": _rng.randf() * TAU})
	if target:
		_target_defeated = true
		_popup(position, "TARGET DESTROYED", ORANGE)
		celebrate("boss")
	combat_cue.emit("target_destroyed" if target else "kill", 1.0 if target else 0.55)
	# Streaks are feedback only: no extra currency, XP or academic credit.
	if _streak in [3, 5, 8, 12]:
		_popup(player_position + Vector2(0, -60), "%d  •  ON A ROLL" % _streak, LIME)
		combat_cue.emit("streak", minf(1.0, float(_streak) / 8.0))
	if not reduced_motion: _shake = maxf(_shake, 4.5 if target else 1.0)
	enemy_killed.emit(enemy_id, kind)

func _take_hit(cause: String = "COLLISION") -> void:
	if _invulnerability > 0.0 or hull <= 0 or not combat_active: return
	_invulnerability = 1.0
	hull = maxi(0, hull - 1)
	_hits += 1
	_last_attack = cause
	_damage_flash = 0.32
	_streak = 0
	_streak_remaining = 0.0
	_burst(player_position, PINK, 22 if not reduced_motion else 6, 195.0)
	_popup(player_position + Vector2(0, -38), "HULL BREACH" if hull > 0 else "SHIP LOST", PINK)
	if not reduced_motion: _shake = 5.0
	shield_hit.emit()
	if hull <= 0: _finish(false)

func _update_gems(delta: float) -> void:
	for index in range(_gems.size() - 1, -1, -1):
		var gem: Dictionary = _gems[index]
		gem["pos"] = (gem["pos"] as Vector2).move_toward(player_position, 250.0 * delta)
		if (gem["pos"] as Vector2).distance_to(player_position) < 22.0:
			_add_particle(gem["pos"], Vector2(0, -35), LIME, 4.0, 0.25)
			_gems.remove_at(index)

func _finish(victory: bool) -> void:
	if _finished: return
	_finished = true
	_encounter_cleared = victory
	freeze()
	_bullets.clear()
	if victory: celebrate("victory")
	combat_finished.emit({"victory": victory, "hull": hull, "kills": _kills, "coins": _kills * 4, "hits": _hits, "duration": _elapsed, "cause": _last_attack, "boss_defeated": _target_defeated, "boss_wave": bool(_config.get("boss", false))})

func _clamp_position(position: Vector2, padding: float) -> Vector2:
	return Vector2(clampf(position.x, padding, maxf(padding, size.x - padding)), clampf(position.y, padding, maxf(padding, size.y - padding)))

func _turret_position(index: int) -> Vector2:
	var total := turret_count + clampi(int(_loadout.get("carrier", 0)), 0, 3)
	var angle := _orbit_angle + float(index) * TAU / float(maxi(1, total))
	return _clamp_position(player_position + Vector2.from_angle(angle) * (53.0 if index < turret_count else 86.0), 12.0)

func _enemy_color(kind: String) -> Color:
	match kind:
		"heavy": return ORANGE
		"runner": return LIME
		"shooter": return PURPLE
		"charger": return Color("ff754b")
		"sniper": return Color("79ddff")
		"miner": return Color("ffcd75")
		"splitter": return Color("ceff84")
		"elite", "boss": return Color("e490ff")
	return PINK

func _burst(position: Vector2, tint: Color, count: int, speed: float) -> void:
	for i: int in range(count):
		var velocity: Vector2 = Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(speed * 0.2, speed)
		_add_particle(position, velocity, tint, _rng.randf_range(1.5, 4.5), _rng.randf_range(0.2, 0.65))


func _add_particle(position: Vector2, velocity: Vector2, tint: Color, radius: float, life: float) -> void:
	if _particles.size() >= MAX_PARTICLES:
		return
	_particles.append({"pos": position, "velocity": velocity, "color": tint, "radius": radius, "life": life, "max_life": life})


func _popup(position: Vector2, message: String, tint: Color) -> void:
	if _popups.size() >= 10:
		_popups.pop_front()
	_popups.append({"pos": position, "text": message, "color": tint, "life": 1.1})

func _create_glow_texture() -> void:
	# One cached radial texture supplies soft light on the Web Compatibility path.
	# No full-screen bloom buffer or per-projectile Light2D node is needed.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.14, 0.38, 0.68, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.18), Color(1, 1, 1, 0.035), Color(1, 1, 1, 0)])
	_glow_texture = GradientTexture2D.new()
	_glow_texture.gradient = gradient
	_glow_texture.width = 128
	_glow_texture.height = 128
	_glow_texture.fill = GradientTexture2D.FILL_RADIAL
	_glow_texture.fill_from = Vector2(0.5, 0.5)
	_glow_texture.fill_to = Vector2(1.0, 0.5)

func _draw_glow(position: Vector2, radius: float, tint: Color, energy: float = 1.0) -> void:
	if _glow_texture == null: return
	var light := tint
	light.a *= energy
	draw_texture_rect(_glow_texture, Rect2(position - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), false, light)

func _add_ring(position: Vector2, tint: Color, radius: float, life: float) -> void:
	if _rings.size() >= MAX_RINGS: _rings.pop_front()
	_rings.append({"pos": position, "color": tint, "radius": radius, "life": life, "max_life": life})

func _draw_rings() -> void:
	for ring: Dictionary in _rings:
		var remaining := clampf(float(ring["life"]) / float(ring["max_life"]), 0.0, 1.0)
		var radius := float(ring["radius"]) * (0.85 if reduced_motion else (1.0 - remaining * remaining))
		var tint: Color = ring["color"]
		tint.a = remaining * (0.25 if reduced_motion else 0.65)
		draw_arc(ring["pos"], maxf(1.0, radius), 0.0, TAU, 40, tint, 2.0 + remaining * 3.0, true)
		if not reduced_motion: _draw_glow(ring["pos"], maxf(8.0, radius * 0.6), tint, remaining * 0.5)


func _update_effects(delta: float) -> void:
	_celebration = maxf(0.0, _celebration - delta * 1.4)
	_muzzle_flash = maxf(0.0, _muzzle_flash - delta)
	_damage_flash = maxf(0.0, _damage_flash - delta)
	for index in range(_rings.size() - 1, -1, -1):
		_rings[index]["life"] = float(_rings[index]["life"]) - delta
		if float(_rings[index]["life"]) <= 0.0: _rings.remove_at(index)
	for index in range(_ship_trail.size() - 1, -1, -1):
		_ship_trail[index]["life"] = float(_ship_trail[index]["life"]) - delta
		if float(_ship_trail[index]["life"]) <= 0.0 or reduced_motion: _ship_trail.remove_at(index)
	for i: int in range(_particles.size() - 1, -1, -1):
		var particle: Dictionary = _particles[i]
		particle["life"] = float(particle["life"]) - delta
		if float(particle["life"]) <= 0.0:
			_particles.remove_at(i)
			continue
		var position: Vector2 = particle["pos"]
		var velocity: Vector2 = particle["velocity"]
		particle["pos"] = position + velocity * delta * (0.35 if reduced_motion else 1.0)
		particle["velocity"] = velocity * maxf(0.0, 1.0 - delta * 2.0)
	for i: int in range(_arcs.size() - 1, -1, -1):
		_arcs[i]["life"] = float(_arcs[i]["life"]) - delta
		if float(_arcs[i]["life"]) <= 0.0:
			_arcs.remove_at(i)
	for i: int in range(_popups.size() - 1, -1, -1):
		var popup: Dictionary = _popups[i]
		popup["life"] = float(popup["life"]) - delta
		var position: Vector2 = popup["pos"]
		popup["pos"] = position + Vector2(0.0, -20.0 if not reduced_motion else 0.0) * delta
		if float(popup["life"]) <= 0.0:
			_popups.remove_at(i)


func _draw() -> void:
	if size.x < 1.0 or size.y < 1.0: return
	_draw_background()
	if not _initialized: return
	draw_set_transform(_shake_offset)
	for enemy: Dictionary in _enemies: _draw_telegraph(enemy)
	_draw_rings()
	if not reduced_motion:
		for index in range(1, _ship_trail.size()):
			var trail_alpha := float(_ship_trail[index]["life"]) / 0.35
			draw_line(_ship_trail[index - 1]["pos"], _ship_trail[index]["pos"], Color(CYAN, trail_alpha * 0.22), 12.0, true)
	for gem: Dictionary in _gems:
		var point: Vector2 = gem["pos"]
		_draw_glow(point, 15.0, LIME, 0.55)
		draw_colored_polygon(PackedVector2Array([point + Vector2(0, -5), point + Vector2(3.5, 0), point + Vector2(0, 5), point + Vector2(-3.5, 0)]), LIME)
	for enemy: Dictionary in _enemies: _draw_enemy(enemy)
	draw_set_transform(_shake_offset)
	for bullet: Dictionary in _bullets: _draw_bullet(bullet)
	for arc: Dictionary in _arcs: _draw_arc(arc)
	if int(_loadout.get("plasma", 0)) > 0:
		draw_arc(player_position, 106.0, _orbit_angle - 1.2, _orbit_angle + 1.2, 32, Color(0.67, 0.43, 1.0, 0.55), 7.0, true)
	_draw_player()
	draw_set_transform(_shake_offset)
	for particle: Dictionary in _particles:
		var tint: Color = particle["color"]
		tint.a = clampf(float(particle["life"]) / float(particle["max_life"]), 0.0, 1.0)
		var spark_position: Vector2 = particle["pos"]
		var spark_tail: Vector2 = (particle["velocity"] as Vector2) * (0.0 if reduced_motion else 0.035)
		draw_line(spark_position - spark_tail, spark_position, tint, maxf(1.0, float(particle["radius"]) * 0.65), true)
		draw_circle(spark_position, float(particle["radius"]) * 0.48, Color(1.0, 1.0, 1.0, tint.a))
	if _celebration > 0.0:
		var tint := _celebration_color
		tint.a = _celebration * 0.6
		draw_arc(player_position, 65.0 + (1.0 - _celebration) * (220.0 if not reduced_motion else 25.0), 0.0, TAU, 64, tint, 3.0, true)
	var font := ThemeDB.fallback_font
	for popup: Dictionary in _popups:
		var tint: Color = popup["color"]
		tint.a = minf(1.0, float(popup["life"]) * 2.0)
		var message := str(popup["text"])
		var width := font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var position: Vector2 = popup["pos"] - Vector2(width * 0.5, 0)
		draw_string_outline(font, position, message, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, NAVY)
		draw_string(font, position, message, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, tint)
	if _resume_remaining > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.14, 0.22, 0.20))
		draw_arc(player_position, 45.0, -PI / 2, -PI / 2 + TAU * _resume_remaining / 0.6, 40, CYAN, 4.0, true)
	draw_set_transform(Vector2.ZERO)
	if _damage_flash > 0.0:
		# Border feedback keeps the center and projectile lanes unobscured.
		draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color(PINK, _damage_flash * (0.8 if reduced_motion else 1.8)), false, 5.0)

func _draw_telegraph(enemy: Dictionary) -> void:
	var position: Vector2 = enemy["pos"]
	var radius := float(enemy["radius"])
	var state := str(enemy["state"])
	var kind := str(enemy["kind"])
	var tint := _enemy_color(kind)
	if float(enemy["spawn"]) > 0.0:
		_draw_glow(position, radius * 2.8, tint, 0.28)
		draw_arc(position, radius + 14.0, 0.0, TAU, 32, Color(tint.r, tint.g, tint.b, 0.5), 2.0, true)
		for angle in [0.0, PI / 2, PI, PI * 1.5]:
			draw_line(position + Vector2.from_angle(angle) * (radius + 8), position + Vector2.from_angle(angle) * (radius + 20), tint, 2.0)
	if float(enemy.get("pulse_stun", 0.0)) > 0.0:
		draw_arc(position, radius + 6.0, 0.0, TAU, 24, CYAN, 1.5, true)
		return
	if state not in ["aim", "locked", "dash"]: return
	var direction: Vector2 = enemy["aim"]
	var locked := state != "aim"
	var alpha := 0.7 if locked else 0.25
	var endpoint := position + direction * (220.0 if kind == "charger" else maxf(size.x, size.y))
	if kind == "charger" or (kind == "boss" and bool(enemy.get("rush", Patterns.is_rush(enemy)))):
		draw_line(position, endpoint, Color(tint.r, tint.g, tint.b, 0.13), radius * 1.8, true)
		draw_line(position, endpoint, Color(tint.r, tint.g, tint.b, alpha), 3.0, true)
	else:
		var plan: Array = enemy.get("shot_plan", Patterns.shots(enemy, size.y < 330))
		for shot: Dictionary in plan:
			var lane: Vector2 = shot.direction
			if float(shot.get("arming", 0)) > 0:
				draw_arc(_clamp_position(position + lane * (float(shot.get("offset", 0)) + 20), 8), 19, 0, TAU, 24, ORANGE, 2, true)
			else: draw_line(position, position + lane * maxf(size.x, size.y), Color(tint.r, tint.g, tint.b, alpha), 2.0, true)
	draw_arc(position, radius + 6.0, 0, TAU, 32, tint, 3.0 if locked else 1.0, true)

func _draw_enemy(enemy: Dictionary) -> void:
	var position: Vector2 = enemy["pos"]
	var kind := str(enemy["kind"])
	var radius := float(enemy["radius"])
	var tint := Patterns.tint(String(enemy.get("boss_type", "lancer"))) if kind == "boss" else _enemy_color(kind)
	var angle := (player_position - position).angle()
	var target := bool(enemy["target"])
	var alpha := 0.35 if float(enemy["spawn"]) > 0.0 else 1.0
	draw_set_transform(_shake_offset)
	_draw_glow(position + Vector2(4, 8), radius * 1.45, Color(0, 0, 0, 0.8), alpha)
	_draw_glow(position, radius * (3.1 if target else 2.2), tint, (0.28 if target else 0.17) * alpha)
	draw_set_transform(position + _shake_offset, angle)
	var points := PackedVector2Array()
	# Each threat has its own silhouette as well as a color.
	match kind:
		"boss", "sniper", "miner", "splitter": points = Patterns.silhouette(String(enemy.get("boss_type", "lancer")) if kind == "boss" else kind)
		"runner": points = PackedVector2Array([Vector2(1, 0), Vector2(-0.85, -0.72), Vector2(-0.34, 0), Vector2(-0.85, 0.72)])
		"charger": points = PackedVector2Array([Vector2(1, 0), Vector2(0.3, -0.48), Vector2(0.1, -1), Vector2(-0.9, -0.7), Vector2(-0.52, 0), Vector2(-0.9, 0.7), Vector2(0.1, 1), Vector2(0.3, 0.48)])
		"chaser": points = PackedVector2Array([Vector2(1, 0), Vector2(-0.5, -0.92), Vector2(-0.28, 0), Vector2(-0.5, 0.92)])
		_:
			var sides := 8 if kind in ["heavy", "boss"] else 6
			for index in range(sides): points.append(Vector2.from_angle(float(index) * TAU / float(sides)))
	for index in range(points.size()): points[index] *= radius
	var fill := Color(tint.r * 0.17 + 0.03, tint.g * 0.17 + 0.03, tint.b * 0.20 + 0.06, alpha)
	if float(enemy["flash"]) > 0.0: fill = Color(0.8, 0.93, 1.0, alpha)
	draw_colored_polygon(points, fill)
	# Directional metal facets give the hull depth without blurring its edge.
	for index in range(points.size()):
		var next := (index + 1) % points.size()
		var shade := 0.16 if points[index].y < 0.0 else 0.055
		draw_colored_polygon(PackedVector2Array([points[index], points[next], points[next] * 0.57, points[index] * 0.57]), Color(tint, shade * alpha))
	points.append(points[0])
	tint.a = alpha
	draw_polyline(points, tint, 2.0, true)
	if kind in ["shooter", "elite", "boss", "sniper"]:
		var orbit := 0.0 if reduced_motion else _time * (0.32 if target else -0.7) + float(enemy["phase"])
		for segment in range(3):
			var start := orbit + float(segment) * TAU / 3.0
			draw_arc(Vector2.ZERO, radius * 0.66, start, start + 1.5, 12, Color(tint, 0.65), 2.0, true)
		draw_rect(Rect2(radius * 0.40, -4, radius * 0.78, 8), Color("17283e"))
		draw_line(Vector2(radius * 0.4, -3), Vector2(radius * 1.18, -3), tint, 1.5)
		draw_line(Vector2(radius * 0.4, 3), Vector2(radius * 1.18, 3), tint, 1.5)
		if target:
			for side in [-1.0, 1.0]:
				var pod := Vector2(-radius * 0.1, radius * float(side) * 0.72)
				draw_rect(Rect2(pod - Vector2(8, 4), Vector2(16, 8)), Color("302346"))
				draw_line(pod - Vector2(7, 0), pod + Vector2(7, 0), tint, 2.0)
				_draw_glow(pod - Vector2(10, 0), 17.0, tint, 0.75)
	elif kind == "heavy":
		for plate in [-1.0, 1.0]:
			draw_rect(Rect2(-radius * 0.6, float(plate) * radius * 0.48 - 3, radius * 1.2, 6), Color(tint, 0.65))
		draw_arc(Vector2.ZERO, radius * 0.42, 0.0, TAU, 16, tint, 3.0, true)
	else:
		draw_line(Vector2(-radius * 0.35, -radius * 0.4), Vector2(radius * 0.5, 0), tint, 2.5)
		draw_line(Vector2(-radius * 0.35, radius * 0.4), Vector2(radius * 0.5, 0), tint, 2.5)
		if kind == "runner":
			draw_line(Vector2(-radius * 0.9, -radius * 0.3), Vector2(-radius * 1.2, -radius * 0.3), tint, 2.0)
			draw_line(Vector2(-radius * 0.9, radius * 0.3), Vector2(-radius * 1.2, radius * 0.3), tint, 2.0)
	_draw_glow(Vector2.ZERO, radius * 0.62, tint, 0.65)
	draw_circle(Vector2.ZERO, radius * 0.14, Color(0.95, 0.92, 1.0, alpha))
	if str(enemy["state"]) in ["aim", "locked"]:
		_draw_glow(Vector2(radius, 0), radius, tint, 0.8 if str(enemy["state"]) == "locked" else 0.35)
	if bool(enemy["armored"]):
		for segment in range(6):
			draw_arc(Vector2.ZERO, radius + 9.0, float(segment) * TAU / 6 + 0.07, float(segment + 1) * TAU / 6 - 0.07, 9, CYAN, 4.0, true)
	elif Patterns.shielded(enemy):
		draw_arc(Vector2.ZERO, radius + 8, 0, TAU, 40, Color("7abfff"), 4, true)
	if enemy.get("enraged", false): draw_arc(Vector2.ZERO, radius + 13, 0.2, 5.9, 40, PINK, 1.5, true)
	if float(enemy["marked"]) > 0.0: draw_arc(Vector2.ZERO, radius + 5, 0, TAU, 24, LIME, 1.5, true)
	draw_set_transform(_shake_offset)
	if target:
		# Four brackets stay upright, so the objective remains readable in a crowd.
		for quadrant in range(4):
			var corner_angle := PI / 4.0 + float(quadrant) * PI / 2.0
			var corner := position + Vector2.from_angle(corner_angle) * (radius + 17.0)
			var toward_center := (position - corner).sign()
			draw_line(corner, corner + Vector2(toward_center.x * 7.0, 0), ORANGE, 2.0)
			draw_line(corner, corner + Vector2(0, toward_center.y * 7.0), ORANGE, 2.0)
	if target or float(enemy["hp"]) < float(enemy["max_hp"]):
		var bar_width := 90.0 if target else radius * 2
		var start := position + Vector2(-bar_width * 0.5, -radius - 16)
		draw_rect(Rect2(start - Vector2(1, 1), Vector2(bar_width + 2, 6)), Color(0.03, 0.04, 0.09, 0.9))
		draw_rect(Rect2(start, Vector2(bar_width * clampf(float(enemy["hp"]) / float(enemy["max_hp"]), 0, 1), 4)), CYAN if bool(enemy["armored"]) else tint)

func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), NAVY)
	var palette: Array[Color] = [CYAN, PURPLE, ORANGE, Color("61efb1"), PINK]
	var sector_color: Color = palette[posmod(int(_config.get("level", 1)) - 1, palette.size())]
	var parallax := Vector2.ZERO if reduced_motion else (player_position - size * 0.5) * 0.025
	if _background != null:
		var tex_size: Vector2 = _background.get_size()
		var aspect: float = maxf((size.x + 32.0) / tex_size.x, (size.y + 32.0) / tex_size.y)
		var display_size: Vector2 = tex_size * aspect
		draw_texture_rect(_background, Rect2((size - display_size) * 0.5 - parallax, display_size), false, Color(0.60, 0.67, 0.85, 0.74))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.012, 0.025, 0.065, 0.58))
	else:
		draw_circle(size * Vector2(0.22, 0.24), size.x * 0.39, Color(0.06, 0.10, 0.24, 0.28))
		draw_circle(size * Vector2(0.88, 0.77), size.x * 0.33, Color(0.14, 0.06, 0.23, 0.20))
	_draw_glow(size * Vector2(0.12, 0.25) - parallax, maxf(size.x, size.y) * 0.68, sector_color, 0.24)
	_draw_glow(size * Vector2(0.9, 0.76) + parallax, maxf(size.x, size.y) * 0.5, PURPLE, 0.19)
	# Distant orbital architecture anchors the arena in a spaceport.
	var station := size * Vector2(0.82, 0.13) - parallax * 0.55
	var station_radius := minf(size.x, size.y) * 0.28
	draw_arc(station, station_radius, -0.8, 3.8, 56, Color(sector_color, 0.055), 17.0, true)
	draw_arc(station, station_radius + 15.0, -0.5, 3.3, 56, Color(sector_color, 0.12), 1.0, true)
	for panel in range(12):
		var a := float(panel) * TAU / 12.0
		draw_line(station + Vector2.from_angle(a) * (station_radius - 8.0), station + Vector2.from_angle(a) * (station_radius + 8.0), Color(sector_color, 0.10), 3.0)
	for x: int in range(0, int(size.x), 74):
		draw_line(Vector2(float(x), 0.0), Vector2(float(x), size.y), Color(0.18, 0.40, 0.57, 0.045), 1.0)
	for y: int in range(0, int(size.y), 74):
		draw_line(Vector2(0.0, float(y)), Vector2(size.x, float(y)), Color(0.18, 0.40, 0.57, 0.045), 1.0)
	for i: int in range(68):
		var depth := 0.3 + float(i % 3) * 0.35
		var px: float = fposmod(float(i * 173 + 37), 997.0) / 997.0 * size.x - parallax.x * depth
		var drift := 0.0 if reduced_motion else _time * depth * 0.75
		var py: float = fposmod(fposmod(float(i * 283 + 113), 991.0) / 991.0 * size.y + drift - parallax.y * depth, size.y)
		var alpha: float = 0.20 + float(i % 4) * 0.08
		var star := Vector2(px, py)
		draw_circle(star, 1.25 if i % 5 == 0 else 0.7, Color(0.70, 0.85, 1.0, alpha))
		if i % 13 == 0:
			_draw_glow(star, 9.0, CYAN, 0.32)
			draw_line(star - Vector2(3, 0), star + Vector2(3, 0), Color(0.7, 0.9, 1, 0.22), 1.0)
	# Dark edge rails create depth and keep the play boundary clear.
	draw_rect(Rect2(0, 0, 6, size.y), Color(0.01, 0.025, 0.05, 0.65))
	draw_rect(Rect2(size.x - 6, 0, 6, size.y), Color(0.01, 0.025, 0.05, 0.65))
	var corner_color: Color = Color(0.28, 0.88, 0.97, 0.48)
	for corner: Vector2 in [Vector2(10.0, 10.0), Vector2(size.x - 10.0, 10.0), Vector2(10.0, size.y - 10.0), size - Vector2(10.0, 10.0)]:
		var direction: Vector2 = Vector2(1.0 if corner.x < size.x * 0.5 else -1.0, 1.0 if corner.y < size.y * 0.5 else -1.0)
		draw_line(corner, corner + Vector2(direction.x * 24.0, 0.0), corner_color, 2.0)
		draw_line(corner, corner + Vector2(0.0, direction.y * 24.0), corner_color, 2.0)


func _draw_bullet(bullet: Dictionary) -> void:
	var position: Vector2 = bullet["pos"]
	var velocity: Vector2 = bullet["velocity"]
	var tint: Color = bullet["color"]
	var hostile: bool = bool(bullet["hostile"])
	if hostile:
		if bullet.get("mine", false):
			var armed := float(bullet.get("arming", 0)) <= 0
			draw_arc(position, 17 if not armed else 10, 0, TAU, 24, Color(ORANGE, 0.45 if not armed else 1.0), 2, true)
			draw_line(position - Vector2(7,7), position + Vector2(7,7), ORANGE, 2, true)
			draw_line(position - Vector2(7,-7), position + Vector2(7,-7), ORANGE, 2, true)
			return
		var tail := position - velocity.normalized() * 12.0
		_draw_glow(position, 19.0, tint, 0.8)
		draw_line(tail, position, Color(tint, 0.4), 4.0, true)
		draw_circle(position, 6.3, Color("260d25"))
		draw_arc(position, 5.3, 0.0, TAU, 16, tint, 2.3, true)
		draw_circle(position, 2.6, Color("fff1d8"))
	else:
		var power := clampf(float(bullet.get("damage", 2.0)), 1.0, 12.0)
		var tail: Vector2 = position - velocity.normalized() * (15.0 + power * 1.1)
		draw_line(tail, position, Color(tint.r, tint.g, tint.b, 0.10), 12.0, true)
		_draw_glow(position, 15.0, tint, 0.55)
		draw_line(tail, position, tint, 2.3 + power * 0.25, true)
		draw_line(position - velocity.normalized() * 7.0, position, Color(1.0, 1.0, 1.0, 0.9), 1.8, true)


func _draw_arc(arc: Dictionary) -> void:
	var start: Vector2 = arc["from"]
	var end: Vector2 = arc["to"]
	var perpendicular: Vector2 = (end - start).normalized().orthogonal()
	var points: PackedVector2Array = PackedVector2Array([start])
	for i: int in range(1, 6):
		var offset: float = sin(float(i) * 2.8 + float(arc["seed"])) * 11.0
		points.append(start.lerp(end, float(i) / 6.0) + perpendicular * offset)
	points.append(end)
	var alpha: float = clampf(float(arc["life"]) / 0.23, 0.0, 1.0)
	draw_polyline(points, Color(0.64, 0.40, 1.0, alpha * 0.20), 12.0, true)
	draw_polyline(points, Color(0.75, 0.61, 1.0, alpha), 3.0, true)
	draw_polyline(points, Color(0.92, 0.91, 1.0, alpha), 1.0, true)


func _draw_player() -> void:
	draw_set_transform(_shake_offset)
	var shield_tint: Color = ORANGE if overdrive_enabled else CYAN
	_draw_glow(player_position, 105.0, shield_tint, 0.24)
	_draw_glow(player_position + Vector2(4, 9), 37.0, Color(0, 0, 0, 0.7))
	draw_arc(player_position, 33.0, 0.0, TAU, 40, Color(shield_tint.r, shield_tint.g, shield_tint.b, 0.25), 1.0, true)
	if not _config.is_empty():
		var charge := clampf(1.0 - _pulse_cooldown / PULSE_COOLDOWN, 0.0, 1.0)
		draw_arc(player_position, 42.0, -PI / 2.0, -PI / 2.0 + maxf(0.001, TAU * charge), 48, Color(CYAN, 0.62 if charge >= 1.0 else 0.26), 2.0, true)
	if _invulnerability > 0.0 and combat_active:
		_draw_glow(player_position, 58.0, CYAN, 0.25)
		draw_arc(player_position, 36.0, 0.0, TAU, 40, Color(0.40, 0.94, 1.0, 0.7), 2.5, true)
	if turret_count > 0:
		draw_arc(player_position, 54.0, 0.0, TAU, 64, Color(0.50, 0.95, 0.65, 0.17), 1.0, true)
	if int(_loadout.get("carrier", 0)) > 0:
		draw_arc(player_position, 86.0, 0.0, TAU, 64, Color(0.70, 0.45, 1.0, 0.25), 1.5, true)
		for panel in range(4):
			var point := player_position + Vector2.from_angle(float(panel) * PI / 2 + PI / 4) * 30.0
			draw_circle(point, 6.0, Color("60499d"))
	for i: int in range(turret_count + clampi(int(_loadout.get("carrier", 0)), 0, 3)):
		var position: Vector2 = _turret_position(i)
		var turret_tint := LIME if i < turret_count else PURPLE
		draw_set_transform(_shake_offset)
		draw_line(player_position, position, Color(turret_tint, 0.08), 1.0)
		var turret_angle: float = _aim_angle
		var nearest: int = _nearest_enemy(position)
		if nearest >= 0:
			var target: Vector2 = _enemies[nearest]["pos"]
			turret_angle = (target - position).angle()
		draw_set_transform(position + _shake_offset, turret_angle)
		_draw_glow(Vector2.ZERO, 28.0, turret_tint, 0.4)
		draw_circle(Vector2.ZERO, 10.0, Color("12253a"))
		draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 20, turret_tint, 1.6, true)
		draw_arc(Vector2.ZERO, 6.0, 1.2, 5.0, 16, Color(turret_tint, 0.4), 2.0, true)
		draw_rect(Rect2(4.0, -3.0, 12.0, 6.0), Color("395660"))
		draw_line(Vector2(6, 0), Vector2(17, 0), turret_tint, 2.0)
		draw_circle(Vector2.ZERO, 3.0, Color.WHITE)
	draw_set_transform(player_position + _shake_offset, _aim_angle + PI / 2.0)
	var flame_length: float = 12.0 if reduced_motion else 12.0 + sin(_time * 28.0) * 4.0
	var moving := player_position.distance_squared_to(_last_player_position) > 0.1
	if moving and not reduced_motion: flame_length += 11.0
	_draw_glow(Vector2(0, 25), 44.0, shield_tint, 0.7)
	draw_colored_polygon(PackedVector2Array([Vector2(-7.0, 14.0), Vector2(0.0, 22.0 + flame_length), Vector2(7.0, 14.0)]), Color(0.28, 0.91, 1.0, 0.5))
	draw_colored_polygon(PackedVector2Array([Vector2(-3.0, 14.0), Vector2(0.0, 23.0), Vector2(3.0, 14.0)]), Color.WHITE)
	if _ship != null:
		draw_texture_rect(_ship, Rect2(-29.0, -29.0, 58.0, 58.0), false)
	else:
		var ship_points: PackedVector2Array = PackedVector2Array([Vector2(0.0, -26.0), Vector2(20.0, 18.0), Vector2(6.0, 12.0), Vector2(0.0, 17.0), Vector2(-6.0, 12.0), Vector2(-20.0, 18.0)])
		draw_colored_polygon(ship_points, Color("b4eef7"))
		ship_points.append(ship_points[0])
		draw_polyline(ship_points, CYAN, 2.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(0.0, -15.0), Vector2(6.0, 8.0), Vector2(-6.0, 8.0)]), Color("13375b"))
		draw_line(Vector2(0.0, -9.0), Vector2(0.0, 4.0), CYAN, 3.0)
	if _muzzle_flash > 0.0 and not reduced_motion:
		_draw_glow(Vector2(0, -26), 26.0, CYAN, _muzzle_flash / 0.065)
		draw_line(Vector2(0, -22), Vector2(0, -34), Color(0.9, 1, 1, _muzzle_flash / 0.065), 3.0, true)
	draw_set_transform(_shake_offset)
