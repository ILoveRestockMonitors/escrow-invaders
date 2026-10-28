extends Control
## Game UI and explicit encounter state machine. No course extraction or AI calls.

const StudyModel = preload("res://scripts/study_model.gd")
const ProgressionModel = preload("res://scripts/progression_model.gd")
const ResponseJournal = preload("res://scripts/response_journal.gd")
const EncounterDirector = preload("res://scripts/encounter_director.gd")
const LootDisplay = preload("res://scripts/loot_display.gd")
const ShipDisplay = preload("res://scripts/ship_display.gd")
const HangarDisplay = preload("res://scripts/hangar_display.gd")
const AnswerConfetti = preload("res://scripts/answer_confetti.gd")
const SectorTrack = preload("res://scripts/sector_track.gd")
const Arena = preload("res://scripts/arena.gd")
const GameAudio = preload("res://scripts/game_audio.gd")
const UiDescriptions = preload("res://scripts/ui_descriptions.gd")
const Palette = preload("res://scripts/ui_palette.gd")
const CloudSave = preload("res://scripts/cloud_save.gd")
const BG := Palette.BASE
const PANEL := Palette.SURFACE
const EDGE := Palette.EDGE
const WHITE := Palette.TEXT
const MUTED := Palette.MUTED
const CYAN := Palette.SYSTEM
const LIME := Palette.SUCCESS
const GOLD := Palette.REWARD
const PINK := Palette.DANGER
enum Phase { READY, CORE, FEEDBACK, UPGRADE, COMBAT, BONUS_INTRO, BONUS, SUMMARY, CLEAR, DEFEAT, HANGAR, SHOP, BOOST_INTRO, BOOST, REVIVE, STUDY }

var test_mode := false
var bonus_seconds := 10.0
var combat_seconds := 8.0
var phase: int = Phase.READY
var model = StudyModel.new()
var progression = ProgressionModel.new()
var journal
var _xp_bar: ProgressBar
var _evolution_label: Label
var _ratio_row: HBoxContainer
var _ratio_bar: ProgressBar
var _ratio_caption: Label
var _answer_count := -1
var _answer_totals := {"correct": 0, "wrong": 0, "answered": 0}
var _rank_progress_label: Label
var _xp_caption: Label
var _diorama: Control
var _last_clear: Dictionary = {}
var _reward_return: Callable
var _boost_mode := false
var _revive_mode := false
var _arena_attempt_id := ""
var _boost_slot := 0
var _wallet_label: Label
var _hud_tick := 0.0
var _save_problem_open := false
var _save_return_phase: int = Phase.READY
var arena: Control
var audio: Node
var core_index := 0
var bonus_index := 0
var current_question: Dictionary = {}
var score := 0
var combo := 0
var shields := 3
var turret_level := 1
var lightning_level := 0
var overdrive := false
var assisted := false
var confidence := -1
var answer_attempts := 0
var last_correct := false
var last_is_bonus := false
var bonus_remaining := 10.0
var combat_remaining := 0.0
var total_kills := 0
var total_coins := 0
var paused := false
var _answer_buttons: Array[Button] = []
var _confidence_buttons: Array[Button] = []
var _side: VBoxContainer
var _side_scroll: ScrollContainer
var _hud_wave: Label
var _hud_score: Label
var _hud_combo: Label
var _hud_shields: Label
var _arena_status: Label
var _arena_title: Label
var _loadout: HBoxContainer
var _hint_label: Label
var _bonus_label: Label
var _bonus_bar: ProgressBar
var _combat_bar: ProgressBar
var _numeric: LineEdit
var _sound_button: Button
var _pause_button: Button
var _save_notice: Label
var _content_title: Label
var _mobile := false
var _margins: MarginContainer
var _page: VBoxContainer
var _header: HBoxContainer
var _brand_title: Label
var _brand_subtitle: Label
var _status_row: HBoxContainer
var _controls: Label
var _effects: CheckButton
var _ready_hero: TextureRect
var _body: HBoxContainer
var _arena_panel: PanelContainer
var _side_panel: PanelContainer
var _menu_nav: HBoxContainer
var _menu_buttons: Array[Button] = []
var _help_button: Button
var _help_layer: Control
var _help_panel: PanelContainer
var _help_scroll: ScrollContainer
var _help_body: VBoxContainer
var _help_close_button: Button
var _help_topic_buttons: Array[Button] = []
var _help_paused_here := false
var _help_underlay_focus: Dictionary = {}
var _help_previous_focus: Control
var _hangar_view: Control
var _mobile_hangar: Control
var _pulse_button: Button
var _pulse_bar: ProgressBar
var _pulse_row: HBoxContainer
var _combat_brief: Label
var _music_setting: CheckButton
var _effects_setting: CheckButton
var _study_primary: Button
var _study_keys_held: Dictionary = {}
var _study_keys_blocked: Dictionary = {}
var _study_generation := 0
var _answer_confetti: Control
var _web_skin := false
var _web_ui_clock := 0.0
var _footer: HBoxContainer
var _mission_streak: Label
var _ability_status: Label
var _route_track: Control
var _home_install: Button
var _document_badge: Label
var _document_badge_box: PanelContainer
var _document_seal := ""
var _study_backdrop: TextureRect
var _action_hotkeys: Dictionary = {}
var _question_elapsed_seconds := 0.0
var _question_timer_running := false
var _version_label: Label
var _cloud: JavaScriptObject
var _cloud_state: Dictionary = {}
var _cloud_status := ""
var _cloud_poll := 0.0
var _cloud_push_wait := 0.0
var _cloud_push_hash := ""
var _cloud_push_in_flight := false
var _cloud_pending_adopt: Dictionary = {}
var _cloud_reloading := false
const ACTION_KEYS := [KEY_R, KEY_V, KEY_K, KEY_C, KEY_H, KEY_G, KEY_J, KEY_L, KEY_B, KEY_P, KEY_Y, KEY_X, KEY_I, KEY_U, KEY_E, KEY_O, KEY_M, KEY_F, KEY_T, KEY_N, KEY_Q, KEY_Z]


func _ready() -> void:
	_web_skin = OS.has_feature("web") and bool(JavaScriptBridge.eval("Boolean(window.orbitalUI)"))
	model.persistence_enabled = not test_mode
	progression.persistence_enabled = not test_mode
	if not test_mode:
		_cloud_startup()
		model.load_course_bank()
		model.load_progress()
		progression.load_progress()
	journal = ResponseJournal.new(model, progression)
	journal.persistence_enabled = not test_mode
	journal.recover()
	audio = GameAudio.new()
	add_child(audio)
	theme = Theme.new()
	theme.default_font = Palette.BODY_FONT
	theme.default_font_size = 16
	var scroll_track := _style(Color("102531"), Color("102531"), 3)
	scroll_track.set_content_margin_all(2)
	scroll_track.shadow_size = 0
	var scroll_grip := _style(Color("40666d"), Color("40666d"), 3)
	scroll_grip.set_content_margin_all(3)
	scroll_grip.shadow_size = 0
	theme.set_stylebox("scroll", "VScrollBar", scroll_track)
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]: theme.set_stylebox(state, "VScrollBar", scroll_grip)
	_build_ui()
	if _cloud != null: _cloud_set_status(_cloud_status if not _cloud_status.is_empty() else "CHECKING")
	_show_ready()
	resized.connect(_responsive_layout)
	call_deferred("_responsive_layout")


func _style(color: Color, border: Color = EDGE, radius: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.01, 0.03, 0.24)
	style.shadow_size = 4
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _label(text: String, font_size: int = 18, color: Color = WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if font_size >= 20: label.add_theme_font_override("font", Palette.DISPLAY_FONT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _button(text: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = 48
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_font_override("font", Palette.DISPLAY_FONT)
	button.add_theme_color_override("font_color", BG if primary else WHITE)
	button.add_theme_color_override("font_hover_color", BG if primary else WHITE)
	button.add_theme_color_override("font_pressed_color", BG if primary else WHITE)
	button.add_theme_color_override("font_focus_color", BG if primary else WHITE)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_stylebox_override("normal", _style(LIME if primary else Color("14253c"), LIME if primary else EDGE, 8))
	button.add_theme_stylebox_override("hover", _style(Color("d5ffa3") if primary else Color("203953"), CYAN, 8))
	button.add_theme_stylebox_override("pressed", _style(Color("a2dc4c") if primary else Color("2b4e68"), WHITE, 8))
	button.add_theme_stylebox_override("disabled", _style(Color("0e192b"), Color("22364b"), 8))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), CYAN, 8))
	var focus_style := button.get_theme_stylebox("focus") as StyleBoxFlat
	focus_style.set_border_width_all(3)
	focus_style.shadow_size = 0
	button.pressed.connect(callback)
	if primary and phase in [Phase.FEEDBACK, Phase.BOOST_INTRO, Phase.BONUS_INTRO] and not is_instance_valid(_study_primary):
		_study_primary = button
		button.tooltip_text = "Enter: " + text
	button.mouse_entered.connect(func() -> void:
		if not button.disabled: audio.play("hover"))
	return button


func _preferred_action_key(button: Button) -> int:
	if button == _pause_button or button == _help_close_button: return KEY_ESCAPE
	if button == _pulse_button: return KEY_SPACE
	if button == _sound_button: return KEY_M
	if button == _help_button: return KEY_F
	if button == _effects: return KEY_T
	if button == _music_setting: return KEY_M
	if button == _effects_setting: return KEY_E
	var title := button.text.to_upper()
	if title == "GUESSING": return KEY_G
	if title == "LEANING": return KEY_J
	if title == "SURE": return KEY_L
	if title.contains("SOLUTION"): return KEY_V
	if title.begins_with("TRY ") or title.begins_with("RETRY") or title.begins_with("REBUILD"): return KEY_R
	if title.contains("HINT"): return KEY_H
	if title.begins_with("SKIP") or title.begins_with("SAVE FOR LATER") or title.begins_with("SAVE QUESTIONS"): return KEY_K
	if title.begins_with("BACK") or title.begins_with("DONE"): return KEY_B
	if title.begins_with("REVIVE"): return KEY_Y
	if title.contains("EXPORT"): return KEY_X
	if title.contains("PHONE"): return KEY_I
	if title == "HOME": return KEY_O
	if title == "UPGRADES": return KEY_U
	if title == "WEAPONS": return KEY_E
	if title == "STUDY": return KEY_B
	if title.begins_with("CONTINUE") or title.begins_with("NEXT") or title.begins_with("CLAIM") or title.begins_with("VIEW DEFEAT"): return KEY_C
	if title.begins_with("PLAY") or title.begins_with("START") or title.begins_with("DEPLOY"): return KEY_P
	return 0


func _refresh_action_hotkeys() -> void:
	_action_hotkeys.clear()
	if not is_instance_valid(_help_layer): return
	var buttons: Array[Button] = []
	for control in find_children("*", "Button", true, false):
		var button := control as Button
		if not button.is_visible_in_tree() or _answer_buttons.has(button): continue
		if _help_layer.visible != _help_layer.is_ancestor_of(button): continue
		buttons.append(button)
	# Claim stable mnemonic keys before assigning alternatives to repeated actions.
	for button in buttons:
		if button.has_meta("action_key"): button.remove_meta("action_key")
		var preferred := _preferred_action_key(button)
		if preferred != 0 and not _action_hotkeys.has(preferred):
			_action_hotkeys[preferred] = button
			button.set_meta("action_key", preferred)
	for button in buttons:
		if not button.has_meta("action_key"):
			for key in ACTION_KEYS:
				if not _action_hotkeys.has(key):
					_action_hotkeys[key] = button
					button.set_meta("action_key", key)
					break
		if not button.has_meta("action_key"): continue
		var code := int(button.get_meta("action_key"))
		var key_name := "Esc" if code == KEY_ESCAPE else "Space" if code == KEY_SPACE else OS.get_keycode_string(code)
		var badge := button.get_node_or_null("ActionHotkey") as Label
		if not is_instance_valid(badge):
			badge = Label.new()
			badge.name = "ActionHotkey"
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.add_theme_font_override("font", Palette.BODY_FONT)
			badge.add_theme_font_size_override("font_size", 11)
			badge.add_theme_color_override("font_color", CYAN)
			var badge_style := StyleBoxFlat.new()
			badge_style.bg_color = BG
			badge_style.set_corner_radius_all(2)
			badge_style.content_margin_left = 3
			badge_style.content_margin_right = 3
			badge.add_theme_stylebox_override("normal", badge_style)
			button.add_child(badge)
			badge.position = Vector2(7, 2)
		badge.text = "[" + key_name + "]"
		badge.visible = not button.text.ends_with("[H]")
		button.tooltip_text = key_name + ": " + button.text + (" / Enter continues" if button == _study_primary else "")
		# Use an inset badge so existing labels and test/action contracts stay intact.
		if not button.has_meta("hotkey_inset"):
			button.set_meta("hotkey_inset", true)
			for state in ["normal", "hover", "pressed", "disabled", "focus"]:
				var source_style := button.get_theme_stylebox(state)
				if source_style is StyleBoxFlat:
					var inset_style := source_style.duplicate() as StyleBoxFlat
					inset_style.content_margin_top = maxf(12 if button in [_sound_button, _pause_button] else 19, inset_style.content_margin_top)
					button.add_theme_stylebox_override(state, inset_style)


func _handle_action_key(event: InputEventKey) -> bool:
	if not event.pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return false
	var code := event.keycode if event.keycode != 0 else event.physical_keycode
	if not _action_hotkeys.has(code): return false
	if event.echo or _study_keys_blocked.has(code): return true
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit: return false
	var button: Button = _action_hotkeys[code]
	if not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled: return false
	if _help_layer.visible != _help_layer.is_ancestor_of(button): return false
	if paused and _side.is_ancestor_of(button): return true
	if button.toggle_mode: button.button_pressed = not button.button_pressed
	else: button.pressed.emit()
	return true


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_study_backdrop = TextureRect.new()
	_study_backdrop.texture = preload("res://assets/arena-background.png")
	_study_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_study_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_study_backdrop.modulate.a = 0.16
	_study_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_study_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_study_backdrop)
	var margins := MarginContainer.new()
	_margins = margins
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 18)
	add_child(margins)
	var page := VBoxContainer.new()
	_page = page
	page.add_theme_constant_override("separation", 14)
	margins.add_child(page)
	var header := HBoxContainer.new()
	_header = header
	header.add_theme_constant_override("separation", 20)
	page.add_child(header)
	var brand := VBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_brand_title = _label("ESCROW INVADERS", 28, CYAN)
	_brand_title.add_theme_font_override("font", Palette.DISPLAY_FONT)
	_brand_subtitle = _label("ORBITAL CLOSING DESK / FLIGHT DIVISION", 11, MUTED)
	brand.add_child(_brand_title)
	brand.add_child(_brand_subtitle)
	header.add_child(brand)
	_status_row = HBoxContainer.new()
	_status_row.add_theme_constant_override("separation", 8)
	page.add_child(_status_row)
	_hud_wave = _label("5 CORE + 2 BONUS", 18)
	_hud_wave.custom_minimum_size.x = 150
	_hud_wave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_status_row.add_child(_hud_wave)
	_hud_score = _label("0 XP", 23, LIME)
	_hud_score.custom_minimum_size.x = 120
	_hud_score.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_status_row.add_child(_hud_score)
	_sound_button = _button("Sound off", _toggle_sound)
	_sound_button.icon = preload("res://assets/ui-sound.svg")
	_sound_button.autowrap_mode = TextServer.AUTOWRAP_OFF
	_sound_button.custom_minimum_size.x = 110
	_sound_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	header.add_child(_sound_button)
	_pause_button = _button("Pause", _toggle_pause)
	_pause_button.icon = preload("res://assets/ui-pause.svg")
	_pause_button.autowrap_mode = TextServer.AUTOWRAP_OFF
	_pause_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	header.add_child(_pause_button)
	_wallet_label = _label("COINS 0     GEMS 0", 13, GOLD)
	page.add_child(_wallet_label)
	_ratio_row = HBoxContainer.new()
	_ratio_row.add_theme_constant_override("separation", 12)
	page.add_child(_ratio_row)
	_ratio_caption = _label("RIGHT 0 : 0 WRONG / NO ANSWERS", 12, CYAN)
	_ratio_row.add_child(_ratio_caption)
	_ratio_bar = ProgressBar.new()
	_ratio_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ratio_bar.custom_minimum_size = Vector2(40, 12)
	_ratio_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ratio_bar.show_percentage = false
	_ratio_bar.max_value = 100
	_ratio_bar.add_theme_stylebox_override("fill", _style(LIME, LIME, 3))
	_ratio_bar.add_theme_stylebox_override("background", _style(PINK, PINK, 3))
	_ratio_row.add_child(_ratio_bar)
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 16)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_body)
	_arena_panel = PanelContainer.new()
	_arena_panel.add_theme_stylebox_override("panel", _style(Color("0a1427")))
	_arena_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_arena_panel.size_flags_stretch_ratio = 2.15
	_body.add_child(_arena_panel)
	var arena_column := VBoxContainer.new()
	arena_column.add_theme_constant_override("separation", 10)
	_arena_panel.add_child(arena_column)
	var arena_header := HBoxContainer.new()
	_arena_title = _label("SECTOR 07  /  LOST EQUITY", 13, MUTED)
	arena_header.add_child(_arena_title)
	_arena_status = _label("SYSTEMS READY", 13, CYAN)
	_arena_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	arena_header.add_child(_arena_status)
	arena_column.add_child(arena_header)
	arena = Arena.new()
	arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena.custom_minimum_size = Vector2(440, 240)
	arena.combat_finished.connect(_on_combat_finished)
	arena.shield_hit.connect(_on_shield_hit)
	arena.question_requested.connect(_on_question_requested)
	arena.enemy_killed.connect(_on_enemy_killed)
	arena.combat_cue.connect(_on_combat_cue)
	arena_column.add_child(arena)
	_hangar_view = HangarDisplay.new()
	_hangar_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hangar_view.custom_minimum_size = Vector2(0, 160)
	arena_column.add_child(_hangar_view)
	_combat_bar = ProgressBar.new()
	_combat_bar.custom_minimum_size.y = 5
	_combat_bar.show_percentage = false
	_combat_bar.max_value = 100
	_combat_bar.add_theme_stylebox_override("fill", _style(CYAN, CYAN, 2))
	_combat_bar.add_theme_stylebox_override("background", _style(Color("172740"), Color("172740"), 2))
	arena_column.add_child(_combat_bar)
	_pulse_row = HBoxContainer.new()
	_pulse_row.add_theme_constant_override("separation", 12)
	_pulse_button = _button("REPULSOR / READY", _activate_pulse, true)
	_pulse_button.focus_mode = Control.FOCUS_NONE
	_pulse_button.custom_minimum_size.y = 44
	_pulse_button.add_theme_font_size_override("font_size", 14)
	_pulse_button.tooltip_text = "Space or tap. Clear nearby bullets and push enemies back. Recharges in 7 seconds."
	_pulse_row.add_child(_pulse_button)
	_pulse_bar = ProgressBar.new()
	_pulse_bar.custom_minimum_size = Vector2(64, 8)
	_pulse_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pulse_bar.max_value = 1.0
	_pulse_bar.show_percentage = false
	_pulse_bar.add_theme_stylebox_override("fill", _style(CYAN, CYAN, 3))
	_pulse_bar.add_theme_stylebox_override("background", _style(Color("182e40"), EDGE, 3))
	for meter in [_combat_bar, _pulse_bar]:
		for state in ["fill", "background"]:
			var meter_style := meter.get_theme_stylebox(state) as StyleBoxFlat
			meter_style.content_margin_top = 0
			meter_style.content_margin_bottom = 0
			meter_style.content_margin_left = 0
			meter_style.content_margin_right = 0
			meter_style.shadow_size = 0
	_pulse_row.add_child(_pulse_bar)
	arena_column.add_child(_pulse_row)
	_hud_shields = _label("SHIELDS  3 / 3", 13, CYAN)
	_hud_combo = _label("COMBO x0", 13, LIME)
	_hud_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_row.add_child(_hud_shields)
	_status_row.add_child(_hud_combo)
	_loadout = HBoxContainer.new()
	_loadout.add_theme_constant_override("separation", 8)
	arena_column.add_child(_loadout)
	var controls := _label("WASD / ARROWS  ·  HOLD + DRAG TO MOVE  ·  AUTO-FIRE", 12, MUTED)
	_controls = controls
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arena_column.add_child(controls)
	_side_panel = PanelContainer.new()
	_side_panel.custom_minimum_size.x = 400
	_side_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_panel.size_flags_stretch_ratio = 1.0
	_side_panel.add_theme_stylebox_override("panel", _style(PANEL))
	_body.add_child(_side_panel)
	var scroll := ScrollContainer.new()
	_side_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_side_panel.add_child(scroll)
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 13)
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_side)
	_menu_nav = HBoxContainer.new()
	_menu_nav.add_theme_constant_override("separation", 6)
	for index in range(4):
		var button := _button(["Home", "Upgrades", "Weapons", "Study"][index], _navigate_menu.bind(index))
		button.add_theme_font_size_override("font_size", 15)
		_menu_nav.add_child(button)
		_menu_buttons.append(button)
	page.add_child(_menu_nav)
	var footer := HBoxContainer.new()
	_footer = footer
	page.add_child(footer)
	_save_notice = _label(("ORIGINAL SAMPLE MATH" if model.sample_data else model.bank_title.to_upper()) + "  ·  " + _save_scope(), 12, MUTED)
	footer.add_child(_save_notice)
	_version_label = _label("v" + String(ProjectSettings.get_setting("application/config/version", "")), 12, CYAN)
	_version_label.name = "RunningVersion"
	_version_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	footer.add_child(_version_label)
	var effects := CheckButton.new()
	_effects = effects
	effects.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), CYAN, 5))
	effects.custom_minimum_size.y = 44
	effects.text = "Reduced motion"
	effects.add_theme_font_size_override("font_size", 13)
	effects.add_theme_color_override("font_color", MUTED)
	effects.toggled.connect(func(enabled: bool) -> void:
		arena.reduced_motion = enabled
		_answer_confetti.reduced_motion = enabled
		_hangar_view.reduced_motion = enabled
		_hangar_view.queue_redraw()
		if is_instance_valid(_mobile_hangar):
			_mobile_hangar.reduced_motion = enabled
			_mobile_hangar.queue_redraw()
		for card in _side.get_children():
			if card is ShipDisplay or card is LootDisplay: card.reduced_motion = enabled)
	footer.add_child(effects)
	_help_button = _button("Help", _open_help)
	_help_button.custom_minimum_size = Vector2(56, 44)
	_help_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_help_button.add_theme_font_size_override("font_size", 13)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := _help_button.get_theme_stylebox(state) as StyleBoxFlat
		style.content_margin_left = 8
		style.content_margin_right = 8
	footer.add_child(_help_button)
	_build_help()
	_answer_confetti = AnswerConfetti.new()
	add_child(_answer_confetti)
	_update_hud()


func _responsive_layout() -> void:
	if not is_instance_valid(_side_panel):
		return
	# The web shell sizes the canvas in CSS pixels, so text remains phone-readable.
	_mobile = size.x < 1000 or size.y < 680
	var document := phase in [Phase.CORE, Phase.BONUS, Phase.BOOST, Phase.REVIVE, Phase.FEEDBACK, Phase.BOOST_INTRO, Phase.STUDY]
	_study_backdrop.visible = document
	for edge in ["left", "right", "top", "bottom"]:
		_margins.add_theme_constant_override("margin_" + edge, 10 if _mobile else 18)
	_page.add_theme_constant_override("separation", 8 if _mobile else 10)
	_header.add_theme_constant_override("separation", 6 if _mobile else 20)
	_brand_title.text = "ESCROW\nINVADERS" if _mobile else "ESCROW INVADERS"
	_brand_title.add_theme_font_size_override("font_size", 16 if _mobile else 28)
	_brand_title.add_theme_constant_override("line_spacing", -2 if _mobile else 0)
	_brand_subtitle.visible = not _mobile
	_sound_button.custom_minimum_size.x = 92 if _mobile else 110
	_sound_button.add_theme_font_size_override("font_size", 13 if _mobile else 17)
	_pause_button.custom_minimum_size.x = 82 if _mobile else 90
	_pause_button.add_theme_font_size_override("font_size", 13 if _mobile else 17)
	for button in [_sound_button, _pause_button]:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var style := button.get_theme_stylebox(state) as StyleBoxFlat
			style.content_margin_left = 8 if _mobile else 16
			style.content_margin_right = 8 if _mobile else 16
	for label in [_hud_wave, _hud_score, _hud_shields, _hud_combo]:
		label.custom_minimum_size.x = 0
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 12 if _mobile else 17)
	_hud_wave.text = "LEVEL %d" % int(progression.state.level)
	_side_panel.custom_minimum_size.x = 0 if _mobile else minf(860, size.x - 36) if document else (365 if size.x < 1200 else 400)
	_side_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if document and not _mobile else Control.SIZE_EXPAND_FILL
	_body.alignment = BoxContainer.ALIGNMENT_CENTER if document else BoxContainer.ALIGNMENT_BEGIN
	_arena_panel.visible = (not _mobile or phase == Phase.COMBAT) and not document
	_side_panel.visible = not _mobile or phase != Phase.COMBAT
	var in_hangar := phase in [Phase.READY, Phase.SHOP, Phase.HANGAR, Phase.STUDY]
	_hangar_view.visible = in_hangar
	arena.visible = not in_hangar
	_combat_bar.visible = not in_hangar
	_pulse_row.visible = phase == Phase.COMBAT
	_controls.visible = not in_hangar
	_loadout.visible = not in_hangar and not (_mobile and size.y < 500)
	if is_instance_valid(_mobile_hangar): _mobile_hangar.visible = _mobile and size.y >= 600
	if in_hangar:
		_hangar_view.level = int(progression.state.level)
		_hangar_view.rank = int(progression.state.rank)
		_hangar_view.drones = int(progression.get_loadout().get("turrets", 1))
		_hangar_view.queue_redraw()
		_arena_title.text = "ORBITAL HANGAR"
		_arena_status.text = "ALL SYSTEMS ONLINE"
	arena.custom_minimum_size = Vector2(0, 100) if _mobile else Vector2(440, 240)
	_arena_title.visible = not _mobile
	_arena_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if _mobile else HORIZONTAL_ALIGNMENT_RIGHT
	_controls.text = "DRAG TO STEER  /  TAP REPULSOR" if _mobile else "WASD / DRAG TO STEER   ·   SPACE: REPULSOR   ·   AUTO-FIRE"
	_controls.visible = not in_hangar and not (_mobile and size.y < 500)
	_wallet_label.visible = not (_mobile and size.y < 500 and phase == Phase.COMBAT)
	if _web_skin:
		_status_row.custom_minimum_size.y = (74 if size.y >= 500 else 44) if _mobile else 62
		_status_row.modulate.a = 0.0
		_wallet_label.hide()
		_brand_title.modulate.a = 0.0
		_brand_subtitle.modulate.a = 0.0
		_arena_title.modulate.a = 0.0
		_arena_status.modulate.a = 0.0
		_pulse_row.modulate.a = 0.0
		_pulse_bar.hide()
	_controls.hide()
	if is_instance_valid(_home_install): _home_install.visible = _mobile
	_side_panel.add_theme_stylebox_override("panel", _style(Color("0c202b") if document else PANEL, Color("396771") if document else EDGE))
	_effects.text = "Less motion" if _mobile else "Reduced motion"
	_effects.add_theme_font_size_override("font_size", 12 if _mobile else 13)
	_save_notice.text = ("SYNCED SAVE" if _cloud != null else "SAVED HERE") if _mobile else (("ORIGINAL SAMPLE MATH" if model.sample_data else model.bank_title.to_upper()) + "  ·  " + _save_scope())
	_save_notice.text = _save_warning() if not _save_warning().is_empty() else _save_notice.text
	_save_notice.add_theme_font_size_override("font_size", 10 if not _mobile else 11)
	if is_instance_valid(_ready_hero):
		_ready_hero.visible = _mobile and size.y >= 600
	if is_instance_valid(_content_title):
		_content_title.add_theme_font_size_override("font_size", (21 if _mobile else 25) if phase in [Phase.CORE, Phase.BONUS, Phase.BOOST, Phase.REVIVE] else (27 if _mobile else 29))
	for button in _answer_buttons:
		button.add_theme_font_size_override("font_size", 17 if _mobile else 18)
		button.custom_minimum_size.y = (48 if phase == Phase.BONUS else 58) if _mobile else 50
	_side.add_theme_constant_override("separation", 10 if _mobile or document or phase in [Phase.READY, Phase.COMBAT] else 13)
	_menu_nav.visible = phase in [Phase.READY, Phase.SHOP, Phase.HANGAR, Phase.STUDY]
	for index in range(_menu_buttons.size()):
		_menu_buttons[index].disabled = phase == [Phase.READY, Phase.SHOP, Phase.HANGAR, Phase.STUDY][index]
		_menu_buttons[index].add_theme_color_override("font_disabled_color", LIME)
		_menu_buttons[index].add_theme_font_size_override("font_size", 13 if _mobile else 15)
		_menu_buttons[index].autowrap_mode = TextServer.AUTOWRAP_OFF
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var style := _menu_buttons[index].get_theme_stylebox(state) as StyleBoxFlat
			style.content_margin_left = 8 if _mobile else 16
			style.content_margin_right = 8 if _mobile else 16
	call_deferred("_sync_web_ui")
	call_deferred("_refresh_action_hotkeys")


func _clear_side() -> void:
	_action_hotkeys.clear()
	for key in ACTION_KEYS:
		if Input.is_key_pressed(key) or Input.is_physical_key_pressed(key): _study_keys_blocked[key] = true
	call_deferred("_responsive_layout")
	# A new question/feedback screen owns keyboard focus. A previously focused
	# Sound/Help button must not consume Enter intended for the new study step.
	if not is_instance_valid(_help_layer) or not _help_layer.visible:
		get_viewport().gui_release_focus()
	_study_generation += 1
	_study_primary = null
	_document_badge = null
	_document_badge_box = null
	_document_seal = ""
	_ready_hero = null
	_mobile_hangar = null
	_home_install = null
	_route_track = null
	_mission_streak = null
	_ability_status = null
	_combat_brief = null
	_diorama = null
	_xp_bar = null
	_rank_progress_label = null
	_xp_caption = null
	_side_scroll.set_deferred("scroll_vertical", 0)
	_answer_buttons.clear()
	_confidence_buttons.clear()
	_hint_label = null
	_numeric = null
	_bonus_label = null
	_bonus_bar = null
	for child in _side.get_children():
		_side.remove_child(child)
		child.queue_free()


func _heading(eyebrow: String, title: String, color: Color = CYAN) -> void:
	var document := phase in [Phase.CORE, Phase.BONUS, Phase.BOOST, Phase.REVIVE, Phase.FEEDBACK, Phase.BOOST_INTRO]
	if document:
		var document_header := HBoxContainer.new()
		document_header.add_theme_constant_override("separation", 10)
		document_header.add_child(_label(eyebrow, 11, color))
		_document_badge_box = PanelContainer.new()
		var seal_style := _style(Color("163039"), CYAN, 2)
		seal_style.content_margin_left = 7
		seal_style.content_margin_right = 7
		seal_style.content_margin_top = 4
		seal_style.content_margin_bottom = 4
		seal_style.shadow_size = 0
		_document_badge_box.add_theme_stylebox_override("panel", seal_style)
		_document_badge_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_document_badge = _label("REVIEW" if phase == Phase.FEEDBACK else "IN ESCROW", 12, CYAN)
		if phase == Phase.BOOST_INTRO and progression.state.get("boost", {}).get("status", "") == "complete":
			_document_badge.text = "FUNDED"
			_document_badge.add_theme_color_override("font_color", GOLD)
		_document_badge.add_theme_font_override("font", Palette.DISPLAY_FONT)
		_document_badge.autowrap_mode = TextServer.AUTOWRAP_OFF
		_document_badge_box.add_child(_document_badge)
		document_header.add_child(_document_badge_box)
		_side.add_child(document_header)
		_document_seal = _document_badge.text
		if _web_skin: _document_badge_box.modulate.a = 0.0
	else:
		_side.add_child(_label(eyebrow, 12, color))
	_content_title = _label(title, 29, WHITE)
	if phase in [Phase.CORE, Phase.BONUS, Phase.BOOST, Phase.REVIVE]:
		_content_title.add_theme_font_override("font", Palette.BODY_FONT)
		_content_title.add_theme_constant_override("line_spacing", 2)
	_side.add_child(_content_title)
	if phase in [Phase.FEEDBACK, Phase.BOOST_INTRO, Phase.BONUS_INTRO]:
		_side.add_child(_label("ENTER / NEXT STEP    TAB / OTHER ACTIONS", 12, CYAN))



func _save_warning() -> String:
	var warnings: Array[String] = []
	for message in [model.progress_warning, progression.progress_warning, journal.warning if journal != null else ""]:
		if not String(message).is_empty() and String(message) not in warnings: warnings.append(String(message))
	return " / ".join(warnings)


func _update_hud() -> void:
	if _answer_count != model.response_receipts.size():
		_answer_count = model.response_receipts.size()
		_answer_totals = model.get_learning_dashboard().totals
	var answered := int(_answer_totals.answered)
	var accuracy := 100.0 * float(_answer_totals.correct) / answered if answered > 0 else 0.0
	_ratio_caption.text = "RIGHT %d : %d WRONG / %s" % [int(_answer_totals.correct), int(_answer_totals.wrong), "%.0f%%" % accuracy if answered > 0 else "NO ANSWERS"]
	_ratio_bar.value = accuracy
	_ratio_bar.modulate = Color.WHITE if answered > 0 else Color("415267")
	_ratio_row.tooltip_text = "All saved first answers, including hinted answers. Skips and retries excluded. Green = right; pink = wrong."
	if is_instance_valid(arena): arena.refresh_ship(progression.get_loadout())
	if is_instance_valid(_evolution_label): _evolution_label.text = _hull_caption()
	score = int(progression.state.total_xp)
	shields = int(progression.state.hull)
	combo = int(progression.state.combo)
	_hud_wave.text = "LEVEL %d" % int(progression.state.level)
	_hud_score.text = "RANK %d" % int(progression.state.rank)
	_hud_combo.text = "%d / %d XP" % [int(progression.state.xp), progression.get_xp_needed()]
	_hud_shields.text = "HEALTH %d / 3" % shields
	if is_instance_valid(_wallet_label):
		_wallet_label.text = "COINS %s     GEMS %s" % [_compact_number(int(progression.state.get("coins", 0))), _compact_number(int(progression.state.get("gems", 0)))]
	_hud_shields.add_theme_color_override("font_color", PINK if shields <= 1 else CYAN)
	if is_instance_valid(_xp_bar):
		_xp_bar.max_value = progression.get_xp_needed()
		_xp_bar.value = int(progression.state.xp)
	if is_instance_valid(_rank_progress_label):
		_rank_progress_label.text = "SHIP RANK %d  /  NEXT %d" % [int(progression.state.rank), int(progression.state.rank) + 1]
	if is_instance_valid(_xp_caption):
		_xp_caption.text = "%d XP to your next FREE upgrade" % (progression.get_xp_needed() - int(progression.state.xp))
	if not _save_warning().is_empty():
		_save_notice.text = _save_warning()
		_save_notice.add_theme_color_override("font_color", GOLD)


func _ship_card(mode: String = "ship", compact: bool = false) -> void:
	var display := ShipDisplay.new()
	display.mode = mode
	display.drones = int(progression.get_loadout().get("turrets", 1))
	display.rank = int(progression.state.rank)
	display.reduced_motion = arena.reduced_motion
	display.custom_minimum_size.y = 112 if compact else 178
	match mode:
		"locked":
			display.title = "TARGET LOCK // ARMOR ONLINE"
			display.subtitle = "YOUR ANSWER IS THE ARMOR BREAKER"
		"independent":
			display.title = "COUNTERSTRIKE // DIRECT HIT"
			display.subtitle = "ARMOR SHATTERED + ATTACK INTERRUPTED"
		"assisted":
			display.title = "ASSISTED COUNTER // ARMOR DOWN"
			display.subtitle = "PARTIAL STRIKE + ATTACK INTERRUPTED"
		"solution":
			display.title = "SUPPORT OVERRIDE // ARMOR DOWN"
			display.subtitle = "REVIEW QUEUED // FIGHT STILL WINNABLE"
		"unlock":
			display.title = "BLUEPRINT DECODED"
			display.subtitle = "PERMANENTLY ADDED TO YOUR HANGAR"
		_:
			display.title = "ORBIT DIVISION // RANK %02d" % int(progression.state.rank)
			display.subtitle = "%d DRONE%s // READY FOR DEPLOYMENT" % [display.drones, "S" if display.drones != 1 else ""]
	_side.add_child(display)
	_diorama = display

func _hull_caption() -> String:
	var rank := int(progression.state.rank)
	var next: int = progression.Evolution.next_rank(rank)
	var stage: int = progression.Evolution.stage(rank)
	return "HULL %d / %d / NEXT EVOLUTION: RANK %d" % [stage, progression.Evolution.RANKS.size(), next] if next > 0 else "ALL %d HULL EVOLUTIONS / SHIP RANK KEEPS GROWING" % progression.Evolution.RANKS.size()

func _answer_reward_card(response: Dictionary) -> void:
	var reward: Dictionary = response.get("answer_reward", {})
	if reward.is_empty(): return
	if int(reward.get("xp", 0)) > 0:
		_side.add_child(_label("+%d XP / +%d COINS / +%d GEMS" % [reward.xp, reward.coins, reward.gems], 17, LIME))
		if int(reward.streak) > 1: _side.add_child(_label("%d CORRECT IN A ROW / STREAK BONUS" % int(reward.streak), 14, GOLD))
		if bool(reward.evolved):
			_side.add_child(_label("SHIP EVOLVED / NEW HULL INSTALLED", 20, CYAN))
			_ship_card("unlock", true)
	else:
		_side.add_child(_label("-%d COINS / ANSWER STREAK RESET" % int(reward.penalty), 16, PINK))


func _info_card(title: String, accent: Color = CYAN) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := _style(Color("122532"), EDGE, 7)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	_side.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	column.add_child(_label(title, 11, accent))
	return column


func _progress_card(compact: bool = false) -> void:
	var next: Dictionary = progression.next_milestone()
	if compact:
		var card := _info_card("NEXT UNLOCK / CLEAR LEVEL %d" % int(next.get("level", 3)), GOLD)
		card.add_child(_label(String(next.get("title", "Frontier technology")), 22, WHITE))
		card.add_child(_label(String(next.get("description", "Push into the next sector.")), 14, MUTED))
		_route_track = SectorTrack.new()
		_route_track.level = int(progression.state.level)
		card.add_child(_route_track)
		return
	_side.add_child(_label("NEXT UNLOCK / CLEAR LEVEL %d" % int(next.get("level", 3)), 12, GOLD))
	_side.add_child(_label(String(next.get("title", "Frontier technology")), 25, WHITE))
	_side.add_child(_label(String(next.get("description", "Push into the next sector.")), 15, MUTED))
	var distance := maxi(0, int(next.get("level", 3)) - int(progression.state.level) + 1)
	_side.add_child(_label("%d CLEAR%s AWAY" % [distance, "S" if distance != 1 else ""], 13, GOLD))
	var route := HBoxContainer.new()
	route.add_theme_constant_override("separation", 5)
	for offset in range(5):
		var sector := int(progression.state.level) + offset
		var box := PanelContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var box_style := _style(Color("172a3d"), LIME if offset == 0 else GOLD if sector % 5 == 0 else EDGE, 5)
		box_style.content_margin_left = 4
		box_style.content_margin_right = 4
		box.add_theme_stylebox_override("panel", box_style)
		var number := _label(("B" if sector % 5 == 0 else "") + str(sector), 12, LIME if offset == 0 else GOLD if sector % 5 == 0 else MUTED)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(number)
		route.add_child(box)
	_side.add_child(route)
	for milestone in ProgressionModel.MILESTONES:
		if int(milestone.level) > int(next.get("level", 0)):
			_side.add_child(_label("ON THE HORIZON  /  %s  ·  L%d" % [String(milestone.title), int(milestone.level)], 12, MUTED))
			break
	_side.add_child(HSeparator.new())
	_rank_progress_label = _label("SHIP RANK %d  /  NEXT %d" % [int(progression.state.rank), int(progression.state.rank) + 1], 13, CYAN)
	_side.add_child(_rank_progress_label)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size.y = 10
	_xp_bar.show_percentage = false
	_xp_bar.max_value = progression.get_xp_needed()
	_xp_bar.value = int(progression.state.xp)
	_xp_bar.add_theme_stylebox_override("fill", _style(LIME, LIME, 3))
	_xp_bar.add_theme_stylebox_override("background", _style(Color("172740"), Color("172740"), 3))
	_side.add_child(_xp_bar)
	_xp_caption = _label("%d XP to your next FREE upgrade" % (progression.get_xp_needed() - int(progression.state.xp)), 14, MUTED)
	_side.add_child(_xp_caption)
	if phase != Phase.READY:
		_evolution_label = _label(_hull_caption(), 14, GOLD)
		_side.add_child(_evolution_label)
	_side.add_child(_label("Correct: 100 XP + streak bonus, 20 coins. Hinted: 40 XP, 8 coins. Every 3-answer streak earns a gem. Miss: up to -15 coins and streak reset. New hulls add damage and fire rate.", 13, MUTED))


func _show_ready() -> void:
	_revive_mode = false
	_boost_mode = false
	phase = Phase.READY
	paused = false
	audio.set_paused(false)
	arena.set_process(true)
	arena.freeze()
	audio.set_combat(false)
	_clear_side()
	_heading("YOUR NEXT FLIGHT / SECTOR %02d" % int(progression.state.level), "Own the frontier.")
	_evolution_label = _label(_hull_caption(), 14, GOLD)
	_side.add_child(_evolution_label)
	_side.add_child(_button(_play_label(), start_run, true))
	_mobile_hangar = HangarDisplay.new()
	_mobile_hangar.compact = true
	_mobile_hangar.rank = int(progression.state.rank)
	_mobile_hangar.drones = int(progression.get_loadout().get("turrets", 1))
	_mobile_hangar.reduced_motion = arena.reduced_motion
	_mobile_hangar.custom_minimum_size.y = 150
	_side.add_child(_mobile_hangar)
	if String(progression.state.get("boost", {}).get("status", "")) == "active":
		_side.add_child(_button("CONTINUE YOUR 3-QUESTION REWARD", _show_boost_intro))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.add_child(_button("UPGRADE SHIP", _show_shop))
	actions.add_child(_button("EQUIP WEAPONS", _show_hangar))
	for action in actions.get_children(): action.add_theme_font_size_override("font_size", 14)
	_side.add_child(actions)
	_side.add_child(_button("STUDY / TOPICS & PROGRESS", _show_study))
	_progress_card(true)
	_side.add_child(_label("%s verified questions / saved on this device" % _compact_number(model.question_bank.size()), 12, MUTED))
	if OS.has_feature("web"):
		_home_install = _button("ADD TO PHONE", _install_app)
		_side.add_child(_home_install)
	if not model.bank_warning.is_empty(): _side.add_child(_label(model.bank_warning, 14, GOLD))
	_pause_button.disabled = true
	_update_hud()


func _install_app() -> void:
	if OS.has_feature("web"): JavaScriptBridge.eval("window.escrowInstall && window.escrowInstall()")


func _play_label() -> String:
	if progression.state.current.get("attempt_status", "") == "defeated": return "REVIVE OR RETRY / LEVEL %d" % int(progression.state.level)
	if int(progression.state.pending_upgrades) > 0: return "CHOOSE FREE UPGRADE & PLAY"
	return "PLAY / LEVEL %d" % int(progression.state.level)


func _navigate_menu(destination: int) -> void:
	if _help_layer.visible or phase not in [Phase.READY, Phase.SHOP, Phase.HANGAR, Phase.STUDY]: return
	match destination:
		0: _show_ready()
		1: _show_shop()
		2: _show_hangar()
		3: _show_study()


func _build_help() -> void:
	_help_layer = Control.new()
	_help_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_help_layer.z_index = 20
	add_child(_help_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.025, 0.06, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_help_layer.add_child(dim)
	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: inset.add_theme_constant_override("margin_" + edge, 12)
	_help_layer.add_child(inset)
	_help_panel = PanelContainer.new()
	_help_panel.add_theme_stylebox_override("panel", _style(PANEL, CYAN))
	inset.add_child(_help_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_help_panel.add_child(column)
	var heading := HBoxContainer.new()
	heading.add_child(_label("QUICK HELP", 20, CYAN))
	_help_close_button = _button("Close", _close_help, true)
	_help_close_button.custom_minimum_size = Vector2(82, 48)
	_help_close_button.autowrap_mode = TextServer.AUTOWRAP_OFF
	_help_close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	heading.add_child(_help_close_button)
	column.add_child(heading)
	var topics := HBoxContainer.new()
	topics.add_theme_constant_override("separation", 6)
	for index in range(3):
		var button := _button(["Play", "Rewards", "Upgrades"][index], _render_help_topic.bind(index))
		button.add_theme_font_size_override("font_size", 14)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var style := button.get_theme_stylebox(state) as StyleBoxFlat
			style.content_margin_left = 6
			style.content_margin_right = 6
		topics.add_child(button)
		_help_topic_buttons.append(button)
	column.add_child(topics)
	var sound_settings := HBoxContainer.new()
	_music_setting = CheckButton.new()
	_music_setting.text = "Music"
	_music_setting.button_pressed = true
	_music_setting.custom_minimum_size.y = 44
	_music_setting.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_music_setting.toggled.connect(func(enabled: bool) -> void: audio.music_enabled = enabled)
	sound_settings.add_child(_music_setting)
	_effects_setting = CheckButton.new()
	_effects_setting.text = "Sound effects"
	_effects_setting.button_pressed = true
	_effects_setting.custom_minimum_size.y = 44
	_effects_setting.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effects_setting.toggled.connect(func(enabled: bool) -> void: audio.effects_enabled = enabled)
	sound_settings.add_child(_effects_setting)
	column.add_child(sound_settings)
	_help_scroll = ScrollContainer.new()
	_help_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_help_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_help_scroll)
	_help_body = VBoxContainer.new()
	_help_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help_body.add_theme_constant_override("separation", 12)
	_help_scroll.add_child(_help_body)
	_help_layer.hide()


func _open_help() -> void:
	if _help_layer.visible: return
	_help_previous_focus = get_viewport().gui_get_focus_owner()
	_help_paused_here = not paused and phase in [Phase.CORE, Phase.FEEDBACK, Phase.COMBAT, Phase.BONUS, Phase.BOOST, Phase.REVIVE]
	if _help_paused_here: _toggle_pause()
	arena.release_steering()
	# Modal pointer blocking is not enough: Tab must stay inside Help too.
	_help_underlay_focus.clear()
	for control in find_children("*", "Control", true, false):
		if control == _help_layer or _help_layer.is_ancestor_of(control): continue
		if control.focus_mode != Control.FOCUS_NONE:
			_help_underlay_focus[control] = control.focus_mode
			control.focus_mode = Control.FOCUS_NONE
	_render_help_topic(2 if phase in [Phase.SHOP, Phase.HANGAR, Phase.UPGRADE] else (1 if _boost_mode or phase in [Phase.CLEAR, Phase.BONUS_INTRO, Phase.SUMMARY] else 0))
	_help_layer.show()
	_help_close_button.grab_focus()
	_action_hotkeys.clear()
	call_deferred("_refresh_action_hotkeys")


func _close_help() -> void:
	if not _help_layer.visible: return
	_help_layer.hide()
	for control in _help_underlay_focus:
		if is_instance_valid(control): control.focus_mode = _help_underlay_focus[control]
	_help_underlay_focus.clear()
	var resume := _help_paused_here
	_help_paused_here = false
	if resume and paused: _toggle_pause()
	if is_instance_valid(_help_previous_focus) and _help_previous_focus.is_visible_in_tree():
		_help_previous_focus.grab_focus()
	else:
		_help_button.grab_focus()
	_action_hotkeys.clear()
	call_deferred("_refresh_action_hotkeys")


func _render_help_topic(topic: int) -> void:
	if topic < 0 or topic > 2: return
	for child in _help_body.get_children():
		_help_body.remove_child(child)
		child.queue_free()
	for index in range(_help_topic_buttons.size()):
		_help_topic_buttons[index].disabled = index == topic
		_help_topic_buttons[index].add_theme_color_override("font_disabled_color", LIME)
	call_deferred("_refresh_action_hotkeys")
	var entries: Array
	match topic:
		0:
			entries = [
				["MOVE & SHOOT", "Drag a finger inside the arena to move. On a computer, use WASD or arrows. Your ship aims and fires automatically."],
				["REPULSOR PULSE", "Press Space or tap Repulsor to clear nearby hostile shots, push enemies away and damage exposed targets. It recharges after 7 seconds of combat. Save it for a tight escape. Armor still needs a question or the skip override."],
				["ANSWER WITH YOUR KEYBOARD", "Press W, A, S or D for answers top to bottom. Up/Down chooses an answer; Enter confirms it. Every action shows its shortcut badge: H hint, K skip and C continue. Answers are final; there are no question retries. G / J / L choose Guessing / Leaning / Sure. Enter still continues feedback; Tab and Shift+Tab reach every control. Page Up/Down scrolls long text. Release held keys before the next step."],
				["CLEAR THE LEVEL", "Avoid enemies and pink shots. Destroy the marked leader and all escorts to advance. The bar below the arena is the leader's health."],
				["BATTLE QUESTION", "The fight pauses while you read. Correct answers break armor, deal extra damage and earn XP and coins. A wrong answer costs 1 health, up to 15 coins and your answer streak. Read the explanation and continue; there is no retry. Skip removes armor without question rewards or penalties."],
				["DEATH & REVIVE", "Answer 1 question correctly to revive with full health, once per attempt. A wrong answer ends that revive chance with no retry. Retry starts the level over; your earned XP, currency and permanent upgrades stay."],
			]
		1:
			entries = [
				["LEVEL VS. RANK", "Level is how far you have fought. Rank grows with XP from enemies, level clears and answers. Every new rank gives you one free permanent upgrade."],
				["COINS & GEMS", "Both come from winning fights. Coins buy Shot Damage and Fire Rate. Gems buy Reactor Speed. Spend them in Upgrades."],
				["3-QUESTION REWARDS", "After a clear, complete 3 untimed questions to double the shown reward. In Upgrades, a 3-question set can cover missing currency: it spends what you have toward that price and study pays the rest."],
				["TIMED BONUS", "An optional 10-second question gives extra firing speed for your next level. The timer starts only when you press Start. Skip or miss with no health penalty."],
				["YOUR LEARNING", "Study lets you select categories, track right and wrong answers, and target weak concepts. Every answer is final. Learning history and game rewards are separate, and progress is saved on this device."],
				["ANSWER REWARDS", "Independent correct answers earn 100 XP and 20 coins. Each next correct answer adds 15 XP, up to 160 total; every third streak answer earns a gem. Hinted answers earn 40 XP and 8 coins and reset the independent streak. Wrong answers earn no answer XP, cost up to 15 coins and reset the streak. These rules apply to battle, bonus, reward and revive answers."],
				["SHIP EVOLUTION", "Ship Rank unlocks ten mystery replacement hulls. Five veteran evolutions await at Ranks 45, 55, 70, 90 and 120. Your physical ship changes in combat and the hangar; each evolution adds 6% base damage and 4% base fire rate. Existing hulls and upgrades stay installed. Home shows your hull progress and the next rank."],
				["ENEMY THREAT", "Enemy health and attack pressure respond to your equipped ship at the start of each encounter. Health grows more slowly than your ship power, so upgrades keep their advantage. A fight never gains health just because you rank up during it. Bosses alternate between five distinct types; their contract cards explain the mechanics."],
			]
		2:
			entries = [
				["UPGRADES: PERMANENT STATS", "Shot Damage makes bullets hit harder. Fire Rate makes the ship and drones shoot more often. Reactor Speed adds a firing-speed multiplier. Purchases apply automatically; no equipping needed."],
				["WEAPONS: CHOOSE YOUR EQUIPMENT", "Clear a weapon's listed level to unlock it. Tap Equip to use it in your next fight, or Remove to free its slot. Equipping is free. A full loadout shows which weapon will be replaced."],
				["WEAPON SLOTS", "Start with 1 extra-weapon slot. Clear Level 10 for a second slot. Your main cannon and orbiting drone work even with no extra weapon equipped."],
				["FREE RANK UPGRADE", "When your XP bar fills, choose one free permanent improvement before continuing. This is separate from buying an upgrade with coins or gems."],
			]
	for entry in entries:
		_help_body.add_child(_label(String(entry[0]), 16, LIME))
		_help_body.add_child(_label(String(entry[1]), 18, WHITE))
		_help_body.add_child(HSeparator.new())
	if topic == 0 and OS.has_feature("web"): _help_body.add_child(_button("ADD TO PHONE", _install_app))
	_help_scroll.set_deferred("scroll_vertical", 0)


func _boost_back_to_shop() -> void:
	if _help_layer.visible or paused or not _boost_mode or _save_problem_open: return
	progression.cancel_boost()
	if not _commit_pending_saves():
		_show_save_problem()
		return
	_show_shop()


func start_run() -> void:
	if phase not in [Phase.READY, Phase.HANGAR, Phase.DEFEAT]: return
	paused = false
	audio.set_paused(false)
	_pause_button.text = "Pause"
	arena.set_process(true)
	audio.play("click")
	if progression.state.current.get("attempt_status", "") == "defeated":
		_show_defeat()
		return
	_route_next()


func _route_next() -> void:
	if phase in [Phase.COMBAT, Phase.CORE, Phase.BONUS, Phase.BOOST, Phase.REVIVE]: return
	_update_hud()
	if not _save_warning().is_empty() and not _commit_pending_saves():
		_show_save_problem()
		return
	if bool(progression.state.get("checkpoint_pending", false)):
		_show_summary()
	elif int(progression.state.pending_upgrades) > 0:
		_show_upgrades()
	elif String(progression.state.get("bonus", {}).get("status", "")) == "pending":
		_show_bonus_intro()
	else:
		_prepare_encounter()


func _prepare_encounter() -> void:
	_revive_mode = false
	_boost_mode = false
	var block: Dictionary = progression.state.get("block", {})
	if block.get("core", []).is_empty() or int(block.get("index", 0)) >= 5:
		model.start_run()
		model.save_progress()
		progression.state.block = {"core": model.core_questions.duplicate(true), "bonus": model.bonus_questions.duplicate(true), "index": 0}
		progression.save_progress()
		block = progression.state.block
	core_index = int(block.get("index", 0))
	var selected: Dictionary = block.core[clampi(core_index, 0, block.core.size() - 1)]
	if progression.state.current.is_empty():
		var excluded: Array = []
		for bonus_question in block.get("bonus", []):
			if not bonus_question.is_empty(): excluded.append(bonus_question.id)
		for boost_question in progression.state.get("boost", {}).get("questions", []): excluded.append(boost_question.id)
		var next: Dictionary = model.select_next_question(excluded)
		if not next.is_empty():
			selected = next
			block.core[core_index] = next
		elif not model.matches_preferences(selected):
			_show_study()
			return
	var encounter: Dictionary = progression.ensure_encounter(selected)
	current_question = encounter.question
	assisted = bool(encounter.get("hint_used", false))
	answer_attempts = int(encounter.get("response", {}).get("attempts", 0))
	confidence = -1
	last_is_bonus = false
	if not _commit_pending_saves():
		_show_save_problem()
		return
	_launch_combat()


func _combat_sidebar() -> void:
	_clear_side()
	var level := int(progression.state.level)
	var mission := _info_card("ACTIVE CONTRACT / BOSS" if level % 5 == 0 else "ACTIVE CONTRACT / SECTOR %02d" % level, PINK if level % 5 == 0 else CYAN)
	mission.add_child(_label("Clear the sector.", 24, WHITE))
	var config: Dictionary = EncounterDirector.config_for(level, int(progression.state.current.get("seed", 1)))
	var matched: Dictionary = EncounterDirector.match_loadout(config, progression.get_loadout())
	mission.add_child(_label("ENEMY HULL x%.2f / MATCHED TO YOUR SHIP" % float(matched.threat.hp_scale), 12, GOLD))
	if not String(config.get("boss_guide", "")).is_empty():
		mission.add_child(_label(String(config.target_name), 17, PINK))
		mission.add_child(_label(String(config.boss_guide), 13, MUTED))
	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 12)
	_combat_brief = _label(str(int(arena.encounter_status().get("remaining", 0))), 44, WHITE)
	_combat_brief.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_combat_brief.custom_minimum_size.x = 78
	_combat_brief.autowrap_mode = TextServer.AUTOWRAP_OFF
	_combat_brief.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_row.add_child(_combat_brief)
	var count_caption := VBoxContainer.new()
	count_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	count_caption.add_child(_label("HOSTILES LEFT", 12, PINK))
	_mission_streak = _label("Destroy the leader + escorts", 13, MUTED)
	count_caption.add_child(_mission_streak)
	count_row.add_child(count_caption)
	mission.add_child(count_row)
	var ability := _info_card("SHIP SYSTEM / DEFENSE", CYAN)
	var ability_heading := HBoxContainer.new()
	ability_heading.add_child(_label("REPULSOR", 20, WHITE))
	_ability_status = _label("READY", 13, LIME)
	_ability_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ability_heading.add_child(_ability_status)
	ability.add_child(ability_heading)
	ability.add_child(_label("Clear nearby shots. Push enemies back.\nSPACE or tap the charge meter.", 14, MUTED))
	_side.add_child(_button("STUDY / TOPICS & PROGRESS", _show_study))
	_progress_card(true)
	_update_hud()


func _launch_combat() -> void:
	phase = Phase.COMBAT
	_pause_button.disabled = false
	_combat_sidebar()
	_arena_status.text = "DEPLOYING"
	audio.set_combat(true)
	call_deferred("_start_arena_encounter")


func _start_arena_encounter() -> void:
	await get_tree().process_frame
	if phase != Phase.COMBAT: return
	var encounter: Dictionary = progression.begin_attempt()
	if not _commit_pending_saves():
		_show_save_problem()
		return
	var config: Dictionary = EncounterDirector.config_for(int(encounter.level), int(encounter.seed))
	var response: Dictionary = encounter.get("response", {})
	var counter := String(response.get("counter", "")) if bool(response.get("resolved", false)) else ""
	arena.launch_encounter(config, progression.get_loadout(), int(progression.state.hull), counter)
	_arena_title.text = "LIVE / SECTOR %02d" % int(progression.state.level)
	audio.play("launch")
	_arena_attempt_id = String(encounter.attempt_id)
	_update_hud()


func _on_question_requested() -> void:
	if phase != Phase.COMBAT: return
	audio.set_combat(false)
	audio.play("lock")
	phase = Phase.CORE
	var encounter: Dictionary = progression.state.current
	current_question = encounter.question
	var response: Dictionary = encounter.get("response", {})
	answer_attempts = int(response.get("attempts", 0))
	assisted = bool(encounter.get("hint_used", false)) or answer_attempts > 0
	if answer_attempts > 0:
		phase = Phase.FEEDBACK
		_render_response(response.get("result", {}))
	else:
		_render_question(false)


func _render_question(is_bonus: bool) -> void:
	_question_elapsed_seconds = 0.0
	_question_timer_running = true
	phase = Phase.REVIVE if _revive_mode else (Phase.BONUS if is_bonus else (Phase.BOOST if _boost_mode else Phase.CORE))
	_clear_side()
	arena.freeze()
	_arena_status.text = "STUDY BOOST // DANGER PAUSED" if _boost_mode else ("BONUS TRANSMISSION" if is_bonus else "TARGET LOCKED // DANGER PAUSED")
	if _revive_mode:
		_arena_status.text = "REVIVE SIGNAL // DANGER PAUSED"
		_heading("ONE CORRECT ANSWER / REVIVE", String(current_question["prompt"]), LIME)
	else:
		_heading("STUDY REWARD / QUESTION %d OF 3" % (_boost_slot + 1) if _boost_mode else ("TIMED BONUS / 10 SECONDS" if is_bonus else "BATTLE QUESTION / BREAK ARMOR"), String(current_question["prompt"]), GOLD if is_bonus or _boost_mode else CYAN)
	if not is_bonus:
		if _revive_mode:
			_side.add_child(_label("Correct = 3 hull + a 2-second shield. Untimed. One revive per attempt.", 15, LIME))
		elif _boost_mode:
			var boost: Dictionary = progression.get_active_boost()
			var prize := UiDescriptions.shop_title(String(boost.get("item", ""))) if boost.get("kind", "") == "upgrade" else "DOUBLE LEVEL REWARDS"
			_side.add_child(_label("WORKING TOWARD: " + prize, 14, GOLD))
			_side.add_child(_label("Untimed. Correct answers earn XP and coins; misses cost up to 15 coins and reset your streak. Every answer is final.", 14, MUTED))
		else:
			_side.add_child(_label("Untimed. Correct: armor break + damage. First miss: -1 health. Skip: armor off, no XP or bonus damage.", 14, CYAN))
			_side.add_child(_button("SKIP QUESTION / KEEP FIGHTING", _skip_core))
	else:
		_bonus_label = _label("10.0 SECONDS", 24, GOLD)
		_side.add_child(_bonus_label)
		_bonus_bar = ProgressBar.new()
		_bonus_bar.max_value = bonus_seconds
		_bonus_bar.value = bonus_remaining
		_bonus_bar.show_percentage = false
		_bonus_bar.custom_minimum_size.y = 9
		_side.add_child(_bonus_bar)
		_side.add_child(_label("Correct = extra firepower + XP + coins. Miss = up to -15 coins + streak reset.", 14, MUTED))
	_side.add_child(_label("W / A / S / D: ANSWER   UP/DOWN: SELECT   ENTER: CONFIRM" + ("   H: HINT" if not is_bonus else ""), 12, CYAN))
	var choices: Array = current_question["choices"]
	for index in range(choices.size()):
		var button := _button("[%s]   %s" % ["WASD"[index], String(choices[index])], submit_choice.bind(index))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_override("font", Palette.BODY_FONT)
		button.add_theme_stylebox_override("normal", _style(Color("142d3a"), Color("3b5865"), 6))
		button.add_theme_stylebox_override("hover", _style(Color("1c4149"), CYAN, 6))
		button.add_theme_stylebox_override("pressed", _style(Color("23545b"), WHITE, 6))
		button.custom_minimum_size.y = 58
		button.add_theme_font_size_override("font_size", 20)
		_side.add_child(button)
		_answer_buttons.append(button)
		button.focus_entered.connect(_reveal_study_control.bind(button))
	if not is_bonus:
		_side.add_child(_label("HOW SURE ARE YOU?  ·  OPTIONAL", 12, MUTED))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		for index in range(3):
			var button := _button(["Guessing", "Leaning", "Sure"][index], _set_confidence.bind(index))
			button.add_theme_font_size_override("font_size", 14)
			row.add_child(button)
			_confidence_buttons.append(button)
		_side.add_child(row)
		var hint_button := _button("Need a hint?  [H]", _show_hint)
		_side.add_child(hint_button)
		_hint_label = _label(String(current_question.get("hint", "")) if assisted else "", 15, GOLD)
		_side.add_child(_hint_label)
		if _revive_mode: _side.add_child(_button("BACK TO DEFEAT", _leave_revive))
	_set_confidence(confidence)
	_update_hud()
	# A movement key held as combat pauses must be released before it can answer.
	_study_keys_blocked.clear()
	for key in ACTION_KEYS + [KEY_W, KEY_A, KEY_S, KEY_D, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_UP, KEY_DOWN]:
		if Input.is_key_pressed(key) or Input.is_physical_key_pressed(key): _study_keys_blocked[key] = true
	call_deferred("_focus_first_answer", _study_generation)


func _reveal_study_control(control: Control) -> void:
	if is_instance_valid(control) and control.is_visible_in_tree() and _side_scroll.is_ancestor_of(control):
		_side_scroll.ensure_control_visible(control)


func _focus_first_answer(generation: int) -> void:
	if generation != _study_generation or paused or _help_layer.visible or _answer_buttons.is_empty(): return
	_answer_buttons[0].grab_focus()
	# Keep the prompt at the top; subsequent keyboard navigation reveals choices.
	_side_scroll.set_deferred("scroll_vertical", 0)


func _set_confidence(value: int) -> void:
	confidence = value
	for index in range(_confidence_buttons.size()):
		var selected_style := _style(Color("23425a") if index == value else Color("14253c"), CYAN if index == value else EDGE, 8)
		selected_style.content_margin_top = 19
		_confidence_buttons[index].add_theme_stylebox_override("normal", selected_style)


func _show_hint() -> void:
	if phase not in [Phase.CORE, Phase.BOOST, Phase.REVIVE] or paused: return
	assisted = true
	if _revive_mode:
		progression.state.current.revive.hint_used = true
	elif _boost_mode:
		if not progression.state.boost.has("hints"): progression.state.boost.hints = {}
		progression.state.boost.hints[str(_boost_slot)] = true
	else:
		progression.state.current.hint_used = true
	progression.save_progress()
	_hint_label.text = String(current_question.get("hint", "Use the rule you remember, then eliminate the choices that do not fit."))
	call_deferred("_reveal_study_control", _hint_label)
	audio.play("click")


func submit_choice(index: int) -> void:
	if _help_layer.visible: return
	if phase not in [Phase.CORE, Phase.BONUS, Phase.BOOST, Phase.REVIVE] or paused: return
	if index < 0 or index >= current_question.get("choices", []).size(): return
	journal.answer_metadata = {"selected_index": index, "elapsed_seconds": _question_elapsed_seconds}
	_submit_answer(index == int(current_question["answer"]))


func _submit_answer(correct: bool, timed_out: bool = false) -> void:
	if _help_layer.visible: return
	if phase not in [Phase.CORE, Phase.BONUS, Phase.BOOST, Phase.REVIVE] or paused: return
	if timed_out: journal.answer_metadata = {"selected_index": -1, "elapsed_seconds": _question_elapsed_seconds}
	_question_timer_running = false
	if _revive_mode:
		_submit_revive(correct)
		return
	if _boost_mode:
		_submit_boost(correct)
		return
	last_is_bonus = phase == Phase.BONUS
	last_correct = correct and not timed_out
	phase = Phase.FEEDBACK
	var counter := "assisted" if answer_attempts > 0 else "independent"
	var result: Dictionary = journal.resolve(current_question, last_correct, assisted, confidence, last_is_bonus, timed_out, counter)
	if result.has("error"):
		_show_save_problem()
		return
	answer_attempts += 1
	arena.hull = int(progression.state.hull)
	if not last_is_bonus:
		var response: Dictionary = progression.state.current.get("response", {})
		if bool(response.get("resolved", false)):
			arena.apply_counter(String(response.get("counter", "solution")))
	audio.play(("bonus" if last_is_bonus else "correct") if last_correct else "wrong")
	_render_response(result)
	if last_correct: _celebrate_answer()
	else: _set_document_seal("WRONG", GOLD if last_is_bonus else PINK)
	_update_hud()


func _celebrate_answer() -> void:
	_set_document_seal("CLEARED", LIME)
	# The committed answer triggers this, never a re-render or a shown solution.
	var area := _side_panel.get_global_rect()
	area.position -= global_position
	if _web_skin:
		_sync_web_ui()
		JavaScriptBridge.eval("window.orbitalUI.celebrate(" + JSON.stringify({"area": [area.position.x, area.position.y, area.size.x, area.size.y], "reduced": arena.reduced_motion}) + ")")
	else:
		_answer_confetti.celebrate(area, arena.reduced_motion)


func _set_document_seal(text: String, tint: Color) -> void:
	_document_seal = text
	if is_instance_valid(_document_badge):
		_document_badge.text = text
		_document_badge.add_theme_color_override("font_color", tint)
		var style := _document_badge_box.get_theme_stylebox("panel") as StyleBoxFlat
		style.border_color = tint
	call_deferred("_sync_web_ui")


func _official_answer_card() -> void:
	var card := _info_card("OFFICIAL ANSWER", CYAN)
	card.add_child(_label("[%s]  %s" % ["WASD"[int(current_question.answer)], String(current_question.choices[int(current_question.answer)])], 18, WHITE))


func _render_response(result: Dictionary) -> void:
	phase = Phase.FEEDBACK
	_clear_side()
	_pause_button.disabled = false
	if last_is_bonus:
		_heading("BONUS RECEIVED" if last_correct else "TRANSMISSION CLOSED", "Extra juice." if last_correct else "Keep the orbit.", GOLD)
		_answer_reward_card(result.get("response", {}))
		_side.add_child(_label(String(current_question.get("explanation", "")), 19))
		_side.add_child(_label("Extra firepower stays through retries until the next sector is cleared." if last_correct else "No bonus firepower. Review this concept in Study.", 16, MUTED))
		_side.add_child(_button("CONTINUE", _route_next, true))
		return
	var response: Dictionary = progression.state.current.get("response", {})
	var fatal := bool(response.get("fatal", false)) and int(progression.state.hull) <= 0
	var resolved := bool(response.get("resolved", false))
	var counter := String(response.get("counter", ""))
	if not resolved:
		# Finish an older saved miss without asking for another answer.
		var final: Dictionary = journal.resolve_solution()
		if final.has("error"):
			_show_save_problem()
			return
		arena.apply_counter("solution")
	_heading("SHIP LOST" if fatal else ("CORRECT / COUNTERSTRIKE" if response.get("first_correct", false) else "INCORRECT / ANSWER RECORDED"), "Hull breached." if fatal else ("Armor. Gone." if response.get("first_correct", false) else "Learn it. Move on."), PINK if fatal or not response.get("first_correct", false) else LIME)
	_ship_card(counter if not counter.is_empty() else "solution", true)
	_answer_reward_card(response)
	_official_answer_card()
	_side.add_child(_label(String(current_question.get("explanation", "")), 19))
	_side.add_child(_label("One answer recorded. A miss stays wrong; future practice targets this concept." if not response.get("first_correct", false) else "Answer saved. Mastery comes from remembering on later days.", 14, MUTED))
	_side.add_child(_button("VIEW DEFEAT" if fatal else "CONTINUE  /  RESUME BATTLE", _show_defeat if fatal else _resume_battle, true))


func _retry_core() -> void:
	return # Submitted answers cannot reopen.


func _show_solution() -> void:
	if phase != Phase.FEEDBACK or paused or _revive_mode: return
	var result: Dictionary = journal.resolve_solution()
	if result.has("error"):
		_show_save_problem()
		return
	arena.apply_counter("solution")
	_render_response(result)
	_update_hud()


func _resume_battle() -> void:
	if phase != Phase.FEEDBACK or paused or _revive_mode: return
	if int(progression.state.hull) <= 0:
		_show_defeat()
		return
	phase = Phase.COMBAT
	_combat_sidebar()
	call_deferred("_resume_after_layout")


func _resume_after_layout() -> void:
	await get_tree().process_frame
	if phase == Phase.COMBAT:
		arena.hull = int(progression.state.hull)
		arena.resume_combat()
		audio.set_combat(true)


func _on_enemy_killed(enemy_id: String, kind: String) -> void:
	var old_rank := int(progression.state.rank)
	var gained: int = progression.grant_kill(enemy_id, kind)
	if gained > 0:
		total_kills += 1
		if int(progression.state.rank) > old_rank: audio.play("upgrade")
	_update_hud()


func _on_shield_hit() -> void:
	if phase != Phase.COMBAT: return
	progression.state.hull = arena.hull
	progression.save_progress()
	audio.play("hit")
	_update_hud()


func _on_combat_finished(stats: Dictionary) -> void:
	if phase != Phase.COMBAT: return
	audio.set_combat(false)
	progression.state.hull = int(stats.get("hull", arena.hull))
	if not bool(stats.get("victory", false)):
		_show_defeat()
		return
	if int(progression.state.level) % 5 == 0:
		progression.state.block.summary = model.get_summary()
	_last_clear = progression.clear_encounter()
	if _last_clear.has("error"):
		_show_save_problem()
		return
	phase = Phase.CLEAR
	arena.celebrate("victory")
	audio.play("finish")
	_clear_side()
	_heading("LEVEL %02d CLEARED" % int(_last_clear.get("level", 1)), "Sector secured.", LIME)
	var unlocks: Array = _last_clear.get("unlocks", [])
	if not unlocks.is_empty(): _ship_card("unlock", true)
	for item in unlocks:
		_side.add_child(_label(String(item.get("title", "NEW BLUEPRINT")), 25, GOLD))
		_side.add_child(_label(String(item.get("description", "Permanent hangar technology unlocked.")), 17, WHITE))
	_side.add_child(_label("+%d XP SAVED / HEALTH REPAIRED" % int(_last_clear.get("xp", 0)), 15, CYAN))
	_loot_card(_last_clear, "loot")
	_side.add_child(_button("ANSWER 3 / DOUBLE REWARDS", _offer_boost.bind("double_clear", ""), true))
	_side.add_child(_button("KEEP REWARDS / NEXT LEVEL", _route_next))
	_side.add_child(_button("UPGRADE SHIP", _show_shop))
	_progress_card()
	_pause_button.disabled = true
	_update_hud()


func _show_defeat() -> void:
	_revive_mode = false
	_boost_mode = false
	phase = Phase.DEFEAT
	arena.freeze()
	audio.set_combat(false)
	progression.mark_defeated()
	_clear_side()
	_heading("OUT OF HEALTH / LEVEL %d" % int(progression.state.level), "Ship down.\nUpgrades kept.", PINK)
	_side.add_child(_label("XP banked. Upgrades kept.", 18, WHITE))
	if not bool(progression.state.current.get("revive_used", false)):
		_side.add_child(_button("REVIVE / ANSWER 1 QUESTION", _start_revive, true))
		_side.add_child(_label("Restore all 3 health with a short shield. Once per attempt. Retry starts this level over.", 16, LIME))
	else:
		_side.add_child(_label("Revive used this attempt. Rebuild for a fresh hull and another chance.", 16, GOLD))
	var response: Dictionary = progression.state.get("current", {}).get("response", {})
	if bool(response.get("skipped", false)):
		_side.add_child(_label("You used the no-study override. No answer was graded and no study reward was earned.", 16, MUTED))
	elif bool(response.get("resolved", false)):
		_side.add_child(_label("Your answer is already recorded. Its counterstrike returns on this retry; it will not be graded or rewarded again.", 16, MUTED))
	_side.add_child(_button("RETRY LEVEL %d / START OVER" % int(progression.state.level), _route_next))
	_side.add_child(_button("CHANGE WEAPONS", _show_hangar))
	_side.add_child(_button("HOME", _show_ready))
	_progress_card()
	_pause_button.disabled = true
	_update_hud()


func _show_upgrades() -> void:
	phase = Phase.UPGRADE
	arena.freeze()
	_clear_side()
	_heading("RANK %d / FREE UPGRADE" % int(progression.state.rank), "Choose one\nfree upgrade.", LIME)
	_side.add_child(_label("You earned enough XP to rank up. Pick one below; no coins or gems needed. It stays after death.", 16, MUTED))
	for choice in progression.upgrade_options():
		_side.add_child(_button(UiDescriptions.rank_title(String(choice.id)), choose_upgrade.bind(String(choice.id)), true))
		_side.add_child(_label(UiDescriptions.rank_effect(String(choice.id), progression.get_loadout()), 15, MUTED))
	_pause_button.disabled = true
	_update_hud()


func choose_upgrade(kind: String) -> void:
	if phase != Phase.UPGRADE or paused: return
	if not progression.choose_upgrade(kind): return
	audio.play("upgrade")
	arena.celebrate("correct")
	_route_next()


func _show_hangar() -> void:
	_revive_mode = false
	_boost_mode = false
	phase = Phase.HANGAR
	arena.freeze()
	_clear_side()
	_heading("WEAPONS / EQUIPMENT", "Choose your\nweapons.", CYAN)
	_side.add_child(_button(_play_label(), start_run, true))
	_side.add_child(_label("%d / %d WEAPON SLOTS USED" % [progression.state.equipped.size(), progression.module_slots()], 16, LIME))
	_side.add_child(_label("Equipping is free. Equipped weapons work automatically in your next fight. Clear the listed level to unlock each weapon.", 16, MUTED))
	for item in progression.module_catalog():
		var key := String(item.id)
		var unlocked := int(progression.state.modules.get(key, 0)) > 0
		var equipped: bool = key in progression.state.equipped
		_side.add_child(HSeparator.new())
		_side.add_child(_label(String(item.title), 21, WHITE))
		_side.add_child(_label(String(item.get("description", "")), 16, MUTED))
		var text := "REMOVE / EQUIPPED" if equipped else "EQUIP WEAPON"
		if not unlocked: text = "LOCKED / CLEAR LEVEL %d" % int(item.get("unlock_level", 1))
		if unlocked and not equipped and progression.state.equipped.size() >= progression.module_slots():
			var replaced := String(progression.state.equipped[0])
			for other in progression.module_catalog():
				if other.id == replaced: replaced = String(other.title)
			_side.add_child(_label("Your slots are full. Equipping this replaces " + replaced + ".", 15, GOLD))
		var button := _button(text, _equip_module.bind(key), unlocked and not equipped)
		button.disabled = not unlocked
		_side.add_child(button)
	_side.add_child(_label("Your main cannon and orbiting drone always fire, even with no extra weapons equipped. A second weapon slot opens after clearing Level 10.", 15, MUTED))
	_pause_button.disabled = true


func _equip_module(key: String) -> void:
	if progression.equip_module(key): audio.play("upgrade")
	_show_hangar()


func _show_bonus_intro() -> void:
	phase = Phase.BONUS_INTRO
	_clear_side()
	var block: Dictionary = progression.state.get("block", {})
	var slot := 0 if int(block.get("index", 0)) == 2 else 1
	var bonuses: Array = block.get("bonus", [])
	var question: Dictionary = bonuses[slot] if slot < bonuses.size() else {}
	# Category changes apply to bonuses that have not been started yet, too.
	if not question.is_empty() and (question.id in model.session_seen or (not model.preferences.categories.is_empty() and model.category_for(question) not in model.preferences.categories)):
		var familiar: Array = []
		var excluded: Array = []
		for core_question in block.get("core", []):
			familiar.append(core_question.concept)
			excluded.append(core_question.id)
		question = model.select_bonus_question(familiar, excluded)
	if question.is_empty():
		progression.skip_bonus()
		_route_next()
		return
	progression.state.bonus.question = question
	progression.save_progress()
	_heading("OPTIONAL / TIMED BONUS", "One question.\n10 seconds.", GOLD)
	_side.add_child(_label("A short question from a familiar concept. Correct answers boost your next sector, including every retry.", 18, WHITE))
	_side.add_child(_label("The timer starts when you tap Start. Skip is free. Miss or timeout: up to -15 coins and streak reset.", 16, MUTED))
	_side.add_child(_button("START 10-SECOND QUESTION", start_bonus, true))
	_side.add_child(_button("SKIP BONUS / KEEP PLAYING", _skip_bonus))
	_pause_button.disabled = true


func start_bonus() -> void:
	if phase != Phase.BONUS_INTRO or paused: return
	current_question = progression.state.bonus.get("question", {})
	if current_question.is_empty():
		_skip_bonus()
		return
	progression.start_bonus(current_question)
	last_is_bonus = true
	last_correct = false
	answer_attempts = 0
	assisted = false
	confidence = -1
	bonus_remaining = bonus_seconds
	if not _commit_pending_saves():
		_show_save_problem()
		return
	_pause_button.disabled = false
	_render_question(true)


func _skip_bonus() -> void:
	if phase != Phase.BONUS_INTRO or paused: return
	progression.skip_bonus()
	_route_next()


func _show_summary(_failed: bool = false) -> void:
	phase = Phase.SUMMARY
	arena.freeze()
	audio.set_combat(false)
	_clear_side()
	var summary: Dictionary = progression.state.get("block", {}).get("summary", model.get_summary())
	_heading("CHECKPOINT // FIVE SECTORS BANKED", ("Five sectors.\nProgress banked." if int(summary.core_answered) == 0 else "Look what\nyou remembered."), LIME)
	_side.add_child(_label("No counterstrike answers this block" if int(summary.core_answered) == 0 else "%d / %d independent first answers" % [int(summary.core_correct), int(summary.core_answered)], 25, WHITE))
	_side.add_child(_label("%d assisted first answers\n%d bonus clears\n%d delayed mastery advances" % [int(summary.core_assisted), int(summary.bonus_correct), int(summary.mastery_advances)], 17, MUTED))
	_side.add_child(HSeparator.new())
	for concept in summary.concepts:
		var good := int(summary.concepts[concept].get("independent_correct", 0)) > 0
		var label := String(concept).trim_prefix(model.bank_id + ":").replace("-", " ").capitalize()
		_side.add_child(_label(("RECALLED  " if good else "REVIEW NEXT  ") + label, 15, LIME if good else GOLD))
	_side.add_child(_label("Full hull restored. Your next block mixes concepts and prioritizes review. The frontier continues at Level %d." % int(progression.state.level), 17, WHITE))
	_side.add_child(_button("CONTINUE  /  LEVEL %d" % int(progression.state.level), _continue_checkpoint, true))
	_side.add_child(_button("DONE FOR NOW", _show_ready))
	_side.add_child(_button("EXPORT ALL PROGRESS", _export_progress))
	_pause_button.disabled = true
	_update_hud()


func _continue_checkpoint() -> void:
	if phase != Phase.SUMMARY: return
	progression.state.block = {}
	progression.acknowledge_checkpoint()
	_route_next()


func _show_save_problem() -> void:
	if not _save_problem_open: _save_return_phase = phase
	_save_problem_open = true
	phase = Phase.FEEDBACK
	arena.freeze()
	audio.set_combat(false)
	_clear_side()
	_heading("SAVE NEEDS ATTENTION", "Keep this\nwindow open.", GOLD)
	_side.add_child(_label(_save_warning(), 17, GOLD))
	_side.add_child(_label("Your progress is held in memory. Retry saving before continuing.", 17, WHITE))
	_side.add_child(_button("RETRY SAVE", _recover_save, true))
	_side.add_child(_button("EXPORT CURRENT PROGRESS", _export_progress))
	_pause_button.disabled = true


func _commit_pending_saves() -> bool:
	if test_mode: return true
	if not journal.recover(): return false
	# A clear, hint, or upgrade may have failed without creating a response journal.
	var learning_saved: bool = model.save_progress()
	var ship_saved: bool = progression.save_progress()
	return learning_saved and ship_saved


func _recover_save() -> void:
	if not _commit_pending_saves():
		_show_save_problem()
		return
	_save_problem_open = false
	if _revive_mode:
		_begin_revive_question()
		return
	if _boost_mode:
		var boost: Dictionary = progression.get_active_boost()
		var response: Dictionary = boost.get("responses", {}).get(str(_boost_slot), {})
		if _save_return_phase == Phase.FEEDBACK and not response.is_empty():
			_render_boost_response(response.get("result", {}))
		elif boost.get("status", "") in ["active", "complete"]:
			_begin_boost_question()
		else:
			_show_boost_intro()
		return
	if _save_return_phase in [Phase.CORE, Phase.BONUS, Phase.BONUS_INTRO, Phase.FEEDBACK] and not current_question.is_empty():
		var target: Dictionary = progression.state.get("bonus" if last_is_bonus else "current", {})
		var response: Dictionary = target.get("response", {})
		if not response.is_empty():
			last_correct = bool(response.get("last_correct", false))
			arena.hull = int(progression.state.hull)
			if not last_is_bonus and bool(response.get("resolved", false)): arena.apply_counter(String(response.get("counter", "solution")))
			_render_response(response.get("result", {}))
			return
		if not target.is_empty():
			_render_question(last_is_bonus)
			return
	phase = Phase.READY
	_route_next()


func _export_progress() -> void:
	var text := JSON.stringify({"schema_version": 3, "preferences": model.preferences, "answer_records": model.response_receipts, "analytics": model.get_learning_dashboard(), "history": model.history, "run": model.get_summary(), "arcade": progression.state, "study_boosts": model.boost_sessions, "revive_sessions": model.revive_sessions, "sample_data": model.sample_data, "bank_id": model.bank_id, "source_url": model.bank_source_url}, "  ")
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), "escrow-invaders-progress.json", "application/json")
	else:
		var file := FileAccess.open("user://progress-export.json", FileAccess.WRITE)
		if file != null:
			file.store_string(text)
			file.close()
			_save_notice.text = "Export saved: " + ProjectSettings.globalize_path("user://progress-export.json")


func _toggle_sound() -> void:
	audio.muted = not audio.muted
	_sound_button.text = "Sound off" if audio.muted else "Sound on"
	if not audio.muted:
		audio.play("click")
		audio.set_combat(phase == Phase.COMBAT and not paused)


func _on_combat_cue(cue: String, _intensity: float) -> void:
	if phase == Phase.COMBAT and not paused and not _help_layer.visible:
		audio.play(cue)


func _activate_pulse() -> void:
	if phase != Phase.COMBAT or paused or _help_layer.visible: return
	arena.activate_pulse()
	_update_pulse_hud()


func _update_pulse_hud() -> void:
	var pulse: Dictionary = arena.pulse_status()
	_pulse_button.disabled = paused or _help_layer.visible or not bool(pulse.ready)
	_pulse_button.text = "REPULSOR / READY" if bool(pulse.ready) else "REPULSOR / %.1fs" % float(pulse.cooldown)
	if paused: _pulse_button.text = "REPULSOR / PAUSED"
	_pulse_bar.value = float(pulse.charge)
	if is_instance_valid(_ability_status):
		_ability_status.text = "PAUSED" if paused else "READY" if bool(pulse.ready) else "%.1fs" % float(pulse.cooldown)
		_ability_status.add_theme_color_override("font_color", LIME if bool(pulse.ready) else CYAN)


func _toggle_pause() -> void:
	if _help_layer.visible: return
	if phase not in [Phase.CORE, Phase.FEEDBACK, Phase.COMBAT, Phase.BONUS, Phase.BOOST, Phase.REVIVE]: return
	paused = not paused
	arena.release_steering()
	_pause_button.text = "Resume" if paused else "Pause"
	_pause_button.icon = preload("res://assets/ui-play.svg") if paused else preload("res://assets/ui-pause.svg")
	arena.set_process(not paused)
	_answer_confetti.set_process(not paused and not _answer_confetti._pieces.is_empty())
	for button in _side.find_children("*", "Button", true, false): button.disabled = paused
	_arena_status.text = "PAUSED // PRESS RESUME" if paused else "DANGER PAUSED" if phase != Phase.COMBAT else "WEAPONS FREE"
	audio.set_combat(phase == Phase.COMBAT and not paused)
	audio.set_paused(paused)
	if phase == Phase.COMBAT: _update_pulse_hud()
	if phase == Phase.COMBAT and _revive_mode and not paused:
		call_deferred("_resume_revive_after_layout")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(_help_layer) and _help_layer.visible:
		_help_paused_here = false # A focus loss requires an explicit Resume after closing Help.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(_pause_button) and phase in [Phase.COMBAT, Phase.BONUS] and not paused: _toggle_pause()


## Shared home-lab save: adopt the server copy before loading when it holds this player's
## progress, then upload each local save so every device continues the same game.
func _cloud_startup() -> void:
	if not OS.has_feature("web") or not bool(JavaScriptBridge.eval("Boolean(window.escrowSync)")):
		return
	_cloud = JavaScriptBridge.get_interface("escrowSync")
	_cloud_state = CloudSave.read_state()
	var remote: Variant = CloudSave._parse(String(_cloud.initial()))
	if remote is Dictionary:
		var action := CloudSave.decide(_cloud_state, CloudSave.local_files(), remote)
		if action == "adopt":
			var error := CloudSave.adopt(remote, _cloud_state)
			_cloud_status = "SYNCED" if error.is_empty() else "SYNC ERROR"
		elif action == "push":
			CloudSave.mark_dirty()
		else:
			_cloud_status = "SYNCED"
	CloudSave.write_state(_cloud_state)


func _save_scope() -> String:
	return "ONE SAVE ON EVERY DEVICE" if _cloud != null else "PROGRESS SAVED LOCALLY"


func _cloud_set_status(status: String) -> void:
	_cloud_status = status
	if is_instance_valid(_version_label):
		var base := "v" + String(ProjectSettings.get_setting("application/config/version", ""))
		_version_label.text = base if status.is_empty() else base + " · " + status


func _cloud_handle_remote(remote: Dictionary) -> void:
	var local := CloudSave.local_files()
	var theirs := CloudSave.remote_files(remote)
	if not theirs.is_empty() and CloudSave.bundle_hash(theirs) == CloudSave.bundle_hash(local):
		_cloud_state.revision = int(remote.get("revision", 0))
		_cloud_state.hash = CloudSave.bundle_hash(local)
		CloudSave.write_state(_cloud_state)
		_cloud_set_status("SYNCED")
		return
	match CloudSave.decide(_cloud_state, local, remote):
		"adopt":
			_cloud_pending_adopt = remote
			_cloud_set_status("NEWER SAVE WAITING")
		"push": CloudSave.mark_dirty()
		_: _cloud_set_status("SYNCED")


func _cloud_tick(delta: float) -> void:
	if _cloud_reloading:
		return
	if not _cloud_pending_adopt.is_empty() and phase in [Phase.READY, Phase.HANGAR, Phase.SHOP, Phase.STUDY, Phase.CLEAR, Phase.DEFEAT]:
		# Another device saved more progress; switch to it from a menu, never mid-mission.
		model.persistence_enabled = false
		progression.persistence_enabled = false
		journal.persistence_enabled = false
		var error := CloudSave.adopt(_cloud_pending_adopt, _cloud_state)
		_cloud_pending_adopt = {}
		if not error.is_empty():
			_cloud_set_status("SYNC ERROR")
			return
		_cloud_reloading = true
		_cloud_set_status("LOADING SAVE")
		# Give the browser time to persist the files before reloading.
		get_tree().create_timer(2.0).timeout.connect(func() -> void: JavaScriptBridge.eval("location.reload()"))
		return
	_cloud_poll -= delta
	_cloud_push_wait -= delta
	if _cloud_poll > 0.0:
		return
	_cloud_poll = 0.5
	var message := String(_cloud.next())
	while not message.is_empty():
		var split := message.find("\n")
		var kind := message.substr(0, split) if split >= 0 else message
		var body: Variant = CloudSave._parse(message.substr(split + 1)) if split >= 0 else null
		if kind == "pushed":
			_cloud_push_in_flight = false
			if body is Dictionary:
				_cloud_state.revision = int(body.get("revision", 0))
				_cloud_state.hash = _cloud_push_hash
				CloudSave.write_state(_cloud_state)
				_cloud_set_status("SYNCED")
		elif kind == "conflict":
			# The server holds newer progress from another device.
			_cloud_push_in_flight = false
			if body is Dictionary: _cloud_handle_remote(body)
		elif kind == "remote":
			# A routine check; ignore it while an upload is still settling.
			if body is Dictionary and not _cloud_push_in_flight: _cloud_handle_remote(body)
		else:
			if _cloud_push_in_flight:
				_cloud_push_in_flight = false
				CloudSave.mark_dirty()
				_cloud_push_wait = 15.0
			_cloud_set_status("OFFLINE" if kind == "offline" else "LOCAL ONLY")
		message = String(_cloud.next())
	if CloudSave.dirty and not _cloud_push_in_flight and _cloud_push_wait <= 0.0 and _cloud_pending_adopt.is_empty():
		CloudSave.dirty = false
		var local := CloudSave.local_files()
		_cloud_push_hash = CloudSave.bundle_hash(local)
		if not local.has("arcade-progress.json") or _cloud_push_hash == String(_cloud_state.hash):
			return
		_cloud_push_in_flight = true
		_cloud_push_wait = 6.0
		_cloud_set_status("SYNCING")
		_cloud.push(CloudSave.push_body(_cloud_state, local))


func _process(delta: float) -> void:
	if _cloud != null: _cloud_tick(delta)
	if _question_timer_running and not paused and not _help_layer.visible and phase in [Phase.CORE, Phase.BONUS, Phase.BOOST, Phase.REVIVE]:
		_question_elapsed_seconds += delta
	if _web_skin:
		_web_ui_clock -= delta
		if _web_ui_clock <= 0.0:
			_web_ui_clock = 0.12
			_sync_web_ui()
	if paused: return
	if phase == Phase.BONUS:
		bonus_remaining = maxf(0.0, bonus_remaining - delta)
		if is_instance_valid(_bonus_label): _bonus_label.text = "%.1f SECONDS" % bonus_remaining
		if is_instance_valid(_bonus_bar): _bonus_bar.value = bonus_remaining
		if bonus_remaining <= 0.0: _submit_answer(false, true)
	elif phase == Phase.COMBAT:
		_hud_tick -= delta
		if _hud_tick > 0: return
		_hud_tick = 0.1
		var status: Dictionary = arena.encounter_status()
		_update_pulse_hud()
		if is_instance_valid(_combat_brief):
			var streak := int(status.get("streak", 0))
			_combat_brief.text = str(int(status.get("remaining", 0)))
			if is_instance_valid(_mission_streak): _mission_streak.text = "%d KILL STREAK" % streak if streak >= 3 else "Destroy the leader + escorts"
		_arena_status.text = "%s  /  %d HOSTILES LEFT" % [String(status.get("target_name", "FRONTIER")), int(status.get("remaining", 0))]
		_combat_bar.max_value = maxf(1, float(status.get("target_max_hp", 100)))
		_combat_bar.value = float(status.get("target_hp", 0))


func _web_rect(control: Control) -> Array:
	if not is_instance_valid(control) or not control.is_visible_in_tree(): return []
	var rect := control.get_global_rect()
	return [rect.position.x - global_position.x, rect.position.y - global_position.y, rect.size.x, rect.size.y]


func _sync_web_ui() -> void:
	if not _web_skin or not is_instance_valid(_help_layer): return
	var status: Dictionary = arena.encounter_status()
	var badge_rect: Array = []
	if is_instance_valid(_document_badge_box) and _side_scroll.get_global_rect().encloses(_document_badge_box.get_global_rect()):
		badge_rect = _web_rect(_document_badge_box)
	var state := {
		"phase": String(Phase.keys()[phase]).to_lower(), "width": size.x, "height": size.y,
		"mobile": _mobile, "reduced": arena.reduced_motion, "paused": paused, "help": _help_layer.visible,
		"hud": _web_rect(_status_row), "logo": _web_rect(_brand_title), "frame": _web_rect(_arena_panel),
		"arena": _web_rect(arena), "side": _web_rect(_side_panel), "pulseRect": _web_rect(_pulse_row), "footer": _web_rect(_footer),
		"level": int(progression.state.level), "rank": int(progression.state.rank), "hull": int(progression.state.hull),
		"xp": int(progression.state.xp), "xpMax": progression.get_xp_needed(),
		"coins": int(progression.state.coins), "gems": int(progression.state.gems),
		"ratioRect": _web_rect(_ratio_row), "right": int(_answer_totals.correct), "wrong": int(_answer_totals.wrong),
		"evolution": progression.get_loadout().evolution,
		"remaining": int(status.get("remaining", 0)), "target": String(status.get("target_name", "")),
		"pulse": arena.pulse_status(), "fps": Engine.get_frames_per_second()
		,"panelOverflow": maxf(0.0, _side.size.y - _side_scroll.size.y)
		,"sealRect": badge_rect, "seal": _document_seal
		,"unlockTitle": String((_last_clear.get("unlocks", []) as Array)[0].get("title", "")) if not (_last_clear.get("unlocks", []) as Array).is_empty() else ""
		,"funded": phase == Phase.BOOST_INTRO and progression.state.get("boost", {}).get("status", "") == "complete"
	}
	JavaScriptBridge.eval("window.orbitalUI && window.orbitalUI.update(" + JSON.stringify(state) + ")")


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var code: int = event.keycode if event.keycode != 0 else event.physical_keycode
		if not event.pressed:
			_study_keys_blocked.erase(code)
			if _study_keys_held.erase(code):
				get_viewport().set_input_as_handled()
			return
		if _study_keys_held.has(code):
			get_viewport().set_input_as_handled()
			return
		if _handle_action_key(event):
			_study_keys_held[code] = true
			get_viewport().set_input_as_handled()
			return
		if _handle_study_key(event):
			_study_keys_held[code] = true
			get_viewport().set_input_as_handled()
			return
	# Space stays a combat action even after the player focused Pause or Sound.
	if event is InputEventKey and event.keycode == KEY_SPACE and event.pressed and not event.echo and phase == Phase.COMBAT and not paused and not _help_layer.visible:
		_activate_pulse()
		get_viewport().set_input_as_handled()


func _handle_study_key(event: InputEventKey) -> bool:
	if paused or _help_layer.visible or not event.pressed: return false
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return false
	var answering := phase in [Phase.CORE, Phase.BONUS, Phase.BOOST, Phase.REVIVE]
	var reading := phase in [Phase.FEEDBACK, Phase.BOOST_INTRO, Phase.BONUS_INTRO]
	if not answering and not reading: return false
	var code: int = event.keycode if event.keycode != 0 else event.physical_keycode
	var answer_keys := [KEY_W, KEY_A, KEY_S, KEY_D]
	var recognized := code in answer_keys or code in [KEY_UP, KEY_DOWN, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_H, KEY_PAGEUP, KEY_PAGEDOWN]
	if not recognized: return false
	if event.echo or _study_keys_blocked.has(code): return true
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit: return false
	if code in [KEY_PAGEUP, KEY_PAGEDOWN]:
		_side_scroll.scroll_vertical += int(_side_scroll.size.y * 0.8) * (1 if code == KEY_PAGEDOWN else -1)
		return true
	# Space belongs to the combat pulse; it must never answer as danger pauses.
	if code == KEY_SPACE: return true
	if answering:
		if code in answer_keys:
			submit_choice(answer_keys.find(code))
			return true
		if code in [KEY_UP, KEY_DOWN] and not _answer_buttons.is_empty():
			var selected := _answer_buttons.find(focused)
			selected = posmod(selected + (1 if code == KEY_DOWN else -1), _answer_buttons.size()) if selected >= 0 else (0 if code == KEY_DOWN else _answer_buttons.size() - 1)
			_answer_buttons[selected].grab_focus()
			_reveal_study_control(_answer_buttons[selected])
			return true
		if code == KEY_H and phase != Phase.BONUS:
			_show_hint()
			return true
	if code in [KEY_ENTER, KEY_KP_ENTER]:
		# Tab-selected secondary actions keep normal Enter semantics.
		if focused is Button and _side.is_ancestor_of(focused) and not focused.disabled:
			focused.pressed.emit()
			return true
		if is_instance_valid(focused): return false
		if reading and is_instance_valid(_study_primary) and not _study_primary.disabled:
			_study_primary.pressed.emit()
			return true
		if answering and not _answer_buttons.is_empty():
			_answer_buttons[0].grab_focus()
			return true
	return false


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo(): return
	if _help_layer.visible:
		if event is InputEventKey and event.keycode == KEY_ESCAPE: _close_help()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and _handle_study_key(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.keycode == KEY_SPACE and phase == Phase.COMBAT and not paused:
		_activate_pulse()
		get_viewport().set_input_as_handled()

func _compact_number(value: int) -> String:
	if value >= 1000000: return "%.1fm" % (float(value) / 1000000.0)
	if value >= 10000: return "%.1fk" % (float(value) / 1000.0)
	return str(value)


func _loot_card(reward: Dictionary, mode: String = "loot", progress: int = 0) -> void:
	var display := LootDisplay.new()
	display.coins = int(reward.get("coins", 0))
	display.gems = int(reward.get("gems", 0))
	display.xp = int(reward.get("xp", 0))
	display.mode = mode
	display.progress = progress
	display.reduced_motion = arena.reduced_motion
	_side.add_child(display)


func _skip_core() -> void:
	if phase != Phase.CORE or paused or _boost_mode: return
	var result: Dictionary = journal.skip_core()
	if result.has("error"):
		_show_save_problem()
		return
	phase = Phase.FEEDBACK
	arena.apply_counter("solution")
	_resume_battle()


func _show_shop() -> void:
	_revive_mode = false
	_boost_mode = false
	phase = Phase.SHOP
	arena.freeze()
	audio.set_combat(false)
	_clear_side()
	_heading("UPGRADES / ALWAYS ACTIVE", "Make your\nship stronger.", GOLD)
	_side.add_child(_button(_play_label(), _shop_deploy))
	_side.add_child(_label("Buy with battle rewards. Short on coins or gems? Answer 3 questions to cover the difference. Every upgrade is permanent and applies automatically.", 16, MUTED))
	var boost: Dictionary = progression.get_active_boost()
	if String(boost.get("status", "")) == "active":
		_side.add_child(_button("CONTINUE STUDY REWARD / %d OF 3" % mini(3, int(boost.get("index", 0)) + 1), _show_boost_intro, true))
	for item in progression.shop_options():
		_side.add_child(HSeparator.new())
		_side.add_child(_label("%s / %s" % [UiDescriptions.shop_title(String(item.id)), "MAXED" if bool(item.get("maxed", false)) else "NEXT: TIER %d" % (int(item.get("rank", 0)) + 1)], 21, WHITE))
		_side.add_child(_label(UiDescriptions.shop_effect(String(item.id), progression.get_loadout()), 16, MUTED))
		if not bool(item.get("maxed", false)):
			_side.add_child(_label("COST %s %s / YOU HAVE %s" % [_compact_number(int(item.cost)), String(item.currency).to_upper(), _compact_number(int(progression.state[item.currency]))], 15, GOLD))
		if bool(item.get("maxed", false)):
			_side.add_child(_label("MAXED // FULL REACTOR OUTPUT", 16, LIME))
		elif bool(item.get("locked", false)):
			_side.add_child(_button("CONTINUE THIS STUDY REWARD", _show_boost_intro, true))
		elif bool(item.get("affordable", false)):
			_side.add_child(_button("BUY / %s %s" % [_compact_number(int(item.cost)), String(item.currency).to_upper()], _buy_shop_upgrade.bind(String(item.id)), true))
		else:
			if String(boost.get("status", "")) == "active":
				_side.add_child(_label("Finish your current study reward before starting another.", 15, GOLD))
			else:
				_side.add_child(_button("ANSWER 3 QUESTIONS / UPGRADE", _offer_boost.bind("upgrade", String(item.id)), true))
	_pause_button.disabled = true
	_update_hud()


func _shop_deploy() -> void:
	phase = Phase.READY
	start_run()


func _buy_shop_upgrade(key: String) -> void:
	if phase != Phase.SHOP or paused: return
	if progression.buy_upgrade(key):
		audio.play("upgrade")
		arena.celebrate("correct")
	_show_shop()


func _offer_boost(kind: String, item: String = "") -> void:
	var offer: Dictionary = progression.create_boost_offer(kind, item)
	if offer.has("error"):
		if String(progression.get_active_boost().get("status", "")) == "active":
			_show_boost_intro()
		else:
			_side.add_child(_label(String(offer.error), 16, GOLD))
		return
	_show_boost_intro()


func _show_boost_intro() -> void:
	_revive_mode = false
	phase = Phase.BOOST_INTRO
	_boost_mode = true
	arena.freeze()
	audio.set_combat(false)
	_clear_side()
	var boost: Dictionary = progression.get_active_boost()
	if boost.is_empty():
		_show_shop()
		return
	if boost.get("status", "") == "complete":
		_show_boost_complete()
		return
	var upgrade := String(boost.get("kind", "")) == "upgrade"
	_heading("STUDY REWARD / 3 QUESTIONS", "Earn your\nship upgrade." if upgrade else "Double your\nlevel rewards.", GOLD)
	var reward: Dictionary = boost.get("reward", {})
	if upgrade:
		var quote: Dictionary = boost.get("quote", {})
		var currency := String(quote.get("currency", "coins"))
		var price := int(quote.get("cost", 0))
		var contribution := mini(price, int(progression.state.get(currency, 0)))
		_side.add_child(_label("PRICE: %d %s\nYOU HAVE: %d  /  STUDY COVERS: %d" % [price, currency.to_upper(), contribution, price - contribution], 16, GOLD))
	else:
		_loot_card(reward, "boost", int(boost.get("index", 0)))
	if upgrade:
		var item_title := UiDescriptions.shop_title(String(boost.get("item", "upgrade")))
		_side.add_child(_label(item_title, 25, LIME))
		_side.add_child(_label("Complete 3 questions to install this upgrade. Your available currency goes toward its price; studying covers the rest.", 18, WHITE))
	else:
		_side.add_child(_label("Your original reward is already saved. Complete 3 questions to receive the same amount again, once.", 18, WHITE))
	_side.add_child(_label("No timer. Each correct answer earns XP and coins; a miss costs up to 15 coins and resets your streak. Read the official explanation, then continue.", 16, MUTED))
	_side.add_child(_button("CONTINUE QUESTIONS" if boost.get("status", "") == "active" else "START 3 QUESTIONS", _start_study_boost, true))
	_side.add_child(_button("BACK TO UPGRADES", _boost_back_to_shop))
	_side.add_child(_button("SAVE FOR LATER / PLAY", _leave_boost))
	_pause_button.disabled = true


func _start_study_boost() -> void:
	if phase != Phase.BOOST_INTRO or paused: return
	var boost: Dictionary = progression.get_active_boost()
	if boost.get("status", "") != "active":
		var questions: Array[Dictionary] = []
		var excluded: Array = []
		for question in progression.state.get("block", {}).get("core", []): excluded.append(question.id)
		for index in range(3):
			var question: Dictionary = model.select_next_question(excluded)
			if question.is_empty():
				_side.add_child(_label("No fresh questions available in this set. Continue playing to your next checkpoint or choose more categories.", 15, GOLD))
				return
			questions.append(question)
			excluded.append(question.id)
		if not progression.start_boost(questions): return
	if not _commit_pending_saves():
		_show_save_problem()
		return
	_begin_boost_question()


func _begin_boost_question() -> void:
	var boost: Dictionary = progression.get_active_boost()
	if boost.get("status", "") == "complete":
		_show_boost_complete()
		return
	_boost_mode = true
	last_is_bonus = false
	_boost_slot = int(boost.get("index", 0))
	current_question = boost.questions[_boost_slot]
	var response: Dictionary = boost.get("responses", {}).get(str(_boost_slot), {})
	answer_attempts = int(response.get("attempts", 0))
	assisted = answer_attempts > 0 or bool(boost.get("hints", {}).get(str(_boost_slot), false))
	confidence = -1
	_pause_button.disabled = false
	if answer_attempts > 0 and not bool(response.get("resolved", false)):
		_render_boost_response(response.get("result", {}))
	else:
		_render_question(false)


func _submit_boost(correct: bool) -> void:
	if phase != Phase.BOOST or paused: return
	phase = Phase.FEEDBACK
	last_correct = correct
	var stage := "assisted" if answer_attempts > 0 else "independent"
	var result: Dictionary = journal.resolve_boost(current_question, correct, assisted, confidence, stage)
	if result.has("error"):
		_show_save_problem()
		return
	answer_attempts += 1
	audio.play("correct" if correct else "wrong")
	_render_boost_response(result)
	if correct: _celebrate_answer()
	else: _set_document_seal("WRONG", PINK)
	_update_hud()


func _render_boost_response(result: Dictionary) -> void:
	phase = Phase.FEEDBACK
	_boost_mode = true
	_clear_side()
	var boost: Dictionary = progression.get_active_boost()
	var response: Dictionary = boost.get("responses", {}).get(str(_boost_slot), {})
	var resolved := bool(response.get("resolved", false))
	_heading("STUDY BOOST // %d OF 3" % (_boost_slot + 1), "One step closer." if resolved else "Work the rule.", LIME if resolved else GOLD)
	if not resolved:
		# Older pending feedback is completed as a solution exposure, never a retry.
		var final: Dictionary = journal.resolve_boost(current_question, false, true, -1, "solution")
		if final.has("error"):
			_show_save_problem()
			return
		boost = progression.get_active_boost()
	_loot_card(_boost_preview(boost), "boost", int(boost.get("index", 0)))
	_answer_reward_card(response)
	_official_answer_card()
	_side.add_child(_label(String(current_question.get("explanation", "")), 19, WHITE))
	_side.add_child(_label("CORRECT / answer saved" if response.get("first_correct", false) else "INCORRECT / recorded as wrong. No retry.", 16, LIME if response.get("first_correct", false) else PINK))
	_side.add_child(_button("CLAIM YOUR BOOST" if int(boost.get("index", 0)) >= 3 else "NEXT QUESTION", _continue_boost, true))
	_side.add_child(_button("SAVE QUESTIONS / KEEP PLAYING", _leave_boost))
	_side.add_child(_button("BACK TO UPGRADES", _boost_back_to_shop))
	_pause_button.disabled = false


func _retry_boost() -> void:
	return # Submitted answers cannot reopen.


func _boost_solution() -> void:
	if phase != Phase.FEEDBACK or paused: return
	var result: Dictionary = journal.resolve_boost(current_question, false, true, -1, "solution")
	if result.has("error"):
		_show_save_problem()
		return
	_render_boost_response(result)


func _continue_boost() -> void:
	if phase != Phase.FEEDBACK or paused: return
	_begin_boost_question()


func _show_boost_complete() -> void:
	phase = Phase.BOOST_INTRO
	_boost_mode = false
	_clear_side()
	var boost: Dictionary = progression.get_active_boost()
	var upgrade: bool = boost.get("kind", "") == "upgrade"
	_heading("THREE REVIEWS COMPLETE", "Upgrade installed." if upgrade else "Loot doubled.", LIME)
	if upgrade: _ship_card("unlock")
	else: _loot_card(boost.get("reward", {}), "boost", 3)
	_side.add_child(_label("Your permanent build just got stronger." if upgrade else "The extra coins, gems, and XP are banked. Your next upgrade is closer.", 19, WHITE))
	var summary: Dictionary = model.get_boost_summary(String(boost.get("id", "")))
	_side.add_child(_label("%d / %d independent first answers\n%d assisted first answers  /  %d delayed mastery advances" % [int(summary.get("core_correct", 0)), int(summary.get("core_answered", 0)), int(summary.get("core_assisted", 0)), int(summary.get("mastery_advances", 0))], 16, MUTED))
	_side.add_child(_button("BACK TO UPGRADES" if upgrade else "CONTINUE", _show_shop if upgrade else _finish_boost_to_game, true))
	_side.add_child(_button("BACK TO BASE", _show_ready))
	arena.celebrate("bonus")
	audio.play("bonus")
	_pause_button.disabled = true
	_update_hud()


func _finish_boost_to_game() -> void:
	_boost_mode = false
	phase = Phase.READY
	_route_next()


func _leave_boost() -> void:
	progression.cancel_boost()
	_boost_mode = false
	phase = Phase.READY
	_route_next()


func _boost_preview(boost: Dictionary) -> Dictionary:
	if boost.get("kind", "") == "upgrade":
		var quote: Dictionary = boost.get("quote", {})
		var preview := {"coins": 0, "gems": 0, "xp": 0}
		preview[String(quote.get("currency", "coins"))] = int(quote.get("cost", 0))
		return preview
	return boost.get("reward", {})


func _start_revive() -> void:
	if phase != Phase.DEFEAT or paused or bool(progression.state.current.get("revive_used", false)): return
	_revive_mode = true
	_boost_mode = false
	var saved: Dictionary = progression.state.current.get("revive", {})
	if saved.is_empty():
		var excluded: Array = [progression.state.current.question.id]
		for question in progression.state.get("boost", {}).get("questions", []): excluded.append(question.id)
		var question: Dictionary = model.select_next_question(excluded)
		if question.is_empty():
			_revive_mode = false
			return
		var started: Dictionary = progression.start_revive(question)
		if started.is_empty() or started.has("error"):
			if not _save_warning().is_empty(): _show_save_problem()
			else: _show_defeat()
			return
	if not _commit_pending_saves():
		_show_save_problem()
		return
	_begin_revive_question()


func _begin_revive_question() -> void:
	var revive: Dictionary = progression.state.current.get("revive", {})
	if revive.is_empty():
		_show_defeat()
		return
	# A retry screen saved by an older release becomes final feedback.
	if revive.get("status", "") == "active" and int(revive.get("submission", 0)) > 0:
		revive.status = "feedback"
		progression.state.current.revive = revive
		if not _commit_pending_saves():
			_show_save_problem()
			return
	_revive_mode = true
	_boost_mode = false
	last_is_bonus = false
	current_question = revive.question
	answer_attempts = int(revive.get("submission", 0))
	assisted = bool(revive.get("hint_used", false)) or answer_attempts > 0
	confidence = -1
	_pause_button.disabled = false
	if revive.get("status", "") in ["feedback", "earned", "claimed"]:
		_render_revive_response()
	else:
		_render_question(false)


func _submit_revive(correct: bool) -> void:
	if phase != Phase.REVIVE or paused: return
	phase = Phase.FEEDBACK
	var result: Dictionary = journal.resolve_revive(current_question, correct, assisted, confidence)
	if result.has("error"):
		_show_save_problem()
		return
	audio.play("correct" if correct else "wrong")
	_render_revive_response()
	if correct: _celebrate_answer()
	else: _set_document_seal("WRONG", PINK)
	_update_hud()


func _render_revive_response() -> void:
	phase = Phase.FEEDBACK
	_revive_mode = true
	arena.freeze()
	_clear_side()
	var revive: Dictionary = progression.state.current.get("revive", {})
	var earned: bool = revive.get("status", "") in ["earned", "claimed"]
	_heading("REVIVE EARNED" if earned else "REVIVE MISSED / INCORRECT", "Back from\nthe brink." if earned else "Answer recorded.", LIME if earned else GOLD)
	_answer_reward_card(revive.get("response", {}))
	if earned:
		_official_answer_card()
		_side.add_child(_label(String(current_question.get("explanation", "")), 19, WHITE))
		_side.add_child(_label("RESTORE 3 HULL / 2-SECOND RETURN SHIELD", 17, LIME))
		var live_fight := _arena_attempt_id == String(progression.state.current.get("attempt_id", ""))
		_side.add_child(_label("The enemies keep their remaining health. Your fight resumes where you fell." if live_fight else "After closing the game, this sector restarts. Your saved answer and earned rewards stay recorded; defeated enemies cannot pay twice.", 16, MUTED))
		_side.add_child(_button("REVIVE / RETURN TO BATTLE", _resume_revive, true))
	else:
		_official_answer_card()
		_side.add_child(_label(String(current_question.get("explanation", "")), 19, WHITE))
		_side.add_child(_label("Your answer is wrong and final. No revive earned. Rebuild the ship to play again.", 17, PINK))
		_side.add_child(_button("BACK TO DEFEAT", _leave_revive, true))
	_pause_button.disabled = false
	_update_hud()


func _retry_revive() -> void:
	return # Submitted answers cannot reopen.


func _leave_revive() -> void:
	if not _revive_mode or paused or _save_problem_open: return
	if not _commit_pending_saves():
		_show_save_problem()
		return
	_show_defeat()


func _resume_revive() -> void:
	if phase != Phase.FEEDBACK or not _revive_mode or paused: return
	var revive: Dictionary = progression.state.current.get("revive", {})
	if revive.get("status", "") == "earned":
		if not progression.claim_revive():
			_show_save_problem()
			return
	elif revive.get("status", "") != "claimed":
		return
	if not _commit_pending_saves():
		_show_save_problem()
		return
	phase = Phase.COMBAT
	paused = false
	_pause_button.text = "Pause"
	_pause_button.disabled = false
	_combat_sidebar()
	call_deferred("_resume_revive_after_layout")


func _resume_revive_after_layout() -> void:
	await get_tree().process_frame
	if phase != Phase.COMBAT or not _revive_mode or paused: return
	var encounter: Dictionary = progression.state.current
	var response: Dictionary = encounter.get("response", {})
	var counter := String(response.get("counter", "")) if bool(response.get("resolved", false)) else ""
	if _arena_attempt_id == String(encounter.attempt_id):
		if not arena.revive_encounter(int(progression.state.hull)):
			# Leave the earned receipt available if the live arena cannot resume.
			_render_revive_response()
			return
		if not counter.is_empty():
			arena.apply_counter(counter)
			if not arena.combat_active: arena.resume_combat()
	else:
		# A closed window has no live arena; keep the same attempt and kill receipts.
		var config: Dictionary = EncounterDirector.config_for(int(encounter.level), int(encounter.seed))
		arena.launch_encounter(config, progression.get_loadout(), int(progression.state.hull), counter)
		arena._invulnerability = 2.0
		arena._resume_remaining = 0.6
		_arena_attempt_id = String(encounter.attempt_id)
	_revive_mode = false
	current_question = encounter.question
	answer_attempts = int(response.get("attempts", 0))
	assisted = bool(encounter.get("hint_used", false)) or answer_attempts > 0
	last_is_bonus = false
	arena.set_process(true)
	audio.play("revive")
	audio.set_combat(true)
	_update_hud()


func _show_study() -> void:
	phase = Phase.STUDY
	arena.freeze()
	audio.set_combat(false)
	_clear_side()
	_heading("YOUR STUDY DESK", "Choose your focus.", CYAN)
	_side.add_child(_label("Pick course categories for new battle, reward and bonus questions. Saved questions already in progress keep their original category.", 16, MUTED))
	var adaptive := CheckButton.new()
	adaptive.text = "Adaptive practice"
	_style_study_toggle(adaptive)
	adaptive.button_pressed = bool(model.preferences.adaptive)
	adaptive.toggled.connect(_change_adaptive)
	_side.add_child(adaptive)
	_side.add_child(_label("Adaptive practice favors weaker concepts and due reviews, using different questions before repeating recently seen ones. Mixed practice samples your selected categories without weakness weighting.", 14, MUTED))
	var categories: Dictionary = model.available_categories()
	var names := categories.keys()
	names.sort()
	for category in names:
		var toggle := CheckButton.new()
		toggle.text = "%s (%d)" % [category, categories[category]]
		_style_study_toggle(toggle)
		toggle.add_theme_font_size_override("font_size", 14)
		toggle.button_pressed = model.preferences.categories.is_empty() or category in model.preferences.categories
		toggle.disabled = toggle.button_pressed and (model.preferences.categories.size() == 1 or categories.size() == 1)
		toggle.toggled.connect(_change_category.bind(String(category)))
		_side.add_child(toggle)
	_side.add_child(_button("SELECT ALL CATEGORIES", _select_all_categories))
	_side.add_child(_label("%d questions in your selection / one answer per question, no retries." % model.eligible_questions().size(), 14, CYAN))
	var dashboard: Dictionary = model.get_learning_dashboard()
	var totals: Dictionary = dashboard.totals
	var card := _info_card("YOUR ANSWER RECORD", LIME)
	card.add_child(_label("%d RIGHT / %d WRONG" % [totals.correct, totals.wrong], 23, WHITE))
	card.add_child(_label("%d answered / %s accuracy" % [totals.answered, ("%.0f%%" % (100.0 * float(totals.correct) / float(totals.answered))) if totals.answered > 0 else "no answers yet"], 17, CYAN))
	card.add_child(_label("%d independently correct / %d with hints / %d timed out" % [totals.independent, totals.assisted, totals.timeouts], 14, MUTED))
	if int(totals.timed_answers) > 0:
		card.add_child(_label("%.1fs average answer time" % (float(totals.seconds) / float(totals.timed_answers)), 14, MUTED))
	_side.add_child(_label("All saved first answers count, including battle, reward and revive questions. Hinted correct answers count as right and are marked assisted. Skips and old retries are excluded. Earlier records may lack question details.", 14, MUTED))
	_side.add_child(_button("EXPORT ALL PROGRESS", _export_progress))
	_side.add_child(_label("Saved in this browser on this device. Export keeps your full answer history and settings.", 14, MUTED))
	_side.add_child(_label("FOCUS NEXT", 18, GOLD))
	if dashboard.weaknesses.is_empty():
		_side.add_child(_label("Answer a few questions to discover which topics need practice.", 15, MUTED))
	for index in range(mini(5, dashboard.weaknesses.size())):
		var row: Dictionary = dashboard.weaknesses[index]
		_side.add_child(_label("%s / %d right, %d wrong / %.0f%%" % [String(row.concept).trim_prefix(model.bank_id + ":").replace("-", " ").capitalize(), row.correct, row.wrong, float(row.accuracy) * 100.0], 15, GOLD))
	_side.add_child(_label("BY CATEGORY", 18, CYAN))
	for category in dashboard.categories:
		var row: Dictionary = dashboard.categories[category]
		_side.add_child(_label("%s
%d right / %d wrong / %.0f%%" % [category, row.correct, row.wrong, 100.0 * float(row.correct) / float(row.answered)], 15, WHITE))
	_side.add_child(_label("ALL TOPIC RESULTS", 18, CYAN))
	var topics: Array = dashboard.topics.keys()
	topics.sort()
	for concept in topics:
		var row: Dictionary = dashboard.topics[concept]
		var memory: Dictionary = model.history.concepts.get(concept, {})
		_side.add_child(_label("%s / %d right / %d wrong / %.0f%%" % [String(concept).trim_prefix(model.bank_id + ":").replace("-", " ").capitalize(), row.correct, row.wrong, 100.0 * float(row.correct) / float(row.answered)], 15, WHITE))
		_side.add_child(_label("Memory stage %d of 3 / %s" % [int(memory.get("mastery_stage", 0)), "needs review" if memory.get("needs_review", false) else "continue spaced practice"], 12, MUTED))
	_side.add_child(_label("BY ACTIVITY", 18, CYAN))
	for context in dashboard.contexts:
		var row: Dictionary = dashboard.contexts[context]
		_side.add_child(_label("%s / %d right / %d wrong" % [String(context).capitalize(), row.correct, row.wrong], 15, MUTED))
	_side.add_child(_label("RECENT STUDY DAYS (UTC)", 18, CYAN))
	var dates: Array = dashboard.days.keys()
	dates.sort()
	dates.reverse()
	for index in range(mini(7, dates.size())):
		var row: Dictionary = dashboard.days[dates[index]]
		_side.add_child(_label("%s / %d answered / %.0f%% right" % [dates[index], row.answered, 100.0 * float(row.correct) / float(row.answered)], 14, MUTED))
	_side.add_child(_label("LAST 25 ANSWERS", 18, CYAN))
	for index in range(mini(25, dashboard.recent.size())):
		var entry: Dictionary = dashboard.recent[index]
		var item := _info_card(("RIGHT" if entry.get("correct", false) else "WRONG") + " / " + String(entry.get("context", "earlier practice")).to_upper(), LIME if entry.get("correct", false) else PINK)
		item.add_child(_label(Time.get_datetime_string_from_unix_time(int(entry.recorded_at)).replace("T", " ") + " UTC" if int(entry.get("recorded_at", 0)) > 0 else "Date unavailable in earlier record", 12, MUTED))
		item.add_child(_label(String(entry.get("prompt", "Earlier answer: detailed question record unavailable.")), 15, WHITE))
		if entry.has("choices"):
			var selected := int(entry.get("selected_index", -1))
			item.add_child(_label("Your answer: " + (String(entry.choices[selected]) if selected >= 0 and selected < entry.choices.size() else "No answer / timeout"), 14, WHITE))
			item.add_child(_label("Correct: " + String(entry.choices[int(entry.answer)]), 14, CYAN))
			var confidence_label: String = "not supplied" if int(entry.get("confidence", -1)) < 0 else ["guessing", "leaning", "sure"][int(entry.confidence)]
			item.add_child(_label("Confidence: %s / %s / %.1fs" % [confidence_label, "hint used" if entry.get("assisted", false) else "no hint", float(entry.get("elapsed_seconds", 0.0))], 12, MUTED))
	_pause_button.disabled = true
	_update_hud()

func _change_adaptive(enabled: bool) -> void:
	model.set_preferences(model.preferences.categories, enabled)
	_show_study()

func _change_category(enabled: bool, category: String) -> void:
	var selected: Array = model.preferences.categories.duplicate()
	if selected.is_empty(): selected = model.available_categories().keys()
	if enabled and category not in selected: selected.append(category)
	if not enabled: selected.erase(category)
	# An empty stored list means all categories; never accidentally turn none into all.
	if not selected.is_empty(): model.set_preferences(selected, bool(model.preferences.adaptive))
	_show_study()

func _select_all_categories() -> void:
	model.set_preferences([], bool(model.preferences.adaptive))
	_show_study()

func _style_study_toggle(toggle: CheckButton) -> void:
	toggle.custom_minimum_size.y = 56
	toggle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := _style(Color("14253c"), EDGE, 8)
		style.content_margin_top = 22
		style.content_margin_bottom = 10
		toggle.add_theme_stylebox_override(state, style)
