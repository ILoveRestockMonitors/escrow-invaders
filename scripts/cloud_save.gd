extends RefCounted
## One shared save on the home lab, so every device continues the same game.
## The server keeps the files; each device remembers the revision it last matched.

const FILES := ["arcade-progress.json", "response-journal.json", "study-progress.json"]
## Save folder; tests point this elsewhere so they never touch a real save.
static var root := "user://"

## Set by every successful local save write; cleared once uploaded.
static var dirty := false

static func _parse(text: String) -> Variant:
	if text.is_empty():
		return null
	var parser := JSON.new()
	return parser.data if parser.parse(text) == OK else null

static func mark_dirty() -> void:
	dirty = true

static func read_state() -> Dictionary:
	var state := {"device_id": "", "revision": 0, "hash": ""}
	if FileAccess.file_exists(root + "cloud-sync.json"):
		var file := FileAccess.open(root + "cloud-sync.json", FileAccess.READ)
		if file != null:
			var parsed: Variant = _parse(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				state.device_id = String(parsed.get("device_id", ""))
				state.revision = int(parsed.get("revision", 0))
				state.hash = String(parsed.get("hash", ""))
	if state.device_id.is_empty():
		state.device_id = "%x%x" % [int(Time.get_unix_time_from_system() * 1000.0), randi()]
	return state

static func write_state(state: Dictionary) -> void:
	var file := FileAccess.open(root + "cloud-sync.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(state))
		file.close()

static func local_files() -> Dictionary:
	var files := {}
	for name in FILES:
		var path: String = root + name
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			if file != null:
				files[name] = file.get_as_text()
				file.close()
	return files

static func bundle_hash(files: Dictionary) -> String:
	var joined := ""
	for name in FILES:
		joined += name + "\n" + String(files.get(name, "")) + "\n"
	return joined.md5_text()

## [lifetime ship XP, recorded answers]; matches the server's ordering.
static func score(files: Dictionary) -> Array:
	var xp := 0
	var answers := 0
	var arcade: Variant = _parse(String(files.get("arcade-progress.json", "")))
	if arcade is Dictionary and arcade.get("state") is Dictionary:
		xp = int(arcade.state.get("total_xp", 0))
	var journal: Variant = _parse(String(files.get("response-journal.json", "")))
	if journal is Dictionary and journal.get("entries") is Dictionary:
		answers = journal.entries.size()
	return [xp, answers]

static func better(a: Array, b: Array) -> bool:
	return a[0] > b[0] if a[0] != b[0] else a[1] > b[1]

static func remote_files(remote: Dictionary) -> Dictionary:
	var files := {}
	if remote.get("files") is Dictionary:
		for name in FILES:
			if remote.files.get(name) is String:
				files[name] = remote.files[name]
	return files

## Returns "adopt", "push" or "none" for this device against the server copy.
static func decide(state: Dictionary, local: Dictionary, remote: Dictionary) -> String:
	var theirs := remote_files(remote)
	var revision := int(remote.get("revision", 0))
	if revision <= 0 or not theirs.has("arcade-progress.json"):
		return "push" if local.has("arcade-progress.json") else "none"
	if not local.has("arcade-progress.json"):
		return "adopt"
	var changed := bundle_hash(local) != String(state.hash)
	if revision == int(state.revision):
		return "push" if changed else "none"
	if not changed:
		return "adopt"
	# Both sides moved (or this device never synced): the one with more progress wins.
	return "push" if better(score(local), score(theirs)) else "adopt"

## Replaces local save files with the server copy. Each previous local file is kept as
## its .previous.json fallback and in cloud-sync-backup, so nothing is overwritten unrecoverably.
static func adopt(remote: Dictionary, state: Dictionary) -> String:
	var theirs := remote_files(remote)
	for name in FILES:
		if theirs.has(name) and _parse(theirs[name]) == null:
			return "Cloud save file %s is unreadable." % name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root + "cloud-sync-backup"))
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "")
	for name in FILES:
		var absolute := ProjectSettings.globalize_path(root + name)
		if FileAccess.file_exists(absolute):
			DirAccess.copy_absolute(absolute, ProjectSettings.globalize_path(root + "cloud-sync-backup" + "/" + stamp + "-" + name))
	for name in FILES:
		var absolute := ProjectSettings.globalize_path(root + name)
		if not theirs.has(name):
			# The shared save has no such file; move this device's copy aside so it is not mixed in.
			for suffix in ["", ".previous.json"]:
				if FileAccess.file_exists(absolute + suffix):
					DirAccess.rename_absolute(absolute + suffix, ProjectSettings.globalize_path(root + "cloud-sync-backup" + "/" + stamp + "-moved-" + name + suffix))
			continue
		var file := FileAccess.open(absolute + ".tmp", FileAccess.WRITE)
		if file == null:
			return "Could not write the cloud save."
		file.store_string(theirs[name])
		file.close()
		var backup := absolute + ".previous.json"
		if FileAccess.file_exists(absolute):
			if FileAccess.file_exists(backup):
				DirAccess.remove_absolute(backup)
			DirAccess.rename_absolute(absolute, backup)
		if DirAccess.rename_absolute(absolute + ".tmp", absolute) != OK:
			return "Could not commit the cloud save."
	state.revision = int(remote.revision)
	state.hash = bundle_hash(theirs)
	write_state(state)
	dirty = false
	return ""

static func push_body(state: Dictionary, local: Dictionary) -> String:
	return JSON.stringify({"base_revision": int(state.revision), "device_id": state.device_id, "files": local})
