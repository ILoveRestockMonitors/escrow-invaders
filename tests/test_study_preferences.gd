extends SceneTree
## Integration coverage for honest analytics, final answers and adaptive selection.
const Study = preload("res://scripts/study_model.gd")
const Progression = preload("res://scripts/progression_model.gd")
const Journal = preload("res://scripts/response_journal.gd")
const Main = preload("res://scripts/main.gd")
const Scene = preload("res://main.tscn")
var checks := 0
var failures: Array[String] = []
var game

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _initialize() -> void: call_deferred("run_tests")
func settle() -> void:
	for frame in range(5):
		await process_frame
		if is_instance_valid(game):
			game.set_process(false)
			game.arena.set_process(false)
func run_tests() -> void:
	test_filters_and_selection()
	test_analytics_and_recovery()
	await test_final_answers_ui()
	await test_study_layout()
	print("Study preferences: ", checks, " checks; ", failures.size(), " failures")
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)

func test_filters_and_selection() -> void:
	var study = Study.new()
	study.persistence_enabled = false
	check(study.load_course_bank(), "Course bank loaded")
	check(study.available_categories().size() == 7, "Seven real course categories")
	check(study.set_preferences(["Financing"], true), "Can choose one category")
	study.start_run()
	check(study.core_questions.size() == 5, "Filtered block still has five questions")
	for question in study.core_questions: check(question.category == "Financing", "Every core respects selection")
	for question in study.bonus_questions:
		if not question.is_empty(): check(question.category == "Financing", "Bonus respects selection")
	check(not study.set_preferences(["nonexistent"], true), "Reject unknown categories without losing preference")
	check(study.preferences.categories == ["Financing"], "Invalid change preserved selection")
	var question: Dictionary = study.select_next_question()
	study.clock_override_unix = 1800000000
	study.record_answer(question, false, false, 2)
	study.session_seen.append(question.id)
	var weak: String = question.concept
	for index in range(10):
		var next: Dictionary = study.select_next_question()
		check(next.id != question.id and next.category == "Financing", "Adaptive gives a different question within chosen category")
		check(next.concept == weak, "Adaptive prioritizes weak concept transfer")
	check(study.set_preferences([], false), "Mixed mode and all categories supported")
	check(study.eligible_questions().size() == 1048, "All bank questions available again")
	# Preferences and no-immediate-repeat memory survive a real disk roundtrip.
	study.persistence_enabled = true
	study.save_path = "user://study-preferences-test.json"
	check(study.save_progress(), "Preferences save")
	var reload = Study.new()
	reload.load_course_bank()
	reload.save_path = study.save_path
	reload.load_progress()
	check(reload.preferences == study.preferences and reload.session_seen == study.session_seen, "Preferences and seen IDs restored")
	for suffix in ["", ".previous.json"]:
		if FileAccess.file_exists(study.save_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(study.save_path + suffix))

func test_analytics_and_recovery() -> void:
	var study = Study.new()
	study.persistence_enabled = false
	study.load_course_bank()
	study.clock_override_unix = 1800000000
	var progression = Progression.new()
	progression.persistence_enabled = false
	var journal = Journal.new(study, progression)
	journal.persistence_enabled = false
	var question: Dictionary = study.select_next_question()
	progression.ensure_encounter(question)
	progression.begin_attempt()
	journal.answer_metadata = {"selected_index": (int(question.answer) + 1) % 4, "elapsed_seconds": 4.5}
	journal.test_interrupt_after = "study"
	check(journal.resolve(question, false, false, 2).has("error"), "Interrupted commit is recoverable")
	journal.test_interrupt_after = ""
	check(journal.recover(), "Interrupted answer commits without new answer")
	var response: Dictionary = progression.state.current.response
	check(response.resolved and not response.first_correct and response.attempts == 1, "A wrong battle answer is final")
	check(progression.state.hull == 2, "Miss costs one hull")
	check(journal.resolve(question, true, true, 2, false, false, "assisted").has("error"), "Guided retry rejected at journal boundary")
	journal.resolve(question, true, false, 2)
	var dashboard: Dictionary = study.get_learning_dashboard()
	check(dashboard.totals.answered == 1 and dashboard.totals.wrong == 1 and dashboard.totals.correct == 0, "Double submission cannot alter a miss or inflate totals")
	check(dashboard.recent[0].selected_index == journal.answer_metadata.selected_index and dashboard.totals.seconds == 4.5, "Selected answer and duration retained")
	check(dashboard.categories[question.category].wrong == 1 and dashboard.topics[question.concept].wrong == 1, "Category and topic analytics are exact")
	# Revive has one chance: failing never exposes another submission.
	progression.mark_defeated()
	var revive_question: Dictionary = study.select_next_question([question.id])
	progression.start_revive(revive_question)
	journal.resolve_revive(revive_question, false, false, 1)
	check(not progression.retry_revive() and not progression.claim_revive(), "Missed revive cannot retry or claim")
	check(journal.resolve_revive(revive_question, true, false, 2).correct == false, "Duplicate revive answer keeps original wrong receipt")
	dashboard = study.get_learning_dashboard()
	check(dashboard.totals.answered == 2 and dashboard.totals.wrong == 2, "Revive included once in totals")
	check(dashboard.contexts.revive.wrong == 1, "Revive context is separate")
	# A boost advances after each single answer, preserving the earned completion economy.
	progression.state.last_clear_reward = {"coins": 10, "gems": 1, "xp": 20, "level": 1}
	progression.create_boost_offer("double_clear")
	var questions: Array = []
	var excluded: Array = [question.id, revive_question.id]
	for index in range(3):
		var next: Dictionary = study.select_next_question(excluded)
		questions.append(next)
		excluded.append(next.id)
	check(progression.start_boost(questions), "Three fresh boost questions")
	for index in range(3):
		var result: Dictionary = journal.resolve_boost(questions[index], index == 1, index == 1, -1)
		check(not result.has("error") and progression.state.boost.index == index + 1, "One boost answer advances immediately even when wrong")
	dashboard = study.get_learning_dashboard()
	check(dashboard.totals.answered == 5 and dashboard.totals.correct == 1 and dashboard.totals.wrong == 4, "All contexts have honest right/wrong totals")
	check(dashboard.totals.assisted == 1 and dashboard.totals.independent == 0, "Hinted correct remains right but assisted")
	check(study.session_seen.size() == 5, "Supplemental study cannot clear no-repeat memory")
	check(Progression.valid({"version": Progression.VERSION, "state": progression.state}), "Single-answer states remain save-valid")
	# Legacy guided receipts remain preserved but never count as new questions.
	study.response_receipts.legacy_retry = {"first_attempt": false, "correct": true}
	study.response_receipts.legacy_first = {"first_attempt": true, "correct": true, "recorded_at": 1700000000}
	study.response_receipts.other_bank = {"first_attempt": true, "correct": true, "bank_id": "other"}
	dashboard = study.get_learning_dashboard()
	check(dashboard.totals.answered == 6 and dashboard.totals.correct == 2, "Legacy first result preserved; retries and other bank excluded")
	check(dashboard.categories["Earlier answers (topic unavailable)"].correct == 1, "Legacy unknown topic never invented")

func fresh() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = Scene.instantiate()
	game.test_mode = true
	root.add_child(game)
	await settle()
	game.model.load_course_bank()
func visible_labels() -> String:
	var value := ""
	for node in game._side.find_children("*", "Label", true, false): value += node.text + "\n"
	return value
func no_retry_controls() -> bool:
	for node in game._side.find_children("*", "Button", true, false):
		if node.text.contains("TRY WITH") or node.text.contains("SOLUTION"): return false
	return true
func test_final_answers_ui() -> void:
	await fresh()
	game.start_run()
	await settle()
	game.arena._arrive_target()
	await settle()
	game.submit_choice((int(game.current_question.answer) + 1) % 4)
	await settle()
	check(game.phase == Main.Phase.FEEDBACK and no_retry_controls(), "Battle miss shows explanation and no retry controls")
	check(visible_labels().contains("One answer recorded"), "Battle feedback explains final result")
	game._retry_core()
	check(game.phase == Main.Phase.FEEDBACK, "Old retry entry point cannot reopen")
	game._resume_battle()
	await settle()
	game._show_defeat()
	game._start_revive()
	await settle()
	game.submit_choice((int(game.current_question.answer) + 1) % 4)
	await settle()
	check(game.phase == Main.Phase.FEEDBACK and no_retry_controls(), "Revive miss shows no retry")
	game._retry_revive()
	check(game.phase == Main.Phase.FEEDBACK, "Old revive entry point cannot reopen")
	game._show_ready()
	game._show_study()
	await settle()
	check(visible_labels().contains("0 RIGHT / 2 WRONG"), "Study shows all actual wrong answers")
	game.queue_free()
	await process_frame
func test_study_layout() -> void:
	for viewport in [Vector2i(1440, 900), Vector2i(390, 844), Vector2i(844, 390), Vector2i(360, 640)]:
		root.size = viewport
		await fresh()
		game._show_study()
		await settle()
		check(game.phase == Main.Phase.STUDY and game._menu_nav.visible, "Study reachable with persistent menu")
		check(game._side_panel.size.x <= viewport.x and game._side_scroll.size.x <= viewport.x, "Study fits desktop and phone widths")
		for button in game._menu_buttons:
			var font: Font = button.get_theme_font("font")
			var width := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
			check(width <= button.size.x - 16, "Four navigation labels fit without splitting words")
		check(game._side_scroll.get_v_scroll_bar().max_value > 0, "Long dashboard remains scrollable")
		game._change_category(false, "Financing")
		await settle()
		check("Financing" not in game.model.preferences.categories and game.model.preferences.categories.size() == 6, "Topic toggle takes effect")
		game._change_adaptive(false)
		await settle()
		check(not game.model.preferences.adaptive, "Mixed mode selectable")
		game._navigate_menu(0)
		await settle()
		check(game.phase == Main.Phase.READY, "Home navigation leaves study safely")
	game.queue_free()
	await process_frame
