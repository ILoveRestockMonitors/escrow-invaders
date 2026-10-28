extends Control
const Evolution = preload("res://scripts/ship_evolution.gd")
## Small live diorama used by the hangar, target lock, and blueprint reveal.
var mode := "ship"
var title := "ORBIT // MK I"
var subtitle := "ALL SYSTEMS ONLINE"
var drones := 1
var rank := 1
var reduced_motion := false
var _time := 0.0
var _age := 0.0
var _ship: Texture2D = preload("res://assets/player-ship.png")

func _ready() -> void:
	if custom_minimum_size.y == 0: custom_minimum_size.y = 150
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func _process(delta: float) -> void:
	_age += delta
	if not reduced_motion: _time += delta
	queue_redraw()

func _draw() -> void:
	var cyan := Color("53e8ff")
	var lime := Color("bfff68")
	var pink := Color("ff7aa9")
	var gold := Color("ffbc63")
	var accent: Color = pink if mode == "locked" else (gold if mode == "solution" else lime if mode in ["independent", "assisted", "unlock"] else cyan)
	draw_style_box(_panel(Color("081426"), Color("28435d")), Rect2(Vector2.ZERO, size))
	for x in range(0, int(size.x), 24):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.18, 0.32, 0.44, 0.15))
	for y in range(0, int(size.y), 24):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.18, 0.32, 0.44, 0.15))
	var center := Vector2(size.x * 0.5, size.y * 0.47)
	var radius := minf(size.y * 0.30, 60.0)
	for index in range(3):
		draw_arc(center, radius + index * 10, _time * 0.18 + index, _time * 0.18 + index + 4.6, 64, Color(accent, 0.13 + index * 0.06), 1.0, true)
	if mode in ["locked", "independent", "assisted", "solution"]:
		var points := PackedVector2Array()
		for index in range(6): points.append(center + Vector2.from_angle(index * TAU / 6.0 - PI / 2) * 22)
		draw_colored_polygon(points, Color("351d42"))
		points.append(points[0])
		draw_polyline(points, pink, 2.0, true)
		draw_circle(center, 8.0, Color("ffbc63"))
		for index in range(8):
			var angle := index * TAU / 8.0 + 0.1
			var expansion := 0.0 if mode == "locked" else minf(_age * 110, 90)
			var opacity := 0.9 if mode == "locked" else maxf(0, 1.0 - _age)
			draw_arc(center, radius + expansion, angle, angle + 0.52, 12, Color(cyan, opacity), 3.0, true)
		if mode in ["independent", "assisted"] and _age < 1.2:
			draw_line(Vector2(center.x, size.y), center, Color(lime, maxf(0, 1.0 - _age)), 5 if mode == "independent" else 2, true)
			draw_arc(center, _age * 100, 0, TAU, 64, Color(lime, maxf(0, 1.0 - _age)), 2.0, true)
	else:
		draw_texture_rect(Evolution.texture(rank), Rect2(center - Vector2(36, 36), Vector2(72, 72)), false)
		for index in range(clampi(drones, 1, 8)):
			var position := center + Vector2.from_angle(_time * 0.6 + index * TAU / maxi(drones, 1)) * radius
			draw_circle(position, 10, Color(cyan, 0.15))
			draw_circle(position, 5, cyan)
			draw_line(position, position + Vector2(0, -12), lime, 3, true)
		if rank >= 10:
			draw_arc(center, radius + 19, -_time, -_time + 5.4, 64, Color(lime, 0.5), 2, true)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(14, 22), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, 12, accent)
	draw_string(font, Vector2(14, size.y - 13), subtitle, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, 11, Color("9eb5ce"))

func _panel(fill: Color, line: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = line
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	return box
