extends SceneTree
## Integration checks against the actual imported course file; no learner saves.

const Model = preload("res://scripts/study_model.gd")
const MainScene = preload("res://main.tscn")
var checks := 0
var failures: Array[String] = []
var populated_bonus_slots := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _run() -> void:
	var model = Model.new()
	model.persistence_enabled = false
	_check(model.load_course_bank(), "Actual installed course bank loads.")
	if model.sample_data:
		printerr("No actual course bank installed.")
		quit(1)
		return
	var originals: Dictionary = {}
	var longest: Dictionary = {}
	var longest_size := 0
	for question in model.question_bank:
		originals[question["id"]] = question
		var text_size: int = String(question["prompt"]).length()
		for choice in question["choices"]:
			text_size += String(choice).length()
		if text_size > longest_size:
			longest_size = text_size
			longest = question
	for mission in range(50):
		model.rng.seed = 7100 + mission
		model.start_run()
		_check(model.core_questions.size() == 5, "Five actual questions selected.")
		var ids: Array = []
		for question in model.core_questions:
			_check(question["id"] not in ids, "Core questions do not repeat within a mission.")
			ids.append(question["id"])
			_check(question["choices"] == originals[question["id"]]["choices"], "Official answer order is retained.")
		_check(model.bonus_questions.size() == 2, "Both bonus checkpoints exist.")
		for slot in range(2):
			var bonus: Dictionary = model.bonus_questions[slot]
			if bonus.is_empty():
				continue
			populated_bonus_slots += 1
			var familiar: Array = []
			for index in range(2 if slot == 0 else 4):
				familiar.append(model.core_questions[index]["concept"])
			_check(bonus["concept"] in familiar, "Bonus builds on a concept already encountered.")
			_check(bonus["id"] not in ids and bonus["bonus_eligible"], "Bonus is a separate selected short question.")
			ids.append(bonus["id"])
			_check(bonus["choices"] == originals[bonus["id"]]["choices"], "Bonus preserves official choice order.")
	root.size = Vector2i(1280, 720)
	var game = MainScene.instantiate()
	game.test_mode = true
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.arena.set_process(false)
	_check(game.model.load_course_bank(), "Actual main scene accepts the installed bank.")
	game.start_run()
	for frame in range(5):
		await process_frame
		game.arena.set_process(false)
	game.progression.state.current.question = longest.duplicate(true)
	game.current_question = longest
	game._render_question(false)
	for frame in range(4):
		await process_frame
	_check(game._answer_buttons.size() == longest["choices"].size(), "Longest source question renders all choices.")
	for button in game._answer_buttons:
		_check(button.size.x <= game._side_panel.size.x, "Long answer choices stay within the sidebar.")
	game._side_scroll.scroll_vertical = 100
	await process_frame
	_check(game._side_scroll.scroll_vertical > 0, "Long question can scroll to lower answers.")
	game._render_question(false)
	for frame in range(4):
		await process_frame
	_check(game._side_scroll.scroll_vertical == 0, "A new question starts at the top after a long question.")
	game.submit_choice(int(longest["answer"]))
	_check(game.last_correct and game.model.get_summary()["core_correct"] == 1, "Actual official key is accepted and scored in the main scene.")
	_check(not game.model.persistence_enabled and not game.progression.persistence_enabled and not game.journal.persistence_enabled, "Integration answers cannot modify either learner save or its response journal.")
	game.queue_free()
	await process_frame
	print("Installed course: ", checks, " checks; ", populated_bonus_slots, "/100 populated bonus slots across 50 seeded missions.")
	for failure in failures:
		printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
