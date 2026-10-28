extends SceneTree
const MainScene = preload("res://main.tscn")
const Main = preload("res://scripts/main.gd")
var game
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func settle() -> void:
	for frame in range(5):
		await process_frame
		game.set_process(false)
		game.arena.set_process(false)

func fresh() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = MainScene.instantiate()
	game.test_mode = true
	root.add_child(game)
	await settle()
	game.model.load_course_bank()
	game.start_run()
	await settle()
	check(game._answer_confetti._pieces.is_empty(), "Launch alone does not celebrate")

func burst() -> void:
	var confetti = game._answer_confetti
	check(confetti._pieces.size() > 0 and confetti._pieces.size() <= confetti.MAX_PIECES, "Correct answer produces bounded visible paper")
	check(confetti.mouse_filter == Control.MOUSE_FILTER_IGNORE and confetti.focus_mode == Control.FOCUS_NONE, "Confetti cannot intercept pointer or keyboard input")
	check(confetti.get_global_rect().size == game.size, "Overlay covers the full responsive UI")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await fresh()
	game.arena._arrive_target()
	var wrong: int = (int(game.current_question.answer) + 1) % game.current_question.choices.size()
	game.submit_choice(wrong)
	check(game._answer_confetti._pieces.is_empty(), "A wrong answer does not celebrate")
	game._retry_core()
	game.submit_choice(int(game.current_question.answer))
	check(game._answer_confetti._pieces.is_empty(), "A submitted miss cannot be corrected or celebrated")
	check(game.model.get_summary().core_correct == 0, "Attempted correction cannot erase the first miss")
	game._answer_confetti._process(3.0)
	check(game._answer_confetti._pieces.is_empty() and not game._answer_confetti.is_processing(), "Paper cleans itself up and stops processing")
	game._render_response(game.progression.state.current.response.result)
	game.submit_choice(int(game.current_question.answer))
	check(game._answer_confetti._pieces.is_empty(), "Re-rendering feedback or duplicate input never celebrates again")
	await fresh()
	game.arena._arrive_target()
	game.submit_choice(int(game.current_question.answer))
	burst()
	game._toggle_pause()
	check(not game._answer_confetti.is_processing(), "Pause freezes the celebration")
	game._toggle_pause()
	check(game._answer_confetti.is_processing(), "Resume lets the celebration finish")
	await fresh()
	game.arena.freeze()
	game._show_shop()
	game._offer_boost("upgrade", "power")
	game._start_study_boost()
	for slot in range(3):
		game.submit_choice(int(game.current_question.answer))
		burst()
		game._answer_confetti._process(3.0)
		game._continue_boost()
	check(game._answer_confetti._pieces.is_empty(), "Claiming a reward does not count as another correct answer")
	await fresh()
	game.arena.freeze()
	game.progression.state.bonus = {"id":"confetti-bonus", "status":"pending", "target_level":3, "question":game.model.bonus_questions[0], "response":{}, "enhancement":false}
	game._show_bonus_intro()
	game.start_bonus()
	game.submit_choice(int(game.current_question.answer))
	burst()
	await fresh()
	game.arena.hull = 1
	game.progression.state.hull = 1
	game.arena._invulnerability = 0.0
	game.arena._take_hit("CONFETTI TEST")
	game._start_revive()
	game.submit_choice(int(game.current_question.answer))
	burst()
	check(game.progression.state.hull == 0 and game.phase == Main.Phase.FEEDBACK, "Confetti never resumes a fight or claims a revive itself")
	root.size = Vector2i(390, 844)
	await fresh()
	game._effects.button_pressed = true
	game.arena._arrive_target()
	game.submit_choice(int(game.current_question.answer))
	burst()
	var before: Array = game._answer_confetti._pieces.duplicate(true)
	game._answer_confetti._process(0.2)
	check(game._answer_confetti._pieces == before, "Reduced motion displays stationary paper without travel or rotation")
	game._answer_confetti._process(1.0)
	check(game._answer_confetti._pieces.is_empty(), "Gentle celebration ends quickly")
	for index in range(20): game._celebrate_answer()
	check(game._answer_confetti._pieces.size() <= game._answer_confetti.MAX_PIECES, "Back-to-back celebrations cannot accumulate particles")
	game.queue_free()
	await process_frame
	print("Answer confetti: ", checks, " checks; ", failures.size(), " failures")
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
