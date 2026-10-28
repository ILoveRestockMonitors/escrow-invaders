extends SceneTree
const Progression = preload("res://scripts/progression_model.gd")
const Study = preload("res://scripts/study_model.gd")
const Journal = preload("res://scripts/response_journal.gd")
const Evolution = preload("res://scripts/ship_evolution.gd")
const MainScene = preload("res://main.tscn")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	call_deferred("_run")

func setup(path: String = "") -> Dictionary:
	var study := Study.new()
	var ship := Progression.new()
	var journal := Journal.new(study, ship)
	study.persistence_enabled = not path.is_empty()
	ship.persistence_enabled = not path.is_empty()
	journal.persistence_enabled = not path.is_empty()
	if not path.is_empty():
		study.save_path = path + "/study.json"
		ship.save_path = path + "/ship.json"
		journal.journal_path = path + "/journal.json"
	return {"study": study, "ship": ship, "journal": journal}

func answer(c: Dictionary, correct: bool, hinted: bool = false) -> Dictionary:
	var q: Dictionary = c.study.question_bank[int(c.ship.state.level)]
	c.ship.ensure_encounter(q)
	c.ship.begin_attempt()
	var result: Dictionary = c.journal.resolve(q, correct, hinted, -1)
	c.ship.clear_encounter()
	return result

func _run() -> void:
	var unique: Dictionary = {}
	for index in range(Evolution.HULLS.size()):
		var rank := 1 if index == 0 else int(Evolution.RANKS[index - 1])
		check(Evolution.stage(rank) == index, "Evolution rank threshold is exact")
		var image := Evolution.texture(rank).get_image()
		var digest := image.get_data().hex_encode().sha256_text()
		check(not unique.has(digest), "Every hull has unique rendered pixels")
		unique[digest] = true
		check(image.get_width() > 0 and not image.is_empty(), "Hull imports successfully")
		if index > 0: check(Evolution.stage(rank - 1) == index - 1, "Next design stays locked before rank")
	_test_rank_41()
	var c := setup()
	var first := answer(c, true)
	check(first.xp == 100 and first.answer_reward.coins == 20, "Correct response pays the new base reward")
	check(c.ship.state.pending_upgrades > 0, "One correct answer immediately earns a free rank upgrade")
	var second := answer(c, true)
	var third := answer(c, true)
	check(second.xp == 115 and third.xp == 130 and third.answer_reward.gems == 1, "Independent streak adds XP and third-answer gem")
	for index in range(8):
		check(answer(c, true).xp <= 160, "Streak XP remains capped")
	var miss := answer(c, false)
	check(miss.xp == 0 and miss.answer_reward.penalty == 15 and int(c.ship.state.answer_streak) == 0, "Miss loses coins, earns no XP and resets streak")
	check(answer(c, true).xp == 100, "Streak starts again after miss")
	var hinted := answer(c, true, true)
	check(hinted.xp == 40 and hinted.answer_reward.coins == 8 and int(c.ship.state.answer_streak) == 0, "Hinted answer earns smaller reward and resets independent streak")
	for rank in [1,3,6,10,16,24,41,45,55,70,90,120,1000]:
		c.ship.state.rank = rank
		var loadout: Dictionary = c.ship.get_loadout()
		check(loadout.evolution == Evolution.stage(rank) and loadout.ship_rank == rank, "Combat receives the permanent hull rank")
		check(loadout.damage >= 2 and loadout.fire_rate >= 1, "Evolution grants actual combat stats")
	# Recover a coin penalty at every journal boundary without repeating it.
	for boundary in ["journal", "study", "arcade"]:
		var path := "user://evolution-%s-%d" % [boundary, Time.get_ticks_usec()]
		var saved := setup(path)
		saved.ship.state.coins = 50
		saved.ship.state["answer_streak"] = 4
		saved.ship.ensure_encounter(saved.study.question_bank[0])
		saved.ship.begin_attempt()
		saved.journal.test_interrupt_after = boundary
		check(saved.journal.resolve(saved.study.question_bank[0], false, false, -1).has("error"), "Interrupt miss at " + boundary)
		var restored := setup(path)
		restored.study.load_progress()
		restored.ship.load_progress()
		check(restored.journal.recover(), "Recover miss at " + boundary)
		check(restored.ship.state.coins == 35 and restored.ship.state.hull == 2 and restored.ship.state.answer_streak == 0, "One durable penalty at " + boundary)
		check(restored.journal.recover() and restored.ship.state.coins == 35, "Repeated recovery cannot charge penalty twice")
	# Exercise the actual shared visuals and ratio on requested screen sizes.
	for dimensions in [Vector2i(1440,900), Vector2i(390,844), Vector2i(844,390), Vector2i(360,640)]:
		root.size = dimensions
		var game = MainScene.instantiate()
		game.test_mode = true
		root.add_child(game)
		for frame in range(8): await process_frame
		game.set_process(false)
		game.arena.set_process(false)
		check(game._ratio_caption.text.contains("NO ANSWERS"), "Empty ratio is honest")
		game.start_run()
		for frame in range(8): await process_frame
		game.arena.set_process(false)
		game.arena.question_requested.emit()
		game.submit_choice(int(game.current_question.answer))
		check(game._ratio_caption.text.contains("RIGHT 1 : 0 WRONG") and game._ratio_bar.value == 100, "Correct answer updates top meter")
		for rank in [3,6,10,16,24,41,45,55,70,90,120]:
			game.progression.state.rank = rank
			game._update_hud()
			game._show_ready()
			for frame in range(5): await process_frame
			check(game.arena._ship == Evolution.texture(rank), "Live arena replaces its physical hull")
			check(game._hangar_view.rank == rank, "Hangar uses the same evolution rank")
			if rank == 41: check(game._evolution_label.text.contains("NEXT EVOLUTION: RANK 45"), "Rank 41 Home has a future evolution instead of a max label")
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(game._ratio_row.get_global_rect()), "Ratio fits screen at " + str(dimensions))
		check(not game._ratio_row.get_global_rect().intersects(game._body.get_global_rect()), "Top ratio never overlaps gameplay")
		game.queue_free()
		await process_frame
	print("Ship evolutions: ", checks, " checks; ", failures.size(), " failures")
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)

func _test_rank_41() -> void:
	var path := "user://rank41-%d" % Time.get_ticks_usec()
	var c := setup(path)
	c.ship.state.rank = 41
	c.ship.state.total_xp = 23500
	c.ship.state.coins = 987
	c.ship.state.hull = 2
	c.ship.state.pending_upgrades = 2
	c.ship.state.upgrades.power = 8
	var before: Dictionary = c.ship.state.duplicate(true)
	check(c.ship.save_progress(), "Actual Rank 41 save commits")
	var restored := setup(path)
	restored.ship.load_progress()
	check(restored.ship.state == JSON.parse_string(JSON.stringify(before)), "Rank 41 XP, wallet, hull and upgrades survive without migration loss")
	check(Evolution.stage(41) == 5 and Evolution.next_rank(41) == 45, "Earned fifth hull stays while five additional evolutions remain ahead")
	var earned_texture := Evolution.texture(41)
	restored.ship._add_xp(1099)
	check(restored.ship.state.rank == 41, "Rank 41 retains its actual 1100-XP rank cost")
	restored.ship._add_xp(1)
	check(restored.ship.state.rank == 42 and Evolution.texture(42) == earned_texture, "An intermediate rank never changes or removes the earned hull")
	while int(restored.ship.state.rank) < 45:
		restored.ship._add_xp(restored.ship.get_xp_needed())
	check(Evolution.stage(45) == 6 and Evolution.texture(45) != earned_texture, "First veteran evolution physically replaces the Rank 41 hull")
	check(restored.ship.state.coins == 987 and restored.ship.state.upgrades.power == 8, "Evolution does not spend wallet or erase upgrades")
	check(Evolution.next_rank(45) == 55 and Evolution.next_rank(119) == 120, "Later mystery milestones stay available")
	var high_rank := int(restored.ship.state.rank)
	restored.ship._add_xp(200000)
	check(int(restored.ship.state.rank) > high_rank and restored.ship.state.xp < restored.ship.get_xp_needed(), "Ship Rank continues without a terminal branch")
