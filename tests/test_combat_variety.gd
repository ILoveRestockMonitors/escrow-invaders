extends SceneTree
const Arena = preload("res://scripts/arena.gd")
const Director = preload("res://scripts/encounter_director.gd")
const Patterns = preload("res://scripts/combat_patterns.gd")
var checks := 0
var failures: Array[String] = []
var arena
const STARTER := {"turrets":1,"damage":2.0,"fire_rate":1.0,"overdrive":1.0}
const STRONG := {"turrets":2,"damage":8.0,"fire_rate":2.5,"overdrive":1.3,"ricochet":2,"lightning":3,"plasma":1,"carrier":2}

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func fixture(level: int) -> Dictionary:
	var config: Dictionary = Director.config_for(level, 711)
	config.packets = []
	config.question_at = 99999
	arena.launch_encounter(config, STARTER, 3)
	arena._enemies.clear()
	arena._spawn_queue.clear()
	arena._invulnerability = 9999
	arena._fire_cooldown = 9999
	arena._turret_cooldown = 9999
	arena.player_position = Vector2(500,400)
	arena._add_enemy(Vector2(200,200), "boss" if level % 5 == 0 else "elite", "target")
	var enemy: Dictionary = arena._enemies.back()
	enemy.armored = false
	enemy.spawn = 0.0
	enemy.aim = Vector2.RIGHT
	return enemy

func _run() -> void:
	arena = Arena.new()
	arena.size = Vector2(700,600)
	root.add_child(arena)
	await process_frame
	arena.set_process(false)
	var silhouettes: Dictionary = {}
	var names: Dictionary = {}
	for index in range(5):
		var level := 5 * (index + 1)
		var config: Dictionary = Director.config_for(level, 99)
		check(config.boss_type == Patterns.BOSSES[index], "Each checkpoint has its own authored boss")
		check(not names.has(config.target_name), "Boss names are distinct")
		names[config.target_name] = true
		var shape := str(Patterns.silhouette(config.boss_type))
		check(not silhouettes.has(shape), "Boss bodies have physically distinct outlines")
		silhouettes[shape] = true
		check(not String(config.boss_guide).is_empty(), "Boss contract gives a dodge/counter guide")
		check(Director.config_for(level+25,99).boss_type == config.boss_type, "Veteran rounds deterministically remix the same authored mechanic")
		var enemy := fixture(level)
		enemy.state = "aim"
		enemy.timer = 0.001
		arena._update_enemies(0.01)
		check(enemy.state == "locked" and enemy.has("shot_plan"), "Warned shots commit once")
		var plan: Array = enemy.shot_plan.duplicate(true)
		enemy.aim = Vector2.DOWN # Simulate a later direction change; committed lanes stay fixed.
		arena._enemy_fire(enemy)
		check(arena._bullet_count(true) == plan.size(), "Every warned lane produces exactly one projectile")
		for i in range(plan.size()):
			check((arena._bullets[i].velocity as Vector2).normalized().dot(plan[i].direction) > 0.999, "Shot follows the committed warning direction")
		arena.freeze()
		var before: Array = arena._enemies.duplicate(true)
		arena._simulate(1.0)
		check(arena._enemies == before, "Boss mechanics freeze for reading and pause")
	var lancer := fixture(5)
	lancer.attack = 1
	lancer.state = "aim"
	lancer.timer = 0.001
	arena._update_enemies(0.01)
	var aim: Vector2 = lancer.aim
	arena._update_enemies(0.21)
	check(lancer.state == "dash", "Lancer executes an actual warned rush")
	var position: Vector2 = lancer.pos
	arena.player_position = Vector2(500,50)
	arena._update_enemies(0.05)
	check((lancer.pos as Vector2).distance_to(position) > 19 and lancer.aim == aim, "Rush commits its lane instead of instantly turning into the player")
	var brood := fixture(15)
	brood.enraged = true
	arena._enemy_fire(brood)
	check(arena._spawn_queue == ["runner","heavy"], "Brood calls a real finite escort wave")
	arena._enemy_fire(brood)
	check(arena._spawn_queue.size() == 2, "Brood can summon only once, preventing endless objectives")
	var miner := fixture(20)
	miner.attack = 1
	arena._enemy_fire(miner)
	check(arena._bullets.size() == 4 and arena._bullets[0].mine, "Minekeeper places stationary hazards")
	arena.player_position = arena._bullets[0].pos
	arena._invulnerability = 0
	arena._update_bullets(0.1)
	check(arena.hull == 3 and arena._bullets[0].arming > 0, "Mine warning gives a real harmless arming interval")
	arena.freeze()
	var arming: float = arena._bullets[0].arming
	arena._simulate(1)
	check(arena._bullets[0].arming == arming, "Reading cannot silently arm mines")
	arena.combat_active = true
	arena._pulse_cooldown = 0
	arena.set_process(true)
	check(arena.activate_pulse() and arena._bullets.size() < 4, "Repulsor clears nearby mines, including arming hazards")
	arena.set_process(false)
	for bullet: Dictionary in arena._bullets: check((bullet.pos as Vector2).distance_to(arena.player_position) > Arena.PULSE_RADIUS, "Only mines outside the pulse remain")
	var guard := fixture(25)
	guard.state = "recover"
	guard.timer = 0.65
	var hp: float = guard.hp
	arena._damage_enemy(arena._target_index(), 10)
	check(is_equal_approx(hp - float(guard.hp),5.5), "Bulwark shield reduces real incoming damage")
	guard.pulse_stun = 0.8
	hp = guard.hp
	arena._damage_enemy(arena._target_index(), 10)
	check(is_equal_approx(hp - float(guard.hp),10), "Repulsor stun disables the Bulwark shield")
	fixture(1)
	arena._enemies.clear()
	arena._add_enemy(Vector2(200,200),"splitter","split")
	arena._enemies[0].spawn = 0.0
	arena._damage_enemy(0,9999)
	check(arena._enemies.size() == 2 and arena._enemies[0].kind == "runner" and arena._enemies[1].kind == "runner", "Splitters create two finite child enemies")
	check(arena._enemies[0].id != arena._enemies[1].id, "Split children have distinct reward identities")
	for child: Dictionary in arena._enemies: child.spawn = 0.0
	while not arena._enemies.is_empty(): arena._damage_enemy(0,9999)
	check(arena._enemies.is_empty(), "Split children cannot split recursively")
	for kind in ["sniper","miner","splitter"]:
		check(not Patterns.silhouette(kind).is_empty(), "New enemy has an authored body")
		var found := false
		for packet in Director.config_for(12,611).packets:
			if kind in packet: found = true
		check(found, "New enemy actually appears in seeded encounters")
	for level in [1,5,12,25,100,10000]:
		var base: Dictionary = Director.config_for(level,44)
		var starter: Dictionary = Director.match_loadout(base,STARTER)
		var strong: Dictionary = Director.match_loadout(base,STRONG)
		check(starter.target_hp == base.target_hp, "Starter difficulty keeps its original authored health")
		check(strong.target_hp > starter.target_hp and strong.mob_scale > starter.mob_scale, "Real upgrades raise enemy strength")
		check(strong.projectile_speed >= starter.projectile_speed and strong.attack_interval < starter.attack_interval, "Upgrades also influence attack pressure")
		check(strong.threat.hp_scale < strong.threat.ship_power, "Enemy scaling preserves the player's upgrade advantage")
		check(strong == Director.match_loadout(base,STRONG) and base == Director.config_for(level,44), "Threat tuning is deterministic and never mutates authored config")
		arena.launch_encounter(base,STRONG,3)
		check(arena._target_max_hp == strong.target_hp, "The actual launched fight uses tuned enemy health")
		var snapshot: Dictionary = arena._config.duplicate(true)
		arena.refresh_ship({"damage":50.0,"fire_rate":5.0,"turrets":5})
		check(arena._config == snapshot, "Mid-fight rank changes never inflate existing enemy health")
	arena.queue_free()
	await process_frame
	print("Combat variety: ",checks," checks; ",failures.size()," failures")
	for failure in failures: printerr("FAIL: ",failure)
	quit(0 if failures.is_empty() else 1)
