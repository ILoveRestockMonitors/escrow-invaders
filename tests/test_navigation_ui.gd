extends SceneTree
## Menu/help navigation must preserve the actual activity and saved study state.
const MainScene = preload("res://main.tscn")
const MainScript = preload("res://scripts/main.gd")
var game
var checks := 0
var failures: Array[String] = []
var dimensions := Vector2i(1280, 720)

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message + " at " + str(dimensions))

func settle() -> void:
	for frame in range(5):
		await process_frame
		if is_instance_valid(game):
			game.set_process(false)
			game.arena.set_process(false)

func fresh(launch: bool = false) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	root.size = dimensions
	game = MainScene.instantiate()
	game.test_mode = true
	root.add_child(game)
	await settle()
	check(game.model.load_course_bank(), "Navigation uses the installed course without loading learner saves")
	game._show_ready()
	if launch:
		game.start_run()
		await settle()
		check(game.phase == MainScript.Phase.COMBAT, "Fixture launches an actual combat attempt")

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_key_input(event)

func gui_key(code: int, shifted: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shifted
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func nav_buttons() -> Array:
	return game._menu_nav.find_children("*", "Button", true, false)

func battle_snapshot() -> Dictionary:
	return {"elapsed": game.arena._elapsed, "enemies": game.arena._enemies.duplicate(true), "bullets": game.arena._bullets.duplicate(true), "queue": game.arena._spawn_queue.duplicate(true), "packet": game.arena._packet, "hull": game.arena.hull, "question_opened": game.arena._question_opened, "counter": game.arena._resolved_counter}

func _run() -> void:
	await test_safe_menu_routes()
	await test_combat_help()
	await test_reading_help()
	await test_bonus_help()
	await test_boost_return()
	await test_help_keyboard_focus()
	await test_mobile_help()
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	print("Navigation UI: ", checks, " checks; ", failures.size(), " failures")
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)

func test_safe_menu_routes() -> void:
	await fresh()
	var state: Dictionary = game.progression.state.duplicate(true)
	var learning: Dictionary = game.model.history.duplicate(true)
	check(nav_buttons().size() == 4, "Safe menus expose four consistent destinations")
	var targets := [MainScript.Phase.SHOP, MainScript.Phase.HANGAR, MainScript.Phase.READY]
	for index in range(3):
		nav_buttons()[[1, 2, 0][index]].pressed.emit()
		await settle()
		check(game.phase == targets[index] and game._menu_nav.visible, "Visible menu action reaches its named destination")
		check(game.progression.state == state and game.model.history == learning and game._arena_attempt_id.is_empty(), "Menu navigation starts no attempt, spends no currency and records no answers")
	game._navigate_menu(-1)
	game._navigate_menu(4)
	check(game.phase == MainScript.Phase.READY, "Invalid destination cannot route to an unrelated activity")
	game.start_run()
	await settle()
	var attempt: String = game.progression.state.current.attempt_id
	for destination in range(3): game._navigate_menu(destination)
	check(game.phase == MainScript.Phase.COMBAT and game.progression.state.current.attempt_id == attempt, "Menu helper cannot leave a live battle or create another attempt")
	check(not game._menu_nav.visible, "Safe-menu navigation is hidden during combat")

func test_combat_help() -> void:
	await fresh(true)
	game.arena._simulate(0.3)
	var before: Dictionary = battle_snapshot()
	var attempt: String = game.progression.state.current.attempt_id
	game._help_button.pressed.emit()
	check(game._help_layer.visible and game.paused and not game.arena.is_processing(), "Help visibly pauses an active battle")
	check(game.phase == MainScript.Phase.COMBAT, "Help leaves the battle phase intact")
	# Opening twice must not replace the original unpaused state with 'paused'.
	game._open_help()
	for frame in range(4): await process_frame
	game._process(10.0)
	check(battle_snapshot() == before and game.progression.state.current.attempt_id == attempt, "Reading help advances no enemies, bullets, hull or attempt")
	game._navigate_menu(1)
	key(KEY_W)
	check(game.phase == MainScript.Phase.COMBAT and game._help_layer.visible, "Underlying menu/number actions cannot navigate through help")
	key(KEY_ESCAPE)
	check(not game._help_layer.visible and not game.paused and game.arena.is_processing(), "Escape closes help and restores the formerly running battle")
	game.arena.set_process(false)
	check(battle_snapshot() == before, "Closing help itself neither resets nor advances the saved live fight")
	game._toggle_pause()
	check(game.paused, "Player can already be paused before requesting help")
	game._open_help()
	game._help_close_button.pressed.emit()
	check(not game._help_layer.visible and game.paused and not game.arena.is_processing(), "Closing help preserves an existing manual pause")
	check(game._pause_button.text == "Resume", "Existing pause still offers Resume after help closes")

func test_reading_help() -> void:
	dimensions = Vector2i(390, 844)
	await fresh(true)
	var longest: Dictionary = {}
	var length := 0
	for question in game.model.question_bank:
		var n: int = String(question.prompt).length() + str(question.choices).length()
		if n > length:
			longest = question
			length = n
	game.progression.state.current.question = longest.duplicate(true)
	game.arena._arrive_target()
	await settle()
	game._side_scroll.ensure_control_visible(game._answer_buttons.back())
	await settle()
	var scroll: int = game._side_scroll.scroll_vertical
	var question: Dictionary = game.current_question.duplicate(true)
	var response: Dictionary = game.progression.state.current.response.duplicate(true)
	var history: Dictionary = game.model.history.duplicate(true)
	var first_button: int = game._answer_buttons[0].get_instance_id()
	check(scroll > 0, "Long-question fixture starts with meaningful reading scroll")
	game._open_help()
	game.submit_choice(int(question.answer))
	key([KEY_W, KEY_A, KEY_S, KEY_D][int(question.answer)])
	game._show_hint()
	check(game.phase == MainScript.Phase.CORE and game.progression.state.current.response == response and game.model.history == history, "Help blocks both tapped and numeric-key answers without grading")
	for topic in range(3): game._render_help_topic(topic)
	game._close_help()
	await settle()
	check(game.current_question == question and game._side_scroll.scroll_vertical == scroll, "Closing help restores the exact question and reading position")
	check(game._answer_buttons[0].get_instance_id() == first_button, "Help preserves the existing question controls instead of rebuilding their state")
	check(not game.paused and not game.arena.combat_active, "Closing question help leaves danger frozen for reading")
	game.submit_choice(int(question.answer))
	check(game.phase == MainScript.Phase.FEEDBACK, "Question becomes answerable again after closing help")
	var graded: Dictionary = game.progression.state.current.response.duplicate(true)
	var xp: int = int(game.progression.state.total_xp)
	game._open_help()
	key(KEY_W)
	game._close_help()
	check(game.phase == MainScript.Phase.FEEDBACK and game.progression.state.current.response == graded and int(game.progression.state.total_xp) == xp, "Feedback help cannot regrade or repeat a reward")
	dimensions = Vector2i(1280, 720)

func test_bonus_help() -> void:
	await fresh(true)
	var bonus: Dictionary = game.model.bonus_questions[0]
	game.progression.state.bonus = {"id": "navigation-bonus", "status": "pending", "target_level": 3, "question": bonus, "response": {}, "enhancement": false}
	game.arena.freeze()
	game._show_bonus_intro()
	game.start_bonus()
	game._process(2.5)
	var remaining: float = game.bonus_remaining
	var question_id: String = game.current_question.id
	check(is_equal_approx(remaining, 7.5), "Timed bonus has already consumed part of its time")
	game._open_help()
	game._process(60.0)
	game.submit_choice(int(game.current_question.answer))
	check(game.phase == MainScript.Phase.BONUS and is_equal_approx(game.bonus_remaining, remaining) and game.progression.state.bonus.response.is_empty(), "Help freezes the existing bonus timer and answer input")
	game._close_help()
	check(not game.paused and game.current_question.id == question_id and is_equal_approx(game.bonus_remaining, remaining), "Closing help resumes the same timed question without resetting its clock")
	game._process(0.5)
	check(is_equal_approx(game.bonus_remaining, remaining - 0.5), "Bonus time continues normally after help")
	game._toggle_pause()
	game._open_help()
	game._close_help()
	game._process(60.0)
	check(game.paused and is_equal_approx(game.bonus_remaining, remaining - 0.5), "Help never clears an existing pause on a timed bonus")

func test_boost_return() -> void:
	await fresh()
	game._show_shop()
	game._offer_boost("upgrade", "power")
	var offered: Dictionary = game.progression.state.boost.duplicate(true)
	game._boost_back_to_shop()
	check(game.phase == MainScript.Phase.SHOP and game.progression.state.boost == offered and game.progression.state.current.is_empty(), "Back to upgrades preserves an offered study set without launching combat")
	game._show_boost_intro()
	game._start_study_boost()
	game.submit_choice(int(game.current_question.answer))
	game._continue_boost()
	var active: Dictionary = game.progression.state.boost.duplicate(true)
	var question_id: String = game.current_question.id
	var recap: Dictionary = game.model.get_boost_summary(String(active.id)).duplicate(true)
	game._boost_back_to_shop()
	check(game.phase == MainScript.Phase.SHOP and game.progression.state.boost == active and game.progression.state.current.is_empty(), "Back to upgrades preserves an active set and its completed review count")
	check(game.model.get_boost_summary(String(active.id)) == recap, "Returning to the shop does not grade or erase a boost review")
	game._show_boost_intro()
	game._start_study_boost()
	check(game.phase == MainScript.Phase.BOOST and game.current_question.id == question_id, "Resume study returns to the same next saved question")

func contained(control: Control) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= -1 and rect.end.x <= root.size.x + 1 and rect.position.y >= -1 and rect.end.y <= root.size.y + 1

func test_help_keyboard_focus() -> void:
	for destination in [0, 1]:
		await fresh()
		game.progression.state.coins = 1000
		game.progression.state.gems = 30
		game._navigate_menu(destination)
		await settle()
		# Preserve mixed focus policies, not merely restore every control to ALL.
		game._effects.focus_mode = Control.FOCUS_CLICK
		var original_modes: Dictionary = {}
		for control in game.find_children("*", "Control", true, false):
			if control == game._help_layer or game._help_layer.is_ancestor_of(control): continue
			original_modes[control] = control.focus_mode
		var original_focus: Control = game._side.find_children("*", "Button", true, false)[0]
		original_focus.grab_focus()
		var phase: int = game.phase
		var state: Dictionary = game.progression.state.duplicate(true)
		var visited_focus: Dictionary = {}
		game._open_help()
		var disabled_underlay := true
		for control in original_modes:
			disabled_underlay = disabled_underlay and control.focus_mode == Control.FOCUS_NONE
		check(disabled_underlay, "Help removes all underlying menu controls from keyboard focus")
		check(root.gui_get_focus_owner() == game._help_close_button, "Opening Help gives actual GUI focus to Close")
		for shifted in [false, true]:
			for step in range(8):
				await gui_key(KEY_TAB, shifted)
				var focus: Control = root.gui_get_focus_owner()
				check(is_instance_valid(focus) and game._help_layer.is_ancestor_of(focus), "Real Tab/Shift-Tab remains within Help")
				if is_instance_valid(focus): visited_focus[focus.get_instance_id()] = true
				await gui_key(KEY_ENTER if step % 2 == 0 else KEY_SPACE)
				check(game.phase == phase and game.progression.state == state and game._arena_attempt_id.is_empty(), "GUI Enter/Space cannot start a battle or purchase an underlying upgrade")
				if not game._help_layer.visible: game._open_help()
		check(visited_focus.size() >= 2, "Real Tab traversal moves between Help controls while a current topic is disabled")
		# Exercise a real GUI activation of Close, rather than its callback directly.
		game._help_close_button.grab_focus()
		await gui_key(KEY_SPACE)
		check(not game._help_layer.visible, "Space activates the focused Close button through GUI input")
		var restored_modes := true
		for control in original_modes:
			restored_modes = restored_modes and control.focus_mode == original_modes[control]
		check(restored_modes, "Closing Help restores every original underlying focus mode")
		check(root.gui_get_focus_owner() == original_focus, "Closing Help restores the original focused menu control")

func verify_nav(label: String) -> void:
	await settle()
	check(game._menu_nav.visible and contained(game._menu_nav), label + ": navigation is immediately visible in the viewport")
	for button in nav_buttons():
		check(contained(button) and button.size.x >= 44 and button.size.y >= 44, label + ": every destination is reachable with a 44px touch target")
	check(contained(game._help_button) and game._help_button.size.x >= 44 and game._help_button.size.y >= 44, label + ": Help is reachable without scrolling")

func verify_help(label: String) -> void:
	await settle()
	check(game._help_layer.visible and contained(game._help_panel), label + ": help panel fits the viewport")
	check(contained(game._help_close_button) and game._help_close_button.size.x >= 44 and game._help_close_button.size.y >= 44, label + ": Close is visible with a usable touch target")
	for button in game._help_topic_buttons:
		check(contained(button) and button.size.x >= 44 and button.size.y >= 44, label + ": help topics remain reachable")
	check(contained(game._help_scroll) and game._help_scroll.size.y > 40, label + ": help keeps usable scroll space")
	# Decorative separators may follow the final paragraph; test readable content.
	var paragraphs: Array = game._help_body.find_children("*", "Label", true, false)
	if not paragraphs.is_empty():
		var last: Control = paragraphs.back()
		game._help_scroll.ensure_control_visible(last)
		await settle()
		var overlap: Rect2 = last.get_global_rect().intersection(game._help_scroll.get_global_rect())
		check(overlap.size.y > 10, label + ": final help content can be reached by scrolling")
	check(contained(game._help_close_button), label + ": Close stays reachable after scrolling help")

func test_mobile_help() -> void:
	for size in [Vector2i(375,667), Vector2i(390,844), Vector2i(430,932), Vector2i(844,390), Vector2i(1280,720)]:
		dimensions = size
		await fresh()
		for destination in range(3):
			game._navigate_menu(destination)
			await verify_nav("Menu %d" % destination)
		var phase: int = game.phase
		game._help_button.pressed.emit()
		check(game._help_topic_buttons.size() == 3, "Help groups explanations into three topics")
		for topic in range(3):
			game._help_topic_buttons[topic].pressed.emit()
			await verify_help("Help topic %d" % topic)
		game._help_close_button.pressed.emit()
		await settle()
		check(game.phase == phase and not game._help_layer.visible and not game.paused, "Closing menu help returns to the same menu without a pause")
		check(not game.model.persistence_enabled and not game.progression.persistence_enabled and not game.journal.persistence_enabled, "Navigation checks never write learner history")
