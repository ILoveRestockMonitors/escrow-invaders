extends RefCounted
## Shared geometry and shot plans: attack warnings describe the exact live attack.
const BOSSES := ["lancer", "cyclone", "brood", "minekeeper", "bulwark"]
const NAMES := ["THE FORECLOSER", "THE UNDERWRITER", "TITLE AUDITOR", "LIEN MINER", "COLLATERAL FORTRESS"]
const GUIDES := [
	"LANCER / Fan volleys alternate with a warned rush. Move sideways when the lane locks.",
	"CYCLONE / Rotating rings alternate with sweeping fans. Use the gaps between spokes.",
	"BROOD / Calls one escort wave below half hull. Clear its finite reinforcements.",
	"MINEKEEPER / Drops arming mines between aimed volleys. Avoid the warning circles; Repulsor clears mines.",
	"BULWARK / Recovery shields reduce damage. Repulsor disables the shield during its stun.",
]

static func boss_for(level: int) -> String:
	return BOSSES[posmod(int(level / 5) - 1, BOSSES.size())]

static func boss_name(kind: String) -> String:
	return NAMES[maxi(0, BOSSES.find(kind))]

static func guide(kind: String) -> String:
	return GUIDES[maxi(0, BOSSES.find(kind))]

static func tint(kind: String) -> Color:
	return [Color("ff885c"), Color("bc9bff"), Color("c7ed68"), Color("ffcb73"), Color("7abfff")][maxi(0, BOSSES.find(kind))]

static func shielded(enemy: Dictionary) -> bool:
	return enemy.get("boss_type", "") == "bulwark" and enemy.get("state", "") == "recover" and float(enemy.get("timer", 0)) > 0.12 and float(enemy.get("pulse_stun", 0)) <= 0 and float(enemy.get("guard_disabled", 0)) <= 0

static func is_rush(enemy: Dictionary) -> bool:
	return enemy.get("kind", "") == "charger" or (enemy.get("boss_type", "") == "lancer" and int(enemy.get("attack", 0)) % 2 == 1)

static func shots(enemy: Dictionary, short_arena: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var kind := String(enemy.get("kind", ""))
	var boss := String(enemy.get("boss_type", ""))
	var aim: Vector2 = enemy.get("aim", Vector2.DOWN)
	var attack := int(enemy.get("attack", 0))
	if kind == "miner" or (boss == "minekeeper" and attack % 2 == 1):
		for index in range(1 if kind == "miner" else 4):
			result.append({"direction": Vector2.from_angle(index * TAU / 4.0 + attack * 0.3), "offset": 0.0 if kind == "miner" else 64.0, "speed": 0.0, "arming": 0.9, "cause": "ARMED MINE"})
	elif kind == "sniper":
		result.append({"direction": aim, "speed": 1.5, "cause": "SNIPER SHOT"})
	elif boss == "cyclone" and attack % 2 == 0:
		var count := (6 if short_arena else 8) + (2 if enemy.get("enraged", false) else 0)
		for index in range(count):
			result.append({"direction": Vector2.from_angle(index * TAU / count + attack * 0.37), "speed": 0.85, "cause": "CYCLONE SPOKES"})
	elif kind == "boss":
		var spread: Array = [-0.52,-0.26,0.0,0.26,0.52] if boss == "cyclone" or boss == "bulwark" else [-0.26,0.0,0.26]
		if short_arena: spread = [-0.26,0.0,0.26]
		for offset in spread:
			result.append({"direction": aim.rotated(float(offset)), "speed": 1.0, "cause": "BOSS VOLLEY"})
	elif kind == "elite":
		for offset in [-0.26,0.0,0.26] if not short_arena else [0.0]:
			result.append({"direction": aim.rotated(float(offset)), "speed": 1.0, "cause": "MARKED TARGET VOLLEY"})
	else:
		result.append({"direction": aim, "speed": 1.0, "cause": "SHOOTER LANE"})
	return result

static func silhouette(kind: String) -> PackedVector2Array:
	match kind:
		"lancer": return PackedVector2Array([Vector2(1.45,0),Vector2(0.1,-0.32),Vector2(-0.6,-1),Vector2(-0.88,-0.7),Vector2(-0.55,0),Vector2(-0.88,0.7),Vector2(-0.6,1),Vector2(0.1,0.32)])
		"cyclone": return PackedVector2Array([Vector2(1,0),Vector2(0.8,-0.7),Vector2(0,-1),Vector2(-0.7,-0.5),Vector2(-1,0),Vector2(-0.5,0.7),Vector2(0,1),Vector2(0.7,0.5)])
		"brood": return PackedVector2Array([Vector2(0.8,-0.65),Vector2(0.95,-0.2),Vector2(0.55,0),Vector2(0.95,0.2),Vector2(0.8,0.65),Vector2(-0.4,1),Vector2(-1,0.75),Vector2(-0.6,0),Vector2(-1,-0.75),Vector2(-0.4,-1)])
		"minekeeper": return PackedVector2Array([Vector2(1,0),Vector2(0.48,-0.4),Vector2(0.4,-1),Vector2(0,-0.52),Vector2(-0.4,-1),Vector2(-0.48,-0.4),Vector2(-1,0),Vector2(-0.48,0.4),Vector2(-0.4,1),Vector2(0,0.52),Vector2(0.4,1),Vector2(0.48,0.4)])
		"bulwark": return PackedVector2Array([Vector2(1,-0.6),Vector2(1,0.6),Vector2(0.4,1),Vector2(-0.85,0.8),Vector2(-1,0.35),Vector2(-0.75,0),Vector2(-1,-0.35),Vector2(-0.85,-0.8),Vector2(0.4,-1)])
		"sniper": return PackedVector2Array([Vector2(1.35,0),Vector2(0.0,-0.35),Vector2(-0.75,-0.6),Vector2(-1,0),Vector2(-0.75,0.6),Vector2(0,0.35)])
		"miner": return PackedVector2Array([Vector2(0.8,-0.55),Vector2(0.8,0.55),Vector2(-0.1,0.35),Vector2(-0.5,0.95),Vector2(-1,0.5),Vector2(-0.65,0),Vector2(-1,-0.5),Vector2(-0.5,-0.95),Vector2(-0.1,-0.35)])
		"splitter": return PackedVector2Array([Vector2(1,0),Vector2(0.2,-0.95),Vector2(-0.7,-0.8),Vector2(-0.25,0),Vector2(-0.7,0.8),Vector2(0.2,0.95)])
	return PackedVector2Array()
