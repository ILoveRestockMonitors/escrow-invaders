extends SceneTree

const Bank = preload("res://scripts/course_bank.gd")
const Model = preload("res://scripts/study_model.gd")
const MainScene = preload("res://main.tscn")
const MainScript = preload("res://scripts/main.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _fixture() -> Dictionary:
	var questions: Array = []
	for index in range(6):
		questions.append({"id": str(index), "concept": "fixture", "prompt": "Synthetic import test %d?" % index, "choices": ["First", "Second"], "answer": 1, "answer_verified": true, "source_url": "https://example.invalid/test", "explanation": "", "bonus_eligible": true})
	return {"schema_version": 1, "bank_id": "test-only", "title": "Synthetic import fixture", "source_url": "https://example.invalid/test", "questions": questions}


func _run() -> void:
	var fixture := _fixture()
	var loaded: Dictionary = Bank.validate(fixture)
	_check(not loaded.has("error") and loaded["questions"].size() == 6, "Valid question bank loads all questions.")
	var question: Dictionary = loaded["questions"][0]
	_check(question["id"] == "test-only:0" and question["concept"] == "test-only:fixture", "Course IDs cannot collide with sample learning history.")
	_check(question["explanation"].contains("No explanation was supplied"), "Missing official explanations are explicitly identified.")
	_check(not question["sample"] and not question["shuffle_choices"], "Imported course questions preserve official choice order.")
	var model = Model.new()
	model.persistence_enabled = false
	_check(model._shuffle_choices(question)["choices"] == ["First", "Second"], "Letter-dependent answers retain their order during run selection.")
	for field_value in [["answer", 2], ["answer", -1], ["answer", 0.5], ["answer", "B"], ["answer_verified", false], ["answer_verified", "true"], ["choices", ["Same", "Same"]], ["choices", ["Only"]], ["source_url", ""], ["prompt", ""]]:
		var invalid := _fixture()
		invalid["questions"][0][field_value[0]] = field_value[1]
		_check(Bank.validate(invalid).has("error"), "Invalid bank rejected: " + str(field_value))
	var duplicate := _fixture()
	duplicate["questions"][1]["id"] = "0"
	_check(Bank.validate(duplicate).has("error"), "Duplicate question IDs are rejected.")
	duplicate = _fixture()
	duplicate["questions"][1]["prompt"] = duplicate["questions"][0]["prompt"]
	_check(Bank.validate(duplicate).has("error"), "Duplicate question wording is rejected.")
	var tiny := _fixture()
	tiny["questions"].resize(4)
	_check(Bank.validate(tiny).has("error"), "An incomplete bank cannot break a five-question run.")
	var path := "user://course-import-test.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(fixture))
	file.close()
	_check(model.load_course_bank(path), "The JSON file loader activates the validated course bank.")
	_check(not model.sample_data and model.bank_id == "test-only", "Course metadata replaces sample labeling.")
	model.start_run()
	_check(model.core_questions.size() == 5 and model.bonus_questions.size() == 2, "Course runs have five questions and two explicit bonus slots.")
	var core_ids: Array = model.core_questions.map(func(q): return q["id"])
	for bonus in model.bonus_questions:
		_check(bonus.is_empty() or bonus["id"] not in core_ids, "A bonus cannot repeat an exact core item from the same run.")
	var previous_bank: Array = model.question_bank.duplicate(true)
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("invalid JSON")
	file.close()
	_check(not model.load_course_bank(path) and model.question_bank == previous_bank, "An invalid replacement leaves the active bank unchanged.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var game = MainScene.instantiate()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.arena.set_process(false)
	game.start_run()
	for frame in range(5):
		await process_frame
		game.arena.set_process(false)
	game.core_index = 4
	game.progression.state.current.question = question.duplicate(true)
	game.current_question = question
	game._render_question(false)
	_check(not is_instance_valid(game._numeric) and game._answer_buttons.size() == 2, "A non-math boss uses its original multiple-choice answers.")
	game.submit_choice(3)
	_check(game.phase == MainScript.Phase.CORE and game.shields == 3, "A key for a nonexistent choice cannot cost a shield.")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_A
	game._unhandled_key_input(key)
	_check(game.phase == MainScript.Phase.FEEDBACK and game.last_correct, "Keyboard choices work for a non-math boss.")
	game.progression.state.level = 3
	game.progression.state.current = {}
	game.progression.state.pending_upgrades = 0
	game.progression.state.checkpoint_pending = false
	game.progression.state.block = {"core": game.model.core_questions.duplicate(true), "bonus": [{}, {}], "index": 2}
	game.progression.state.bonus = {"id": "no-short-bonus", "status": "pending", "target_level": 3, "question": {}, "response": {}}
	game._show_bonus_intro()
	game.start_bonus()
	_check(game.phase == MainScript.Phase.COMBAT and game.progression.state.bonus.status == "skipped", "An unavailable short bonus is skipped without opening an empty timer.")
	game._skip_bonus()
	_check(game.core_index == 2 and game.phase == MainScript.Phase.COMBAT and int(game.progression.state.level) == 3, "Missing short bonuses safely continue at the next uncleared encounter.")
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("Course bank: ", checks, " checks passed.")
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
