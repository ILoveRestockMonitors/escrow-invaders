extends SceneTree
## Same-attempt revive flow, isolated durable recovery, and phone readability.
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
	for frame in range(10):
		await process_frame
		if is_instance_valid(game):
			game.set_process(false)
			game.arena.set_process(false)

func fresh(launch: bool = true) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	root.size = dimensions
	game = MainScene.instantiate()
	game.test_mode = true
	root.add_child(game)
	await settle()
	check(game.model.load_course_bank(), "Installed course supplies verified revive questions")
	game._show_ready()
	if launch:
		game.start_run()
		await settle()
		check(game.phase == MainScript.Phase.COMBAT and not game._arena_attempt_id.is_empty(), "Fixture launches an actual arena attempt")

func die() -> void:
	game.arena.hull = 1
	game.progression.state.hull = 1
	game.arena._invulnerability = 0.0
	game.arena.combat_active = true
	game.arena._take_hit("TEST TELEGRAPH")

	check(game.phase == MainScript.Phase.DEFEAT and int(game.progression.state.hull) == 0, "Real arena damage reaches defeat at zero hull")

func open_core() -> void:
	game.arena._arrive_target()
	check(game.phase == MainScript.Phase.CORE and game.arena._question_opened, "Real target arrival opens the saved core question")

func correct() -> void:
	game.submit_choice(int(game.current_question.answer))

func wrong() -> void:
	game.submit_choice((int(game.current_question.answer) + 1) % game.current_question.choices.size())

func visible_text() -> String:
	var text := ""
	for label in game._side.find_children("*", "Label", true, false): text += label.text + "\n"
	for button in game._side.find_children("*", "Button", true, false): text += button.text + "\n"
	return text

func battle_signature() -> Dictionary:
	var enemies: Array = []
	for enemy in game.arena._enemies:
		enemies.append({"id": enemy.id, "hp": enemy.hp, "target": enemy.target, "armored": enemy.armored})
	return {"enemies": enemies, "queue": game.arena._spawn_queue.duplicate(true), "packet": game.arena._packet, "elapsed": game.arena._elapsed, "counter": game.arena._resolved_counter, "target_defeated": game.arena._target_defeated}

func enable_saves(folder: String) -> void:
	game.model.save_path = folder + "/study.json"
	game.progression.save_path = folder + "/arcade.json"
	game.journal.journal_path = folder + "/journal.json"
	game.model.persistence_enabled = true
	game.progression.persistence_enabled = true
	game.journal.persistence_enabled = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))

func reopen(folder: String) -> void:
	await fresh(false)
	enable_saves(folder)
	game.model.load_progress()
	game.progression.load_progress()
	check(game.journal.recover(), "Saved revive response commits reconcile on reopen")
	check(game.model.progress_warning.is_empty() and game.progression.progress_warning.is_empty(), "Revive study and arcade payloads reload cleanly")
	game._show_defeat()
	game._start_revive()
	await settle()

func _run() -> void:
	await test_precore_revive()
	await test_postcore_and_second_death()
	await test_wrong_retry_and_hints()
	await test_fatal_core_and_decline()
	await test_boost_isolation()
	await test_durable_guided_revive()
	await test_durable_earned_revive()
	await test_save_recovery()
	await test_mobile()
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	print("Revive UI: ", checks, " checks; ", failures.size(), " failures")
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)

func test_precore_revive() -> void:
	await fresh()
	var attempt: String = game.progression.state.current.attempt_id
	var core: Dictionary = game.progression.state.current.question.duplicate(true)
	die()
	var frozen: Dictionary = battle_signature()
	game._start_revive()
	check(game.phase == MainScript.Phase.REVIVE and game._revive_mode and not game._boost_mode, "Defeat starts its own revive question mode")
	var revive_id: String = game.progression.state.current.revive.id
	check(String(game.current_question.id).begins_with(game.model.bank_id + ":") and game.current_question.id != core.id, "Revive selects an actual course question distinct from the encounter core")
	game._process(120.0)
	check(game.phase == MainScript.Phase.REVIVE and battle_signature() == frozen and not game.arena.combat_active, "Untimed revive reading freezes the live fight")
	correct()
	check(game.phase == MainScript.Phase.FEEDBACK and game.progression.state.current.revive.status == "earned", "Correct answer earns revival while explanation remains visible")
	check(int(game.progression.state.hull) == 0 and not game.arena.combat_active, "Correct feedback does not silently resume danger")
	var recap: Dictionary = game.model.get_revive_summary(revive_id)
	check(recap.core_answered == 1 and recap.core_correct == 1 and game.model.get_summary().core_answered == 0, "Revive recall has its own honest recap")
	game._resume_revive()
	await settle()
	check(game.phase == MainScript.Phase.COMBAT and game.arena.combat_active and game.arena.hull == 3, "Pre-core revive resumes screening with full hull")
	check(game.progression.state.current.attempt_id == attempt and game._arena_attempt_id == attempt and battle_signature() == frozen, "Live revival preserves attempt, enemies, packets and elapsed combat")
	# The deferred resume allows one rendered frame; the arena suite checks exact durations.
	check(game.arena._invulnerability > 1.5 and game.arena._resume_remaining > 0.1, "Revival retains its return shield and cue after layout settles")
	check(game.progression.state.current.response.is_empty(), "Pre-core revive does not invent an answer or armor override")
	open_core()
	check(game.current_question.id == core.id, "Original core remains available after the early revive")

func test_postcore_and_second_death() -> void:
	await fresh()
	open_core()
	correct()
	game._resume_battle()
	await settle()
	game._on_enemy_killed("previously-earned-kill", "ordinary")
	var attempt: String = game.progression.state.current.attempt_id
	var core_response: Dictionary = game.progression.state.current.response.duplicate(true)
	var receipts: Dictionary = game.progression.state.current.kill_receipts.duplicate(true)
	var wallet: Array = [game.progression.state.total_xp, game.progression.state.coins, game.progression.state.gems]
	die()
	var frozen: Dictionary = battle_signature()
	game._start_revive()
	correct()
	game._resume_revive()
	await settle()
	check(battle_signature() == frozen, "Post-core revival preserves damaged target, armor and earned counter instead of replaying it")
	check(game.progression.state.current.attempt_id == attempt and game.progression.state.current.kill_receipts == receipts, "Revival retains original reward identities")
	check(game.progression.state.current.response.first_result == core_response.first_result and game.model.get_summary().core_answered == 1, "Reviving does not regrade the core answer")
	game._on_enemy_killed("previously-earned-kill", "ordinary")
	game._resume_revive()
	correct()
	check([game.progression.state.total_xp, game.progression.state.coins, game.progression.state.gems] == [int(wallet[0])+115,int(wallet[1])+20,wallet[2]], "Correct revive pays its streak reward once; duplicate actions pay nothing")
	check(bool(game.progression.state.current.revive_used), "The successful revival is marked used for this attempt")
	die()
	var state: Dictionary = game.progression.state.duplicate(true)
	game._start_revive()
	check(game.phase == MainScript.Phase.DEFEAT and game.progression.state == state, "A second death cannot offer or start a second revive on the same attempt")
	check(not visible_text().contains("REVIVE / ANSWER 1 QUESTION"), "Exhausted defeat removes the revive action")
	game._route_next()
	await settle()
	for step in range(10):
		if game.phase != MainScript.Phase.UPGRADE: break
		game.choose_upgrade(String(game.progression.upgrade_options()[0].id))
		await settle()
	check(game.phase == MainScript.Phase.COMBAT and game.progression.state.current.attempt_id != attempt and not bool(game.progression.state.current.revive_used), "An explicit rebuild starts a genuinely new attempt with a fresh revive allowance")

func test_wrong_retry_and_hints() -> void:
	await fresh()
	die()
	game._start_revive()
	var id: String = game.progression.state.current.revive.id
	var question_id: String = game.current_question.id
	game._toggle_pause()
	correct()
	game._show_hint()
	game._leave_revive()
	check(game.phase == MainScript.Phase.REVIVE and game.progression.state.current.revive.status == "active" and not game.progression.state.current.revive.hint_used and int(game.model.get_revive_summary(id).get("core_answered", 0)) == 0, "Paused revive blocks answering, hint and leave actions")
	game._toggle_pause()
	game.arena.set_process(false)
	wrong()
	check(game.progression.state.current.revive.status == "feedback" and int(game.progression.state.hull) == 0, "Wrong first revive stays dead and offers guidance")
	var response_before: Dictionary = game.progression.state.current.revive.response.duplicate(true)
	game._show_solution()
	game._retry_core()
	game._resume_battle()
	check(game.phase == MainScript.Phase.FEEDBACK and game.progression.state.current.revive.response == response_before and int(game.progression.state.hull) == 0, "Core solution and continuation callbacks cannot resolve or bypass a revive")
	game._resume_revive()
	check(game.phase == MainScript.Phase.FEEDBACK and not game.arena.combat_active, "Wrong answer cannot claim a revive")
	game._retry_revive()
	wrong()
	correct()
	var recap: Dictionary = game.model.get_revive_summary(id)
	check(game.phase == MainScript.Phase.FEEDBACK and game.current_question.id == question_id, "Old retry callback leaves final feedback open")
	check(game.progression.state.current.revive.response == response_before, "No later input changes the original miss")
	check(recap.core_answered == 1 and recap.core_correct == 0 and recap.mastery_advances == 0, "Final wrong answer keeps one failed retrieval")
	check(game.progression.state.current.revive.status == "feedback", "Wrong revive never earns a claim")
	game._toggle_pause()
	game._resume_revive()
	check(int(game.progression.state.hull) == 0, "Pause cannot bypass final wrong feedback")
	game._toggle_pause()
	game._leave_revive()
	check(game.phase == MainScript.Phase.DEFEAT, "Final feedback returns to defeat")
	await fresh()
	die()
	game._start_revive()
	id = game.progression.state.current.revive.id
	game._show_hint()
	correct()
	recap = game.model.get_revive_summary(id)
	check(recap.core_answered == 1 and recap.core_assisted == 1 and recap.core_correct == 0, "Hint before first correct answer is recorded as assisted")

func test_fatal_core_and_decline() -> void:
	await fresh()
	open_core()
	game.progression.state.hull = 1
	game.arena.hull = 1
	wrong()
	var first: Dictionary = game.progression.state.current.response.first_result.duplicate(true)
	check(game.phase == MainScript.Phase.FEEDBACK and int(game.progression.state.hull) == 0 and visible_text().contains(String(game.current_question.explanation)), "Fatal core mistake retains its official explanation before defeat")
	game._show_defeat()
	game._start_revive()
	correct()
	game._resume_revive()
	await settle()
	check(game.phase == MainScript.Phase.COMBAT and game.arena.combat_active and game.arena._counter_applied, "Fatal-core revive resumes a winnable armor-overridden encounter")
	check(game.progression.state.current.response.first_result == first and game.model.get_summary().core_correct == 0 and game.model.get_summary().core_answered == 1, "Fatal-core revival preserves the original incorrect learning result")
	await fresh()
	die()
	var history: Dictionary = game.model.history.duplicate(true)
	game._start_revive()
	game._leave_revive()
	check(game.phase == MainScript.Phase.DEFEAT and int(game.progression.state.hull) == 0 and not bool(game.progression.state.current.get("revive_used", false)), "Declining an unanswered revive gives no hull or reward")
	check(game.model.history == history and int(game.progression.state.total_xp) == 0, "Decline creates no academic response or XP")
	game._start_revive()
	wrong()
	game._leave_revive()
	check(game.phase == MainScript.Phase.DEFEAT and int(game.progression.state.hull) == 0, "Leaving after a wrong answer cannot count as correct")

func test_boost_isolation() -> void:
	await fresh(false)
	game._show_shop()
	game._offer_boost("upgrade", "power")
	game._start_study_boost()
	correct()
	var boost: Dictionary = game.progression.state.boost.duplicate(true)
	var boost_summary: Dictionary = game.model.get_boost_summary(String(boost.id)).duplicate(true)
	game._leave_boost()
	await settle()
	for step in range(10):
		if game.phase != MainScript.Phase.UPGRADE: break
		game.choose_upgrade(String(game.progression.upgrade_options()[0].id))
		await settle()
	die()
	game._start_revive()
	correct()
	game._resume_revive()
	await settle()
	check(game.progression.state.boost == boost and game.model.get_boost_summary(String(boost.id)) == boost_summary, "Reviving neither replaces nor regrades a paused three-question boost")

func test_durable_earned_revive() -> void:
	await fresh()
	var folder := "user://revive-ui-earned-" + str(Time.get_ticks_usec())
	enable_saves(folder)
	game._on_enemy_killed("retained-kill", "ordinary")
	die()
	game._start_revive()
	var attempt: String = game.progression.state.current.attempt_id
	var id: String = game.progression.state.current.revive.id
	var question: Dictionary = game.current_question.duplicate(true)
	correct()
	var receipts: Dictionary = game.progression.state.current.kill_receipts.duplicate(true)
	var xp: int = int(game.progression.state.total_xp)
	check(game.model.save_progress() and game.progression.save_progress(), "Earned revive and learning result save durably")
	await reopen(folder)
	check(game.phase == MainScript.Phase.FEEDBACK and game.progression.state.current.revive.status == "earned", "Reload returns the already-earned revive explanation")
	check(game.current_question.id == question.id and game.current_question.prompt == question.prompt and game.current_question.choices == question.choices and int(game.current_question.answer) == int(question.answer) and game.current_question.explanation == question.explanation and game.model.get_revive_summary(id).core_answered == 1, "Reload preserves the official question and one academic attempt")
	check(visible_text().to_lower().contains("restart"), "Reload honestly explains that the live arena must restart")
	game._resume_revive()
	await settle()
	check(game.phase == MainScript.Phase.COMBAT and game.arena.combat_active and game.arena.hull == 3, "Reloaded earned revive launches a playable arena")
	check(game.progression.state.current.attempt_id == attempt and game._arena_attempt_id == attempt and game.progression.state.current.kill_receipts.keys() == receipts.keys(), "Reloaded revive keeps the same attempt and kill receipt identities")
	for key in receipts: check(int(game.progression.state.current.kill_receipts.get(key, -1)) == int(receipts[key]), "Reloaded kill receipt retains its original amount")
	game._on_enemy_killed("retained-kill", "ordinary")
	check(int(game.progression.state.total_xp) == xp, "Restarted arena cannot repay an already-earned kill")
	check(game.model.save_progress() and game.progression.save_progress(), "Claimed revive persists")
	await reopen(folder)
	check(game.phase == MainScript.Phase.DEFEAT and bool(game.progression.state.current.revive_used), "Reloading a claimed revive cannot offer another same-attempt revival")

func test_durable_guided_revive() -> void:
	await fresh()
	var folder := "user://revive-ui-guided-" + str(Time.get_ticks_usec())
	enable_saves(folder)
	die()
	game._start_revive()
	var id: String = game.progression.state.current.revive.id
	var question_id: String = game.current_question.id
	game._show_hint()
	wrong()
	check(game.model.save_progress() and game.progression.save_progress(), "Wrong assisted revive persists before closing")
	await reopen(folder)
	check(game.phase == MainScript.Phase.FEEDBACK and game.current_question.id == question_id and game.progression.state.current.revive.status == "feedback", "Reload preserves the same missed revive and its guidance")
	var recap: Dictionary = game.model.get_revive_summary(id)
	check(recap.core_answered == 1 and recap.core_assisted == 1 and recap.core_correct == 0, "Reload retains the original assisted incorrect retrieval")
	game._retry_revive()
	check(game.phase == MainScript.Phase.FEEDBACK and game.current_question.id == question_id, "Reloaded feedback cannot reopen the original question")
	correct()
	recap = game.model.get_revive_summary(id)
	check(game.progression.state.current.revive.status == "feedback" and recap.core_answered == 1 and recap.core_correct == 0, "A missed revive stays final after reload")

func test_save_recovery() -> void:
	await fresh()
	die()
	game._start_revive()
	var id: String = game.progression.state.current.revive.id
	var question_id: String = game.current_question.id
	game.journal.test_interrupt_after = "study"
	correct()
	check(game._save_problem_open and game.phase == MainScript.Phase.FEEDBACK, "Interrupted revive grade displays recovery")
	game.journal.test_interrupt_after = ""
	enable_saves("user://revive-ui-recover-" + str(Time.get_ticks_usec()))
	game.test_mode = false
	game._recover_save()
	await settle()
	check(not game._save_problem_open and game._revive_mode and game.phase == MainScript.Phase.FEEDBACK, "Recovery returns to earned revive feedback rather than core or boost routing")
	check(game.current_question.id == question_id and game.progression.state.current.revive.status == "earned" and game.model.get_revive_summary(id).core_answered == 1, "Recovered revive is earned and graded exactly once")
	var original_path: String = game.progression.save_path
	var blocker := original_path.get_base_dir() + "/blocker"
	var file := FileAccess.open(blocker, FileAccess.WRITE)
	file.store_string("Blocks a child save directory.")
	file.close()
	game.progression.save_path = blocker + "/arcade.json"
	game._resume_revive()
	check(game._save_problem_open and not game.arena.combat_active, "Failed claim save holds the live battle frozen")
	game.progression.save_path = original_path
	game._recover_save()
	await settle()
	if game.phase == MainScript.Phase.FEEDBACK: game._resume_revive()
	await settle()
	check(not game._save_problem_open and game.phase == MainScript.Phase.COMBAT and game.arena.hull == 3, "Claim save recovery resumes the earned same-attempt revival")
	check(game.model.get_revive_summary(id).core_answered == 1, "Claim recovery never regrades the earned answer")

func contained(control: Control) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= -1 and rect.end.x <= root.size.x + 1 and rect.position.y >= -1 and rect.end.y <= root.size.y + 1

func verify_panel(label: String) -> void:
	await settle()
	check(contained(game._header) and contained(game._status_row), label + ": header and hull controls remain contained")
	check(contained(game._side_panel) and game._side_panel.visible, label + ": question panel fits the viewport")
	if game._wallet_label.visible: check(contained(game._wallet_label), label + ": wallet remains contained")
	var buttons: Array = game._side.find_children("*", "Button", true, false)
	for button in buttons:
		if not button.is_visible_in_tree(): continue
		check(button.size.y >= 44 and button.size.x <= game._side_scroll.size.x + 1, label + ": button wraps with a usable touch target")
	if not buttons.is_empty():
		var last: Control = buttons.back()
		game._side_scroll.ensure_control_visible(last)
		await settle()
		var reachable: Rect2 = last.get_global_rect().intersection(game._side_scroll.get_global_rect())
		check(reachable.size.y >= minf(44.0, last.size.y), label + ": final action is reachable by scrolling")

func test_mobile() -> void:
	for size in [Vector2i(375,667), Vector2i(390,844), Vector2i(430,932), Vector2i(844,390), Vector2i(1280,720)]:
		dimensions = size
		await fresh()
		die()
		await verify_panel("Revive invitation")
		game._start_revive()
		var longest: Dictionary = {}
		var length := 0
		for question in game.model.question_bank:
			var n: int = String(question.prompt).length() + str(question.choices).length()
			if n > length:
				longest = question
				length = n
		game.progression.state.current.revive.question = longest.duplicate(true)
		game._begin_revive_question()
		await verify_panel("Longest official revive question")
		check(game._answer_buttons.size() == longest.choices.size(), "Every official revive choice remains available")
		check(game._content_title.get_theme_font_size("font_size") == (21 if game._mobile else 25), "Revive prompt uses readable question typography")
		for button in game._answer_buttons: check(button.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "Long revive choices wrap")
		wrong()
		await verify_panel("Revive hint feedback")
		game._retry_revive()
		await settle()
		check(game.phase == MainScript.Phase.FEEDBACK, "Final wrong feedback remains readable without retry")
		await verify_panel("Final revive explanation")
		# A fresh attempt still supports a real first-answer revive on a phone.
		game._leave_revive()
		game._route_next()
		await settle()
		die()
		game._start_revive()
		correct()
		await verify_panel("Earned first-answer revive")
		game._resume_revive()
		await settle()
		check(contained(game._arena_panel) and game._arena_panel.visible, "Revived combat fits the phone arena")
		die()
		await verify_panel("Revive exhausted defeat")
		check(not game.model.persistence_enabled and not game.progression.persistence_enabled and not game.journal.persistence_enabled, "Responsive revive checks never write learner history")
