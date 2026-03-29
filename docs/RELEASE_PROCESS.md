# Release Process Documentation

## Overview

Huebound uses GitHub Actions CI/CD to automatically build and deploy to Steam. The workflow handles:
- Building both full game and demo
- Toggling the `IS_DEMO` flag automatically
- Deploying to the correct Steam branch

---

## Git Workflow

**ALWAYS follow this branch workflow:**

1. **Create a feature branch** from `dev` when starting work
   ```bash
   git checkout dev
   git pull origin dev
   git checkout -b feature/your-work-description
   ```

2. **Work on the feature branch** — make all changes here

3. **When complete, create PR to `dev` branch** (NOT master)
   ```bash
   git push origin feature/your-work-description
   # Create PR via GitHub: feature → dev
   ```

4. **After PR is merged to `dev`, CI/CD publishes to Steam preview branch**
   - User tests the build on Steam

5. **User creates PR from `dev` to `master`**

6. **After PR is merged to `master`, CI/CD publishes to Steam default branch**

**NEVER push directly to `master`. All work goes through `dev` first.**

---

## CI/CD Deployment

### What Happens Automatically

| Trigger | Main Game | Demo |
|---------|-----------|------|
| Push to `dev` | Builds → uploads to default → promotes to `preview` | Builds → uploads to `default` |
| Push to `master` | Builds → uploads to `default` | Builds → uploads to `default` |

The workflow (`.github/workflows/steam-deploy.yml`):
1. Checks out code
2. Sets up Godot
3. Installs GodotSteam export templates
4. Builds full game (`IS_DEMO = false`)
5. Builds demo (`IS_DEMO = true`)
6. Deploys demo to Steam default branch
7. Deploys main game to default branch
8. On dev branch: promotes main game to preview branch

### Manual Override

You can manually trigger a build via GitHub Actions:
1. Go to Actions → Build and Deploy to Steam
2. Click "Run workflow"
3. Select branch and run

---

## Demo vs Full Game

| Aspect | Full Game | Demo |
|--------|-----------|------|
| **Flag** | `IS_DEMO = false` | `IS_DEMO = true` |
| **Colors** | All 256 | 20 only |
| **Splitter node** | Available | Blocked |
| **Export folder** | `export/` | `export_demo/` |
| **Steam App ID** | 4459040 | 4555340 |
| **Release branch** | `preview` (dev) / `default` (master) | `default` |

---

## Steam App IDs

| App | App ID | Depot ID |
|-----|--------|----------|
| Main Game | 4459040 | 4459041 |
| Demo | 4555340 | 4555341 |

---

## Local Development (If Needed)

If you need to build manually:

### Build Full Game
```bash
# Ensure IS_DEMO is false in scripts/autoloads/demo_config.gd
godot --headless --export-release "Steam Windows" export/Huebound.exe
```

### Build Demo
```bash
# Set IS_DEMO = true in scripts/autoloads/demo_config.gd
godot --headless --export-release "Steam Windows" export_demo/Huebound.exe

# Reset to false for development
```

---

## Troubleshooting

### Demo has full game content
**Cause**: CI/CD or manual export had `IS_DEMO = false`
**Fix**: Check the workflow run logs to verify the sed command changed the flag

### Build failed in CI/CD
**Cause**: Usually missing secrets or GodotSteam templates
**Fix**: 
- Verify `STEAM_WEB_API_KEY` and `STEAM_CONFIG_VDF` secrets are set
- Check GodotSteam template download step

### Preview branch not updating
**Cause**: `STEAM_BUILD_ID` secret not set after main game upload
**Fix**: The workflow logs show the build ID - set it as a secret for auto-promotion

---

## Secrets Required

In GitHub repo Settings → Secrets and variables → Actions:

| Secret | Required | Purpose |
|--------|----------|---------|
| `STEAM_WEB_API_KEY` | Yes | Steam Web API key for authentication |
| `STEAM_CONFIG_VDF` | Yes | Steam depot configuration |
| `STEAM_BUILD_ID` | No | Main game build ID for preview promotion |
| `STEAM_DEMO_BUILD_ID` | No | Demo build ID (not used - demo stays on default) |

*Last Updated: 2026-03-29*
