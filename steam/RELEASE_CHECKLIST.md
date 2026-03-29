# Huebound — Steam Release Checklist

**App ID: 4459040 | Depot ID: 4459041**

---

## Git Workflow

**ALWAYS follow this branch workflow:**

- [ ] **Create feature branch from `dev`**
  ```bash
  git checkout dev
  git pull origin dev
  git checkout -b feature/your-work-description
  ```

- [ ] **Work on feature branch** — all changes go here

- [ ] **When complete, PR to `dev` branch** (NOT master)
  ```bash
  git push origin feature/your-work-description
  # Create PR: feature → dev
  ```

- [ ] **After PR merged, CI/CD publishes to Steam preview branch**
  - User tests the build on Steam

- [ ] **User creates PR from `dev` to `master`**

- [ ] **After PR merged to master, CI/CD publishes to Steam default branch**

**NEVER push directly to `master`. All work goes through `dev` first.**

---

## CI/CD Deployment

All builds are handled automatically by GitHub Actions (`.github/workflows/steam-deploy.yml`):

| Trigger | Main Game | Demo |
|---------|-----------|------|
| Push to `dev` | → Preview branch | → Default branch |
| Push to `master` | → Default branch | → Default branch |

Manual builds are only needed if CI/CD is broken.

---

## Steamworks Store Page

Log into https://partner.steamworks.com → App Admin → 4459040

### Basic Info
- [ ] App name: Huebound
- [ ] Developer/Publisher: Dan Hicks
- [ ] Release type: Early Access

### Store Page → About This Game
- [ ] Copy long description from `steam/store_page.md`
- [ ] Supports basic HTML: `<b>`, `<i>`, `<ul>`, `<li>`, `<h2>`

### Store Page → Short Description
- [ ] Copy from `steam/store_page.md` (max 300 chars)

### Early Access Tab
- [ ] Fill in all 5 Q&A answers from `steam/store_page.md`

### Tags
Idle, Clicker, Casual, Strategy, Puzzle, Colorful, Relaxing, Abstract, Factory

### Genre
Casual, Indie, Strategy

---

## Required Store Images

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

---

## Achievements

In Steamworks → Stats & Achievements → Achievements

**Key achievements** (add at minimum):
- `first_color` - Discover first color
- `ten_colors` - Discover 10 colors
- `fifty_colors` - Discover 50 colors
- `hundred_colors` - Discover 100 colors
- `all_colors` - Discover all 256 colors
- `ten_nodes` - Place 10 nodes
- `rich` - Earn 10,000 total Light

Each achievement needs a **64x64 icon** (locked + unlocked versions).

---

## Quick Reference

| Item | Value |
|------|-------|
| App ID | 4459040 |
| Depot ID | 4459041 |
| Demo App ID | 4555340 |
| Export preset | "Steam Windows" |
| Build output | `export/` (full), `export_demo/` (demo) |
| Store copy | `steam/store_page.md` |
| Achievements | `steam/achievements.vdf` |

---

*Last Updated: 2026-03-29*
