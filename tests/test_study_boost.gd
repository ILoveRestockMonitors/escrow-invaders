extends SceneTree
const Study = preload("res://scripts/study_model.gd")
const Progression = preload("res://scripts/progression_model.gd")
const Journal = preload("res://scripts/response_journal.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_test_optional_combat()
	_test_double_loot()
	_test_upgrade_offer()
	_test_guided_boost()
	_test_crash_recovery()
	_test_skip_recovery()
	_test_legacy_economy()
	_test_invalid_boost_state()
	_test_upgrade_commit_recovery()
	if failures.is_empty():
		print("Study boosts: ", checks, " checks passed.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func setup(persistent: bool = false, path: String = "") -> Dictionary:
	var base := path if not path.is_empty() else "user://study-boost-%d" % Time.get_ticks_usec()
	var study := Study.new()
	study.persistence_enabled = persistent
	study.save_path = base + "/study.json"
	study.clock_override_unix = 1800000000
	var game := Progression.new()
	game.persistence_enabled = persistent
	game.save_path = base + "/ship.json"
	var journal := Journal.new(study, game)
	journal.persistence_enabled = persistent
	journal.journal_path = base + "/journal.json"
	return {"study": study, "game": game, "journal": journal, "path": base}

func encounter(c: Dictionary) -> void:
	c.game.ensure_encounter(c.study.question_bank[0])
	c.game.begin_attempt()

func clear_without_study(c: Dictionary) -> Dictionary:
	encounter(c)
	var skipped: Dictionary = c.journal.skip_core()
	check(not skipped.has("error") and skipped.response.skipped, "Optional core skip is durably represented.")
	return c.game.clear_encounter()

func questions(c: Dictionary) -> Array:
	return [c.study.question_bank[1].duplicate(true), c.study.question_bank[2].duplicate(true), c.study.question_bank[3].duplicate(true)]

func answer_current(c: Dictionary, correct: bool = true, assisted: bool = false, counter: String = "independent") -> Dictionary:
	var boost: Dictionary = c.game.state.boost
	return c.journal.resolve_boost(boost.questions[int(boost.index)], correct, assisted, -1, counter)

func _test_optional_combat() -> void:
	var c := setup()
	for level in range(1, 6):
		encounter(c)
		c.game.state.combo = 2
		c.journal.skip_core()
		check(int(c.game.state.hull) == 3 and int(c.game.state.combo) == 2, "Skipping has no hull or combo penalty.")
		for enemy in range(12):
			c.game.grant_kill("escort-%d" % enemy, "ordinary")
		c.game.grant_kill("leader", "boss" if level == 5 else "elite")
		var result: Dictionary = c.game.clear_encounter()
		check(int(result.coins) == 60 + 5 * level, "Clear has guaranteed coin loot without study.")
		check(int(result.gems) == (5 if level == 5 else 1), "Gem drops are available without studying.")
		check(c.game.clear_encounter().has("error"), "Duplicate clear cannot double currencies.")
	check(int(c.game.state.level) == 6, "Five skipped questions do not gate combat progression.")
	check(c.study.history.questions.is_empty() and c.study.response_receipts.is_empty(), "Skipping fabricates no academic response or learning receipt.")
	check(int(c.study.get_summary().core_answered) == 0, "Skipped questions do not inflate checkpoint denominator.")
	check(int(c.game.state.gems) == 9 and int(c.game.state.coins) > 250, "Ordinary playing earns both permanent-upgrade currencies.")
	var before: float = c.game.get_loadout().damage
	check(c.game.buy_upgrade("power"), "Normal combat wallet can buy a permanent upgrade.")
	check(is_equal_approx(float(c.game.get_loadout().damage) / before, 1.12), "First paid power tier is a visible twelve-percent step.")
	check(int(c.game.shop_options()[0].cost) == 363, "Next coin tier has predictable rounded pricing.")

func _test_double_loot() -> void:
	var c := setup()
	var clear: Dictionary = clear_without_study(c)
	var offer: Dictionary = c.game.create_boost_offer("double_clear")
	check(offer.reward.coins == clear.coins and offer.reward.gems == clear.gems and offer.reward.xp == clear.xp, "Double offer quotes exact clear loot, including XP.")
	check(not c.game.start_boost([questions(c)[0], questions(c)[0], questions(c)[2]]), "A boost requires three distinct questions.")
	check(c.game.start_boost(questions(c)), "Three verified questions activate the optional offer.")
	check(c.game.create_boost_offer("upgrade", "power").has("error"), "An active boost cannot be overwritten.")
	var old_coins := int(c.game.state.coins)
	var old_xp := int(c.game.state.total_xp)
	var first_question: Dictionary = c.game.state.boost.questions[0]
	answer_current(c)
	check(int(c.game.state.coins) == old_coins + 20 and int(c.game.state.total_xp) == old_xp + 100, "A correct partial boost immediately pays its answer reward; set loot waits.")
	c.journal.resolve_boost(first_question, true, false, -1)
	check(int(c.game.state.boost.index) == 1, "Duplicate prior-slot answer cannot advance next slot.")
	c.game.cancel_boost()
	check(int(c.game.get_active_boost().index) == 1, "Leaving preserves completed study work.")
	answer_current(c)
	var result := answer_current(c)
	check(result.boost_complete and int(c.game.state.boost.index) == 3, "Third resolution completes the offer.")
	check(int(c.game.state.coins) == old_coins + int(clear.coins) + 60, "One extra matching clear coin reward.")
	check(int(c.game.state.total_xp) == old_xp + int(clear.xp) + 345, "One extra matching clear XP reward.")
	check(int(c.game.state.gems) == int(clear.gems) * 2 + 1, "One extra matching gem reward.")
	check(c.game.create_boost_offer("double_clear").has("error"), "Completed clear offer cannot mint another boost reward.")
	check(int(c.study.get_summary().core_answered) == 0, "Optional study is separate from five-core checkpoint count.")
	check(int(c.study.get_boost_summary(String(offer.id)).core_answered) == 3, "All three actual retrievals have their own learning summary.")

func _test_upgrade_offer() -> void:
	var c := setup()
	c.game.state.coins = 100
	var offer: Dictionary = c.game.create_boost_offer("upgrade", "power")
	check(int(offer.quote.cost) == 250 and int(offer.quote.rank) == 0, "Upgrade offer fixes its exact target tier and price.")
	check(c.game.start_boost(questions(c)), "Short-wallet study can activate an install offer.")
	c.game.state.coins = 500
	check(not c.game.buy_upgrade("power"), "The quoted tier cannot be bought out from under an active boost.")
	check(c.game.buy_upgrade("cadence"), "Other purchases remain available during a saved boost.")
	c.game.state.coins = 40
	answer_current(c)
	answer_current(c)
	var result := answer_current(c)
	check(int(c.game.state.shop_ranks.power) == 1 and int(c.game.state.coins) == 0, "Final retrieval atomically installs quoted upgrade using available coins.")
	check(int(result.reward.spent) == 100 and int(result.reward.covered) == 150, "Receipt records actual contribution and bound study coverage.")
	check(int(result.reward.coins) == 0 and int(c.game.state.total_xp) == 345, "Install set pays three answer rewards alongside its quoted upgrade.")
	check(int(c.game.state.shop_ranks.cadence) == 1, "Unrelated purchased tier survives boost completion.")
	var next: Dictionary = c.game.create_boost_offer("upgrade", "power")
	check(int(next.quote.rank) == 1 and next.id != offer.id, "A later shop tier has its own offer identity.")

func _test_guided_boost() -> void:
	var c := setup()
	clear_without_study(c)
	var offer: Dictionary = c.game.create_boost_offer("double_clear")
	c.game.start_boost(questions(c))
	c.game.state.hull = 1
	c.game.state.combo = 5
	var question: Dictionary = c.game.state.boost.questions[0]
	answer_current(c, false)
	check(int(c.game.state.boost.index) == 1, "Wrong first answer is final and advances its slot.")
	check(int(c.game.state.hull) == 1 and int(c.game.state.combo) == 0, "Optional miss resets combo without losing combat hull.")
	check(c.journal.resolve_boost(question, true, true, -1, "assisted").has("error"), "Old question cannot accept a guided retry.")
	answer_current(c)
	answer_current(c, false)
	check(c.game.state.boost.status == "complete", "Three single answers finish the learning set.")
	var summary: Dictionary = c.study.get_boost_summary(String(offer.id))
	check(int(summary.core_answered) == 3 and int(summary.core_correct) == 1, "Misses stay wrong in the three-question recap.")
	check(int(c.study.get_summary().core_answered) == 0, "Boost remains separate from core denominator.")


func _test_crash_recovery() -> void:
	for boundary in ["journal", "study", "arcade"]:
		var c := setup(true)
		clear_without_study(c)
		var offer: Dictionary = c.game.create_boost_offer("double_clear")
		c.game.start_boost(questions(c))
		answer_current(c)
		answer_current(c)
		c.journal.test_interrupt_after = boundary
		var result := answer_current(c)
		check(result.has("error"), "Injected boost interruption at " + boundary)
		var restored := setup(true, c.path)
		restored.study.clock_override_unix += Study.DAY_SECONDS * 3
		restored.study.load_progress()
		restored.game.load_progress()
		check(restored.journal.recover(), "Boost transaction recovers after " + boundary)
		check(restored.game.state.boost.status == "complete" and int(restored.game.state.coins) == 190 and int(restored.game.state.gems) == 3, "One complete double reward after " + boundary)
		check(int(restored.study.get_boost_summary(String(offer.id)).core_answered) == 3, "Exactly three submitted retrievals after " + boundary)
		check(int(restored.study.get_summary().core_answered) == 0, "Checkpoint summary remains separate after " + boundary)
		check(restored.journal.recover() and int(restored.game.state.total_xp) == 475, "Repeated recovery cannot multiply clear XP after " + boundary)

func _test_skip_recovery() -> void:
	var c := setup(true)
	encounter(c)
	c.journal.test_interrupt_after = "journal"
	c.journal.skip_core()
	var restored := setup(true, c.path)
	restored.study.load_progress()
	restored.game.load_progress()
	check(restored.journal.recover(), "An interrupted academic-neutral skip can recover.")
	check(restored.game.state.current.response.skipped and restored.game.state.current.response.counter == "solution", "Skip resumes with the weak combat override.")
	check(restored.study.history.questions.is_empty() and restored.study.response_receipts.is_empty(), "Skip recovery does not fabricate study data.")
	check(int(restored.game.state.hull) == 3 and int(restored.game.state.total_xp) == 0, "Skip recovery has no answer penalty/reward.")

func _test_legacy_economy() -> void:
	var c := setup(true)
	var old_state: Dictionary = c.game.state.duplicate(true)
	for key in ["coins", "gems", "shop_ranks", "offers", "boost", "last_clear_reward"]:
		old_state.erase(key)
	check(Progression.atomic_write(c.game.save_path, {"version": 1, "state": old_state}).is_empty(), "Write pre-economy ship fixture.")
	c.game.load_progress()
	check(int(c.game.state.coins) == 0 and int(c.game.state.gems) == 0 and c.game.state.offers.is_empty(), "Pre-economy ship save gets clean new defaults.")
	check(c.game.save_progress(), "Migrated ship state can save normally.")

func _test_invalid_boost_state() -> void:
	var c := setup()
	clear_without_study(c)
	c.game.create_boost_offer("double_clear")
	c.game.start_boost(questions(c))
	var payload := {"version": 1, "state": c.game.state.duplicate(true)}
	payload.state.boost.index = 3
	check(not Progression.valid(payload), "Active boost cannot load a completed/out-of-range slot.")
	payload = {"version": 1, "state": c.game.state.duplicate(true)}
	payload.state.boost.responses = {"broken": {}}
	check(not Progression.valid(payload), "Malformed saved boost slot is rejected.")
	check(not c.study._valid_progress({"version": 1, "history": {"questions": {}, "concepts": {}}, "boost_sessions": {"broken": {"attempts": {}, "stats": {"core_answered": "three"}}}}), "Malformed saved boost academic counters are rejected.")

func _test_upgrade_commit_recovery() -> void:
	for boundary in ["study", "arcade"]:
		var c := setup(true)
		c.game.state.coins = 200
		c.game.create_boost_offer("upgrade", "power")
		c.game.start_boost(questions(c))
		answer_current(c)
		answer_current(c)
		c.journal.test_interrupt_after = boundary
		check(answer_current(c).has("error"), "Upgrade completion interrupted after " + boundary)
		var restored := setup(true, c.path)
		restored.study.load_progress()
		restored.game.load_progress()
		check(restored.journal.recover(), "Bound install recovers after " + boundary)
		check(int(restored.game.state.shop_ranks.power) == 1 and int(restored.game.state.coins) == 10, "Exactly one tier installed and one contribution spent after " + boundary)
		check(restored.journal.recover() and int(restored.game.state.shop_ranks.power) == 1 and int(restored.game.state.coins) == 10, "Repeated install recovery cannot spend or upgrade twice after " + boundary)
