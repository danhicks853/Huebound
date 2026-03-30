extends Node

signal currency_changed(amount: float)
signal currency_rate_changed(rate: float)

const _SAVE_FILENAME := "huebound_save.json"
const _ZEN_SAVE_FILENAME := "huebound_zen_save.json"
const CLOUD_SAVE_FILE := "huebound_save.json"
const CLOUD_ZEN_SAVE_FILE := "huebound_zen_save.json"

# Shared save path so demo and full game access the same file.
# On web exports, user:// (IndexedDB) is the only option.
static func _get_shared_save_dir() -> String:
	if OS.has_feature("web"):
		return "user://"
	# OS.get_data_dir() = %APPDATA% (Win), ~/Library/Application Support (macOS), ~/.local/share (Linux)
	return OS.get_data_dir().path_join("Huebound")

static func get_save_path() -> String:
	return _get_shared_save_dir().path_join(_SAVE_FILENAME)

static func get_zen_save_path() -> String:
	return _get_shared_save_dir().path_join(_ZEN_SAVE_FILENAME)

var SAVE_FILE: String :
	get: return get_save_path() if not zen_mode else get_zen_save_path()

var currency: float = 50.0 : set = _set_currency
var total_earned: float = 0.0
var game_speed: float = 1.0

# Pending data from load — main_game reads and clears these
var pending_nodes: Array = []
var pending_connections: Array = []

# Tutorial tracking
var tutorial_completed: bool = false

# Prestige tracking
var prestige_count: int = 0
var prestige_sources: Array[String] = []  # color names chosen as permanent sources
var discoveries_since_prestige: int = 0
var endgame_seen: bool = false

# Zen Mode: no currency, no prestiges, instant color discovery, auto-add nodes
var zen_mode: bool = false

# Colorblind mode: 0 = Off, 1 = Protanopia, 2 = Deuteranopia, 3 = Tritanopia
var colorblind_mode: int = 0

# Orb trail quality: 0 = Low, 1 = Medium, 2 = High
var orb_quality: int = 2

# UI scale factor (1.0 = default, range 0.75–2.0)
var ui_scale: float = 1.0

func _ready() -> void:
	# Load ui_scale early so the title screen is already scaled correctly
	_load_ui_scale()

func _load_ui_scale() -> void:
	var path = get_save_path()
	if not FileAccess.file_exists(path):
		return
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		return
	var json = JSON.new()
	if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
		ui_scale = float(json.data.get("ui_scale", 1.0))
		apply_ui_scale()
	f.close()

func apply_ui_scale() -> void:
	var win = get_viewport().get_window()
	if win:
		# Cap so virtual viewport never shrinks below 960px wide
		var max_factor = float(win.size.x) / 960.0
		ui_scale = clampf(ui_scale, 0.75, maxf(max_factor, 1.0))
		win.content_scale_factor = ui_scale

# Templates: saved node layouts (unlocked after 2nd prestige)
# Each: {name: String, nodes: [{node_id, ox, oy}], connections: [{from: int, to: int}]}
var templates: Array[Dictionary] = []

# Currency rate tracking (currency earned per second)
var _rate_history: Array[float] = []
var _rate_timer: float = 0.0
var _rate_earned_this_second: float = 0.0
var currency_per_second: float = 0.0
var peak_currency_per_second: float = 0.0

# Global upgrades: each has a level (0 = not purchased)
var upgrades := {
	"production_speed": 0,
	"transfer_speed": 0,
	"buffer_size": 0,
	"discovery_bonus": 0,
	"sell_value": 0,
}

const UPGRADE_DEFS := {
	"production_speed": {
		"name": "Production Speed",
		"description": "+15% source output rate per level",
		"base_cost": 200.0,
		"cost_scale": 2.0,
		"max_level": 10,
		"per_level": 0.15,
	},
	"transfer_speed": {
		"name": "Transfer Speed",
		"description": "+20% orb travel speed per level",
		"base_cost": 150.0,
		"cost_scale": 1.8,
		"max_level": 10,
		"per_level": 0.20,
	},
	"buffer_size": {
		"name": "Buffer Size",
		"description": "+2 buffer slots on all nodes per level",
		"base_cost": 300.0,
		"cost_scale": 2.2,
		"max_level": 5,
		"per_level": 2,
	},
	"discovery_bonus": {
		"name": "Discovery Bonus",
		"description": "+50% first-discovery bonus per level",
		"base_cost": 400.0,
		"cost_scale": 2.5,
		"max_level": 8,
		"per_level": 0.50,
	},
	"sell_value": {
		"name": "Sell Value",
		"description": "+10% base sell value per level",
		"base_cost": 500.0,
		"cost_scale": 2.5,
		"max_level": 10,
		"per_level": 0.10,
	},
}

# Save timestamp for offline progress
var last_save_time: int = 0

func _set_currency(value: float) -> void:
	currency = value
	currency_changed.emit(currency)

func _process(delta: float) -> void:
	_rate_timer += delta
	if _rate_timer >= 1.0:
		_rate_timer -= 1.0
		_rate_history.append(_rate_earned_this_second)
		_rate_earned_this_second = 0.0
		if _rate_history.size() > 5:
			_rate_history.pop_front()
		var total := 0.0
		for r in _rate_history:
			total += r
		currency_per_second = total / _rate_history.size()
		if currency_per_second > peak_currency_per_second:
			peak_currency_per_second = currency_per_second
		currency_rate_changed.emit(currency_per_second)

func add_currency(amount: float) -> void:
	currency += amount
	total_earned += amount
	_rate_earned_this_second += amount
	# Steam achievement for total earnings
	if total_earned >= 10000.0:
		SteamManager.unlock_achievement("rich")

func spend_currency(amount: float) -> bool:
	if currency >= amount:
		currency -= amount
		return true
	return false

func can_afford(amount: float) -> bool:
	return currency >= amount

func get_upgrade_cost(upgrade_id: String) -> float:
	var def = UPGRADE_DEFS.get(upgrade_id, {})
	if def.is_empty():
		return 0.0
	return def.base_cost * pow(def.cost_scale, upgrades.get(upgrade_id, 0))

func buy_upgrade(upgrade_id: String) -> bool:
	var def = UPGRADE_DEFS.get(upgrade_id, {})
	if def.is_empty():
		return false
	var lvl = upgrades.get(upgrade_id, 0)
	if lvl >= def.max_level:
		return false
	var cost = get_upgrade_cost(upgrade_id)
	if spend_currency(cost):
		upgrades[upgrade_id] = lvl + 1
		return true
	return false

func get_upgrade_mult(upgrade_id: String) -> float:
	var def = UPGRADE_DEFS.get(upgrade_id, {})
	if def.is_empty():
		return 1.0
	return 1.0 + upgrades.get(upgrade_id, 0) * def.per_level

func get_upgrade_bonus(upgrade_id: String) -> int:
	var def = UPGRADE_DEFS.get(upgrade_id, {})
	if def.is_empty():
		return 0
	return upgrades.get(upgrade_id, 0) * int(def.per_level)

func _get_palette() -> Node:
	return get_node_or_null("/root/ColorPalette")

func save_game() -> void:
	var palette = _get_palette()
	var discovered_indices: Array[int] = []
	if palette:
		for i in range(palette.discovered.size()):
			if palette.discovered[i]:
				discovered_indices.append(i)
	# Serialize placed nodes
	var saved_nodes: Array[Dictionary] = []
	if NodeFactory:
		for i in range(NodeFactory.placed_nodes.size()):
			var node = NodeFactory.placed_nodes[i]
			saved_nodes.append({
				"node_id": node.node_id,
				"x": node.global_position.x,
				"y": node.global_position.y,
				"level": node.level,
			})
	# Serialize connections as index pairs
	var saved_connections: Array[Dictionary] = []
	if NodeFactory:
		for conn in NodeFactory.connections:
			var from_idx = NodeFactory.placed_nodes.find(conn.from)
			var to_idx = NodeFactory.placed_nodes.find(conn.to)
			if from_idx >= 0 and to_idx >= 0:
				saved_connections.append({"from": from_idx, "to": to_idx})
	var save_data := {
		"currency": currency,
		"total_earned": total_earned,
		"discovered_colors": discovered_indices,
		"last_save_time": Time.get_unix_time_from_system(),
		"peak_cps": peak_currency_per_second,
		"upgrades": upgrades.duplicate(),
		"node_purchase_counts": NodeFactory.node_purchase_counts.duplicate() if NodeFactory else {},
		"unlocked_nodes": NodeFactory.unlocked_nodes.duplicate() if NodeFactory else [],
		"placed_nodes": saved_nodes,
		"connections": saved_connections,
		"tutorial_completed": tutorial_completed,
		"prestige_count": prestige_count,
		"prestige_sources": prestige_sources.duplicate(),
		"discoveries_since_prestige": discoveries_since_prestige,
		"endgame_seen": endgame_seen,
		"zen_mode": zen_mode,
		"colorblind_mode": colorblind_mode,
		"orb_quality": orb_quality,
		"ui_scale": ui_scale,
		"templates": templates.duplicate(true),
		"is_demo_save": DemoConfig.is_demo(),
	}
	var json_string = JSON.stringify(save_data, "\t")
	# Ensure save directory exists
	var save_dir = _get_shared_save_dir()
	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)
	# Always write to local file
	var file = FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		# Web exports need explicit IndexedDB sync
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.setTimeout(function() { FS.syncfs(false, function(err) {}); }, 100);")
	# Also write to Steam Cloud if available
	if zen_mode:
		SteamManager.cloud_save(CLOUD_ZEN_SAVE_FILE, json_string)
	else:
		SteamManager.cloud_save(CLOUD_SAVE_FILE, json_string)

func _migrate_legacy_save() -> void:
	# If no save at the shared path but one exists at the old user:// location, copy it over.
	# This ensures saves from before the shared-path change (and demo saves) carry forward.
	if OS.has_feature("web"):
		return  # web always uses user://, no migration needed
	var legacy_path := "user://huebound_save.json"
	if not FileAccess.file_exists(SAVE_FILE) and FileAccess.file_exists(legacy_path):
		var save_dir = _get_shared_save_dir()
		if not DirAccess.dir_exists_absolute(save_dir):
			DirAccess.make_dir_recursive_absolute(save_dir)
		var f = FileAccess.open(legacy_path, FileAccess.READ)
		if f:
			var data = f.get_as_text()
			f.close()
			var out = FileAccess.open(SAVE_FILE, FileAccess.WRITE)
			if out:
				out.store_string(data)
				out.close()

func _is_save_compatible(json_string: String) -> bool:
	# Demo builds must not load full-game saves
	if not DemoConfig.is_demo():
		return true  # full game accepts everything
	var json = JSON.new()
	if json.parse(json_string) == OK:
		var data = json.data
		if data is Dictionary:
			# Accept: demo saves (is_demo_save=true) or legacy saves with no flag
			var is_demo_save = data.get("is_demo_save", true)
			return is_demo_save
	return true  # unparseable — let load_game handle the error

func load_game() -> void:
	_migrate_legacy_save()
	var cloud_file = CLOUD_ZEN_SAVE_FILE if zen_mode else CLOUD_SAVE_FILE
	var local_path = SAVE_FILE
	var json_string := ""
	# Try Steam Cloud first
	var cloud_data = SteamManager.cloud_load(cloud_file)
	if cloud_data != "":
		# Compare timestamps: use whichever save is newer
		var local_data := ""
		if FileAccess.file_exists(local_path):
			var f = FileAccess.open(local_path, FileAccess.READ)
			if f:
				local_data = f.get_as_text()
				f.close()
		if local_data != "":
			var cloud_time = _get_save_time(cloud_data)
			var local_time = _get_save_time(local_data)
			json_string = cloud_data if cloud_time >= local_time else local_data
		else:
			json_string = cloud_data
	else:
		# No cloud save — use local
		if not FileAccess.file_exists(local_path):
			return
		var file = FileAccess.open(local_path, FileAccess.READ)
		if not file:
			return
		json_string = file.get_as_text()
		file.close()
	if json_string == "":
		return
	if not _is_save_compatible(json_string):
		push_warning("Demo cannot load a full-game save.")
		return
	var json = JSON.new()
	if json.parse(json_string) == OK:
		var data = json.data
		currency = data.get("currency", 50.0)
		total_earned = data.get("total_earned", 0.0)
		last_save_time = data.get("last_save_time", 0)
		peak_currency_per_second = data.get("peak_cps", 0.0)
		var saved_upgrades = data.get("upgrades", {})
		for key in saved_upgrades:
			if upgrades.has(key):
				upgrades[key] = int(saved_upgrades[key])
		var nf = get_node_or_null("/root/NodeFactory")
		if nf:
			var saved_counts = data.get("node_purchase_counts", {})
			for key in saved_counts:
				nf.node_purchase_counts[key] = int(saved_counts[key])
			var saved_unlocks = data.get("unlocked_nodes", [])
			nf.unlocked_nodes.clear()
			for nid in saved_unlocks:
				nf.unlocked_nodes.append(str(nid))
		var palette = _get_palette()
		if palette:
			# Reset discoveries before restoring to prevent double-counting
			for i in range(palette.discovered.size()):
				palette.discovered[i] = false
			palette.discovery_count = 0
			var disc = data.get("discovered_colors", [])
			for idx in disc:
				if idx >= 0 and idx < palette.discovered.size():
					palette.discovered[idx] = true
					palette.discovery_count += 1
		# Store node/connection data for main_game to recreate
		pending_nodes = data.get("placed_nodes", [])
		pending_connections = data.get("connections", [])
		tutorial_completed = data.get("tutorial_completed", false)
		prestige_count = int(data.get("prestige_count", 0))
		var saved_prestige_sources = data.get("prestige_sources", [])
		prestige_sources.clear()
		for s in saved_prestige_sources:
			prestige_sources.append(str(s))
		discoveries_since_prestige = int(data.get("discoveries_since_prestige", 0))
		endgame_seen = data.get("endgame_seen", false)
		zen_mode = bool(data.get("zen_mode", false))
		colorblind_mode = int(data.get("colorblind_mode", 0))
		orb_quality = int(data.get("orb_quality", 2))
		ui_scale = float(data.get("ui_scale", 1.0))
		apply_ui_scale()
		templates.clear()
		var saved_templates = data.get("templates", [])
		for t in saved_templates:
			templates.append(t)

func reset_state() -> void:
	currency = 50.0
	total_earned = 0.0
	peak_currency_per_second = 0.0
	currency_per_second = 0.0
	_rate_history.clear()
	_rate_earned_this_second = 0.0
	_rate_timer = 0.0
	for key in upgrades:
		upgrades[key] = 0
	pending_nodes.clear()
	pending_connections.clear()
	tutorial_completed = false
	prestige_count = 0
	prestige_sources.clear()
	discoveries_since_prestige = 0
	endgame_seen = false
	zen_mode = false
	var nf = get_node_or_null("/root/NodeFactory")
	if nf:
		nf.node_purchase_counts.clear()
		nf.unlocked_nodes.clear()
		nf.placed_nodes.clear()
		nf.connections.clear()
	var palette = _get_palette()
	if palette:
		for i in range(palette.discovered.size()):
			palette.discovered[i] = false
		palette.discovery_count = 0

func prestige_reset() -> void:
	# Reset currency, upgrades, canvas — keep discoveries and prestige state
	currency = 50.0
	total_earned = 0.0
	peak_currency_per_second = 0.0
	currency_per_second = 0.0
	_rate_history.clear()
	_rate_earned_this_second = 0.0
	_rate_timer = 0.0
	for key in upgrades:
		upgrades[key] = 0
	pending_nodes.clear()
	pending_connections.clear()
	discoveries_since_prestige = 0
	var nf = get_node_or_null("/root/NodeFactory")
	if nf:
		nf.node_purchase_counts.clear()
		nf.unlocked_nodes.clear()
		nf.placed_nodes.clear()
		nf.connections.clear()

func has_save() -> bool:
	var save_path = get_zen_save_path() if zen_mode else get_save_path()
	if FileAccess.file_exists(save_path):
		var f = FileAccess.open(save_path, FileAccess.READ)
		if f:
			var txt = f.get_as_text()
			f.close()
			if _is_save_compatible(txt):
				return true
	# Check legacy user:// path (pre-shared-path saves) — only for normal mode
	if not zen_mode and not OS.has_feature("web") and FileAccess.file_exists("user://huebound_save.json"):
		var f = FileAccess.open("user://huebound_save.json", FileAccess.READ)
		if f:
			var txt = f.get_as_text()
			f.close()
			if _is_save_compatible(txt):
				return true
	var cloud_file = CLOUD_ZEN_SAVE_FILE if zen_mode else CLOUD_SAVE_FILE
	if SteamManager.cloud_has_file(cloud_file):
		var cloud_data = SteamManager.cloud_load(cloud_file)
		if _is_save_compatible(cloud_data):
			return true
	return false

func _has_zen_save() -> bool:
	var was_zen = zen_mode
	zen_mode = true
	var result = has_save()
	zen_mode = was_zen
	return result

func _get_save_time(json_string: String) -> float:
	var json = JSON.new()
	if json.parse(json_string) == OK:
		var data = json.data
		if data is Dictionary:
			return float(data.get("last_save_time", 0))
	return 0.0
