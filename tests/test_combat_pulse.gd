extends SceneTree
## Tactical actions preserve the original combat, study and reward boundaries.
const Arena = preload("res://scripts/arena.gd")
const Director = preload("res://scripts/encounter_director.gd")
var checks := 0
var failures: Array[String] = []
var arena
var kills: Array[String] = []
var cues: Array[String] = []
var outcomes: Array[Dictionary] = []

func _initialize() -> void: call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func fixture() -> void:
	var config: Dictionary = Director.config_for(1, 932)
	config.question_at = 9999.0
	config.packets = []
	arena.launch_encounter(config, {"turrets": 1, "damage": 2.0}, 3)
	arena.player_position = Vector2(195, 340)
	arena._fire_cooldown = 99999.0
	arena._turret_cooldown = 99999.0
	arena._invulnerability = 0.0
	arena.set_process(true)
	kills.clear()
	cues.clear()
	outcomes.clear()

func add_enemy(id: String, kind: String, offset: Vector2, spawning: bool = false) -> void:
	arena._add_enemy(arena.player_position + offset, kind, id)
	if not spawning: arena._enemies.back().spawn = 0.0

func _run() -> void:
	arena = Arena.new()
	check(not arena.activate_pulse(), "Uninitialized arena cannot spend pulse")
	arena.size = Vector2(390, 620)
	root.add_child(arena)
	await process_frame
	arena.enemy_killed.connect(func(id: String, _kind: String): kills.append(id))
	arena.combat_cue.connect(func(kind: String, _intensity: float): cues.append(kind))
	arena.combat_finished.connect(func(stats: Dictionary): outcomes.append(stats))
	check(not arena.activate_pulse(), "Idle hangar cannot spend pulse")
	fixture()
	check(arena.pulse_status().ready and arena.pulse_status().charge == 1.0, "New combat starts charged")
	add_enemy("near", "chaser", Vector2(65, 0))
	add_enemy("far", "heavy", Vector2(0, -210))
	add_enemy("stunned", "heavy", Vector2(-65, 0))
	add_enemy("target", "elite", Vector2(0, -100))
	add_enemy("spawning", "runner", Vector2(0, 65), true)
	var initial_target_hp: float = arena._enemies[arena._enemy_index("target")].hp
	var initial_far_hp: float = arena._enemies[arena._enemy_index("far")].hp
	var initial_spawn: Dictionary = arena._enemies[arena._enemy_index("spawning")].duplicate(true)
	arena._add_hostile_bullet(arena.player_position + Vector2(0, -60), Vector2.DOWN)
	arena._add_hostile_bullet(arena.player_position + Vector2(0, -230), Vector2.DOWN)
	arena._fire_bullet(arena.player_position, arena.player_position + Vector2(100, 0), false)
	var original_config: Dictionary = arena._config.duplicate(true)
	check(arena.activate_pulse(), "Charged active pulse fires")
	check(arena._bullet_count(true) == 1 and arena._bullet_count(false) == 1, "Only nearby hostile shots are cleared")
	check(kills == ["near"] and arena._kills == 1, "Pulse kill uses the single existing kill receipt path")
	check(arena._enemies[arena._enemy_index("far")].hp == initial_far_hp, "Out-of-range enemy remains unharmed")
	check(arena._enemies[arena._enemy_index("target")].hp == initial_target_hp and arena._enemies[arena._enemy_index("target")].armored, "Pulse cannot bypass question armor")
	check(arena._enemies[arena._enemy_index("spawning")] == initial_spawn, "Pulse respects spawn protection")
	var heavy: Dictionary = arena._enemies[arena._enemy_index("stunned")]
	check(heavy.hp == 12.0 and heavy.pulse_stun == 0.8 and heavy.state == "recover", "Surviving exposed enemy takes bounded damage and stagger")
	check(heavy.pos.distance_to(arena.player_position) > 100.0, "Pulse opens physical escape space")
	var stagger_position: Vector2 = heavy.pos
	arena._update_enemies(0.1)
	check(heavy.pos == stagger_position, "Stagger prevents ordinary contact enemy movement")
	check(arena._config == original_config and outcomes.is_empty(), "Pulse does not mutate encounter objectives or invent a clear")
	check(arena._invulnerability == 0.55, "Pulse grants a short escape window")
	check(arena.pulse_status().cooldown == 7.0 and not arena.pulse_status().ready, "Pulse enters seven-second recharge")
	check(not arena.activate_pulse() and kills == ["near"], "Repeated input cannot double spend or duplicate kills")
	check(cues.count("pulse") == 1, "Accepted activation emits exactly one pulse audio cue")
	arena.freeze()
	var cooldown: float = arena._pulse_cooldown
	for frame in range(120): arena._process(1.0 / 60.0)
	check(arena._pulse_cooldown == cooldown and not arena.activate_pulse(), "Study freeze preserves recharge and rejects activation")
	fixture()
	arena.set_process(false)
	check(not arena.activate_pulse(), "Root pause via disabled processing rejects activation")
	arena.set_process(true)
	arena._resume_remaining = 0.6
	check(not arena.activate_pulse(), "Get-ready cue rejects pulse")
	arena._resume_remaining = 0.0
	check(arena.activate_pulse(), "Pulse becomes available after get-ready")
	arena._resume_remaining = 0.6
	arena._process(0.2)
	check(arena._pulse_cooldown == 7.0, "Get-ready consumes no tactical cooldown")
	arena._resume_remaining = 0.0
	for frame in range(421): arena._simulate(1.0 / 60.0)
	check(arena.pulse_status().ready and arena.pulse_status().charge == 1.0, "Seven active seconds restore charge")
	check(cues.count("pulse_ready") == 1, "Recharge emits one ready cue")
	check(arena._kills == 0 and outcomes.is_empty(), "Empty pulses and elapsed time grant no objective or kills")
	check(arena.activate_pulse(), "Recharged pulse fires again")
	arena._simulate(0.04)
	var revive_cooldown: float = arena._pulse_cooldown
	while arena.hull > 0:
		arena._invulnerability = 0.0
		arena._take_hit("TEST")
	check(not arena.activate_pulse(), "Defeated ship cannot activate pulse")
	check(arena.revive_encounter(), "Earned revive can resume pulse-equipped battle")
	check(arena._pulse_cooldown == revive_cooldown, "Revive preserves tactical cooldown")
	fixture()
	for i in range(3): add_enemy("streak-%d" % i, "runner", Vector2(60, 0).rotated(float(i)))
	check(arena.activate_pulse(), "Pulse can strike multiple real enemies")
	check(kills.size() == 3 and arena._streak == 3 and cues.count("streak") == 1, "Actual successive kills produce cosmetic streak feedback")
	arena._invulnerability = 0.0
	arena._take_hit("TEST")
	check(arena._streak == 0 and arena._streak_remaining == 0.0, "Taking damage breaks visual streak")
	arena.reduced_motion = true
	fixture()
	add_enemy("reduced", "chaser", Vector2(60, 0))
	check(arena.activate_pulse() and kills == ["reduced"], "Reduced motion preserves tactical effect")
	check(arena._shake == 0.0 and arena._ship_trail.is_empty(), "Reduced effects avoid added shake and trails")
	for index in range(200): arena._add_ring(Vector2.ZERO, Color.CYAN, 60.0, 0.5)
	check(arena._rings.size() == arena.MAX_RINGS, "Simultaneous impact rings stay bounded")
	arena._update_effects(2.0)
	check(arena._rings.is_empty(), "Expired impact rings are released")
	arena.reset_arena()
	check(arena._pulse_cooldown == 0.0 and arena._pulse_uses == 0 and arena._streak == 0 and arena._rings.is_empty(), "Reset clears transient tactical and feedback state")
	arena.set_process(false)
	for failure in failures: push_error(failure)
	print("%d combat pulse checks; %d failures" % [checks, failures.size()])
	arena.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
