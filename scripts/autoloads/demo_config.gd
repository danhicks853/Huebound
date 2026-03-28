extends Node

# Set to true for demo builds, false for full game
const IS_DEMO := false

# The 20 colors available in the demo — a self-contained recipe chain across all tiers
const DEMO_COLORS: Array[String] = [
	# Tier 0 (3)
	"Blue", "Red", "Yellow",
	# Tier 1 (4)
	"Purple", "Orange", "Green", "Rose",
	# Tier 2 (4)
	"Crimson", "Vermillion", "Amber", "Teal",
	# Tier 3 (5)
	"Wine", "Rust", "Olive", "Maroon", "Sienna",
	# Tier 4 (2)
	"Ember", "Auburn",
	# Tier 5 (2)
	"Blackberry", "Paprika",
]

# Node types blocked in the demo
const DEMO_BLOCKED_NODES: Array[String] = [
	"splitter",
]

func is_demo() -> bool:
	return IS_DEMO

func is_color_in_demo(color_name: String) -> bool:
	if not IS_DEMO:
		return true
	return color_name in DEMO_COLORS

func is_node_blocked(node_id: String) -> bool:
	if not IS_DEMO:
		return false
	return node_id in DEMO_BLOCKED_NODES

func get_demo_color_count() -> int:
	return DEMO_COLORS.size()
