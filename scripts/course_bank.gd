extends RefCounted
## Read-only validation/normalization of a locally collected official-answer bank.
## No networking and no inference of missing answers.

static func read_bank(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "Course bank has not been added yet."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "The course bank could not be opened."}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"error": "The course bank contains invalid JSON."}
	return validate(parser.data)


static func validate(payload: Variant) -> Dictionary:
	if not payload is Dictionary or payload.get("schema_version") != 1:
		return {"error": "Unsupported course-bank schema."}
	for field in ["bank_id", "title", "source_url"]:
		if not payload.get(field) is String or String(payload[field]).strip_edges().is_empty():
			return {"error": "Missing bank metadata: " + field}
	if not _web_url(String(payload["source_url"])):
		return {"error": "Bank source_url must identify the source website."}
	if not payload.get("questions") is Array or payload["questions"].size() < 5:
		return {"error": "At least five verified course questions are required."}
	var questions: Array[Dictionary] = []
	var ids: Dictionary = {}
	var seen_prompts: Dictionary = {}
	for index in range(payload["questions"].size()):
		var raw: Variant = payload["questions"][index]
		var prefix := "Question %d: " % (index + 1)
		if not raw is Dictionary:
			return {"error": prefix + "expected an object."}
		for field in ["id", "concept", "prompt", "source_url"]:
			if not raw.get(field) is String or String(raw[field]).strip_edges().is_empty():
				return {"error": prefix + "missing " + field}
		if not _web_url(String(raw["source_url"])):
			return {"error": prefix + "missing usable source provenance."}
		if not raw.get("answer_verified") is bool or raw["answer_verified"] != true:
			return {"error": prefix + "the answer has not been verified against the source."}
		if not raw.get("choices") is Array or raw["choices"].size() < 2 or raw["choices"].size() > 4:
			return {"error": prefix + "expected two to four choices."}
		var choices: Array[String] = []
		for choice in raw["choices"]:
			if not choice is String or choice.strip_edges().is_empty() or choice.strip_edges() in choices:
				return {"error": prefix + "empty or duplicate answer choices."}
			choices.append(choice.strip_edges())
		var answer: Variant = raw.get("answer")
		if not (answer is int or answer is float):
			return {"error": prefix + "answer must be a zero-based index."}
		if not is_finite(float(answer)) or float(answer) != floor(float(answer)) or answer < 0 or answer >= choices.size():
			return {"error": prefix + "answer is outside the choices."}
		var identifier := String(raw["id"]).strip_edges()
		var prompt := String(raw["prompt"]).strip_edges()
		var fingerprint := JSON.stringify([prompt.to_lower(), choices.map(func(choice: String): return choice.to_lower())])
		if ids.has(identifier) or seen_prompts.has(fingerprint):
			return {"error": prefix + "duplicate id or question wording; deduplicate the backup first."}
		ids[identifier] = true
		seen_prompts[fingerprint] = true
		var explanation: Variant = raw.get("explanation", "")
		var hint: Variant = raw.get("hint", "")
		if not explanation is String or not hint is String:
			return {"error": prefix + "explanation and hint must be text."}
		for flag in ["bonus_eligible", "shuffle_choices"]:
			if raw.has(flag) and not raw[flag] is bool:
				return {"error": prefix + flag + " must be true or false."}
		var question: Dictionary = raw.duplicate(true)
		question["source_question_id"] = raw.get("source_question_id", identifier)
		question["id"] = String(payload["bank_id"]) + ":" + identifier
		question["concept"] = String(payload["bank_id"]) + ":" + String(raw["concept"]).strip_edges()
		question["prompt"] = prompt
		question["choices"] = choices
		question["answer"] = int(answer)
		question["answer_text"] = choices[int(answer)]
		question["explanation"] = explanation.strip_edges() if not explanation.strip_edges().is_empty() else "The course marks '%s' as correct. No explanation was supplied by the source." % choices[int(answer)]
		question["hint"] = hint.strip_edges() if not hint.strip_edges().is_empty() else "Identify exactly what the question asks, then eliminate choices that contradict it. This is a general study prompt; the source supplied no hint."
		question["level"] = 1
		question["sample"] = false
		# Preserve letter references such as 'both A and B' in official choices.
		question["shuffle_choices"] = bool(raw.get("shuffle_choices", false))
		question["bonus_eligible"] = bool(raw.get("bonus_eligible", false))
		if raw.has("numeric_answer"):
			if not (raw["numeric_answer"] is float or raw["numeric_answer"] is int) or not is_finite(float(raw["numeric_answer"])):
				return {"error": prefix + "numeric_answer must be a finite number."}
		questions.append(question)
	return {"questions": questions, "bank_id": payload["bank_id"], "title": payload["title"], "source_url": payload["source_url"]}


static func _web_url(value: String) -> bool:
	return value.begins_with("https://") or value.begins_with("http://")
