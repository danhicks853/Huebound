# Huebound — Steam Release Checklist

**App ID: 4459040 | Depot ID: 4459041**

---

## Phase 1: GodotSteam Setup

- [ ] **Download GodotSteam pre-compiled editor** matching Godot 4.6 to `D:\godot`
  - Go to https://godotsteam.com/ → Downloads
  - Get the **Godot 4.6** GodotSteam editor for Windows
  - Extract to `D:\godot\`
  - Also download the matching **export templates**
- [ ] **Open Huebound with the GodotSteam editor** (`D:\godot\Godot.exe` — not the standard Godot editor)
  - Verify console prints: `[Steam] Initialized — user: YourName`
  - If Steam isn't running, you'll see: `[Steam] Init failed` — that's expected
- [ ] **Set custom export template**
  - Project → Export → "Steam Windows" preset
  - Set **Custom Template (Release)** to `D:\godot\templates\windows_release.exe`
- [ ] **Test Steam overlay**
  - Have Steam running on your machine
  - `steam_appid.txt` already created in project root with `4459040`
  - Run from GodotSteam editor → press Shift+Tab → Steam overlay should appear

## Phase 2: Steamworks Store Page

Log into https://partner.steamworks.com → App Admin → 4459040

- [ ] **Basic Info**
  - App name: Huebound
  - Developer/Publisher: Dan Hicks
  - Release type: Early Access
- [ ] **Store Page → About This Game**
  - Copy long description from `steam/store_page.md`
  - Supports basic HTML: `<b>`, `<i>`, `<ul>`, `<li>`, `<h2>`
- [ ] **Store Page → Short Description**
  - Copy from `steam/store_page.md` (max 300 chars)
- [ ] **Early Access tab**
  - Fill in all 5 Q&A answers from `steam/store_page.md`
- [ ] **Tags**: Idle, Clicker, Casual, Strategy, Puzzle, Colorful, Relaxing, Abstract, Factory
- [ ] **Genre**: Casual, Indie, Strategy

### Required Store Images

Take screenshots at **1920x1080** showing a colorful factory with many connections.

| Asset | Size | Status |
|-------|------|--------|
| Header Capsule | 460x215 | [ ] |
| Small Capsule | 231x87 | [ ] |
| Main Capsule | 616x353 | [ ] |
| Hero Graphic | 3840x1240 | [ ] |
| Logo | 940x400 (transparent PNG) | [ ] |
| Library Capsule | 600x900 | [ ] |
| Library Hero | 3840x1240 | [ ] |
| Screenshots (min 5) | 1280x720+ | [ ] |

**Tip**: Since the game is procedural/geometric, take screenshots showing:
1. A large colorful factory with many connections and orbs flowing
2. The collection gallery with many colors discovered
3. The prestige dialog
4. A close-up of combiners mixing colors
5. The shop/upgrade panel

## Phase 3: Achievements (Optional but Recommended)

- [ ] In Steamworks → Stats & Achievements → Achievements
  - Use `steam/achievements.vdf` as reference — 260+ achievements defined
  - You can bulk-import or add key ones manually
  - At minimum add: `first_color`, `ten_colors`, `fifty_colors`, `hundred_colors`, `all_colors`, `ten_nodes`, `rich`
  - Each achievement needs a **64x64 icon** (locked + unlocked versions)
- [ ] **Achievement icons**: Create simple geometric icons matching the game's style
  - Unlocked: colored circle/shape on dark background
  - Locked: grey silhouette version

## Phase 4: Build & Upload

- [ ] **Export the game**
  ```
  In GodotSteam Editor (D:\godot\Godot.exe):
  Project → Export → "Steam Windows" → Export Project
  Output: export/Huebound.exe
  ```
- [ ] **Copy steam_api64.dll** into `export/`
  - Get it from the Steamworks SDK: `sdk/redistributable_bin/win64/steam_api64.dll`
  - Or it may be included automatically by GodotSteam export templates
- [ ] **Verify export/ contains**:
  ```
  Huebound.exe
  steam_api64.dll
  ```
  Do NOT include `steam_appid.txt` in the build output.
- [ ] **Install SteamCMD** (if not already)
  - Download from https://developer.valvesoftware.com/wiki/SteamCMD
- [ ] **Upload build**
  ```
  steamcmd +login YOUR_STEAM_USERNAME +run_app_build "D:\aigame\idlegame\steam\build\app_build.vdf" +quit
  ```
  You'll be prompted for password and Steam Guard code.
- [ ] **Verify upload** in Steamworks → Builds → should show new build

## Phase 5: Launch Configuration

In Steamworks → Installation → General:

- [ ] **Executable**: `Huebound.exe`
- [ ] **OS**: Windows
- [ ] **Launch Type**: Launch (Default)

## Phase 6: Pricing & Release

- [ ] **Set pricing** in Steamworks → Pricing
  - Suggested EA price: $2.99–$4.99 (or Free to Play)
  - Valve reviews pricing — allow 2+ days
- [ ] **Age rating questionnaire** — complete in Steamworks
- [ ] **Tax/banking info** — verify completed in Steamworks settings
- [ ] **Submit store page for review** (2-5 business days)
- [ ] **After store page approved**: Set build live on Default branch
- [ ] **Set release date** or click "Release Now"

## Phase 7: Post-Launch

- [ ] **Test the live build** — install from Steam, verify it runs
- [ ] **Verify cloud saves work** (if enabled)
- [ ] **Announce on itch.io** that Steam version is available
- [ ] **Monitor Steam discussions** for bug reports

---

## Quick Reference

| Item | Value |
|------|-------|
| App ID | 4459040 |
| Depot ID | 4459041 |
| Export preset | "Steam Windows" |
| Build output | `export/` |
| VDF configs | `steam/build/` |
| Store copy | `steam/store_page.md` |
| Achievements | `steam/achievements.vdf` |
