extends SceneTree
## Real enemy simulation: pursuit, dodge windows, collisions and pause boundaries.
const Arena = preload("res://scripts/arena.gd")
const Director = preload("res://scripts/encounter_director.gd")
var arena
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run_tests")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func fixture(kind: String, state: String = "idle", viewport: Vector2 = Vector2(700, 600)) -> Dictionary:
	arena.size = viewport
	var config: Dictionary = Director.config_for(5 if kind == "boss" else 1, 771)
	config.packets = []
	config.question_at = 99999.0
	arena.launch_encounter(config, {"turrets": 1, "damage": 2.0}, 3)
	arena._enemies.clear()
	arena._spawn_queue.clear()
	arena._invulnerability = 999.0
	arena._fire_cooldown = 99999.0
	arena._turret_cooldown = 99999.0
	arena.player_position = Vector2(viewport.x * 0.70, viewport.y * 0.75)
	arena._add_enemy(Vector2(viewport.x * 0.25, viewport.y * 0.25), kind, "target")
	var enemy: Dictionary = arena._enemies.back()
	enemy.spawn = 0.0
	enemy.state = state
	enemy.timer = 20.0
	enemy.aim = (arena.player_position - enemy.pos).normalized()
	return enemy

func run_tests() -> void:
	arena = Arena.new()
	arena.size = Vector2(700, 600)
	root.add_child(arena)
	await process_frame
	arena.set_process(false)
	for kind in ["elite", "boss"]:
		for state in ["idle", "aim", "locked", "recover"]:
			var enemy := fixture(kind, state)
			var before: Vector2 = enemy.pos
			var distance := before.distance_to(arena.player_position)
			arena._update_enemies(0.1)
			check(enemy.pos.distance_to(arena.player_position) < distance, "%s pursues during %s" % [kind, state])
			check(is_equal_approx(before.distance_to(enemy.pos), float(enemy.speed) * 0.1), "Pursuit uses its real speed cap")
			check(float(enemy.speed) >= 120.0 and float(enemy.speed) < Arena.PLAYER_SPEED, "Pursuit is obvious from Level 1 and can be outrun")
		var enemy := fixture(kind, "recover")
		enemy.pos = Vector2(300, 300)
		arena.player_position = Vector2(470, 300)
		arena._update_enemies(0.1)
		check(enemy.pos.x > 300.0, "Leader closes through the former 145-180px parking band")
		var before: Vector2 = enemy.pos
		arena.player_position = Vector2(130, 300)
		arena._update_enemies(0.1)
		check(enemy.pos.x < before.x, "Leader retargets immediately when player changes sides")
		enemy = fixture(kind, "locked")
		enemy.timer = 0.12
		before = enemy.pos
		var aim: Vector2 = enemy.aim
		arena.player_position = Vector2(50, 500)
		arena._update_enemies(0.04)
		check(enemy.pos.distance_to(arena.player_position) < before.distance_to(arena.player_position) and enemy.aim == aim, "Direction lock preserves aim without stopping the chase")
		arena._update_enemies(0.1)
		check(enemy.pos.distance_to(arena.player_position) < before.distance_to(arena.player_position) and enemy.state == "recover" and arena._bullet_count(true) > 0, "Leader keeps chasing while its locked shot fires")
		for bullet: Dictionary in arena._bullets:
			check(is_equal_approx((bullet.pos as Vector2).distance_to(enemy.pos), 20.0), "Volley originates at the moved leader and visible warning")
		arena._update_enemies(0.04)
		check(enemy.pos.distance_to(arena.player_position) < before.distance_to(arena.player_position), "Pursuit resumes immediately after firing")
		enemy = fixture(kind, "aim")
		enemy.timer = 0.01
		before = enemy.pos
		arena._update_enemies(0.04)
		check(enemy.state == "locked" and enemy.pos != before, "Entering firing lock never interrupts pursuit")
		enemy = fixture(kind)
		enemy.spawn = 0.2
		before = enemy.pos
		arena._update_enemies(0.1)
		check(enemy.pos == before, "Spawn arrival does not chase through its warning")
		enemy.spawn = 0.0
		enemy.pulse_stun = 0.2
		arena._update_enemies(0.1)
		check(enemy.pos == before, "Repulsor stagger suspends pursuit")
		arena._update_enemies(0.11)
		arena._update_enemies(0.04)
		check(enemy.pos != before, "Pursuit resumes after stagger")
		enemy = fixture(kind, "recover")
		before = enemy.pos
		arena.freeze()
		arena._process(1.0)
		check(enemy.pos == before, "Question freeze holds pursuing leader still")
		arena._counter_applied = true
		arena.resume_combat()
		arena._process(0.3)
		check(enemy.pos == before, "Get-ready window holds pursuit")
		arena._process(0.3)
		arena._process(0.04)
		check(enemy.pos != before, "Normal simulation resumes pursuit after get-ready")
		# Contact remains actual damage and never teleports an enemy through the player.
		enemy = fixture(kind, "recover")
		arena._invulnerability = 0.0
		enemy.pos = arena.player_position - Vector2(float(enemy.radius) + 13.0, 0)
		arena._update_enemies(0.1)
		check(arena.hull == 2 and arena._last_attack == kind.to_upper() + " COLLISION", "Pursuing leader threatens real contact damage")
		check(enemy.pos.distance_to(arena.player_position) >= float(enemy.radius) + 12.0, "Contact displacement gives an escape gap")
		# Multiple full attack cycles must move the leader, not only short idle frames.
		enemy = fixture(kind)
		enemy.timer = 0.0
		var initial: Vector2 = enemy.pos
		var attacks := 0
		for frame in range(300):
			arena._update_enemies(1.0 / 60.0)
			attacks = int(enemy.attack)
		check(attacks >= 2 and initial.distance_to(enemy.pos) > minf(float(enemy.speed) * 2.0, initial.distance_to(arena.player_position) - 100.0), "Leader covers meaningful distance over several volleys")
		for dimensions in [Vector2(390, 560), Vector2(700, 210), Vector2(1280, 720)]:
			enemy = fixture(kind, "recover", dimensions)
			arena.player_position = Vector2(24, 24)
			for frame in range(240): arena._update_enemies(1.0 / 60.0)
			var padding := float(enemy.radius) + 3.0
			check(enemy.pos.x >= padding and enemy.pos.y >= padding and enemy.pos.x <= dimensions.x - padding and enemy.pos.y <= dimensions.y - padding, "Leader stays within arena on desktop, portrait and short landscape")
	# Later regular leaders pick up speed; checkpoint bosses apply strong pressure
	# without ever outrunning the player's 290px/s steering cap.
	for level in [1, 3, 6, 11, 100, 10000]:
		fixture("elite")
		arena._config = Director.config_for(level, 771)
		arena._enemies.clear()
		arena._add_enemy(Vector2(100, 100), "elite", "target")
		var speed := float(arena._enemies.back().speed)
		check(speed >= 120.0 and speed <= 150.0 and speed < Arena.PLAYER_SPEED, "Regular pursuit is visibly fast within an outrunnable cap at level %d" % level)
		if level >= 3: check(speed > 120.0, "Later leaders pick up pursuit pressure")
	for level in [5, 10, 50, 10000]:
		fixture("boss")
		arena._config = Director.config_for(level, 771)
		arena._enemies.clear()
		arena._add_enemy(Vector2(100, 100), "boss", "target")
		check(float(arena._enemies.back().speed) >= 150.0 and float(arena._enemies.back().speed) < Arena.PLAYER_SPEED, "Checkpoint boss pursuit is conspicuous and outrunnable")
	# A boss alone can close in and defeat a parked ship through real simulation.
	var hunter := fixture("boss", "recover")
	arena._invulnerability = 0.0
	hunter.armored = false
	for frame in range(600):
		arena._simulate(1.0 / 60.0)
		if not arena.combat_active: break
	check(arena.hull == 0 and arena._last_attack == "BOSS COLLISION", "Standing still lets a pursuing boss catch and defeat the player")
	# Ordinary ranged behavior is deliberately unaffected by leader pursuit.
	var shooter := fixture("shooter")
	shooter.pos = Vector2(300, 300)
	arena.player_position = Vector2(470, 300)
	arena._update_enemies(0.1)
	check(shooter.pos == Vector2(300, 300), "Ordinary shooter retains its firing-distance band")
	shooter.state = "aim"
	arena.player_position = Vector2(550, 300)
	arena._update_enemies(0.1)
	check(shooter.pos == Vector2(300, 300), "Ordinary shooter retains its stationary aiming behavior")
	arena.queue_free()
	await process_frame
	print("Boss pursuit: ", checks, " checks; ", failures.size(), " failures")
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
