extends Node

# Registry of node type definitions
# Each node type has: name, cost, description, shape, color, category

signal node_placed(factory_node: Node2D)
signal node_removed(factory_node: Node2D)
signal connection_made(from_node: Node2D, to_node: Node2D)
signal connection_removed(from_node: Node2D, to_node: Node2D)

enum NodeType { PRODUCER, PROCESSOR, SELLER, SPLITTER }
enum Shape { CIRCLE, HEXAGON, DIAMOND, SQUARE, OCTAGON }

var grid_snap_enabled: bool = true

const NODE_DEFS := {
	"blue_source": {
		"type": NodeType.PRODUCER,
		"name": "Blue Source",
		"description": "Generates pure blue orbs",
		"cost": 10.0,
		"shape": Shape.CIRCLE,
		"color": Color8(0, 0, 255),
		"rate": 1.0,
		"max_level": 1,
		"unlock_cost": 0.0, # available from start
	},
	"red_source": {
		"type": NodeType.PRODUCER,
		"name": "Red Source",
		"description": "Generates pure red orbs",
		"cost": 25.0,
		"shape": Shape.CIRCLE,
		"color": Color8(255, 0, 0),
		"rate": 0.8,
		"max_level": 1,
		"unlock_cost": 10.0, # unlocks via shop purchase
	},
	"yellow_source": {
		"type": NodeType.PRODUCER,
		"name": "Yellow Source",
		"description": "Generates pure yellow orbs",
		"cost": 75.0,
		"shape": Shape.CIRCLE,
		"color": Color8(255, 255, 0),
		"rate": 0.6,
		"max_level": 1,
		"unlock_cost": 100.0, # unlocks after earning 100 total light
	},
	"combiner": {
		"type": NodeType.PROCESSOR,
		"name": "Combiner",
		"description": "Mixes exactly 2 input colors",
		"cost": 20.0,
		"shape": Shape.HEXAGON,
		"color": Color(0.8, 0.8, 0.8),
		"rate": 0.8,
		"max_level": 1,
		"unlock_cost": 50.0, # unlocks after earning 50 total light
		"upkeep": 0.5,
	},
	"splitter": {
		"type": NodeType.SPLITTER,
		"name": "Splitter",
		"description": "Splits orb into two copies with halved value",
		"cost": 100.0,
		"shape": Shape.SQUARE,
		"color": Color(0.5, 0.8, 1.0),
		"rate": 0.6,
		"max_level": 1,
		"unlock_cost": 500.0, # unlocks after earning 500 total light
		"upkeep": 2.0,
	},
	"seller": {
		"type": NodeType.SELLER,
		"name": "Seller",
		"description": "Sells orbs — rarer colors are worth more light",
		"cost": 15.0,
		"shape": Shape.DIAMOND,
		"color": Color(1.0, 0.85, 0.3),
		"rate": 2.0,
		"max_level": 1,
		"unlock_cost": 0.0,
	},
}

# Tracks which nodes have been unlocked via shop purchase
var unlocked_nodes: Array[String] = []

# Dynamic node defs generated from prestige sources + rainbow
var _dynamic_defs := {}

const PRESTIGE_RATE_BY_TIER := { 0: 1.0, 1: 0.8, 2: 0.7, 3: 0.6, 4: 0.5, 5: 0.4 }
const PRESTIGE_COST_BY_TIER := { 0: 10.0, 1: 20.0, 2: 40.0, 3: 60.0, 4: 80.0, 5: 100.0 }

func rebuild_dynamic_defs() -> void:
	_dynamic_defs.clear()
	var gs = get_node_or_null("/root/GameState")
	var palette = get_node_or_null("/root/ColorPalette")
	if gs == null or palette == null:
		return
	# Build prestige source nodes
	for color_name in gs.prestige_sources:
		var idx = palette.find_color_by_name(color_name)
		if idx < 0:
			continue
		var entry = palette.palette[idx]
		var node_id = "prestige_" + color_name.to_lower().replace(" ", "_")
		_dynamic_defs[node_id] = {
			"type": NodeType.PRODUCER,
			"name": color_name + " Source",
			"description": "Generates " + color_name + " orbs (Prestige)",
			"cost": PRESTIGE_COST_BY_TIER.get(entry.tier, 60.0),
			"shape": Shape.CIRCLE,
			"color": entry.color,
			"rate": PRESTIGE_RATE_BY_TIER.get(entry.tier, 0.6),
			"max_level": 1,
			"unlock_cost": 0.0,
			"prestige": true,
		}
	# Rainbow node for endgame (prestige 25)
	if gs.prestige_count >= 24 and gs.endgame_seen == false:
		var cp = palette
		if cp.discovery_count >= cp.get_palette_size():
			_dynamic_defs["rainbow"] = {
				"type": NodeType.PRODUCER,
				"name": "Rainbow",
				"description": "All colors united",
				"cost": 1.0,
				"shape": Shape.OCTAGON,
				"color": Color(1, 1, 1),
				"rate": 1.0,
				"max_level": 1,
				"unlock_cost": 0.0,
				"rainbow": true,
			}

func is_node_unlocked(node_id: String) -> bool:
	var gs = get_node_or_null("/root/GameState")
	if gs and gs.zen_mode:
		return true
	var def = get_node_def(node_id)
	if def.is_empty():
		return false
	var cost = def.get("unlock_cost", 0.0)
	if cost == 0.0:
		return true
	return node_id in unlocked_nodes

func buy_node_unlock(node_id: String) -> bool:
	var def = get_node_def(node_id)
	if def.is_empty():
		return false
	if node_id in unlocked_nodes:
		return false
	var cost = def.get("unlock_cost", 0.0)
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return false
	if gs.spend_currency(cost):
		unlocked_nodes.append(node_id)
		return true
	return false

func get_locked_nodes() -> Array[String]:
	var result: Array[String] = []
	var all = get_all_defs()
	for id in all:
		var cost = all[id].get("unlock_cost", 0.0)
		if cost > 0.0 and not (id in unlocked_nodes):
			result.append(id)
	return result

# Track how many of each node type have been purchased (for escalating costs)
var node_purchase_counts := {}

func get_node_cost(node_id: String) -> float:
	var def = get_node_def(node_id)
	if def.is_empty():
		return 0.0
	var base = def.cost
	var count = node_purchase_counts.get(node_id, 0)
	return base * (1.0 + 0.3 * log(1.0 + count))

func get_node_sell_value(node_id: String) -> float:
	# Refund = cost at (count - 1), i.e. what the last one cost, times 50%
	var def = get_node_def(node_id)
	if def.is_empty():
		return 0.0
	var base = def.cost
	var count = node_purchase_counts.get(node_id, 0)
	var prev_count = max(count - 1, 0)
	var paid = base * (1.0 + 0.3 * log(1.0 + prev_count))
	return paid * 0.5

func record_purchase(node_id: String) -> void:
	node_purchase_counts[node_id] = node_purchase_counts.get(node_id, 0) + 1

func record_sell(node_id: String) -> void:
	var count = node_purchase_counts.get(node_id, 0)
	if count > 0:
		node_purchase_counts[node_id] = count - 1

# All placed nodes in the world
var placed_nodes: Array[Node2D] = []
# Connections: array of {from: Node2D, to: Node2D}
var connections: Array[Dictionary] = []

# Grid settings
const GRID_SIZE := 80
const NODE_RADIUS := 30.0

func get_node_def(node_id: String) -> Dictionary:
	var d = NODE_DEFS.get(node_id, {})
	if d.is_empty():
		d = _dynamic_defs.get(node_id, {})
	return d

func get_all_defs() -> Dictionary:
	var all = NODE_DEFS.duplicate()
	for key in _dynamic_defs:
		all[key] = _dynamic_defs[key]
	return all

func snap_to_grid(pos: Vector2) -> Vector2:
	if not grid_snap_enabled:
		return pos
	return Vector2(
		snapped(pos.x, GRID_SIZE),
		snapped(pos.y, GRID_SIZE)
	)

func is_position_free(pos: Vector2) -> bool:
	for node in placed_nodes:
		if node.global_position.distance_to(pos) < GRID_SIZE * 0.8:
			return false
	return true

func register_node(factory_node: Node2D) -> void:
	placed_nodes.append(factory_node)
	node_placed.emit(factory_node)

func unregister_node(factory_node: Node2D) -> void:
	placed_nodes.erase(factory_node)
	# Remove all connections involving this node
	var to_remove: Array[Dictionary] = []
	for conn in connections:
		if conn.from == factory_node or conn.to == factory_node:
			to_remove.append(conn)
	for conn in to_remove:
		connections.erase(conn)
		connection_removed.emit(conn.from, conn.to)
	node_removed.emit(factory_node)

func add_connection(from_node: Node2D, to_node: Node2D) -> bool:
	# Don't allow self-connections
	if from_node == to_node:
		return false
	# Check if connection already exists
	for conn in connections:
		if conn.from == from_node and conn.to == to_node:
			return false
	# Sellers can't output
	if from_node.node_type == NodeType.SELLER:
		return false
	# Producers can't receive input
	if to_node.node_type == NodeType.PRODUCER:
		return false
	# Limit input connections by node type
	var max_inputs := 1
	if to_node.node_type == NodeType.PROCESSOR:
		max_inputs = 2  # Combiners always take exactly 2 inputs
	else:
		max_inputs = 1
	var current_inputs = get_connections_to(to_node).size()
	if current_inputs >= max_inputs:
		return false
	# Limit output connections: Splitter gets 2, others get 1
	var max_outputs = 2 if from_node.node_type == NodeType.SPLITTER else 1
	var current_outputs = get_connections_from(from_node).size()
	if current_outputs >= max_outputs:
		return false
	connections.append({"from": from_node, "to": to_node})
	connection_made.emit(from_node, to_node)
	return true

func remove_connection(from_node: Node2D, to_node: Node2D) -> void:
	for i in range(connections.size() - 1, -1, -1):
		if connections[i].from == from_node and connections[i].to == to_node:
			connections.remove_at(i)
			connection_removed.emit(from_node, to_node)
			break

func get_connections_from(node: Node2D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for conn in connections:
		if conn.from == node:
			result.append(conn)
	return result

func get_connections_to(node: Node2D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for conn in connections:
		if conn.to == node:
			result.append(conn)
	return result

func get_node_at(pos: Vector2) -> Node2D:
	for node in placed_nodes:
		if node.global_position.distance_to(pos) < NODE_RADIUS + 10:
			return node
	return null

func get_connection_near(pos: Vector2, threshold: float = 15.0) -> Dictionary:
	var best_conn := {}
	var best_dist := threshold
	for conn in connections:
		var a: Vector2 = conn.from.global_position
		var b: Vector2 = conn.to.global_position
		var dist = _point_to_segment_dist(pos, a, b)
		if dist < best_dist:
			best_dist = dist
			best_conn = conn
	return best_conn

func _point_to_segment_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab = b - a
	var ap = p - a
	var t = clamp(ap.dot(ab) / ab.dot(ab), 0.0, 1.0)
	var closest = a + ab * t
	return p.distance_to(closest)
