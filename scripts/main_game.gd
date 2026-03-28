extends Node2D

enum Mode { IDLE, PLACING, CONNECTING, DRAGGING, BOX_SELECT, PLACING_TEMPLATE }

var current_mode: int = Mode.IDLE
var placing_node_id: String = ""
var placing_preview: FactoryNode = null
var connecting_from: FactoryNode = null
var selected_node: FactoryNode = null

var camera_drag: bool = false
var camera_drag_start: Vector2 = Vector2.ZERO

# Touch input state
var _touch_points: Dictionary = {}  # finger_index -> position
var _touch_pan_active: bool = false
var _touch_pan_start: Vector2 = Vector2.ZERO
var _pinch_start_dist: float = 0.0
var _pinch_start_zoom: Vector2 = Vector2.ONE
var _touch_tap_candidate: bool = false  # true if single touch hasn't moved much
var _touch_tap_start: Vector2 = Vector2.ZERO
const TOUCH_TAP_THRESHOLD := 15.0  # pixels of movement before it becomes a pan

# Node dragging
var dragging_node: FactoryNode = null
var drag_offset: Vector2 = Vector2.ZERO
var _drag_moved: bool = false

# Box selection
var _box_select_start: Vector2 = Vector2.ZERO
var _box_select_end: Vector2 = Vector2.ZERO
var _box_selected_nodes: Array[FactoryNode] = []
var _box_select_rect_node: Node2D = null

# Template placement
var _placing_template: Dictionary = {}  # the template being placed
var _template_previews: Array[FactoryNode] = []  # ghost nodes shown during placement

# Connection hover / delete X
var _hovered_conn_line: ConnectionLine = null
var _conn_delete_btn: Button = null

# Colorblind filter
var _colorblind_layer: CanvasLayer = null
var _colorblind_rect: ColorRect = null

@onready var world: Node2D = $World
@onready var connections_layer: Node2D = $World/Connections
@onready var nodes_layer: Node2D = $World/Nodes
@onready var grid_layer: Node2D = $World/Grid
@onready var camera: Camera2D = $Camera2D
@onready var hud: CanvasLayer = $HUD
@onready var _palette: Node = get_node("/root/ColorPalette")

# Flying color nodes (recovery mechanic when low on currency)
var flying_nodes_layer: Node2D
var _flying_node_spawn_timer: float = 0.0
const FLYING_NODE_SPAWN_INTERVAL: float = 2.0  # Spawn every 2 seconds when eligible
const FLYING_NODE_REWARD: float = 50.0  # Light given when clicked

# Dynamic threshold: player needs at least enough to buy a seller
func _get_flying_node_threshold() -> float:
	return NodeFactory.get_node_cost("seller")

func _get_vp_size() -> Vector2:
	return get_viewport().get_visible_rect().size

func _ready() -> void:
	NodeFactory.rebuild_dynamic_defs()
	_setup_hud()
	_setup_colorblind_filter()
	_setup_flying_nodes_layer()
	SFX.start_ambient()
	# Restore saved nodes and connections if any
	_restore_saved_layout()
	# Check for endgame state (prestige 25 with rainbow)
	if _is_endgame_state():
		return
	# Start tutorial if fresh game and tutorial not already completed/skipped
	if NodeFactory.placed_nodes.is_empty() and not GameState.tutorial_completed:
		call_deferred("_start_tutorial")

func _setup_colorblind_filter() -> void:
	_colorblind_layer = CanvasLayer.new()
	_colorblind_layer.layer = 2  # Just above HUD (layer 1) so screen texture captures world + HUD
	add_child(_colorblind_layer)
	_colorblind_rect = ColorRect.new()
	_colorblind_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_colorblind_rect.color = Color.WHITE
	_colorblind_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader = load("res://shaders/colorblind.gdshader")
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("mode", float(GameState.colorblind_mode))
	_colorblind_rect.material = mat
	_colorblind_rect.visible = GameState.colorblind_mode > 0
	_colorblind_layer.add_child(_colorblind_rect)

func _setup_flying_nodes_layer() -> void:
	flying_nodes_layer = Node2D.new()
	flying_nodes_layer.name = "FlyingNodes"
	flying_nodes_layer.z_index = 10  # Above nodes and connections
	world.add_child(flying_nodes_layer)
	# Move to top so it's last in draw order and input propagation
	world.move_child(flying_nodes_layer, -1)

func _update_colorblind_filter(mode: int) -> void:
	GameState.colorblind_mode = mode
	if _colorblind_rect and _colorblind_rect.material:
		(_colorblind_rect.material as ShaderMaterial).set_shader_parameter("mode", float(mode))
		_colorblind_rect.visible = mode > 0
	GameState.save_game()

func _restore_saved_layout() -> void:
	if GameState.pending_nodes.is_empty():
		return
	# Recreate nodes
	var restored_nodes: Array[FactoryNode] = []
	for node_data in GameState.pending_nodes:
		var nid = str(node_data.get("node_id", ""))
		var def = NodeFactory.get_node_def(nid)
		if def.is_empty():
			restored_nodes.append(null)
			continue
		var node = FactoryNode.new()
		node.setup(nid)
		node.global_position = Vector2(float(node_data.get("x", 0)), float(node_data.get("y", 0)))
		node.level = int(node_data.get("level", 1))
		nodes_layer.add_child(node)
		NodeFactory.register_node(node)
		restored_nodes.append(node)
	# Recreate connections
	for conn_data in GameState.pending_connections:
		var from_idx = int(conn_data.get("from", -1))
		var to_idx = int(conn_data.get("to", -1))
		if from_idx < 0 or to_idx < 0:
			continue
		if from_idx >= restored_nodes.size() or to_idx >= restored_nodes.size():
			continue
		var from_node = restored_nodes[from_idx]
		var to_node = restored_nodes[to_idx]
		if from_node == null or to_node == null:
			continue
		if NodeFactory.add_connection(from_node, to_node):
			_create_connection_line(from_node, to_node)
	# Clear pending data
	GameState.pending_nodes.clear()
	GameState.pending_connections.clear()

var info_update_timer: float = 0.0
var _autosave_timer: float = 0.0

func _process(delta: float) -> void:
	# Autosave every 30 seconds
	_autosave_timer += delta
	if _autosave_timer >= 30.0:
		_autosave_timer = 0.0
		GameState.save_game()
	
	# Refresh info panel and shop periodically
	info_update_timer += delta
	if info_update_timer >= 0.25:
		info_update_timer = 0.0
		if selected_node:
			_update_info_panel()
		if _shop_open:
			_update_shop_buttons()
		_update_palette_locks()
		if _tutorial_active:
			_check_tutorial_progress()
	
	# Update prestige button visibility and glow
	if prestige_btn:
		var eligible = _can_prestige()
		if eligible and not prestige_btn.visible:
			prestige_btn.visible = true
			var is_final = GameState.prestige_count >= 24 and _palette.discovery_count >= _palette.get_palette_size()
			prestige_btn.text = "✦ Spectrum Complete" if is_final else "✦ Spectrum Reset"
		elif not eligible and prestige_btn.visible:
			prestige_btn.visible = false
		if prestige_btn.visible:
			_prestige_glow_time += delta * 2.0
			var glow = 0.5 + 0.5 * sin(_prestige_glow_time)
			prestige_btn.modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.2, 1.0, 1.4), glow)
	
	# Flying color nodes: spawn when low on currency
	_update_flying_nodes(delta)
	
	# Discovery notification cards float up and fade
	_update_discovery_cards(delta)
	
	# Keep preview node attached to mouse every frame
	if placing_preview:
		placing_preview.global_position = NodeFactory.snap_to_grid(get_global_mouse_position())
	
	# Keep template preview group attached to mouse
	if current_mode == Mode.PLACING_TEMPLATE and _template_previews.size() > 0:
		var mouse_world = NodeFactory.snap_to_grid(get_global_mouse_position())
		for i in range(_template_previews.size()):
			var preview = _template_previews[i]
			if is_instance_valid(preview):
				var tpl_node = _placing_template.nodes[i]
				preview.global_position = mouse_world + Vector2(float(tpl_node.ox), float(tpl_node.oy))

func _is_mouse_over_ui() -> bool:
	var mouse_pos = get_viewport().get_mouse_position()
	var gui_control = _find_gui_control_at(hud, mouse_pos)
	return gui_control != null

func _find_gui_control_at(node: Node, pos: Vector2) -> Control:
	if node is Control:
		var ctrl = node as Control
		if ctrl.visible and ctrl.mouse_filter == Control.MOUSE_FILTER_STOP:
			if ctrl.get_global_rect().has_point(pos):
				return ctrl
	for child in node.get_children():
		var result = _find_gui_control_at(child, pos)
		if result:
			return result
	return null

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var world_pos = get_global_mouse_position()
		
		# Zoom (only when not over UI)
		if not _is_mouse_over_ui():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				camera.zoom = (camera.zoom * 1.1).clamp(Vector2(0.3, 0.3), Vector2(3.0, 3.0))
				_clear_connection_hover()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				camera.zoom = (camera.zoom / 1.1).clamp(Vector2(0.3, 0.3), Vector2(3.0, 3.0))
				_clear_connection_hover()
		
		# Middle mouse: always camera pan
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				camera_drag = true
			else:
				camera_drag = false
		
		# Left click
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Check flying nodes first (recovery mechanic) - only in IDLE mode
				if current_mode == Mode.IDLE and not _is_mouse_over_ui():
					if _try_click_flying_node(world_pos):
						return  # Handled flying node click
				
				if current_mode == Mode.IDLE:
					# Check if clicking a node — start dragging
					var clicked_node = NodeFactory.get_node_at(world_pos)
					if clicked_node:
						_clear_box_selection()
						_select_node(clicked_node)
						current_mode = Mode.DRAGGING
						dragging_node = clicked_node
						drag_offset = clicked_node.global_position - world_pos
						_drag_moved = false
					else:
						_deselect()
						_clear_box_selection()
						# Start box selection
						current_mode = Mode.BOX_SELECT
						_box_select_start = world_pos
						_box_select_end = world_pos
						_start_box_select_visual()
				elif current_mode == Mode.BOX_SELECT:
					# Clicking while box-selected — check if clicking a node
					var clicked_node = NodeFactory.get_node_at(world_pos)
					if clicked_node:
						_clear_box_selection()
						_select_node(clicked_node)
						current_mode = Mode.DRAGGING
						dragging_node = clicked_node
						drag_offset = clicked_node.global_position - world_pos
					else:
						_clear_box_selection()
						current_mode = Mode.BOX_SELECT
						_box_select_start = world_pos
						_box_select_end = world_pos
						_start_box_select_visual()
				elif current_mode == Mode.CONNECTING:
					# In connect mode: if clicking a node, handle connection; otherwise ignore
					var clicked_node = NodeFactory.get_node_at(world_pos)
					if clicked_node:
						_try_connect(world_pos)
					else:
						# Clicked empty space in connect mode — cancel and allow pan
						pass
				else:
					_handle_world_click(world_pos)
			else:
				# Left release
				if current_mode == Mode.DRAGGING:
					if dragging_node:
						dragging_node.global_position = NodeFactory.snap_to_grid(dragging_node.global_position)
					dragging_node = null
					if _drag_moved:
						_deselect()
					current_mode = Mode.IDLE
					_update_mode_label()
				elif current_mode == Mode.BOX_SELECT:
					_finish_box_select()
					# Stay in IDLE with selection shown
		
		# Right click
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if current_mode == Mode.DRAGGING:
				# Cancel drag — snap back (we don't track original pos, just snap)
				if dragging_node:
					dragging_node.global_position = NodeFactory.snap_to_grid(dragging_node.global_position)
				dragging_node = null
				_deselect()
				current_mode = Mode.IDLE
				_update_mode_label()
			elif current_mode == Mode.BOX_SELECT:
				_clear_box_selection()
				current_mode = Mode.IDLE
				_update_mode_label()
			elif current_mode != Mode.IDLE:
				_cancel_action()
			else:
				# In idle mode: right-click on node shows popup, near connection removes it, otherwise pan
				var rclick_node = NodeFactory.get_node_at(world_pos)
				if rclick_node:
					_select_node(rclick_node)
					_show_node_popup(rclick_node, event.position)
				else:
					var conn = NodeFactory.get_connection_near(world_pos)
					if not conn.is_empty():
						_remove_connection(conn.from, conn.to)
					else:
						camera_drag = true
		
		if event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
			camera_drag = false
	
	if event is InputEventMouseMotion:
		if camera_drag:
			camera.position -= event.relative / camera.zoom
		if current_mode == Mode.DRAGGING and dragging_node:
			dragging_node.global_position = get_global_mouse_position() + drag_offset
			_drag_moved = true
		if current_mode == Mode.BOX_SELECT:
			_box_select_end = get_global_mouse_position()
			_update_box_select_visual()
		# Connection hover detection (only in IDLE / CONNECTING modes)
		if current_mode == Mode.IDLE or current_mode == Mode.CONNECTING:
			_update_connection_hover(get_global_mouse_position(), event.position)
		elif _hovered_conn_line:
			_clear_connection_hover()
	
	# Touch input: pinch-to-zoom and single-finger pan on empty canvas
	# Note: single taps are handled via Godot's emulate_mouse_from_touch (on by default)
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_points[event.index] = event.position
			if _touch_points.size() == 1:
				_touch_tap_candidate = true
				_touch_tap_start = event.position
				_touch_pan_active = false
			elif _touch_points.size() == 2:
				# Two fingers — start pinch, cancel any mouse emulation
				_touch_tap_candidate = false
				_touch_pan_active = false
				var points = _touch_points.values()
				_pinch_start_dist = points[0].distance_to(points[1])
				_pinch_start_zoom = camera.zoom
		else:
			if event.index in _touch_points:
				_touch_points.erase(event.index)
			_touch_pan_active = false
			_touch_tap_candidate = false
	
	if event is InputEventScreenDrag:
		_touch_points[event.index] = event.position
		if _touch_points.size() == 1 and current_mode == Mode.IDLE:
			# Single finger drag on empty canvas — pan camera
			if _touch_tap_candidate:
				if event.position.distance_to(_touch_tap_start) > TOUCH_TAP_THRESHOLD:
					_touch_tap_candidate = false
					_touch_pan_active = true
			if _touch_pan_active:
				camera.position -= event.relative / camera.zoom
		elif _touch_points.size() == 2:
			# Pinch zoom
			var points = _touch_points.values()
			var current_dist = points[0].distance_to(points[1])
			if _pinch_start_dist > 0:
				var scale = current_dist / _pinch_start_dist
				camera.zoom = (_pinch_start_zoom * scale).clamp(Vector2(0.3, 0.3), Vector2(3.0, 3.0))
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if current_mode == Mode.DRAGGING:
			if dragging_node:
				dragging_node.global_position = NodeFactory.snap_to_grid(dragging_node.global_position)
			dragging_node = null
			_deselect()
			current_mode = Mode.IDLE
			_update_mode_label()
		elif current_mode != Mode.IDLE:
			_cancel_action()
		else:
			_deselect()

func _handle_world_click(pos: Vector2) -> void:
	match current_mode:
		Mode.PLACING:
			_try_place_node(pos)
		Mode.PLACING_TEMPLATE:
			_try_place_template(pos)
		Mode.CONNECTING:
			_try_connect(pos)
		Mode.IDLE:
			var clicked_node = NodeFactory.get_node_at(pos)
			if clicked_node:
				_select_node(clicked_node)
			else:
				_deselect()

func _try_place_node(pos: Vector2) -> void:
	var snapped_pos = NodeFactory.snap_to_grid(pos)
	if not NodeFactory.is_position_free(snapped_pos):
		return
	
	var def = NodeFactory.get_node_def(placing_node_id)
	if def.is_empty():
		return
	var cost = NodeFactory.get_node_cost(placing_node_id)
	if not GameState.spend_currency(cost):
		return
	NodeFactory.record_purchase(placing_node_id)
	
	var node = FactoryNode.new()
	node.setup(placing_node_id)
	node.global_position = snapped_pos
	nodes_layer.add_child(node)
	NodeFactory.register_node(node)
	SFX.play_place()
	# Steam achievement for placing nodes
	if NodeFactory.placed_nodes.size() >= 10:
		SteamManager.unlock_achievement("ten_nodes")
	
	# Check if this is the Rainbow node — trigger endgame
	if def.get("rainbow", false):
		_cancel_action()
		call_deferred("_trigger_rainbow_endgame", node)
		return
	
	# Exit placement mode after placing
	_cancel_action()

func _try_connect(pos: Vector2) -> void:
	var target = NodeFactory.get_node_at(pos)
	if target == null:
		return
	
	if connecting_from == null:
		connecting_from = target
		target.selected = true
		_update_mode_label()
	else:
		if connecting_from != target:
			if NodeFactory.add_connection(connecting_from, target):
				_create_connection_line(connecting_from, target)
				SFX.play_connect()
		connecting_from.selected = false
		connecting_from = null
		# Stay in connect mode — don't call _cancel_action()
		_update_mode_label()

func _create_connection_line(from: FactoryNode, to: FactoryNode) -> void:
	var line = ConnectionLine.new()
	line.setup(from, to)
	connections_layer.add_child(line)

func _remove_connection(from: FactoryNode, to: FactoryNode) -> void:
	_clear_connection_hover()
	NodeFactory.remove_connection(from, to)
	SFX.play_disconnect()
	# Find and remove the visual ConnectionLine
	for child in connections_layer.get_children():
		if child is ConnectionLine and child.from_node == from and child.to_node == to:
			child.queue_free()
			break

func _update_connection_hover(world_pos: Vector2, screen_pos: Vector2) -> void:
	# Don't hover connections when the mouse is over a node
	var node_under = NodeFactory.get_node_at(world_pos)
	if node_under:
		if _hovered_conn_line:
			_clear_connection_hover()
		return
	# Find the nearest connection line
	var conn = NodeFactory.get_connection_near(world_pos, 20.0)
	if conn.is_empty():
		if _hovered_conn_line:
			_clear_connection_hover()
		return
	# Find the matching ConnectionLine visual
	var target_line: ConnectionLine = null
	for child in connections_layer.get_children():
		if child is ConnectionLine and child.from_node == conn.from and child.to_node == conn.to:
			target_line = child
			break
	if target_line == null:
		if _hovered_conn_line:
			_clear_connection_hover()
		return
	# Same line already hovered — just reposition the X button
	if target_line == _hovered_conn_line:
		_reposition_conn_delete_btn(conn.from, conn.to)
		return
	# New hover — clear old, set new
	_clear_connection_hover()
	_hovered_conn_line = target_line
	_hovered_conn_line.hovered = true
	_show_conn_delete_btn(conn.from, conn.to)

func _clear_connection_hover() -> void:
	if _hovered_conn_line and is_instance_valid(_hovered_conn_line):
		_hovered_conn_line.hovered = false
	_hovered_conn_line = null
	if _conn_delete_btn and is_instance_valid(_conn_delete_btn):
		_conn_delete_btn.queue_free()
	_conn_delete_btn = null

func _show_conn_delete_btn(from: FactoryNode, to: FactoryNode) -> void:
	if _conn_delete_btn and is_instance_valid(_conn_delete_btn):
		_conn_delete_btn.queue_free()
	_conn_delete_btn = Button.new()
	_conn_delete_btn.text = "X"
	_conn_delete_btn.custom_minimum_size = Vector2(22, 22)
	_conn_delete_btn.size = Vector2(22, 22)
	_conn_delete_btn.add_theme_font_size_override("font_size", 12)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.6, 0.1, 0.1, 0.9)
	style.set_corner_radius_all(11)
	style.set_content_margin_all(0)
	_conn_delete_btn.add_theme_stylebox_override("normal", style)
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.9, 0.15, 0.15, 1.0)
	hover_style.set_corner_radius_all(11)
	hover_style.set_content_margin_all(0)
	_conn_delete_btn.add_theme_stylebox_override("hover", hover_style)
	var pressed_style = StyleBoxFlat.new()
	pressed_style.bg_color = Color(1.0, 0.2, 0.2, 1.0)
	pressed_style.set_corner_radius_all(11)
	pressed_style.set_content_margin_all(0)
	_conn_delete_btn.add_theme_stylebox_override("pressed", pressed_style)
	_conn_delete_btn.add_theme_color_override("font_color", Color(1, 1, 1))
	_conn_delete_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	_conn_delete_btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	var captured_from = from
	var captured_to = to
	_conn_delete_btn.pressed.connect(func(): _remove_connection(captured_from, captured_to))
	hud.add_child(_conn_delete_btn)
	_reposition_conn_delete_btn(from, to)

func _reposition_conn_delete_btn(from: FactoryNode, to: FactoryNode) -> void:
	if not _conn_delete_btn or not is_instance_valid(_conn_delete_btn):
		return
	var mid_world = (from.global_position + to.global_position) * 0.5
	var vp = get_viewport()
	var canvas_transform = vp.get_canvas_transform()
	var screen_mid = canvas_transform * mid_world
	_conn_delete_btn.position = screen_mid - _conn_delete_btn.size * 0.5

func _select_node(node: FactoryNode) -> void:
	_deselect()
	selected_node = node
	node.selected = true
	_delete_confirm = false
	_update_info_panel()

func _deselect() -> void:
	if selected_node:
		selected_node.selected = false
		selected_node = null
	_update_info_panel()

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var vp = get_viewport()
	var canvas_transform = vp.get_canvas_transform()
	return canvas_transform.affine_inverse() * screen_pos

func _cancel_action() -> void:
	current_mode = Mode.IDLE
	if placing_preview:
		placing_preview.queue_free()
		placing_preview = null
	if connecting_from:
		connecting_from.selected = false
		connecting_from = null
	_clear_template_previews()
	_deselect()
	_clear_connection_hover()
	# Clear any lingering selection highlights on all nodes
	for node in NodeFactory.placed_nodes:
		if is_instance_valid(node):
			node.selected = false
	_clear_box_selection()
	_update_mode_label()

func start_placing(node_id: String) -> void:
	_cancel_action()
	var def = NodeFactory.get_node_def(node_id)
	if def.is_empty():
		return
	if not NodeFactory.is_node_unlocked(node_id):
		return
	if not GameState.can_afford(def.cost):
		return
	
	current_mode = Mode.PLACING
	placing_node_id = node_id
	
	# Create preview
	placing_preview = FactoryNode.new()
	placing_preview.setup(node_id)
	placing_preview.modulate.a = 0.5
	placing_preview.is_preview = true
	nodes_layer.add_child(placing_preview)
	_update_mode_label()

func start_connecting() -> void:
	_cancel_action()
	_deselect()
	current_mode = Mode.CONNECTING
	connecting_from = null
	_update_mode_label()

func _draw_grid() -> void:
	grid_layer.queue_redraw()

# ---- HUD ----

var currency_label: Label
var rate_label: Label
var income_label: Label
var upkeep_label: Label
var _upkeep_tooltip: PanelContainer = null
var _hud_margin: MarginContainer
var _discovery_cards: Array[Control] = []
var mode_label: Label
var cancel_btn: Button
var info_panel: PanelContainer
var info_label: RichTextLabel
var upgrade_btn: Button
var delete_btn: Button
var save_template_btn: Button
var node_buttons: Dictionary = {}
var gallery_btn: Button
var _delete_confirm: bool = false
var _node_popup: PanelContainer = null
var prestige_btn: Button = null
var _prestige_glow_time: float = 0.0
var gallery_panel: PanelContainer = null
var gallery_grid: Control = null
var _gallery_search: LineEdit = null
var _gallery_visible: Array[int] = []  # filtered palette indices; empty = show all
var shop_btn: Button
var shop_panel: PanelContainer = null
var shop_buttons: Dictionary = {}
var node_unlock_buttons: Dictionary = {}
var _node_unlock_section: VBoxContainer = null
var connect_btn: Button
var _palette_collapse_btn: Button = null
var _palette_scroll: ScrollContainer = null
var _palette_grid: GridContainer = null
var _palette_collapsed: bool = false
var _nodes_tab_content: VBoxContainer = null
var _templates_tab_content: VBoxContainer = null
var _templates_list: VBoxContainer = null
var _tab_nodes_btn: Button = null
var _tab_templates_btn: Button = null
var _template_hover_popup: PanelContainer = null
var _template_name_dialog: Control = null

# Tutorial system
var _tutorial_active := false
var _tutorial_step := 0
var _tutorial_overlay: Control = null
var _tutorial_tooltip: PanelContainer = null
var _tutorial_highlight: Control = null
var _tutorial_completed_steps: Array[String] = []

func _setup_hud() -> void:
	# Set up bundled fonts so emoji + text render on web export
	var base_font = load("res://fonts/NotoSans-Regular.ttf") as FontFile
	var emoji_font = load("res://fonts/NotoColorEmoji-Regular.ttf") as FontFile
	if base_font:
		if emoji_font:
			base_font.fallbacks = [emoji_font]
		ThemeDB.fallback_font = base_font
		var theme = Theme.new()
		theme.default_font = base_font
		get_tree().root.theme = theme
	
	# Main container — MOUSE_FILTER_IGNORE on all layout containers so clicks pass through
	_hud_margin = MarginContainer.new()
	_hud_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_margin.add_theme_constant_override("margin_left", 10)
	_hud_margin.add_theme_constant_override("margin_right", 10)
	_hud_margin.add_theme_constant_override("margin_top", 10)
	_hud_margin.add_theme_constant_override("margin_bottom", 10)
	hud.add_child(_hud_margin)
	
	var root_container = VBoxContainer.new()
	root_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_margin.add_child(root_container)
	
	# Top bar scroll wrapper — prevents clipping at high UI scale
	var top_scroll = ScrollContainer.new()
	top_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	top_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	top_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	top_scroll.custom_minimum_size = Vector2(0, 44)
	root_container.add_child(top_scroll)

	var top_bar = HBoxContainer.new()
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_scroll.add_child(top_bar)
	
	# Title
	var title = Label.new()
	title.text = "HUEBOUND"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0, 0.9))
	top_bar.add_child(title)
	
	var spacer1 = Control.new()
	spacer1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer1)
	
	# Currency + rate
	var currency_vbox = VBoxContainer.new()
	currency_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(currency_vbox)
	
	currency_label = Label.new()
	currency_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	currency_label.text = "$ %.1f" % GameState.currency
	currency_label.add_theme_font_size_override("font_size", 22)
	currency_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	currency_vbox.add_child(currency_label)
	GameState.currency_changed.connect(func(amt): currency_label.text = "$ %.1f" % amt)
	
	# Income / Upkeep / Net row
	var rate_row = HBoxContainer.new()
	rate_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rate_row.add_theme_constant_override("separation", 8)
	currency_vbox.add_child(rate_row)
	
	income_label = Label.new()
	income_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	income_label.text = "+0.0"
	income_label.add_theme_font_size_override("font_size", 11)
	income_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 0.8))
	rate_row.add_child(income_label)
	
	upkeep_label = Label.new()
	upkeep_label.mouse_filter = Control.MOUSE_FILTER_PASS
	upkeep_label.text = "-0.0"
	upkeep_label.add_theme_font_size_override("font_size", 11)
	upkeep_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4, 0.8))
	upkeep_label.mouse_entered.connect(_show_upkeep_tooltip)
	upkeep_label.mouse_exited.connect(_hide_upkeep_tooltip)
	rate_row.add_child(upkeep_label)
	
	rate_label = Label.new()
	rate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rate_label.text = "= 0.0/s"
	rate_label.add_theme_font_size_override("font_size", 11)
	rate_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.4, 0.8))
	rate_row.add_child(rate_label)
	
	GameState.currency_rate_changed.connect(func(rate):
		_update_rate_display(rate)
		_update_palette_locks()
	)
	
	# Prestige button (between currency and collection)
	var spacer_prestige = Control.new()
	spacer_prestige.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer_prestige.custom_minimum_size = Vector2(10, 0)
	top_bar.add_child(spacer_prestige)
	
	prestige_btn = Button.new()
	prestige_btn.custom_minimum_size = Vector2(0, 36)
	prestige_btn.add_theme_font_size_override("font_size", 12)
	var prest_style = StyleBoxFlat.new()
	prest_style.bg_color = Color(0.15, 0.1, 0.25, 0.9)
	prest_style.border_color = Color(0.6, 0.4, 1.0, 0.7)
	prest_style.set_border_width_all(2)
	prest_style.set_corner_radius_all(4)
	prest_style.set_content_margin_all(6)
	prestige_btn.add_theme_stylebox_override("normal", prest_style)
	var prest_hover = prest_style.duplicate()
	prest_hover.bg_color = Color(0.2, 0.15, 0.35, 0.9)
	prestige_btn.add_theme_stylebox_override("hover", prest_hover)
	prestige_btn.add_theme_color_override("font_color", Color(0.8, 0.6, 1.0))
	prestige_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 1.0))
	prestige_btn.pressed.connect(_on_prestige_btn_pressed)
	prestige_btn.visible = false
	top_bar.add_child(prestige_btn)
	
	# Gallery button
	var spacer_gallery = Control.new()
	spacer_gallery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer_gallery.custom_minimum_size = Vector2(10, 0)
	top_bar.add_child(spacer_gallery)
	
	gallery_btn = Button.new()
	gallery_btn.text = "Collection 0/%d" % _palette.get_palette_size()
	gallery_btn.custom_minimum_size = Vector2(0, 36)
	gallery_btn.add_theme_font_size_override("font_size", 13)
	var gal_style = StyleBoxFlat.new()
	gal_style.bg_color = Color(0.1, 0.1, 0.18, 0.9)
	gal_style.border_color = Color(0.4, 0.4, 0.6, 0.5)
	gal_style.set_border_width_all(1)
	gal_style.set_corner_radius_all(4)
	gal_style.set_content_margin_all(6)
	gallery_btn.add_theme_stylebox_override("normal", gal_style)
	var gal_hover = gal_style.duplicate()
	gal_hover.bg_color = Color(0.15, 0.15, 0.25, 0.9)
	gallery_btn.add_theme_stylebox_override("hover", gal_hover)
	gallery_btn.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9))
	gallery_btn.pressed.connect(_toggle_gallery)
	top_bar.add_child(gallery_btn)
	
	# Shop button (hidden in endgame)
	if not _is_endgame_state():
		var spacer_shop = Control.new()
		spacer_shop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spacer_shop.custom_minimum_size = Vector2(10, 0)
		top_bar.add_child(spacer_shop)
		
		shop_btn = Button.new()
		shop_btn.text = "Shop"
		shop_btn.custom_minimum_size = Vector2(60, 36)
		shop_btn.add_theme_font_size_override("font_size", 13)
		var shop_style = StyleBoxFlat.new()
		shop_style.bg_color = Color(0.12, 0.1, 0.05, 0.9)
		shop_style.border_color = Color(0.6, 0.5, 0.2, 0.5)
		shop_style.set_border_width_all(1)
		shop_style.set_corner_radius_all(4)
		shop_style.set_content_margin_all(6)
		shop_btn.add_theme_stylebox_override("normal", shop_style)
		var shop_hover = shop_style.duplicate()
		shop_hover.bg_color = Color(0.18, 0.15, 0.08, 0.9)
		shop_btn.add_theme_stylebox_override("hover", shop_hover)
		shop_btn.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
		shop_btn.pressed.connect(_toggle_shop)
		top_bar.add_child(shop_btn)
	
	# Menu button
	var spacer_menu = Control.new()
	spacer_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer_menu.custom_minimum_size = Vector2(10, 0)
	top_bar.add_child(spacer_menu)
	
	var menu_btn = Button.new()
	menu_btn.text = "Menu"
	menu_btn.custom_minimum_size = Vector2(60, 36)
	menu_btn.add_theme_font_size_override("font_size", 13)
	var menu_style = StyleBoxFlat.new()
	menu_style.bg_color = Color(0.12, 0.08, 0.08, 0.9)
	menu_style.border_color = Color(0.5, 0.3, 0.3, 0.5)
	menu_style.set_border_width_all(1)
	menu_style.set_corner_radius_all(4)
	menu_style.set_content_margin_all(6)
	menu_btn.add_theme_stylebox_override("normal", menu_style)
	var menu_hover = menu_style.duplicate()
	menu_hover.bg_color = Color(0.18, 0.1, 0.1, 0.9)
	menu_btn.add_theme_stylebox_override("hover", menu_hover)
	menu_btn.add_theme_color_override("font_color", Color(0.9, 0.6, 0.6))
	menu_btn.pressed.connect(_show_game_menu)
	top_bar.add_child(menu_btn)
	
	# Prestige indicator
	if GameState.prestige_count > 0:
		var prestige_lbl = Label.new()
		prestige_lbl.text = "P%d" % GameState.prestige_count
		prestige_lbl.add_theme_font_size_override("font_size", 11)
		prestige_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 0.6))
		prestige_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_bar.add_child(prestige_lbl)
	
	# Mode label + Cancel button row
	var mode_row = HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	root_container.add_child(mode_row)
	
	mode_label = Label.new()
	mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_label.text = ""
	mode_label.add_theme_font_size_override("font_size", 14)
	mode_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 0.7))
	mode_row.add_child(mode_label)
	
	cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(70, 32)
	cancel_btn.add_theme_font_size_override("font_size", 12)
	var cancel_style = StyleBoxFlat.new()
	cancel_style.bg_color = Color(0.2, 0.1, 0.1, 0.9)
	cancel_style.border_color = Color(0.6, 0.3, 0.3, 0.6)
	cancel_style.set_border_width_all(1)
	cancel_style.set_corner_radius_all(4)
	cancel_style.set_content_margin_all(4)
	cancel_btn.add_theme_stylebox_override("normal", cancel_style)
	var cancel_hover = cancel_style.duplicate()
	cancel_hover.bg_color = Color(0.3, 0.15, 0.15, 0.9)
	cancel_btn.add_theme_stylebox_override("hover", cancel_hover)
	cancel_btn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	cancel_btn.pressed.connect(func():
		if current_mode == Mode.DRAGGING:
			if dragging_node:
				dragging_node.global_position = NodeFactory.snap_to_grid(dragging_node.global_position)
			dragging_node = null
			current_mode = Mode.IDLE
			_update_mode_label()
		elif current_mode != Mode.IDLE:
			_cancel_action()
		else:
			_deselect()
	)
	cancel_btn.visible = false
	mode_row.add_child(cancel_btn)
	
	# Spacer
	var spacer_mid = Control.new()
	spacer_mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer_mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_container.add_child(spacer_mid)
	
	# Bottom panel: node palette + info
	var bottom = HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 10)
	root_container.add_child(bottom)
	
	# Node palette (left side of bottom)
	var palette_panel = PanelContainer.new()
	palette_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var palette_style = StyleBoxFlat.new()
	palette_style.bg_color = Color(0.08, 0.08, 0.14, 0.9)
	palette_style.border_color = Color(0.3, 0.3, 0.4, 0.5)
	palette_style.set_border_width_all(1)
	palette_style.set_corner_radius_all(6)
	palette_style.set_content_margin_all(8)
	palette_panel.add_theme_stylebox_override("panel", palette_style)
	bottom.add_child(palette_panel)
	
	var palette_vbox = VBoxContainer.new()
	palette_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	palette_vbox.add_theme_constant_override("separation", 4)
	palette_panel.add_child(palette_vbox)
	
	# Tab bar row
	var tab_row = HBoxContainer.new()
	tab_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab_row.add_theme_constant_override("separation", 4)
	palette_vbox.add_child(tab_row)
	
	_tab_nodes_btn = Button.new()
	_tab_nodes_btn.text = "Nodes"
	_tab_nodes_btn.custom_minimum_size = Vector2(70, 22)
	_tab_nodes_btn.add_theme_font_size_override("font_size", 11)
	_tab_nodes_btn.pressed.connect(func(): _switch_palette_tab(0))
	tab_row.add_child(_tab_nodes_btn)
	
	_tab_templates_btn = Button.new()
	_tab_templates_btn.text = "Templates (%d/%d)" % [GameState.templates.size(), _get_max_template_slots()]
	_tab_templates_btn.custom_minimum_size = Vector2(100, 22)
	_tab_templates_btn.add_theme_font_size_override("font_size", 11)
	_tab_templates_btn.visible = _get_max_template_slots() > 0 and not DemoConfig.is_demo()
	_tab_templates_btn.pressed.connect(func(): _switch_palette_tab(1))
	tab_row.add_child(_tab_templates_btn)
	
	var tab_spacer = Control.new()
	tab_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(tab_spacer)
	
	_palette_collapse_btn = Button.new()
	_palette_collapse_btn.text = "▼"
	_palette_collapse_btn.custom_minimum_size = Vector2(24, 18)
	_palette_collapse_btn.add_theme_font_size_override("font_size", 10)
	var collapse_style = StyleBoxFlat.new()
	collapse_style.bg_color = Color(0.1, 0.1, 0.18, 0.8)
	collapse_style.set_border_width_all(0)
	collapse_style.set_corner_radius_all(3)
	collapse_style.set_content_margin_all(2)
	_palette_collapse_btn.add_theme_stylebox_override("normal", collapse_style)
	var collapse_hover = collapse_style.duplicate()
	collapse_hover.bg_color = Color(0.15, 0.15, 0.25, 0.9)
	_palette_collapse_btn.add_theme_stylebox_override("hover", collapse_hover)
	_palette_collapse_btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	_palette_collapse_btn.pressed.connect(_toggle_palette_collapse)
	tab_row.add_child(_palette_collapse_btn)
	
	# ── Nodes tab content ──
	_nodes_tab_content = VBoxContainer.new()
	_nodes_tab_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nodes_tab_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nodes_tab_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette_vbox.add_child(_nodes_tab_content)
	
	_palette_scroll = ScrollContainer.new()
	_palette_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_palette_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_palette_scroll.custom_minimum_size = Vector2(0, 62)
	_palette_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_nodes_tab_content.add_child(_palette_scroll)
	
	_palette_grid = GridContainer.new()
	_palette_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_palette_grid.columns = 6
	_palette_grid.add_theme_constant_override("h_separation", 6)
	_palette_grid.add_theme_constant_override("v_separation", 6)
	_palette_scroll.add_child(_palette_grid)
	
	# Build ordered node list
	var _all_node_defs = NodeFactory.get_all_defs()
	var utility_ids := ["seller", "combiner", "splitter"]
	var ordered_ids: Array[String] = []
	if _is_endgame_state():
		_all_node_defs = {}
		var rainbow_def = NodeFactory.get_node_def("rainbow")
		if not rainbow_def.is_empty():
			_all_node_defs["rainbow"] = rainbow_def
		for id in _all_node_defs:
			ordered_ids.append(id)
	else:
		connect_btn = _create_connect_button()
		_palette_grid.add_child(connect_btn)
		for uid in utility_ids:
			if _all_node_defs.has(uid) and not DemoConfig.is_node_blocked(uid):
				ordered_ids.append(uid)
		for id in _all_node_defs:
			if id not in utility_ids and not DemoConfig.is_node_blocked(id):
				ordered_ids.append(id)
	
	for id in ordered_ids:
		var def = _all_node_defs[id]
		var btn = _create_node_button(id, def)
		_palette_grid.add_child(btn)
		node_buttons[id] = btn
	
	# ── Templates tab content ──
	_templates_tab_content = VBoxContainer.new()
	_templates_tab_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_templates_tab_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_templates_tab_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_templates_tab_content.visible = false
	palette_vbox.add_child(_templates_tab_content)
	
	var tpl_scroll = ScrollContainer.new()
	tpl_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	tpl_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tpl_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tpl_scroll.custom_minimum_size = Vector2(0, 62)
	tpl_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tpl_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_templates_tab_content.add_child(tpl_scroll)
	
	_templates_list = VBoxContainer.new()
	_templates_list.add_theme_constant_override("separation", 4)
	_templates_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tpl_scroll.add_child(_templates_list)
	
	_rebuild_templates_list()
	_switch_palette_tab(0)
	
	# Info panel (right side of bottom)
	info_panel = PanelContainer.new()
	info_panel.custom_minimum_size = Vector2(160, 0)
	var info_style = StyleBoxFlat.new()
	info_style.bg_color = Color(0.08, 0.08, 0.14, 0.9)
	info_style.border_color = Color(0.3, 0.3, 0.4, 0.5)
	info_style.set_border_width_all(1)
	info_style.set_corner_radius_all(6)
	info_style.set_content_margin_all(8)
	info_panel.add_theme_stylebox_override("panel", info_style)
	bottom.add_child(info_panel)
	
	var info_vbox = VBoxContainer.new()
	info_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_theme_constant_override("separation", 6)
	info_panel.add_child(info_vbox)
	
	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.fit_content = true
	info_label.scroll_active = false
	info_label.add_theme_font_size_override("normal_font_size", 12)
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_label.add_theme_color_override("default_color", Color(0.7, 0.7, 0.8))
	info_vbox.add_child(info_label)
	
	var btn_row = HBoxContainer.new()
	btn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_row.add_theme_constant_override("separation", 4)
	info_vbox.add_child(btn_row)
	
	upgrade_btn = Button.new()
	upgrade_btn.text = "Upgrade"
	upgrade_btn.visible = false
	upgrade_btn.add_theme_font_size_override("font_size", 11)
	var upg_style = StyleBoxFlat.new()
	upg_style.bg_color = Color(0.1, 0.2, 0.1, 0.9)
	upg_style.border_color = Color(0.3, 0.7, 0.3, 0.7)
	upg_style.set_border_width_all(1)
	upg_style.set_corner_radius_all(3)
	upg_style.set_content_margin_all(4)
	upgrade_btn.add_theme_stylebox_override("normal", upg_style)
	var upg_hover = upg_style.duplicate()
	upg_hover.bg_color = Color(0.15, 0.3, 0.15, 0.9)
	upgrade_btn.add_theme_stylebox_override("hover", upg_hover)
	upgrade_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	upgrade_btn.pressed.connect(_on_upgrade_pressed)
	btn_row.add_child(upgrade_btn)
	
	# Spacer between upgrade and delete
	var btn_spacer = Control.new()
	btn_spacer.custom_minimum_size = Vector2(20, 0)
	btn_row.add_child(btn_spacer)
	
	delete_btn = Button.new()
	delete_btn.text = "Sell"
	delete_btn.visible = false
	delete_btn.add_theme_font_size_override("font_size", 11)
	var del_style = StyleBoxFlat.new()
	del_style.bg_color = Color(0.2, 0.1, 0.1, 0.9)
	del_style.border_color = Color(0.7, 0.3, 0.3, 0.7)
	del_style.set_border_width_all(1)
	del_style.set_corner_radius_all(3)
	del_style.set_content_margin_all(4)
	delete_btn.add_theme_stylebox_override("normal", del_style)
	var del_hover = del_style.duplicate()
	del_hover.bg_color = Color(0.3, 0.15, 0.15, 0.9)
	delete_btn.add_theme_stylebox_override("hover", del_hover)
	delete_btn.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	delete_btn.pressed.connect(_on_delete_pressed)
	btn_row.add_child(delete_btn)
	
	save_template_btn = Button.new()
	save_template_btn.text = "Save Template"
	save_template_btn.visible = false
	save_template_btn.add_theme_font_size_override("font_size", 11)
	var tpl_style = StyleBoxFlat.new()
	tpl_style.bg_color = Color(0.1, 0.1, 0.2, 0.9)
	tpl_style.border_color = Color(0.3, 0.5, 0.8, 0.7)
	tpl_style.set_border_width_all(1)
	tpl_style.set_corner_radius_all(3)
	tpl_style.set_content_margin_all(4)
	save_template_btn.add_theme_stylebox_override("normal", tpl_style)
	var tpl_hover = tpl_style.duplicate()
	tpl_hover.bg_color = Color(0.15, 0.15, 0.3, 0.9)
	save_template_btn.add_theme_stylebox_override("hover", tpl_hover)
	save_template_btn.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	save_template_btn.pressed.connect(_on_save_template_pressed)
	btn_row.add_child(save_template_btn)
	
	_update_info_panel()
	_update_palette_locks()
	_palette.color_discovered.connect(_on_color_discovered)

func _update_mode_label() -> void:
	match current_mode:
		Mode.IDLE:
			mode_label.text = ""
			cancel_btn.visible = false
		Mode.PLACING:
			var def = NodeFactory.get_node_def(placing_node_id)
			mode_label.text = "Placing: %s" % def.get("name", "")
			cancel_btn.visible = true
		Mode.CONNECTING:
			if connecting_from:
				mode_label.text = "Connect: click target node"
			else:
				mode_label.text = "Connect: click source node"
			cancel_btn.visible = true
		Mode.DRAGGING:
			mode_label.text = "Dragging"
			cancel_btn.visible = true
		Mode.BOX_SELECT:
			mode_label.text = "Selecting..."
			cancel_btn.visible = true
		Mode.PLACING_TEMPLATE:
			mode_label.text = "Placing Template: %s" % _placing_template.get("name", "")
			cancel_btn.visible = true

func _on_upgrade_pressed() -> void:
	if selected_node and selected_node.upgrade():
		_update_info_panel()

func _on_delete_pressed() -> void:
	# Bulk delete from box selection
	if _box_selected_nodes.size() > 0:
		if not _delete_confirm:
			_delete_confirm = true
			delete_btn.text = "Confirm Sell %d?" % _box_selected_nodes.size()
			return
		_delete_confirm = false
		_delete_box_selected()
		return
	# Single node delete
	if not selected_node:
		return
	if not _delete_confirm:
		_delete_confirm = true
		delete_btn.text = "Confirm?"
		return
	# Confirmed — actually delete
	_delete_confirm = false
	var node = selected_node
	var nid = node.node_id
	_deselect()
	NodeFactory.unregister_node(node)
	# Refund 50% of what this node cost at its purchase level
	var refund = NodeFactory.get_node_sell_value(nid)
	NodeFactory.record_sell(nid)
	GameState.add_currency(refund)
	node.queue_free()
	SFX.play_delete()

func _update_info_panel() -> void:
	if selected_node == null:
		info_label.text = "[color=#667]Select a node to see details[/color]\n\n[color=#556]Tip: Place sources, connect to\ncombiner, then to seller.\nMix colors to discover new ones![/color]"
		upgrade_btn.visible = false
		delete_btn.visible = false
		save_template_btn.visible = false
		return
	
	delete_btn.visible = true
	save_template_btn.visible = false
	if not _delete_confirm:
		var refund = NodeFactory.get_node_sell_value(selected_node.node_id)
		delete_btn.text = "Sell $%.0f" % refund
	
	var def = selected_node.node_def
	var color_hex = selected_node.base_color.to_html(false)
	var can_upgrade = def.get("max_level", 1) > 1
	upgrade_btn.visible = can_upgrade
	var text = ""
	if can_upgrade:
		text = "[color=#%s][b]%s[/b][/color] (Lv.%d)\n" % [color_hex, def.get("name", ""), selected_node.level]
	else:
		text = "[color=#%s][b]%s[/b][/color]\n" % [color_hex, def.get("name", "")]
	text += "[color=#889]%s[/color]\n\n" % def.get("description", "")
	
	match selected_node.node_type:
		NodeFactory.NodeType.PRODUCER:
			var cname = _palette.get_color_name(selected_node.base_color)
			text += "Output: [color=#%s]%s[/color]\n" % [color_hex, cname]
			text += "Rate: %.1f/s\n" % def.get("rate", 1.0)
		NodeFactory.NodeType.PROCESSOR:
			var cur_ins = NodeFactory.get_connections_to(selected_node).size()
			text += "Inputs: %d/2\n" % cur_ins
			text += "Rate: %.1f/s\n" % def.get("rate", 1.0)
			if selected_node._last_produced_color != Color.TRANSPARENT:
				var out_name = _palette.get_color_name(selected_node._last_produced_color)
				var out_hex = selected_node._last_produced_color.to_html(false)
				text += "Output: [color=#%s]%s[/color]\n" % [out_hex, out_name]
			elif cur_ins < 2:
				text += "Output: [color=#667]Connect 2 inputs[/color]\n"
			else:
				text += "Output: [color=#667]Waiting...[/color]\n"
		NodeFactory.NodeType.SELLER:
			text += "Sells orbs by color rarity\n"
			text += "Rate: %.1f/s\n" % def.get("rate", 1.0)
		NodeFactory.NodeType.SPLITTER:
			text += "Splits orbs into 2 (halves value each)\n"
			text += "Rate: %.1f/s\n" % def.get("rate", 1.0)
	
	var upkeep = def.get("upkeep", 0.0)
	if upkeep > 0.0:
		text += "[color=#f88]Upkeep: %.1f/s[/color]\n" % upkeep
	
	text += "Buffer: %d/%d\n" % [selected_node.output_buffer.size() + selected_node.input_buffer.size(), selected_node.max_buffer * 2]
	
	if can_upgrade:
		if selected_node.is_max_level():
			upgrade_btn.text = "MAX"
			upgrade_btn.disabled = true
		else:
			var upgrade_cost = selected_node.get_upgrade_cost()
			upgrade_btn.text = "Upgrade $%.0f" % upgrade_cost
			upgrade_btn.disabled = not GameState.can_afford(upgrade_cost)
	
	info_label.text = text

func _get_node_info_text(node: FactoryNode) -> String:
	var def = node.node_def
	var color_hex = node.base_color.to_html(false)
	var text = "[color=#%s][b]%s[/b][/color]\n" % [color_hex, def.get("name", "")]
	text += "[color=#889]%s[/color]\n" % def.get("description", "")
	match node.node_type:
		NodeFactory.NodeType.PRODUCER:
			var cname = _palette.get_color_name(node.base_color)
			text += "Output: [color=#%s]%s[/color]\n" % [color_hex, cname]
			text += "Rate: %.1f/s" % def.get("rate", 1.0)
		NodeFactory.NodeType.PROCESSOR:
			var cur_ins = NodeFactory.get_connections_to(node).size()
			text += "Inputs: %d/2\n" % cur_ins
			if node._last_produced_color != Color.TRANSPARENT:
				var out_name = _palette.get_color_name(node._last_produced_color)
				var out_hex = node._last_produced_color.to_html(false)
				text += "Output: [color=#%s]%s[/color]" % [out_hex, out_name]
			elif cur_ins < 2:
				text += "Output: [color=#667]Need 2 inputs[/color]"
			else:
				text += "Output: [color=#667]Waiting...[/color]"
		NodeFactory.NodeType.SELLER:
			text += "Sells orbs by rarity"
		NodeFactory.NodeType.SPLITTER:
			text += "Splits orbs into 2"
	var upkeep = def.get("upkeep", 0.0)
	if upkeep > 0.0:
		text += "\n[color=#f88]Upkeep: %.1f/s[/color]" % upkeep
	if node.node_cps != 0.0:
		text += "\n[color=#aab]CPS: %.1f[/color]" % node.node_cps
	return text

func _show_node_popup(node: FactoryNode, screen_pos: Vector2) -> void:
	_hide_node_popup()
	_node_popup = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.08, 0.95)
	style.border_color = node.base_color * 0.6
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	_node_popup.add_theme_stylebox_override("panel", style)
	_node_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.custom_minimum_size = Vector2(180, 0)
	label.add_theme_font_size_override("normal_font_size", 11)
	label.add_theme_color_override("default_color", Color(0.7, 0.7, 0.8))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = _get_node_info_text(node)
	_node_popup.add_child(label)
	
	hud.add_child(_node_popup)
	
	# Position near mouse after layout
	await get_tree().process_frame
	if is_instance_valid(_node_popup):
		var vp = _get_vp_size()
		var tip_size = _node_popup.size
		var x = screen_pos.x + 16
		var y = screen_pos.y - tip_size.y * 0.5
		if x + tip_size.x > vp.x - 10:
			x = screen_pos.x - tip_size.x - 16
		y = clampf(y, 10, vp.y - tip_size.y - 10)
		_node_popup.position = Vector2(x, y)
	
	# Auto-dismiss after 3 seconds
	await get_tree().create_timer(3.0).timeout
	_hide_node_popup()

func _hide_node_popup() -> void:
	if _node_popup and is_instance_valid(_node_popup):
		_node_popup.queue_free()
		_node_popup = null

func _get_total_upkeep() -> float:
	var total := 0.0
	for node in NodeFactory.placed_nodes:
		if not is_instance_valid(node):
			continue
		var upkeep = node.node_def.get("upkeep", 0.0)
		if upkeep > 0.0 and node._has_processed:
			total += upkeep * GameState.game_speed
	return total

func _get_upkeep_breakdown() -> Dictionary:
	var breakdown := {}  # node_name -> { count, rate }
	for node in NodeFactory.placed_nodes:
		if not is_instance_valid(node):
			continue
		var upkeep = node.node_def.get("upkeep", 0.0)
		if upkeep > 0.0 and node._has_processed:
			var name = node.node_def.get("name", "Unknown")
			if not breakdown.has(name):
				breakdown[name] = { "count": 0, "rate": upkeep * GameState.game_speed }
			breakdown[name].count += 1
	return breakdown

func _update_rate_display(net_rate: float) -> void:
	var total_upkeep = _get_total_upkeep()
	var gross_income = net_rate + total_upkeep
	if gross_income > 0.01:
		income_label.text = "+%.1f" % gross_income
	else:
		income_label.text = "+0.0"
	if total_upkeep > 0.01:
		upkeep_label.text = "-%.1f" % total_upkeep
		upkeep_label.visible = true
	else:
		upkeep_label.text = "-0.0"
		upkeep_label.visible = total_upkeep > 0.0 or gross_income > 0.01
	rate_label.text = "= %.1f/s" % net_rate

func _show_upkeep_tooltip() -> void:
	_hide_upkeep_tooltip()
	var breakdown = _get_upkeep_breakdown()
	if breakdown.is_empty():
		return
	_upkeep_tooltip = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.12, 0.95)
	style.border_color = Color(0.4, 0.3, 0.3, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	_upkeep_tooltip.add_theme_stylebox_override("panel", style)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_upkeep_tooltip.add_child(vbox)
	var header = Label.new()
	header.text = "Upkeep Breakdown"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
	vbox.add_child(header)
	for name in breakdown:
		var entry = breakdown[name]
		var line = Label.new()
		line.text = "%s x%d  (%.1f/s)" % [name, entry.count, entry.rate * entry.count]
		line.add_theme_font_size_override("font_size", 10)
		line.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
		vbox.add_child(line)
	var total_line = Label.new()
	total_line.text = "Total: -%.1f/s" % _get_total_upkeep()
	total_line.add_theme_font_size_override("font_size", 10)
	total_line.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	vbox.add_child(total_line)
	hud.add_child(_upkeep_tooltip)
	# Position below the upkeep label
	await get_tree().process_frame
	if is_instance_valid(_upkeep_tooltip) and is_instance_valid(upkeep_label):
		var label_pos = upkeep_label.global_position
		var label_size = upkeep_label.size
		_upkeep_tooltip.position = Vector2(label_pos.x, label_pos.y + label_size.y + 4)

func _hide_upkeep_tooltip() -> void:
	if _upkeep_tooltip and is_instance_valid(_upkeep_tooltip):
		_upkeep_tooltip.queue_free()
		_upkeep_tooltip = null

func _create_node_button(id: String, def: Dictionary) -> Button:
	var btn = Button.new()
	btn.text = "%s\n$%.0f" % [def.name, def.cost]
	btn.custom_minimum_size = Vector2(100, 56)
	btn.add_theme_font_size_override("font_size", 12)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.12, 0.12, 0.2, 0.9)
	btn_style.border_color = def.color * 0.7
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(4)
	btn_style.set_content_margin_all(4)
	btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.18, 0.18, 0.28, 0.9)
	btn_hover.border_color = def.color
	btn.add_theme_stylebox_override("hover", btn_hover)
	var btn_pressed = btn_style.duplicate()
	btn_pressed.bg_color = Color(0.22, 0.22, 0.32, 0.9)
	btn.add_theme_stylebox_override("pressed", btn_pressed)
	var btn_disabled = btn_style.duplicate()
	btn_disabled.bg_color = Color(0.08, 0.08, 0.1, 0.9)
	btn_disabled.border_color = Color(0.3, 0.3, 0.3, 0.4)
	btn.add_theme_stylebox_override("disabled", btn_disabled)
	btn.add_theme_color_override("font_color", def.color.lightened(0.3))
	btn.add_theme_color_override("font_hover_color", def.color.lightened(0.5))
	btn.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.45))
	var captured_id = id
	btn.pressed.connect(func(): start_placing(captured_id))
	return btn

func _create_connect_button() -> Button:
	var btn = Button.new()
	btn.text = "Connect\n-->"
	btn.custom_minimum_size = Vector2(80, 56)
	btn.add_theme_font_size_override("font_size", 12)
	var conn_style = StyleBoxFlat.new()
	conn_style.bg_color = Color(0.12, 0.12, 0.2, 0.9)
	conn_style.border_color = Color(0.5, 0.8, 0.5, 0.7)
	conn_style.set_border_width_all(1)
	conn_style.set_corner_radius_all(4)
	conn_style.set_content_margin_all(4)
	btn.add_theme_stylebox_override("normal", conn_style)
	var conn_hover = conn_style.duplicate()
	conn_hover.bg_color = Color(0.18, 0.18, 0.28, 0.9)
	conn_hover.border_color = Color(0.5, 1.0, 0.5, 0.9)
	btn.add_theme_stylebox_override("hover", conn_hover)
	btn.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	btn.add_theme_color_override("font_hover_color", Color(0.6, 1.0, 0.6))
	btn.pressed.connect(start_connecting)
	return btn

func _toggle_palette_collapse() -> void:
	_palette_collapsed = not _palette_collapsed
	if _palette_collapsed:
		# Force all items into one row
		_palette_grid.columns = _palette_grid.get_child_count()
		_palette_scroll.custom_minimum_size.y = 62
		_palette_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_palette_collapse_btn.text = "▶"
	else:
		_palette_grid.columns = 6
		_palette_scroll.custom_minimum_size.y = 62
		_palette_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_palette_collapse_btn.text = "▼"

func _update_palette_locks() -> void:
	for id in node_buttons:
		var btn: Button = node_buttons[id]
		var unlocked = NodeFactory.is_node_unlocked(id)
		var def = NodeFactory.get_node_def(id)
		if unlocked:
			var cost = NodeFactory.get_node_cost(id)
			var can_afford = GameState.can_afford(cost)
			btn.disabled = not can_afford
			btn.text = "%s\n$%.0f" % [def.name, cost]
			btn.modulate.a = 1.0 if can_afford else 0.6
		else:
			btn.disabled = true
			btn.text = "%s\n[LOCKED] $%.0f" % [def.name, def.get("unlock_cost", 0.0)]
			btn.modulate.a = 0.4
	gallery_btn.text = "Collection %d/%d" % [_palette.discovery_count, _get_collection_total()]

func _toggle_gallery() -> void:
	if gallery_panel != null:
		gallery_panel.queue_free()
		gallery_panel = null
		gallery_grid = null
		_gallery_search = null
		_gallery_visible.clear()
		_hide_gallery_tooltip()
		return
	_build_gallery()

var _gallery_tooltip: PanelContainer = null

func _build_gallery() -> void:
	gallery_panel = PanelContainer.new()
	gallery_panel.set_anchors_preset(Control.PRESET_CENTER)
	gallery_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	gallery_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	panel_style.border_color = Color(0.3, 0.3, 0.5, 0.6)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(16)
	gallery_panel.add_theme_stylebox_override("panel", panel_style)
	hud.add_child(gallery_panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	gallery_panel.add_child(vbox)
	
	# Header row
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)
	
	var title = Label.new()
	title.text = "Collection %d/%d" % [_palette.discovery_count, _get_collection_total()]
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	
	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.2, 0.1, 0.1, 0.9)
	close_style.set_corner_radius_all(4)
	close_style.set_content_margin_all(2)
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.pressed.connect(_toggle_gallery)
	header.add_child(close_btn)
	
	# Search bar
	_gallery_search = LineEdit.new()
	_gallery_search.placeholder_text = "Search colors..."
	_gallery_search.clear_button_enabled = true
	_gallery_search.add_theme_font_size_override("font_size", 13)
	_gallery_search.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	_gallery_search.add_theme_color_override("font_placeholder_color", Color(0.4, 0.4, 0.55))
	var search_style = StyleBoxFlat.new()
	search_style.bg_color = Color(0.08, 0.08, 0.14, 0.9)
	search_style.border_color = Color(0.3, 0.3, 0.5, 0.5)
	search_style.set_border_width_all(1)
	search_style.set_corner_radius_all(4)
	search_style.set_content_margin_all(6)
	_gallery_search.add_theme_stylebox_override("normal", search_style)
	_gallery_search.add_theme_stylebox_override("focus", search_style)
	_gallery_search.text_changed.connect(_gallery_filter_changed)
	vbox.add_child(_gallery_search)
	_gallery_visible.clear()
	
	# Dot grid — larger circles
	var dot_size := 18
	var dot_spacing := 4
	var cols := 16
	var rows := ceili(float(_palette.get_palette_size()) / cols)
	var grid_w := cols * (dot_size + dot_spacing) - dot_spacing
	var grid_h := rows * (dot_size + dot_spacing) - dot_spacing
	
	# Wrap the dot grid in a scroll container so it fits within the viewport
	var vp = _get_vp_size()
	var gallery_scroll = ScrollContainer.new()
	gallery_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	gallery_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gallery_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# Cap height: viewport minus header/search/padding (~120px overhead)
	var max_grid_h = min(grid_h, vp.y - 120)
	gallery_scroll.custom_minimum_size = Vector2(grid_w, max_grid_h)
	vbox.add_child(gallery_scroll)
	
	gallery_grid = Control.new()
	gallery_grid.custom_minimum_size = Vector2(grid_w, grid_h)
	gallery_grid.draw.connect(_draw_gallery_grid.bind(gallery_grid, dot_size, dot_spacing, cols))
	gallery_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	gallery_grid.gui_input.connect(_gallery_hover.bind(gallery_grid, dot_size, dot_spacing, cols))
	gallery_grid.mouse_exited.connect(func(): _hide_gallery_tooltip())
	gallery_scroll.add_child(gallery_grid)

func _gallery_filter_changed(query: String) -> void:
	_gallery_visible.clear()
	var q = query.strip_edges().to_lower()
	if q.is_empty():
		# No filter — show all
		if gallery_grid:
			gallery_grid.queue_redraw()
		return
	# Build a set of discovered color names that match the query
	var matching_discovered: Array[String] = []
	for i in range(_palette.get_palette_size()):
		if _palette.is_discovered(i) and _palette.palette[i].name.to_lower().find(q) >= 0:
			matching_discovered.append(_palette.palette[i].name)
	# Now include: any color whose name matches the query (discovered),
	# OR any color (discovered or not) that has a matching discovered color as an ingredient
	for i in range(_palette.get_palette_size()):
		var entry = _palette.palette[i]
		# Direct name match (discovered)
		if _palette.is_discovered(i) and entry.name.to_lower().find(q) >= 0:
			_gallery_visible.append(i)
			continue
		# Ingredient match: this color's recipe contains a discovered color that matches query
		if entry.recipe.size() > 0:
			for ingredient_name in entry.recipe:
				if ingredient_name in matching_discovered:
					_gallery_visible.append(i)
					break
	if gallery_grid:
		gallery_grid.queue_redraw()

func _draw_gallery_grid(grid: Control, dot_size: int, dot_spacing: int, cols: int) -> void:
	var palette_size = _palette.get_palette_size()
	var step = dot_size + dot_spacing
	var radius = dot_size * 0.5
	var filtering = not _gallery_visible.is_empty()
	for i in range(palette_size):
		var col = i % cols
		var row = i / cols
		var center = Vector2(col * step + radius, row * step + radius)
		var visible = not filtering or i in _gallery_visible
		if _palette.is_discovered(i):
			var c: Color = _palette.palette[i].color
			if not visible:
				c = Color(c.r * 0.2, c.g * 0.2, c.b * 0.2, 0.3)
				grid.draw_circle(center, radius, c)
			else:
				# Glow
				var glow = c
				glow.a = 0.2
				grid.draw_circle(center, radius + 2, glow)
				grid.draw_circle(center, radius, c)
		else:
			if not visible:
				grid.draw_circle(center, radius, Color(0.05, 0.05, 0.07, 0.2))
			else:
				grid.draw_circle(center, radius, Color(0.1, 0.1, 0.13))
				grid.draw_arc(center, radius, 0, TAU, 16, Color(0.2, 0.2, 0.25), 1.0)

func _gallery_hover(event: InputEvent, grid: Control, dot_size: int, dot_spacing: int, cols: int) -> void:
	if not (event is InputEventMouseMotion):
		return
	var step = dot_size + dot_spacing
	var col = int(event.position.x) / step
	var row = int(event.position.y) / step
	var idx = row * cols + col
	if idx < 0 or idx >= _palette.get_palette_size():
		_hide_gallery_tooltip()
		return
	# Skip tooltip for filtered-out dots
	if not _gallery_visible.is_empty() and idx not in _gallery_visible:
		_hide_gallery_tooltip()
		return
	
	var entry = _palette.palette[idx]
	var discovered = _palette.is_discovered(idx)
	var in_demo = DemoConfig.is_color_in_demo(entry.name)
	var color_name = entry.name if discovered else "???"
	var recipe: Array = entry.recipe
	
	# Build tooltip text
	var tip_text = color_name
	if recipe.size() > 0:
		if discovered:
			# Color is discovered — reveal full recipe
			tip_text += "\n" + " + ".join(recipe)
		else:
			# Not discovered — show ??? for each ingredient
			var display_parts: Array[String] = []
			for ingredient_name in recipe:
				var source_idx = _palette.find_color_by_name(ingredient_name)
				if source_idx >= 0 and _palette.is_discovered(source_idx):
					display_parts.append(ingredient_name)
				else:
					display_parts.append("???")
			tip_text += "\n" + " + ".join(display_parts)
	if not in_demo:
		tip_text += "\n[DEMO_BLOCKED]"
	
	# Show or update tooltip near mouse
	_show_gallery_tooltip(tip_text, entry.color if discovered else Color(0.3, 0.3, 0.35), event.position + grid.global_position, discovered)

func _show_gallery_tooltip(text: String, color: Color, global_pos: Vector2, discovered: bool) -> void:
	if _gallery_tooltip == null:
		_gallery_tooltip = PanelContainer.new()
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.04, 0.04, 0.08, 0.95)
		style.border_color = Color(0.3, 0.3, 0.5, 0.6)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.set_content_margin_all(8)
		_gallery_tooltip.add_theme_stylebox_override("panel", style)
		_gallery_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(_gallery_tooltip)
	
	# Clear old children
	for child in _gallery_tooltip.get_children():
		child.queue_free()
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gallery_tooltip.add_child(vbox)
	
	var name_lbl = Label.new()
	name_lbl.text = text.split("\n")[0]
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", color.lightened(0.3) if discovered else Color(0.5, 0.5, 0.6))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)
	
	var lines = text.split("\n")
	var has_demo_block = text.find("[DEMO_BLOCKED]") >= 0
	if lines.size() > 1 and lines[1] != "[DEMO_BLOCKED]":
		var recipe_lbl = Label.new()
		recipe_lbl.text = lines[1]
		recipe_lbl.add_theme_font_size_override("font_size", 11)
		recipe_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		recipe_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(recipe_lbl)
		if discovered and not has_demo_block:
			var hint_lbl = Label.new()
			hint_lbl.text = "Other recipes may exist"
			hint_lbl.add_theme_font_size_override("font_size", 9)
			hint_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.55))
			hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox.add_child(hint_lbl)
	if has_demo_block:
		var demo_lbl = Label.new()
		demo_lbl.text = "Not available in demo"
		demo_lbl.add_theme_font_size_override("font_size", 10)
		demo_lbl.add_theme_color_override("font_color", Color(0.7, 0.4, 0.3))
		demo_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(demo_lbl)
	
	_gallery_tooltip.visible = true
	# Position near mouse, offset to the right
	await get_tree().process_frame
	if is_instance_valid(_gallery_tooltip):
		var vp = _get_vp_size()
		var tip_size = _gallery_tooltip.size
		var x = global_pos.x + 16
		var y = global_pos.y - tip_size.y * 0.5
		if x + tip_size.x > vp.x - 10:
			x = global_pos.x - tip_size.x - 16
		y = clampf(y, 10, vp.y - tip_size.y - 10)
		_gallery_tooltip.position = Vector2(x, y)

func _hide_gallery_tooltip() -> void:
	if _gallery_tooltip:
		_gallery_tooltip.queue_free()
		_gallery_tooltip = null

func _get_collection_total() -> int:
	if DemoConfig.is_demo():
		return DemoConfig.get_demo_color_count()
	return _palette.get_palette_size()

func _refresh_gallery() -> void:
	if gallery_grid != null:
		gallery_grid.queue_redraw()

var _shop_open := false
var _shop_width := 280.0

func _toggle_shop() -> void:
	if shop_panel == null:
		_build_shop()
	_shop_open = not _shop_open
	var tween = create_tween()
	if _shop_open:
		var vp_w = _get_vp_size().x
		tween.tween_property(shop_panel, "position:x", vp_w - _shop_width, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		var margin_tween = create_tween()
		margin_tween.tween_method(func(v): _hud_margin.add_theme_constant_override("margin_right", int(v)), 10.0, 10.0 + _shop_width, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	else:
		var vp_w = _get_vp_size().x
		tween.tween_property(shop_panel, "position:x", vp_w, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		var margin_tween = create_tween()
		margin_tween.tween_method(func(v): _hud_margin.add_theme_constant_override("margin_right", int(v)), 10.0 + _shop_width, 10.0, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

func _build_shop() -> void:
	shop_panel = PanelContainer.new()
	shop_panel.custom_minimum_size = Vector2(_shop_width, 0)
	var vp_size = _get_vp_size()
	shop_panel.size = Vector2(_shop_width, vp_size.y)
	shop_panel.position = Vector2(vp_size.x, 0) # Start offscreen right
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.06, 0.02, 0.95)
	panel_style.border_color = Color(0.6, 0.5, 0.2, 0.6)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(0)
	panel_style.set_content_margin_all(12)
	shop_panel.add_theme_stylebox_override("panel", panel_style)
	hud.add_child(shop_panel)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_panel.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)
	
	# Header
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	vbox.add_child(header)
	
	var title = Label.new()
	title.text = "UPGRADES"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	
	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(28, 28)
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.2, 0.1, 0.1, 0.9)
	close_style.set_corner_radius_all(4)
	close_style.set_content_margin_all(2)
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.pressed.connect(_toggle_shop)
	header.add_child(close_btn)
	
	var sep = HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.4, 0.35, 0.15, 0.4))
	vbox.add_child(sep)
	
	# Node unlock section
	_node_unlock_section = VBoxContainer.new()
	_node_unlock_section.add_theme_constant_override("separation", 6)
	vbox.add_child(_node_unlock_section)
	
	var nodes_title = Label.new()
	nodes_title.text = "UNLOCK NODES"
	nodes_title.add_theme_font_size_override("font_size", 12)
	nodes_title.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	_node_unlock_section.add_child(nodes_title)
	
	var _shop_all_defs = NodeFactory.get_all_defs()
	for node_id in _shop_all_defs:
		var ndef = _shop_all_defs[node_id]
		var unlock_cost = ndef.get("unlock_cost", 0.0)
		if unlock_cost <= 0.0:
			continue
		
		var card = HBoxContainer.new()
		card.add_theme_constant_override("separation", 6)
		_node_unlock_section.add_child(card)
		
		# Color swatch
		var swatch = ColorRect.new()
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.color = ndef.color
		card.add_child(swatch)
		
		var info = VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		card.add_child(info)
		
		var nname = Label.new()
		nname.text = ndef.name
		nname.add_theme_font_size_override("font_size", 11)
		nname.add_theme_color_override("font_color", ndef.color.lightened(0.3))
		info.add_child(nname)
		
		var ndesc = Label.new()
		ndesc.text = ndef.description
		ndesc.add_theme_font_size_override("font_size", 8)
		ndesc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.4))
		ndesc.autowrap_mode = TextServer.AUTOWRAP_WORD
		info.add_child(ndesc)
		
		var buy_btn = Button.new()
		buy_btn.custom_minimum_size = Vector2(80, 28)
		buy_btn.add_theme_font_size_override("font_size", 10)
		var nbtn_style = StyleBoxFlat.new()
		nbtn_style.bg_color = Color(0.1, 0.1, 0.18, 0.9)
		nbtn_style.border_color = ndef.color * 0.5
		nbtn_style.set_border_width_all(1)
		nbtn_style.set_corner_radius_all(4)
		nbtn_style.set_content_margin_all(3)
		buy_btn.add_theme_stylebox_override("normal", nbtn_style)
		var nbtn_hover = nbtn_style.duplicate()
		nbtn_hover.bg_color = Color(0.15, 0.15, 0.25, 0.9)
		nbtn_hover.border_color = ndef.color * 0.7
		buy_btn.add_theme_stylebox_override("hover", nbtn_hover)
		buy_btn.add_theme_color_override("font_color", ndef.color.lightened(0.3))
		buy_btn.pressed.connect(_buy_node_unlock.bind(node_id))
		card.add_child(buy_btn)
		node_unlock_buttons[node_id] = {"button": buy_btn, "card": card}
	
	var sep2 = HSeparator.new()
	sep2.add_theme_color_override("separator", Color(0.4, 0.35, 0.15, 0.4))
	vbox.add_child(sep2)
	
	# Upgrade rows
	for upgrade_id in GameState.UPGRADE_DEFS:
		var def = GameState.UPGRADE_DEFS[upgrade_id]
		var card = VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)
		vbox.add_child(card)
		
		var name_label = Label.new()
		name_label.text = def.name
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.6))
		card.add_child(name_label)
		
		var desc_label = Label.new()
		desc_label.text = def.description
		desc_label.add_theme_font_size_override("font_size", 9)
		desc_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.4))
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		card.add_child(desc_label)
		
		var buy_btn = Button.new()
		buy_btn.custom_minimum_size = Vector2(0, 32)
		buy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buy_btn.add_theme_font_size_override("font_size", 11)
		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.15, 0.12, 0.05, 0.9)
		btn_style.border_color = Color(0.5, 0.4, 0.15, 0.6)
		btn_style.set_border_width_all(1)
		btn_style.set_corner_radius_all(4)
		btn_style.set_content_margin_all(4)
		buy_btn.add_theme_stylebox_override("normal", btn_style)
		var btn_hover = btn_style.duplicate()
		btn_hover.bg_color = Color(0.22, 0.18, 0.08, 0.9)
		buy_btn.add_theme_stylebox_override("hover", btn_hover)
		buy_btn.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
		buy_btn.pressed.connect(_buy_shop_upgrade.bind(upgrade_id))
		card.add_child(buy_btn)
		shop_buttons[upgrade_id] = buy_btn
	
	_update_shop_buttons()

func _buy_node_unlock(node_id: String) -> void:
	if NodeFactory.buy_node_unlock(node_id):
		SFX.play_unlock()
		_update_shop_buttons()
		_update_palette_locks()

func _buy_shop_upgrade(upgrade_id: String) -> void:
	if GameState.buy_upgrade(upgrade_id):
		SFX.play_shop_buy()
		_update_shop_buttons()

func _update_shop_buttons() -> void:
	# Node unlock buttons
	for node_id in node_unlock_buttons:
		var data = node_unlock_buttons[node_id]
		var btn: Button = data.button
		var card: Control = data.card
		if NodeFactory.is_node_unlocked(node_id):
			card.visible = false
		else:
			card.visible = true
			var cost = NodeFactory.get_node_def(node_id).get("unlock_cost", 0.0)
			btn.text = "$%.0f" % cost
			btn.disabled = not GameState.can_afford(cost)
	# Hide section title if all unlocked
	if _node_unlock_section:
		var any_visible := false
		for node_id in node_unlock_buttons:
			if node_unlock_buttons[node_id].card.visible:
				any_visible = true
				break
		_node_unlock_section.visible = any_visible
	# Upgrade buttons
	for upgrade_id in shop_buttons:
		var btn: Button = shop_buttons[upgrade_id]
		var def = GameState.UPGRADE_DEFS[upgrade_id]
		var lvl = GameState.upgrades.get(upgrade_id, 0)
		if lvl >= def.max_level:
			btn.text = "MAX (Lv.%d)" % lvl
			btn.disabled = true
		else:
			var cost = GameState.get_upgrade_cost(upgrade_id)
			btn.text = "Lv.%d > %d\n$%.0f" % [lvl, lvl + 1, cost]
			btn.disabled = not GameState.can_afford(cost)

var _settings_modal: SettingsUI = null

func _show_settings() -> void:
	if _settings_modal:
		_settings_modal.queue_free()
		_settings_modal = null
		return
	_settings_modal = SettingsUI.create(hud, func(idx): _update_colorblind_filter(idx))
	_settings_modal.closed.connect(func(): _settings_modal = null)

var _game_menu: Control = null

func _show_game_menu() -> void:
	if _game_menu:
		_game_menu.queue_free()
		_game_menu = null
		return
	
	_game_menu = Control.new()
	_game_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_menu.add_child(dim)
	
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.12, 0.95)
	style.border_color = Color(0.4, 0.4, 0.6, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	_game_menu.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "Menu"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var sep = HSeparator.new()
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	vbox.add_child(sep)
	
	# Save
	_add_menu_modal_btn(vbox, "Save", Color(0.4, 0.9, 0.4), func():
		GameState.save_game()
		_close_game_menu()
	)
	
	# Load (with confirmation)
	_add_menu_modal_btn(vbox, "Load", Color(0.6, 0.7, 0.9), func():
		_close_game_menu()
		_show_load_confirm()
	)
	
	# Settings
	_add_menu_modal_btn(vbox, "Settings", Color(0.7, 0.7, 0.9), func():
		_close_game_menu()
		_show_settings()
	)
	
	# Spectrum Reset / Complete (prestige)
	if _can_prestige():
		var sep_prestige = HSeparator.new()
		sep_prestige.add_theme_stylebox_override("separator", StyleBoxLine.new())
		vbox.add_child(sep_prestige)
		var is_final = GameState.prestige_count >= 24 and _palette.discovery_count >= _palette.get_palette_size()
		var prestige_text = "Spectrum Complete" if is_final else "Spectrum Reset"
		_add_menu_modal_btn(vbox, prestige_text, Color(1.0, 0.85, 0.3), func():
			_close_game_menu()
			if is_final:
				_start_final_prestige()
			else:
				_show_prestige_selection()
		)
	
	var sep2 = HSeparator.new()
	sep2.add_theme_stylebox_override("separator", StyleBoxLine.new())
	vbox.add_child(sep2)
	
	# Save & Quit
	_add_menu_modal_btn(vbox, "Save & Quit", Color(1.0, 0.7, 0.7), func():
		GameState.save_game()
		get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
	)
	
	# Cancel
	_add_menu_modal_btn(vbox, "Cancel", Color(0.6, 0.6, 0.7), func():
		_close_game_menu()
	)
	
	hud.add_child(_game_menu)
	
	await get_tree().process_frame
	var vp = _get_vp_size()
	var sz = panel.size
	panel.position = Vector2(maxf((vp.x - sz.x) * 0.5, 0), maxf((vp.y - sz.y) * 0.5, 0))

func _close_game_menu() -> void:
	if _game_menu:
		_game_menu.queue_free()
		_game_menu = null

func _add_menu_modal_btn(parent: Control, text: String, color: Color, callback: Callable) -> void:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(180, 34)
	btn.add_theme_font_size_override("font_size", 14)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.1, 0.1, 0.18, 0.9)
	btn_style.border_color = color * 0.5
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(4)
	btn_style.set_content_margin_all(6)
	btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.15, 0.15, 0.25, 0.9)
	btn_hover.border_color = color * 0.8
	btn.add_theme_stylebox_override("hover", btn_hover)
	btn.add_theme_color_override("font_color", color)
	btn.pressed.connect(callback)
	parent.add_child(btn)

func _show_load_confirm() -> void:
	var modal = Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(dim)
	
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.12, 0.95)
	style.border_color = Color(0.5, 0.4, 0.3, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	modal.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "Load Last Save?"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var body = Label.new()
	body.text = "This will load your last autosave.\nAny unsaved progress will be lost."
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(body)
	
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 32)
	cancel_btn.add_theme_font_size_override("font_size", 13)
	var cancel_style = StyleBoxFlat.new()
	cancel_style.bg_color = Color(0.15, 0.15, 0.25, 0.9)
	cancel_style.border_color = Color(0.4, 0.4, 0.5, 0.5)
	cancel_style.set_border_width_all(1)
	cancel_style.set_corner_radius_all(4)
	cancel_style.set_content_margin_all(4)
	cancel_btn.add_theme_stylebox_override("normal", cancel_style)
	cancel_btn.pressed.connect(func(): modal.queue_free())
	btn_row.add_child(cancel_btn)
	
	var load_btn = Button.new()
	load_btn.text = "Load"
	load_btn.custom_minimum_size = Vector2(100, 32)
	load_btn.add_theme_font_size_override("font_size", 13)
	var load_style = StyleBoxFlat.new()
	load_style.bg_color = Color(0.1, 0.15, 0.3, 0.9)
	load_style.border_color = Color(0.4, 0.5, 0.8, 0.7)
	load_style.set_border_width_all(1)
	load_style.set_corner_radius_all(4)
	load_style.set_content_margin_all(4)
	load_btn.add_theme_stylebox_override("normal", load_style)
	var load_hover = load_style.duplicate()
	load_hover.bg_color = Color(0.15, 0.2, 0.4, 0.9)
	load_btn.add_theme_stylebox_override("hover", load_hover)
	load_btn.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	load_btn.pressed.connect(func():
		GameState.load_game()
		get_tree().change_scene_to_file("res://scenes/main_game.tscn")
	)
	btn_row.add_child(load_btn)
	
	hud.add_child(modal)
	
	await get_tree().process_frame
	var vp = _get_vp_size()
	var sz = panel.size
	panel.position = Vector2(maxf((vp.x - sz.x) * 0.5, 0), maxf((vp.y - sz.y) * 0.5, 0))

func _on_color_discovered(palette_index: int, color_name: String, color: Color, bonus_value: float) -> void:
	gallery_btn.text = "Collection %d/%d" % [_palette.discovery_count, _get_collection_total()]
	_refresh_gallery()
	SFX.play_discovery()
	_spawn_discovery_card(color_name, color, bonus_value)
	# Track prestige progress
	GameState.discoveries_since_prestige += 1
	# Steam achievements
	var achievement_id = "color_" + color_name.to_lower().replace(" ", "_")
	SteamManager.unlock_achievement(achievement_id)
	# Check tier — tier 5 is rare
	var entry = _palette.palette[palette_index]
	if entry.get("tier", 0) >= 5:
		SteamManager.unlock_achievement("tier_5")
	# Milestone achievements
	if _palette.discovery_count >= 1:
		SteamManager.unlock_achievement("first_color")
	if _palette.discovery_count >= 10:
		SteamManager.unlock_achievement("ten_colors")
	if _palette.discovery_count >= 50:
		SteamManager.unlock_achievement("fifty_colors")
	if _palette.discovery_count >= 100:
		SteamManager.unlock_achievement("hundred_colors")
	if _palette.discovery_count >= _palette.get_palette_size():
		SteamManager.unlock_achievement("all_colors")
	SteamManager.set_status("Discovering colors (%d/256)" % _palette.discovery_count)
	# Demo completion check
	if DemoConfig.is_demo() and _palette.discovery_count >= DemoConfig.get_demo_color_count():
		call_deferred("_show_demo_complete_banner")

func _spawn_discovery_card(color_name: String, color: Color, bonus_value: float) -> void:
	var card = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.9)
	style.border_color = color * 0.8
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)
	
	var title_lbl = Label.new()
	title_lbl.text = "NEW COLOR"
	title_lbl.add_theme_font_size_override("font_size", 9)
	title_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_lbl)
	
	var name_lbl = Label.new()
	name_lbl.text = color_name
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", color.lightened(0.3))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)
	
	if bonus_value > 0.0:
		var bonus_lbl = Label.new()
		bonus_lbl.text = "+$%.0f" % bonus_value
		bonus_lbl.add_theme_font_size_override("font_size", 11)
		bonus_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		bonus_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bonus_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(bonus_lbl)
	
	# Click to dismiss
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			_dismiss_discovery_card(card)
	)
	
	hud.add_child(card)
	
	# Position at top-center after layout
	await get_tree().process_frame
	var vp = _get_vp_size()
	var sz = card.size
	card.position = Vector2((vp.x - sz.x) * 0.5, 60 + _discovery_cards.size() * 70)
	card.set_meta("life", 3.5)
	card.set_meta("start_y", card.position.y)
	_discovery_cards.append(card)

func _dismiss_discovery_card(card: Control) -> void:
	if card and is_instance_valid(card):
		_discovery_cards.erase(card)
		card.queue_free()

func _update_discovery_cards(delta: float) -> void:
	var to_remove: Array[Control] = []
	for card in _discovery_cards:
		if not is_instance_valid(card):
			to_remove.append(card)
			continue
		var life = card.get_meta("life") - delta
		card.set_meta("life", life)
		# Float upward slowly
		card.position.y -= 8.0 * delta
		# Fade in last second
		if life <= 1.0:
			card.modulate.a = max(life, 0.0)
		if life <= 0.0:
			to_remove.append(card)
			card.queue_free()
	for card in to_remove:
		_discovery_cards.erase(card)

# ─── Flying Color Nodes (Recovery Mechanic) ────────────────────────────────────

func _update_flying_nodes(delta: float) -> void:
	# Only spawn/clear flying nodes when not in placement/template/connect modes
	if current_mode == Mode.PLACING or current_mode == Mode.PLACING_TEMPLATE or current_mode == Mode.CONNECTING:
		return
	
	var threshold = _get_flying_node_threshold()
	var should_spawn = GameState.currency < threshold
	var current_count = flying_nodes_layer.get_child_count()
	
	# Only spawn if player has no way to produce income (no seller + no source)
	var has_seller = _count_placed("seller") > 0
	var has_source = _count_placed("blue_source") > 0 or _count_placed("red_source") > 0 or _count_placed("yellow_source") > 0
	var can_earn = has_seller and has_source
	
	if should_spawn and not can_earn:
		# Spawn timer
		_flying_node_spawn_timer += delta
		if _flying_node_spawn_timer >= FLYING_NODE_SPAWN_INTERVAL:
			_flying_node_spawn_timer = 0.0
			_try_spawn_flying_node()
	else:
		# Clear all flying nodes when currency is above threshold or player can earn
		if current_count > 0:
			for child in flying_nodes_layer.get_children():
				child.queue_free()
		_flying_node_spawn_timer = 0.0

func _try_spawn_flying_node() -> void:
	# Limit max flying nodes to avoid clutter
	if flying_nodes_layer.get_child_count() >= 5:
		return
	
	# Pick a random discovered color (or default colors if none discovered)
	var node_color: Color
	if _palette.discovery_count > 0:
		# Pick from discovered colors, weighted toward lower tiers
		var discovered_indices: Array[int] = []
		for i in range(_palette.discovered.size()):
			if _palette.discovered[i]:
				discovered_indices.append(i)
		if discovered_indices.size() > 0:
			var idx = discovered_indices[randi() % discovered_indices.size()]
			node_color = _palette.palette[idx].color
		else:
			node_color = Color.from_hsv(randf(), 0.8, 1.0)
	else:
		# Default colors for fresh start: primaries
		var defaults = [Color.BLUE, Color.RED, Color.YELLOW, Color.CYAN, Color.MAGENTA, Color.GREEN]
		node_color = defaults[randi() % defaults.size()]
	
	# Calculate visible world bounds based on camera
	var vp_size = get_viewport().get_visible_rect().size
	var zoom = camera.zoom.x
	var cam_pos = camera.global_position
	var visible_size = vp_size / zoom
	var bounds = Rect2(
		cam_pos - visible_size * 0.5 + Vector2(50, 50),
		visible_size - Vector2(100, 100)
	)
	
	var node = FlyingColorNode.new()
	node.setup(node_color, bounds)
	# Use a lambda to capture the node reference for the callback
	node.on_collected = func(): _on_flying_node_collected(node)
	flying_nodes_layer.add_child(node)

func _on_flying_node_collected(node: FlyingColorNode) -> void:
	if not is_instance_valid(node):
		return
	
	# Give the reward
	GameState.add_currency(FLYING_NODE_REWARD)
	
	# Play SFX
	SFX.play_sell(FLYING_NODE_REWARD)
	
	# Remove the node (visual pop effect is handled by the node itself)
	node.queue_free()

func _try_click_flying_node(world_pos: Vector2) -> bool:
	# Check if clicking a flying node - returns true if a node was clicked
	for child in flying_nodes_layer.get_children():
		if child is FlyingColorNode:
			if child.is_clicked_at(world_pos):
				child.collect()
				return true
	return false

# ─── Demo Completion ──────────────────────────────────────────────────────────

var _demo_banner_shown := false

func _show_demo_complete_banner() -> void:
	if _demo_banner_shown:
		return
	_demo_banner_shown = true
	
	var modal = Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.7)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(bg)
	
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.98)
	style.border_color = Color(1.0, 0.85, 0.3, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(30)
	panel.add_theme_stylebox_override("panel", style)
	modal.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	
	# Congratulations header
	var congrats_lbl = Label.new()
	congrats_lbl.text = "Congratulations!"
	congrats_lbl.add_theme_font_size_override("font_size", 28)
	congrats_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	congrats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(congrats_lbl)
	
	# Achievement description
	var desc_lbl = Label.new()
	desc_lbl.text = "You discovered all %d colors in the demo!" % DemoConfig.get_demo_color_count()
	desc_lbl.add_theme_font_size_override("font_size", 15)
	desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc_lbl)
	
	# Separator
	var sep = HSeparator.new()
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	vbox.add_child(sep)
	
	# Full game pitch
	var pitch_lbl = Label.new()
	pitch_lbl.text = "The full game has so much more to explore:"
	pitch_lbl.add_theme_font_size_override("font_size", 13)
	pitch_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	pitch_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(pitch_lbl)
	
	# Feature list
	var features_lbl = Label.new()
	features_lbl.text = "256 colors across 6 tiers\n24 prestige resets with new source nodes\nSplitter nodes to duplicate orbs\nSaveable templates for complex layouts\nA hidden endgame for completionists"
	features_lbl.add_theme_font_size_override("font_size", 12)
	features_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8))
	features_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(features_lbl)
	
	# Separator
	var sep2 = HSeparator.new()
	sep2.add_theme_stylebox_override("separator", StyleBoxLine.new())
	vbox.add_child(sep2)
	
	# Button row
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)
	
	# Wishlist / Purchase on Steam button
	var steam_btn = Button.new()
	steam_btn.text = "Wishlist on Steam"
	steam_btn.custom_minimum_size = Vector2(200, 42)
	steam_btn.add_theme_font_size_override("font_size", 14)
	var steam_style = StyleBoxFlat.new()
	steam_style.bg_color = Color(0.1, 0.2, 0.4, 0.95)
	steam_style.border_color = Color(0.4, 0.7, 1.0, 0.8)
	steam_style.set_border_width_all(2)
	steam_style.set_corner_radius_all(6)
	steam_style.set_content_margin_all(8)
	steam_btn.add_theme_stylebox_override("normal", steam_style)
	var steam_hover = steam_style.duplicate()
	steam_hover.bg_color = Color(0.15, 0.3, 0.55, 0.95)
	steam_btn.add_theme_stylebox_override("hover", steam_hover)
	steam_btn.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	steam_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	steam_btn.pressed.connect(func(): OS.shell_open("https://store.steampowered.com/app/4459040/Huebound/"))
	btn_row.add_child(steam_btn)
	
	# Continue playing button
	var close_btn = Button.new()
	close_btn.text = "Continue Playing"
	close_btn.custom_minimum_size = Vector2(180, 42)
	close_btn.add_theme_font_size_override("font_size", 14)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.1, 0.1, 0.18, 0.9)
	btn_style.border_color = Color(0.4, 0.4, 0.6, 0.5)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(6)
	btn_style.set_content_margin_all(8)
	close_btn.add_theme_stylebox_override("normal", btn_style)
	var close_hover = btn_style.duplicate()
	close_hover.bg_color = Color(0.15, 0.15, 0.25, 0.9)
	close_btn.add_theme_stylebox_override("hover", close_hover)
	close_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.75))
	close_btn.pressed.connect(func(): modal.queue_free())
	btn_row.add_child(close_btn)
	
	# Subtext
	var sub_lbl = Label.new()
	sub_lbl.text = "You can keep playing the demo as long as you like."
	sub_lbl.add_theme_font_size_override("font_size", 10)
	sub_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub_lbl)
	
	hud.add_child(modal)
	await get_tree().process_frame
	var vp_size = _get_vp_size()
	var p_size = panel.size
	panel.position = Vector2(maxf((vp_size.x - p_size.x) * 0.5, 0), maxf((vp_size.y - p_size.y) * 0.5, 0))

# ─── Tutorial System ───────────────────────────────────────────────────────────

enum TutorialStep {
	INTRO,
	PLACE_BLUE,
	PLACE_SELLER,
	CONNECT_BLUE_SELLER,
	WAIT_FOR_SHOP,
	SHOP_INTRO,
	WAIT_FOR_RED_UNLOCK,
	NOTIFY_RED,
	WAIT_FOR_COMBINER_UNLOCK,
	NOTIFY_COMBINER,
	PLACE_NEW_BLUE,
	PLACE_COMBINER,
	PLACE_COMBINER_SELLER,
	CONNECT_COMBINER_CHAIN,
	WAIT_FOR_YELLOW_UNLOCK,
	NOTIFY_YELLOW,
	DONE,
}

# Snapshot counts at key tutorial moments
var _tut_skip_checked := false
var _tut_wait_timer := 0.0
var _tut_blue_count_before := 0
var _tut_red_count_before := 0
var _tut_seller_count_before := 0
var _tut_connection_count_before := 0

func _count_placed(node_id: String) -> int:
	var count := 0
	for node in NodeFactory.placed_nodes:
		if node.node_id == node_id:
			count += 1
	return count

func _start_tutorial() -> void:
	_tutorial_active = true
	_tutorial_step = TutorialStep.INTRO
	_show_tutorial_step()

func _end_tutorial() -> void:
	_tutorial_active = false
	_tutorial_step = TutorialStep.DONE
	GameState.tutorial_completed = true
	_clear_tutorial_ui()

func _clear_tutorial_ui() -> void:
	if _tutorial_overlay:
		_tutorial_overlay.queue_free()
		_tutorial_overlay = null
	if _tutorial_tooltip:
		_tutorial_tooltip.queue_free()
		_tutorial_tooltip = null
	if _tutorial_highlight:
		_tutorial_highlight.queue_free()
		_tutorial_highlight = null

func _show_tutorial_step() -> void:
	_clear_tutorial_ui()
	match _tutorial_step:
		TutorialStep.INTRO:
			_show_intro_panel()
		TutorialStep.PLACE_BLUE:
			_show_tutorial_hint(node_buttons.get("blue_source"),
				"Click Blue Source, then place\nit anywhere on the canvas.")
		TutorialStep.PLACE_SELLER:
			_show_tutorial_hint(node_buttons.get("seller"),
				"Now place a Seller.\nSellers convert orbs into Light.")
		TutorialStep.CONNECT_BLUE_SELLER:
			_show_tutorial_hint(connect_btn,
				"Connect them!\nClick Connect, then click the\nBlue Source, then the Seller.\n\nTip: Right-click to delete connections.")
		TutorialStep.WAIT_FOR_SHOP:
			_clear_tutorial_ui()
		TutorialStep.SHOP_INTRO:
			_show_tutorial_hint(shop_btn,
				"Open the Shop!\nUnlock new node types here.")
		TutorialStep.WAIT_FOR_RED_UNLOCK:
			_clear_tutorial_ui()
		TutorialStep.NOTIFY_RED:
			_show_tutorial_hint(node_buttons.get("red_source"),
				"Red Source unlocked!\nPlace red nodes and combine\ncolors for rarer hues worth more!")
		TutorialStep.WAIT_FOR_COMBINER_UNLOCK:
			_clear_tutorial_ui()
		TutorialStep.NOTIFY_COMBINER:
			_show_tutorial_hint(node_buttons.get("combiner"),
				"Combiner unlocked!\nMix colors together for new hues.")
		TutorialStep.PLACE_NEW_BLUE:
			_tut_blue_count_before = _count_placed("blue_source")
			_show_tutorial_hint(node_buttons.get("blue_source"),
				"Place another Blue Source\nfor your mixing chain.")
		TutorialStep.PLACE_COMBINER:
			_show_tutorial_hint(node_buttons.get("combiner"),
				"Place a Combiner anywhere.\nIt will mix connected inputs.")
		TutorialStep.PLACE_COMBINER_SELLER:
			_tut_seller_count_before = _count_placed("seller")
			_show_tutorial_hint(node_buttons.get("seller"),
				"Place a Seller to sell\nthe combined colors.")
		TutorialStep.CONNECT_COMBINER_CHAIN:
			_tut_connection_count_before = NodeFactory.connections.size()
			_show_tutorial_hint(connect_btn,
				"Wire it up!\nBlue + Red to Combiner,\nthen Combiner to Seller.")
		TutorialStep.WAIT_FOR_YELLOW_UNLOCK:
			_clear_tutorial_ui()
		TutorialStep.NOTIFY_YELLOW:
			_show_tutorial_hint(node_buttons.get("yellow_source"),
				"Yellow unlocked!\nThree primaries means many\nnew color combinations!")
		TutorialStep.DONE:
			_end_tutorial()

func _show_intro_panel() -> void:
	# Centered panel (no dimming)
	_tutorial_tooltip = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.12, 0.95)
	style.border_color = Color(0.4, 0.5, 0.9, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	_tutorial_tooltip.add_theme_stylebox_override("panel", style)
	_tutorial_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 12)
	_tutorial_tooltip.add_child(vbox)
	
	var title = Label.new()
	title.text = "HUEBOUND"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)
	
	var body = Label.new()
	body.text = "Mix colors. Discover new hues. Earn Light.\n\nPlace sources, connect them to sellers,\nand combine colors to unlock rarer shades."
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(body)
	
	var skip_box = CheckBox.new()
	skip_box.text = "Skip tutorial"
	skip_box.add_theme_font_size_override("font_size", 11)
	skip_box.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	skip_box.alignment = HORIZONTAL_ALIGNMENT_CENTER
	skip_box.toggled.connect(func(on): _tut_skip_checked = on)
	vbox.add_child(skip_box)
	
	var begin_btn = Button.new()
	begin_btn.text = "Begin"
	begin_btn.custom_minimum_size = Vector2(120, 32)
	begin_btn.add_theme_font_size_override("font_size", 13)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.15, 0.15, 0.3, 0.9)
	btn_style.border_color = Color(0.4, 0.5, 0.9, 0.7)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(4)
	btn_style.set_content_margin_all(4)
	begin_btn.add_theme_stylebox_override("normal", btn_style)
	begin_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	begin_btn.pressed.connect(func():
		if _tut_skip_checked:
			_end_tutorial()
		else:
			_advance_tutorial(TutorialStep.PLACE_BLUE)
	)
	vbox.add_child(begin_btn)
	
	hud.add_child(_tutorial_tooltip)
	
	# Center it after layout
	await get_tree().process_frame
	var vp = _get_vp_size()
	var size = _tutorial_tooltip.size
	_tutorial_tooltip.position = Vector2(maxf((vp.x - size.x) * 0.5, 0), maxf((vp.y - size.y) * 0.5, 0))

func _show_tutorial_hint(target: Control, text: String) -> void:
	if target == null:
		return
	
	# Arrow + tooltip drawn on a canvas overlay (no dimming, no highlight boxes)
	_tutorial_highlight = Control.new()
	_tutorial_highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tutorial_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_tutorial_highlight)
	
	# Tooltip box — click to dismiss
	_tutorial_tooltip = PanelContainer.new()
	var tip_style = StyleBoxFlat.new()
	tip_style.bg_color = Color(0.06, 0.06, 0.12, 0.92)
	tip_style.border_color = Color(0.4, 0.5, 0.9, 0.7)
	tip_style.set_border_width_all(2)
	tip_style.set_corner_radius_all(6)
	tip_style.set_content_margin_all(10)
	_tutorial_tooltip.add_theme_stylebox_override("panel", tip_style)
	_tutorial_tooltip.mouse_filter = Control.MOUSE_FILTER_STOP
	_tutorial_tooltip.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_clear_tutorial_ui()
	)
	
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_tooltip.add_child(label)
	
	hud.add_child(_tutorial_tooltip)
	
	# Position tooltip above target and draw arrow pointing down at it
	await get_tree().process_frame
	_position_tooltip_with_arrow(target)

func _position_tooltip_with_arrow(target: Control) -> void:
	if not is_instance_valid(_tutorial_tooltip) or not is_instance_valid(target):
		return
	var target_rect = target.get_global_rect()
	var tip_size = _tutorial_tooltip.size
	var vp = _get_vp_size()
	
	var target_cx = target_rect.position.x + target_rect.size.x / 2.0
	var target_top = target_rect.position.y
	var target_bottom = target_rect.position.y + target_rect.size.y
	
	# Try above the target with arrow pointing down
	var arrow_gap := 8.0
	var x = target_cx - tip_size.x / 2.0
	var y = target_top - tip_size.y - arrow_gap - 10.0
	var arrow_points_down := true
	
	# If above goes off screen, put below with arrow pointing up
	if y < 10:
		y = target_bottom + arrow_gap + 10.0
		arrow_points_down = false
	
	x = clampf(x, 10, vp.x - tip_size.x - 10)
	_tutorial_tooltip.position = Vector2(x, y)
	
	# Draw arrow on the highlight canvas
	if is_instance_valid(_tutorial_highlight):
		var arrow_target = target
		_tutorial_highlight.draw.connect(func(canvas = _tutorial_highlight):
			if not is_instance_valid(_tutorial_tooltip):
				return
			var tip_pos = _tutorial_tooltip.position
			var tip_sz = _tutorial_tooltip.size
			var arrow_x = clampf(target_cx, tip_pos.x + 10, tip_pos.x + tip_sz.x - 10)
			var arrow_color = Color(0.4, 0.5, 0.9, 0.8)
			if arrow_points_down:
				# Arrow from bottom of tooltip to top of target
				var from_y = tip_pos.y + tip_sz.y
				var to_y = target_top - 2
				canvas.draw_line(Vector2(arrow_x, from_y), Vector2(arrow_x, to_y), arrow_color, 2.0)
				# Arrowhead
				canvas.draw_line(Vector2(arrow_x, to_y), Vector2(arrow_x - 6, to_y - 8), arrow_color, 2.0)
				canvas.draw_line(Vector2(arrow_x, to_y), Vector2(arrow_x + 6, to_y - 8), arrow_color, 2.0)
			else:
				# Arrow from top of tooltip to bottom of target
				var from_y = tip_pos.y
				var to_y = target_bottom + 2
				canvas.draw_line(Vector2(arrow_x, from_y), Vector2(arrow_x, to_y), arrow_color, 2.0)
				# Arrowhead
				canvas.draw_line(Vector2(arrow_x, to_y), Vector2(arrow_x - 6, to_y + 8), arrow_color, 2.0)
				canvas.draw_line(Vector2(arrow_x, to_y), Vector2(arrow_x + 6, to_y + 8), arrow_color, 2.0)
		)
		_tutorial_highlight.queue_redraw()

func _check_tutorial_progress() -> void:
	match _tutorial_step:
		TutorialStep.INTRO:
			pass  # Handled by Begin button in _show_intro_panel
		TutorialStep.PLACE_BLUE:
			if _count_placed("blue_source") >= 1:
				_advance_tutorial(TutorialStep.PLACE_SELLER)
		TutorialStep.PLACE_SELLER:
			if _count_placed("seller") >= 1:
				_advance_tutorial(TutorialStep.CONNECT_BLUE_SELLER)
		TutorialStep.CONNECT_BLUE_SELLER:
			if NodeFactory.connections.size() >= 1:
				_tut_wait_timer = 5.0
				_advance_tutorial(TutorialStep.WAIT_FOR_SHOP)
		TutorialStep.WAIT_FOR_SHOP:
			_tut_wait_timer -= 0.25  # _check_tutorial_progress runs every 0.25s
			if _tut_wait_timer <= 0.0 and GameState.currency >= 10.0:
				_advance_tutorial(TutorialStep.SHOP_INTRO)
		TutorialStep.SHOP_INTRO:
			if _shop_open:
				_advance_tutorial(TutorialStep.WAIT_FOR_RED_UNLOCK)
		TutorialStep.WAIT_FOR_RED_UNLOCK:
			if NodeFactory.is_node_unlocked("red_source"):
				_advance_tutorial(TutorialStep.NOTIFY_RED)
		TutorialStep.NOTIFY_RED:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_advance_tutorial(TutorialStep.WAIT_FOR_COMBINER_UNLOCK)
		TutorialStep.WAIT_FOR_COMBINER_UNLOCK:
			if NodeFactory.is_node_unlocked("combiner"):
				_advance_tutorial(TutorialStep.NOTIFY_COMBINER)
		TutorialStep.NOTIFY_COMBINER:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_advance_tutorial(TutorialStep.PLACE_NEW_BLUE)
		TutorialStep.PLACE_NEW_BLUE:
			if _count_placed("blue_source") > _tut_blue_count_before:
				_advance_tutorial(TutorialStep.PLACE_COMBINER)
		TutorialStep.PLACE_COMBINER:
			if _count_placed("combiner") >= 1:
				_advance_tutorial(TutorialStep.PLACE_COMBINER_SELLER)
		TutorialStep.PLACE_COMBINER_SELLER:
			if _count_placed("seller") > _tut_seller_count_before:
				_advance_tutorial(TutorialStep.CONNECT_COMBINER_CHAIN)
		TutorialStep.CONNECT_COMBINER_CHAIN:
			# Need at least 3 new connections (blue->comb, red->comb, comb->seller)
			if NodeFactory.connections.size() >= _tut_connection_count_before + 3:
				_advance_tutorial(TutorialStep.WAIT_FOR_YELLOW_UNLOCK)
		TutorialStep.WAIT_FOR_YELLOW_UNLOCK:
			if NodeFactory.is_node_unlocked("yellow_source"):
				_advance_tutorial(TutorialStep.NOTIFY_YELLOW)
		TutorialStep.NOTIFY_YELLOW:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_end_tutorial()

func _advance_tutorial(next_step: int) -> void:
	_tutorial_step = next_step
	_show_tutorial_step()

# ─── Box Selection ────────────────────────────────────────────────────────────

func _start_box_select_visual() -> void:
	if _box_select_rect_node:
		_box_select_rect_node.queue_free()
	_box_select_rect_node = Node2D.new()
	_box_select_rect_node.z_index = 100
	_box_select_rect_node.draw.connect(_draw_box_select_rect)
	world.add_child(_box_select_rect_node)
	_update_mode_label()

func _update_box_select_visual() -> void:
	if _box_select_rect_node:
		_box_select_rect_node.queue_redraw()

func _draw_box_select_rect() -> void:
	if not _box_select_rect_node:
		return
	var rect = _get_box_select_rect()
	var fill = Color(0.4, 0.6, 1.0, 0.1)
	var border = Color(0.4, 0.6, 1.0, 0.5)
	_box_select_rect_node.draw_rect(rect, fill, true)
	_box_select_rect_node.draw_rect(rect, border, false, 2.0)

func _get_box_select_rect() -> Rect2:
	var tl = Vector2(min(_box_select_start.x, _box_select_end.x), min(_box_select_start.y, _box_select_end.y))
	var br = Vector2(max(_box_select_start.x, _box_select_end.x), max(_box_select_start.y, _box_select_end.y))
	return Rect2(tl, br - tl)

func _finish_box_select() -> void:
	var rect = _get_box_select_rect()
	# Remove the drag visual
	if _box_select_rect_node:
		_box_select_rect_node.queue_free()
		_box_select_rect_node = null
	# Find all nodes inside the rect
	_box_selected_nodes.clear()
	for node in NodeFactory.placed_nodes:
		if rect.has_point(node.global_position):
			_box_selected_nodes.append(node)
			node.selected = true
	current_mode = Mode.IDLE
	if _box_selected_nodes.size() > 0:
		_show_box_selection_info()
	_update_mode_label()

func _show_box_selection_info() -> void:
	var count = _box_selected_nodes.size()
	var total_refund := 0.0
	for node in _box_selected_nodes:
		total_refund += NodeFactory.get_node_sell_value(node.node_id)
	info_label.text = "[color=#6af][b]%d nodes selected[/b][/color]\n\nSell all for [color=#fc3]$%.0f[/color]" % [count, total_refund]
	upgrade_btn.visible = false
	delete_btn.visible = true
	_delete_confirm = false
	delete_btn.text = "Sell %d Nodes" % count
	save_template_btn.visible = _get_max_template_slots() > 0 and count >= 2

func _clear_box_selection() -> void:
	for node in _box_selected_nodes:
		if is_instance_valid(node):
			node.selected = false
	_box_selected_nodes.clear()
	if _box_select_rect_node:
		_box_select_rect_node.queue_free()
		_box_select_rect_node = null

func _delete_box_selected() -> void:
	for node in _box_selected_nodes:
		if is_instance_valid(node):
			var nid = node.node_id
			NodeFactory.unregister_node(node)
			var refund = NodeFactory.get_node_sell_value(nid)
			NodeFactory.record_sell(nid)
			GameState.add_currency(refund)
			node.queue_free()
	_box_selected_nodes.clear()
	SFX.play_delete()
	_deselect()

# ─── Template System ─────────────────────────────────────────────────────────

const TEMPLATE_UNLOCK_PRESTIGES := [2, 5, 10, 15, 20]

func _get_max_template_slots() -> int:
	var slots := 0
	for p in TEMPLATE_UNLOCK_PRESTIGES:
		if GameState.prestige_count >= p:
			slots += 1
	return slots

func _get_next_template_unlock() -> int:
	for p in TEMPLATE_UNLOCK_PRESTIGES:
		if GameState.prestige_count < p:
			return p
	return -1  # all unlocked

func _switch_palette_tab(idx: int) -> void:
	_nodes_tab_content.visible = (idx == 0)
	_templates_tab_content.visible = (idx == 1)
	# Style active/inactive tabs
	var active_style = StyleBoxFlat.new()
	active_style.bg_color = Color(0.15, 0.15, 0.3, 0.9)
	active_style.border_color = Color(0.5, 0.5, 0.8, 0.8)
	active_style.set_border_width_all(1)
	active_style.set_corner_radius_all(4)
	active_style.set_content_margin_all(3)
	var inactive_style = StyleBoxFlat.new()
	inactive_style.bg_color = Color(0.08, 0.08, 0.14, 0.9)
	inactive_style.border_color = Color(0.3, 0.3, 0.4, 0.5)
	inactive_style.set_border_width_all(1)
	inactive_style.set_corner_radius_all(4)
	inactive_style.set_content_margin_all(3)
	if idx == 0:
		_tab_nodes_btn.add_theme_stylebox_override("normal", active_style)
		_tab_nodes_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		_tab_templates_btn.add_theme_stylebox_override("normal", inactive_style)
		_tab_templates_btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	else:
		_tab_nodes_btn.add_theme_stylebox_override("normal", inactive_style)
		_tab_nodes_btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		_tab_templates_btn.add_theme_stylebox_override("normal", active_style)
		_tab_templates_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	if idx == 1:
		_rebuild_templates_list()

func _rebuild_templates_list() -> void:
	if not _templates_list:
		return
	for child in _templates_list.get_children():
		child.queue_free()
	
	var max_slots = _get_max_template_slots()
	# Update tab button text
	if _tab_templates_btn:
		_tab_templates_btn.text = "Templates (%d/%d)" % [GameState.templates.size(), max_slots]
	var used = GameState.templates.size()
	
	# Slot counter
	var slot_lbl = Label.new()
	slot_lbl.text = "Slots: %d / %d" % [used, max_slots]
	slot_lbl.add_theme_font_size_override("font_size", 10)
	slot_lbl.add_theme_color_override("font_color", Color(0.5, 0.6, 0.8))
	slot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_templates_list.add_child(slot_lbl)
	
	if GameState.templates.is_empty():
		var hint = Label.new()
		hint.text = "No templates yet.\nBox-select nodes, then click\nSave Template in the info panel."
		hint.add_theme_font_size_override("font_size", 10)
		hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD
		_templates_list.add_child(hint)
	else:
		for i in range(GameState.templates.size()):
			_add_template_card(_templates_list, GameState.templates[i], i)
	
	# Next unlock hint
	var next_p = _get_next_template_unlock()
	if next_p > 0:
		var unlock_lbl = Label.new()
		unlock_lbl.text = "Next slot at Prestige %d" % next_p
		unlock_lbl.add_theme_font_size_override("font_size", 9)
		unlock_lbl.add_theme_color_override("font_color", Color(0.4, 0.35, 0.55))
		unlock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_templates_list.add_child(unlock_lbl)

func _on_save_template_pressed() -> void:
	if _box_selected_nodes.size() < 2:
		return
	var max_slots = _get_max_template_slots()
	if GameState.templates.size() >= max_slots:
		info_label.text = "[color=#f66]All template slots full![/color]\n[color=#889]Delete one or prestige for more.[/color]"
		return
	_show_template_name_dialog()

func _show_template_name_dialog() -> void:
	if _template_name_dialog:
		_template_name_dialog.queue_free()
		_template_name_dialog = null
	_template_name_dialog = Control.new()
	_template_name_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_template_name_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.add_child(_template_name_dialog)
	
	var dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_template_name_dialog.add_child(dim)
	
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.12, 0.95)
	style.border_color = Color(0.3, 0.5, 0.8, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	_template_name_dialog.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	
	var title_lbl = Label.new()
	title_lbl.text = "Name Your Template"
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)
	
	var count_lbl = Label.new()
	count_lbl.text = "%d nodes selected" % _box_selected_nodes.size()
	count_lbl.add_theme_font_size_override("font_size", 11)
	count_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(count_lbl)
	
	var name_input = LineEdit.new()
	name_input.placeholder_text = "Template name..."
	name_input.text = "Template %d" % (GameState.templates.size() + 1)
	name_input.select_all_on_focus = true
	name_input.custom_minimum_size = Vector2(260, 32)
	name_input.add_theme_font_size_override("font_size", 13)
	vbox.add_child(name_input)
	
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)
	
	var save_btn = Button.new()
	save_btn.text = "Save"
	save_btn.custom_minimum_size = Vector2(80, 30)
	save_btn.add_theme_font_size_override("font_size", 12)
	var sb_style = StyleBoxFlat.new()
	sb_style.bg_color = Color(0.1, 0.15, 0.25, 0.9)
	sb_style.border_color = Color(0.3, 0.5, 0.8, 0.6)
	sb_style.set_border_width_all(1)
	sb_style.set_corner_radius_all(4)
	sb_style.set_content_margin_all(4)
	save_btn.add_theme_stylebox_override("normal", sb_style)
	save_btn.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	save_btn.pressed.connect(func():
		var tpl_name = name_input.text.strip_edges()
		if tpl_name.is_empty():
			tpl_name = "Template %d" % (GameState.templates.size() + 1)
		_finalize_save_template(tpl_name)
	)
	btn_row.add_child(save_btn)
	
	var cancel_dlg_btn = Button.new()
	cancel_dlg_btn.text = "Cancel"
	cancel_dlg_btn.custom_minimum_size = Vector2(80, 30)
	cancel_dlg_btn.add_theme_font_size_override("font_size", 12)
	var cb_style = StyleBoxFlat.new()
	cb_style.bg_color = Color(0.15, 0.1, 0.1, 0.9)
	cb_style.border_color = Color(0.5, 0.3, 0.3, 0.5)
	cb_style.set_border_width_all(1)
	cb_style.set_corner_radius_all(4)
	cb_style.set_content_margin_all(4)
	cancel_dlg_btn.add_theme_stylebox_override("normal", cb_style)
	cancel_dlg_btn.add_theme_color_override("font_color", Color(0.8, 0.5, 0.5))
	cancel_dlg_btn.pressed.connect(func():
		_template_name_dialog.queue_free()
		_template_name_dialog = null
	)
	btn_row.add_child(cancel_dlg_btn)
	
	# Enter key submits
	name_input.text_submitted.connect(func(_text):
		var tpl_name = name_input.text.strip_edges()
		if tpl_name.is_empty():
			tpl_name = "Template %d" % (GameState.templates.size() + 1)
		_finalize_save_template(tpl_name)
	)
	
	# Center panel
	await get_tree().process_frame
	if is_instance_valid(panel):
		var vp = _get_vp_size()
		var sz = panel.size
		panel.global_position = Vector2(maxf((vp.x - sz.x) * 0.5, 0), maxf((vp.y - sz.y) * 0.5, 0))
	name_input.grab_focus()

func _finalize_save_template(tpl_name: String) -> void:
	if _template_name_dialog:
		_template_name_dialog.queue_free()
		_template_name_dialog = null
	if _box_selected_nodes.size() < 2:
		return
	if GameState.templates.size() >= _get_max_template_slots():
		return
	# Compute center of selected nodes
	var center = Vector2.ZERO
	for node in _box_selected_nodes:
		center += node.global_position
	center /= _box_selected_nodes.size()
	# Build node list with offsets relative to center
	var tpl_nodes: Array[Dictionary] = []
	for node in _box_selected_nodes:
		var offset = node.global_position - center
		tpl_nodes.append({"node_id": node.node_id, "ox": offset.x, "oy": offset.y})
	# Build connection list (only connections between selected nodes)
	var tpl_connections: Array[Dictionary] = []
	for conn in NodeFactory.connections:
		var from_idx = _box_selected_nodes.find(conn.from)
		var to_idx = _box_selected_nodes.find(conn.to)
		if from_idx >= 0 and to_idx >= 0:
			tpl_connections.append({"from": from_idx, "to": to_idx})
	var template := {
		"name": tpl_name,
		"nodes": tpl_nodes,
		"connections": tpl_connections,
	}
	GameState.templates.append(template)
	GameState.save_game()
	_clear_box_selection()
	_deselect()
	info_label.text = "[color=#6af]Template saved![/color]\n[color=#aab]%s (%d nodes)[/color]" % [tpl_name, tpl_nodes.size()]
	save_template_btn.visible = false
	_rebuild_templates_list()
	# Show templates tab and make it visible if first template
	_tab_templates_btn.visible = true
	_switch_palette_tab(1)

func _add_template_card(parent: VBoxContainer, tpl: Dictionary, idx: int) -> void:
	var card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.08, 0.08, 0.15, 0.9)
	card_style.border_color = Color(0.25, 0.35, 0.6, 0.5)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(4)
	card_style.set_content_margin_all(6)
	card.add_theme_stylebox_override("panel", card_style)
	parent.add_child(card)
	
	# Hover preview
	card.mouse_entered.connect(func(): _show_template_hover(tpl, card))
	card.mouse_exited.connect(func(): _hide_template_hover())
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	card.add_child(hbox)
	
	var info_col = VBoxContainer.new()
	info_col.add_theme_constant_override("separation", 1)
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_col)
	
	var name_lbl = Label.new()
	name_lbl.text = tpl.get("name", "Template")
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_col.add_child(name_lbl)
	
	var node_count = tpl.get("nodes", []).size()
	var conn_count = tpl.get("connections", []).size()
	var total_cost = _get_template_cost(tpl)
	var detail_lbl = Label.new()
	detail_lbl.text = "%d nodes, %d links — $%.0f" % [node_count, conn_count, total_cost]
	detail_lbl.add_theme_font_size_override("font_size", 9)
	detail_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	detail_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_col.add_child(detail_lbl)
	
	var btn_col = HBoxContainer.new()
	btn_col.add_theme_constant_override("separation", 3)
	hbox.add_child(btn_col)
	
	var place_btn = Button.new()
	place_btn.text = "Place"
	place_btn.custom_minimum_size = Vector2(45, 22)
	place_btn.add_theme_font_size_override("font_size", 10)
	var pb_style = StyleBoxFlat.new()
	pb_style.bg_color = Color(0.1, 0.15, 0.25, 0.9)
	pb_style.border_color = Color(0.3, 0.5, 0.8, 0.6)
	pb_style.set_border_width_all(1)
	pb_style.set_corner_radius_all(3)
	pb_style.set_content_margin_all(2)
	place_btn.add_theme_stylebox_override("normal", pb_style)
	place_btn.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	place_btn.pressed.connect(func(): _start_placing_template(idx))
	btn_col.add_child(place_btn)
	
	var del_btn = Button.new()
	del_btn.text = "X"
	del_btn.custom_minimum_size = Vector2(22, 22)
	del_btn.add_theme_font_size_override("font_size", 10)
	var db_style = StyleBoxFlat.new()
	db_style.bg_color = Color(0.15, 0.08, 0.08, 0.9)
	db_style.border_color = Color(0.6, 0.3, 0.3, 0.5)
	db_style.set_border_width_all(1)
	db_style.set_corner_radius_all(3)
	db_style.set_content_margin_all(2)
	del_btn.add_theme_stylebox_override("normal", db_style)
	del_btn.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
	del_btn.pressed.connect(func():
		GameState.templates.remove_at(idx)
		GameState.save_game()
		_rebuild_templates_list()
	)
	btn_col.add_child(del_btn)

func _show_template_hover(tpl: Dictionary, card: Control) -> void:
	_hide_template_hover()
	var nodes_data = tpl.get("nodes", [])
	var conns_data = tpl.get("connections", [])
	if nodes_data.is_empty():
		return
	_template_hover_popup = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	style.border_color = Color(0.3, 0.5, 0.8, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	_template_hover_popup.add_theme_stylebox_override("panel", style)
	hud.add_child(_template_hover_popup)
	
	# Draw the template layout as a minimap
	var preview = Control.new()
	preview.custom_minimum_size = Vector2(180, 140)
	_template_hover_popup.add_child(preview)
	
	# Compute bounds for scaling
	var min_pos = Vector2(INF, INF)
	var max_pos = Vector2(-INF, -INF)
	for n in nodes_data:
		var p = Vector2(float(n.ox), float(n.oy))
		min_pos = Vector2(min(min_pos.x, p.x), min(min_pos.y, p.y))
		max_pos = Vector2(max(max_pos.x, p.x), max(max_pos.y, p.y))
	var span = max_pos - min_pos
	var scale_factor = 1.0
	if span.x > 0 or span.y > 0:
		scale_factor = min(160.0 / max(span.x, 1.0), 120.0 / max(span.y, 1.0))
	var center_offset = Vector2(90, 70)
	var data_center = (min_pos + max_pos) * 0.5
	
	# Draw connections as lines
	for conn in conns_data:
		var fi = int(conn.from)
		var ti = int(conn.to)
		if fi >= 0 and fi < nodes_data.size() and ti >= 0 and ti < nodes_data.size():
			var from_p = (Vector2(float(nodes_data[fi].ox), float(nodes_data[fi].oy)) - data_center) * scale_factor + center_offset
			var to_p = (Vector2(float(nodes_data[ti].ox), float(nodes_data[ti].oy)) - data_center) * scale_factor + center_offset
			var line = Line2D.new()
			line.add_point(from_p)
			line.add_point(to_p)
			line.default_color = Color(0.4, 0.5, 0.7, 0.4)
			line.width = 1.5
			preview.add_child(line)
	
	# Draw nodes as colored circles
	for n in nodes_data:
		var p = (Vector2(float(n.ox), float(n.oy)) - data_center) * scale_factor + center_offset
		var def = NodeFactory.get_node_def(n.node_id)
		var col = def.get("color", Color.WHITE) if not def.is_empty() else Color.WHITE
		var dot = ColorRect.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.color = col
		dot.position = p - Vector2(5, 5)
		preview.add_child(dot)
	
	# Position popup above the card
	await get_tree().process_frame
	if is_instance_valid(_template_hover_popup) and is_instance_valid(card):
		var card_rect = card.get_global_rect()
		var popup_size = _template_hover_popup.size
		_template_hover_popup.global_position = Vector2(
			card_rect.position.x,
			card_rect.position.y - popup_size.y - 4
		)

func _hide_template_hover() -> void:
	if _template_hover_popup:
		_template_hover_popup.queue_free()
		_template_hover_popup = null

func _get_template_cost(tpl: Dictionary) -> float:
	var total := 0.0
	for tpl_node in tpl.get("nodes", []):
		total += NodeFactory.get_node_cost(tpl_node.node_id)
	return total

func _start_placing_template(idx: int) -> void:
	if idx < 0 or idx >= GameState.templates.size():
		return
	_cancel_action()
	_placing_template = GameState.templates[idx]
	var total_cost = _get_template_cost(_placing_template)
	if not GameState.can_afford(total_cost):
		info_label.text = "[color=#f66]Not enough Light![/color]\nNeed [color=#fc3]$%.0f[/color]" % total_cost
		_placing_template = {}
		return
	# Create ghost previews
	current_mode = Mode.PLACING_TEMPLATE
	_template_previews.clear()
	for tpl_node in _placing_template.nodes:
		var preview = FactoryNode.new()
		preview.setup(tpl_node.node_id)
		preview.is_preview = true
		preview.modulate = Color(1, 1, 1, 0.4)
		nodes_layer.add_child(preview)
		_template_previews.append(preview)
	_update_mode_label()

func _try_place_template(pos: Vector2) -> void:
	if _placing_template.is_empty():
		return
	var center = NodeFactory.snap_to_grid(pos)
	# Check all positions are free
	for tpl_node in _placing_template.nodes:
		var target_pos = center + Vector2(float(tpl_node.ox), float(tpl_node.oy))
		target_pos = NodeFactory.snap_to_grid(target_pos)
		if not NodeFactory.is_position_free(target_pos):
			return
	# Check total cost
	var total_cost = _get_template_cost(_placing_template)
	if not GameState.spend_currency(total_cost):
		return
	# Place all nodes
	var placed: Array[FactoryNode] = []
	for tpl_node in _placing_template.nodes:
		var target_pos = center + Vector2(float(tpl_node.ox), float(tpl_node.oy))
		target_pos = NodeFactory.snap_to_grid(target_pos)
		NodeFactory.record_purchase(tpl_node.node_id)
		var node = FactoryNode.new()
		node.setup(tpl_node.node_id)
		node.global_position = target_pos
		nodes_layer.add_child(node)
		NodeFactory.register_node(node)
		placed.append(node)
	# Recreate connections
	for conn in _placing_template.get("connections", []):
		var from_idx = int(conn.from)
		var to_idx = int(conn.to)
		if from_idx >= 0 and from_idx < placed.size() and to_idx >= 0 and to_idx < placed.size():
			var from_node = placed[from_idx]
			var to_node = placed[to_idx]
			var already = false
			for existing in NodeFactory.connections:
				if existing.from == from_node and existing.to == to_node:
					already = true
					break
			if not already:
				NodeFactory.connections.append({"from": from_node, "to": to_node})
				var line = ConnectionLine.new()
				line.setup(from_node, to_node)
				connections_layer.add_child(line)
				NodeFactory.connection_made.emit(from_node, to_node)
	SFX.play_place()
	_cancel_action()

func _clear_template_previews() -> void:
	for preview in _template_previews:
		if is_instance_valid(preview):
			preview.queue_free()
	_template_previews.clear()
	_placing_template = {}

# ─── Prestige System ──────────────────────────────────────────────────────────

func _on_prestige_btn_pressed() -> void:
	if not _can_prestige():
		return
	var is_final = GameState.prestige_count >= 24 and _palette.discovery_count >= _palette.get_palette_size()
	if is_final:
		_start_final_prestige()
	else:
		_show_prestige_selection()

func _can_prestige() -> bool:
	if DemoConfig.is_demo() and GameState.prestige_count >= 1:
		return false
	if GameState.endgame_seen:
		return false
	if GameState.discoveries_since_prestige < 10:
		return false
	# Final prestige requires all 256 discovered
	if GameState.prestige_count >= 24:
		return _palette.discovery_count >= _palette.get_palette_size()
	# Normal prestige: need at least 3 eligible colors to offer
	return _get_prestige_eligible_colors().size() >= 3

func _get_prestige_eligible_colors() -> Array[Dictionary]:
	var eligible: Array[Dictionary] = []
	var primary_names := ["Blue", "Red", "Yellow"]
	for i in range(_palette.palette.size()):
		if not _palette.discovered[i]:
			continue
		var entry = _palette.palette[i]
		if entry.name in primary_names:
			continue
		if entry.name in GameState.prestige_sources:
			continue
		eligible.append(entry)
	return eligible

func _show_prestige_selection() -> void:
	var eligible = _get_prestige_eligible_colors()
	if eligible.size() < 3:
		return
	# Pick 3 random from eligible
	eligible.shuffle()
	var choices: Array[Dictionary] = []
	for i in range(3):
		choices.append(eligible[i])
	
	var modal = Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.75)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(dim)
	
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.12, 0.95)
	style.border_color = Color(0.8, 0.7, 0.2, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	modal.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "Spectrum Reset"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var desc = Label.new()
	desc.text = "Your Light, canvas, and upgrades will be reset.\nDiscoveries are kept. Choose a new permanent source:"
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc)
	
	var choices_row = HBoxContainer.new()
	choices_row.add_theme_constant_override("separation", 16)
	choices_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(choices_row)
	
	for entry in choices:
		var choice_btn = _create_prestige_choice(entry, modal)
		choices_row.add_child(choice_btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 32)
	cancel_btn.add_theme_font_size_override("font_size", 13)
	var cancel_style = StyleBoxFlat.new()
	cancel_style.bg_color = Color(0.15, 0.15, 0.25, 0.9)
	cancel_style.border_color = Color(0.4, 0.4, 0.5, 0.5)
	cancel_style.set_border_width_all(1)
	cancel_style.set_corner_radius_all(4)
	cancel_style.set_content_margin_all(4)
	cancel_btn.add_theme_stylebox_override("normal", cancel_style)
	cancel_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	cancel_btn.pressed.connect(func(): modal.queue_free())
	vbox.add_child(cancel_btn)
	
	hud.add_child(modal)
	
	await get_tree().process_frame
	var vp = _get_vp_size()
	var sz = panel.size
	panel.position = Vector2(maxf((vp.x - sz.x) * 0.5, 0), maxf((vp.y - sz.y) * 0.5, 0))

func _create_prestige_choice(entry: Dictionary, modal: Control) -> VBoxContainer:
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	
	# Color swatch
	var swatch = ColorRect.new()
	swatch.custom_minimum_size = Vector2(80, 80)
	swatch.color = entry.color
	col.add_child(swatch)
	
	# Color name
	var name_lbl = Label.new()
	name_lbl.text = entry.name
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_lbl)
	
	# Tier label
	var tier_lbl = Label.new()
	tier_lbl.text = "Tier %d" % entry.tier
	tier_lbl.add_theme_font_size_override("font_size", 11)
	tier_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tier_lbl)
	
	# Select button
	var btn = Button.new()
	btn.text = "Select"
	btn.custom_minimum_size = Vector2(80, 30)
	btn.add_theme_font_size_override("font_size", 13)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.1, 0.1, 0.18, 0.9)
	btn_style.border_color = Color(0.8, 0.7, 0.2, 0.5)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(4)
	btn_style.set_content_margin_all(4)
	btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.15, 0.15, 0.25, 0.9)
	btn_hover.border_color = Color(1.0, 0.85, 0.3, 0.8)
	btn.add_theme_stylebox_override("hover", btn_hover)
	btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	btn.pressed.connect(func():
		modal.queue_free()
		_execute_prestige(entry.name)
	)
	col.add_child(btn)
	
	return col

func _execute_prestige(chosen_color_name: String) -> void:
	GameState.prestige_sources.append(chosen_color_name)
	GameState.prestige_count += 1
	GameState.prestige_reset()
	GameState.save_game()
	get_tree().change_scene_to_file("res://scenes/main_game.tscn")

func _start_final_prestige() -> void:
	# Prestige 25 — Spectrum Complete
	GameState.prestige_count = 25
	GameState.prestige_reset()
	# Override: set currency to 1 for rainbow node
	GameState.currency = 1.0
	GameState.save_game()
	get_tree().change_scene_to_file("res://scenes/main_game.tscn")

func _is_endgame_state() -> bool:
	# Prestige 25 with rainbow available — strip normal shop
	return GameState.prestige_count >= 25 and not GameState.endgame_seen

# ─── Rainbow Endgame Sequence ─────────────────────────────────────────────────

var _endgame_orb_script: GDScript = null

func _get_endgame_orb_script() -> GDScript:
	if _endgame_orb_script == null:
		_endgame_orb_script = GDScript.new()
		_endgame_orb_script.source_code = 'extends Node2D

func _draw() -> void:
	var c: Color = get_meta("orb_color", Color.WHITE)
	var glow = c
	glow.a = 0.25
	draw_circle(Vector2.ZERO, 10, glow)
	draw_circle(Vector2.ZERO, 5, c)
	var bright = c.lightened(0.5)
	bright.a = 0.9
	draw_circle(Vector2.ZERO, 2.5, bright)
'
		_endgame_orb_script.reload()
	return _endgame_orb_script

func _create_endgame_orb(c: Color) -> Node2D:
	var orb = Node2D.new()
	orb.set_meta("orb_color", c)
	orb.set_script(_get_endgame_orb_script())
	return orb

func _trigger_rainbow_endgame(rainbow_node: Node2D) -> void:
	GameState.endgame_seen = true
	GameState.save_game()
	
	# Disable all input
	set_process_input(false)
	
	# Bright ROYGBIV spectrum for cycling
	var roygbiv := [
		Color(1.0, 0.0, 0.0),     # Red
		Color(1.0, 0.5, 0.0),     # Orange
		Color(1.0, 1.0, 0.0),     # Yellow
		Color(0.0, 1.0, 0.0),     # Green
		Color(0.0, 0.5, 1.0),     # Blue
		Color(0.3, 0.0, 1.0),     # Indigo
		Color(0.6, 0.0, 1.0),     # Violet
	]
	
	# Phase 1: Rainbow node smoothly transitions through bright ROYGBIV
	var tween = create_tween()
	rainbow_node.modulate = roygbiv[0]
	for _loop in range(3):
		for c in roygbiv:
			tween.tween_property(rainbow_node, "modulate", c, 0.3).set_trans(Tween.TRANS_SINE)
	# End on white
	tween.tween_property(rainbow_node, "modulate", Color.WHITE, 0.4).set_trans(Tween.TRANS_SINE)
	
	await tween.finished
	
	# Phase 2: Burst of colored orbs from the rainbow node in every direction
	var burst_tween = create_tween()
	var center = rainbow_node.global_position
	var orb_nodes: Array[Node2D] = []
	for i in range(256):
		# Pick a random bright ROYGBIV color for each orb
		var c: Color = roygbiv[randi() % roygbiv.size()]
		# Slight random hue shift for variety
		c = c.lightened(randf() * 0.3)
		
		var orb = _create_endgame_orb(c)
		orb.global_position = center
		world.add_child(orb)
		orb_nodes.append(orb)
		# Shoot in every direction — evenly spaced with slight randomness
		var angle = (float(i) / 256.0) * TAU + randf() * 0.3
		var dist = 200.0 + randf() * 600.0
		var target = center + Vector2(cos(angle), sin(angle)) * dist
		var duration = 1.5 + randf() * 1.5
		burst_tween.parallel().tween_property(orb, "global_position", target, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	# Phase 3: Camera zoom out
	burst_tween.parallel().tween_property(camera, "zoom", Vector2(0.3, 0.3), 3.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	
	await burst_tween.finished
	await get_tree().create_timer(1.0).timeout
	
	# Phase 4: Fade to white
	var white_overlay = ColorRect.new()
	white_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	white_overlay.color = Color(1, 1, 1, 0)
	white_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(white_overlay)
	
	var fade_tween = create_tween()
	fade_tween.tween_property(white_overlay, "color:a", 1.0, 2.0)
	await fade_tween.finished
	await get_tree().create_timer(1.0).timeout
	
	# Phase 5: Text sequence
	white_overlay.color = Color(0.03, 0.03, 0.06, 1.0)
	
	# Clean up world
	for orb in orb_nodes:
		if is_instance_valid(orb):
			orb.queue_free()
	
	var text_container = VBoxContainer.new()
	text_container.set_anchors_preset(Control.PRESET_CENTER)
	text_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	text_container.grow_vertical = Control.GROW_DIRECTION_BOTH
	text_container.alignment = BoxContainer.ALIGNMENT_CENTER
	text_container.add_theme_constant_override("separation", 20)
	hud.add_child(text_container)
	
	var line1 = Label.new()
	line1.text = "You found every color."
	line1.add_theme_font_size_override("font_size", 28)
	line1.add_theme_color_override("font_color", Color(0.6, 0.7, 1.0))
	line1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line1.modulate.a = 0
	text_container.add_child(line1)
	
	var t1 = create_tween()
	t1.tween_property(line1, "modulate:a", 1.0, 1.5)
	await t1.finished
	await get_tree().create_timer(2.0).timeout
	
	var line2 = Label.new()
	line2.text = "Thank you for playing."
	line2.add_theme_font_size_override("font_size", 22)
	line2.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	line2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line2.modulate.a = 0
	text_container.add_child(line2)
	
	var t2 = create_tween()
	t2.tween_property(line2, "modulate:a", 1.0, 1.5)
	await t2.finished
	await get_tree().create_timer(2.5).timeout
	
	# Fade out text
	var t3 = create_tween()
	t3.tween_property(text_container, "modulate:a", 0.0, 1.5)
	await t3.finished
	text_container.queue_free()
	
	# Phase 6: Credits scroll
	_show_endgame_credits(white_overlay)

func _show_endgame_credits(overlay: ColorRect) -> void:
	var scroll = VBoxContainer.new()
	scroll.set_anchors_preset(Control.PRESET_CENTER)
	scroll.grow_horizontal = Control.GROW_DIRECTION_BOTH
	scroll.grow_vertical = Control.GROW_DIRECTION_BOTH
	scroll.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_theme_constant_override("separation", 16)
	overlay.add_child(scroll)
	
	var credits_title = Label.new()
	credits_title.text = "HUEBOUND"
	credits_title.add_theme_font_size_override("font_size", 36)
	credits_title.add_theme_color_override("font_color", Color(0.6, 0.7, 1.0))
	credits_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scroll.add_child(credits_title)
	
	var dev_header = Label.new()
	dev_header.text = "Developed by"
	dev_header.add_theme_font_size_override("font_size", 14)
	dev_header.add_theme_color_override("font_color", Color(0.4, 0.45, 0.6))
	dev_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scroll.add_child(dev_header)
	
	var dev_name = Label.new()
	dev_name.text = "Dan Hicks"
	dev_name.add_theme_font_size_override("font_size", 20)
	dev_name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	dev_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scroll.add_child(dev_name)
	
	var feedback_header = Label.new()
	feedback_header.text = "Community Feedback"
	feedback_header.add_theme_font_size_override("font_size", 14)
	feedback_header.add_theme_color_override("font_color", Color(0.4, 0.45, 0.6))
	feedback_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scroll.add_child(feedback_header)
	
	var feedback_names = Label.new()
	feedback_names.text = "2blade30  -  Acamaeda  -  DavejHale  -  De_inordinatio\nEelsEverywhere  -  Ellensiel  -  GhostDog43\nKingManuel  -  konnichimade  -  LustreOfHavoc\nMercy_2.0  -  Pooplayer1  -  Ravery\nThe_God_Kvothe  -  xtagtv"
	feedback_names.add_theme_font_size_override("font_size", 15)
	feedback_names.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8))
	feedback_names.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scroll.add_child(feedback_names)
	
	var closing = Label.new()
	closing.text = "All colors, just like all people, are beautiful."
	closing.add_theme_font_size_override("font_size", 13)
	closing.add_theme_color_override("font_color", Color(0.35, 0.4, 0.55))
	closing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scroll.add_child(closing)
	
	# Fade in credits
	scroll.modulate.a = 0
	var fade_in = create_tween()
	fade_in.tween_property(scroll, "modulate:a", 1.0, 2.0)
	await fade_in.finished
	await get_tree().create_timer(6.0).timeout
	
	# Fade out and return to title
	var fade_out = create_tween()
	fade_out.tween_property(overlay, "modulate:a", 0.0, 2.0)
	await fade_out.finished
	
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
