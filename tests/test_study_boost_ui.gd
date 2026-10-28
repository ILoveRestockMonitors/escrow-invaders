extends SceneTree
## Optional study-economy UI with real questions and isolated durable roundtrips.
const MainScene = preload("res://main.tscn")
const MainScript = preload("res://scripts/main.gd")
var checks := 0
var failures: Array[String] = []
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

func fresh(launch: bool = true) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = MainScene.instantiate()
	game.test_mode = true
	root.add_child(game)
	await settle()
	check(game.model.load_course_bank(), "Installed bank supplies actual boost questions")
	game._show_ready()
	if launch:
		game.start_run()
		await settle()

func request_question() -> void:
	game.arena.question_requested.emit()
	check(game.phase == MainScript.Phase.CORE, "Encounter offers its optional core question")

func clear_without_study() -> void:
	request_question()
	game._skip_core()
	await settle()
	game.arena.freeze()
	game.arena.combat_finished.emit({"victory": true, "hull": int(game.progression.state.hull)})
	check(game.phase == MainScript.Phase.CLEAR, "Skipped study still permits an objective clear")

func advance_to_combat() -> void:
	for step in range(20):
		match game.phase:
			MainScript.Phase.CLEAR: game._route_next()
			MainScript.Phase.SUMMARY: game._continue_checkpoint()
			MainScript.Phase.UPGRADE: game.choose_upgrade(String(game.progression.upgrade_options()[0].id))
			MainScript.Phase.BONUS_INTRO: game._skip_bonus()
			MainScript.Phase.DEFEAT: game._route_next()
			_: break
		await settle()
	check(game.phase == MainScript.Phase.COMBAT, "Normal encounter remains playable")

func correct() -> void:
	game.submit_choice(int(game.current_question.answer))

func complete_remaining_boost() -> void:
	for step in range(5):
		if game.progression.get_active_boost().get("status", "") == "complete":
			if game.phase == MainScript.Phase.FEEDBACK: game._continue_boost()
			break
		if game.phase == MainScript.Phase.FEEDBACK: game._continue_boost()
		if game.phase == MainScript.Phase.BOOST_INTRO: game._start_study_boost()
		if game.phase == MainScript.Phase.BOOST: correct()
		await settle()
	check(game.progression.get_active_boost().get("status", "") == "complete", "Three resolved reviews finish the selected offer")

func visible_text() -> String:
	var text := ""
	for label in game._side.find_children("*", "Label", true, false): text += label.text + "\n"
	return text

func enable_isolated_saves(folder: String) -> void:
	game.model.save_path = folder + "/study.json"
	game.progression.save_path = folder + "/arcade.json"
	game.journal.journal_path = folder + "/journal.json"
	game.model.persistence_enabled = true
	game.progression.persistence_enabled = true
	game.journal.persistence_enabled = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))

func reopen_saved(folder: String) -> void:
	await fresh(false)
	enable_isolated_saves(folder)
	game.model.load_progress()
	game.progression.load_progress()
	check(game.journal.recover(), "Durable boost response journal reconciles on reopen")
	check(game.model.progress_warning.is_empty() and game.progression.progress_warning.is_empty(), "Saved study and ship payloads load cleanly")
	game._show_ready()
	await settle()

func _run() -> void:
	await test_optional_core_and_normal_shop()
	await test_double_loot_and_learning()
	await test_shortfall_purchase()
	await test_resume_and_durable_offer()
	await test_boost_save_recovery()
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	print("Study boost UI: ", checks, " checks; ", failures.size(), " failures")
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)

func test_optional_core_and_normal_shop() -> void:
	await fresh()
	var history: Dictionary = game.model.history.duplicate(true)
	request_question()
	var hull: int = int(game.progression.state.hull)
	game._toggle_pause()
	game._skip_core()
	check(game.phase == MainScript.Phase.CORE and game.progression.state.current.response.is_empty(), "Pause blocks Skip just like answer submission")
	game._toggle_pause()
	game.arena.set_process(false)
	game._skip_core()
	await settle()
	check(game.phase == MainScript.Phase.COMBAT and game.progression.state.current.response.skipped, "Skip resumes combat with a saved manual override")
	check(int(game.progression.state.total_xp) == 0 and int(game.progression.state.hull) == hull, "Skip grants no question XP and loses no hull")
	check(game.model.history == history and game.model.get_summary().core_answered == 0, "Skip creates no academic attempt or mastery")
	game._skip_core()
	check(int(game.progression.state.total_xp) == 0, "Duplicate Skip cannot mint reward")
	game.arena.freeze()
	game.arena.combat_finished.emit({"victory": true, "hull": hull})
	for level in range(2, 6):
		await advance_to_combat()
		await clear_without_study()
	check(int(game.progression.state.level) == 6 and game.model.get_summary().core_answered == 0, "Five no-study clears progress without fabricating learning")
	game._route_next()
	check(game.phase == MainScript.Phase.SUMMARY and visible_text().contains("No counterstrike answers this block"), "No-study checkpoint is explicit about its empty academic recap")
	check(game.model.history == history, "No-study block leaves all learning history unchanged")
	game._show_shop()
	var option: Dictionary = game.progression.shop_options()[0]
	var coins: int = int(game.progression.state.coins)
	var damage: float = float(game.progression.get_loadout().damage)
	check(option.affordable, "Normal combat earnings can fund a permanent improvement without study")
	game._buy_shop_upgrade(String(option.id))
	check(int(game.progression.state.coins) == coins - int(option.cost) and int(game.progression.state.shop_ranks.power) == 1, "Normal shop purchase spends its actual price and installs the tier")
	check(float(game.progression.get_loadout().damage) > damage, "Purchased improvement changes combat output")

func test_double_loot_and_learning() -> void:
	await fresh()
	await clear_without_study()
	var base: Dictionary = game.progression.state.last_clear_reward.duplicate(true)
	var start_coins: int = int(game.progression.state.coins)
	var start_gems: int = int(game.progression.state.gems)
	var start_xp: int = int(game.progression.state.total_xp)
	game._offer_boost("double_clear")
	check(game.phase == MainScript.Phase.BOOST_INTRO, "Clear reward offers an optional study preview")
	var offer: Dictionary = game.progression.get_active_boost()
	check(offer.reward == {"coins": base.coins, "gems": base.gems, "xp": base.xp}, "Double offer quotes exactly the clear reward")
	game._process(120.0)
	check(game.progression.get_active_boost().status == "offered", "Offer does not start a question or timer automatically")
	game._start_study_boost()
	check(game.phase == MainScript.Phase.BOOST and game.progression.get_active_boost().questions.size() == 3, "Boost begins exactly three real questions")
	var ids: Array = []
	for question in game.progression.get_active_boost().questions:
		check(question.id not in ids and String(question.id).begins_with(game.model.bank_id + ":"), "Boost questions are distinct installed course questions")
		ids.append(question.id)
	game._process(120.0)
	check(game.phase == MainScript.Phase.BOOST and int(game.progression.get_active_boost().index) == 0, "Boost reading is untimed")
	game._toggle_pause()
	correct()
	check(int(game.progression.get_active_boost().index) == 0 and game.phase == MainScript.Phase.BOOST, "Pause locks boost answer submission")
	game._toggle_pause()
	game.arena.set_process(false)
	var wrong: int = (int(game.current_question.answer) + 1) % game.current_question.choices.size()
	var hull: int = int(game.progression.state.hull)
	var combo: int = int(game.progression.state.combo)
	game.submit_choice(wrong)
	check(game.phase == MainScript.Phase.FEEDBACK and int(game.progression.get_active_boost().index) == 1, "Wrong boost answer is final and completes its slot")
	check(int(game.progression.state.hull) == hull and int(game.progression.state.combo) == combo, "Optional study mistake has no combat penalty")
	game._retry_boost()
	correct()
	check(int(game.progression.get_active_boost().index) == 1, "Attempted retry cannot advance beyond the final first review")
	var recap: Dictionary = game.model.get_boost_summary(String(offer.id))
	check(recap.core_answered == 1 and recap.core_correct == 0, "Missed first retrieval is preserved without a retry")
	game._continue_boost()
	game._show_hint()
	correct()
	recap = game.model.get_boost_summary(String(offer.id))
	check(recap.core_answered == 2 and recap.core_assisted == 1 and recap.core_correct == 0, "Requested first-attempt hint remains assisted in the boost record")
	check(int(game.progression.state.coins) == start_coins - 7 and int(game.progression.state.gems) == start_gems, "Partial set applies one miss penalty and one hinted reward; completion loot waits")
	game._continue_boost()
	correct()
	check(game.progression.get_active_boost().status == "complete", "Third resolved question completes the offer")
	check(int(game.progression.state.coins) == start_coins + int(base.coins) + 13 and int(game.progression.state.gems) == start_gems + int(base.gems) and int(game.progression.state.total_xp) == start_xp + int(base.xp) + 140, "Completion adds one quoted clear reward, excluding unrelated earnings")
	check(game.model.get_summary().core_answered == 0, "Three boost responses do not inflate encounter-core accuracy")
	recap = game.model.get_boost_summary(String(offer.id))
	check(recap.core_answered == 3 and recap.core_correct == 1 and recap.mastery_advances == 0, "Boost recap records actual retrieval without immediate fake mastery")
	var wallet: Array = [game.progression.state.coins, game.progression.state.gems, game.progression.state.total_xp]
	correct()
	game._continue_boost()
	game._continue_boost()
	check(visible_text().contains("1 / 3 independent first answers"), "Completion screen shows the separate honest study-set recap")
	game._start_study_boost()
	check([game.progression.state.coins, game.progression.state.gems, game.progression.state.total_xp] == wallet, "Repeated Answer/Claim/Start cannot claim a complete offer again")
	check(game.progression.create_boost_offer("double_clear").has("error"), "The same cleared level cannot generate another double reward")

func test_shortfall_purchase() -> void:
	await fresh(false)
	game.progression.state.coins = 40
	game._show_shop()
	var item: Dictionary = game.progression.shop_options()[0]
	check(not item.affordable, "Shop fixture has a real currency shortfall")
	game._offer_boost("upgrade", "power")
	var offer: Dictionary = game.progression.get_active_boost()
	check(int(offer.quote.cost) == int(item.cost) and int(offer.quote.rank) == 0 and offer.quote.currency == "coins", "Study purchase binds the advertised item, tier, cost and currency")
	check(visible_text().contains(str(item.cost)), "Upgrade preview displays the quoted price")
	game._start_study_boost()
	check(not game.progression.buy_upgrade("power"), "An active upgrade offer locks direct purchase of the same tier")
	var hull: int = int(game.progression.state.hull)
	game.submit_choice((int(game.current_question.answer) + 1) % game.current_question.choices.size())
	game._boost_solution()
	check(int(game.progression.get_active_boost().index) == 1 and int(game.progression.state.hull) == hull, "Reading a solution resolves a missed boost review without a hull penalty")
	check(game.model.get_boost_summary(String(offer.id)).core_correct == 0, "Solution completion does not invent an independent correct answer")
	# Additional earnings remain possible while the player leaves and resumes.
	# The approved offer promises the item; currently available coins contribute.
	game.progression.state.coins = 55
	await complete_remaining_boost()
	check(int(game.progression.state.shop_ranks.power) == 1 and int(game.progression.state.coins) == 0, "Study installs exactly the quoted tier using the current contribution")
	var matching_receipts := 0
	for receipt in game.progression.state.receipts.values():
		var reward: Dictionary = receipt.get("reward", {})
		if reward.get("upgrade", "") == "power":
			matching_receipts += 1
			check(int(reward.spent) == 95 and int(reward.covered) == int(item.cost) - 95 and int(reward.rank) == 1, "Purchase receipt reports spent currency, study-covered remainder and installed rank")
	check(matching_receipts == 1, "One transaction owns the upgrade-install reward")
	game._show_boost_intro()
	game._start_study_boost()
	check(int(game.progression.state.shop_ranks.power) == 1, "Reopening completed offer cannot install a second tier")

func test_resume_and_durable_offer() -> void:
	await fresh()
	var folder := "user://boost-ui-" + str(Time.get_ticks_usec())
	enable_isolated_saves(folder)
	check(game.model.save_progress() and game.progression.save_progress(), "Isolated initial saves commit")
	await clear_without_study()
	game._offer_boost("double_clear")
	game._start_study_boost()
	correct()
	var original: Dictionary = game.progression.get_active_boost()
	var next_id: String = original.questions[1].id
	game._leave_boost()
	await advance_to_combat()
	check(game.progression.get_active_boost().id == original.id and int(game.progression.get_active_boost().index) == 1, "Leaving active study preserves its offer and completed slot")
	await clear_without_study()
	game._offer_boost("double_clear")
	check(game.progression.get_active_boost().id == original.id and game.progression.get_active_boost().reward == original.reward, "A later clear cannot overwrite an unfinished offer or its reward quote")
	check(game.model.save_progress() and game.progression.save_progress(), "Intermediate reward and study state are durably saved")
	await reopen_saved(folder)
	game._show_boost_intro()
	game._start_study_boost()
	check(game.phase == MainScript.Phase.BOOST and game.current_question.id == next_id, "Reload resumes the same next study question")
	check(int(game.progression.get_active_boost().index) == 1, "Reload preserves completed study progress")
	for slot in range(3):
		var restored: Dictionary = game.progression.get_active_boost().questions[slot]
		var saved: Dictionary = original.questions[slot]
		check(restored.id == saved.id and restored.prompt == saved.prompt and restored.choices == saved.choices and int(restored.answer) == int(saved.answer) and restored.explanation == saved.explanation, "Reload preserves each question, official choices, key and explanation")
	var before_coins: int = int(game.progression.state.coins)
	var before_gems: int = int(game.progression.state.gems)
	await complete_remaining_boost()
	check(int(game.progression.state.coins) == before_coins + int(original.reward.coins) + 40 and int(game.progression.state.gems) == before_gems + int(original.reward.gems) + 1, "Resumed offer pays its original clear reward and two correct-answer rewards with a streak gem")
	var wallet: Array = [int(game.progression.state.coins), int(game.progression.state.gems), int(game.progression.state.total_xp)]
	await reopen_saved(folder)
	game._show_boost_intro()
	game._start_study_boost()
	check(game.progression.get_active_boost().status == "complete" and [int(game.progression.state.coins), int(game.progression.state.gems), int(game.progression.state.total_xp)] == wallet, "Reloading a claimed offer preserves wallet without paying again")

func test_boost_save_recovery() -> void:
	await fresh(false)
	game._show_shop()
	game._offer_boost("upgrade", "reactor")
	game._start_study_boost()
	var first_id: String = game.current_question.id
	game.journal.test_interrupt_after = "study"
	correct()
	check(game.phase == MainScript.Phase.FEEDBACK and game._save_problem_open, "Interrupted boost commit opens save recovery")
	game.journal.test_interrupt_after = ""
	# Real recovery invokes the non-test save path; isolated files avoid learner data.
	var folder := "user://boost-ui-recovery-" + str(Time.get_ticks_usec())
	enable_isolated_saves(folder)
	game.test_mode = false
	game._recover_save()
	game.test_mode = true
	await settle()
	check(not game._save_problem_open and game._boost_mode, "Recovery returns to boost flow rather than encounter feedback")
	check(int(game.progression.get_active_boost().index) == 1 and game.model.get_boost_summary(String(game.progression.get_active_boost().id)).core_answered == 1, "Recovery commits the answer once and advances its study slot")
	check(game.current_question.id == first_id or game.current_question.id == game.progression.get_active_boost().questions[1].id, "Recovered UI shows a valid saved boost question")
