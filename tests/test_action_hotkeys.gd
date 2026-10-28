extends SceneTree
## Context-action keyboard coverage uses real GUI events and isolated test state.
const MainScene = preload("res://main.tscn")
const Main = preload("res://scripts/main.gd")
const ANSWERS = [KEY_W, KEY_A, KEY_S, KEY_D]
var game
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")
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
func key(code: int, pressed := true, echo := false, ctrl := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	event.ctrl_pressed = ctrl
	Input.parse_input_event(event)
	await settle()
func tap(code: int, ctrl := false) -> void:
	await key(code, true, false, ctrl)
	await key(code, false, false, ctrl)
func battle_question() -> void:
	game.start_run()
	await settle()
	game.arena._arrive_target()
	await settle()
func verify_badges(label: String) -> void:
	var registered: Dictionary = {}
	for node in game.find_children("*", "Button", true, false):
		var button := node as Button
		if not button.is_visible_in_tree() or game._answer_buttons.has(button): continue
		if game._help_layer.visible != game._help_layer.is_ancestor_of(button): continue
		check(button.has_meta("action_key"), label + ": every visible action has a key")
		if not button.has_meta("action_key"): continue
		var code := int(button.get_meta("action_key"))
		check(code not in ANSWERS, label + ": action keys never take WASD")
		check(not registered.has(code), label + ": action keys are unique")
		registered[code] = button
		check(game._action_hotkeys.get(code) == button, label + ": registry points at the active button")
		var badge := button.get_node_or_null("ActionHotkey") as Label
		check(is_instance_valid(badge) and (badge.visible or button.text.ends_with("[H]")), label + ": shortcut is visibly labeled")
		check(button.tooltip_text.begins_with("Esc" if code == KEY_ESCAPE else "Space" if code == KEY_SPACE else OS.get_keycode_string(code)), label + ": tooltip agrees with key")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await test_question_actions()
	await test_menu_actions()
	await test_modal_and_focus()
	await test_phase_inventory()
	game.queue_free()
	await process_frame
	print("Action hotkeys: ", checks, " checks; ", failures.size(), " failures")
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)

func test_question_actions() -> void:
	await fresh()
	await battle_question()
	verify_badges("Core")
	await tap(KEY_G)
	check(game.confidence == 0 and game.answer_attempts == 0, "G selects Guessing without answering")
	await tap(KEY_J)
	check(game.confidence == 1 and game.answer_attempts == 0, "J selects Leaning without answering")
	await tap(KEY_L)
	check(game.confidence == 2 and game.answer_attempts == 0, "L selects Sure without answering")
	await tap(KEY_K, true)
	check(game.phase == Main.Phase.CORE, "Browser-modified actions are ignored")
	await tap(ANSWERS[(int(game.current_question.answer) + 1) % 4])
	verify_badges("Miss feedback")
	check(not game._action_hotkeys.has(KEY_R) and not game._action_hotkeys.has(KEY_V), "Retry and solution shortcuts are absent after a final miss")
	await key(KEY_R)
	check(game.phase == Main.Phase.FEEDBACK, "R cannot reopen a submitted answer")
	await key(KEY_R, true, true)
	check(game.phase == Main.Phase.FEEDBACK and game.answer_attempts == 1, "Held old retry cannot submit again")
	await key(KEY_R, false)
	await tap(ANSWERS[(int(game.current_question.answer) + 1) % 4])
	await key(KEY_V)
	check(game.phase == Main.Phase.FEEDBACK and game.progression.state.current.response.resolved, "Final feedback already contains the official explanation")
	await key(KEY_V, true, true)
	check(game.phase == Main.Phase.FEEDBACK, "Held solution cannot dismiss feedback")
	await key(KEY_V, false)
	await tap(KEY_C)
	check(game.phase == Main.Phase.COMBAT, "C continues resolved feedback")
	await fresh()
	await battle_question()
	await tap(KEY_K)
	check(game.phase == Main.Phase.COMBAT and game.model.get_summary().core_answered == 0, "K skips without inventing a learning attempt")

func test_menu_actions() -> void:
	await fresh()
	verify_badges("Home")
	await tap(KEY_U)
	check(game.phase == Main.Phase.SHOP, "U opens upgrades")
	verify_badges("Shop")
	var offers: Array[Button] = []
	for node in game._side.find_children("*", "Button", true, false):
		if node.text.begins_with("ANSWER 3 QUESTIONS"): offers.append(node)
	check(offers.size() == 3, "Three distinct study upgrade actions exist")
	if offers.size() == 3:
		await tap(int(offers[1].get_meta("action_key")))
		check(game.phase == Main.Phase.BOOST_INTRO and game.progression.get_active_boost().item == "cadence", "Repeated action shortcut selects its specific upgrade")
		verify_badges("Study offer")
		await tap(KEY_B)
		check(game.phase == Main.Phase.SHOP, "B returns to upgrades")
	await tap(KEY_E)
	check(game.phase == Main.Phase.HANGAR, "E opens weapons")
	verify_badges("Weapons")
	var before: Dictionary = game.progression.state.duplicate(true)
	for node in game._side.find_children("*", "Button", true, false):
		if node.disabled and node.has_meta("action_key"):
			await tap(int(node.get_meta("action_key")))
	check(game.progression.state == before, "Disabled weapon shortcuts cannot equip or unlock")
	await tap(KEY_O)
	check(game.phase == Main.Phase.READY, "O returns Home")
	await tap(KEY_P)
	check(game.phase == Main.Phase.COMBAT, "P starts the actual battle")

func test_modal_and_focus() -> void:
	await fresh()
	game.start_run()
	await settle()
	await tap(KEY_F)
	check(game._help_layer.visible and game.paused, "F opens Help and pauses combat")
	verify_badges("Help")
	await tap(KEY_W)
	check(game._help_layer.visible and game.paused, "Help does not leak answer/movement shortcuts")
	var mix: bool = game.audio.music_enabled
	await tap(KEY_M)
	check(game.audio.music_enabled != mix and game.audio.muted, "Help M changes music without toggling master sound underneath")
	game._notification(Main.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await tap(KEY_ESCAPE)
	check(not game._help_layer.visible and game.paused, "Focus loss in Help keeps the battle paused when Help closes")
	await tap(KEY_ESCAPE)
	check(not game.paused and game.phase == Main.Phase.COMBAT, "Explicit Escape resumes after focus loss")
	await tap(KEY_F)
	await tap(KEY_ESCAPE)
	check(not game.paused, "Help without a focus loss preserves the normal return behavior")

func test_phase_inventory() -> void:
	for dimensions in [Vector2i(390,844), Vector2i(1280,720)]:
		root.size = dimensions
		await fresh()
		await battle_question()
		await tap(ANSWERS[int(game.current_question.answer)])
		verify_badges("Correct feedback")
		game._show_upgrades()
		await settle()
		verify_badges("Free rank upgrade")
		game.progression.state.hull = 0
		game._show_defeat()
		await settle()
		verify_badges("Defeat")
		await tap(KEY_Y)
		check(game.phase == Main.Phase.REVIVE, "Y opens the revive question")
		verify_badges("Revive")
		await tap(KEY_B)
		check(game.phase == Main.Phase.DEFEAT, "B returns from revive without a claim")
		game._show_summary()
		await settle()
		verify_badges("Checkpoint")
		game._show_save_problem()
		await settle()
		verify_badges("Save recovery")
