extends Node2D
class_name FactoryNode

signal orb_produced(orb: Dictionary)
signal orb_received(orb: Dictionary)

var node_id: String = ""
var node_def: Dictionary = {}
var node_type: int = NodeFactory.NodeType.PRODUCER

# Production — orbs are {color: Color, sources: Array[Color]}
var production_timer: float = 0.0
var output_buffer: Array[Dictionary] = []
var input_buffer: Array[Dictionary] = []
var max_buffer: int = 5
var _base_buffer: int = 5
var _input_slots: Dictionary = {} # For combiners: {source_node_id: Array[Dictionary]}

# Visual
var base_color: Color = Color.WHITE
var shape: int = NodeFactory.Shape.CIRCLE
var glow_intensity: float = 0.0
var hover: bool = false
var selected: bool = false
var pulse_time: float = 0.0

# Level (only meaningful for Processors/Combiners)
var level: int = 1
var is_preview: bool = false
var _palette: Node = null

var _has_processed := false
var _last_produced_color: Color = Color.TRANSPARENT

# Per-node CPS tracking
var _cps_earned_this_sec: float = 0.0
var _cps_upkeep_this_sec: float = 0.0
var _cps_history: Array[float] = []
var _cps_timer: float = 0.0
var node_cps: float = 0.0

func setup(id: String) -> void:
	node_id = id
	node_def = NodeFactory.get_node_def(id)
	if node_def.is_empty():
		return
	node_type = node_def.type
	base_color = node_def.color
	shape = node_def.shape

func _ready() -> void:
	_palette = get_node_or_null("/root/ColorPalette")
	if is_preview:
		return
	# Set up collision area for hover only (clicks handled via NodeFactory.get_node_at)
	var area = Area2D.new()
	area.input_pickable = false
	var collision = CollisionShape2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = NodeFactory.NODE_RADIUS + 5
	collision.shape = circle_shape
	area.add_child(collision)
	add_child(area)
	area.mouse_entered.connect(func(): hover = true; queue_redraw())
	area.mouse_exited.connect(func(): hover = false; queue_redraw())

func _process(delta: float) -> void:
	pulse_time += delta * 2.0
	
	if node_def.is_empty() or is_preview:
		return
	
	# Apply global buffer upgrade
	max_buffer = _base_buffer + GameState.get_upgrade_bonus("buffer_size")
	
	var base_rate: float = node_def.rate
	
	# CPS tracking
	_cps_timer += delta
	if _cps_timer >= 1.0:
		_cps_timer -= 1.0
		_cps_history.append(_cps_earned_this_sec - _cps_upkeep_this_sec)
		_cps_earned_this_sec = 0.0
		_cps_upkeep_this_sec = 0.0
		if _cps_history.size() > 3:
			_cps_history.pop_front()
		var total := 0.0
		for h in _cps_history:
			total += h
		node_cps = total / _cps_history.size()
		# Snap to zero when effectively idle
		if abs(node_cps) < 0.05:
			node_cps = 0.0
			_cps_history.clear()
	
	# Upkeep: drain currency per second (only after first orb processed, skip in zen mode)
	var upkeep = node_def.get("upkeep", 0.0)
	if upkeep > 0.0 and _has_processed and not GameState.zen_mode:
		var cost = upkeep * delta * GameState.game_speed
		if GameState.currency < cost:
			return # Stall if can't afford upkeep
		GameState.currency -= cost
		_cps_upkeep_this_sec += cost
	
	match node_type:
		NodeFactory.NodeType.PRODUCER:
			_process_producer(delta, base_rate * GameState.get_upgrade_mult("production_speed"))
		NodeFactory.NodeType.PROCESSOR:
			_process_processor(delta, base_rate * level)
		NodeFactory.NodeType.SELLER:
			_process_seller(delta, base_rate)
		NodeFactory.NodeType.SPLITTER:
			_process_splitter(delta, base_rate)
	
	# Glow based on buffer fullness
	var target_glow = 0.0
	if output_buffer.size() > 0:
		target_glow = float(output_buffer.size()) / max_buffer
	var old_glow = glow_intensity
	glow_intensity = lerp(glow_intensity, target_glow, delta * 3.0)
	
	# Only redraw when visual state actually changes
	if abs(glow_intensity - old_glow) > 0.005 or selected:
		queue_redraw()

func _process_producer(delta: float, rate: float) -> void:
	if output_buffer.size() >= max_buffer:
		return
	production_timer += delta * rate * GameState.game_speed
	if production_timer >= 1.0:
		production_timer -= 1.0
		var orb = {"color": base_color, "sources": [base_color]}
		output_buffer.append(orb)
		orb_produced.emit(orb)

func _process_processor(delta: float, rate: float) -> void:
	# Check each connected input has at least one orb in its slot
	var connections = NodeFactory.get_connections_to(self)
	var num_inputs = connections.size()
	if num_inputs < 2:
		return
	# Clean up slots for disconnected sources
	var connected_ids: Array[int] = []
	for conn in connections:
		var sid = conn.from.get_instance_id()
		connected_ids.append(sid)
	for key in _input_slots.keys():
		if key not in connected_ids:
			_input_slots.erase(key)
	# Check all connected inputs have at least one orb
	var all_ready := true
	for conn in connections:
		var sid = conn.from.get_instance_id()
		if not _input_slots.has(sid) or _input_slots[sid].is_empty():
			all_ready = false
			break
	if not all_ready:
		return
	# Peek at input orbs to find recipe match
	var input_names: Array[String] = []
	var input_colors: Array[Color] = []
	for conn in connections:
		var sid = conn.from.get_instance_id()
		var peek_orb = _input_slots[sid][0]
		var nearest_idx = _palette.find_nearest_color(peek_orb.color)
		input_names.append(_palette.palette[nearest_idx].name)
		input_colors.append(peek_orb.color)
	var recipe_idx = _palette.lookup_recipe(input_names)
	if output_buffer.size() >= max_buffer:
		return
	production_timer += delta * rate * GameState.game_speed
	if production_timer >= 1.0:
		production_timer -= 1.0
		# Consume one orb from each input slot
		var all_sources: Array[Color] = []
		for conn in connections:
			var sid = conn.from.get_instance_id()
			var orb = _input_slots[sid].pop_front()
			for s in orb.sources:
				if not _has_similar_color(all_sources, s):
					all_sources.append(s)
		var result_color: Color
		if recipe_idx >= 0:
			# Valid recipe — output the exact palette color
			result_color = _palette.palette[recipe_idx].color
		else:
			# No recipe match — CMY fallback, produces a muddy/low-value color
			result_color = _palette.mix_colors(input_colors)
		var result = {"color": result_color, "sources": all_sources}
		output_buffer.append(result)
		orb_produced.emit(result)
		_last_produced_color = result_color
		_has_processed = true

func _process_seller(_delta: float, _rate: float) -> void:
	while not input_buffer.is_empty():
		var orb = input_buffer.pop_front()
		var sale = _palette.sell_color(orb.color, orb.sources)
		# In zen mode: no currency earned, just discovery
		if GameState.zen_mode:
			continue
		# Small bonus for mixing more sources (linear, not exponential)
		var unique_sources = orb.sources.size()
		var mix_mult = 1.0 + max(unique_sources - 1, 0) * 0.25
		var sell_mult = GameState.get_upgrade_mult("sell_value")
		var disc_mult = GameState.get_upgrade_mult("discovery_bonus")
		var base_earn = sale.value * mix_mult * sell_mult
		var bonus_earn = sale.bonus * disc_mult
		var total = base_earn + bonus_earn
		GameState.add_currency(total)
		_cps_earned_this_sec += base_earn  # Discovery bonus excluded from CPS
		_spawn_float_text(total, orb.color)

func _spawn_float_text(amount: float, color: Color) -> void:
	var label = Label.new()
	if amount >= 1000.0:
		label.text = "+%.1fk" % (amount / 1000.0)
	else:
		label.text = "+%.1f" % amount
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-20, -NodeFactory.NODE_RADIUS - 20)
	add_child(label)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.2)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)

func _process_splitter(delta: float, rate: float) -> void:
	if input_buffer.is_empty():
		return
	if output_buffer.size() >= max_buffer - 1: # Need room for 2
		return
	production_timer += delta * rate * GameState.game_speed
	if production_timer >= 1.0:
		production_timer -= 1.0
		var orb = input_buffer.pop_front()
		# Clone into two orbs, each with half the sources (halves value)
		var half = max(ceili(orb.sources.size() / 2.0), 1)
		var sources_a: Array[Color] = []
		var sources_b: Array[Color] = []
		for i in range(orb.sources.size()):
			if i < half:
				sources_a.append(orb.sources[i])
			else:
				sources_b.append(orb.sources[i])
		if sources_b.is_empty():
			sources_b = sources_a.duplicate()
		var copy1 = {"color": orb.color, "sources": sources_a}
		var copy2 = {"color": orb.color, "sources": sources_b}
		output_buffer.append(copy1)
		output_buffer.append(copy2)
		orb_produced.emit(copy1)
		_has_processed = true

func receive_orb(orb: Dictionary, source_node: Node2D = null) -> bool:
	if node_type == NodeFactory.NodeType.PRODUCER:
		return false
	if node_type == NodeFactory.NodeType.PROCESSOR and source_node:
		# Combiner: route to per-connection slot
		var sid = source_node.get_instance_id()
		if not _input_slots.has(sid):
			_input_slots[sid] = []
		# Limit per-slot buffer
		if _input_slots[sid].size() >= max_buffer:
			return false
		_input_slots[sid].append(orb)
		orb_received.emit(orb)
		return true
	# Sellers and others: flat input buffer
	if input_buffer.size() >= max_buffer:
		return false
	input_buffer.append(orb)
	orb_received.emit(orb)
	return true

func take_orb() -> Dictionary:
	if output_buffer.is_empty():
		return {}
	return output_buffer.pop_front()

func _has_similar_color(arr: Array[Color], c: Color) -> bool:
	for existing in arr:
		if existing.is_equal_approx(c):
			return true
	return false

func has_output() -> bool:
	return not output_buffer.is_empty()

func can_receive() -> bool:
	if node_type == NodeFactory.NodeType.PRODUCER:
		return false
	return input_buffer.size() < max_buffer

func get_max_level() -> int:
	return node_def.get("max_level", 1)

func is_max_level() -> bool:
	return level >= get_max_level()

func get_upgrade_cost() -> float:
	return node_def.cost * level * 1.5

func upgrade() -> bool:
	if is_max_level():
		return false
	var cost = get_upgrade_cost()
	if GameState.spend_currency(cost):
		level += 1
		_base_buffer = 5 + level * 2
		queue_redraw()
		return true
	return false

func _draw() -> void:
	var radius = NodeFactory.NODE_RADIUS
	var color = base_color
	
	# Glow effect (skip outer glow on Low quality)
	if glow_intensity > 0.0 or hover:
		var glow_color = color
		glow_color.a = 0.15 + glow_intensity * 0.2
		if hover:
			glow_color.a += 0.15
		draw_circle(Vector2.ZERO, radius + 12, glow_color)
		if GameState.orb_quality >= 1:
			glow_color.a *= 0.5
			draw_circle(Vector2.ZERO, radius + 20, glow_color)
	
	# Selection ring
	if selected:
		var sel_color = Color(1, 1, 1, 0.4 + sin(pulse_time * 3.0) * 0.2)
		_draw_shape(Vector2.ZERO, radius + 6, shape, sel_color, false)
	
	# Main shape - filled
	var bg_color = Color(0.1, 0.1, 0.15, 0.9)
	_draw_shape(Vector2.ZERO, radius, shape, bg_color, true)
	
	# Border
	var border_color = color
	border_color.a = 0.8 + glow_intensity * 0.2
	_draw_shape(Vector2.ZERO, radius, shape, border_color, false)
	
	# Inner detail - buffer indicator
	if output_buffer.size() > 0 or input_buffer.size() > 0:
		var fill = float(output_buffer.size() + input_buffer.size()) / (max_buffer * 2)
		var inner_radius = radius * 0.6 * fill
		var inner_color = color
		inner_color.a = 0.3
		draw_circle(Vector2.ZERO, inner_radius, inner_color)
	
	# Level indicator (only for upgradeable nodes)
	if level > 1 and node_type == NodeFactory.NodeType.PROCESSOR:
		var font = ThemeDB.fallback_font
		var level_text = str(level)
		var text_size = font.get_string_size(level_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
		draw_string(font, Vector2(-text_size.x / 2, text_size.y / 2 - 2), level_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(1, 1, 1, 0.7))
	
	# Node type icon (simple geometric indicator)
	match node_type:
		NodeFactory.NodeType.PRODUCER:
			# Small plus sign
			var s = 6.0
			draw_line(Vector2(-s, 0), Vector2(s, 0), color, 2.0)
			draw_line(Vector2(0, -s), Vector2(0, s), color, 2.0)
		NodeFactory.NodeType.PROCESSOR:
			# Small arrows merging
			var s = 6.0
			draw_line(Vector2(-s, -s), Vector2(0, 0), color, 2.0)
			draw_line(Vector2(-s, s), Vector2(0, 0), color, 2.0)
			draw_line(Vector2(0, 0), Vector2(s, 0), color, 2.0)
		NodeFactory.NodeType.SELLER:
			# Dollar sign-ish
			var s = 6.0
			draw_line(Vector2(0, -s), Vector2(0, s), color, 2.0)
			draw_line(Vector2(-s * 0.5, -s * 0.3), Vector2(s * 0.5, -s * 0.3), color, 1.5)
			draw_line(Vector2(-s * 0.5, s * 0.3), Vector2(s * 0.5, s * 0.3), color, 1.5)
		NodeFactory.NodeType.SPLITTER:
			# Fork / Y shape
			var s = 6.0
			draw_line(Vector2(0, s), Vector2(0, 0), color, 2.0)
			draw_line(Vector2(0, 0), Vector2(-s, -s), color, 2.0)
			draw_line(Vector2(0, 0), Vector2(s, -s), color, 2.0)
	
	# CPS indicator above node
	if not is_preview and abs(node_cps) > 0.01:
		var font = ThemeDB.fallback_font
		var cps_text: String
		if abs(node_cps) >= 1000.0:
			cps_text = "%.1fk/s" % (node_cps / 1000.0)
		else:
			cps_text = "%.1f/s" % node_cps
		var cps_color: Color
		if node_cps > 0:
			cps_color = Color(0.4, 1.0, 0.4, 0.7)
		else:
			cps_color = Color(1.0, 0.4, 0.4, 0.7)
		var text_size = font.get_string_size(cps_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 9)
		var pos = Vector2(-text_size.x / 2, -(radius + 14))
		draw_string(font, pos, cps_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, cps_color)

func _draw_shape(center: Vector2, radius: float, s: int, color: Color, filled: bool) -> void:
	match s:
		NodeFactory.Shape.CIRCLE:
			if filled:
				draw_circle(center, radius, color)
			else:
				draw_arc(center, radius, 0, TAU, 64, color, 2.0)
		NodeFactory.Shape.HEXAGON:
			var points = _get_polygon_points(center, radius, 6)
			if filled:
				draw_colored_polygon(points, color)
			else:
				for i in range(points.size()):
					draw_line(points[i], points[(i + 1) % points.size()], color, 2.0)
		NodeFactory.Shape.DIAMOND:
			var points = _get_polygon_points(center, radius, 4, PI / 4.0)
			if filled:
				draw_colored_polygon(points, color)
			else:
				for i in range(points.size()):
					draw_line(points[i], points[(i + 1) % points.size()], color, 2.0)
		NodeFactory.Shape.SQUARE:
			var points = _get_polygon_points(center, radius, 4)
			if filled:
				draw_colored_polygon(points, color)
			else:
				for i in range(points.size()):
					draw_line(points[i], points[(i + 1) % points.size()], color, 2.0)
		NodeFactory.Shape.OCTAGON:
			var points = _get_polygon_points(center, radius, 8)
			if filled:
				draw_colored_polygon(points, color)
			else:
				for i in range(points.size()):
					draw_line(points[i], points[(i + 1) % points.size()], color, 2.0)

func _get_polygon_points(center: Vector2, radius: float, sides: int, offset: float = 0.0) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(sides):
		var angle = (TAU / sides) * i + offset - PI / 2.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points
