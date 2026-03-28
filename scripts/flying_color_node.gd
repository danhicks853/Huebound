extends Node2D
class_name FlyingColorNode

# Wandering color orb that appears when player is low on currency
# Click to collect 50 Light

var color: Color = Color.WHITE
var wander_speed: float = 30.0
var pulse_time: float = 0.0
var click_radius: float = 25.0

# Wandering state
var velocity: Vector2 = Vector2.ZERO
var wander_target: Vector2 = Vector2.ZERO
var change_dir_timer: float = 0.0
var bounds: Rect2 = Rect2()

# Collection callback
var on_collected: Callable = Callable()

func setup(node_color: Color, screen_bounds: Rect2) -> void:
	color = node_color
	bounds = screen_bounds
	# Start at random position within bounds
	global_position = Vector2(
		randf_range(bounds.position.x + 50, bounds.end.x - 50),
		randf_range(bounds.position.y + 50, bounds.end.y - 50)
	)
	_pick_new_target()

func _input(event: InputEvent) -> void:
	# Direct input handling for clicking
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var world_pos = get_global_mouse_position()
			if is_clicked_at(world_pos):
				collect()
				# Consume the event so it doesn't propagate
				get_viewport().set_input_as_handled()

func _pick_new_target() -> void:
	# Pick a new wander target within bounds
	wander_target = Vector2(
		randf_range(bounds.position.x + 30, bounds.end.x - 30),
		randf_range(bounds.position.y + 30, bounds.end.y - 30)
	)
	# Random speed variation
	wander_speed = randf_range(20.0, 50.0)

func _process(delta: float) -> void:
	pulse_time += delta * 3.0
	
	# Wander toward target
	var dir = (wander_target - global_position).normalized()
	var dist = global_position.distance_to(wander_target)
	
	if dist < 10.0:
		_pick_new_target()
		dir = (wander_target - global_position).normalized()
	
	# Smooth velocity changes
	velocity = velocity.lerp(dir * wander_speed, delta * 2.0)
	global_position += velocity * delta
	
	# Keep within bounds (soft bounce)
	var margin = 30.0
	if global_position.x < bounds.position.x + margin:
		velocity.x = abs(velocity.x) * 0.5
		global_position.x = bounds.position.x + margin
	elif global_position.x > bounds.end.x - margin:
		velocity.x = -abs(velocity.x) * 0.5
		global_position.x = bounds.end.x - margin
		
	if global_position.y < bounds.position.y + margin:
		velocity.y = abs(velocity.y) * 0.5
		global_position.y = bounds.position.y + margin
	elif global_position.y > bounds.end.y - margin:
		velocity.y = -abs(velocity.y) * 0.5
		global_position.y = bounds.end.y - margin
	
	queue_redraw()

func _draw() -> void:
	var pulse = 0.7 + 0.3 * sin(pulse_time)
	var radius = click_radius * pulse
	
	# Outer glow ring
	var glow = color
	glow.a = 0.15
	draw_circle(Vector2.ZERO, radius + 15, glow)
	
	# Middle ring
	glow.a = 0.25
	draw_circle(Vector2.ZERO, radius + 8, glow)
	
	# Core orb
	var core = color
	core.a = 0.9
	draw_circle(Vector2.ZERO, radius * 0.7, core)
	
	# Bright center
	var bright = color.lightened(0.4)
	bright.a = 0.8
	draw_circle(Vector2.ZERO, radius * 0.3, bright)
	
	# Light sparkles
	for i in range(3):
		var angle = pulse_time * 0.5 + i * TAU / 3.0
		var sparkle_pos = Vector2(cos(angle), sin(angle)) * (radius * 1.2)
		var sparkle_alpha = 0.3 + 0.2 * sin(pulse_time * 2.0 + i)
		draw_circle(sparkle_pos, 3.0, Color(1, 1, 1, sparkle_alpha))

func is_clicked_at(pos: Vector2) -> bool:
	return global_position.distance_to(pos) <= click_radius * 1.5

func collect() -> void:
	if on_collected.is_valid():
		on_collected.call()
	
	# Visual pop effect before removing
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.1)
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
