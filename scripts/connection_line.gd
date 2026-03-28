extends Node2D
class_name ConnectionLine

var from_node: FactoryNode
var to_node: FactoryNode
var orbs: Array[Dictionary] = [] # {position: float (0-1), orb_data: {color: Color, sources: Array[Color]}}
var transfer_timer: float = 0.0
var transfer_rate: float = 1.5 # seconds between transfers
var orb_speed: float = 120.0 # pixels per second base speed
var line_color: Color = Color(0.4, 0.4, 0.5, 0.4)
var pulse_offset: float = 0.0
var hovered: bool = false

func setup(from: FactoryNode, to: FactoryNode) -> void:
	from_node = from
	to_node = to
	pulse_offset = randf() * TAU

func _process(delta: float) -> void:
	if not is_instance_valid(from_node) or not is_instance_valid(to_node):
		queue_free()
		return
	
	pulse_offset += delta
	
	# Move existing orbs along the line — speed depends on distance
	var speed_mult = GameState.get_upgrade_mult("transfer_speed")
	var line_length = from_node.global_position.distance_to(to_node.global_position)
	line_length = maxf(line_length, 1.0)
	var to_remove: Array[int] = []
	for i in range(orbs.size()):
		orbs[i].position += (orb_speed * speed_mult * GameState.game_speed * delta) / line_length
		if orbs[i].position >= 1.0:
			# Deliver orb to target (pass from_node so combiner can track per-input slots)
			if to_node.receive_orb(orbs[i].orb_data, from_node):
				to_remove.append(i)
			else:
				# Target can't receive, hold at end
				orbs[i].position = 0.99
	
	# Remove delivered orbs (reverse order)
	for i in range(to_remove.size() - 1, -1, -1):
		orbs.remove_at(to_remove[i])
	
	# Try to pull orbs from source
	transfer_timer += delta * GameState.game_speed
	if transfer_timer >= transfer_rate:
		transfer_timer = 0.0
		if from_node.has_output() and orbs.size() < 5:
			var orb_data = from_node.take_orb()
			if not orb_data.is_empty():
				orbs.append({"position": 0.0, "orb_data": orb_data})
	
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(from_node) or not is_instance_valid(to_node):
		return
	
	var start = from_node.global_position - global_position
	var end = to_node.global_position - global_position
	var direction = (end - start).normalized()
	
	# Offset start/end to node edges
	start += direction * NodeFactory.NODE_RADIUS
	end -= direction * NodeFactory.NODE_RADIUS
	
	# Draw base line with subtle pulse
	var alpha = 0.25 + sin(pulse_offset * 1.5) * 0.05
	var base_col = Color(0.4, 0.4, 0.5, alpha)
	if hovered:
		# Highlight: thicker, brighter, reddish tint
		var glow_col = Color(1.0, 0.3, 0.3, 0.12)
		draw_line(start, end, glow_col, 6.0)
		base_col = Color(1.0, 0.4, 0.4, 0.7)
		draw_line(start, end, base_col, 2.5)
	else:
		draw_line(start, end, base_col, 1.5)
	
	var quality = GameState.orb_quality  # 0=Low, 1=Medium, 2=High
	
	# Draw flow direction indicator (small chevrons) — skip on Low
	if quality >= 1:
		var length = start.distance_to(end)
		var num_chevrons = max(int(length / 40.0), 1)
		for i in range(num_chevrons):
			var t = fmod(float(i) / num_chevrons + pulse_offset * 0.1, 1.0)
			var pos = start.lerp(end, t)
			var perp = Vector2(-direction.y, direction.x) * 4.0
			var chevron_color = Color(0.5, 0.5, 0.6, 0.15)
			draw_line(pos - direction * 3 + perp, pos, chevron_color, 1.0)
			draw_line(pos - direction * 3 - perp, pos, chevron_color, 1.0)
	
	# Draw orbs
	for orb in orbs:
		var pos = start.lerp(end, orb.position)
		var orb_col: Color = orb.orb_data.color
		if quality >= 2:
			# High: glow + core + bright center
			var glow = orb_col
			glow.a = 0.2
			draw_circle(pos, 8, glow)
			draw_circle(pos, 4, orb_col)
			var bright = orb_col.lightened(0.5)
			bright.a = 0.8
			draw_circle(pos, 2, bright)
		elif quality == 1:
			# Medium: core + bright center, no glow
			draw_circle(pos, 4, orb_col)
			var bright = orb_col.lightened(0.5)
			bright.a = 0.8
			draw_circle(pos, 2, bright)
		else:
			# Low: just the core
			draw_circle(pos, 4, orb_col)
