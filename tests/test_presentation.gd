extends SceneTree
## Exercise actual input routing and the new controls without touching learner saves.
const MainScene = preload("res://main.tscn")
var game
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func settle() -> void:
	for frame in range(5): await process_frame

func space() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _run() -> void:
	for dimensions in [Vector2i(375,667), Vector2i(390,844), Vector2i(844,390), Vector2i(1280,720)]:
		root.size = dimensions
		game = MainScene.instantiate()
		game.test_mode = true
		root.add_child(game)
		await settle()
		check(game.audio.muted, "Audio remains opt-in at " + str(dimensions))
		check(game._hangar_view.visible and not game.arena.visible, "Home presents the hangar")
		var history: Dictionary = game.model.history.duplicate(true)
		game.start_run()
		await settle()
		check(game.arena.visible and not game._hangar_view.visible, "Launching shows the live arena")
		check(game._pulse_button.is_visible_in_tree(), "Pulse action visible in combat")
		var rect: Rect2 = game._pulse_button.get_global_rect()
		check(rect.position.x >= 0 and rect.end.x <= root.size.x and rect.end.y <= root.size.y and rect.size.y >= 44, "Pulse fits with a proper touch target")
		game._sound_button.grab_focus()
		await space()
		check(float(game.arena.pulse_status().cooldown) > 6.0, "Space fires pulse even with Sound focused")
		check(game.audio.muted, "Space does not accidentally toggle the focused Sound button")
		game._toggle_pause()
		var cooldown: float = game.arena.pulse_status().cooldown
		game._pulse_button.pressed.emit()
		await space()
		check(is_equal_approx(cooldown, float(game.arena.pulse_status().cooldown)), "Pause freezes recharge and blocks pulse")
		game._open_help()
		game._music_setting.grab_focus()
		await space()
		check(game.paused and game._help_layer.visible and is_equal_approx(cooldown, float(game.arena.pulse_status().cooldown)), "Help controls work without firing pulse")
		var master_muted: bool = game.audio.muted
		game._music_setting.button_pressed = false
		game._effects_setting.button_pressed = false
		check(not game.audio.music_enabled and not game.audio.effects_enabled and game.audio.muted == master_muted, "Separate mix toggles preserve master mute")
		game._close_help()
		check(game.paused, "Closing Help retains an existing pause")
		game._toggle_pause()
		check(game.arena.is_processing(), "Combat resumes normally")
		game.arena._arrive_target()
		await settle()
		check(not game._pulse_row.visible, "Question view hides combat-only controls")
		var before: Dictionary = game.arena.pulse_status().duplicate()
		await space()
		check(game.arena.pulse_status() == before and game.model.history == history, "Space during study cannot activate pulse or record a study answer")
		game.queue_free()
		await process_frame
	print("Presentation UI: ", checks, " checks; ", failures.size(), " failures")
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
