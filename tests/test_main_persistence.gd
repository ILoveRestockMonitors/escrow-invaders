extends SceneTree
## Integration checks use real atomic files under isolated test storage.
const MainScene = preload("res://main.tscn")
const MainScript = preload("res://scripts/main.gd")
const Study = preload("res://scripts/study_model.gd")
const Progression = preload("res://scripts/progression_model.gd")
var game
var save_directory := ""
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func settle() -> void:
	for frame in range(5):
		await process_frame
		if is_instance_valid(game):
			game.set_process(false)
			game.arena.set_process(false)

func fresh() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = MainScene.instantiate()
	# Prevent _ready from ever loading the real learner's browser/user save.
	game.test_mode = true
	root.add_child(game)
	await settle()
	save_directory = "user://main-persistence-%d" % Time.get_ticks_usec()
	game.model.save_path = save_directory + "/study.json"
	game.progression.save_path = save_directory + "/ship.json"
	game.journal.journal_path = save_directory + "/journal.json"
	game.model.persistence_enabled = true
	game.progression.persistence_enabled = true
	game.journal.persistence_enabled = true
	game.model.clock_override_unix = 1800000000
	game.test_mode = false
	game.start_run()
	await settle()
	check(game.phase == MainScript.Phase.COMBAT, "Isolated persistent fixture reaches combat.")

func blocker() -> String:
	var path := save_directory + "/blocker"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("An ordinary file prevents creation of a child save directory.")
	file.close()
	return path

func question() -> void:
	game.arena.question_requested.emit()
	check(game.phase == MainScript.Phase.CORE, "Encounter opens its question.")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _test_hint()
	await _test_failed_grade()
	await _test_failed_clear()
	await _test_ordinary_retry()
	await _test_readonly_study()
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	if failures.is_empty():
		print("Main persistence: ", checks, " checks passed.")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)

func _test_hint() -> void:
	await fresh()
	question()
	game._show_hint()
	var reloaded := Progression.new()
	reloaded.save_path = game.progression.save_path
	reloaded.load_progress()
	check(bool(reloaded.state.current.get("hint_used", false)), "Hint exposure is saved before answering.")
	game.submit_choice(int(game.current_question.answer))
	var response: Dictionary = game.progression.state.current.response
	check(response.resolved and response.counter == "assisted", "Hinted first answer resolves as an assisted counter.")
	check(response.first_result.first_attempt and response.first_result.assisted, "A hinted first response retains correct grading stage.")
	check(int(game.progression.state.total_xp) == 40, "Hinted answer grants only assisted XP.")

func _test_failed_grade() -> void:
	await fresh()
	question()
	var original_path: String = game.model.save_path
	game.model.save_path = blocker() + "/study.json"
	game.submit_choice(int(game.current_question.answer))
	check(game.phase == MainScript.Phase.FEEDBACK and not game.journal.warning.is_empty(), "Failed learning write holds a visible recovery screen.")
	check(int(game.progression.state.total_xp) == 0, "Ship reward waits for durable learning commit.")
	game.model.save_path = original_path
	game._recover_save()
	check(game.phase == MainScript.Phase.FEEDBACK, "Recovered answer returns to explanation instead of launching another question.")
	check(game.progression.state.current.response.resolved, "Recovered answer applies its saved counter.")
	check(int(game.progression.state.total_xp) == 100, "Recovered answer grants exactly one independent reward.")
	var reloaded := Study.new()
	reloaded.save_path = original_path
	reloaded.load_progress()
	check(int(reloaded.get_summary().core_answered) == 1 and int(reloaded.get_summary().core_correct) == 1, "Recovered learning save contains one actual first answer.")
	game._recover_save()
	check(int(game.progression.state.total_xp) == 100, "Repeated recovery does not repeat the reward.")

func _test_failed_clear() -> void:
	await fresh()
	question()
	game.submit_choice(int(game.current_question.answer))
	game._resume_battle()
	await settle()
	var original_path: String = game.progression.save_path
	game.progression.save_path = blocker() + "/ship.json"
	game.arena.freeze()
	game.arena.combat_finished.emit({"victory": true, "hull": 2})
	check(int(game.progression.state.level) == 2 and game.progression.state.current.is_empty(), "Completed objective remains in memory after its save fails.")
	check(not game.progression.progress_warning.is_empty(), "Failed clear is visibly unsaved.")
	game._route_next()
	check(game.phase == MainScript.Phase.FEEDBACK, "Routing cannot bypass a failed ordinary clear save.")
	game.progression.save_path = original_path
	game._recover_save()
	check(game.phase in [MainScript.Phase.UPGRADE, MainScript.Phase.COMBAT], "Recovered clear routes to progress/combat, never an empty question.")
	for step in range(5):
		if game.phase != MainScript.Phase.UPGRADE:
			break
		game.choose_upgrade(String(game.progression.upgrade_options()[0].id))
		await settle()
	await settle()
	check(game.phase == MainScript.Phase.COMBAT and int(game.progression.state.current.level) == 2, "Next playable encounter follows successful clear recovery.")
	var reloaded := Progression.new()
	reloaded.save_path = original_path
	reloaded.load_progress()
	check(int(reloaded.state.level) == 2 and int(reloaded.state.total_xp) == 165, "Recovered clear saves one first-clear reward and its original answer reward.")

func _test_ordinary_retry() -> void:
	await fresh()
	var original_path: String = game.progression.save_path
	game.progression.save_path = blocker() + "/ship.json"
	game._on_enemy_killed("actual-fixture-kill", "ordinary")
	check(int(game.progression.state.total_xp) == 4, "A genuine kill remains recoverable in memory.")
	check(not game._commit_pending_saves(), "No journal entry cannot disguise an ordinary save failure.")
	game.progression.save_path = original_path
	check(game._commit_pending_saves(), "Retry writes pending ordinary progression state.")
	var reloaded := Progression.new()
	reloaded.save_path = original_path
	reloaded.load_progress()
	check(int(reloaded.state.total_xp) == 4, "Ordinary kill reward reaches durable storage.")
	check(reloaded.grant_kill("actual-fixture-kill", "ordinary") == 0, "Retried ordinary save preserves kill deduplication.")

func _test_readonly_study() -> void:
	await fresh()
	var original_path: String = game.model.save_path
	var before := FileAccess.get_file_as_string(original_path)
	game.model.persistence_enabled = false
	game.model.progress_warning = "Unreadable learning progress was left untouched. Saving is disabled until recovery."
	check(not game._commit_pending_saves(), "Unrecoverable learning storage does not report save success.")
	game._show_ready()
	game._route_next()
	check(game.phase == MainScript.Phase.FEEDBACK, "Disabled learning storage remains at recovery screen.")
	game._recover_save()
	check(game.phase == MainScript.Phase.FEEDBACK and not game.model.progress_warning.is_empty(), "Retry cannot bypass disabled storage.")
	check(FileAccess.get_file_as_string(original_path) == before, "Disabled learning save remains untouched.")
