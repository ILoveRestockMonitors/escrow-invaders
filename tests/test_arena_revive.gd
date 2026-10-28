extends SceneTree
const ArenaScript = preload("res://scripts/arena.gd")
const Director = preload("res://scripts/encounter_director.gd")
const LOADOUT := {"turrets": 2, "damage": 2.2, "fire_rate": 1.1, "ricochet": 1, "overdrive": 1.0}
var checks := 0
var failures: Array[String] = []
var arena
var kills: Array[String] = []
var results: Array[Dictionary] = []
var questions := 0

func _initialize() -> void: call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	arena = ArenaScript.new()
	check(not arena.revive_encounter(), "Uninitialized arena rejects revive")
	arena.size = Vector2(390, 560)
	root.add_child(arena)
	await process_frame
	arena.set_process(false)
	arena.enemy_killed.connect(func(enemy_id: String, _kind: String): kills.append(enemy_id))
	arena.combat_finished.connect(func(stats: Dictionary): results.append(stats))
	arena.question_requested.connect(func(): questions += 1)
	check(not arena.revive_encounter(), "Idle arena rejects revive")

	var config: Dictionary = Director.config_for(3, 911)
	arena.launch_encounter(config, LOADOUT, 3)
	check(not arena.revive_encounter(), "Healthy active encounter cannot revive")
	for frame in range(60): arena._process(1.0/60.0)
	var opening_elapsed: float = arena._elapsed
	kill_ship()
	check(arena._finished and arena.hull == 0 and not arena._question_opened, "Fixture dies before core question")
	check(arena.revive_encounter(2), "Pre-question defeat can revive")
	check(arena.hull == 2 and arena.combat_active, "Pre-question revive restores requested hull and resumes")
	check(arena._elapsed == opening_elapsed and not arena._finished, "Pre-question revive preserves elapsed and reopens same attempt")
	for frame in range(600):
		arena._invulnerability = 999.0
		arena._process(1.0/60.0)
		if arena._question_opened: break
	check(arena._question_opened and questions == 1 and not arena.combat_active, "Revived screening reaches the original core opportunity once")
	arena.apply_counter("independent")
	arena.resume_combat()
	kill_ship()
	check(not arena.revive_encounter(), "Second defeat cannot consume a duplicate revive")

	arena.launch_encounter(config, LOADOUT, 3)
	arena._elapsed = 8.5
	arena._arrive_target()
	arena.apply_counter("assisted")
	arena._add_enemy(Vector2(120, 160), "shooter", "escort-a")
	arena._add_enemy(Vector2(220, 260), "charger", "escort-b")
	for enemy: Dictionary in arena._enemies: enemy.spawn = 0.0
	arena._damage_enemy(arena._enemy_index("escort-a"), 3.0)
	arena._add_enemy(Vector2(320, 460), "chaser", "already-killed")
	arena._enemies.back().spawn = 0.0
	arena._damage_enemy(arena._enemy_index("already-killed"), 999.0)
	arena.resume_combat()
	kill_ship()
	# A frozen fatal-core or future death animation may still retain both pools.
	arena._fire_bullet(Vector2(150, 300), Vector2(150, 100), false)
	arena._add_hostile_bullet(Vector2(160, 310), Vector2.RIGHT, "IMMINENT SHOT")
	arena._add_hostile_bullet(Vector2(170, 310), Vector2.LEFT, "IMMINENT SHOT")
	for enemy: Dictionary in arena._enemies:
		enemy.state = "dash" if enemy.kind == "charger" else "locked"
		enemy.timer = 0.02
	var hp: Dictionary = {}
	var positions: Dictionary = {}
	for enemy: Dictionary in arena._enemies:
		hp[enemy.id] = enemy.hp
		positions[enemy.id] = enemy.pos
	var prior_packet: int = arena._packet
	var prior_queue: Array = arena._spawn_queue.duplicate()
	var prior_kills: int = arena._kills
	var prior_signal_count := kills.size()
	var prior_result_count := results.size()
	var prior_pos: Vector2 = arena.player_position
	var prior_loadout: Dictionary = arena._loadout.duplicate(true)
	arena._dragging = true
	arena._touch_index = 8
	check(arena.revive_encounter(99), "New launch resets revive allowance")
	check(arena.hull == 3, "Restored hull clamps to ship maximum")
	check(arena._enemies.size() == hp.size(), "Revive preserves live enemy count")
	for enemy: Dictionary in arena._enemies:
		check(enemy.hp == hp[enemy.id] and enemy.pos == positions[enemy.id], "Revive preserves HP and position for " + str(enemy.id))
		check(enemy.state == "recover" and enemy.timer >= 1.2, "Revive interrupts imminent attack for " + str(enemy.id))
	check(arena._packet == prior_packet and arena._spawn_queue == prior_queue, "Revive preserves finite packet progress")
	check(arena._elapsed == 8.5 and arena._kills == prior_kills, "Revive preserves elapsed and kill totals")
	check(arena._loadout == prior_loadout and arena.player_position == prior_pos, "Revive preserves loadout and player position")
	check(arena._counter_applied and arena._resolved_counter == "assisted", "Revive retains original academic counter")
	check(arena._bullet_count(true) == 0 and arena._bullet_count(false) == 1, "Revive clears only hostile projectiles")
	check(kills.size() == prior_signal_count and results.size() == prior_result_count, "Revive emits no kill or duplicate completion rewards")
	check(arena._touch_index == -1 and not arena._dragging, "Revive releases stale thumb and mouse steering")
	check(arena._invulnerability == 2.0 and arena._resume_remaining == 0.6, "Revive provides two active seconds protection and ready cue")
	check(not arena.revive_encounter(), "Immediate duplicate revive input is rejected")
	arena._take_hit("OVERLAP")
	check(arena.hull == 3, "Revive protection prevents overlapping enemy damage")
	var paused_hp: Dictionary = hp.duplicate()
	for frame in range(30): arena._process(1.0/60.0)
	check(arena._elapsed == 8.5 and arena._invulnerability == 2.0, "Get-ready cue consumes no hostile time or protection")
	for enemy: Dictionary in arena._enemies: check(enemy.hp == paused_hp[enemy.id], "Ready cue preserves target HP")
	kill_ship()
	check(not arena.revive_encounter(), "Second death remains a defeat after spent revive")

	# Main may apply a saved fatal-core solution before or after the live revive.
	for order in ["before", "after"]:
		arena.launch_encounter(config, LOADOUT, 1)
		arena._arrive_target()
		arena.hull = 0
		check(not arena._finished, "Fatal-core fixture is frozen without combat completion")
		if order == "before": arena.apply_counter("solution")
		check(arena.revive_encounter(), "Fatal core can revive with counter applied " + order)
		if order == "after":
			check(not arena.combat_active, "Unresolved fatal core cannot silently resume armored battle")
			var elapsed: float = arena._elapsed
			for frame in range(120): arena._process(1.0/60.0)
			check(arena._elapsed == elapsed, "Fatal-core revive stays safely frozen awaiting saved counter")
			arena.apply_counter("solution")
			arena.resume_combat()
		check(arena.combat_active and arena._counter_applied, "Saved fatal-core solution makes revived target damageable")
		check(arena.encounter_status().target_hp == arena._target_max_hp, "Solution revive grants no invented correct-answer strike")

	arena.launch_encounter(config, LOADOUT, 3)
	arena._finish(true)
	arena.hull = 0
	check(not arena.revive_encounter(), "Cleared encounter cannot revive even if external hull changes")
	arena.launch_encounter(config, LOADOUT, 3)
	kill_ship()
	check(not arena.revive_encounter(0), "Zero-hull request is rejected")
	check(arena.revive_encounter(1), "Rejected invalid request does not consume revive allowance")
	arena.reset_arena()
	check(not arena.revive_encounter(), "Reset removes reviveable battle")
	for failure in failures: push_error(failure)
	print("%d arena revive checks; %d failures" % [checks, failures.size()])
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func kill_ship() -> void:
	arena.combat_active = true
	while arena.hull > 0:
		arena._invulnerability = 0.0
		arena._take_hit("TEST IMPACT")
