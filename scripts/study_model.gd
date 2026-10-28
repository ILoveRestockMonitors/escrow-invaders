extends RefCounted
## Learning model with a validated course-bank loader and original math fallback.
## History contains only actual responses, keyed under `questions` and `concepts`.
## Core accuracy = independent correct first attempts / core first attempts.
## Bonus responses and retries never increase core accuracy or spaced mastery.
## Confidence: -1 = not supplied, 0 = guessing, 1 = leaning, 2 = sure.
## A mastery stage requires a subsequent independent success at least 24 hours
## later, on another day, and after its review due date. Stage 3 = mastered.

const DAY_SECONDS := 86400
const SCHEMA_VERSION := 1
const CourseBank = preload("res://scripts/course_bank.gd")
const CloudSave = preload("res://scripts/cloud_save.gd")
const REVIEW_INTERVALS := [DAY_SECONDS, DAY_SECONDS * 3, DAY_SECONDS * 7, DAY_SECONDS * 14]

var core_questions: Array[Dictionary] = []
var bonus_questions: Array[Dictionary] = []
var history: Dictionary = {"questions": {}, "concepts": {}}
var persistence_enabled := true
var save_path := "user://study-progress.json"
var progress_warning := ""
var bank_warning := ""
var sample_data := true
var bank_title := "Original practice math"
var bank_id := "sample-math"
var bank_source_url := ""
## Injectable for deterministic tests. A negative value uses the system clock.
var clock_override_unix: int = -1
var rng := RandomNumberGenerator.new()
var question_bank: Array[Dictionary] = []
var _bonus_bank: Array[Dictionary] = []
var _run_attempts: Dictionary = {}
var _stats: Dictionary = {}
var response_receipts: Dictionary = {}
var boost_sessions: Dictionary = {}
var revive_sessions: Dictionary = {}
var preferences: Dictionary = {"categories": [], "adaptive": true}
var session_seen: Array = []


func _init() -> void:
	rng.randomize()
	_build_question_bank()
	reset_run_stats()


func load_course_bank(path: String = "res://data/course-bank.json") -> bool:
	if not FileAccess.file_exists(path):
		return false
	var result: Dictionary = CourseBank.read_bank(path)
	if result.has("error"):
		bank_warning = "Course bank not loaded: " + String(result["error"])
		return false
	question_bank.assign(result["questions"])
	_bonus_bank.clear()
	for question in question_bank:
		if bool(question.get("bonus_eligible", false)):
			_bonus_bank.append(question)
	sample_data = false
	bank_title = String(result["title"])
	bank_id = String(result["bank_id"])
	bank_source_url = String(result["source_url"])
	bank_warning = ""
	return true


func start_run() -> void:
	reset_run_stats()
	session_seen.clear()
	core_questions.clear()
	bonus_questions.clear()
	var candidates: Array[Dictionary] = eligible_questions().duplicate(true)
	var used_concepts: Array[String] = []
	var used_ids: Array[String] = []
	for slot in range(5):
		var best_index := -1
		var best_score := -INF
		for index in range(candidates.size()):
			var question: Dictionary = candidates[index]
			var score: float = _question_priority(question)
			if String(question["concept"]) in used_concepts:
				score -= 1000.0
			if score > best_score:
				best_score = score
				best_index = index
		if best_index < 0:
			break
		var selected: Dictionary = candidates.pop_at(best_index)
		used_concepts.append(String(selected["concept"]))
		used_ids.append(String(selected["id"]))
		core_questions.append(_shuffle_choices(selected))
	# Bonus 1 uses a concept encountered in core 1 or 2; bonus 2 in core 1-4.
	# These are short transfer questions, never the same item as the core prompt.
	for encounter_count in [2, 4]:
		var familiar: Array[String] = []
		for index in range(mini(encounter_count, core_questions.size())):
			familiar.append(String(core_questions[index]["concept"]))
		var eligible: Array[Dictionary] = []
		for question in _bonus_bank:
			if not matches_preferences(question): continue
			if String(question["id"]) in used_ids:
				continue
			if String(question["concept"]) not in familiar:
				continue
			if not bonus_questions.is_empty() and question["id"] == bonus_questions[0].get("id", ""):
				continue
			eligible.append(question)
		if not eligible.is_empty():
			bonus_questions.append(_shuffle_choices(eligible[rng.randi_range(0, eligible.size() - 1)]))
		else:
			bonus_questions.append({})


func record_answer(question: Dictionary, correct: bool, assisted: bool, confidence: int, is_bonus: bool = false, timed_out: bool = false) -> Dictionary:
	var identifier := String(question.get("id", ""))
	var concept := String(question.get("concept", ""))
	if identifier.is_empty() or concept.is_empty():
		return {"error": "Question is missing an id or concept."}
	var attempt_key := ("bonus:" if is_bonus else "core:") + identifier
	var first_attempt := not _run_attempts.has(attempt_key)
	_run_attempts[attempt_key] = int(_run_attempts.get(attempt_key, 0)) + 1
	var effective_assistance := assisted or not first_attempt
	var answer_correct := correct and not timed_out
	var independently_correct := answer_correct and not effective_assistance
	var now := _now()
	var question_records: Dictionary = history.get("questions", {})
	var concept_records: Dictionary = history.get("concepts", {})
	var question_state: Dictionary = question_records.get(identifier, {}).duplicate(true)
	var concept_state: Dictionary = concept_records.get(concept, {}).duplicate(true)
	var old_stage := int(concept_state.get("mastery_stage", 0))
	var mastery_advanced := false
	question_state["last_seen_at"] = now
	question_state["concept"] = concept
	# -1 means the learner did not provide a confidence assessment.
	question_state["last_confidence"] = clampi(confidence, -1, 2)
	if is_bonus:
		question_state["bonus_attempts"] = int(question_state.get("bonus_attempts", 0)) + 1
		if answer_correct:
			question_state["bonus_correct"] = int(question_state.get("bonus_correct", 0)) + 1
		if first_attempt:
			_stats["bonus_answered"] += 1
			if answer_correct:
				_stats["bonus_correct"] += 1
			if timed_out:
				_stats["bonus_timed_out"] += 1
	else:
		question_state["core_attempts"] = int(question_state.get("core_attempts", 0)) + 1
		question_state["last_correct"] = answer_correct
		question_state["last_assisted"] = effective_assistance
		question_state["needs_review"] = not independently_correct
		concept_state["last_seen_at"] = now
		concept_state["last_confidence"] = clampi(confidence, -1, 2)
		# Only the first answer represents a fresh retrieval attempt.
		if first_attempt:
			_stats["core_answered"] += 1
			concept_state["core_attempts"] = int(concept_state.get("core_attempts", 0)) + 1
			if independently_correct:
				_stats["core_correct"] += 1
				_stats["independent_correct"] += 1
				concept_state["independent_correct"] = int(concept_state.get("independent_correct", 0)) + 1
			if effective_assistance:
				_stats["core_assisted"] += 1
			var run_concepts: Dictionary = _stats["concepts"]
			var concept_summary: Dictionary = run_concepts.get(concept, {"answered": 0, "independent_correct": 0, "assisted": 0})
			concept_summary["answered"] += 1
			if independently_correct:
				concept_summary["independent_correct"] += 1
			if effective_assistance:
				concept_summary["assisted"] += 1
			run_concepts[concept] = concept_summary
			_stats["concepts"] = run_concepts
		if independently_correct:
			var last_independent := int(concept_state.get("last_independent_at", 0))
			var last_remediation := int(concept_state.get("last_remediation_at", 0))
			var last_learning_exposure := maxi(last_independent, last_remediation)
			var success_count := int(concept_state.get("spaced_successes", 0))
			var first_success := success_count == 0
			var spaced_success := now - last_learning_exposure >= DAY_SECONDS and _day_key(now) != _day_key(last_learning_exposure) and now >= int(concept_state.get("due_at", 0))
			if first_success or spaced_success:
				success_count += 1
				var new_stage := mini(3, maxi(0, success_count - 1))
				concept_state["spaced_successes"] = success_count
				concept_state["last_independent_at"] = now
				concept_state["mastery_stage"] = new_stage
				concept_state["due_at"] = now + int(REVIEW_INTERVALS[new_stage])
				concept_state["needs_review"] = false
				mastery_advanced = new_stage > old_stage
				if mastery_advanced:
					_stats["mastery_advances"] += 1
		else:
			# An incorrect or assisted core answer returns next session.
			# Repeating a revealed answer cannot clear this review requirement.
			concept_state["needs_review"] = true
			concept_state["due_at"] = now
			# Remediation exposes the rule again. A new run on the same day
			# must not turn that freshly taught answer into delayed mastery.
			concept_state["last_remediation_at"] = now
			question_state["needs_review"] = true
		concept_records[concept] = concept_state
	question_records[identifier] = question_state
	history["questions"] = question_records
	history["concepts"] = concept_records
	if persistence_enabled:
		save_progress()
	return {
		"correct": answer_correct,
		"assisted": effective_assistance,
		"confidence": clampi(confidence, -1, 2),
		"is_bonus": is_bonus,
		"timed_out": timed_out,
		"first_attempt": first_attempt,
		"independently_correct": independently_correct,
		"mastery_advanced": mastery_advanced,
		"mastery_stage": int(concept_state.get("mastery_stage", 0)),
		"review_due": bool(concept_state.get("needs_review", false)),
		"explanation": String(question.get("explanation", "")),
	}


func get_summary() -> Dictionary:
	var summary: Dictionary = _stats.duplicate(true)
	var answered := int(summary["core_answered"])
	summary["core_accuracy"] = float(summary["core_correct"]) / float(answered) if answered > 0 else 0.0
	summary["sample_data"] = sample_data
	summary["bank_id"] = bank_id
	return summary


func reset_run_stats() -> void:
	_run_attempts.clear()
	_stats = {
		"core_answered": 0, "core_correct": 0, "core_assisted": 0,
		"bonus_answered": 0, "bonus_correct": 0, "bonus_timed_out": 0,
		"independent_correct": 0, "mastery_advances": 0, "concepts": {},
	}


func load_progress() -> void:
	if not persistence_enabled:
		return
	var found := false
	for path in [save_path, save_path + ".previous.json"]:
		if not FileAccess.file_exists(path):
			continue
		found = true
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parser := JSON.new()
		var parse_error := parser.parse(file.get_as_text())
		file.close()
		if parse_error != OK or not _valid_progress(parser.data):
			continue
		var payload: Dictionary = parser.data
		history = payload.history.duplicate(true)
		preferences = payload.get("preferences", {"categories": [], "adaptive": true}).duplicate(true)
		session_seen = payload.get("session_seen", []).duplicate()
		if eligible_questions().size() < 5: preferences.categories = []
		response_receipts = payload.get("response_receipts", {}).duplicate(true)
		boost_sessions = payload.get("boost_sessions", {}).duplicate(true)
		revive_sessions = payload.get("revive_sessions", {}).duplicate(true)
		var session: Dictionary = payload.get("session", {})
		if not session.is_empty():
			_run_attempts = session.get("attempts", {}).duplicate(true)
			_stats = session.get("stats", _stats).duplicate(true)
		if path != save_path and FileAccess.file_exists(save_path):
			var preserved := save_path + ".corrupt-%d" % Time.get_ticks_usec()
			if DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(preserved)) != OK:
				persistence_enabled = false
		progress_warning = "Recovered the previous valid learning save." if path != save_path else ""
		return
	if found:
		persistence_enabled = false
		progress_warning = "Unreadable learning progress was left untouched. Saving is disabled until it can be recovered."


func save_progress() -> bool:
	if not persistence_enabled:
		return false
	var absolute_path := ProjectSettings.globalize_path(save_path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		progress_warning = "Could not create the progress folder."
		return false
	var temporary_path := absolute_path + ".tmp"
	var backup_path := absolute_path + ".previous.json"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		progress_warning = "Could not write progress. Your previous save is untouched."
		return false
	file.store_string(JSON.stringify({"version": SCHEMA_VERSION, "saved_at": _now(), "history": history, "response_receipts": response_receipts, "boost_sessions": boost_sessions, "revive_sessions": revive_sessions, "preferences": preferences, "session_seen": session_seen, "session": {"attempts": _run_attempts, "stats": _stats}}, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		progress_warning = "Progress write failed. Your previous save is untouched."
		return false
	var had_previous := FileAccess.file_exists(absolute_path)
	if had_previous:
		if FileAccess.file_exists(backup_path):
			var remove_error := DirAccess.remove_absolute(backup_path)
			if remove_error != OK:
				progress_warning = "Could not rotate the progress backup. Your current save is untouched."
				return false
		var backup_error := DirAccess.rename_absolute(absolute_path, backup_path)
		if backup_error != OK:
			progress_warning = "Could not back up progress. Your current save is untouched."
			return false
	var commit_error := DirAccess.rename_absolute(temporary_path, absolute_path)
	if commit_error != OK:
		if had_previous:
			DirAccess.rename_absolute(backup_path, absolute_path)
		progress_warning = "Could not finish saving progress; the previous save was retained."
		return false
	progress_warning = ""
	CloudSave.mark_dirty()
	return true


func _valid_progress(payload: Variant) -> bool:
	if not payload is Dictionary:
		return false
	var version_value: Variant = payload.get("version", -1)
	if not (version_value is int or version_value is float) or float(version_value) != float(SCHEMA_VERSION):
		return false
	if payload.has("preferences"):
		var prefs: Variant = payload.preferences
		if not prefs is Dictionary or not prefs.get("categories") is Array or not prefs.get("adaptive") is bool: return false
		for category in prefs.categories:
			if not category is String: return false
	if payload.has("session_seen"):
		if not payload.session_seen is Array: return false
		for identifier in payload.session_seen:
			if not identifier is String: return false
	var candidate: Variant = payload.get("history")
	if not candidate is Dictionary:
		return false
	if not candidate.get("questions") is Dictionary or not candidate.get("concepts") is Dictionary:
		return false
	for collection in [candidate["questions"], candidate["concepts"]]:
		for key in collection:
			if not key is String or not collection[key] is Dictionary:
				return false
			var state: Dictionary = collection[key]
			for numeric_key in ["last_seen_at", "last_confidence", "bonus_attempts", "bonus_correct", "core_attempts", "independent_correct", "mastery_stage", "last_independent_at", "last_remediation_at", "spaced_successes", "due_at"]:
				if state.has(numeric_key):
					if not (state[numeric_key] is int or state[numeric_key] is float):
						return false
					var value := float(state[numeric_key])
					var minimum := -1.0 if numeric_key == "last_confidence" else 0.0
					if not is_finite(value) or value < minimum or value != floor(value):
						return false
			if int(state.get("mastery_stage", 0)) > 3 or int(state.get("last_confidence", 0)) > 2:
				return false
			for bool_key in ["last_correct", "last_assisted", "needs_review"]:
				if state.has(bool_key) and not state[bool_key] is bool:
					return false
	if payload.has("response_receipts"):
		if not payload.response_receipts is Dictionary:
			return false
		for transaction in payload.response_receipts:
			if not transaction is String or not payload.response_receipts[transaction] is Dictionary:
				return false
	if payload.has("boost_sessions"):
		if not payload.boost_sessions is Dictionary:
			return false
		for boost_id in payload.boost_sessions:
			var boost: Variant = payload.boost_sessions[boost_id]
			if not boost_id is String or not _valid_session(boost):
				return false
	if payload.has("revive_sessions"):
		if not payload.revive_sessions is Dictionary:
			return false
		for revive_id in payload.revive_sessions:
			if not revive_id is String or not _valid_session(payload.revive_sessions[revive_id]):
				return false
	if payload.has("session"):
		if not payload.session is Dictionary:
			return false
		var session: Dictionary = payload.session
		if not session.get("attempts") is Dictionary or not session.get("stats") is Dictionary:
			return false
		for key in ["core_answered", "core_correct", "core_assisted", "bonus_answered", "bonus_correct", "bonus_timed_out", "independent_correct", "mastery_advances"]:
			var value: Variant = session.stats.get(key)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0 or float(value) != floor(float(value)):
				return false
		if not session.stats.get("concepts") is Dictionary:
			return false
	return true


func record_transaction(transaction_id: String, input: Dictionary) -> Dictionary:
	if response_receipts.has(transaction_id):
		return response_receipts[transaction_id].duplicate(true)
	var result: Dictionary
	if input.get("stage", "") == "solution":
		# Reading a solution is remediation exposure, not a submitted response.
		var question: Dictionary = input.question
		var identifier := String(question.id)
		var concept := String(question.concept)
		var now := int(input.timestamp)
		var question_state: Dictionary = history.questions.get(identifier, {}).duplicate(true)
		var concept_state: Dictionary = history.concepts.get(concept, {}).duplicate(true)
		question_state.last_seen_at = now
		question_state.needs_review = true
		concept_state.last_seen_at = now
		concept_state.last_remediation_at = now
		concept_state.due_at = now
		concept_state.needs_review = true
		history.questions[identifier] = question_state
		history.concepts[concept] = concept_state
		result = {"correct": false, "assisted": true, "first_attempt": false, "viewed_solution": true, "mastery_advanced": false, "is_bonus": false, "explanation": String(input.question.get("explanation", ""))}
	else:
		var was_persistent := persistence_enabled
		var prior_clock := clock_override_unix
		persistence_enabled = false
		clock_override_unix = int(input.timestamp)
		var is_boost := bool(input.get("is_boost", false))
		var is_revive := bool(input.get("is_revive", false))
		var supplemental := is_boost or is_revive
		var sessions: Dictionary = revive_sessions if is_revive else boost_sessions
		var main_attempts: Dictionary = _run_attempts
		var main_stats: Dictionary = _stats
		if supplemental:
			var session_id := String(input.target_id)
			if sessions.has(session_id):
				_run_attempts = sessions[session_id].attempts.duplicate(true)
				_stats = sessions[session_id].stats.duplicate(true)
			else:
				_run_attempts = {}
				_stats = {}
				reset_run_stats()
		result = record_answer(input.question, bool(input.correct), bool(input.assisted), int(input.confidence), bool(input.is_bonus), bool(input.timed_out))
		if supplemental:
			sessions[String(input.target_id)] = {"attempts": _run_attempts.duplicate(true), "stats": _stats.duplicate(true)}
			_run_attempts = main_attempts
			_stats = main_stats
			result.is_boost = is_boost
			result.is_revive = is_revive
		clock_override_unix = prior_clock
		persistence_enabled = was_persistent
	if result.has("error"):
		return result

	if input.get("stage", "") == "first":
		var question: Dictionary = input.question
		result.merge({"bank_id": bank_id, "question_id": question.id, "concept": question.concept, "category": category_for(question), "prompt": question.prompt, "choices": question.choices.duplicate(), "answer": question.answer, "selected_index": int(input.get("selected_index", -1)), "context": "revive" if input.get("is_revive", false) else ("study reward" if input.get("is_boost", false) else ("bonus" if input.get("is_bonus", false) else "battle"))})
		if input.has("elapsed_seconds"): result.elapsed_seconds = float(input.elapsed_seconds)
		if question.id not in session_seen: session_seen.append(question.id)
	result["transaction_id"] = transaction_id
	result["recorded_at"] = int(input.timestamp)
	response_receipts[transaction_id] = result.duplicate(true)
	return result


func select_next_question(excluded_ids: Array = []) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	for question in eligible_questions():
		if question.id in excluded_ids or question.id in session_seen:
			continue
		var score := _question_priority(question)
		if score > best_score:
			best = question
			best_score = score
	return _shuffle_choices(best) if not best.is_empty() else {}


func select_bonus_question(familiar_concepts: Array, excluded_ids: Array = []) -> Dictionary:
	var eligible: Array[Dictionary] = []
	for question in _bonus_bank:
		if question.concept in familiar_concepts and question.id not in excluded_ids and question.id not in session_seen and matches_preferences(question):
			eligible.append(question)
	return _shuffle_choices(eligible[rng.randi_range(0, eligible.size() - 1)]) if not eligible.is_empty() else {}


func _question_priority(question: Dictionary) -> float:
	var concept_records: Dictionary = history.get("concepts", {})
	var question_records: Dictionary = history.get("questions", {})
	var concept_state: Dictionary = concept_records.get(question["concept"], {})
	var question_state: Dictionary = question_records.get(question["id"], {})
	var score := rng.randf_range(0.0, 20.0)
	if not preferences.adaptive: return score
	if question_state.is_empty():
		score += 120.0
	elif _now() - int(question_state.get("last_seen_at", 0)) < DAY_SECONDS:
		score -= 1000.0
	if bool(concept_state.get("needs_review", false)):
		score += 350.0
	if bool(question_state.get("needs_review", false)):
		score += 350.0
	var due_at := int(concept_state.get("due_at", 0))
	if due_at > 0 and due_at <= _now():
		score += 300.0
	var attempts := int(concept_state.get("core_attempts", 0))
	if attempts > 0:
		var correct_count := int(concept_state.get("independent_correct", 0))
		score += (1.0 - float(correct_count) / float(attempts)) * 150.0
	# New or struggling learners get the one-step example before harder transfer.
	var target_level := 2 if int(concept_state.get("spaced_successes", 0)) >= 2 and not bool(concept_state.get("needs_review", false)) else 1
	if int(question.get("level", 1)) == target_level:
		score += 35.0
	return score


func _shuffle_choices(question: Dictionary) -> Dictionary:
	var shuffled: Dictionary = question.duplicate(true)
	if not bool(question.get("shuffle_choices", true)):
		return shuffled
	var original_choices: Array = question["choices"]
	var right_answer := String(original_choices[int(question["answer"])])
	var unique_choices: Array[String] = []
	for choice in original_choices:
		if String(choice) not in unique_choices:
			unique_choices.append(String(choice))
	for index in range(unique_choices.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var temporary: String = unique_choices[index]
		unique_choices[index] = unique_choices[other]
		unique_choices[other] = temporary
	shuffled["choices"] = unique_choices
	shuffled["answer"] = unique_choices.find(right_answer)
	return shuffled


func _now() -> int:
	return clock_override_unix if clock_override_unix >= 0 else int(Time.get_unix_time_from_system())


func _day_key(timestamp: int) -> int:
	var offset_seconds := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return int(floor(float(timestamp + offset_seconds) / float(DAY_SECONDS)))


func _q(identifier: String, concept: String, prompt: String, choices: Array[String], answer: int, numeric_answer: float, unit: String, explanation: String, hint: String, level: int = 1) -> Dictionary:
	return {
		"id": identifier, "concept": concept, "prompt": prompt,
		"choices": choices, "answer": answer, "explanation": explanation,
		"hint": hint, "level": level, "sample": true,
		"numeric_answer": numeric_answer, "answer_text": str(int(numeric_answer)),
		"numeric_unit": unit,
	}


func _build_question_bank() -> void:
	# All rates are hypothetical values supplied in each question.
	question_bank = [
		_q("commission_01", "commission", "In this made-up sale, the price is $200,000 and the total commission is 3%. What is the total commission?", ["$6,000", "$600", "$60,000", "$3,000"], 0, 6000, "dollars", "$200,000 × 0.03 = $6,000. This is the total before any split.", "Convert 3% to 0.03, then multiply by the sale price."),
		_q("commission_02", "commission", "A practice sale is $350,000. With a hypothetical total commission of 2%, how many dollars is that?", ["$7,000", "$700", "$17,500", "$3,500"], 0, 7000, "dollars", "$350,000 × 0.02 = $7,000.", "One percent is $3,500. Find two percent."),
		_q("commission_03", "commission", "A hypothetical $480,000 sale has a 2.5% total commission. What is the total?", ["$12,000", "$1,200", "$24,000", "$9,600"], 0, 12000, "dollars", "$480,000 × 0.025 = $12,000.", "2.5% is 0.025 as a decimal.", 2),
		_q("commission_04", "commission", "A $10,000 commission is split equally between two fictional offices. How much does each office receive?", ["$5,000", "$2,500", "$10,000", "$20,000"], 0, 5000, "dollars", "$10,000 ÷ 2 = $5,000 per office.", "An equal split between two means divide by two."),
		_q("commission_05", "commission", "For a practice deal, an agent receives 60% of an $8,000 commission. What is the agent's share?", ["$4,800", "$3,200", "$800", "$6,000"], 0, 4800, "dollars", "$8,000 × 0.60 = $4,800.", "Find six tenths of $8,000.", 2),
		_q("area_01", "lot_area", "A rectangular lot is 40 feet wide and 60 feet long. What is its area in square feet?", ["2,400 sq ft", "200 sq ft", "100 sq ft", "24,000 sq ft"], 0, 2400, "square feet", "40 × 60 = 2,400 square feet. Area uses width × length.", "Multiply the two side lengths. Adding would not give area."),
		_q("area_02", "lot_area", "A rectangular yard measures 25 feet by 80 feet. How many square feet does it cover?", ["2,000 sq ft", "210 sq ft", "105 sq ft", "20,000 sq ft"], 0, 2000, "square feet", "25 × 80 = 2,000 square feet.", "A rectangle's area is length times width."),
		_q("area_03", "lot_area", "A rectangular room measures 12 feet by 15 feet. What is the floor area?", ["180 sq ft", "54 sq ft", "27 sq ft", "360 sq ft"], 0, 180, "square feet", "12 × 15 = 180 square feet.", "Find 12 groups of 15."),
		_q("area_04", "lot_area", "A rectangular lot has an area of 3,600 square feet and a width of 40 feet. How long is it?", ["90 feet", "80 feet", "144 feet", "3,560 feet"], 0, 90, "feet", "3,600 ÷ 40 = 90 feet. Divide area by width to recover length.", "Area = width × length. Reverse that multiplication.", 2),
		_q("area_05", "lot_area", "Two separate rectangular garden sections each measure 20 feet by 30 feet. What is their combined area?", ["1,200 sq ft", "600 sq ft", "100 sq ft", "2,400 sq ft"], 0, 1200, "square feet", "Each section is 20 × 30 = 600 square feet; two sections total 1,200.", "Find one section's area, then double it.", 2),
		_q("down_01", "down_payment", "A fictional home costs $300,000. What is a 10% down payment, ignoring all other costs?", ["$30,000", "$3,000", "$270,000", "$10,000"], 0, 30000, "dollars", "$300,000 × 0.10 = $30,000.", "Ten percent is one tenth of the price."),
		_q("down_02", "down_payment", "For a practice purchase of $250,000, the down payment is 20%. How much is the down payment?", ["$50,000", "$25,000", "$5,000", "$200,000"], 0, 50000, "dollars", "$250,000 × 0.20 = $50,000.", "Twenty percent is one fifth."),
		_q("down_03", "down_payment", "A fictional buyer puts 5% down on a $400,000 price. How many dollars is the down payment?", ["$20,000", "$2,000", "$40,000", "$380,000"], 0, 20000, "dollars", "$400,000 × 0.05 = $20,000.", "Find 10% first, then halve it."),
		_q("down_04", "down_payment", "A practice purchase costs $320,000 and the buyer pays $64,000 down. What percent of the price is paid down?", ["20%", "5%", "25%", "80%"], 0, 20, "percent", "$64,000 ÷ $320,000 × 100 = 20%.", "Divide the down payment by the full price, then multiply by 100.", 2),
		_q("down_05", "down_payment", "Ignoring fees, a fictional $200,000 purchase has a 15% down payment. How much of the price remains after the down payment?", ["$170,000", "$30,000", "$185,000", "$150,000"], 0, 170000, "dollars", "15% of $200,000 is $30,000; $200,000 − $30,000 = $170,000.", "Subtract the down payment from the full price.", 2),
		_q("rent_01", "annual_rent", "A fictional unit rents for $1,500 per month for all 12 months. What is the year's gross rent, before expenses?", ["$18,000", "$15,000", "$1,800", "$16,500"], 0, 18000, "dollars", "$1,500 × 12 = $18,000 gross annual rent.", "There are 12 monthly payments in a full year."),
		_q("rent_02", "annual_rent", "A unit receives $2,000 rent each month for 12 months. What is the total rent received?", ["$24,000", "$20,000", "$2,400", "$22,000"], 0, 24000, "dollars", "$2,000 × 12 = $24,000.", "Multiply the monthly amount by 12."),
		_q("rent_03", "annual_rent", "A practice unit receives $21,600 in rent across 12 equal monthly payments. What is each payment?", ["$1,800", "$2,160", "$180", "$2,400"], 0, 1800, "dollars", "$21,600 ÷ 12 = $1,800 per month.", "Divide the annual amount by the number of months.", 2),
		_q("rent_04", "annual_rent", "A fictional unit rents for $1,200 per month but is occupied for only 10 months. How much rent is actually received?", ["$12,000", "$14,400", "$10,000", "$1,200"], 0, 12000, "dollars", "$1,200 × 10 paid months = $12,000. The two empty months generate no rent.", "Use the 10 paid months, rather than automatically multiplying by 12.", 2),
		_q("rent_05", "annual_rent", "Two fictional units each collect $1,000 a month for 12 months. What is their combined gross annual rent?", ["$24,000", "$12,000", "$2,000", "$20,000"], 0, 24000, "dollars", "2 units × $1,000 × 12 months = $24,000.", "Work out one unit's annual rent, then double it.", 2),
		_q("percent_01", "price_change", "A fictional $100,000 asking price is reduced by 10%. How many dollars is the reduction?", ["$10,000", "$90,000", "$1,000", "$110,000"], 0, 10000, "dollars", "$100,000 × 0.10 = $10,000. The question asks for the reduction itself.", "Find 10% of the original price."),
		_q("percent_02", "price_change", "A practice price rises from $200,000 to $220,000. What is the percentage increase from the original price?", ["10%", "20%", "9%", "2%"], 0, 10, "percent", "The increase is $20,000. $20,000 ÷ $200,000 × 100 = 10%.", "Compare the increase with the original price.", 2),
		_q("percent_03", "price_change", "A fictional $150,000 price increases by 4%. How many dollars is the increase?", ["$6,000", "$600", "$4,000", "$156,000"], 0, 6000, "dollars", "$150,000 × 0.04 = $6,000.", "One percent is $1,500. Multiply that by four."),
		_q("percent_04", "price_change", "A practice $80,000 price is discounted by 5%. What is the new price after the discount?", ["$76,000", "$4,000", "$75,000", "$84,000"], 0, 76000, "dollars", "5% of $80,000 is $4,000. $80,000 − $4,000 = $76,000.", "Find the discount, then subtract it from the original price.", 2),
		_q("percent_05", "price_change", "A hypothetical $50,000 repair budget includes a 10% reserve within that total. How many dollars is the reserve?", ["$5,000", "$500", "$45,000", "$10,000"], 0, 5000, "dollars", "$50,000 × 0.10 = $5,000 reserved within the budget.", "One tenth of the total is the reserve."),
	]
	_bonus_bank = [
		_q("bonus_commission_01", "commission", "Quick recall: 1% of a $100,000 sale?", ["$1,000", "$100", "$10,000", "$500"], 0, 1000, "dollars", "$100,000 × 0.01 = $1,000.", "Divide by 100."),
		_q("bonus_commission_02", "commission", "An $8,000 commission split equally in two: each share?", ["$4,000", "$2,000", "$8,000", "$16,000"], 0, 4000, "dollars", "$8,000 ÷ 2 = $4,000.", "Halve the total."),
		_q("bonus_area_01", "lot_area", "A 10 ft × 20 ft patio: area?", ["200 sq ft", "60 sq ft", "30 sq ft", "2,000 sq ft"], 0, 200, "square feet", "10 × 20 = 200 square feet.", "Multiply length by width."),
		_q("bonus_area_02", "lot_area", "A 10 ft × 10 ft room: area?", ["100 sq ft", "20 sq ft", "40 sq ft", "1,000 sq ft"], 0, 100, "square feet", "10 × 10 = 100 square feet.", "Multiply the sides."),
		_q("bonus_down_01", "down_payment", "10% down on $100,000: how much down?", ["$10,000", "$1,000", "$90,000", "$100,000"], 0, 10000, "dollars", "$100,000 × 0.10 = $10,000.", "Find one tenth."),
		_q("bonus_down_02", "down_payment", "20% down on $100,000: how much down?", ["$20,000", "$2,000", "$80,000", "$10,000"], 0, 20000, "dollars", "$100,000 × 0.20 = $20,000.", "Double ten percent."),
		_q("bonus_rent_01", "annual_rent", "$1,000 monthly rent × 12 paid months?", ["$12,000", "$10,000", "$1,200", "$2,000"], 0, 12000, "dollars", "$1,000 × 12 = $12,000.", "Multiply the monthly payment by 12."),
		_q("bonus_rent_02", "annual_rent", "$12,000 yearly rent ÷ 12 equal months?", ["$1,000", "$100", "$12,000", "$1,200"], 0, 1000, "dollars", "$12,000 ÷ 12 = $1,000 per month.", "Divide the annual total by 12."),
		_q("bonus_percent_01", "price_change", "A $10,000 budget: what is 10%?", ["$1,000", "$100", "$9,000", "$10,000"], 0, 1000, "dollars", "$10,000 × 0.10 = $1,000.", "Find one tenth."),
		_q("bonus_percent_02", "price_change", "5% of a $100,000 price?", ["$5,000", "$500", "$50,000", "$95,000"], 0, 5000, "dollars", "$100,000 × 0.05 = $5,000.", "Halve ten percent."),
	]

func get_boost_summary(boost_id: String) -> Dictionary:
	if not boost_sessions.has(boost_id):
		return {}
	var result: Dictionary = boost_sessions[boost_id].stats.duplicate(true)
	result.core_accuracy = float(result.core_correct) / float(result.core_answered) if int(result.core_answered) > 0 else 0.0
	return result

func _valid_session(session: Variant) -> bool:
	if not session is Dictionary or not session.get("attempts") is Dictionary or not session.get("stats") is Dictionary:
		return false
	for key in session.attempts:
		var count: Variant = session.attempts[key]
		if not key is String or not (count is int or count is float) or not is_finite(float(count)) or float(count) < 0 or float(count) != floor(float(count)):
			return false
	for key in ["core_answered", "core_correct", "core_assisted", "bonus_answered", "bonus_correct", "bonus_timed_out", "independent_correct", "mastery_advances"]:
		var count: Variant = session.stats.get(key)
		if not (count is int or count is float) or not is_finite(float(count)) or float(count) < 0 or float(count) != floor(float(count)):
			return false
	if not session.stats.get("concepts") is Dictionary:
		return false
	for key in session.stats.concepts:
		if not key is String or not session.stats.concepts[key] is Dictionary:
			return false
	return true

func get_revive_summary(revive_id: String) -> Dictionary:
	if not revive_sessions.has(revive_id):
		return {}
	var result: Dictionary = revive_sessions[revive_id].stats.duplicate(true)
	result.core_accuracy = float(result.core_correct) / float(result.core_answered) if int(result.core_answered) > 0 else 0.0
	return result


func category_for(question: Dictionary) -> String:
	return String(question.get("category", "Practice math"))

func matches_preferences(question: Dictionary) -> bool:
	return preferences.categories.is_empty() or category_for(question) in preferences.categories

func available_categories() -> Dictionary:
	var categories: Dictionary = {}
	for question in question_bank:
		var category := category_for(question)
		categories[category] = int(categories.get(category, 0)) + 1
	return categories

func eligible_questions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for question in question_bank:
		if matches_preferences(question):
			result.append(question)
	return result

func set_preferences(categories: Array, adaptive: bool) -> bool:
	var available := available_categories()
	for category in categories:
		if not available.has(category): return false
	var previous := preferences.duplicate(true)
	preferences = {"categories": categories.duplicate(), "adaptive": adaptive}
	if eligible_questions().size() < 5:
		preferences = previous
		return false
	if persistence_enabled and not save_progress():
		preferences = previous
		return false
	return true

func get_learning_dashboard() -> Dictionary:
	var totals := {"answered": 0, "correct": 0, "wrong": 0, "independent": 0, "assisted": 0, "timeouts": 0, "seconds": 0.0, "timed_answers": 0}
	var categories: Dictionary = {}
	var topics: Dictionary = {}
	var contexts: Dictionary = {}
	var days: Dictionary = {}
	var recent: Array[Dictionary] = []
	for transaction_id in response_receipts:
		var result: Dictionary = response_receipts[transaction_id]
		if not bool(result.get("first_attempt", false)) or result.get("viewed_solution", false): continue
		# Old receipts retain their real result even when they lack question detail.
		if result.has("bank_id") and result.bank_id != bank_id: continue
		var category := String(result.get("category", "Earlier answers (topic unavailable)"))
		var concept := String(result.get("concept", "Earlier answers"))
		var context := String(result.get("context", "revive" if result.get("is_revive", false) else ("study reward" if result.get("is_boost", false) else ("bonus" if result.get("is_bonus", false) else "battle"))))
		var day := Time.get_date_string_from_unix_time(int(result.recorded_at)) if int(result.get("recorded_at", 0)) > 0 else "Date unavailable"
		totals.answered += 1
		totals.correct += 1 if result.get("correct", false) else 0
		totals.wrong += 0 if result.get("correct", false) else 1
		totals.independent += 1 if result.get("independently_correct", false) else 0
		totals.assisted += 1 if result.get("assisted", false) else 0
		totals.timeouts += 1 if result.get("timed_out", false) else 0
		if result.has("elapsed_seconds"):
			totals.seconds += float(result.elapsed_seconds)
			totals.timed_answers += 1
		_accumulate_result(categories, category, result)
		_accumulate_result(topics, concept, result)
		_accumulate_result(contexts, context, result)
		_accumulate_result(days, day, result)
		var entry := result.duplicate(true)
		entry.transaction_id = transaction_id
		recent.append(entry)
	recent.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("recorded_at", 0)) > int(b.get("recorded_at", 0)))
	var weaknesses: Array[Dictionary] = []
	for concept in topics:
		var row: Dictionary = topics[concept].duplicate(true)
		row.concept = concept
		row.accuracy = float(row.correct) / float(row.answered)
		if row.wrong > 0 or row.assisted > 0: weaknesses.append(row)
	weaknesses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.accuracy < b.accuracy if a.accuracy != b.accuracy else int(a.wrong) > int(b.wrong))
	return {"totals": totals, "categories": categories, "topics": topics, "contexts": contexts, "days": days, "recent": recent, "weaknesses": weaknesses}

func _accumulate_result(groups: Dictionary, key: String, result: Dictionary) -> void:
	var row: Dictionary = groups.get(key, {"answered": 0, "correct": 0, "wrong": 0, "independent": 0, "assisted": 0})
	row.answered += 1
	row.correct += 1 if result.get("correct", false) else 0
	row.wrong += 0 if result.get("correct", false) else 1
	row.independent += 1 if result.get("independently_correct", false) else 0
	row.assisted += 1 if result.get("assisted", false) else 0
	groups[key] = row
