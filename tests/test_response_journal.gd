extends SceneTree
const Study = preload("res://scripts/study_model.gd")
const Progression = preload("res://scripts/progression_model.gd")
const Journal = preload("res://scripts/response_journal.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_test_deduplication()
	_test_guided_and_solution()
	_test_fatal()
	_test_interrupted_commits()
	_test_bonus()
	_test_legacy_learning()
	_test_write_failure()
	_test_study_backup()
	_test_late_solution()
	if failures.is_empty():
		print("Response journal: ", checks, " checks passed.")
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
	var base := path if not path.is_empty() else "user://journal-unit-%d" % Time.get_ticks_usec()
	var study = Study.new()
	study.persistence_enabled = persistent
	study.save_path = base + "/study.json"
	study.clock_override_unix = 1800000000
	var game = Progression.new()
	game.persistence_enabled = persistent
	game.save_path = base + "/ship.json"
	var journal = Journal.new(study, game)
	journal.persistence_enabled = persistent
	journal.journal_path = base + "/journal.json"
	return {"study": study, "game": game, "journal": journal, "path": base}

func start(context: Dictionary) -> Dictionary:
	var question: Dictionary = context.study.question_bank[0].duplicate(true)
	context.game.ensure_encounter(question)
	context.game.begin_attempt()
	return question

func _test_deduplication() -> void:
	var c := setup()
	var question := start(c)
	var result: Dictionary = c.journal.resolve(question, true, false, -1)
	check(result.correct and result.first_attempt, "Independent first answer grades normally.")
	check(c.game.state.current.response.counter == "independent", "Correct answer earns strong tactical counter.")
	check(int(c.game.state.total_xp) == 100, "Independent answer grants 100 XP.")
	c.journal.resolve(question, true, false, -1)
	check(int(c.game.state.total_xp) == 100, "Duplicate answer does not mint XP.")
	check(int(c.study.history.questions[question.id].core_attempts) == 1, "Duplicate answer does not invent a study attempt.")
	check(int(c.study.get_summary().core_answered) == 1, "Duplicate answer does not change first-attempt count.")
	check(int(c.study.history.questions[question.id].last_confidence) == -1, "Unknown confidence remains unknown.")
	var hinted := setup()
	question = start(hinted)
	result = hinted.journal.resolve(question, true, true, 1, false, false, "independent")
	check(result.first_attempt and result.assisted, "Hinted first answer remains a first assisted response.")
	check(int(hinted.game.state.total_xp) == 40, "Hinted first resolution gets only assisted XP.")
	check(int(hinted.study.get_summary().core_correct) == 0, "Hint assistance does not count as independent recall.")

func _test_guided_and_solution() -> void:
	var c := setup()
	var question := start(c)
	c.journal.resolve(question, false, false, 2)
	check(int(c.game.state.hull) == 2 and int(c.game.state.total_xp) == 0, "Wrong answer costs one hull and no XP.")
	check(c.game.state.current.response.resolved, "Wrong first answer is final.")
	c.journal.resolve(question, false, false, 2)
	check(int(c.game.state.hull) == 2, "Duplicate wrong submission cannot charge hull twice.")
	var result: Dictionary = c.journal.resolve(question, true, true, -1, false, false, "assisted")
	check(result.has("error"), "Guided retry is rejected.")
	check(c.game.state.current.response.counter == "solution", "Miss receives only the manual armor override.")
	check(int(c.game.state.total_xp) == 0 and int(c.game.state.hull) == 2, "Attempted correction earns nothing and cannot repair hull.")
	c.journal.resolve_solution()
	check(int(c.study.get_summary().core_correct) == 0 and int(c.study.get_summary().core_answered) == 1, "Reading explanation preserves original accuracy.")
	check(int(c.study.history.questions[question.id].core_attempts) == 1, "Explanation never adds a response.")


func _test_fatal() -> void:
	var c := setup()
	var question := start(c)
	c.game.state.hull = 1
	var result: Dictionary = c.journal.resolve(question, false, false, -1)
	check(result.response.fatal and result.response.resolved, "Fatal wrong is durably resolved for a safe restart.")
	check(result.response.counter == "solution" and int(c.game.state.hull) == 0, "Fatal wrong cannot resume battle at positive invented health.")
	c.game.begin_attempt()
	check(int(c.game.state.hull) == 3 and not c.game.state.current.response.fatal, "Fresh attempt resets transient fatal state.")
	check(int(c.study.history.questions[question.id].core_attempts) == 1, "Combat retry never regrades a fatal wrong response.")

func _test_interrupted_commits() -> void:
	for boundary in ["journal", "study", "arcade"]:
		var c := setup(true)
		var question := start(c)
		c.study.save_progress()
		c.journal.test_interrupt_after = boundary
		var result: Dictionary = c.journal.resolve(question, true, false, -1)
		check(result.has("error"), "Injected interruption stops at " + boundary)
		var restored := setup(true, c.path)
		restored.study.clock_override_unix = 1800000000 + Study.DAY_SECONDS * 3
		restored.study.load_progress()
		restored.game.load_progress()
		check(restored.journal.recover(), "Pending transaction recovers after " + boundary)
		check(int(restored.game.state.total_xp) == 100, "Exactly one answer XP reward after " + boundary)
		check(int(restored.study.history.questions[question.id].core_attempts) == 1, "Exactly one actual study attempt after " + boundary)
		check(int(restored.study.history.questions[question.id].last_seen_at) == 1800000000, "Original submission timestamp survives " + boundary)
		check(int(restored.study.get_summary().core_correct) == 1, "Five-question summary survives " + boundary)
		check(restored.game.state.current.response.counter == "independent", "Tactical answer result survives " + boundary)
		check(restored.journal.recover(), "Repeated recovery is harmless after " + boundary)
		restored.journal.resolve(question, true, false, -1)
		check(int(restored.game.state.total_xp) == 100, "Repeated recovery/submission cannot duplicate reward after " + boundary)
	# A guided retry after reopening retains the first attempt's meaning.
	var c := setup(true)
	var question := start(c)
	c.journal.resolve(question, false, false, -1)
	var restored := setup(true, c.path)
	restored.study.load_progress()
	restored.game.load_progress()
	restored.journal.recover()
	restored.game.begin_attempt()
	restored.journal.resolve(question, true, true, -1, false, false, "assisted")
	check(int(restored.study.get_summary().core_correct) == 0 and int(restored.study.get_summary().core_answered) == 1, "Reloaded guided success cannot become independent recall.")
	check(int(restored.game.state.total_xp) == 0, "Reloaded miss cannot earn a corrective reward.")

func _test_bonus() -> void:
	var c := setup(true)
	var question := start(c)
	c.game.state.bonus = {"id": "fixture-bonus", "status": "pending", "target_level": 1, "question": question, "response": {}, "enhancement": false}
	c.game.start_bonus()
	c.journal.test_interrupt_after = "study"
	c.journal.resolve(question, true, false, -1, true)
	var restored := setup(true, c.path)
	restored.study.load_progress()
	restored.game.load_progress()
	check(restored.game.state.bonus.status == "skipped", "Unanswered started bonus is skipped on process restart.")
	check(restored.journal.recover(), "Durably submitted bonus recovers even after startup skip.")
	check(restored.game.state.bonus.status == "resolved" and restored.game.state.bonus.enhancement, "Recovered submitted bonus restores earned enhancement.")
	check(int(restored.game.state.total_xp) == 100, "Bonus reward is exactly 100 XP.")
	check(int(restored.study.get_summary().core_answered) == 0 and int(restored.study.get_summary().bonus_correct) == 1, "Bonus does not contaminate core accuracy.")
	restored.journal.resolve(question, true, false, -1, true)
	check(int(restored.game.state.total_xp) == 100, "Bonus cannot mint another reward.")

func _test_legacy_learning() -> void:
	var c := setup(true)
	var question := start(c)
	c.study.record_answer(question, true, false, -1)
	var before: Dictionary = c.study.history.duplicate(true)
	var file := FileAccess.open(c.study.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "history": before}))
	file.close()
	var restored := setup(true, c.path)
	restored.study.load_progress()
	check(restored.study.history == JSON.parse_string(JSON.stringify(before)), "Existing version-one learning history loads unchanged.")
	check(restored.study.response_receipts.is_empty(), "Legacy learners gain no fabricated response receipts.")
	check(int(restored.game.state.total_xp) == 0, "Old academic history grants no invented game achievements.")

func _test_write_failure() -> void:
	var c := setup(true)
	var question := start(c)
	var blocker: String = c.path + "/blocker"
	var file := FileAccess.open(blocker, FileAccess.WRITE)
	file.store_string("fixture")
	file.close()
	var original_journal: String = c.journal.journal_path
	c.journal.journal_path = blocker + "/journal.json"
	var result: Dictionary = c.journal.resolve(question, true, false, -1)
	check(result.has("error"), "Journal write failure prevents grade commit.")
	check(c.study.history.questions.is_empty(), "No academic response is invented after journal write failure.")
	check(int(c.game.state.total_xp) == 0, "No XP is awarded after journal write failure.")
	c.journal.journal_path = original_journal
	c.game.save_path = blocker + "/ship.json"
	result = c.journal.resolve(question, true, false, -1)
	check(result.has("error"), "Ship write failure leaves journal pending.")
	var restored := setup(true, c.path)
	restored.study.load_progress()
	restored.game.load_progress()
	check(restored.journal.recover(), "Pending ship commit completes after storage recovers.")
	check(int(restored.study.history.questions[question.id].core_attempts) == 1 and int(restored.game.state.total_xp) == 100, "Storage recovery preserves one actual response and one reward.")

func _test_study_backup() -> void:
	var c := setup(true)
	var question := start(c)
	c.journal.resolve(question, true, false, -1)
	c.study.save_progress()
	var file := FileAccess.open(c.study.save_path, FileAccess.WRITE)
	file.store_string("corrupted primary")
	file.close()
	var restored := setup(true, c.path)
	restored.study.load_progress()
	check(int(restored.study.history.questions[question.id].core_attempts) == 1, "Corrupt learning primary recovers valid history backup.")
	check(restored.study.response_receipts.size() == 1, "Learning response receipt survives backup recovery.")
	check(restored.study.save_progress(), "Recovered learning state can save again.")
	check(restored.study._valid_progress(JSON.parse_string(FileAccess.get_file_as_string(c.study.save_path + ".previous.json"))), "Valid history backup remains valid after corrupt-primary recovery.")

func _test_late_solution() -> void:
	var c := setup()
	var question := start(c)
	c.study.record_answer(question, true, false, -1)
	c.study.reset_run_stats()
	c.study.clock_override_unix = 1800000000 + Study.DAY_SECONDS
	c.journal.resolve(question, false, false, -1)
	var attempts := int(c.study.history.questions[question.id].core_attempts)
	c.game.state.current.response.resolved = false # Legacy unresolved miss fixture.
	c.game.state.current.response.counter = ""
	c.study.clock_override_unix = 1800000000 + Study.DAY_SECONDS * 3
	c.journal.resolve_solution()
	check(int(c.study.history.concepts[question.concept].last_remediation_at) == c.study.clock_override_unix, "Late solution viewing restarts the remediation clock.")
	check(int(c.study.history.questions[question.id].core_attempts) == attempts, "Late solution viewing adds no submitted answer.")
	c.study.reset_run_stats()
	var result: Dictionary = c.study.record_answer(question, true, false, -1)
	check(not result.mastery_advanced, "Same-day retrieval after viewing a late solution cannot advance delayed mastery.")
