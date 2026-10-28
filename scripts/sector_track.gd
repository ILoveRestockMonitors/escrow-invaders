extends Control
## Static route graphic, redrawn only for layout changes. No progression writes.
const Palette = preload("res://scripts/ui_palette.gd")
var level := 1

func _ready() -> void:
	custom_minimum_size.y = 60
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var start := int((level - 1) / 5) * 5 + 1
	var step := maxf(1.0, (size.x - 38.0) / 4.0)
	var font := Palette.DISPLAY_FONT
	for index in range(5):
		var sector := start + index
		var center := Vector2(19 + step * index, 21)
		var complete := sector < level
		var current := sector == level
		var boss := sector % 5 == 0
		var tint: Color = Palette.SUCCESS if complete else Palette.SYSTEM if current else Palette.DANGER if boss else Color("577381")
		if index < 4:
			draw_line(center + Vector2(17, 0), center + Vector2(step - 17, 0), Palette.SUCCESS if complete else Palette.EDGE, 2, true)
		if current:
			draw_circle(center, 19, Color(Palette.SYSTEM, 0.08))
			draw_arc(center, 18, 0, TAU, 32, Color(Palette.SYSTEM, 0.55), 1, true)
		if boss:
			var hex := PackedVector2Array()
			for side in range(6): hex.append(center + Vector2.from_angle(TAU * side / 6 - PI / 2) * 15)
			draw_colored_polygon(hex, Color("302338"))
			hex.append(hex[0])
			draw_polyline(hex, tint, 1.5, true)
		else:
			draw_circle(center, 14, Color("183b3e") if current else Color("22372e") if complete else Color("152632"))
			draw_arc(center, 14, 0, TAU, 32, tint, 1.5, true)
		var number := str(sector) if sector < 1000 else "%.0fk" % (float(sector) / 1000.0)
		if boss and sector < 100: number = "B" + number
		var width := font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, center + Vector2(-width * 0.5, 4), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.TEXT if current or complete else tint)
		var label := "DONE" if complete else "NOW" if current else "BOSS" if boss else "LOCKED"
		width = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		draw_string(font, center + Vector2(-width * 0.5, 29), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, tint)
