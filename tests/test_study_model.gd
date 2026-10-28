extends SceneTree

const StudyModel = preload("res://scripts/study_model.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_test_question_bank_and_selection()
	_test_choice_deduplication()
	_test_accuracy_and_bonus_isolation()
	_test_spaced_mastery()
	_test_review_selection()
	_test_invalid_progress_schema()
	_test_optional_confidence()
	_test_remediation_spacing()
	if failures.is_empty():
		print("Study model: ", checks, " checks passed.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)


func _model():
	var model = StudyModel.new()
	model.persistence_enabled = false
	model.clock_override_unix = 1800000000
	model.rng.seed = 12345
	return model


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _test_question_bank_and_selection() -> void:
	var model = _model()
	_check(model.question_bank.size() >= 15, "At least 15 original samples exist.")
	var identifiers: Dictionary = {}
	for question in model.question_bank:
		_check(not identifiers.has(question["id"]), "Bank identifiers are unique: " + question["id"])
		identifiers[question["id"]] = true
		_check(question["sample"] == true, "Content is explicitly marked as sample data.")
		_check(question["choices"].size() == 4, "Each arithmetic question has four choices.")
		_check(int(question["answer_text"]) == int(question["numeric_answer"]), "Numeric recall and answer text agree.")
	# Independently calculated expected results: prevents an answer index from
	# silently pointing at an attractive but mathematically wrong distractor.
	var expected := {
		"commission_01": 200000 * 3 / 100, "commission_02": 350000 * 2 / 100,
		"commission_03": 480000 * 25 / 1000, "commission_04": 10000 / 2,
		"commission_05": 8000 * 60 / 100, "area_01": 40 * 60,
		"area_02": 25 * 80, "area_03": 12 * 15, "area_04": 3600 / 40,
		"area_05": 2 * 20 * 30, "down_01": 300000 * 10 / 100,
		"down_02": 250000 * 20 / 100, "down_03": 400000 * 5 / 100,
		"down_04": 64000 * 100 / 320000, "down_05": 200000 - 200000 * 15 / 100,
		"rent_01": 1500 * 12, "rent_02": 2000 * 12, "rent_03": 21600 / 12,
		"rent_04": 1200 * 10, "rent_05": 2 * 1000 * 12,
		"percent_01": 100000 * 10 / 100, "percent_02": (220000 - 200000) * 100 / 200000,
		"percent_03": 150000 * 4 / 100, "percent_04": 80000 - 80000 * 5 / 100,
		"percent_05": 50000 * 10 / 100,
	}
	for question in model.question_bank:
		_check(is_equal_approx(float(question["numeric_answer"]), float(expected[question["id"]])), "Verified arithmetic: " + question["id"])
		var correct_choice: String = question["choices"][int(question["answer"])]
		var number := correct_choice.replace("$", "").replace(",", "").replace(" sq ft", "").replace(" feet", "").replace("%", "")
		_check(float(number) == float(expected[question["id"]]), "Correct choice matches independently calculated result: " + question["id"])
	for run_index in range(20):
		model.start_run()
		_check(model.core_questions.size() == 5, "A run contains five core encounters.")
		_check(model.bonus_questions.size() == 2, "A run contains two bonus raids.")
		var run_concepts: Dictionary = {}
		for question in model.core_questions:
			run_concepts[question["concept"]] = true
			var original: Dictionary = {}
			for candidate in model.question_bank:
				if candidate["id"] == question["id"]:
					original = candidate
			_check(question["choices"][question["answer"]] == original["choices"][original["answer"]], "Shuffling preserves the correct answer.")
		_check(run_concepts.size() == 5, "Core encounters interleave all five arithmetic concepts.")
		for bonus_index in range(2):
			var familiar: Array = []
			for index in range(2 if bonus_index == 0 else 4):
				familiar.append(model.core_questions[index]["concept"])
			_check(model.bonus_questions[bonus_index]["concept"] in familiar, "Bonus only uses a concept encountered before its trigger.")
	_check(model.history["questions"].is_empty() and model.history["concepts"].is_empty(), "Starting runs does not fabricate learner records.")


func _test_choice_deduplication() -> void:
	var model = _model()
	var question := {"id": "duplicate_fixture", "choices": ["wrong", "right", "wrong", "other"], "answer": 1}
	for iteration in range(30):
		var shuffled: Dictionary = model._shuffle_choices(question)
		_check(shuffled["choices"].size() == 3, "Duplicate choices are removed.")
		_check(shuffled["choices"][shuffled["answer"]] == "right", "Deduplication keeps the answer index correct.")


func _test_accuracy_and_bonus_isolation() -> void:
	var model = _model()
	model.start_run()
	var first: Dictionary = model.core_questions[0]
	model.record_answer(first, false, false, 2)
	var retry: Dictionary = model.record_answer(first, true, false, 2)
	_check(not retry["first_attempt"] and retry["assisted"], "A retry is assisted even if the caller omits the hint flag.")
	model.record_answer(model.core_questions[1], true, true, 0)
	model.record_answer(model.core_questions[2], true, false, 1)
	var before: Dictionary = model.history["concepts"].duplicate(true)
	model.record_answer(model.bonus_questions[0], true, false, 2, true)
	model.record_answer(model.bonus_questions[1], false, false, 2, true, true)
	_check(model.history["concepts"] == before, "Bonus wins and timeout misses do not change concept mastery or due dates.")
	var summary: Dictionary = model.get_summary()
	_check(summary["core_answered"] == 3, "Retries and bonuses do not inflate core count.")
	_check(summary["core_correct"] == 1 and summary["core_assisted"] == 1, "Assisted correctness is separate from independent accuracy.")
	_check(is_equal_approx(summary["core_accuracy"], 1.0 / 3.0), "Core accuracy uses first independent attempts.")
	_check(summary["bonus_answered"] == 2 and summary["bonus_correct"] == 1 and summary["bonus_timed_out"] == 1, "Bonus counters are separate.")
	_check(not model.save_progress(), "Disabled persistence never writes a real learner save.")


func _test_spaced_mastery() -> void:
	var model = _model()
	var question: Dictionary = model.question_bank[0]
	var first: Dictionary = model.record_answer(question, true, false, 2)
	_check(first["mastery_stage"] == 0 and not first["mastery_advanced"], "One immediate answer cannot demonstrate spaced mastery.")
	for repetition in range(8):
		model.reset_run_stats()
		model.clock_override_unix += 60
		var same_day: Dictionary = model.record_answer(question, true, false, 2)
		_check(same_day["mastery_stage"] == 0 and not same_day["mastery_advanced"], "Same-session and same-day grinding cannot raise mastery.")
	model.reset_run_stats()
	model.clock_override_unix = 1800000000 + 86400 + 60
	var delayed: Dictionary = model.record_answer(model.question_bank[1], true, false, 2)
	_check(delayed["mastery_stage"] == 1 and delayed["mastery_advanced"], "Delayed independent recall transfers within the concept.")
	model.reset_run_stats()
	model.clock_override_unix += 86400
	var before_due: Dictionary = model.record_answer(question, true, false, 2)
	_check(before_due["mastery_stage"] == 1 and not before_due["mastery_advanced"], "Review intervals cannot be bypassed by next-day grinding.")
	model.reset_run_stats()
	model.clock_override_unix += 86400 * 2 + 60
	var assisted: Dictionary = model.record_answer(question, true, true, 0)
	_check(assisted["mastery_stage"] == 1 and not assisted["mastery_advanced"], "Assisted responses cannot promote spaced mastery.")
	_check(assisted["review_due"], "Assistance schedules review for the next session.")


func _test_review_selection() -> void:
	var model = _model()
	var missed: Dictionary = model.question_bank[3]
	model.record_answer(missed, false, false, 2)
	model.start_run()
	var selected := false
	for question in model.core_questions:
		if question["concept"] == missed["concept"]:
			selected = true
	_check(selected, "A missed concept receives priority using another question in the next run.")


func _test_invalid_progress_schema() -> void:
	var model = _model()
	_check(not model._valid_progress(null), "Null progress is rejected safely.")
	_check(not model._valid_progress({"version": 1, "history": []}), "Wrong history type is rejected.")
	_check(not model._valid_progress({"version": 1, "history": {"questions": {}, "concepts": {"commission": {"due_at": "garbage"}}}}), "Malformed scheduling values are rejected.")
	_check(model._valid_progress({"version": 1, "history": {"questions": {}, "concepts": {}}}), "An empty real progress schema loads.")


func _test_optional_confidence() -> void:
	var model = _model()
	var question: Dictionary = model.question_bank[0]
	var answer: Dictionary = model.record_answer(question, true, false, -1)
	_check(answer["confidence"] == -1, "Skipped confidence is returned as unknown.")
	_check(model.history["questions"][question["id"]]["last_confidence"] == -1, "Question history does not fabricate self-assessment.")
	_check(model.history["concepts"][question["concept"]]["last_confidence"] == -1, "Concept history preserves unknown confidence.")
	_check(model._valid_progress({"version": 1, "history": model.history}), "Unknown confidence remains valid after save and reload.")
	_check(not model._valid_progress({"version": 1, "history": {"questions": {}, "concepts": {"commission": {"last_confidence": -2}}}}), "Unsupported confidence values are rejected.")


func _test_remediation_spacing() -> void:
	var model = _model()
	var question: Dictionary = model.question_bank[0]
	model.record_answer(question, true, false, -1)
	model.clock_override_unix += 86400 * 3
	model.reset_run_stats()
	model.record_answer(question, false, false, -1)
	model.record_answer(question, true, true, -1)
	var remediation_time: int = model.clock_override_unix
	_check(model.history["concepts"][question["concept"]]["last_remediation_at"] == remediation_time, "A failed or assisted core answer records fresh teaching exposure.")
	model.reset_run_stats()
	model.clock_override_unix += 60
	var immediate: Dictionary = model.record_answer(question, true, false, -1)
	_check(immediate["mastery_stage"] == 0 and not immediate["mastery_advanced"], "Starting another run after remediation cannot promote freshly recalled answers to delayed mastery.")
	_check(immediate["review_due"], "Immediate recovery keeps the concept due for a genuinely delayed review.")
	model.reset_run_stats()
	model.clock_override_unix = remediation_time + 86400 + 60
	var delayed: Dictionary = model.record_answer(model.question_bank[1], true, false, -1)
	_check(delayed["mastery_stage"] == 1 and delayed["mastery_advanced"], "Independent recall on a later day after remediation can advance mastery.")
	_check(not delayed["review_due"], "A genuinely delayed success clears the remediation review flag.")
	_check(model._valid_progress({"version": 1, "history": model.history}), "Remediation timestamps persist within the validated save schema.")
