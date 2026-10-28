extends RefCounted
## Permanent ship progression. Academic grading remains in StudyModel.
const VERSION := 1
const Evolution = preload("res://scripts/ship_evolution.gd")
const CloudSave = preload("res://scripts/cloud_save.gd")
const MILESTONES := [
	{"level": 3, "id": "orbital", "title": "TWIN ORBIT", "description": "A second independently targeting orbital drone."},
	{"level": 5, "id": "ricochet", "title": "RICOCHET CORE", "description": "Shots bounce into the next enemy."},
	{"level": 10, "id": "slot", "title": "DUAL MODULE BAY", "description": "Combine two weapon modules."},
	{"level": 15, "id": "lightning", "title": "CONDUCTIVE LINK", "description": "Electric arcs connect nearby enemies."},
	{"level": 25, "id": "conduction", "title": "STORM CIRCUIT", "description": "An evolved chain links more targets."},
	{"level": 35, "id": "plasma", "title": "PLASMA ORBIT", "description": "A sweeping plasma ring burns through formations."},
	{"level": 75, "id": "carrier", "title": "CARRIER FRAME", "description": "Support drones inherit an equipped module."},
	{"level": 100, "id": "carrier_evolution", "title": "ORBITAL FLEET", "description": "An additional support drone joins the carrier."},
]
var persistence_enabled := true
var save_path := "user://arcade-progress.json"
var progress_warning := ""
var state: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()
	state = _fresh_state()

func _fresh_state() -> Dictionary:
	return {"profile_id": "ship-%d-%d" % [int(Time.get_unix_time_from_system()), _rng.randi()], "level": 1, "rank": 1, "xp": 0, "total_xp": 0, "pending_upgrades": 0, "upgrades": {"power": 0, "cadence": 0, "overdrive": 0}, "modules": {}, "equipped": [], "hull": 3, "combo": 0, "current": {}, "block": {}, "bonus": {}, "checkpoint_pending": false, "receipts": {}, "coins": 0, "gems": 0, "shop_ranks": {"power": 0, "cadence": 0, "reactor": 0}, "offers": {}, "boost": {}, "last_clear_reward": {}}

func ensure_encounter(question: Dictionary) -> Dictionary:
	if not state.current.is_empty():
		return state.current
	var level := int(state.level)
	state.current = {"id": "%s/level/%d" % [state.profile_id, level], "level": level, "seed": _rng.randi_range(1, 2147483646), "attempt": 0, "attempt_id": "", "attempt_status": "ready", "question": question.duplicate(true), "response": {}, "kill_receipts": {}, "revive": {}, "revive_used": false}
	_persist()
	return state.current

func begin_attempt() -> Dictionary:
	if state.current.is_empty():
		return {}
	var encounter: Dictionary = state.current
	if int(encounter.attempt) > 0:
		state.hull = 3
	encounter.attempt = int(encounter.attempt) + 1
	encounter.attempt_id = "%s/attempt/%d" % [encounter.id, encounter.attempt]
	encounter.attempt_status = "active"
	if not encounter.get("response", {}).is_empty():
		encounter.response.fatal = false
	encounter.kill_receipts = {}
	encounter.revive = {}
	encounter.revive_used = false
	state.current = encounter
	_persist()
	return encounter

func mark_defeated() -> void:
	if not state.current.is_empty():
		state.current.attempt_status = "defeated"
	state.hull = 0
	_persist()

func grant_kill(enemy_id: String, kind: String) -> int:
	if state.current.is_empty() or state.current.get("attempt_status", "") != "active" or enemy_id.is_empty():
		return 0
	var receipts: Dictionary = state.current.kill_receipts
	if receipts.has(enemy_id):
		return 0
	var amount := 40 if kind == "boss" else (20 if kind == "elite" else 4)
	receipts[enemy_id] = amount
	state.coins = int(state.coins) + (10 if kind == "boss" else (5 if kind == "elite" else 1))
	state.current.kill_receipts = receipts
	_add_xp(amount)
	_persist()
	return amount

func clear_encounter() -> Dictionary:
	if state.current.is_empty() or not bool(state.current.get("response", {}).get("resolved", false)):
		return {"error": "The encounter question has not been resolved."}
	var level := int(state.current.level)
	if level != int(state.level):
		return {"error": "This encounter was already cleared."}
	var reward := 60 + 5 * mini(level, 20)
	_add_xp(reward)
	var unlocks: Array[Dictionary] = []
	for milestone in MILESTONES:
		if int(milestone.level) == level:
			unlocks.append(milestone.duplicate(true))
			match String(milestone.id):
				"ricochet", "lightning", "plasma", "carrier":
					state.modules[milestone.id] = 1
					if state.equipped.size() < module_slots():
						state.equipped.append(milestone.id)
				"conduction": state.modules.lightning = maxi(2, int(state.modules.get("lightning", 0)))
				"carrier_evolution": state.modules.carrier = maxi(2, int(state.modules.get("carrier", 0)))
	if level > 100 and level % 25 == 0:
		var keys := ["ricochet", "lightning", "plasma", "carrier"]
		var key: String = keys[int(level / 25) % keys.size()]
		state.modules[key] = int(state.modules.get(key, 0)) + 1
		unlocks.append({"level": level, "id": key, "title": "VETERAN " + key.to_upper(), "description": "Module rank increased."})
	state.level = level + 1
	state.hull = mini(3, int(state.hull) + 1)
	state.block["index"] = level % 5
	state.checkpoint_pending = level % 5 == 0
	if state.checkpoint_pending:
		state.hull = 3
		_add_xp(50)
		reward += 50
	if int(state.bonus.get("target_level", -1)) == level:
		state.bonus = {}
	if level % 5 in [2, 4]:
		state.bonus = {"id": "%s/bonus/%d" % [state.profile_id, level], "status": "pending", "target_level": level + 1, "question": {}, "correct": false, "enhancement": false, "response": {}}
	var coins := 60 + 5 * mini(level, 20)
	var gems := 5 if level % 5 == 0 else 1
	state.coins = int(state.coins) + coins
	state.gems = int(state.gems) + gems
	state.last_clear_reward = {"level": level, "xp": reward, "coins": coins, "gems": gems}
	state.current = {}
	_persist()
	return {"level": level, "xp": reward, "coins": coins, "gems": gems, "unlocks": unlocks, "checkpoint": state.checkpoint_pending}

func acknowledge_checkpoint() -> void:
	state.checkpoint_pending = false
	_persist()

func start_bonus(question: Dictionary = {}) -> bool:
	if state.bonus.get("status", "") != "pending":
		return false
	if not question.is_empty():
		state.bonus.question = question.duplicate(true)
	if state.bonus.get("question", {}).is_empty():
		return false
	state.bonus.status = "started"
	_persist()
	return true

func skip_bonus() -> void:
	if state.bonus.get("status", "") in ["pending", "started"]:
		state.bonus.status = "skipped"
		state.bonus.enhancement = false
		_persist()

func apply_response(transaction_id: String, result: Dictionary, input: Dictionary) -> Dictionary:
	if state.receipts.has(transaction_id):
		return state.receipts[transaction_id].duplicate(true)
	var is_bonus := bool(input.get("is_bonus", false))
	var target: Dictionary = state.bonus if is_bonus else state.current
	if target.get("id", "") != input.get("target_id", ""):
		return {"error": "Response does not match the saved encounter."}
	var skipped := String(input.stage) == "skip"
	var first := String(input.stage) == "first"
	var correct := bool(result.get("correct", false))
	var assisted := bool(result.get("assisted", false))
	var previous: Dictionary = target.get("response", {})
	var response: Dictionary = previous.duplicate(true)
	if first:
		response.first_result = result.duplicate(true)
		response.first_correct = correct
		if not is_bonus:
			if not correct:
				state.hull = maxi(0, int(state.hull) - 1)
				state.combo = 0
			elif not assisted:
				state.combo = int(state.combo) + 1
	response.result = result.duplicate(true)
	response.attempts = int(previous.get("attempts", 0)) + (0 if input.stage in ["solution", "skip"] else 1)
	if skipped:
		response.skipped = true
	response.last_correct = correct
	response.assisted = assisted
	response.fatal = not is_bonus and int(state.hull) == 0
	response.resolved = true # A submitted answer is final, including a miss.
	response.counter = ("independent" if not assisted else "assisted") if correct else ("solution" if response.resolved else "")
	var answer_reward := _reward_answer(result) if first and previous.is_empty() else {}
	var reward := int(answer_reward.get("xp", 0))
	if reward > 0:
		target.question_rewarded = true
	response.xp = reward
	response.answer_reward = answer_reward
	target.response = response
	if is_bonus:
		target.status = "resolved"
		target.correct = correct
		target.enhancement = correct
		state.bonus = target
	else:
		state.current = target
	var receipt := {"result": result.duplicate(true), "response": response.duplicate(true), "xp": reward, "answer_reward": answer_reward}
	state.receipts[transaction_id] = receipt
	return receipt.duplicate(true)

func upgrade_options() -> Array[Dictionary]:
	var choices: Array[Dictionary] = [
		{"id": "power", "title": "HOTTER ROUNDS", "description": "Permanent shot damage. Every cannon and drone benefits."},
		{"id": "cadence", "title": "FEED THE CANNONS", "description": "Permanently shorten your weapon firing cycle."},
		{"id": "overdrive", "title": "REACTOR OVERCLOCK", "description": "Raise the permanent overdrive multiplier."},
	]
	if int(state.upgrades.get("overdrive", 0)) >= 15:
		choices.remove_at(2)
	for module in module_catalog():
		if state.modules.has(module.id):
			choices.append({"id": "module:" + String(module.id), "title": String(module.title) + " +", "description": "Permanently improve this module's rank."})
	return choices

func choose_upgrade(key: String) -> bool:
	if int(state.pending_upgrades) <= 0:
		return false
	var eligible := false
	for choice in upgrade_options():
		if choice.id == key:
			eligible = true
	if not eligible:
		return false
	if key.begins_with("module:"):
		var module := key.trim_prefix("module:")
		state.modules[module] = int(state.modules[module]) + 1
	else:
		state.upgrades[key] = int(state.upgrades.get(key, 0)) + 1
	state.pending_upgrades = int(state.pending_upgrades) - 1
	_persist()
	return true

func module_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for milestone in MILESTONES:
		if milestone.id in ["ricochet", "lightning", "plasma", "carrier"]:
			var item: Dictionary = milestone.duplicate(true)
			item.unlock_level = item.level
			result.append(item)
	return result

func module_slots() -> int:
	return 2 if int(state.level) > 10 else 1

func equip_module(key: String) -> bool:
	if not state.modules.has(key):
		return false
	if key in state.equipped:
		state.equipped.erase(key)
	else:
		if state.equipped.size() >= module_slots():
			state.equipped.pop_front()
		state.equipped.append(key)
	_persist()
	return true

func _strength(rank: int) -> float:
	return float(mini(rank, 20)) + sqrt(float(maxi(0, rank - 20)))

func get_loadout() -> Dictionary:
	var bonus := bool(state.bonus.get("enhancement", false)) and int(state.bonus.get("target_level", -1)) == int(state.level)
	var loadout := {"turrets": 2 if int(state.level) > 3 else 1, "damage": 2.0 * (1.0 + 0.035 * _strength(int(state.upgrades.get("power", 0))) + 0.12 * _strength(int(state.shop_ranks.get("power", 0)))), "fire_rate": 1.0 + 0.025 * _strength(int(state.upgrades.get("cadence", 0))) + 0.10 * _strength(int(state.shop_ranks.get("cadence", 0))), "ricochet": 0, "lightning": 0, "plasma": 0, "carrier": 0, "overdrive": 1.0 + minf(0.3, float(state.upgrades.get("overdrive", 0)) * 0.02) + minf(0.4, float(state.shop_ranks.get("reactor", 0)) * 0.08), "bonus": bonus}
	if bonus:
		loadout.overdrive *= 1.25
	for key in ["ricochet", "lightning", "plasma", "carrier"]:
		if key in state.equipped:
			loadout[key] = int(state.modules.get(key, 0))
	var evolution := Evolution.stage(int(state.rank))
	loadout.ship_rank = int(state.rank)
	loadout.evolution = evolution
	loadout.damage *= 1.0 + evolution * 0.06
	loadout.fire_rate *= 1.0 + evolution * 0.04
	return loadout

func _reward_answer(result: Dictionary) -> Dictionary:
	var before := Evolution.stage(int(state.rank))
	var correct := bool(result.get("correct", false))
	var assisted := bool(result.get("assisted", false))
	var reward := {"xp": 0, "coins": 0, "gems": 0, "penalty": 0, "streak": 0, "evolved": false}
	if correct:
		state["answer_streak"] = 0 if assisted else int(state.get("answer_streak", 0)) + 1
		reward.streak = int(state.answer_streak)
		reward.xp = 40 if assisted else 100 + 15 * mini(4, reward.streak - 1)
		reward.coins = 8 if assisted else 20
		reward.gems = 1 if reward.streak > 0 and reward.streak % 3 == 0 else 0
		_add_xp(int(reward.xp))
		state.coins = int(state.coins) + int(reward.coins)
		state.gems = int(state.gems) + int(reward.gems)
	else:
		state["answer_streak"] = 0
		state.combo = 0
		reward.penalty = mini(15, int(state.coins))
		state.coins = int(state.coins) - int(reward.penalty)
	reward.evolved = Evolution.stage(int(state.rank)) > before
	return reward

func next_milestone() -> Dictionary:
	for milestone in MILESTONES:
		if int(milestone.level) >= int(state.level):
			return milestone.duplicate(true)
	var level := (int((int(state.level) - 1) / 25) + 1) * 25
	return {"level": level, "id": "veteran", "title": "VETERAN MODULE", "description": "Another permanent module evolution."}

func get_xp_needed() -> int:
	return 100 + 25 * (int(state.rank) - 1)

func _add_xp(amount: int) -> void:
	state.total_xp = int(state.total_xp) + amount
	state.xp = int(state.xp) + amount
	while int(state.xp) >= get_xp_needed():
		state.xp = int(state.xp) - get_xp_needed()
		state.rank = int(state.rank) + 1
		state.pending_upgrades = int(state.pending_upgrades) + 1

func _persist() -> void:
	if persistence_enabled:
		save_progress()

func save_progress() -> bool:
	if not persistence_enabled:
		return false
	var error := atomic_write(save_path, {"version": VERSION, "state": state})
	progress_warning = "" if error.is_empty() else "SHIP PROGRESS UNSAVED: " + error
	return error.is_empty()

func load_progress() -> void:
	if not persistence_enabled:
		return
	var loaded := read_valid(save_path)
	if loaded.has("error"):
		progress_warning = String(loaded.error)
		persistence_enabled = false
		return
	if loaded.is_empty():
		return
	state = loaded.state.duplicate(true)
	_upgrade_economy_schema()
	if state.bonus.get("status", "") == "started":
		state.bonus.status = "skipped"
		state.bonus.enhancement = false
		_persist()
	if loaded.get("recovered", false):
		if FileAccess.file_exists(save_path):
			var preserved := save_path + ".corrupt-%d" % Time.get_ticks_usec()
			if DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(preserved)) != OK:
				persistence_enabled = false
		progress_warning = "Recovered the previous valid ship save."

static func _integer(value: Variant, minimum: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) == floor(float(value)) and float(value) < 9.0e15

static func valid_question(question: Variant, allow_empty: bool = false) -> bool:
	if not question is Dictionary:
		return false
	if question.is_empty():
		return allow_empty
	for key in ["id", "concept", "prompt"]:
		if not question.get(key) is String or String(question[key]).is_empty():
			return false
	if not question.get("choices") is Array or question.choices.size() < 2 or question.choices.size() > 4:
		return false
	for choice in question.choices:
		if not choice is String:
			return false
	return _integer(question.get("answer")) and int(question.answer) < question.choices.size()

static func valid_response(response: Variant) -> bool:
	if not response is Dictionary:
		return false
	for key in ["resolved", "first_correct", "last_correct", "assisted", "fatal"]:
		if response.has(key) and not response[key] is bool:
			return false
	if response.has("counter") and response.counter not in ["", "independent", "assisted", "solution"]:
		return false
	for key in ["result", "first_result"]:
		if response.has(key) and not response[key] is Dictionary:
			return false
	return not response.has("attempts") or _integer(response.attempts)

static func valid(payload: Variant) -> bool:
	if not payload is Dictionary or payload.get("version", 0) != VERSION or not payload.get("state") is Dictionary:
		return false
	var candidate: Dictionary = payload.state
	for key in ["level", "rank", "xp", "total_xp", "pending_upgrades", "hull", "combo"]:
		if not _integer(candidate.get(key)):
			return false
	if int(candidate.level) < 1 or int(candidate.rank) < 1 or int(candidate.hull) > 3:
		return false
	for key in ["upgrades", "modules", "current", "block", "bonus", "receipts"]:
		if not candidate.get(key) is Dictionary:
			return false
	for ranks in [candidate.upgrades, candidate.modules]:
		for key in ranks:
			if not key is String or not _integer(ranks[key]):
				return false
	if not candidate.get("equipped") is Array or not candidate.get("profile_id") is String or not candidate.get("checkpoint_pending") is bool:
		return false
	for key in candidate.equipped:
		if not key is String or not candidate.modules.has(key):
			return false
	if candidate.equipped.size() > 2:
		return false
	for key in ["coins", "gems"]:
		if candidate.has(key) and not _integer(candidate[key]):
			return false
	if candidate.has("answer_streak") and not _integer(candidate.answer_streak):
		return false
	for key in ["shop_ranks", "offers", "boost", "last_clear_reward"]:
		if candidate.has(key) and not candidate[key] is Dictionary:
			return false
	for key in candidate.get("shop_ranks", {}):
		if key not in ["power", "cadence", "reactor"] or not _integer(candidate.shop_ranks[key]):
			return false
	if not _valid_boost(candidate.get("boost", {})):
		return false
	for key in candidate.get("offers", {}):
		if not key is String or not _valid_boost(candidate.offers[key]):
			return false
	var current: Dictionary = candidate.current
	if not current.is_empty():
		for key in ["id", "attempt_id", "attempt_status"]:
			if not current.get(key) is String:
				return false
		for key in ["level", "seed", "attempt"]:
			if not _integer(current.get(key)):
				return false
		if int(current.level) != int(candidate.level) or current.attempt_status not in ["ready", "active", "defeated"]:
			return false
		if not valid_question(current.get("question")) or not valid_response(current.get("response")) or not current.get("kill_receipts") is Dictionary:
			return false
		if not current.get("revive_used", false) is bool or not _valid_revive(current.get("revive", {}), String(current.attempt_id)):
			return false
		if current.get("revive", {}).get("status", "") == "claimed" and not bool(current.get("revive_used", false)):
			return false
		for key in current.kill_receipts:
			if not key is String or not _integer(current.kill_receipts[key]):
				return false
	var block: Dictionary = candidate.block
	if block.has("index") and (not _integer(block.index) or int(block.index) > 5):
		return false
	for key in ["core", "bonus"]:
		if block.has(key):
			if not block[key] is Array:
				return false
			for question in block[key]:
				if not valid_question(question, key == "bonus"):
					return false
	if block.has("summary") and not block.summary is Dictionary:
		return false
	var bonus: Dictionary = candidate.bonus
	if not bonus.is_empty():
		if not bonus.get("id") is String or bonus.get("status", "") not in ["pending", "started", "skipped", "resolved"] or not _integer(bonus.get("target_level"), 1):
			return false
		if not valid_question(bonus.get("question"), bonus.status in ["pending", "skipped"]) or not valid_response(bonus.get("response")):
			return false
		if not bonus.get("enhancement") is bool:
			return false
	for key in candidate.receipts:
		var receipt: Variant = candidate.receipts[key]
		if not key is String or not receipt is Dictionary or not receipt.get("result") is Dictionary or not valid_response(receipt.get("response")) or not _integer(receipt.get("xp")):
			return false
	return true

static func read_valid(path: String) -> Dictionary:
	var any_file := false
	for candidate in [path, path + ".previous.json"]:
		if not FileAccess.file_exists(candidate):
			continue
		any_file = true
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null:
			continue
		var parser := JSON.new()
		var error := parser.parse(file.get_as_text())
		file.close()
		if error == OK and valid(parser.data):
			var result: Dictionary = parser.data
			result.recovered = candidate != path
			return result
	return {"error": "Unreadable ship progress was left untouched. Export/recover before resetting."} if any_file else {}

static func atomic_write(path: String, payload: Dictionary) -> String:
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		return "Could not create save directory."
	var file := FileAccess.open(absolute + ".tmp", FileAccess.WRITE)
	if file == null:
		return "Could not write temporary save."
	file.store_string(JSON.stringify(payload))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return "Temporary save write failed."
	var backup := absolute + ".previous.json"
	var existing := FileAccess.file_exists(absolute)
	if existing:
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
			return "Could not rotate backup."
		if DirAccess.rename_absolute(absolute, backup) != OK:
			return "Could not preserve current save."
	if DirAccess.rename_absolute(absolute + ".tmp", absolute) != OK:
		if existing:
			DirAccess.rename_absolute(backup, absolute)
		return "Could not commit save."
	CloudSave.mark_dirty()
	return ""

func _upgrade_economy_schema() -> void:
	if not state.current.is_empty():
		if not state.current.has("revive"):
			state.current.revive = {}
		if not state.current.has("revive_used"):
			state.current.revive_used = false
	var defaults := {"coins": 0, "gems": 0, "shop_ranks": {"power": 0, "cadence": 0, "reactor": 0}, "offers": {}, "boost": {}, "last_clear_reward": {}}
	for key in defaults:
		if not state.has(key):
			state[key] = defaults[key]
	for key in ["power", "cadence", "reactor"]:
		if not state.shop_ranks.has(key):
			state.shop_ranks[key] = 0

func shop_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for key in ["power", "cadence", "reactor"]:
		var rank := int(state.shop_ranks.get(key, 0))
		var currency := "gems" if key == "reactor" else "coins"
		var cost := 6 + 3 * rank if key == "reactor" else int(minf(9.0e12, ceil(250.0 * pow(1.45, float(mini(rank, 35))) * (1.0 + float(maxi(0, rank - 35)) * 0.15))))
		var locked: bool = state.boost.get("status", "") == "active" and state.boost.get("kind", "") == "upgrade" and state.boost.get("item", "") == key
		var capped: bool = key == "reactor" and rank >= 5
		options.append({"id": key, "title": {"power": "HEAVY ROUNDS", "cadence": "RAPID FEED", "reactor": "REACTOR SURGE"}[key], "description": {"power": "Permanent shot damage; +12% of base damage per early tier.", "cadence": "Permanent firing speed; +10% per early tier.", "reactor": "A visible +8% reactor step, up to five shop tiers."}[key], "currency": currency, "cost": cost, "rank": rank, "affordable": int(state[currency]) >= cost and not locked and not capped, "locked": locked, "maxed": capped})
	return options

func _shop_item(key: String) -> Dictionary:
	for option in shop_options():
		if option.id == key:
			return option
	return {}

func buy_upgrade(key: String) -> bool:
	var item := _shop_item(key)
	if item.is_empty() or not bool(item.affordable):
		return false
	state[item.currency] = int(state[item.currency]) - int(item.cost)
	state.shop_ranks[key] = int(state.shop_ranks.get(key, 0)) + 1
	_persist()
	return true

func create_boost_offer(kind: String, item: String = "") -> Dictionary:
	if state.boost.get("status", "") == "active":
		return {"error": "A study boost is already in progress. Resume its saved questions first."}
	var offer: Dictionary
	if kind == "double_clear":
		if state.last_clear_reward.is_empty():
			return {"error": "Clear a sector before doubling its loot."}
		var level := int(state.last_clear_reward.level)
		offer = {"id": "%s/double/%d" % [state.profile_id, level], "status": "offered", "kind": kind, "item": "", "reward": {"coins": int(state.last_clear_reward.coins), "gems": int(state.last_clear_reward.gems), "xp": int(state.last_clear_reward.xp)}, "level": level, "questions": [], "index": 0, "responses": {}}
	elif kind == "upgrade":
		var option := _shop_item(item)
		if option.is_empty() or bool(option.get("maxed", false)):
			return {"error": "That upgrade is unavailable."}
		if int(state[option.currency]) >= int(option.cost):
			return {"error": "You already have enough to buy this upgrade."}
		offer = {"id": "%s/shop/%s/%d" % [state.profile_id, item, int(option.rank)], "status": "offered", "kind": kind, "item": item, "quote": {"currency": option.currency, "cost": option.cost, "rank": option.rank, "title": option.title}, "reward": {"coins": 0, "gems": 0, "xp": 0, "upgrade": item}, "questions": [], "index": 0, "responses": {}}
	else:
		return {"error": "Unknown study boost."}
	if state.offers.has(offer.id):
		offer = state.offers[offer.id].duplicate(true)
		if offer.status == "complete":
			return {"error": "This study reward was already claimed."}
	else:
		state.offers[offer.id] = offer.duplicate(true)
	state.boost = offer.duplicate(true)
	_persist()
	return state.boost.duplicate(true)

func start_boost(questions: Array) -> bool:
	if state.boost.get("status", "") == "active":
		return true
	if state.boost.get("status", "") != "offered" or questions.size() != 3:
		return false
	var seen: Dictionary = {}
	for question in questions:
		if not valid_question(question) or seen.has(question.id):
			return false
		seen[question.id] = true
	if state.boost.kind == "upgrade" and int(state.shop_ranks.get(state.boost.item, 0)) != int(state.boost.quote.rank):
		return false
	state.boost.questions = questions.duplicate(true)
	state.boost.status = "active"
	state.offers[state.boost.id] = state.boost.duplicate(true)
	_persist()
	return true

func cancel_boost() -> void:
	# Leaving is a pause, not a reset or a loss of completed answers.
	_persist()

func get_active_boost() -> Dictionary:
	return state.boost.duplicate(true)

func apply_boost_response(transaction_id: String, result: Dictionary, input: Dictionary) -> Dictionary:
	if state.receipts.has(transaction_id):
		return state.receipts[transaction_id].duplicate(true)
	var boost: Dictionary = state.boost
	var slot := int(input.slot)
	if boost.get("id", "") != input.target_id or boost.get("status", "") != "active" or slot != int(boost.index):
		return {"error": "This response does not match the active study boost."}
	var response: Dictionary = boost.responses.get(str(slot), {}).duplicate(true)
	var first: bool = input.stage == "first"
	var answer_reward := _reward_answer(result) if first and response.is_empty() else {}
	if first:
		response.first_result = result.duplicate(true)
		response.first_correct = bool(result.get("correct", false))
	response.result = result.duplicate(true)
	response.attempts = int(response.get("attempts", 0)) + (0 if input.stage == "solution" else 1)
	response.last_correct = bool(result.get("correct", false))
	response.assisted = bool(result.get("assisted", false))
	response.resolved = true # Each study slot completes after one answer.
	response.answer_reward = answer_reward
	response.counter = ("independent" if not response.assisted else "assisted") if response.last_correct else ("solution" if response.resolved else "")
	boost.responses[str(slot)] = response
	var awarded: Dictionary = {}
	if response.resolved:
		boost.index = slot + 1
		if int(boost.index) == 3:
			boost.status = "complete"
			if boost.kind == "double_clear":
				state.coins = int(state.coins) + int(boost.reward.coins)
				state.gems = int(state.gems) + int(boost.reward.gems)
				_add_xp(int(boost.reward.xp))
				awarded = boost.reward.duplicate(true)
			else:
				var quote: Dictionary = boost.quote
				var spent := mini(int(state[quote.currency]), int(quote.cost))
				state[quote.currency] = int(state[quote.currency]) - spent
				state.shop_ranks[boost.item] = int(quote.rank) + 1
				awarded = {"coins": 0, "gems": 0, "xp": 0, "upgrade": boost.item, "rank": int(quote.rank) + 1, "spent": spent, "covered": int(quote.cost) - spent, "currency": quote.currency}
	state.boost = boost
	state.offers[boost.id] = boost.duplicate(true)
	var receipt := {"result": result.duplicate(true), "response": response.duplicate(true), "xp": int(awarded.get("xp", 0)) + int(answer_reward.get("xp", 0)), "answer_reward": answer_reward, "reward": awarded, "boost_complete": boost.status == "complete", "boost_index": boost.index}
	state.receipts[transaction_id] = receipt
	return receipt.duplicate(true)

static func _valid_boost(boost: Variant) -> bool:
	if not boost is Dictionary:
		return false
	if boost.is_empty():
		return true
	if not boost.get("id") is String or boost.get("status", "") not in ["offered", "active", "complete"] or boost.get("kind", "") not in ["double_clear", "upgrade"]:
		return false
	if not boost.get("reward") is Dictionary or not boost.get("questions") is Array or not boost.get("responses") is Dictionary or not _integer(boost.get("index")) or int(boost.index) > 3:
		return false
	if (boost.status == "active" and int(boost.index) >= 3) or (boost.status == "complete" and int(boost.index) != 3) or (boost.status == "offered" and int(boost.index) != 0):
		return false
	if boost.status in ["active", "complete"] and boost.questions.size() != 3:
		return false
	for question in boost.questions:
		if not valid_question(question):
			return false
	for key in ["coins", "gems", "xp"]:
		if not _integer(boost.reward.get(key)):
			return false
	for key in boost.responses:
		if not key is String or key not in ["0", "1", "2"] or not valid_response(boost.responses[key]):
			return false
	if boost.kind == "upgrade":
		if boost.get("item", "") not in ["power", "cadence", "reactor"] or not boost.get("quote") is Dictionary:
			return false
		if boost.quote.get("currency", "") not in ["coins", "gems"] or not _integer(boost.quote.get("cost"), 1) or not _integer(boost.quote.get("rank")):
			return false
	return true

func start_revive(question: Dictionary) -> Dictionary:
	if state.current.is_empty() or state.current.get("attempt_status", "") != "defeated":
		return {"error": "A revive is available only after this ship is defeated."}
	if bool(state.current.get("revive_used", false)):
		return {"error": "This combat attempt has already used its revive."}
	if not state.current.get("revive", {}).is_empty():
		return state.current.revive.duplicate(true)
	if not valid_question(question):
		return {"error": "The revive needs a verified question."}
	state.current.revive = {"id": String(state.current.attempt_id) + "/revive", "status": "active", "question": question.duplicate(true), "response": {}, "submission": 0, "hint_used": false}
	if persistence_enabled and not save_progress():
		return {"error": progress_warning}
	return state.current.revive.duplicate(true)

func retry_revive() -> bool:
	return false # A wrong revive answer is final.


func apply_revive_response(transaction_id: String, result: Dictionary, input: Dictionary) -> Dictionary:
	if state.receipts.has(transaction_id):
		return state.receipts[transaction_id].duplicate(true)
	var revive: Dictionary = state.current.get("revive", {})
	if revive.get("id", "") != input.target_id or revive.get("status", "") != "active" or int(revive.get("submission", -1)) != int(input.revive_submission) or state.current.get("attempt_status", "") != "defeated" or bool(state.current.get("revive_used", false)):
		return {"error": "This response does not match the saved revive attempt."}
	var response: Dictionary = revive.get("response", {}).duplicate(true)
	var correct := bool(result.get("correct", false))
	var answer_reward := _reward_answer(result) if int(input.revive_submission) == 0 and response.is_empty() else {}
	response.answer_reward = answer_reward
	if int(input.revive_submission) == 0:
		response.first_result = result.duplicate(true)
		response.first_correct = correct
	response.result = result.duplicate(true)
	response.attempts = int(input.revive_submission) + 1
	response.last_correct = correct
	response.assisted = bool(result.get("assisted", false))
	response.resolved = correct
	response.counter = ("assisted" if response.assisted else "independent") if correct else ""
	revive.response = response
	revive.status = "earned" if correct else "feedback"
	state.current.revive = revive
	var receipt := {"result": result.duplicate(true), "response": response.duplicate(true), "xp": int(answer_reward.get("xp", 0)), "answer_reward": answer_reward, "revive_earned": correct, "revive_status": revive.status}
	state.receipts[transaction_id] = receipt
	return receipt.duplicate(true)

func claim_revive() -> bool:
	if state.current.is_empty() or state.current.get("attempt_status", "") != "defeated" or bool(state.current.get("revive_used", false)):
		return false
	var revive: Dictionary = state.current.get("revive", {})
	if revive.get("status", "") != "earned" or not bool(revive.get("response", {}).get("last_correct", false)):
		return false
	state.current.revive_used = true
	state.current.revive.status = "claimed"
	state.current.attempt_status = "active"
	state.hull = 3
	# Identity, kill receipts, core response and all earned rewards remain intact.
	return save_progress() if persistence_enabled else true

static func _valid_revive(revive: Variant, attempt_id: String) -> bool:
	if not revive is Dictionary:
		return false
	if revive.is_empty():
		return true
	if revive.get("id", "") != attempt_id + "/revive" or revive.get("status", "") not in ["active", "feedback", "earned", "claimed"]:
		return false
	if not valid_question(revive.get("question")) or not valid_response(revive.get("response")) or not _integer(revive.get("submission")) or not revive.get("hint_used") is bool:
		return false
	if revive.status in ["earned", "claimed"] and (not bool(revive.response.get("resolved", false)) or not bool(revive.response.get("last_correct", false))):
		return false
	if revive.status == "feedback" and (revive.response.is_empty() or bool(revive.response.get("resolved", false))):
		return false
	return true
