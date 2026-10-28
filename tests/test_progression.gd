extends SceneTree
const Model = preload("res://scripts/progression_model.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_test_levels_rewards()
	_test_attempts()
	_test_bonus_and_modules()
	_test_save_recovery()
	_test_nested_validation()
	if failures.is_empty():
		print("Progression: ", checks, " checks passed.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func model():
	var result = Model.new()
	result.persistence_enabled = false
	return result

func question(identifier: String = "fixture") -> Dictionary:
	return {"id": identifier, "concept": "fixture", "prompt": "Fixture", "choices": ["A", "B"], "answer": 0}

func ready_clear(game) -> void:
	game.ensure_encounter(question("q%d" % int(game.state.level)))
	game.begin_attempt()
	game.state.current.response = {"resolved": true, "counter": "independent"}

func _test_levels_rewards() -> void:
	var game = model()
	check(game.get_xp_needed() == 100, "Rank 1 needs 100 XP.")
	for level in range(1, 131):
		ready_clear(game)
		var old_xp := int(game.state.total_xp)
		var result: Dictionary = game.clear_encounter()
		check(int(game.state.level) == level + 1, "Clear advances exactly once at level %d." % level)
		check(int(game.state.total_xp) - old_xp == 60 + 5 * mini(level, 20) + (50 if level % 5 == 0 else 0), "Deterministic first-clear and checkpoint XP at %d." % level)
		check(bool(game.state.checkpoint_pending) == (level % 5 == 0), "Checkpoint is every fifth clear.")
		check(game.clear_encounter().has("error"), "Repeated completion cannot reward twice.")
		if level % 5 == 0:
			game.acknowledge_checkpoint()
		if level == 3:
			check(int(game.get_loadout().turrets) == 2, "Third level permanently unlocks second orbital.")
		if level == 5:
			check(game.state.modules.has("ricochet"), "First boss awards ricochet.")
		if level == 10:
			check(game.module_slots() == 2, "Tenth level unlocks second module slot.")
	check(int(game.state.level) == 131, "There is no five/100-level terminal branch.")
	check(int(game.next_milestone().level) == 150, "Veteran milestones continue.")
	var rank := int(game.state.rank)
	var xp := int(game.state.xp)
	check(int(game.state.total_xp) == int((rank - 1) * 100 + 25 * (rank - 1) * (rank - 2) / 2) + xp, "Rank accounting preserves every XP point.")
	check(xp < game.get_xp_needed(), "Rank overflow is fully processed.")
	var pending := int(game.state.pending_upgrades)
	check(game.choose_upgrade("power"), "An earned rank choice can be spent.")
	check(int(game.state.pending_upgrades) == pending - 1, "Spending consumes exactly one choice.")
	check(not game.choose_upgrade("invented"), "Unknown upgrade cannot consume a choice.")
	game.state.pending_upgrades = 0
	check(not game.choose_upgrade("power"), "No free rank choices.")
	game.state.level = 1000001
	check(int(game.next_milestone().level) > 1000000, "High-level next reward stays ahead.")

func _test_attempts() -> void:
	var game = model()
	game.state.hull = 2
	var encounter: Dictionary = game.ensure_encounter(question())
	var identifier: String = encounter.id
	var seed_value := int(encounter.seed)
	game.ensure_encounter(question("different"))
	check(game.state.current.question.id == "fixture", "Existing encounter retains original question.")
	game.begin_attempt()
	check(int(game.state.hull) == 2, "First attempt retains earned hull state.")
	var first_attempt: String = game.state.current.attempt_id
	check(game.grant_kill("unit-1", "ordinary") == 4, "Ordinary kill awards XP.")
	check(game.grant_kill("unit-1", "ordinary") == 0, "Duplicate kill event is ignored.")
	game.state.current.response = {"resolved": true, "counter": "solution", "fatal": true}
	game.mark_defeated()
	check(int(game.state.total_xp) == 4, "Defeat preserves genuine earned combat XP.")
	check(game.grant_kill("late", "boss") == 0, "Late kill after defeat cannot award XP.")
	game.begin_attempt()
	check(int(game.state.hull) == 3, "Retry restores three hull pips.")
	check(game.state.current.id == identifier and int(game.state.current.seed) == seed_value, "Retry keeps encounter identity and seed.")
	check(game.state.current.attempt_id != first_attempt, "Retry receives fresh attempt identity.")
	check(game.state.current.response.counter == "solution" and not game.state.current.response.fatal, "Retry retains counter and clears transient fatal status.")
	check(game.grant_kill("unit-1", "ordinary") == 4, "An actual new combat kill can earn XP on a new attempt.")
	game.state.hull = 1
	game.clear_encounter()
	check(int(game.state.hull) == 2, "Clear repairs one hull pip.")

func _test_bonus_and_modules() -> void:
	var game = model()
	game.state.level = 2
	ready_clear(game)
	game.clear_encounter()
	check(game.state.bonus.status == "pending" and int(game.state.bonus.target_level) == 3, "Second clear offers next-encounter bonus.")
	check(not game.start_bonus(), "Missing bonus question cannot start clock.")
	check(game.start_bonus(question("bonus")), "Verified bonus question starts once.")
	check(not game.start_bonus(question("bonus")), "Started bonus cannot restart.")
	game.state.bonus.status = "resolved"
	game.state.bonus.enhancement = true
	ready_clear(game)
	check(bool(game.get_loadout().bonus), "Earned enhancement applies to target encounter.")
	game.mark_defeated()
	game.begin_attempt()
	check(bool(game.get_loadout().bonus), "Enhancement survives retry.")
	game.clear_encounter()
	check(game.state.bonus.is_empty() and not game.get_loadout().bonus, "Enhancement expires on target clear.")
	game.state.modules = {"ricochet": 2, "lightning": 3, "plasma": 1, "carrier": 1}
	game.state.equipped = []
	check(game.equip_module("ricochet"), "Unlocked module equips.")
	game.equip_module("lightning")
	check(game.state.equipped == ["lightning"], "Single slot replaces prior module predictably.")
	check(int(game.get_loadout().ricochet) == 0 and int(game.get_loadout().lightning) == 3, "Only equipped modules affect combat.")
	game.state.level = 11
	game.equip_module("ricochet")
	check(game.state.equipped.size() == 2, "Dual bay supports a combined build.")
	check(not game.equip_module("fiction"), "Locked/nonexistent module cannot equip.")

func _test_save_recovery() -> void:
	var path := "user://progression-unit-%d/ship.json" % Time.get_ticks_usec()
	var game = Model.new()
	game.save_path = path
	game.ensure_encounter(question())
	game.begin_attempt()
	game.grant_kill("persisted", "elite")
	var clone = Model.new()
	clone.save_path = path
	clone.load_progress()
	check(int(clone.state.total_xp) == 20, "Combat XP survives loading.")
	check(clone.grant_kill("persisted", "elite") == 0, "Kill receipt survives loading.")
	clone.save_progress()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("broken save")
	file.close()
	var recovered = Model.new()
	recovered.save_path = path
	recovered.load_progress()
	check(int(recovered.state.total_xp) == 20, "Corrupt primary recovers last valid backup.")
	check(not recovered.progress_warning.is_empty(), "Backup recovery is disclosed.")
	var invalid_path := "user://progression-unit-%d/broken.json" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(invalid_path.get_base_dir()))
	file = FileAccess.open(invalid_path, FileAccess.WRITE)
	file.store_string("broken only copy")
	file.close()
	var invalid = Model.new()
	invalid.save_path = invalid_path
	invalid.load_progress()
	check(not invalid.persistence_enabled, "Unrecoverable save cannot be silently overwritten.")
	check(FileAccess.get_file_as_string(invalid_path) == "broken only copy", "Unreadable file remains untouched.")

func _test_nested_validation() -> void:
	var game = model()
	game.ensure_encounter(question())
	var valid_payload := {"version": 1, "state": game.state.duplicate(true)}
	check(Model.valid(valid_payload), "Normal current encounter is a valid saved state.")
	for key in ["question", "response", "kill_receipts"]:
		var payload: Dictionary = valid_payload.duplicate(true)
		payload.state.current[key] = "bad data"
		check(not Model.valid(payload), "Reject malformed nested current " + key)
	var payload: Dictionary = valid_payload.duplicate(true)
	payload.state.modules = {"ricochet": "huge"}
	check(not Model.valid(payload), "Reject nonnumeric module ranks.")
	payload = valid_payload.duplicate(true)
	payload.state.block = {"core": ["not a question"], "index": 0}
	check(not Model.valid(payload), "Reject malformed selected question block.")
	payload = valid_payload.duplicate(true)
	payload.state.checkpoint_pending = "yes"
	check(not Model.valid(payload), "Reject malformed checkpoint flag.")
	payload = valid_payload.duplicate(true)
	payload.state.receipts = {"tx": {"result": [], "response": {}, "xp": 40}}
	check(not Model.valid(payload), "Reject malformed durable response receipt.")
	payload = valid_payload.duplicate(true)
	payload.state.bonus = {"id": "unavailable", "status": "skipped", "target_level": 3, "question": {}, "response": {}, "enhancement": false}
	check(Model.valid(payload), "A skipped unavailable bonus remains a valid save.")
