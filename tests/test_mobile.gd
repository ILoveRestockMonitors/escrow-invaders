extends SceneTree
## Layout checks on real Godot controls with the longest installed course item.
const MainScene = preload("res://main.tscn")
const MainScript = preload("res://scripts/main.gd")
var failures: Array[String] = []
var checks := 0
var game
var dimensions := Vector2i.ZERO

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures.append(description + " at " + str(dimensions))

func settle() -> void:
	for frame in range(5):
		await process_frame
		if is_instance_valid(game):
			game.set_process(false)
			game.arena.set_process(false)

func contained(control: Control) -> bool:
	var r := control.get_global_rect()
	return r.position.x >= -1 and r.end.x <= root.size.x + 1 and r.position.y >= -1 and r.end.y <= root.size.y + 1

func verify_panel(label: String) -> void:
	await settle()
	check(contained(game._header), label + ": header contained")
	check(not game._mobile or game._header.size.y <= 50, label + ": phone header remains compact")
	check(contained(game._status_row), label + ": rank and hull HUD contained")
	if game._wallet_label.visible:
		check(contained(game._wallet_label), label + ": currency wallet remains contained")
	check(contained(game._side_panel) and game._side_panel.visible, label + ": reading panel fits")
	var buttons: Array = game._side.find_children("*", "Button", true, false)
	for button in buttons:
		if not button.is_visible_in_tree(): continue
		check(button.size.y >= 44, label + ": touch target is at least 44 high")
		check(button.size.x <= game._side_scroll.size.x + 1, label + ": button width fits scroll panel")
	if not buttons.is_empty():
		var last: Control = buttons.back()
		game._side_scroll.ensure_control_visible(last)
		await settle()
		var reachable: Rect2 = last.get_global_rect().intersection(game._side_scroll.get_global_rect())
		check(reachable.size.y >= minf(44.0, last.size.y), label + ": final action is reachable by scrolling")

func _run() -> void:
	for size in [Vector2i(375,667), Vector2i(390,844), Vector2i(430,932), Vector2i(844,390), Vector2i(1280,720)]:
		dimensions = size
		root.size = size
		game = MainScene.instantiate()
		game.test_mode = true
		root.add_child(game)
		await settle()
		check(game.model.load_course_bank(), "Real bank loads without persistence")
		game._show_ready()
		await verify_panel("Ready")
		game._show_hangar()
		await verify_panel("Hangar")
		game.start_run()
		await settle()
		check(contained(game._arena_panel) and game._arena_panel.visible, "Combat arena fits")
		check(game._side_panel.visible == not game._mobile, "Phone combat uses dedicated full-width arena")
		game._toggle_pause()
		await settle()
		check(contained(game._pause_button) and game._pause_button.text == "Resume", "Pause/resume remains reachable")
		game._toggle_pause()
		game.arena.set_process(false)
		var longest: Dictionary = {}
		var length := 0
		for question in game.model.question_bank:
			var n: int = String(question.prompt).length() + str(question.choices).length()
			if n > length:
				longest = question
				length = n
		game.progression.state.current.question = longest.duplicate(true)
		game.arena.question_requested.emit()
		await verify_panel("Longest core question")
		check(game._answer_buttons.size() == longest.choices.size(), "Every official answer is rendered")
		for button in game._answer_buttons:
			check(button.size.y >= 48 and button.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "Long official answers wrap with touch height")
		game._side_scroll.ensure_control_visible(game._answer_buttons.back())
		await settle()
		check(contained(game._answer_buttons.back()), "Final official answer can be fully reached")
		game._render_question(false)
		await settle()
		check(game._side_scroll.scroll_vertical == 0, "New question starts at top")
		var wrong: int = (int(longest.answer) + 1) % longest.choices.size()
		game.submit_choice(wrong)
		await verify_panel("Remediation")
		game._retry_core()
		await verify_panel("Guided retry")
		game.submit_choice(int(longest.answer))
		await verify_panel("Official feedback")
		check(not game.last_correct and game.progression.state.current.response.counter == "solution", "Long course miss remains final with its official explanation")
		game._resume_battle()
		await settle()
		game.arena.freeze()
		game.arena.combat_finished.emit({"victory": true, "hull": 2})
		await verify_panel("Encounter clear")
		game.progression.state.pending_upgrades = 1
		game._show_upgrades()
		await verify_panel("Rank choice")
		var before: int = int(game.progression.state.upgrades.power)
		game.choose_upgrade("power")
		await settle()
		game.choose_upgrade("power")
		check(int(game.progression.state.upgrades.power) == before + 1, "Double tap cannot duplicate a single rank choice")
		game.progression.state.block.index = 2
		var bonus: Dictionary = game.model.bonus_questions[0]
		game.progression.state.bonus = {"id": "mobile-bonus", "status": "pending", "target_level": 3, "question": bonus, "response": {}, "enhancement": false}
		game.arena.freeze()
		game._show_bonus_intro()
		await verify_panel("Bonus invitation")
		game.start_bonus()
		await verify_panel("Timed bonus")
		game.submit_choice(int(game.current_question.answer))
		await verify_panel("Bonus feedback")
		game._show_shop()
		await verify_panel("Currency shop")
		game._offer_boost("double_clear")
		await verify_panel("Double loot offer")
		var boost_questions: Array[Dictionary] = [longest]
		for question in game.model.question_bank:
			if question.id != longest.id:
				boost_questions.append(question)
			if boost_questions.size() == 3: break
		check(game.progression.start_boost(boost_questions), "A valid three-question offer can include the longest official prompt")
		game._start_study_boost()
		await verify_panel("Longest boost question")
		check(game.phase == MainScript.Phase.BOOST and game.current_question.id == longest.id, "Boost uses its saved long official question")
		game.submit_choice(int(game.current_question.answer))
		await verify_panel("Boost official feedback")
		game._continue_boost()
		game.submit_choice((int(game.current_question.answer) + 1) % game.current_question.choices.size())
		await verify_panel("Boost remediation")
		game._retry_boost()
		game.submit_choice(int(game.current_question.answer))
		game._continue_boost()
		game.submit_choice(int(game.current_question.answer))
		game._continue_boost()
		await verify_panel("Double loot completion")
		game._show_shop()
		game._offer_boost("upgrade", "power")
		await verify_panel("Quoted study-funded upgrade")
		game._start_study_boost()
		for review in range(3):
			game.submit_choice(int(game.current_question.answer))
			game._continue_boost()
		await verify_panel("Study upgrade installed")
		game._show_summary()
		await verify_panel("Checkpoint recap")
		game._show_defeat()
		await verify_panel("Defeat and retry")
		game.journal.warning = "Test-only simulated save problem"
		game._show_save_problem()
		await verify_panel("Save recovery")
		check(not game.model.persistence_enabled and not game.progression.persistence_enabled and not game.journal.persistence_enabled, "UI tests never write learner progress")
		game.queue_free()
		await process_frame
		game = null
	print("Mobile endless UI: ", checks, " checks; ", failures.size(), " failures")
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
