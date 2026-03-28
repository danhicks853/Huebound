extends Control
class_name SettingsUI

signal closed

var _colorblind_callback: Callable = Callable()
var _pending := {}  # buffered settings changes, applied on Apply click
var _apply_btn: Button = null
var _panel: PanelContainer = null
var _dragging := false
var _drag_offset := Vector2.ZERO

func _get_vp_size() -> Vector2:
	return get_viewport().get_visible_rect().size

static func create(parent: Node, colorblind_callback: Callable = Callable()) -> SettingsUI:
	var ui = SettingsUI.new()
	ui._colorblind_callback = colorblind_callback
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(ui)
	ui._build()
	return ui

func _build() -> void:
	# Dim background
	var dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			_close()
	)
	add_child(dim)

	# Panel
	var panel = PanelContainer.new()
	_panel = panel
	panel.custom_minimum_size = Vector2(420, 0)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.12, 0.95)
	style.border_color = Color(0.3, 0.3, 0.5, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var outer_vbox = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 10)
	panel.add_child(outer_vbox)

	# Title bar (draggable)
	var title_bar = Control.new()
	title_bar.custom_minimum_size = Vector2(0, 28)
	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_bar.gui_input.connect(_on_title_bar_input)
	outer_vbox.add_child(title_bar)

	var title = Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(title)

	# Tab bar
	var tab_bar = HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 4)
	tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	outer_vbox.add_child(tab_bar)

	# Tab content area
	var content_scroll = ScrollContainer.new()
	content_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var vp_size = _get_vp_size()
	var max_h = min(vp_size.y - 160, 450)
	panel.custom_minimum_size.x = min(420, vp_size.x - 40)
	content_scroll.custom_minimum_size = Vector2(0, max_h)
	outer_vbox.add_child(content_scroll)

	var content_container = VBoxContainer.new()
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_container.add_theme_constant_override("separation", 12)
	content_scroll.add_child(content_container)

	# Build tab pages
	var tabs := ["Sound", "Gameplay", "Video", "Accessibility"]
	var pages: Array[VBoxContainer] = []
	for tab_name in tabs:
		var page = VBoxContainer.new()
		page.add_theme_constant_override("separation", 10)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.visible = false
		content_container.add_child(page)
		pages.append(page)

	_build_sound_tab(pages[0])
	_build_gameplay_tab(pages[1])
	_build_video_tab(pages[2])
	_build_accessibility_tab(pages[3])

	# Tab buttons
	var tab_buttons: Array[Button] = []
	for i in range(tabs.size()):
		var btn = Button.new()
		btn.text = tabs[i]
		btn.custom_minimum_size = Vector2(90, 30)
		btn.add_theme_font_size_override("font_size", 12)
		var idx = i
		btn.pressed.connect(func():
			_switch_tab(idx, pages, tab_buttons)
		)
		tab_bar.add_child(btn)
		tab_buttons.append(btn)

	# Button row: Apply + Close
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer_vbox.add_child(btn_row)

	_apply_btn = _make_button("Apply", Color(0.5, 1.0, 0.5))
	_apply_btn.custom_minimum_size = Vector2(100, 32)
	_apply_btn.pressed.connect(_apply_settings)
	_apply_btn.disabled = true
	btn_row.add_child(_apply_btn)

	var close_btn = _make_button("Close", Color(0.7, 0.7, 0.9))
	close_btn.custom_minimum_size = Vector2(100, 32)
	close_btn.pressed.connect(_close)
	btn_row.add_child(close_btn)

	# Show first tab
	_switch_tab(0, pages, tab_buttons)

	# Center panel after layout
	await get_tree().process_frame
	_clamp_panel_to_viewport()

func _switch_tab(idx: int, pages: Array[VBoxContainer], buttons: Array[Button]) -> void:
	for i in range(pages.size()):
		pages[i].visible = (i == idx)
	for i in range(buttons.size()):
		var active_style = StyleBoxFlat.new()
		var inactive_style = StyleBoxFlat.new()
		if i == idx:
			active_style.bg_color = Color(0.15, 0.15, 0.3, 0.9)
			active_style.border_color = Color(0.5, 0.5, 0.8, 0.8)
			active_style.set_border_width_all(1)
			active_style.set_corner_radius_all(4)
			active_style.set_content_margin_all(4)
			buttons[i].add_theme_stylebox_override("normal", active_style)
			buttons[i].add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		else:
			inactive_style.bg_color = Color(0.08, 0.08, 0.14, 0.9)
			inactive_style.border_color = Color(0.3, 0.3, 0.4, 0.5)
			inactive_style.set_border_width_all(1)
			inactive_style.set_corner_radius_all(4)
			inactive_style.set_content_margin_all(4)
			buttons[i].add_theme_stylebox_override("normal", inactive_style)
			buttons[i].add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))

func _clamp_panel_to_viewport() -> void:
	if not is_instance_valid(_panel):
		return
	var vp = _get_vp_size()
	var sz = _panel.size
	_panel.global_position = Vector2(
		clampf(_panel.global_position.x, 0, maxf(vp.x - sz.x, 0)),
		clampf(_panel.global_position.y, 0, maxf(vp.y - sz.y, 0))
	)

func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_offset = event.global_position - _panel.global_position
			else:
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		_panel.global_position = event.global_position - _drag_offset
		_clamp_panel_to_viewport()

func _mark_dirty() -> void:
	if _apply_btn:
		_apply_btn.disabled = false

func _apply_settings() -> void:
	# Commit all pending changes
	if _pending.has("game_speed"):
		GameState.game_speed = _pending.game_speed
	if _pending.has("grid_snap"):
		NodeFactory.grid_snap_enabled = _pending.grid_snap
	if _pending.has("resolution"):
		var r = _pending.resolution
		get_window().size = r
		get_window().content_scale_size = r
		var screen_size = DisplayServer.screen_get_size()
		get_window().position = (screen_size - r) / 2
	if _pending.has("fullscreen"):
		get_window().mode = Window.MODE_FULLSCREEN if _pending.fullscreen else Window.MODE_WINDOWED
	if _pending.has("vsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if _pending.vsync else DisplayServer.VSYNC_DISABLED)
	if _pending.has("ui_scale"):
		GameState.ui_scale = _pending.ui_scale
		GameState.apply_ui_scale()
	if _pending.has("orb_quality"):
		GameState.orb_quality = _pending.orb_quality
	if _pending.has("colorblind_mode"):
		GameState.colorblind_mode = _pending.colorblind_mode
		if _colorblind_callback.is_valid():
			_colorblind_callback.call(_pending.colorblind_mode)
	_pending.clear()
	if _apply_btn:
		_apply_btn.disabled = true
	GameState.save_game()
	# Re-clamp after resolution/scale changes may have shrunk the viewport
	await get_tree().process_frame
	_clamp_panel_to_viewport()

func _close() -> void:
	_pending.clear()
	closed.emit()
	queue_free()

# ── Sound Tab ─────────────────────────────────────────────────────────────────

func _build_sound_tab(page: VBoxContainer) -> void:
	_add_volume_slider(page, "Master Volume", SFX.master_volume, func(val): SFX.set_master_volume(val))
	_add_volume_slider(page, "SFX Volume", SFX.sfx_volume, func(val): SFX.set_sfx_volume(val))
	_add_volume_slider(page, "Ambient Volume", SFX.ambient_volume, func(val): SFX.set_ambient_volume(val))

	var mute_check = CheckButton.new()
	mute_check.text = "Mute All"
	mute_check.button_pressed = SFX.muted
	mute_check.add_theme_font_size_override("font_size", 13)
	mute_check.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	mute_check.toggled.connect(func(pressed): SFX.set_muted(pressed))
	page.add_child(mute_check)

# ── Gameplay Tab ──────────────────────────────────────────────────────────────

func _build_gameplay_tab(page: VBoxContainer) -> void:
	# Game Speed
	var speed_row = VBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 4)
	page.add_child(speed_row)

	var speed_lbl = _make_label("Game Speed: %dx" % int(GameState.game_speed))
	speed_row.add_child(speed_lbl)

	var speed_slider = HSlider.new()
	speed_slider.min_value = 1
	speed_slider.max_value = 3
	speed_slider.step = 1
	speed_slider.value = GameState.game_speed
	speed_slider.custom_minimum_size = Vector2(200, 20)
	speed_slider.value_changed.connect(func(val):
		_pending.game_speed = val
		speed_lbl.text = "Game Speed: %dx" % int(val)
		_mark_dirty()
	)
	speed_row.add_child(speed_slider)

	var speed_note = Label.new()
	speed_note.text = "For feedback/evaluation only."
	speed_note.add_theme_font_size_override("font_size", 10)
	speed_note.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35))
	speed_row.add_child(speed_note)

	# Grid snap
	var snap_check = CheckButton.new()
	snap_check.text = "Snap to Grid"
	snap_check.button_pressed = NodeFactory.grid_snap_enabled
	snap_check.add_theme_font_size_override("font_size", 13)
	snap_check.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	snap_check.toggled.connect(func(pressed):
		_pending.grid_snap = pressed
		_mark_dirty()
	)
	page.add_child(snap_check)

# ── Video Tab ─────────────────────────────────────────────────────────────────

func _build_video_tab(page: VBoxContainer) -> void:
	# Resolution (skip on web)
	if not OS.has_feature("web"):
		var res_row = VBoxContainer.new()
		res_row.add_theme_constant_override("separation", 4)
		page.add_child(res_row)

		res_row.add_child(_make_label("Resolution"))

		var res_options = OptionButton.new()
		var resolutions := [
			Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
			Vector2i(1920, 1080), Vector2i(2560, 1440),
		]
		var current_size = get_window().size
		var selected_idx := 0
		for i in range(resolutions.size()):
			var r = resolutions[i]
			res_options.add_item("%dx%d" % [r.x, r.y], i)
			if current_size.x == r.x and current_size.y == r.y:
				selected_idx = i
		res_options.selected = selected_idx
		res_options.custom_minimum_size = Vector2(220, 28)
		res_options.add_theme_font_size_override("font_size", 12)
		res_options.item_selected.connect(func(idx):
			_pending.resolution = resolutions[idx]
			_mark_dirty()
		)
		res_row.add_child(res_options)

		# Fullscreen
		var fs_check = CheckButton.new()
		fs_check.text = "Fullscreen"
		fs_check.button_pressed = get_window().mode == Window.MODE_FULLSCREEN
		fs_check.add_theme_font_size_override("font_size", 13)
		fs_check.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
		fs_check.toggled.connect(func(pressed):
			_pending.fullscreen = pressed
			_mark_dirty()
		)
		page.add_child(fs_check)

	# VSync
	var vsync_check = CheckButton.new()
	vsync_check.text = "VSync"
	vsync_check.button_pressed = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	vsync_check.add_theme_font_size_override("font_size", 13)
	vsync_check.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	vsync_check.toggled.connect(func(pressed):
		_pending.vsync = pressed
		_mark_dirty()
	)
	page.add_child(vsync_check)

	# UI Scale
	var scale_row = VBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 4)
	page.add_child(scale_row)

	var scale_pct = int(GameState.ui_scale * 100)
	var scale_lbl = _make_label("UI Scale: %d%%" % scale_pct)
	scale_row.add_child(scale_lbl)

	# Cap max scale so the virtual viewport never shrinks below 960px wide
	var win_w = get_viewport().get_window().size.x
	var max_scale_pct = int(floorf(float(win_w) / 960.0 * 100.0 / 5.0) * 5)
	max_scale_pct = clampi(max_scale_pct, 100, 200)

	var scale_slider = HSlider.new()
	scale_slider.min_value = 75
	scale_slider.max_value = max_scale_pct
	scale_slider.step = 5
	scale_slider.value = clampi(scale_pct, 75, max_scale_pct)
	scale_slider.custom_minimum_size = Vector2(200, 20)
	scale_slider.value_changed.connect(func(val):
		_pending.ui_scale = val / 100.0
		scale_lbl.text = "UI Scale: %d%%" % int(val)
		_mark_dirty()
	)
	scale_row.add_child(scale_slider)

	var scale_note = Label.new()
	scale_note.text = "Increase for high-DPI / 4K displays (max %d%% at current resolution)" % max_scale_pct
	scale_note.add_theme_font_size_override("font_size", 10)
	scale_note.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35))
	scale_row.add_child(scale_note)

	# Orb Trail Quality
	var perf_row = VBoxContainer.new()
	perf_row.add_theme_constant_override("separation", 4)
	page.add_child(perf_row)

	var perf_lbl = _make_label("Orb Trail Quality: %s" % _get_quality_label(GameState.orb_quality))
	perf_row.add_child(perf_lbl)

	var perf_slider = HSlider.new()
	perf_slider.min_value = 0
	perf_slider.max_value = 2
	perf_slider.step = 1
	perf_slider.value = GameState.orb_quality
	perf_slider.custom_minimum_size = Vector2(200, 20)
	perf_slider.value_changed.connect(func(val):
		_pending.orb_quality = int(val)
		perf_lbl.text = "Orb Trail Quality: %s" % _get_quality_label(int(val))
		_mark_dirty()
	)
	perf_row.add_child(perf_slider)

# ── Accessibility Tab ─────────────────────────────────────────────────────────

func _build_accessibility_tab(page: VBoxContainer) -> void:
	var cb_row = VBoxContainer.new()
	cb_row.add_theme_constant_override("separation", 4)
	page.add_child(cb_row)

	cb_row.add_child(_make_label("Colorblind Mode"))

	var cb_options = OptionButton.new()
	cb_options.add_item("Off", 0)
	cb_options.add_item("Protanopia (red-blind)", 1)
	cb_options.add_item("Deuteranopia (green-blind)", 2)
	cb_options.add_item("Tritanopia (blue-blind)", 3)
	cb_options.selected = GameState.colorblind_mode
	cb_options.custom_minimum_size = Vector2(220, 28)
	cb_options.add_theme_font_size_override("font_size", 12)
	cb_options.item_selected.connect(func(idx):
		_pending.colorblind_mode = idx
		_mark_dirty()
	)
	cb_row.add_child(cb_options)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_label(text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	return lbl

func _make_button(text: String, font_color: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 13)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.15, 0.15, 0.25, 0.9)
	btn_style.border_color = Color(0.4, 0.4, 0.5, 0.5)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(4)
	btn_style.set_content_margin_all(4)
	btn.add_theme_stylebox_override("normal", btn_style)
	btn.add_theme_color_override("font_color", font_color)
	return btn

func _add_volume_slider(parent: Control, label_text: String, initial_value: float, callback: Callable) -> void:
	var row = VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var lbl = _make_label(label_text)
	row.add_child(lbl)

	var slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = initial_value
	slider.custom_minimum_size = Vector2(200, 20)
	slider.value_changed.connect(func(val): callback.call(val))
	row.add_child(slider)

static func _get_quality_label(level: int) -> String:
	match level:
		0: return "Low"
		1: return "Medium"
		_: return "High"
