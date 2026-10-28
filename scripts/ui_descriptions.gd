extends RefCounted
## Player-facing effects, based on ProgressionModel values and Arena combat caps.
## Loadout does not include purchased ranks, so power/cadence previews show the
## current value instead of guessing the next diminishing-return increment.

static func shop_title(key: String) -> String:
	match key:
		"power": return "SHOT DAMAGE"
		"cadence": return "FIRE RATE"
		"reactor": return "REACTOR SPEED"
	return "UPGRADE"

static func shop_effect(key: String, loadout: Dictionary) -> String:
	match key:
		"power": return _damage_effect(loadout)
		"cadence": return _fire_rate_effect(loadout)
		"reactor": return _reactor_effect(loadout, 0.08)
	return "A permanent improvement to your ship."

static func rank_title(key: String) -> String:
	match key:
		"power": return "SHOT DAMAGE"
		"cadence": return "FIRE RATE"
		"overdrive": return "REACTOR SPEED"
		"module:ricochet": return "MORE BOUNCES"
		"module:lightning": return "CHAIN LIGHTNING"
		"module:plasma": return "PLASMA DAMAGE"
		"module:carrier": return "SUPPORT DRONES"
	return "WEAPON UPGRADE"

static func rank_effect(key: String, loadout: Dictionary) -> String:
	match key:
		"power": return _damage_effect(loadout)
		"cadence": return _fire_rate_effect(loadout)
		"overdrive": return _reactor_effect(loadout, 0.02)
		"module:ricochet":
			var rank := int(loadout.get("ricochet", 0))
			if rank <= 0:
				return "Bullets bounce into other enemies, up to 3 extra targets. Equip Ricochet to use it."
			if rank >= 3:
				return "Bounce limit reached: 3 extra targets per bullet. Higher ranks do not add more bounces."
			return "Each bullet can bounce into more enemies. Extra targets: %d to %d." % [rank, rank + 1]
		"module:lightning":
			var rank := clampi(int(loadout.get("lightning", 0)), 0, 12)
			if rank <= 0:
				return "Electric arcs jump between nearby enemies. Higher ranks strengthen the arcs. Equip Lightning to use it."
			if rank >= 12:
				return "Lightning has reached its combat limit: up to 6 targets, 10.4 base damage each."
			return "Stronger arcs strike nearby enemies. Base damage per target: %.1f to %.1f; up to %d targets after upgrading." % [2.0 + rank * 0.7, 2.0 + (rank + 1) * 0.7, mini(6, rank + 3)]
		"module:plasma":
			var rank := clampi(int(loadout.get("plasma", 0)), 0, 12)
			if rank <= 0:
				return "A rotating plasma sweep damages enemies near your ship. Equip Plasma to use it."
			if rank >= 12:
				return "Plasma has reached its combat limit: 19.4 damage per sweep hit."
			return "Your nearby plasma sweep hits harder. Damage per hit: %.1f to %.1f." % [5.0 + rank * 1.2, 5.0 + (rank + 1) * 1.2]
		"module:carrier":
			var rank := clampi(int(loadout.get("carrier", 0)), 0, 3)
			if rank <= 0:
				return "Support drones orbit your ship and fire automatically. They can use another equipped weapon effect. Equip Carrier to deploy them."
			if rank >= 3:
				return "Carrier is at its combat limit: 3 support drones. Higher ranks do not add more drones."
			return "Add another automatic support drone. Deployed drones: %d to %d when Carrier is equipped." % [rank, rank + 1]
	return "Improve this weapon's permanent rank. Equip the module to use its effect."

static func _damage_effect(loadout: Dictionary) -> String:
	var damage := clampf(float(loadout.get("damage", 2.0)), 1.0, 100.0)
	if damage >= 100.0:
		return "Bullet damage has reached its combat limit: 100 per main shot. Higher damage ranks cannot increase it further."
	return "Your ship and drones deal more damage with each bullet. Current main shot: %.2f damage." % damage

static func _fire_rate_effect(loadout: Dictionary) -> String:
	var fire_rate := clampf(float(loadout.get("fire_rate", 1.0)), 0.5, 5.0)
	var reactor := clampf(float(loadout.get("overdrive", 1.0)), 1.0, 1.4)
	var suffix := " Temporary bonus included." if bool(loadout.get("bonus", false)) else ""
	if fire_rate >= 5.0:
		return "The fire-rate upgrade is at its combat limit. Current firing speed: %.2fx the starter ship.%s" % [fire_rate * reactor, suffix]
	return "Your ship and every drone fire more often. Current firing speed: %.2fx the starter ship.%s" % [fire_rate * reactor, suffix]

static func _reactor_effect(loadout: Dictionary, increase: float) -> String:
	var reactor := clampf(float(loadout.get("overdrive", 1.0)), 1.0, 1.4)
	var bonus := bool(loadout.get("bonus", false))
	if reactor >= 1.4:
		return "Reactor speed is at its combat limit: 1.40x. Your temporary bonus is included." if bonus else "Reactor speed is at its combat limit: 1.40x. More reactor ranks will not increase current firing speed."
	var upgraded := clampf(float(loadout.get("overdrive", 1.0)) + increase * (1.25 if bonus else 1.0), 1.0, 1.4)
	return "Speeds up cannon and drone firing on top of Fire Rate. Reactor multiplier: %.2fx to %.2fx.%s" % [reactor, upgraded, " Temporary bonus included." if bonus else ""]
