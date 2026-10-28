extends RefCounted
## Authored opening patterns followed by finite, deterministic veteran remixes.
## Seeded composition stays fixed; threat tuning snapshots equipment at launch.
const Patterns = preload("res://scripts/combat_patterns.gd")

const OPENING_HP := [120, 145, 165, 190, 560, 210, 245, 275, 320, 900]
const OPENING_CAP := [8, 9, 10, 11, 10, 11, 12, 13, 14, 12]
const TARGET_NAMES := ["DEBT SENTINEL", "REDLINE HUNTER", "ESCROW BREAKER", "IRON LIEN", "THE FORECLOSER", "COLLECTION WARDEN", "BORDER RUNNER", "HEAVY INTEREST", "CLOSING STORM", "THE UNDERWRITER"]
const BANDS := ["NEON APPROACH", "COLLATERAL BELT", "STATIC FRONTIER", "PLASMA REACH", "CARRIER EXPANSE", "VETERAN ORBIT"]

static func config_for(requested_level: int, seed_value: int) -> Dictionary:
	var level := maxi(1, requested_level)
	var boss := level % 5 == 0
	var tier := int((level - 1) / 10)
	var band := mini(5, int((level - 1) / 20))
	var target_hp: float = float(OPENING_HP[level - 1]) if level <= 10 else (900.0 if boss else 300.0) * (1.0 + 0.20 * float(tier))
	# A relief encounter follows each boss. Scaling has no discontinuous wall.
	if level > 10 and level % 5 == 1:
		target_hp *= 0.78
	var capacity: int = OPENING_CAP[level - 1] if level <= 10 else mini(18, 12 + tier)
	var packet_size := 4 if boss else clampi(6 + int(level / 5), 6, 12)
	var packets: Array = []
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	for packet in range(2 if boss else 3):
		var kinds: Array[String] = []
		for slot in range(packet_size):
			var kind := "chaser"
			if slot == packet_size - 1:
				kind = "shooter"
			elif level >= 3 and slot == 0 and packet > 0:
				kind = "charger"
			elif level >= 4 and slot == 1 and packet > 0:
				kind = "heavy"
			elif level >= 2 and slot == 2:
				kind = "shooter" if packet % 2 == 1 else "runner"
			elif level >= 7 and slot > 3:
				kind = ["chaser", "runner", "shooter", "charger", "heavy", "sniper", "miner", "splitter"][random.randi_range(0, 7)] if level >= 12 else ["chaser", "runner", "shooter", "charger", "heavy"][random.randi_range(0, 4)]
			if level >= 6 and packet == 0 and slot == packet_size - 1: kind = "sniper"
			if level >= 9 and packet == 1 and slot == 1: kind = "miner"
			if level >= 12 and packet == 0 and slot == 0: kind = "splitter"
			kinds.append(kind)
		packets.append(kinds)
	var name: String = TARGET_NAMES[level - 1] if level <= 10 else ("VETERAN OVERSEER %d" % tier if boss else "ORBIT ENFORCER %d" % tier)
	var boss_type := Patterns.boss_for(level) if boss else ""
	if boss: name = Patterns.boss_name(boss_type)
	return {
		"level": level, "seed": seed_value, "boss": boss, "target_hp": target_hp,
		"target_name": name, "max_enemies": capacity, "packets": packets,
		"boss_type": boss_type, "boss_guide": Patterns.guide(boss_type) if boss else "",
		"mob_scale": 1.0 + (0.15 if level > 5 else 0.0) + 0.12 * float(tier),
		"question_at": 4.6 + random.randf_range(0.0, 0.7),
		"projectile_speed": minf(215.0, 160.0 + float(tier) * 3.0),
		"band": BANDS[band], "tier": tier, "reward": 60 + 5 * mini(level, 20),
		"attack_interval": maxf(1.15, 2.3 - 0.07 * float(tier)),
	}

static func match_loadout(config: Dictionary, loadout: Dictionary) -> Dictionary:
	var result := config.duplicate(true)
	# Sublinear HP tuning makes upgrades useful while strengthening the opposition.
	var power := maxf(1.0, float(loadout.get("damage", 2.0)) / 2.0) * maxf(1.0, float(loadout.get("fire_rate", 1.0))) * maxf(1.0, float(loadout.get("overdrive", 1.0)))
	power *= 1.0 + 0.35 * maxi(0, int(loadout.get("turrets", 1)) - 1) + 0.20 * mini(3, int(loadout.get("carrier", 0)))
	for key in ["ricochet", "lightning", "plasma"]: power *= 1.0 + 0.05 * mini(12, int(loadout.get(key, 0)))
	power = clampf(power, 1.0, 250.0)
	var hp_scale := minf(2.3, pow(power, 0.15))
	var pressure := minf(0.20, log(power) * 0.035)
	result.target_hp = float(result.get("target_hp", 120.0)) * hp_scale
	result.mob_scale = float(result.get("mob_scale", 1.0)) * minf(1.8, pow(power, 0.10))
	result.projectile_speed = minf(275.0, float(result.get("projectile_speed", 160.0)) * (1.0 + pressure))
	result.attack_interval = maxf(0.95, float(result.get("attack_interval", 2.3)) / (1.0 + pressure))
	result.threat = {"ship_power": power, "hp_scale": hp_scale, "pressure": pressure}
	return result
