extends SceneTree
const Study = preload("res://scripts/study_model.gd")
const Progression = preload("res://scripts/progression_model.gd")
const Journal = preload("res://scripts/response_journal.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_test_one_claim()
	_test_wrong_retries()
	_test_independent_sessions()
	_test_interrupted_answers()
	_test_claim_save_failure()
	_test_validation_and_migration()
	if failures.is_empty():
		print("Revive model: ", checks, " checks passed.")
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
	var base := path if not path.is_empty() else "user://revive-model-%d" % Time.get_ticks_usec()
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

func defeated(c: Dictionary) -> void:
	c.game.ensure_encounter(c.study.question_bank[0])
	c.game.begin_attempt()
	c.journal.skip_core()
	c.game.grant_kill("already-defeated", "ordinary")
	c.game.mark_defeated()

func revive_question(c: Dictionary) -> Dictionary:
	return c.study.question_bank[6].duplicate(true)

func _test_one_claim() -> void:
	var c := setup()
	check(c.game.start_revive(revive_question(c)).has("error"), "An undefeated ship cannot begin a revive.")
	defeated(c)
	var encounter: Dictionary = c.game.state.current.duplicate(true)
	var old_xp := int(c.game.state.total_xp)
	var old_coins := int(c.game.state.coins)
	var question := revive_question(c)
	var revive: Dictionary = c.game.start_revive(question)
	check(revive.status == "active" and revive.id == encounter.attempt_id + "/revive", "Revive is bound to the exact defeated combat attempt.")
	c.game.start_revive(c.study.question_bank[7])
	check(c.game.state.current.revive.question.id == question.id, "Reopening cannot reroll the saved revive question.")
	check(not c.game.claim_revive(), "No answer means no revive claim.")
	var result: Dictionary = c.journal.resolve_revive(question, true, false, -1)
	check(result.revive_earned and c.game.state.current.revive.status == "earned", "Actual correct answer earns revival.")
	check(int(c.game.state.hull) == 0, "Answer feedback remains safely defeated until explicit claim.")
	check(c.game.claim_revive(), "Earned revival can be claimed once.")
	check(int(c.game.state.hull) == 3 and c.game.state.current.attempt_status == "active", "Claim restores hull and active combat status.")
	check(c.game.state.current.attempt_id == encounter.attempt_id and c.game.state.current.kill_receipts == encounter.kill_receipts, "Revive preserves attempt identity and kill deduplication.")
	check(c.game.state.current.response == encounter.response, "Revive leaves the original core result unchanged.")
	check(c.game.grant_kill("already-defeated", "ordinary") == 0, "Reloaded revived battle cannot repay earlier kills.")
	check(int(c.game.state.total_xp) == old_xp + 100 and int(c.game.state.coins) == old_coins + 20, "Correct revive pays one answer reward; claiming grants no duplicate reward.")
	check(not c.game.claim_revive(), "Repeated claim cannot grant another revival.")
	c.game.mark_defeated()
	check(c.game.start_revive(question).has("error"), "Second death in one combat attempt cannot revive again.")
	c.game.begin_attempt()
	c.game.mark_defeated()
	var next: Dictionary = c.game.start_revive(question)
	check(not next.has("error") and next.id != revive.id, "Fresh combat retry receives a fresh revival allowance.")

func _test_wrong_retries() -> void:
	var c := setup()
	defeated(c)
	var question := revive_question(c)
	var revive: Dictionary = c.game.start_revive(question)
	var result: Dictionary = c.journal.resolve_revive(question, false, false, -1)
	check(not result.revive_earned and not c.game.claim_revive(), "A wrong revive grants nothing.")
	for attempt in range(3):
		check(not c.game.retry_revive(), "A submitted revive cannot reopen.")
		var duplicate: Dictionary = c.journal.resolve_revive(question, true, false, -1)
		check(not duplicate.correct and not duplicate.revive_earned, "Attempted correction returns the original miss.")
		check(int(c.study.history.questions[question.id].core_attempts) == 1, "Duplicate submission adds no learning attempt.")
	var summary: Dictionary = c.study.get_revive_summary(String(revive.id))
	check(int(summary.core_answered) == 1 and int(summary.core_correct) == 0, "Miss stays wrong in the revive recap.")
	check(int(c.study.get_summary().core_answered) == 0, "Revive remains outside core denominator.")


func _test_independent_sessions() -> void:
	var c := setup()
	c.game.create_boost_offer("upgrade", "power")
	c.game.start_boost([c.study.question_bank[1], c.study.question_bank[2], c.study.question_bank[3]])
	c.journal.resolve_boost(c.study.question_bank[1], false, false, -1)
	var boost: Dictionary = c.game.state.boost.duplicate(true)
	var boost_summary: Dictionary = c.study.get_boost_summary(String(boost.id)).duplicate(true)
	defeated(c)
	var question := revive_question(c)
	c.game.start_revive(question)
	c.game.state.current.revive.hint_used = true
	var result: Dictionary = c.journal.resolve_revive(question, true, false, 1)
	check(result.assisted and result.first_attempt, "An explicit hint on the first revival question remains assisted.")
	check(c.game.state.boost == boost and c.study.get_boost_summary(String(boost.id)) == boost_summary, "An active study boost remains untouched by revival.")
	check(int(c.study.get_summary().core_answered) == 0, "Revival does not change core recap.")

func _test_interrupted_answers() -> void:
	for boundary in ["journal", "study", "arcade"]:
		var c := setup(true)
		defeated(c)
		var question := revive_question(c)
		var revive: Dictionary = c.game.start_revive(question)
		c.journal.test_interrupt_after = boundary
		check(c.journal.resolve_revive(question, true, false, -1).has("error"), "Interrupt revival after " + boundary)
		var restored := setup(true, c.path)
		restored.study.clock_override_unix += Study.DAY_SECONDS * 2
		restored.study.load_progress()
		restored.game.load_progress()
		check(restored.journal.recover(), "Recover pending revival response after " + boundary)
		check(restored.game.state.current.revive.status == "earned" and int(restored.game.state.hull) == 0, "Earned unclaimed revive survives " + boundary)
		check(int(restored.study.history.questions[question.id].core_attempts) == 1 and int(restored.study.history.questions[question.id].last_seen_at) == 1800000000, "One actual response with original timestamp survives " + boundary)
		check(int(restored.study.get_revive_summary(String(revive.id)).core_correct) == 1, "Separate revive recap survives " + boundary)
		check(restored.game.claim_revive(), "Recovered correct answer can claim once after " + boundary)
		check(restored.journal.recover() and not restored.game.claim_revive(), "Repeated recovery cannot grant another revive after " + boundary)
	# Wrong answer persistence must also retain numbered guided submissions.
	var c := setup(true)
	defeated(c)
	var question := revive_question(c)
	c.game.start_revive(question)
	c.journal.resolve_revive(question, false, false, -1)
	var restored := setup(true, c.path)
	restored.study.load_progress()
	restored.game.load_progress()
	check(not restored.game.retry_revive(), "Wrong feedback remains final after reload.")
	var result: Dictionary = restored.journal.resolve_revive(question, true, false, -1)
	check(not result.correct and not result.revive_earned, "Reloaded corrective input cannot replace the miss.")

func _test_claim_save_failure() -> void:
	var c := setup(true)
	defeated(c)
	var question := revive_question(c)
	c.game.start_revive(question)
	c.journal.resolve_revive(question, true, false, -1)
	var original_path: String = c.game.save_path
	var blocked_path: String = c.path + "/blocker"
	var file := FileAccess.open(blocked_path, FileAccess.WRITE)
	file.store_string("Blocked test directory")
	file.close()
	c.game.save_path = blocked_path + "/ship.json"
	check(not c.game.claim_revive(), "Claim save failure is reported honestly.")
	check(c.game.state.current.revive.status == "claimed" and not c.game.progress_warning.is_empty(), "Pending claim remains recoverable in memory.")
	c.game.save_path = original_path
	check(c.game.save_progress(), "Retry can durably save the pending claim.")
	var restored := setup(true, c.path)
	restored.game.load_progress()
	check(restored.game.state.current.revive.status == "claimed" and int(restored.game.state.hull) == 3, "Claimed status and hull survive successful retry.")
	check(not restored.game.claim_revive(), "Loading the committed claim cannot claim twice.")

func _test_validation_and_migration() -> void:
	var c := setup(true)
	defeated(c)
	var original: Dictionary = c.game.state.duplicate(true)
	original.current.erase("revive")
	original.current.erase("revive_used")
	Progression.atomic_write(c.game.save_path, {"version": 1, "state": original})
	c.game.load_progress()
	check(c.game.state.current.revive.is_empty() and not c.game.state.current.revive_used, "Pre-revival save safely gets optional defaults.")
	c.game.start_revive(revive_question(c))
	var payload := {"version": 1, "state": c.game.state.duplicate(true)}
	payload.state.current.revive.id = "another-attempt/revive"
	check(not Progression.valid(payload), "Revive from another attempt is rejected.")
	payload = {"version": 1, "state": c.game.state.duplicate(true)}
	payload.state.current.revive.status = "earned"
	check(not Progression.valid(payload), "Earned revive requires a correct saved response.")
	payload = {"version": 1, "state": c.game.state.duplicate(true)}
	payload.state.current.revive.question = "broken"
	check(not Progression.valid(payload), "Malformed saved revive question is rejected.")
	check(not c.study._valid_progress({"version": 1, "history": {"questions": {}, "concepts": {}}, "revive_sessions": {"bad": {"attempts": {}, "stats": {}}}}), "Malformed revival study counters are rejected.")
