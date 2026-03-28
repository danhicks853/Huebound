# Huebound — AI Release Instructions

This document provides step-by-step instructions for an AI agent to build and release Huebound to Steam.

---

## Critical: Demo Flag Toggle

**THIS IS THE MOST IMPORTANT STEP.** The demo is NOT a separate export preset. It's the same preset with a code flag changed.

| Build | IS_DEMO Value | Export Folder |
|-------|---------------|---------------|
| Full Game | `false` | `export/` |
| Demo | `true` | `export_demo/` |

File to modify: `d:\aigame\idlegame\scripts\autoloads\demo_config.gd`

---

## Quick Reference

| Item | Value |
|------|-------|
| App ID (Main) | 4459040 |
| Depot ID (Main) | 4459041 |
| App ID (Demo) | 4555340 |
| Depot ID (Demo) | 4555341 |
| Godot Path | `C:\Users\danhi\OneDrive\Desktop\Godot_v4.6.1-stable_win64.exe` |
| SteamCMD | `d:\aigame\idlegame\export_demo\steamcmd.exe` |

---

## Phase 1: Build Full Game

### Step 1.1: Verify IS_DEMO = false

Check `d:\aigame\idlegame\scripts\autoloads\demo_config.gd`:
```gdscript
const IS_DEMO := false
```

If it's `true`, change it to `false`.

### Step 1.2: Export Full Game

```powershell
C:\Users\danhi\OneDrive\Desktop\Godot_v4.6.1-stable_win64.exe --headless --export-release "Steam Windows" d:\aigame\idlegame\export\Huebound.exe
```

Verify output: `d:\aigame\idlegame\export\Huebound.exe` exists.

---

## Phase 2: Build Demo

### Step 2.1: Set IS_DEMO = true

Edit `d:\aigame\idlegame\scripts\autoloads\demo_config.gd`:
```gdscript
const IS_DEMO := true
```

### Step 2.2: Export Demo

```powershell
C:\Users\danhi\OneDrive\Desktop\Godot_v4.6.1-stable_win64.exe --headless --export-release "Steam Windows" d:\aigame\idlegame\export_demo\Huebound.exe
```

Verify output: `d:\aigame\idlegame\export_demo\Huebound.exe` exists.

### Step 2.3: Reset IS_DEMO = false

**IMPORTANT**: Set the flag back for normal development:
```gdscript
const IS_DEMO := false
```

---

## Phase 3: Upload to Steam

### Step 3.1: Verify Builds Exist

Check both folders have the `.exe`:
- `d:\aigame\idlegame\export\Huebound.exe` (full game)
- `d:\aigame\idlegame\export_demo\Huebound.exe` (demo)

### Step 3.2: Run SteamCMD

```powershell
cd d:\aigame\idlegame\export_demo
.\steamcmd.exe +login z932074 +run_app_build "D:\aigame\idlegame\steam\build\app_build.vdf" +run_app_build "D:\aigame\idlegame\steam\build\app_build_demo.vdf" +quit
```

**Expected prompts:**
1. Password for z932074
2. Steam Guard code

**What happens:**
1. First build uploads main game (4459040) from `export/`
2. Second build uploads demo (4555340) from `export_demo/`
3. Both appear in Steamworks → Builds

---

## Complete Checklist

Before starting:
- [ ] Godot executable exists at desktop path
- [ ] `steamcmd.exe` exists in `export_demo/` (or copy it there)

After Phase 1:
- [ ] `IS_DEMO` was `false` during export
- [ ] `export\Huebound.exe` exists

After Phase 2:
- [ ] `IS_DEMO` was toggled to `true` for demo export
- [ ] `export_demo\Huebound.exe` exists
- [ ] `IS_DEMO` reset to `false` after both exports

After Phase 3:
- [ ] SteamCMD login successful
- [ ] Both builds show in Steamworks

---

## Common Mistakes

### "Demo has all 256 colors"
**Cause**: Forgot to set `IS_DEMO = true` before demo export.  
**Fix**: Toggle flag, delete `export_demo\*`, re-export demo.

### "steamcmd.exe not found"
**Cause**: Running from wrong directory or wrong path.  
**Fix**: `cd d:\aigame\idlegame\export_demo` first, then use `.\steamcmd.exe`

### "Full game uploaded as demo"
**Cause**: Both depot configs pointed to same folder.  
**Fix**: Verify `app_build.vdf` uses `export/` and `app_build_demo.vdf` uses `export_demo/`

---

## Build Config Reference

Main app VDF (`steam/build/app_build.vdf`):
- AppID: 4459040
- ContentRoot: `D:\aigame\idlegame\export\`
- Depot: 4459041

Demo VDF (`steam/build/app_build_demo.vdf`):
- AppID: 4555340
- ContentRoot: `D:\aigame\idlegame\export_demo\`
- Depot: 4555341

---

*Last Updated: 2026-03-28*
