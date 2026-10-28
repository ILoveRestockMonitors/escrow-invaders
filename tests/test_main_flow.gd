extends SceneTree
## Deterministic UI/state integration; combat tuning is covered by the arena suite.
const MainScene = preload("res://main.tscn")
const MainScript = preload("res://scripts/main.gd")
var failures: Array[String] = []
var checks := 0
var game

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func settle() -> void:
	for frame in range(5):
		await process_frame
		if is_instance_valid(game):
			game.set_process(false)
			game.arena.set_process(false)

func fresh(level: int = 1) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = MainScene.instantiate()
	game.test_mode = true
	root.add_child(game)
	await settle()
	game.progression.state.level = level
	game.start_run()
	await settle()

func request_question() -> void:
	check(game.phase == MainScript.Phase.COMBAT, "Question is requested from a live encounter")
	game.arena.question_requested.emit()
	check(game.phase == MainScript.Phase.CORE, "Arena signal opens the encounter question")

func correct() -> void:
	game.submit_choice(int(game.current_question.answer))

func resume_battle() -> void:
	game._resume_battle()
	await settle()

func clear_battle() -> void:
	game.arena.freeze()
	game.arena.combat_finished.emit({"victory": true, "hull": int(game.progression.state.hull)})

func advance_to_combat() -> void:
	for step in range(20):
		match game.phase:
			MainScript.Phase.CLEAR: game._route_next()
			MainScript.Phase.SUMMARY: game._continue_checkpoint()
			MainScript.Phase.UPGRADE:
				var options: Array = game.progression.upgrade_options()
				game.choose_upgrade(String(options[0].id))
			MainScript.Phase.BONUS_INTRO: game._skip_bonus()
			MainScript.Phase.DEFEAT: game._route_next()
			_: break
		await settle()
	check(game.phase == MainScript.Phase.COMBAT, "Routing returns to a playable encounter")

func has_button(text: String) -> bool:
	for button in game._side.find_children("*", "Button", true, false):
		if button.text == text: return true
	return false

func _run() -> void:
	await test_answer_lock_and_retry()
	await test_reopened_feedback()
	await test_assistance_and_fatal()
	await test_bonus()
	await test_checkpoint()
	await test_unbounded_routing()
	if is_instance_valid(game):
		check(not game.model.persistence_enabled and not game.progression.persistence_enabled and not game.journal.persistence_enabled, "All test state is isolated from learner saves")
		game.queue_free()
		await process_frame
	print("Endless main flow: ", checks, " checks; ", failures.size(), " failures")
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)

func test_answer_lock_and_retry() -> void:
	await fresh()
	check(game.audio.muted, "Audio starts muted")
	check(game.model.get_summary().core_answered == 0, "Opening combat has not graded a question")
	var deployed_attempt: int = int(game.progression.state.current.attempt)
	game.start_run()
	game._route_next()
	await settle()
	check(int(game.progression.state.current.attempt) == deployed_attempt, "Duplicate Deploy cannot create a second combat attempt")
	game._process(120.0)
	check(game.phase == MainScript.Phase.COMBAT and int(game.progression.state.level) == 1, "Passing a timer never clears a combat objective")
	request_question()
	check(game.confidence == -1, "Confidence defaults to unknown")
	game._process(120.0)
	check(game.phase == MainScript.Phase.CORE and game.model.get_summary().core_answered == 0, "Core reading is untimed")
	correct()
	check(game.phase == MainScript.Phase.FEEDBACK and game.last_correct, "Correct answer freezes on official feedback")
	check(game.model.get_summary().core_answered == 1 and game.model.get_summary().core_correct == 1, "Independent retrieval is counted once")
	check(game.progression.state.current.response.counter == "independent", "Independent answer selects its tactical counter")
	var score: int = int(game.progression.state.total_xp)
	var receipts: int = game.model.response_receipts.size()
	correct()
	game._process(120.0)
	check(int(game.progression.state.total_xp) == score and game.model.response_receipts.size() == receipts, "Double submission and elapsed feedback cannot duplicate rewards or grading")
	await resume_battle()
	check(game.phase == MainScript.Phase.COMBAT, "One continue resumes the same encounter")
	game.arena.enemy_killed.emit("escort-1", "chaser")
	var kill_xp: int = int(game.progression.state.total_xp)
	var kills: int = game.total_kills
	game.arena.enemy_killed.emit("escort-1", "chaser")
	check(int(game.progression.state.total_xp) == kill_xp and game.total_kills == kills, "Duplicate kill signal cannot duplicate XP or kill count")
	var saved_id: String = game.progression.state.current.id
	var seed: int = int(game.progression.state.current.seed)
	var attempt: int = int(game.progression.state.current.attempt)
	game.arena.combat_finished.emit({"victory": false, "hull": 0})
	check(game.phase == MainScript.Phase.DEFEAT and int(game.progression.state.level) == 1, "Combat defeat keeps the uncleared level")
	check(int(game.progression.state.total_xp) == kill_xp, "Defeat retains actual earned XP")
	await advance_to_combat()
	check(game.progression.state.current.id == saved_id and int(game.progression.state.current.seed) == seed, "Combat retry retains encounter identity and seed")
	check(int(game.progression.state.current.attempt) == attempt + 1 and int(game.progression.state.hull) == 3, "Retry uses a new attempt with a fresh hull")
	check(game.progression.state.current.response.counter == "independent" and game.model.response_receipts.size() == receipts, "Resolved counter survives retry without regrading")
	check(game.model.get_summary().core_answered == 1 and int(game.progression.state.total_xp) == kill_xp, "Retry does not repeat question XP or academic response")
	clear_battle()
	var cleared_xp: int = int(game.progression.state.total_xp)
	check(game.phase == MainScript.Phase.CLEAR and int(game.progression.state.level) == 2, "Victory advances the completed objective")
	game.arena.combat_finished.emit({"victory": true, "hull": 3})
	check(int(game.progression.state.level) == 2 and int(game.progression.state.total_xp) == cleared_xp, "Duplicate clear signal cannot advance or reward twice")
	game._route_next()
	game._route_next()
	await advance_to_combat()
	for frame in range(10):
		if int(game.progression.state.current.get("attempt", 0)) > 0: break
		await process_frame
	var next_attempt: int = int(game.progression.state.current.attempt)
	game._route_next()
	game._route_next()
	await settle()
	check(int(game.progression.state.current.attempt) == next_attempt and int(game.progression.state.level) == 2, "Repeated Claim cannot relaunch or skip the next encounter")

func test_assistance_and_fatal() -> void:
	await fresh()
	request_question()
	game._show_hint()
	correct()
	check(game.phase == MainScript.Phase.FEEDBACK and game.last_correct, "A first answer with a requested hint resolves normally")
	check(game.model.get_summary().core_answered == 1 and game.model.get_summary().core_correct == 0 and game.model.get_summary().core_assisted == 1, "Hinted first answer retains assisted learning semantics")
	check(game.progression.state.current.response.counter == "assisted" and int(game.progression.state.total_xp) == 40, "Hinted first answer earns assisted counter and reward")
	await fresh()
	request_question()
	var wrong: int = (int(game.current_question.answer) + 1) % game.current_question.choices.size()
	game.submit_choice(wrong)
	check(int(game.progression.state.hull) == 2 and game.phase == MainScript.Phase.FEEDBACK, "First error costs one hull and opens remediation")
	check(game.progression.state.current.response.resolved and not has_button("TRY WITH THIS HINT"), "A nonfatal miss is final with no retry")
	game._retry_core()
	correct()
	check(int(game.progression.state.hull) == 2 and game.progression.state.current.response.counter == "solution", "Attempted retry cannot replace the miss or change hull")
	check(game.model.get_summary().core_answered == 1 and game.model.get_summary().core_correct == 0, "Guided recovery never erases the first miss")
	check(game.model.history.concepts[game.current_question.concept].needs_review, "Missed concept remains scheduled for review")
	await fresh()
	request_question()
	game.progression.state.hull = 1
	game.arena.hull = 1
	wrong = (int(game.current_question.answer) + 1) % game.current_question.choices.size()
	game.submit_choice(wrong)
	check(game.phase == MainScript.Phase.FEEDBACK and int(game.progression.state.hull) == 0, "Fatal question still presents explanation before defeat")
	check(has_button("VIEW DEFEAT") and not has_button("TRY WITH THIS HINT"), "Zero-hull feedback offers defeat without a misleading retry")
	check(game.progression.state.current.response.resolved and game.progression.state.current.response.counter == "solution", "Fatal miss retains a winnable solution-only counter")
	var answered: int = int(game.model.get_summary().core_answered)
	correct()
	check(int(game.progression.state.hull) == 0 and int(game.model.get_summary().core_answered) == answered, "A second click cannot revive or regrade fatal feedback")
	game._show_defeat()
	await advance_to_combat()
	check(int(game.progression.state.hull) == 3 and game.progression.state.current.response.counter == "solution", "Retry after fatal reading starts safely with solution override")
	check(int(game.model.get_summary().core_answered) == answered, "Fatal combat retry keeps original academic result")

func test_reopened_feedback() -> void:
	await fresh()
	request_question()
	correct()
	var ship: Dictionary = game.progression.state.duplicate(true)
	var history: Dictionary = game.model.history.duplicate(true)
	var receipts: Dictionary = game.model.response_receipts.duplicate(true)
	var stats: Dictionary = game.model._stats.duplicate(true)
	var attempts: Dictionary = game.model._run_attempts.duplicate(true)
	# Recreate the UI from the same durable payload fields. File fault injection and
	# journal reconciliation are exercised separately by the persistence suite.
	await fresh()
	game.arena.freeze()
	game.progression.state = ship.duplicate(true)
	game.model.history = history.duplicate(true)
	game.model.response_receipts = receipts.duplicate(true)
	game.model._stats = stats.duplicate(true)
	game.model._run_attempts = attempts.duplicate(true)
	game._show_ready()
	game.start_run()
	await advance_to_combat()
	check(game.phase == MainScript.Phase.COMBAT and game.progression.state.current.id == ship.current.id, "Reopening resolved feedback returns to the same fight")
	check(game.progression.state.current.response.counter == "independent", "Reopened fight restores its earned tactical counter")
	check(game.model.history == history and game.model.response_receipts == receipts, "Reopening feedback cannot regrade or change learning history")
	check(int(game.progression.state.total_xp) == int(ship.total_xp) and game.model.get_summary().core_answered == 1, "Reopening feedback cannot mint question XP or duplicate its recap")

func test_bonus() -> void:
	await fresh()
	# Use the real block's familiar bonus, while setting up its eligible checkpoint.
	game.arena.freeze()
	var bonus: Dictionary = game.model.bonus_questions[0]
	check(not bonus.is_empty(), "Fixture supplies a familiar short bonus")
	game.progression.state.block.index = 2
	game.progression.state.bonus = {"id": "integration-bonus-1", "status": "pending", "target_level": 3, "question": bonus, "response": {}, "enhancement": false}
	game._show_bonus_intro()
	game._process(60.0)
	check(game.phase == MainScript.Phase.BONUS_INTRO, "Bonus invitation does not run its clock")
	game.start_bonus()
	game._process(2.0)
	var remaining: float = game.bonus_remaining
	game._toggle_pause()
	game._process(30.0)
	correct()
	check(game.phase == MainScript.Phase.BONUS and is_equal_approx(game.bonus_remaining, remaining), "Pause blocks bonus answers and elapsed time")
	game._toggle_pause()
	game.arena.set_process(false)
	var hull: int = int(game.progression.state.hull)
	var combo: int = int(game.progression.state.combo)
	var xp: int = int(game.progression.state.total_xp)
	var history: Dictionary = game.model.history.concepts.duplicate(true)
	game._process(11.0)
	check(game.phase == MainScript.Phase.FEEDBACK and not game.last_correct, "Bonus timeout closes into feedback")
	check(int(game.progression.state.hull) == hull and int(game.progression.state.combo) == 0 and int(game.progression.state.total_xp) == xp, "Bonus timeout resets combo without a hull or XP penalty")
	check(game.model.history.concepts == history and game.model.get_summary().core_answered == 0, "Bonus timeout does not alter learning mastery or core count")
	game._process(11.0)
	check(game.model.get_summary().bonus_timed_out == 1 and game.progression.state.bonus.status == "resolved", "Timeout is recorded once and cannot reopen")
	await fresh()
	game.arena.freeze()
	bonus = game.model.bonus_questions[0]
	game.progression.state.block.index = 2
	game.progression.state.bonus = {"id": "integration-bonus-2", "status": "pending", "target_level": 3, "question": bonus, "response": {}, "enhancement": false}
	game._show_bonus_intro()
	game.start_bonus()
	correct()
	check(game.progression.state.bonus.enhancement and int(game.progression.state.total_xp) == 100, "Correct bonus grants one enhancement and its XP")
	correct()
	check(int(game.progression.state.total_xp) == 100 and game.model.get_summary().bonus_correct == 1, "Bonus double click cannot grant extra reward")

func test_checkpoint() -> void:
	await fresh()
	var previous_ids: Array = []
	for question in game.model.core_questions: previous_ids.append(question.id)
	for level in range(1, 6):
		request_question()
		correct()
		await resume_battle()
		clear_battle()
		if level < 5: await advance_to_combat()
	check(int(game.progression.state.level) == 6 and game.progression.state.checkpoint_pending, "Five cleared encounters bank checkpoint and unlock level six")
	check(game.model.get_summary().core_answered == 5 and game.model.get_summary().core_correct == 5, "Checkpoint contains five actual independent responses")
	game._route_next()
	check(game.phase == MainScript.Phase.SUMMARY, "Checkpoint recap appears before next encounter")
	check(int(game.progression.state.hull) == 3, "Checkpoint restores hull")
	var history: Dictionary = game.model.history.duplicate(true)
	game._continue_checkpoint()
	await advance_to_combat()
	check(game.model.get_summary().core_answered == 0 and int(game.progression.state.block.index) == 0, "Continuing resets only the five-question recap")
	check(game.model.history == history, "New block preserves long-term learning history")
	check(game.model.core_questions.size() == 5 and game.progression.state.current.level == 6, "New eligible block supplies the continuing climb")

func test_unbounded_routing() -> void:
	for level in [5, 20, 100, 125, 1000]:
		await fresh(level)
		request_question()
		correct()
		await resume_battle()
		clear_battle()
		check(int(game.progression.state.level) == level + 1, "Level %d is a checkpoint, not a terminal stage" % level)
		await advance_to_combat()
		check(int(game.progression.state.current.level) == level + 1, "Playable encounter exists beyond level %d" % level)
