# GodotSteam Integration Guide for Huebound

## Overview

GodotSteam is a Steamworks SDK wrapper for Godot. It enables:
- Steam overlay
- Cloud saves
- Achievements
- Steam user identity
- Rich presence

## Option A: Pre-compiled Editor (Recommended for Speed)

The easiest approach — download a Godot editor that already has GodotSteam compiled in.

1. Go to https://godotsteam.com/
2. Download the **GodotSteam pre-compiled editor** matching your Godot version (4.3+)
3. Extract to `D:\godot\`
4. Download the matching **export templates** to `D:\godot\templates\`
5. Open your project with `D:\godot\Godot.exe` instead of the standard Godot editor
6. In Export → Steam Windows preset, set the custom export template to `D:\godot\templates\windows_release.exe`

## Option B: GDExtension Plugin (No Custom Editor)

If you prefer to keep the standard Godot editor:

1. Download the GodotSteam GDExtension from https://github.com/GodotSteam/GodotSteam/releases
2. Extract into your project's `addons/godotsteam/` folder
3. Copy `steam_api64.dll` (from the Steamworks SDK) into your project root
4. Enable the plugin in Project → Project Settings → Plugins

## Steam App ID File

Create a file called `steam_appid.txt` in your project root (next to Huebound.exe) containing just your App ID:

```
APPID
```

This is required for development/testing. Steam uses it to identify your game when not launched through the Steam client. **Do NOT ship this file** — Steam provides the App ID automatically when launched through the client.

## Code Integration

### 1. Create Steam Autoload

Create `scripts/autoloads/steam_manager.gd`:

```gdscript
extends Node

var steam_running := false
var _s: Object = null  # Steam singleton reference

func _ready() -> void:
    if Engine.has_singleton("Steam"):
        _s = Engine.get_singleton("Steam")
        var init = _s.steamInitEx(APP_ID, true)  # Replace APP_ID
        steam_running = (init.status == 0)
        if steam_running:
            print("Steam initialized successfully")
        else:
            print("Steam init failed: ", init.verbal)
    else:
        print("Steam singleton not available (not using GodotSteam build)")

func _process(_delta: float) -> void:
    if steam_running:
        _s.run_callbacks()
```

Add to autoloads in `project.godot`:
```
SteamManager="*res://scripts/autoloads/steam_manager.gd"
```

### 2. Cloud Saves (Replace FileAccess)

In `game_state.gd`, wrap save/load to use Steam Cloud when available:

```gdscript
func _save_to_steam_cloud(data: String) -> void:
    if Engine.has_singleton("Steam") and Steam.isCloudEnabled():
        Steam.fileWrite("huebound_save.json", data.to_utf8_buffer())

func _load_from_steam_cloud() -> String:
    if Engine.has_singleton("Steam") and Steam.isCloudEnabled():
        if Steam.fileExists("huebound_save.json"):
            var size = Steam.getFileSize("huebound_save.json")
            var data = Steam.fileRead("huebound_save.json", size)
            return data.get_string_from_utf8()
    return ""
```

### 3. Achievements (Suggested)

Potential achievements for Huebound:

| ID | Name | Description | Trigger |
|----|------|-------------|---------|
| `first_color` | First Light | Discover your first color | `discovery_count >= 1` |
| `ten_colors` | Palette Beginner | Discover 10 colors | `discovery_count >= 10` |
| `fifty_colors` | Color Enthusiast | Discover 50 colors | `discovery_count >= 50` |
| `hundred_colors` | Chromatic | Discover 100 colors | `discovery_count >= 100` |
| `all_colors` | Huebound | Discover all 256 colors | `discovery_count >= 256` |
| `first_combine` | Mix Master | Create your first combined color | First combiner output |
| `tier_5` | Exotic Hue | Discover a Tier 5 color | Sell a tier 5 color |
| `ten_nodes` | Factory Floor | Place 10 nodes | `placed_nodes.size() >= 10` |
| `rich` | Enlightened | Accumulate 10,000 Light | `total_earned >= 10000` |

To unlock an achievement:
```gdscript
if Engine.has_singleton("Steam"):
    Steam.setAchievement("first_color")
    Steam.storeStats()
```

### 4. Rich Presence (Optional)

Show what the player is doing in their Steam status:

```gdscript
if Engine.has_singleton("Steam"):
    Steam.setRichPresence("status", "Discovering colors (%d/256)" % discovery_count)
```

## Export Configuration

In your "Steam Windows" export preset:
- Set **Custom Template (Release)** to `D:\godot\templates\windows_release.exe`
- Ensure `steam_api64.dll` is included alongside the executable
- Do NOT include `steam_appid.txt` in the export

## Testing

1. Have Steam running on your machine
2. Create `steam_appid.txt` with your App ID in the project root
3. Run from `D:\godot\Godot.exe` — Steam overlay should work (Shift+Tab)
4. Check Steam client → your game should show as "Playing" in your friends list

## Files to Ship

Your final Steam build folder should contain:
```
Huebound.exe
Huebound.pck          (or embedded in .exe)
Huebound.console.exe  (optional, for debug)
steam_api64.dll       (REQUIRED — from Steamworks SDK)
```

Do NOT ship:
- `steam_appid.txt` (development only)
- `.pdb` files (debug symbols)
- `export/` folder (web build)
