extends Node2D
class_name ColorNode

signal clicked(color: Color)
signal currency_recovered(amount: float)

# Visual properties
var base_color: Color = Color.WHITE
var size: float = 40.0
var glow_intensity: float = 0.8

# Movement
var velocity: Vector2 = Vector2.ZERO
var movement_timer: float = 0.0
var wiggle_phase: float = 0.0
var wiggle_speed: float = 2.0

# Lifecycle
var is_popping: bool = false
var pop_progress: float = 0.0

# Recovery mode: special floating node that gives currency when clicked
var is_recovery_node: bool = false

func _ready() -> void:
	# Create visual container
	var canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	
	var container = Control.new()
	container.set_anchors_packing(Control.PACK_FULL_RECT)
	canvas_layer.add_child(container)
	
	var outer_rect: ColorRect
	var inner_glow: ColorRect
	
	# Different visual style for recovery nodes (golden/white distinctive look)
	if is_recovery_node:
		# Recovery node: golden aura, white core, brighter glow
		outer_rect = _create_color_rect(Color(1.0, 0.9, 0.4).lightened(0.5), size * 2.5)
		container.add_child(outer_rect)
		
		inner_glow = _create_color_rect(Color.WHITE, size * 1.8)
		inner_glow.modulate.a = 0.6
		container.add_child(inner_glow)
		
		var core_rect = _create_color_rect(Color(1.0, 0.95, 0.7), size * 1.0)
		container.add_child(core_rect)
		
		# Pulsing golden aura for recovery nodes (faster pulse)
		var tween = create_tween()
		tween.tween_property(inner_glow, "modulate:a", 0.6, 0.8).set_trans(TWEEN_TRANS_CIRC).set_ease(TWEEN_EASE_IN_OUT)
		tween.tween_property(inner_glow, "modulate:a", 1.0, 0.8).set_trans(TWEEN_TRANS_CIRC).set_ease(TWEEN_EASE_IN_OUT).set_loops()
	else:
		# Normal node visual style
		outer_rect = _create_color_rect(base_color.lightened(0.3), size * 2)
		container.add_child(outer_rect)
		
		inner_glow = _create_color_rect(
			base_color.linear_to_srgb().linear_interpolate(Color.WHITE, glow_intensity),
			size * 1.5
		)
		container.add_child(inner_glow)
		
		var core_rect = _create_color_rect(base_color, size * 0.8)
		container.add_child(core_rect)
		
		# Pulse animation for inner glow
		var tween = create_tween()
		tween.tween_property(inner_glow, "modulate:a", 0.4, 1.0).set_trans(TWEEN_TRANS_CIRC).set_ease(TWEEN_EASE_IN_OUT)
		tween.tween_property(inner_glow, "modulate:a", 0.8, 1.0).set_trans(TWEEN_TRANS_CIRC).set_ease(TWEEN_EASE_IN_OUT).set_loops()
	
	# Create collision area for clicking
	var area = Area2D.new()
	area.mouse_entered.connect(_on_mouse_entered)
	area.mouse_exited.connect(_on_mouse_exited)
	add_child(area)
	
	var collision = CollisionShape2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = size / 2.0
	collision.shape = circle_shape
	area.add_child(collision)

var _hovered: bool = false

func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()

func _on_mouse_exited() -> void:
	_hovered = false
	queue_redraw()

# Handle clicks via mouse button press signal on the area
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		is_popping = true
		if is_recovery_node:
			currency_recovered.emit(50.0)
		else:
			clicked.emit(base_color)
		queue_redraw()

func setup(color: Color, position: Vector2) -> void:
	base_color = color
	global_position = position
	
	# Random initial velocity within reasonable bounds
	var angle = randf() * TAU
	velocity = Vector2(cos(angle), sin(angle)) * (30.0 + randf_range(-10.0, 10.0))

func _process(delta: float) -> void:
	if is_popping:
		pop_progress += delta * 5.0
		queue_redraw()
		if pop_progress >= 1.0:
			queue_free()
		return
	
	# Smooth movement with direction changes
	movement_timer += delta
	if movement_timer >= 3.0:
		movement_timer = 0.0
		var angle = randf() * TAU
		velocity = Vector2(cos(angle), sin(angle)) * (30.0 + randf_range(-10.0, 10.0))
	
	global_position += velocity * delta
	
	# Wiggle effect for organic movement
	wiggle_phase += delta * wiggle_speed
	
	# Boundary checking - bounce off edges
	var viewport_size = get_viewport_rect().size
	if global_position.x < size / 2.0 or global_position.x > viewport_size.x - size / 2.0:
		velocity.x *= -1
		global_position.x = clamp(global_position.x, size / 2.0, viewport_size.x - size / 2.0)
	
	if global_position.y < size / 2.0 or global_position.y > viewport_size.y - size / 2.0:
		velocity.y *= -1
		global_position.y = clamp(global_position.y, size / 2.0, viewport_size.y - size / 2.0)

# Helper method to create a color rect with proper sizing
func _create_color_rect(color: Color, size_px: Vector2) -> ColorRect:
	var rect = ColorRect.new()
	rect.color = color
	rect.custom_minimum_size = size_px
	return rect

# Setup for normal nodes
func setup(color: Color, position: Vector2) -> void:
	base_color = color
	global_position = position
	
	# Random initial velocity within reasonable bounds
	var angle = randf() * TAU
	velocity = Vector2(cos(angle), sin(angle)) * (30.0 + randf_range(-10.0, 10.0))

# Setup for recovery nodes (golden floating nodes)
func setup_recovery(position: Vector2) -> void:
	is_recovery_node = true
	global_position = position
	
	# Faster movement for more excitement
	var angle = randf() * TAU
	velocity = Vector2(cos(angle), sin(angle)) * (50.0 + randf_range(-15.0, 15.0))

func get_pop_progress() -> float:
	return pop_progress if is_popping else 0.0
