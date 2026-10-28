extends RefCounted
## Write-ahead bridge: one response is committed once to each independent save.
const Progression = preload("res://scripts/progression_model.gd")
var study: RefCounted
var progression: RefCounted
var persistence_enabled := true
var journal_path := "user://response-journal.json"
var warning := ""
var _entries: Dictionary = {}
# Fault injection used only by isolated persistence tests.
var test_interrupt_after := ""
var answer_metadata: Dictionary = {}

func _init(study_model: RefCounted, progression_model: RefCounted) -> void:
	study = study_model
	progression = progression_model

func resolve(question: Dictionary, correct: bool, assisted: bool, confidence: int, is_bonus: bool = false, timed_out: bool = false, counter: String = "independent") -> Dictionary:
	if not recover():
		return {"error": warning}
	var target: Dictionary = progression.state.bonus if is_bonus else progression.state.current
	if target.is_empty() or not target.has("id"):
		return {"error": "There is no active question encounter."}
	if question.get("id", "") != target.get("question", {}).get("id", ""):
		return {"error": "The response does not match the displayed question."}
	var stage := "first" if is_bonus or counter == "independent" else ("solution" if counter == "solution" else "guided")
	if stage == "guided": return {"error": "Answers are final; question retries are disabled."}
	var transaction_id := "%s/%s/%s" % [target.id, "bonus" if is_bonus else "core", stage]
	if progression.state.receipts.has(transaction_id) and study.response_receipts.has(transaction_id):
		return _public_result(progression.state.receipts[transaction_id])
	# A resolved prompt cannot be reinterpreted by submitting a different stage.
	if bool(target.get("response", {}).get("resolved", false)):
		return {"error": "This question is already resolved."}
	if stage != "first" and target.get("response", {}).is_empty():
		return {"error": "A guided resolution requires a recorded first response."}
	if is_bonus and target.get("status", "") != "started":
		return {"error": "This bonus is not accepting answers."}
	var input := {"target_id": target.id, "question": question.duplicate(true), "correct": correct, "assisted": assisted or stage != "first", "confidence": confidence, "is_bonus": is_bonus, "timed_out": timed_out, "counter": counter, "stage": stage, "timestamp": study._now()}
	if input.stage == "first": input.merge(answer_metadata)
	_entries[transaction_id] = input
	if not _save_journal():
		_entries.erase(transaction_id)
		return {"error": warning}
	if test_interrupt_after == "journal":
		warning = "Test interruption after journal commit."
		return {"error": warning}
	if not _commit(transaction_id, input):
		return {"error": warning}
	return _public_result(progression.state.receipts[transaction_id])

func resolve_solution() -> Dictionary:
	if progression.state.current.is_empty():
		return {"error": "There is no current encounter."}
	var response: Dictionary = progression.state.current.get("response", {})
	if bool(response.get("resolved", false)):
		return {"response": response.duplicate(true), "xp": 0, "correct": false}
	return resolve(progression.state.current.question, false, true, -1, false, false, "solution")

func recover() -> bool:
	if persistence_enabled:
		var loaded := _read_journal()
		if loaded.has("error"):
			warning = String(loaded.error)
			return false
		# Include memory entries after a failed commit; disk is the durable source.
		for key in loaded:
			_entries[key] = loaded[key]
	for transaction_id in _entries.keys():
		if not _commit(String(transaction_id), _entries[transaction_id]):
			return false
	warning = ""
	return true

func _commit(transaction_id: String, input: Dictionary) -> bool:
	var skipped: bool = input.stage == "skip"
	var result: Dictionary = {"correct": false, "assisted": false, "first_attempt": false, "skipped": true, "transaction_id": transaction_id} if skipped else study.record_transaction(transaction_id, input)
	if result.has("error"):
		warning = String(result.error)
		return false
	if not skipped and persistence_enabled and (not study.persistence_enabled or not study.save_progress()):
		warning = "Answer is waiting to be saved: " + String(study.progress_warning)
		return false
	if test_interrupt_after == "study":
		warning = "Test interruption after learning commit."
		return false
	var receipt: Dictionary
	if bool(input.get("is_revive", false)):
		receipt = progression.apply_revive_response(transaction_id, result, input)
	elif bool(input.get("is_boost", false)):
		receipt = progression.apply_boost_response(transaction_id, result, input)
	else:
		receipt = progression.apply_response(transaction_id, result, input)
	if receipt.has("error"):
		warning = String(receipt.error)
		return false
	if persistence_enabled and (not progression.persistence_enabled or not progression.save_progress()):
		warning = "Learning saved; ship reward is waiting to save: " + String(progression.progress_warning)
		return false
	if test_interrupt_after == "arcade":
		warning = "Test interruption after ship commit."
		return false
	_entries.erase(transaction_id)
	if not _save_journal():
		# Retain enough input to reconcile receipts on the next attempt.
		_entries[transaction_id] = input
		return false
	warning = ""
	return true

func _public_result(receipt: Dictionary) -> Dictionary:
	var result: Dictionary = receipt.get("result", {}).duplicate(true)
	result.response = receipt.get("response", {}).duplicate(true)
	result.xp = int(receipt.get("xp", 0))
	result.answer_reward = receipt.get("answer_reward", {}).duplicate(true)
	result.reward = receipt.get("reward", {}).duplicate(true)
	result.boost_complete = bool(receipt.get("boost_complete", false))
	result.boost_index = int(receipt.get("boost_index", 0))
	result.revive_earned = bool(receipt.get("revive_earned", false))
	result.revive_status = String(receipt.get("revive_status", ""))
	return result

func _save_journal() -> bool:
	if not persistence_enabled:
		return true
	var error: String = Progression.atomic_write(journal_path, {"version": 1, "entries": _entries})
	warning = "" if error.is_empty() else "Answer journal unsaved: " + error
	return error.is_empty()

func _read_journal() -> Dictionary:
	var found := false
	for candidate in [journal_path, journal_path + ".previous.json"]:
		if not FileAccess.file_exists(candidate):
			continue
		found = true
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null:
			continue
		var parser := JSON.new()
		var error := parser.parse(file.get_as_text())
		file.close()
		if error == OK and _valid_journal(parser.data):
			if candidate != journal_path and FileAccess.file_exists(journal_path):
				var preserved := journal_path + ".corrupt-%d" % Time.get_ticks_usec()
				if DirAccess.rename_absolute(ProjectSettings.globalize_path(journal_path), ProjectSettings.globalize_path(preserved)) != OK:
					return {"error": "Could not preserve the unreadable journal before recovery."}
			return parser.data.entries.duplicate(true)
	return {"error": "Unreadable answer journal was preserved. Recovery is needed before grading."} if found else {}

func _valid_journal(payload: Variant) -> bool:
	if not payload is Dictionary or payload.get("version", 0) != 1 or not payload.get("entries") is Dictionary:
		return false
	for key in payload.entries:
		var entry: Variant = payload.entries[key]
		if not key is String or not entry is Dictionary or not entry.get("question") is Dictionary:
			return false
		for required in ["target_id", "correct", "assisted", "confidence", "is_bonus", "timed_out", "stage", "timestamp"]:
			if not entry.has(required):
				return false
		if not Progression.valid_question(entry.question) or not entry.target_id is String or entry.stage not in ["first", "guided", "solution", "skip"]:
			return false
		for boolean_key in ["correct", "assisted", "is_bonus", "timed_out"]:
			if not entry[boolean_key] is bool:
				return false
		for category in ["is_boost", "is_revive"]:
			if entry.has(category) and not entry[category] is bool:
				return false
		if bool(entry.get("is_revive", false)) and (bool(entry.get("is_boost", false)) or not Progression._integer(entry.get("revive_submission")) or entry.stage not in ["first", "guided"]):
			return false
		if not Progression._integer(entry.timestamp) or not Progression._integer(entry.confidence, -1) or int(entry.confidence) > 2:
			return false
	return true

func skip_core() -> Dictionary:
	if not recover():
		return {"error": warning}
	var target: Dictionary = progression.state.current
	if target.is_empty():
		return {"error": "There is no encounter to skip."}
	var transaction_id := String(target.id) + "/core/skip"
	if progression.state.receipts.has(transaction_id):
		return _public_result(progression.state.receipts[transaction_id])
	if bool(target.get("response", {}).get("resolved", false)):
		return {"error": "This encounter response is already resolved."}
	var input := {"target_id": target.id, "question": target.question.duplicate(true), "correct": false, "assisted": false, "confidence": -1, "is_bonus": false, "timed_out": false, "counter": "solution", "stage": "skip", "timestamp": study._now()}
	if input.stage == "first": input.merge(answer_metadata)
	_entries[transaction_id] = input
	if not _save_journal():
		_entries.erase(transaction_id)
		return {"error": warning}
	if test_interrupt_after == "journal":
		warning = "Test interruption after skip journal commit."
		return {"error": warning}
	if not _commit(transaction_id, input):
		return {"error": warning}
	return _public_result(progression.state.receipts[transaction_id])

func resolve_boost(question: Dictionary, correct: bool, assisted: bool, confidence: int, counter: String = "independent") -> Dictionary:
	if not recover():
		return {"error": warning}
	var boost: Dictionary = progression.state.boost
	if boost.get("status", "") != "active":
		return {"error": "There is no active study boost."}
	var slot := int(boost.index)
	if slot >= boost.questions.size() or question.get("id", "") != boost.questions[slot].get("id", ""):
		return {"error": "This answer does not match the current boost question."}
	var stage := "first" if counter == "independent" else ("solution" if counter == "solution" else "guided")
	if stage == "guided": return {"error": "Answers are final; question retries are disabled."}
	var transaction_id := "%s/slot/%d/%s" % [boost.id, slot, stage]
	if progression.state.receipts.has(transaction_id) and study.response_receipts.has(transaction_id):
		return _public_result(progression.state.receipts[transaction_id])
	var response: Dictionary = boost.responses.get(str(slot), {})
	if stage != "first" and response.is_empty():
		return {"error": "A guided boost resolution requires an actual first response."}
	var input := {"target_id": boost.id, "slot": slot, "is_boost": true, "question": question.duplicate(true), "correct": correct, "assisted": assisted or stage != "first", "confidence": confidence, "is_bonus": false, "timed_out": false, "counter": counter, "stage": stage, "timestamp": study._now()}
	if input.stage == "first": input.merge(answer_metadata)
	_entries[transaction_id] = input
	if not _save_journal():
		_entries.erase(transaction_id)
		return {"error": warning}
	if test_interrupt_after == "journal":
		warning = "Test interruption after boost journal commit."
		return {"error": warning}
	if not _commit(transaction_id, input):
		return {"error": warning}
	return _public_result(progression.state.receipts[transaction_id])

func resolve_revive(question: Dictionary, correct: bool, assisted: bool, confidence: int) -> Dictionary:
	if not recover():
		return {"error": warning}
	var revive: Dictionary = progression.state.current.get("revive", {})
	if revive.is_empty() or question.get("id", "") != revive.get("question", {}).get("id", ""):
		return {"error": "This answer does not match the saved revive question."}
	var submission := int(revive.submission)
	if submission > 0: return {"error": "The revive question has already been answered."}
	var transaction_id := "%s/answer/%d" % [revive.id, submission]
	if progression.state.receipts.has(transaction_id) and study.response_receipts.has(transaction_id):
		return _public_result(progression.state.receipts[transaction_id])
	if revive.get("status", "") != "active" or progression.state.current.get("attempt_status", "") != "defeated" or bool(progression.state.current.get("revive_used", false)):
		return {"error": "The revive is not accepting another response."}
	var input := {"target_id": revive.id, "is_revive": true, "revive_submission": submission, "question": question.duplicate(true), "correct": correct, "assisted": assisted or bool(revive.get("hint_used", false)) or submission > 0, "confidence": confidence, "is_bonus": false, "timed_out": false, "counter": "independent" if submission == 0 else "assisted", "stage": "first" if submission == 0 else "guided", "timestamp": study._now()}
	if input.stage == "first": input.merge(answer_metadata)
	_entries[transaction_id] = input
	if not _save_journal():
		_entries.erase(transaction_id)
		return {"error": warning}
	if test_interrupt_after == "journal":
		warning = "Test interruption after revive journal commit."
		return {"error": warning}
	if not _commit(transaction_id, input):
		return {"error": warning}
	return _public_result(progression.state.receipts[transaction_id])
