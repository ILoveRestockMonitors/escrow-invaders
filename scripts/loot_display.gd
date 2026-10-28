extends Control
## Original procedural reward art. These numbers are supplied by saved game state.

const INK := Color("071020")
const GOLD := Color("ffd76d")
const AMBER := Color("e99825")
const CYAN := Color("60ecff")
const LIME := Color("c6ff65")
const ROSE := Color("fa8fc4")

var coins: int = 0:
	set(value):
		coins = maxi(0, value)
		queue_redraw()
var gems: int = 0:
	set(value):
		gems = maxi(0, value)
		queue_redraw()
var xp: int = 0:
	set(value):
		xp = maxi(0, value)
		queue_redraw()
var mode: String = "loot":
	set(value):
		mode = value if value in ["loot", "boost", "shop"] else "loot"
		queue_redraw()
var progress: int = 0:
	set(value):
		progress = clampi(value, 0, 3)
		queue_redraw()
var reduced_motion: bool = false:
	set(value):
		reduced_motion = value
		set_process(not value)
		queue_redraw()
var _time := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(280, 166)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)
	set_process(not reduced_motion)

func _process(delta: float) -> void:
	_time = fposmod(_time + delta, TAU * 20.0)
	queue_redraw()

func _draw() -> void:
	if size.x < 1 or size.y < 1: return
	var width := size.x
	var center_y := 67.0
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("0c192c")
	panel.border_color = Color("254058")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(15)
	draw_style_box(panel, Rect2(Vector2.ZERO, size))
	draw_line(Vector2(18, 29), Vector2(width - 18, 29), Color("264259"), 1.0)
	var title := {"loot": "CARGO SECURED", "boost": "STUDY BOOST", "shop": "PERMANENT ARSENAL"}.get(mode, "CARGO SECURED")
	_text(str(title), Vector2(width * 0.5, 20), 11, Color("b0c5d6"))
	var centers := [width * 0.18, width * 0.5, width * 0.82]
	for column in range(3):
		var tint: Color = [GOLD, ROSE, CYAN][column]
		var pos := Vector2(centers[column], center_y)
		var lift := 0.0 if reduced_motion else sin(_time * 1.6 + float(column) * 1.7) * 2.0
		draw_circle(pos, 31, Color(tint.r, tint.g, tint.b, 0.035))
		draw_circle(pos, 22, Color(tint.r, tint.g, tint.b, 0.045))
		if column == 0:
			_coin_stack(pos + Vector2(0, lift))
		elif column == 1:
			_gem(pos + Vector2(0, lift), 21.0, false)
			_gem(pos + Vector2(19, 13), 9.0, true)
		else:
			_reactor(pos + Vector2(0, lift))
		var sparkle := Vector2(centers[column] + 25, center_y - 21)
		var sparkle_alpha := 0.45 if reduced_motion else 0.45 + sin(_time * 2.2 + column) * 0.2
		_sparkle(sparkle, Color(tint.r, tint.g, tint.b, sparkle_alpha), 4.0)
		var value: int = [coins, gems, xp][column]
		_text(_amount(value), Vector2(centers[column], 113), 22, tint)
		_text(["COINS", "GEMS", "SHIP XP"][column], Vector2(centers[column], 130), 10, Color("8ea9bc"))
	if mode == "boost":
		var start := width * 0.5 - 42
		for step in range(3):
			var pos := Vector2(start + step * 42, 151)
			var tint := LIME if step < progress else Color("375268")
			if step < 2: draw_line(pos + Vector2(9, 0), pos + Vector2(33, 0), Color("2c455b"), 2)
			draw_circle(pos, 8, Color(tint.r, tint.g, tint.b, 0.18))
			draw_arc(pos, 8, 0, TAU, 24, tint, 1.3, true)
			if step < progress:
				draw_line(pos + Vector2(-3, 0), pos + Vector2(-0.5, 3), LIME, 1.8, true)
				draw_line(pos + Vector2(-0.5, 3), pos + Vector2(4, -3), LIME, 1.8, true)
			else:
				_text(str(step + 1), pos + Vector2(0, 3.5), 9, Color("99b0c1"))
	else:
		var text := "EARNED. BANKED. YOURS." if mode == "loot" else "BUILD IT. KEEP IT."
		_text(text, Vector2(width * 0.5, 154), 9, Color("66869d"))

func _coin_stack(origin: Vector2) -> void:
	_coin(origin + Vector2(8, 14), 20.0)
	_coin(origin + Vector2(-4, 7), 22.0)
	_coin(origin + Vector2(-8, 0), 22.0)
	_coin(origin + Vector2(-3, -8), 22.0)

func _coin(origin: Vector2, radius: float) -> void:
	var sides := PackedVector2Array([origin + Vector2(-radius, -1), origin + Vector2(radius, -1), origin + Vector2(radius, 5), origin + Vector2(-radius, 5)])
	draw_colored_polygon(sides, AMBER.darkened(0.26))
	draw_set_transform(origin + Vector2(0, 5), 0, Vector2(1, 0.34))
	draw_circle(Vector2.ZERO, radius, AMBER.darkened(0.28))
	draw_set_transform(origin, 0, Vector2(1, 0.34))
	draw_circle(Vector2.ZERO, radius, GOLD)
	draw_arc(Vector2.ZERO, radius - 3, 0, TAU, 32, AMBER, 1.4, true)
	draw_arc(Vector2.ZERO, radius - 1, PI, TAU, 24, Color("fff2b3"), 1.3, true)
	draw_set_transform(Vector2.ZERO)
	draw_line(origin + Vector2(-4, -3), origin + Vector2(4, 3), AMBER, 2.0, true)
	draw_line(origin + Vector2(4, -3), origin + Vector2(-4, 3), AMBER, 2.0, true)

func _gem(origin: Vector2, radius: float, small: bool) -> void:
	var top := origin + Vector2(0, -radius)
	var left := origin + Vector2(-radius * 0.82, -radius * 0.22)
	var right := origin + Vector2(radius * 0.82, -radius * 0.22)
	var tip := origin + Vector2(0, radius)
	var middle := origin + Vector2(0, -radius * 0.22)
	var upper_left := origin + Vector2(-radius * 0.43, -radius * 0.82)
	var upper_right := origin + Vector2(radius * 0.43, -radius * 0.82)
	draw_colored_polygon(PackedVector2Array([top, upper_left, left, middle]), Color("fdafd6"))
	draw_colored_polygon(PackedVector2Array([top, middle, right, upper_right]), Color("e76cb2"))
	draw_colored_polygon(PackedVector2Array([left, tip, middle]), Color("b8428e"))
	draw_colored_polygon(PackedVector2Array([middle, tip, right]), Color("f281bd"))
	draw_polyline(PackedVector2Array([top, upper_left, left, tip, right, upper_right, top]), ROSE, 1.2, true)
	draw_line(top, tip, Color("ffb7df"), 0.9, true)
	if not small: _sparkle(origin + Vector2(-radius * 0.28, -radius * 0.52), Color("fff2fa"), 4.0)

func _reactor(origin: Vector2) -> void:
	var points := PackedVector2Array()
	for side in range(6): points.append(origin + Vector2.from_angle(float(side) * TAU / 6 - PI / 2) * 24)
	draw_colored_polygon(points, Color("14374b"))
	points.append(points[0])
	draw_polyline(points, Color("369caf"), 1.7, true)
	draw_arc(origin, 16, 0, TAU, 32, Color("2a697c"), 1.0, true)
	var bolt := PackedVector2Array([origin + Vector2(3, -17), origin + Vector2(-10, 2), origin + Vector2(-2, 2), origin + Vector2(-6, 16), origin + Vector2(11, -4), origin + Vector2(2, -4)])
	draw_colored_polygon(bolt, CYAN)
	draw_line(origin + Vector2(3, -15), origin + Vector2(-7, 1), Color("c6fbff"), 1.5, true)

func _sparkle(position: Vector2, tint: Color, radius: float) -> void:
	draw_line(position - Vector2(radius, 0), position + Vector2(radius, 0), tint, 1.3, true)
	draw_line(position - Vector2(0, radius), position + Vector2(0, radius), tint, 1.3, true)

func _text(message: String, baseline: Vector2, font_size: int, tint: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, baseline - Vector2(width * 0.5, 0), message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)

func _amount(value: int) -> String:
	if value >= 1000000: return "%.1fM" % (float(value) / 1000000.0)
	if value >= 10000: return "%.1fK" % (float(value) / 1000.0)
	return str(value)
