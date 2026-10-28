extends SceneTree
const Progression = preload("res://scripts/progression_model.gd")
const Study = preload("res://scripts/study_model.gd")
const Journal = preload("res://scripts/response_journal.gd")
const CloudSave = preload("res://scripts/cloud_save.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	call_deferred("_run")

func device(name: String) -> String:
	var folder := ProjectSettings.globalize_path("res://.runtime/cloud-save-test/%s-%d/" % [name, Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder)
	return folder

func play(folder: String, xp: int) -> Progression:
	var ship := Progression.new()
	ship.save_path = folder + "arcade-progress.json"
	ship.load_progress()
	ship._add_xp(xp)
	ship.save_progress()
	var study := Study.new()
	study.save_path = folder + "study-progress.json"
	study.load_progress()
	study.save_progress()
	return ship

func remote_from(folder: String, revision: int) -> Dictionary:
	CloudSave.root = folder
	return {"revision": revision, "files": CloudSave.local_files()}

func _run() -> void:
	# A veteran PC save and a fresh phone save.
	var pc := device("pc")
	var pc_ship := play(pc, 60000)
	var veteran_rank := int(pc_ship.state.rank)
	check(veteran_rank > 40, "Fixture reaches a veteran ship rank")
	CloudSave.dirty = false
	play(pc, 0)
	check(CloudSave.dirty, "A successful local save marks the cloud copy out of date")
	var phone := device("phone")
	play(phone, 30)

	CloudSave.root = pc
	var pc_state := CloudSave.read_state()
	check(not String(pc_state.device_id).is_empty(), "Each device gets an identity")
	check(CloudSave.decide(pc_state, CloudSave.local_files(), {"revision": 0, "files": {}}) == "push", "First device uploads into an empty cloud")
	var server := remote_from(pc, 1)

	CloudSave.root = phone
	var phone_state := CloudSave.read_state()
	var phone_files := CloudSave.local_files()
	check(CloudSave.better(CloudSave.score(server.files), CloudSave.score(phone_files)), "Veteran save outranks the fresh save")
	check(CloudSave.decide(phone_state, phone_files, server) == "adopt", "Never-synced phone adopts the veteran cloud save instead of starting over")
	check(CloudSave.adopt(server, phone_state).is_empty(), "Adoption writes the shared save")
	var loaded := Progression.new()
	loaded.save_path = phone + "arcade-progress.json"
	loaded.load_progress()
	check(int(loaded.state.rank) == veteran_rank and loaded.progress_warning.is_empty(), "Phone loads the PC ship rank cleanly")
	var study := Study.new()
	study.save_path = phone + "study-progress.json"
	study.load_progress()
	check(study.persistence_enabled and study.progress_warning.is_empty(), "Phone loads the shared learning save")
	check(FileAccess.file_exists(phone + "arcade-progress.json.previous.json"), "The replaced phone save stays as its fallback")
	check(DirAccess.get_files_at(phone + "cloud-sync-backup").size() >= 2, "The replaced phone save is also copied aside")
	CloudSave.root = phone
	var after := CloudSave.read_state()
	check(int(after.revision) == 1 and CloudSave.decide(after, CloudSave.local_files(), server) == "none", "Adopted device is in sync")

	# A never-synced device that holds more progress than the cloud uploads instead.
	var small := device("small-cloud")
	play(small, 5)
	var small_cloud := remote_from(small, 1)
	CloudSave.root = pc
	check(CloudSave.decide(CloudSave.read_state(), CloudSave.local_files(), small_cloud) == "push", "A bigger never-synced save is not overwritten by a smaller cloud save")

	# Playing on the phone after syncing, then returning to a stale PC tab.
	play(phone, 500)
	CloudSave.root = phone
	check(CloudSave.decide(after, CloudSave.local_files(), server) == "push", "New phone progress uploads")
	var newer := remote_from(phone, 2)
	CloudSave.root = pc
	var synced_pc := {"device_id": "pc", "revision": 1, "hash": CloudSave.bundle_hash(server.files)}
	check(CloudSave.decide(synced_pc, CloudSave.local_files(), newer) == "adopt", "An unchanged PC picks up the phone's newer progress")
	check(CloudSave.decide(synced_pc, CloudSave.local_files(), server) == "none", "No action when nothing changed")

	# Unreadable cloud data never replaces a local save.
	CloudSave.root = phone
	var bad := {"revision": 9, "files": {"arcade-progress.json": "{broken"}}
	check(not CloudSave.adopt(bad, CloudSave.read_state()).is_empty(), "Corrupt cloud data is refused")
	loaded.load_progress()
	check(int(loaded.state.rank) > 1, "Local save survives a refused cloud copy")

	CloudSave.root = "user://"
	print("Cloud save: ", checks, " checks; ", failures.size(), " failures")
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
