extends SceneTree

const CourseBank = preload("res://scripts/course_bank.gd")

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		printerr("Provide exactly one local question-bank JSON file after --.")
		quit(1)
		return
	var result: Dictionary = CourseBank.read_bank(arguments[0])
	if result.has("error"):
		printerr(String(result["error"]))
		quit(1)
		return
	print("Verified import structure: %d questions / %s" % [result["questions"].size(), result["title"]])
	quit(0)
