extends Control
## Brief paper celebration over the feedback UI, independent of grading and input.
const COLORS := [Color("bafa83"), Color("64eee3"), Color("ffbc63"), Color("ff7aa9"), Color("aa96ff"), Color("edf7ff")]
const MAX_PIECES := 120
var reduced_motion := false
var _pieces: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _age := 0.0
var _duration := 2.1

func _ready() -> void:
	_rng.randomize()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	z_index = 10
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)

func celebrate(area: Rect2, gentle: bool = false) -> void:
	reduced_motion = gentle
	_age = 0.0
	_duration = 0.9 if gentle else 2.1
	# Replace an unfinished burst to keep rapid correct answers bounded.
	_pieces.clear()
	var count := 18 if gentle else 88
	for index in range(mini(count, MAX_PIECES)):
		var side := -1.0 if index % 2 == 0 else 1.0
		var position := area.position + Vector2(area.size.x * (0.17 if side < 0 else 0.83), minf(90.0, area.size.y * 0.18))
		var velocity := Vector2(-side * _rng.randf_range(35, 170), -_rng.randf_range(80, 300))
		if gentle:
			position = area.position + Vector2(16 + (area.size.x - 32) * float(index) / maxi(1, count - 1), 12 + (index % 3) * 7)
			velocity = Vector2.ZERO
		_pieces.append({"pos":position, "velocity":velocity, "angle":_rng.randf_range(-PI, PI), "spin":_rng.randf_range(-5,5), "size":Vector2(_rng.randf_range(4,7),_rng.randf_range(8,13)), "color":COLORS[index % COLORS.size()], "phase":_rng.randf_range(0,TAU)})
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_age += delta
	if _age >= _duration:
		_pieces.clear()
		set_process(false)
	else:
		for piece in _pieces:
			if reduced_motion: continue
			piece.velocity.y += 390.0 * delta
			piece.pos += (piece.velocity as Vector2) * delta
			piece.pos.x += sin(_age * 7.0 + float(piece.phase)) * delta * 18
			piece.angle += float(piece.spin) * delta
	queue_redraw()

func _draw() -> void:
	var opacity := clampf((_duration - _age) / 0.5, 0, 1)
	for piece in _pieces:
		var tint: Color = piece.color
		tint.a = opacity * (0.75 if reduced_motion else 1.0)
		var paper_size: Vector2 = piece.size
		if not reduced_motion: paper_size.x *= 0.35 + absf(cos(_age * 6.0 + float(piece.phase))) * 0.65
		draw_set_transform(piece.pos, float(piece.angle))
		draw_rect(Rect2(-paper_size * 0.5, paper_size), tint)
	draw_set_transform(Vector2.ZERO)
