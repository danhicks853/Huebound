extends Node

# Steam integration — gracefully no-ops when GodotSteam is not available.
# Uses GodotSteam GDExtension which registers "Steam" as an Engine singleton.
# All method calls go through _s (Object) to avoid parse-time errors if the
# GDExtension is absent.

const APP_ID: int = 4459040

var steam_running := false
var steam_username := ""
var steam_id: int = 0
var _s: Object = null

func _ready() -> void:
	if not Engine.has_singleton("Steam"):
		print("[Steam] GodotSteam not available — running without Steam integration.")
		return
	_s = Engine.get_singleton("Steam")

	# Check auto-init result (Project Settings: initialize_on_startup=true)
	var prev = _s.get_steam_init_result()
	if prev.get("status", -1) == 0:
		steam_running = true
	else:
		# Fallback: manual init
		var result = _s.steamInitEx(APP_ID, true)
		print("[Steam] steamInitEx: %s" % str(result))
		if result.get("status", -1) == 0:
			steam_running = true
		else:
			push_warning("[Steam] Init failed: %s" % result)
			return

	steam_username = _s.getPersonaName()
	steam_id = _s.getSteamID()
	print("[Steam] Initialized — user: %s (ID: %d)" % [steam_username, steam_id])

func _process(_delta: float) -> void:
	if steam_running:
		_s.run_callbacks()

# ─── Achievements ─────────────────────────────────────────────────────────────

func unlock_achievement(achievement_id: String) -> void:
	if not steam_running:
		print("[Steam] Achievement skipped (Steam not running): %s" % achievement_id)
		return
	var was_set = _s.setAchievement(achievement_id)
	print("[Steam] setAchievement('%s') returned: %s" % [achievement_id, was_set])
	var stored = _s.storeStats()
	print("[Steam] storeStats() returned: %s" % stored)

func clear_achievement(achievement_id: String) -> void:
	if not steam_running:
		return
	_s.clearAchievement(achievement_id)
	_s.storeStats()

# ─── Cloud Saves ──────────────────────────────────────────────────────────────

func cloud_save(filename: String, data: String) -> bool:
	if not steam_running:
		return false
	if not _s.isCloudEnabled():
		return false
	var success = _s.fileWrite(filename, data.to_utf8_buffer())
	if success:
		print("[Steam] Cloud save written: %s" % filename)
	return success

func cloud_load(filename: String) -> String:
	if not steam_running:
		return ""
	if not _s.isCloudEnabled():
		return ""
	if not _s.fileExists(filename):
		return ""
	var size = _s.getFileSize(filename)
	if size <= 0:
		return ""
	var data = _s.fileRead(filename, size)
	print("[Steam] Cloud save loaded: %s (%d bytes)" % [filename, size])
	return data.get_string_from_utf8()

func cloud_has_file(filename: String) -> bool:
	if not steam_running:
		return false
	if not _s.isCloudEnabled():
		return false
	return _s.fileExists(filename)

# ─── Rich Presence ────────────────────────────────────────────────────────────

func set_status(status_text: String) -> void:
	if not steam_running:
		return
	_s.setRichPresence("status", status_text)
