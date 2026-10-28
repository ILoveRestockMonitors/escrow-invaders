extends SceneTree
func _initialize() -> void:
	var image := Image.new()
	var result := image.load_svg_from_string(FileAccess.get_file_as_string("res://web/app-icon.svg"))
	if result == OK:
		result = image.save_png("res://web/app-icon.png")
	quit(result)
