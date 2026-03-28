extends Node2D

const GRID_SIZE := 80
const GRID_EXTENT := 800 # Smaller grid, drawn once

func _ready() -> void:
	z_index = -10
	# Draw once on ready — grid is static, never needs redraw

func _draw() -> void:
	var dot_color = Color(0.2, 0.2, 0.3, 0.4)
	
	# Draw dots at grid intersections
	for x in range(-GRID_EXTENT, GRID_EXTENT + 1, GRID_SIZE):
		for y in range(-GRID_EXTENT, GRID_EXTENT + 1, GRID_SIZE):
			draw_circle(Vector2(x, y), 1.5, dot_color)
	
	# Draw subtle axis lines
	var axis_color = Color(0.2, 0.2, 0.3, 0.2)
	draw_line(Vector2(-GRID_EXTENT, 0), Vector2(GRID_EXTENT, 0), axis_color, 1.0)
	draw_line(Vector2(0, -GRID_EXTENT), Vector2(0, GRID_EXTENT), axis_color, 1.0)
