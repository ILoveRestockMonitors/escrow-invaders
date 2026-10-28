extends SceneTree
const ArenaScript = preload("res://scripts/arena.gd")
const Director = preload("res://scripts/encounter_director.gd")
var checks := 0
var failures: Array[String] = []
var game
var finished: Dictionary = {}
var killed_ids: Array[String] = []
const STARTER := {"turrets": 1, "damage": 2.0, "fire_rate": 1.0, "ricochet": 0, "lightning": 0, "plasma": 0, "carrier": 0, "overdrive": 1.0}
const LEVEL_TEN := {"turrets": 2, "damage": 2.5, "fire_rate": 1.15, "ricochet": 1, "lightning": 0, "plasma": 0, "carrier": 0, "overdrive": 1.15}

func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	game = ArenaScript.new()
	game.size = Vector2(390, 560)
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.combat_finished.connect(func(stats: Dictionary): finished = stats)
	game.enemy_killed.connect(func(enemy_id: String, _kind: String): killed_ids.append(enemy_id))
	for level in [1, 5, 6, 10, 30, 50, 100, 101, 500, 10000]:
		var config: Dictionary = Director.config_for(level, 17)
		check(config == Director.config_for(level, 17), "Seeded config stable at %d" % level)
		check(config.max_enemies <= 18 and config.max_enemies >= 8, "Enemy resource cap at %d" % level)
		check(config.packets.size() in [2,3] and config.target_hp > 0, "Finite objective at %d" % level)
	var config: Dictionary = Director.config_for(1, 5)
	game.launch_encounter(config, STARTER, 3)
	while game.combat_active: game._process(1.0/60.0)
	check(game._question_opened and not game._counter_applied, "Target arrival opens exactly one unresolved question")
	var before: Dictionary = game.encounter_status()
	var positions: Array = game._enemies.duplicate(true)
	for frame in range(600): game._process(1.0/60.0)
	check(game.encounter_status().elapsed == before.elapsed and game._enemies == positions, "Reading cannot advance enemies or encounter time")
	var target_index: int = game._target_index()
	game._damage_enemy(target_index, 999999)
	check(game.encounter_status().target_hp == config.target_hp, "Unanswered marked target cannot die")
	game.apply_counter("independent")
	check(game.encounter_status().target_hp == config.target_hp - 22.0, "Independent strike removes armor and 22 HP")
	game.apply_counter("independent")
	check(game.encounter_status().target_hp == config.target_hp - 22.0, "Counter cannot double apply")
	game.resume_combat()
	var elapsed: float = game._elapsed
	for frame in range(30): game._process(1.0/60.0)
	check(game._elapsed == elapsed, "Resume cue freezes danger")
	for kind in ["assisted", "solution"]:
		game.launch_encounter(config, STARTER, 3, kind)
		while not game._question_opened and game.combat_active: game._process(1.0/60.0)
		check(game.encounter_status().target_hp == config.target_hp - (11.0 if kind == "assisted" else 0.0), "Retry replays %s counter once" % kind)
		check(game._counter_applied, "Resolved retry bypasses second question")
	game.launch_encounter(config, STARTER, 3, "solution")
	for hit in range(3):
		game._invulnerability = 0.0
		game._take_hit("TEST LANE")
	check(game.hull == 0 and finished.get("victory", true) == false, "Third actual combat hit defeats ship")
	check(finished.get("cause", "") == "TEST LANE", "Defeat identifies causal attack")
	finished.clear()
	game.launch_encounter(config, STARTER, 3)
	game._fire_cooldown = 999999.0
	game._turret_cooldown = 999999.0
	game._invulnerability = 999999.0
	for frame in range(2400):
		if not game.combat_active:
			game.apply_counter("solution")
			game.resume_combat()
		game._process(1.0/60.0)
	check(finished.is_empty() and not game._enemies.is_empty(), "Forty seconds cannot award uncleared objective")
	var max_loadout := {"turrets": 5, "damage": 100.0, "fire_rate": 5.0, "ricochet": 12, "lightning": 12, "plasma": 12, "carrier": 3, "overdrive": 1.4}
	game.launch_encounter(Director.config_for(10000, 9), max_loadout, 3, "independent")
	game._invulnerability = 999999.0
	var max_enemy_count := 0
	var max_friendly := 0
	var max_hostile := 0
	for frame in range(3600):
		game._process(1.0/60.0)
		max_enemy_count = maxi(max_enemy_count, game._enemies.size())
		max_friendly = maxi(max_friendly, game._bullet_count(false))
		max_hostile = maxi(max_hostile, game._bullet_count(true))
	check(max_enemy_count <= 18 and max_friendly <= 80 and max_hostile <= 48, "Largest build respects separate entity budgets")
	check(max_hostile > 0, "Maximum player build cannot suppress hostile projectile allocation")
	check(game.player_position.is_finite(), "High level remains numerically finite")
	game.launch_encounter(config, STARTER, 3)
	game._bullets.clear()
	for i in range(100): game._fire_bullet(Vector2(100, 100), Vector2(300, 100), false)
	for i in range(60): game._add_hostile_bullet(Vector2(200, 50), Vector2.DOWN)
	check(game._bullet_count(false) == 80 and game._bullet_count(true) == 48, "Friendly cap leaves full hostile capacity")
	game._touch_index = 0
	game._touch_target = game.player_position + Vector2(200, 0)
	var origin: Vector2 = game.player_position
	game._move_player(0.1)
	check(absf(game.player_position.distance_to(origin) - 29.0) < 0.1, "Touch uses exact 290 units/s speed cap")
	game.release_steering()
	check(game._touch_index == -1, "Pause/reset releases touch ownership")
	var stationary_losses := 0
	var dodge_wins := 0
	var flawless := 0
	var tactical_clears := 0
	var starter_times: Array[float] = []
	var upgraded_times: Array[float] = []
	for seed_value in range(1, 11):
		var stationary := simulate(seed_value, STARTER, false)
		if not stationary.victory: stationary_losses += 1
		var dodging := simulate(seed_value, STARTER, true)
		if dodging.victory:
			dodge_wins += 1
			if int(dodging.get("pulse_uses", 0)) > 0: tactical_clears += 1
			if dodging.hits == 0: flawless += 1
			starter_times.append(dodging.duration)
		var upgraded := simulate(seed_value, LEVEL_TEN, true)
		if upgraded.victory and dodging.victory: upgraded_times.append(upgraded.duration)
		print("SEED ", seed_value, " stationary=", stationary, " dodge=", dodging, " upgraded=", upgraded)
	print("CALIBRATION stationary losses=", stationary_losses, "/10; dodge wins=", dodge_wins, "/10; flawless=", flawless, "; starter mean=", mean(starter_times), "; upgraded mean=", mean(upgraded_times))
	check(stationary_losses >= 8, "Standing still loses at least 8/10 opening seeds")
	# The user explicitly requested faster constant pursuit, superseding the old
	# slow-leader difficulty band. Verify real wins using the available defenses.
	check(tactical_clears > 0, "Movement and Repulsor can clear the pursuing-leader encounter")
	check(dodge_wins >= 5, "A simple movement/Repulsor policy can clear at least half the opening seeds")
	if not starter_times.is_empty() and not upgraded_times.is_empty():
		check(mean(upgraded_times) <= mean(starter_times) * 0.7 and mean(upgraded_times) >= mean(starter_times) * 0.4, "Upgrades retain a substantial 30-60 percent clear-time benefit against pursuing enemies")
		check(mean(starter_times) >= 15.0 and mean(starter_times) <= 30.0, "Pursuing opening objective stays finite and near twenty seconds")
	for level in range(1, 31):
		finished = {}
		var loadout := STARTER.duplicate()
		loadout.turrets = 2 if level >= 4 else 1
		loadout.damage = 2.0 + float(level) * 0.04
		loadout.fire_rate = 1.0 + float(level) * 0.015
		loadout.ricochet = 1 if level >= 6 else 0
		loadout.lightning = 1 if level >= 16 else 0
		loadout.plasma = 1 if level >= 30 else 0
		game.launch_encounter(Director.config_for(level, level + 71), loadout, 3, "solution")
		# This sweep measures finite objectives and budgets, not survival/fun.
		game._invulnerability = 999999.0
		var largest := 0
		for frame in range(12000):
			if frame % 6 == 0:
				game._touch_index = 0
				game._touch_target = dodge_target()
			game._process(1.0/60.0)
			largest = maxi(largest, game._enemies.size())
			if not finished.is_empty(): break
		check(finished.get("victory", false), "Solution-only finite objective completes at level %d" % level)
		check(largest <= Director.config_for(level, level + 71).max_enemies, "Marked arrival respects encounter enemy ceiling at level %d" % level)
	# Module behaviors are observable in projectile and damage state.
	game.launch_encounter(config, {"ricochet": 2, "damage": 2.0, "turrets": 2}, 3)
	game._enemies.clear()
	game._spawn_queue.clear()
	game._add_enemy(Vector2(190, 250), "heavy", "first")
	game._add_enemy(Vector2(260, 250), "heavy", "second")
	for enemy: Dictionary in game._enemies: enemy.spawn = 0.0
	game._fire_bullet(Vector2(165, 250), Vector2(190, 250), true)
	game._update_bullets(0.03)
	check(game._bullets.size() == 1 and game._bullets[0].bounces == 1, "Ricochet redirects a real bullet after impact")
	check(game._enemies[0].marked > 0.0, "Ricochet leaves a conductive mark")
	game.lightning_level = 1
	game.player_position = Vector2(195, 320)
	var hp_before: float = game._enemies[0].hp
	game._chain_lightning()
	check(hp_before - game._enemies[0].hp > 2.7, "Marked target amplifies and conducts chain damage")
	game._loadout = {"plasma": 1}
	game.player_position = Vector2(100, 250)
	game._orbit_angle = 0.0
	hp_before = game._enemies[0].hp
	game._plasma_sweep()
	check(game._enemies[0].hp < hp_before, "Plasma orbit damages enemies within its swept arc")
	game._loadout = {"plasma": 1, "carrier": 2, "damage": 2.0}
	game.lightning_level = 0
	game._bullets.clear()
	game._fire_bullet(Vector2(165, 250), Vector2(190, 250), true, true)
	check(game._bullets[0].plasma and game._bullets[0].damage == 1.3, "Carrier supports inherit an equipped plasma effect with bounded damage")
	for failure in failures: push_error(failure)
	print("%d encounter arena checks; %d failures" % [checks, failures.size()])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func simulate(seed_value: int, loadout: Dictionary, dodging: bool) -> Dictionary:
	finished = {}
	killed_ids.clear()
	game.launch_encounter(Director.config_for(1, seed_value), loadout, 3, "independent")
	var was_processing: bool = game.is_processing()
	game.set_process(true) # Repulsor uses the same active-play guard as the actual UI.
	for frame in range(9000):
		if dodging and game.combat_active and frame % 6 == 0:
			game._touch_index = 0
			game._touch_target = dodge_target()
			if nearby_threat(): game.activate_pulse()
		game._process(1.0/60.0)
		if not finished.is_empty(): break
	var unique: Dictionary = {}
	for enemy_id in killed_ids: unique[enemy_id] = true
	check(killed_ids.size() == unique.size(), "Kill IDs unique within actual attempt")
	game.set_process(was_processing)
	var result: Dictionary = finished.duplicate() if not finished.is_empty() else {"victory": false, "duration": 150.0, "hits": 3}
	result.pulse_uses = game._pulse_uses
	return result

func nearby_threat() -> bool:
	for enemy: Dictionary in game._enemies:
		if float(enemy.spawn) <= 0.0 and (enemy.pos as Vector2).distance_to(game.player_position) < 125.0: return true
	for bullet: Dictionary in game._bullets:
		if bullet.hostile and (bullet.pos as Vector2).distance_to(game.player_position) < 100.0: return true
	return false

func dodge_target() -> Vector2:
	var best := INF
	var destination: Vector2 = game.player_position
	for option in range(17):
		var velocity := Vector2.ZERO if option == 16 else Vector2.from_angle(float(option) * TAU / 16) * 290.0
		var score := 0.0
		for t in [0.15, 0.35, 0.60]:
			var point: Vector2 = game.player_position + velocity * float(t)
			if point.x < 35 or point.y < 35 or point.x > game.size.x-35 or point.y > game.size.y-35:
				score += 15000.0
			score += point.distance_to(game.size * Vector2(0.5, 0.55)) * 0.018
			for enemy: Dictionary in game._enemies:
				var toward: Vector2 = (game.player_position - enemy.pos).normalized()
				var enemy_position: Vector2 = enemy.pos + toward * float(enemy.speed) * float(t)
				var distance := point.distance_to(enemy_position)
				score += 1000.0 * exp(-maxf(0.0, distance - float(enemy.radius) - 12.0) / 20.0)
				if enemy.state in ["locked", "dash"]:
					var end: Vector2 = enemy.pos + (enemy.aim as Vector2) * 500.0
					score += 30.0 * exp(-Geometry2D.get_closest_point_to_segment(point, enemy.pos, end).distance_to(point) / 20.0)
			for bullet: Dictionary in game._bullets:
				if bullet.hostile:
					var predicted: Vector2 = bullet.pos + bullet.velocity * float(t)
					score += 2000.0 * exp(-point.distance_to(predicted) / 14.0)
		if score < best:
			best = score
			destination = game.player_position + velocity
	return destination

func mean(values: Array[float]) -> float:
	if values.is_empty(): return 0.0
	var total := 0.0
	for value in values: total += value
	return total / float(values.size())
