extends SceneTree
## Real GUI key events: no live learner history, synthetic grading, or browser hooks.
const MainScene = preload("res://main.tscn")
const Main = preload("res://scripts/main.gd")
const ANSWERS = [KEY_W, KEY_A, KEY_S, KEY_D]
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

func event(code: int, down: bool = true, echo: bool = false, ctrl: bool = false, shift: bool = false) -> void:
	var input := InputEventKey.new()
	input.keycode = code
	input.physical_keycode = code
	input.pressed = down
	input.echo = echo
	input.ctrl_pressed = ctrl
	input.shift_pressed = shift
	Input.parse_input_event(input)
	await process_frame
	game.arena.set_process(false)

func tap(code: int, ctrl: bool = false, shift: bool = false) -> void:
	await event(code, true, false, ctrl, shift)
	await event(code, false, false, ctrl, shift)
	await settle()

func question() -> void:
	game.arena._arrive_target()
	await settle()
	check(game.phase == Main.Phase.CORE, "Target arrival opens the actual course question")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	for index in range(4):
		await fresh()
		await question()
		check(game._answer_buttons.size() == 4, "Four-choice fixture")
		check(game._answer_buttons[index].text.begins_with("[%s]" % "WASD"[index]), "Every answer displays its matching WASD key")
		var expected: bool = index == int(game.current_question.answer)
		await tap(ANSWERS[index])
		check(game.phase == Main.Phase.FEEDBACK and game.last_correct == expected and game.answer_attempts == 1, "WASD maps directly to the original answer index")
		check(game.model.get_summary().core_answered == 1, "A keyboard answer records exactly one real first attempt")
	await test_arrows_feedback_and_guards()
	await test_held_movement()
	await test_boost_and_revive()
	await test_long_question()
	game.queue_free()
	await process_frame
	print("Question keyboard: ", checks, " checks; ", failures.size(), " failures")
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)

func test_arrows_feedback_and_guards() -> void:
	await fresh()
	await question()
	check(root.gui_get_focus_owner() == game._answer_buttons[0], "The first answer starts with clear keyboard focus")
	for key in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_KP_1, KEY_B, KEY_C]: await tap(key)
	check(game.phase == Main.Phase.CORE and game.answer_attempts == 0, "Old number/A-D shortcuts cannot grade answers")
	await tap(KEY_A, true)
	check(game.answer_attempts == 0, "Modified shortcuts do not submit answers")
	game._open_help()
	await tap(KEY_W)
	await tap(KEY_H)
	check(game.phase == Main.Phase.CORE and not game.assisted and game._help_layer.visible, "Help blocks WASD and hints underneath")
	game._close_help()
	game._toggle_pause()
	await tap(KEY_D)
	await tap(KEY_ENTER)
	check(game.phase == Main.Phase.CORE and game.answer_attempts == 0, "Pause blocks answering and Enter")
	game._toggle_pause()
	await tap(KEY_H)
	check(game.assisted and not game._hint_label.text.is_empty(), "H reveals the real hint and marks assistance honestly")
	game._answer_buttons[0].grab_focus()
	var answer: int = game.current_question.answer
	for step in range(answer): await tap(KEY_DOWN)
	check(root.gui_get_focus_owner() == game._answer_buttons[answer], "Arrow navigation selects the expected answer")
	await event(KEY_ENTER)
	check(game.phase == Main.Phase.FEEDBACK and game.last_correct, "Enter confirms the focused answer")
	for repeat in range(3): await event(KEY_ENTER, true, true)
	check(game.phase == Main.Phase.FEEDBACK and game.answer_attempts == 1, "Holding Enter cannot dismiss explanation or grade twice")
	await event(KEY_ENTER, false)
	await tap(KEY_ENTER)
	check(game.phase == Main.Phase.COMBAT and not game.arena._pulse_uses, "A fresh Enter continues the fight without firing pulse")
	await fresh()
	await question()
	game._help_button.grab_focus()
	await tap(ANSWERS[int(game.current_question.answer)])
	check(not is_instance_valid(root.gui_get_focus_owner()), "New feedback releases stale Help focus")
	await tap(KEY_ENTER)
	check(game.phase == Main.Phase.COMBAT and not game._help_layer.visible, "Enter continues feedback even if Help was focused before answering")
	await fresh()
	await question()
	await tap(ANSWERS[(int(game.current_question.answer) + 1) % 4])
	await tap(KEY_ENTER)
	check(game.phase == Main.Phase.COMBAT and game.answer_attempts == 1, "Enter resumes battle after a final wrong answer")
	await tap(ANSWERS[int(game.current_question.answer)])
	check(not game.last_correct and game.model.get_summary().core_correct == 0, "Combat input cannot correct the original miss")

func test_held_movement() -> void:
	await fresh()
	await event(KEY_W)
	await question()
	await event(KEY_W, true, true)
	check(game.phase == Main.Phase.CORE and game.answer_attempts == 0, "Holding a movement key across target arrival cannot answer")
	await event(KEY_W, false)
	await tap(KEY_W)
	check(game.phase == Main.Phase.FEEDBACK and game.answer_attempts == 1, "Released movement key can be deliberately pressed to answer")

func test_boost_and_revive() -> void:
	await fresh()
	game.arena.freeze()
	game._show_shop()
	game._offer_boost("upgrade", "power")
	await tap(KEY_ENTER)
	check(game.phase == Main.Phase.BOOST, "Enter starts the offered study set")
	for index in range(3):
		await tap(ANSWERS[int(game.current_question.answer)])
		check(game.phase == Main.Phase.FEEDBACK and game.last_correct, "WASD answers study reward question %d" % (index + 1))
		await tap(KEY_ENTER)
		check(game.phase == (Main.Phase.BOOST if index < 2 else Main.Phase.BOOST_INTRO), "Enter advances exactly one review")
	check(game.progression.state.shop_ranks.power == 1, "Keyboard-only set installs the real upgrade exactly once")
	await fresh()
	game.arena.hull = 1
	game.progression.state.hull = 1
	game.arena._invulnerability = 0
	game.arena._take_hit("KEYBOARD TEST")
	game._start_revive()
	await settle()
	await tap(ANSWERS[int(game.current_question.answer)])
	check(game.phase == Main.Phase.FEEDBACK and game.progression.state.hull == 0, "Revive keyboard correctness still waits at its explanation")
	await tap(KEY_ENTER)
	check(game.phase == Main.Phase.COMBAT and game.progression.state.hull == 3, "Enter claims and resumes the earned revive")
	await fresh()
	game.arena.freeze()
	game.progression.state.bonus = {"id":"keyboard-bonus", "status":"pending", "target_level":3, "question":game.model.bonus_questions[0], "response":{}, "enhancement":false}
	game._show_bonus_intro()
	await tap(KEY_ENTER)
	check(game.phase == Main.Phase.BONUS, "Enter explicitly starts the bonus timer")
	await tap(KEY_H)
	check(not game.assisted, "Timed questions do not acquire an unavailable hint")
	await tap(ANSWERS[int(game.current_question.answer)])
	check(game.phase == Main.Phase.FEEDBACK and game.last_correct, "WASD also answers timed bonuses")

func test_long_question() -> void:
	root.size = Vector2i(390, 844)
	await fresh()
	var longest: Dictionary = {}
	for candidate in game.model.question_bank:
		if str(candidate).length() > str(longest).length(): longest = candidate
	game.progression.state.current.question = longest.duplicate(true)
	await question()
	check(game._side_scroll.scroll_vertical == 0, "Initial focus leaves the full long prompt at the top")
	await tap(KEY_UP)
	check(root.gui_get_focus_owner() == game._answer_buttons.back(), "Up wraps to the final answer")
	var visible: Rect2 = game._answer_buttons.back().get_global_rect().intersection(game._side_scroll.get_global_rect())
	check(visible.size.y >= 44, "Keyboard selection scrolls the chosen long answer into view")
	await tap(KEY_PAGEUP)
	check(game.phase == Main.Phase.CORE, "Page navigation only scrolls; it never submits")
	game._answer_buttons[0].grab_focus()
	await tap(KEY_TAB, false, true)
	check(root.gui_get_focus_owner() is Button and root.gui_get_focus_owner().text.begins_with("SKIP QUESTION"), "Shift+Tab reaches skip without a mouse")
	await tap(KEY_ENTER)
	check(game.phase == Main.Phase.COMBAT and game.model.get_summary().core_answered == 0, "Keyboard skip resumes without creating a study attempt")
