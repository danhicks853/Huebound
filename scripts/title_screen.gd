extends Control

var _buttons: Dictionary = {}
var _dot_canvas: Control = null

# Dot animation state
var _dot_pairs: Array[Dictionary] = []
var _spawn_timer: float = 0.0
var _spawn_interval: float = 2.0

const PRIMARY_COLORS := [
	Color(0.2, 0.4, 1.0),   # Blue
	Color(1.0, 0.2, 0.2),   # Red
	Color(1.0, 1.0, 0.2),   # Yellow
	Color(0.2, 1.0, 0.4),   # Green
	Color(1.0, 0.4, 0.8),   # Pink
	Color(1.0, 0.6, 0.1),   # Orange
	Color(0.6, 0.2, 1.0),   # Purple
	Color(0.2, 1.0, 1.0),   # Cyan
]

func _ready() -> void:
	_build_ui()
	_spawn_timer = randf_range(0.5, 1.5) # First spawn soon

func _process(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = randf_range(1.5, 3.0)
		_spawn_dot_pair()
	
	# Update all dot pairs
	var to_remove: Array[int] = []
	for i in range(_dot_pairs.size()):
		var pair = _dot_pairs[i]
		pair.time += delta
		
		if pair.phase == 0: # Approaching — constant speed (linear)
			var t = clampf(pair.time / pair.approach_dur, 0.0, 1.0)
			pair.pos_a = pair.start_a.lerp(pair.meet_point, t)
			pair.pos_b = pair.start_b.lerp(pair.meet_point, t)
			if t >= 1.0:
				pair.phase = 1
				pair.time = 0.0
		elif pair.phase == 1: # Merged, flying out along combined momentum
			var t = clampf(pair.time / pair.exit_dur, 0.0, 1.0)
			pair.pos_merged = pair.meet_point.lerp(pair.exit_point, t)
			pair.merged_alpha = 1.0 - t * 0.6
			if t >= 1.0:
				to_remove.append(i)
	
	for i in range(to_remove.size() - 1, -1, -1):
		_dot_pairs.remove_at(to_remove[i])
	
	if _dot_canvas:
		_dot_canvas.queue_redraw()

func _spawn_dot_pair() -> void:
	var vp = get_viewport_rect().size
	var margin := 60.0
	
	# Pick two random colors
	var c1 = PRIMARY_COLORS[randi() % PRIMARY_COLORS.size()]
	var c2 = PRIMARY_COLORS[randi() % PRIMARY_COLORS.size()]
	while c2.is_equal_approx(c1):
		c2 = PRIMARY_COLORS[randi() % PRIMARY_COLORS.size()]
	var mixed = Color((c1.r + c2.r) / 2.0, (c1.g + c2.g) / 2.0, (c1.b + c2.b) / 2.0)
	
	# Random meeting point in the middle area
	var meet = Vector2(
		randf_range(vp.x * 0.2, vp.x * 0.8),
		randf_range(vp.y * 0.15, vp.y * 0.85)
	)
	
	# Start positions: random edges
	var start_a = _random_edge_point(vp, margin)
	var start_b = _random_edge_point(vp, margin)
	
	# Exit direction = average of the two incoming velocity vectors (combined momentum)
	var vel_a = (meet - start_a).normalized()
	var vel_b = (meet - start_b).normalized()
	var exit_dir = (vel_a + vel_b).normalized()
	if exit_dir.length() < 0.01:
		exit_dir = vel_a.rotated(PI * 0.5) # If perfectly opposing, deflect sideways
	var exit_point = meet + exit_dir * max(vp.x, vp.y) * 0.8
	
	_dot_pairs.append({
		"color_a": c1,
		"color_b": c2,
		"color_mixed": mixed,
		"start_a": start_a,
		"start_b": start_b,
		"pos_a": start_a,
		"pos_b": start_b,
		"pos_merged": meet,
		"meet_point": meet,
		"exit_point": exit_point,
		"phase": 0, # 0=approaching, 1=merged+exiting
		"time": 0.0,
		"approach_dur": randf_range(1.2, 2.0),
		"exit_dur": randf_range(0.8, 1.4),
		"merged_alpha": 1.0,
	})

func _random_edge_point(vp: Vector2, margin: float) -> Vector2:
	var side = randi() % 4
	match side:
		0: return Vector2(-margin, randf_range(0, vp.y))
		1: return Vector2(vp.x + margin, randf_range(0, vp.y))
		2: return Vector2(randf_range(0, vp.x), -margin)
		_: return Vector2(randf_range(0, vp.x), vp.y + margin)

func _draw_dots(canvas: Control) -> void:
	for pair in _dot_pairs:
		if pair.phase == 0:
			# Draw two approaching dots with glow
			var ga = pair.color_a
			ga.a = 0.15
			canvas.draw_circle(pair.pos_a, 10, ga)
			canvas.draw_circle(pair.pos_a, 5, pair.color_a)
			var gb = pair.color_b
			gb.a = 0.15
			canvas.draw_circle(pair.pos_b, 10, gb)
			canvas.draw_circle(pair.pos_b, 5, pair.color_b)
		elif pair.phase == 1:
			# Draw merged dot (slightly bigger, with glow)
			var gm = pair.color_mixed
			gm.a = 0.2 * pair.merged_alpha
			canvas.draw_circle(pair.pos_merged, 14, gm)
			var core = pair.color_mixed
			core.a = pair.merged_alpha
			canvas.draw_circle(pair.pos_merged, 6, core)
			var bright = pair.color_mixed.lightened(0.4)
			bright.a = 0.6 * pair.merged_alpha
			canvas.draw_circle(pair.pos_merged, 3, bright)

func _build_ui() -> void:
	# Full-screen dark background
	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.08, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	
	# Dot animation canvas (behind UI, on top of bg)
	_dot_canvas = Control.new()
	_dot_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dot_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot_canvas.draw.connect(_draw_dots.bind(_dot_canvas))
	add_child(_dot_canvas)
	
	# Center container
	var center = VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	center.add_theme_constant_override("separation", 12)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(center)
	
	# Title
	var title = Label.new()
	title.text = "HUEBOUND"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.6, 0.7, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)
	
	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "A color-mixing idle discovery game"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.4, 0.45, 0.6))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(subtitle)
	
	if DemoConfig.is_demo():
		var demo_lbl = Label.new()
		demo_lbl.text = "DEMO"
		demo_lbl.add_theme_font_size_override("font_size", 18)
		demo_lbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3, 0.8))
		demo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center.add_child(demo_lbl)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	center.add_child(spacer)
	
	# Buttons
	_add_menu_button(center, "new_game", "New Game", true)
	_add_menu_button(center, "continue", "Continue", GameState.has_save())
	_add_menu_button(center, "settings", "Settings", true)
	_add_menu_button(center, "credits", "Credits", true)
	
	# Version
	var version = Label.new()
	version.text = "v0.1"
	version.add_theme_font_size_override("font_size", 10)
	version.add_theme_color_override("font_color", Color(0.25, 0.25, 0.35))
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(version)

func _add_menu_button(parent: Control, id: String, text: String, enabled: bool) -> void:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(220, 44)
	btn.add_theme_font_size_override("font_size", 16)
	btn.disabled = not enabled
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.14, 0.9)
	style.border_color = Color(0.3, 0.35, 0.6, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", style)
	
	var hover_style = style.duplicate()
	hover_style.bg_color = Color(0.12, 0.12, 0.22, 0.9)
	hover_style.border_color = Color(0.5, 0.55, 0.9, 0.7)
	btn.add_theme_stylebox_override("hover", hover_style)
	
	var disabled_style = style.duplicate()
	disabled_style.bg_color = Color(0.06, 0.06, 0.1, 0.5)
	disabled_style.border_color = Color(0.2, 0.2, 0.3, 0.3)
	btn.add_theme_stylebox_override("disabled", disabled_style)
	
	btn.add_theme_color_override("font_color", Color(0.7, 0.75, 0.95))
	btn.add_theme_color_override("font_disabled_color", Color(0.3, 0.3, 0.4))
	
	btn.pressed.connect(_on_button_pressed.bind(id))
	parent.add_child(btn)
	_buttons[id] = btn

var _confirm_overlay: Control = null

func _on_button_pressed(id: String) -> void:
	match id:
		"new_game":
			if GameState.has_save():
				_show_new_game_confirm()
				return
			GameState.reset_state()
			get_tree().change_scene_to_file("res://scenes/main_game.tscn")
		"continue":
			GameState.load_game()
			get_tree().change_scene_to_file("res://scenes/main_game.tscn")
		"settings":
			_show_settings()
		"credits":
			_show_credits()

func _show_credits() -> void:
	# Simple credits overlay
	var overlay = ColorRect.new()
	overlay.name = "CreditsOverlay"
	overlay.color = Color(0.03, 0.03, 0.06, 0.95)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.add_child(vbox)
	
	var credits_title = Label.new()
	credits_title.text = "HUEBOUND"
	credits_title.add_theme_font_size_override("font_size", 32)
	credits_title.add_theme_color_override("font_color", Color(0.6, 0.7, 1.0))
	credits_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(credits_title)
	
	var credits_text = Label.new()
	credits_text.text = "A color-mixing idle discovery game"
	credits_text.add_theme_font_size_override("font_size", 14)
	credits_text.add_theme_color_override("font_color", Color(0.5, 0.55, 0.7))
	credits_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(credits_text)
	
	var dev_header = Label.new()
	dev_header.text = "Developed by"
	dev_header.add_theme_font_size_override("font_size", 12)
	dev_header.add_theme_color_override("font_color", Color(0.4, 0.45, 0.6))
	dev_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(dev_header)
	
	var dev_name = Label.new()
	dev_name.text = "Dan Hicks"
	dev_name.add_theme_font_size_override("font_size", 16)
	dev_name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	dev_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(dev_name)
	
	var engine_lbl = Label.new()
	engine_lbl.text = "Made with Godot Engine 4"
	engine_lbl.add_theme_font_size_override("font_size", 11)
	engine_lbl.add_theme_color_override("font_color", Color(0.4, 0.45, 0.6))
	engine_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(engine_lbl)
	
	var feedback_header = Label.new()
	feedback_header.text = "Community Feedback"
	feedback_header.add_theme_font_size_override("font_size", 12)
	feedback_header.add_theme_color_override("font_color", Color(0.4, 0.45, 0.6))
	feedback_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(feedback_header)
	
	var feedback_names = Label.new()
	feedback_names.text = "2blade30  -  Acamaeda  -  DavejHale  -  De_inordinatio\nEelsEverywhere  -  Ellensiel  -  GhostDog43\nKingManuel  -  konnichimade  -  LustreOfHavoc\nMercy_2.0  -  Pooplayer1  -  Ravery\nThe_God_Kvothe  -  xtagtv"
	feedback_names.add_theme_font_size_override("font_size", 13)
	feedback_names.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8))
	feedback_names.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(feedback_names)
	
	var closing = Label.new()
	closing.text = "All colors, just like all people, are beautiful."
	closing.add_theme_font_size_override("font_size", 11)
	closing.add_theme_color_override("font_color", Color(0.35, 0.4, 0.55))
	closing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(closing)
	
	var back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(120, 36)
	back_btn.add_theme_font_size_override("font_size", 14)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.08, 0.08, 0.14, 0.9)
	btn_style.border_color = Color(0.3, 0.35, 0.6, 0.5)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(6)
	btn_style.set_content_margin_all(6)
	back_btn.add_theme_stylebox_override("normal", btn_style)
	back_btn.add_theme_color_override("font_color", Color(0.7, 0.75, 0.95))
	back_btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(back_btn)

func _show_new_game_confirm() -> void:
	if _confirm_overlay:
		return
	
	_confirm_overlay = ColorRect.new()
	_confirm_overlay.color = Color(0.03, 0.03, 0.06, 0.9)
	_confirm_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_confirm_overlay)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm_overlay.add_child(vbox)
	
	var warn_title = Label.new()
	warn_title.text = "Start New Game?"
	warn_title.add_theme_font_size_override("font_size", 24)
	warn_title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	warn_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(warn_title)
	
	var warn_body = Label.new()
	warn_body.text = "This will erase your existing save.\nThis cannot be undone."
	warn_body.add_theme_font_size_override("font_size", 14)
	warn_body.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	warn_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(warn_body)
	
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 20)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(120, 40)
	cancel_btn.add_theme_font_size_override("font_size", 14)
	var cancel_style = StyleBoxFlat.new()
	cancel_style.bg_color = Color(0.08, 0.08, 0.14, 0.9)
	cancel_style.border_color = Color(0.3, 0.35, 0.6, 0.5)
	cancel_style.set_border_width_all(1)
	cancel_style.set_corner_radius_all(6)
	cancel_style.set_content_margin_all(6)
	cancel_btn.add_theme_stylebox_override("normal", cancel_style)
	cancel_btn.add_theme_color_override("font_color", Color(0.7, 0.75, 0.95))
	cancel_btn.pressed.connect(func():
		_confirm_overlay.queue_free()
		_confirm_overlay = null
	)
	btn_row.add_child(cancel_btn)
	
	var confirm_btn = Button.new()
	confirm_btn.text = "Erase & Start New"
	confirm_btn.custom_minimum_size = Vector2(160, 40)
	confirm_btn.add_theme_font_size_override("font_size", 14)
	var confirm_style = StyleBoxFlat.new()
	confirm_style.bg_color = Color(0.3, 0.1, 0.1, 0.9)
	confirm_style.border_color = Color(0.7, 0.3, 0.3, 0.7)
	confirm_style.set_border_width_all(1)
	confirm_style.set_corner_radius_all(6)
	confirm_style.set_content_margin_all(6)
	confirm_btn.add_theme_stylebox_override("normal", confirm_style)
	var confirm_hover = confirm_style.duplicate()
	confirm_hover.bg_color = Color(0.4, 0.15, 0.15, 0.9)
	confirm_btn.add_theme_stylebox_override("hover", confirm_hover)
	confirm_btn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7))
	confirm_btn.pressed.connect(func():
		GameState.reset_state()
		get_tree().change_scene_to_file("res://scenes/main_game.tscn")
	)
	btn_row.add_child(confirm_btn)

var _settings_overlay: SettingsUI = null

func _show_settings() -> void:
	if _settings_overlay:
		_settings_overlay.queue_free()
		_settings_overlay = null
		return
	_settings_overlay = SettingsUI.create(self)
	_settings_overlay.closed.connect(func(): _settings_overlay = null)
