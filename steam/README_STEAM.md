# Huebound — Steam Release Guide

## Prerequisites

1. **Steamworks Account** — Create at https://partner.steamworks.com
2. **$100 App Fee** — Pay per title in Steamworks
3. **Tax/Banking Info** — Complete in Steamworks settings
4. **SteamCMD** — Download from https://developer.valvesoftware.com/wiki/SteamCMD

## Step-by-Step Process

### 1. Create Your App in Steamworks

- Log into https://partner.steamworks.com
- Click "Create new app" → choose "Game"
- Name: **Huebound**
- Pay the $100 fee
- Note your **App ID** and **Depot ID** (usually App ID + 1)

### 2. Update Build Config Files

Replace placeholder IDs in these files:
- `steam/build/app_build.vdf` — replace `APPID` with your App ID
- `steam/build/app_build.vdf` — replace `DEPOTID` with your Depot ID
- `steam/build/depot_build_windows.vdf` — replace `DEPOTID` with your Depot ID

### 3. Set Up Store Page

Use the copy in `steam/store_page.md` to fill out:
- **Store Page** → About This Game (long description)
- **Store Page** → Short Description
- **Early Access** → Answer all 4 required questions
- **Tags & Genre** — suggested lists included

#### Required Store Assets (create these):
| Asset | Size | Notes |
|-------|------|-------|
| Header Capsule | 460x215 | Main store listing image |
| Small Capsule | 231x87 | Wishlist/browse views |
| Main Capsule | 616x353 | Featured/sale banners |
| Hero Graphic | 3840x1240 | Top of store page |
| Logo | 940x400 | Transparent PNG |
| Screenshots | 1280x720+ | Minimum 5 required |
| Library Capsule | 600x900 | Steam library grid view |
| Library Hero | 3840x1240 | Steam library background |

**Tip**: Since Huebound is procedural/geometric, take in-game screenshots at 1920x1080 showing a colorful factory with many connections and discovered colors.

### 4. Install GodotSteam

See `steam/GODOTSTEAM_SETUP.md` for full integration instructions.

### 5. Export and Upload

**Normal workflow (recommended):**
- Push changes to `dev` or `master` branch
- GitHub Actions automatically builds and deploys
- See `.github/workflows/steam-deploy.yml` for details

**Manual export (only if CI/CD is broken):**
```bash
# In Godot Editor:
# Project → Export → "Steam Windows" preset → Export Project
# Output to: export/Huebound.exe
```

Manual upload via SteamCMD:
```bash
steamcmd +login YOUR_STEAM_USERNAME +run_app_build "steam/build/app_build.vdf" +quit
```

You'll be prompted for your password and Steam Guard code.

### 7. Configure Launch Options in Steamworks

In Steamworks → Installation → General:
- **Executable**: `Huebound.exe`
- **OS**: Windows
- **Launch Type**: Launch (Default)

### 8. Submit for Review

1. **Store Page Review** — Submit store page first (2-5 business days)
2. **Build Review** — After store page is approved, set your build live on a branch
3. **Release** — Set release date or click "Release Now"

### 9. Early Access Checklist

Before going live, verify:
- [ ] Store page copy is complete and reviewed
- [ ] All 5+ screenshots uploaded
- [ ] All capsule images uploaded
- [ ] Early Access Q&A filled out
- [ ] Build uploaded and tested via Steam
- [ ] Launch options configured
- [ ] Pricing set (or Free to Play)
- [ ] Age rating questionnaire completed
- [ ] Tax interview completed

## File Structure

```
steam/
├── README_STEAM.md          ← This file
├── store_page.md            ← Store description + EA Q&A
├── GODOTSTEAM_SETUP.md      ← GodotSteam integration guide
└── build/
    ├── app_build.vdf        ← SteamCMD app build config
    └── depot_build_windows.vdf  ← Windows depot config
```

```
export/                     ← Created during export (gitignored)
├── Huebound.exe
├── Huebound.pck
└── ...
```
