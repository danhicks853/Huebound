# Release Process Documentation

## Overview

Huebound uses a single export preset with a code flag to differentiate full game vs demo builds. The `IS_DEMO` constant in `demo_config.gd` controls feature restrictions.

---

## Demo vs Full Game

| Aspect | Full Game | Demo |
|--------|-----------|------|
| **Flag** | `IS_DEMO = false` | `IS_DEMO = true` |
| **Colors** | All 256 | 20 only |
| **Splitter node** | Available | Blocked |
| **Export folder** | `export/` | `export_demo/` |
| **Steam App ID** | 4459040 | 4555340 |

---

## Build Steps

### Step 1: Build Full Game

1. **Verify demo flag is OFF**:
   ```gdscript
   # scripts/autoloads/demo_config.gd
   const IS_DEMO := false
   ```

2. **Export from Godot**:
   - Project → Export → "Steam Windows" → Export Project
   - Output: `d:\aigame\idlegame\export\Huebound.exe`

### Step 2: Build Demo

1. **Toggle demo flag ON**:
   ```gdscript
   # scripts/autoloads/demo_config.gd
   const IS_DEMO := true
   ```

2. **Export from Godot**:
   - Project → Export → "Steam Windows" → Export Project
   - Output: `d:\aigame\idlegame\export_demo\Huebound.exe`

3. **Toggle flag back to FALSE** for normal development

---

## Steam Upload

### Option A: Manual SteamCMD

```powershell
# Full game
cd d:\aigame\idlegame\export
.\steamcmd.exe +login z932074 +run_app_build "D:\aigame\idlegame\steam\build\app_build.vdf" +quit

# Demo
cd d:\aigame\idlegame\export_demo
.\steamcmd.exe +login z932074 +run_app_build "D:\aigame\idlegame\steam\build\app_build_demo.vdf" +quit
```

### Option B: Automated (Single Session)

Copy `steamcmd.exe` to one location and run both builds:
```powershell
cd d:\aigame\idlegame\export_demo
.\steamcmd.exe +login z932074 +run_app_build "D:\aigame\idlegame\steam\build\app_build.vdf" +run_app_build "D:\aigame\idlegame\steam\build\app_build_demo.vdf" +quit
```

---

## Build Config Files

### Main App (`steam/build/app_build.vdf`)
```vdf
"AppBuild"
{
	"AppID" "4459040"
	"Desc" "Huebound Early Access build"
	"ContentRoot" "D:\aigame\idlegame\export\"
	"BuildOutput" "..\output\"
	"Depots"
	{
		"4459041" "depot_build_windows.vdf"
	}
}
```

### Demo (`steam/build/app_build_demo.vdf`)
```vdf
"AppBuild"
{
	"AppID" "4555340"
	"Desc" "Huebound Demo build"
	"ContentRoot" "D:\aigame\idlegame\export_demo\"
	"BuildOutput" "..\output\"
	"Depots"
	{
		"4555341" "depot_build_demo.vdf"
	}
}
```

---

## Critical Checklist

- [ ] `demo_config.gd` has `IS_DEMO = false` before full game export
- [ ] `demo_config.gd` has `IS_DEMO = true` before demo export
- [ ] `demo_config.gd` reset to `IS_DEMO = false` after both exports
- [ ] Both `export/` and `export_demo/` folders exist with builds
- [ ] SteamCMD login successful
- [ ] Both builds appear in Steamworks after upload

---

## Troubleshooting

### Demo has full game content
**Cause**: Exported with `IS_DEMO = false`
**Fix**: Toggle flag, re-export demo, verify in `export_demo/`

### SteamCMD can't find executable
**Cause**: steamcmd.exe not in current directory
**Fix**: Use `.\steamcmd.exe` syntax or copy steamcmd.exe to export folder

### Build uploads but doesn't work
**Cause**: Missing GodotSteam DLLs
**Fix**: Verify `libgodotsteam.windows.template_release.x86_64.dll` is in export folder
