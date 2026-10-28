extends Control
const Evolution = preload("res://scripts/ship_evolution.gd")
## Original, resolution-independent orbital hangar. No combat or save state.
var reduced_motion := false
var level := 1
var rank := 1
var drones := 1
var compact := false
var _time := 0.0
var _ship: Texture2D = preload("res://assets/player-ship.png")
var _backdrop: Texture2D = preload("res://assets/arena-background.png")
var _glow: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.65))
	gradient.add_point(0.22, Color(1, 1, 1, 0.22))
	gradient.set_color(gradient.get_point_count() - 1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1, 0.5)
	_glow = texture
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	if not is_visible_in_tree() or reduced_motion: return
	_time += delta
	queue_redraw()

func _light(origin: Vector2, radius: float, tint: Color) -> void:
	if _glow != null:
		draw_texture_rect(_glow, Rect2(origin - Vector2.ONE * radius, Vector2.ONE * radius * 2), false, tint)

func _draw() -> void:
	if size.x <= 0 or size.y <= 0: return
	var small := compact or size.y < 260
	var cyan := Color("61f0e6")
	var amber := Color("ffc782")
	draw_rect(Rect2(Vector2.ZERO, size), Color("071221"))
	draw_texture_rect(_backdrop, Rect2(Vector2.ZERO, size), false, Color(0.45, 0.6, 0.72, 0.6))
	for band in range(32):
		var opacity := pow(float(band) / 31.0, 2) * 0.92
		draw_rect(Rect2(0, size.y * band / 32.0, size.x, size.y / 32.0 + 1), Color(0.018, 0.045, 0.08, opacity))
	_light(Vector2(size.x * 0.8, size.y * 0.16), size.x * 0.65, Color(0.27, 0.5, 1, 0.4))
	_light(Vector2(size.x * 0.15, size.y * 0.7), size.x * 0.5, Color(0.1, 0.85, 0.85, 0.25))
	for index in range(48):
		var pos := Vector2(fposmod(index * 83.71 + 17, size.x), fposmod(index * 51.19 + 29, size.y))
		var alpha := 0.23 + 0.15 * sin(_time * 0.4 + index)
		draw_circle(pos, 0.7 if index % 3 else 1.2, Color(0.7, 0.9, 1, alpha))
	var center := Vector2(size.x * (0.73 if small else 0.55), size.y * (0.5 if small else 0.40))
	var ship_size := minf(size.x * (0.33 if small else 0.42), size.y * (0.77 if small else 0.52))
	var radius := ship_size * 0.69
	# A perspective launch cradle anchors the ship in a lit physical space.
	var platform := center + Vector2(0, ship_size * 0.44)
	draw_set_transform(platform, 0, Vector2(1, 0.30))
	draw_circle(Vector2.ZERO, radius, Color(0.02, 0.11, 0.17, 0.7))
	for ring in range(4):
		draw_arc(Vector2.ZERO, radius - ring * 9, 0, TAU, 80, Color(cyan, 0.12 + ring * 0.06), 1.5, true)
	draw_set_transform(Vector2.ZERO)
	_light(center + Vector2(0, ship_size * 0.25), ship_size * 0.65, Color(cyan, 0.38))
	var lift := 0.0 if reduced_motion else sin(_time * 1.3) * 4
	draw_texture_rect(Evolution.texture(rank), Rect2(center - Vector2.ONE * ship_size * 0.5 + Vector2(0, lift), Vector2.ONE * ship_size), false)
	for index in range(clampi(drones, 1, 5)):
		var angle := _time * 0.22 + index * TAU / maxi(drones, 1)
		var point := center + Vector2(cos(angle) * radius, sin(angle) * radius * 0.55)
		_light(point, 22, Color(cyan, 0.5))
		draw_colored_polygon(PackedVector2Array([point + Vector2(0,-8), point + Vector2(6,2), point + Vector2(0,6), point + Vector2(-6,2)]), Color("b7fff5"))
	var font := ThemeDB.fallback_font
	if small:
		draw_string(font, Vector2(16, 26), "ORBIT / MK %02d" % rank, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.5, 12, cyan)
		draw_string(font, Vector2(16, 52), "Your ship.", HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.54, 23, Color("f0f8ff"))
		draw_string(font, Vector2(16, 79), "Your frontier.", HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.54, 23, Color("f0f8ff"))
		draw_string(font, Vector2(16, size.y - 16), "REPULSOR ONLINE", HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.6, 10, amber)
	else:
		draw_string(font, Vector2(25, 30), "O R B I T   D I V I S I O N", HORIZONTAL_ALIGNMENT_LEFT, size.x - 50, 12, cyan)
		draw_string(font, Vector2(25, 53), "HANGAR 01    /    FLIGHT SYSTEMS READY", HORIZONTAL_ALIGNMENT_LEFT, size.x - 50, 10, Color("95adc3"))
		var baseline := size.y * 0.76
		var title_size := clampi(int(size.x * 0.064), 26, 48)
		draw_string(font, Vector2(26, baseline), "Own the frontier.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 52, title_size, Color("f0f8ff"))
		draw_string(font, Vector2(28, baseline + 31), "DODGE.  REPULSE.  BUILD YOUR ARSENAL.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 56, 12, cyan)
		draw_line(Vector2(28, size.y - 56), Vector2(size.x - 28, size.y - 56), Color(cyan, 0.23), 1)
		draw_string(font, Vector2(28, size.y - 30), "RANK %02d   /   %d ORBIT DRONE%s" % [rank, drones, "S" if drones != 1 else ""], HORIZONTAL_ALIGNMENT_LEFT, size.x - 56, 11, Color("a1b8cc"))
		draw_string(font, Vector2(size.x - 170, size.y - 30), "SECTOR %02d AWAITS" % level, HORIZONTAL_ALIGNMENT_LEFT, 150, 11, amber)
