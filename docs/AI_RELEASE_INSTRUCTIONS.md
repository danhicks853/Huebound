# Huebound — AI Release Instructions

This document provides instructions for an AI agent working on Huebound releases.

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

3. **When complete, create PR to `dev` branch**
   ```bash
   git push origin feature/your-work-description
   # Create PR via GitHub: feature → dev
   ```

4. **After PR is merged to `dev`, CI/CD automatically publishes to Steam preview branch**

5. **User creates PR from `dev` to `master`**

6. **After PR is merged to `master`, CI/CD automatically publishes to Steam default branch**

**NEVER push directly to `master`. All work goes through `dev` first.**

---

## CI/CD Handles Everything

The GitHub Actions workflow (`.github/workflows/steam-deploy.yml`) automatically:

1. ✅ Sets `IS_DEMO = false` and builds full game
2. ✅ Sets `IS_DEMO = true` and builds demo
3. ✅ Resets `IS_DEMO = false` after builds
4. ✅ Uploads demo to Steam default branch
5. ✅ Uploads main game to Steam default branch
6. ✅ Promotes main game to preview branch (on dev merge only)

**Do not manually toggle `IS_DEMO` or run manual builds unless specifically requested.**

---

## Quick Reference

| Item | Value |
|------|-------|
| App ID (Main) | 4459040 |
| Depot ID (Main) | 4459041 |
| App ID (Demo) | 4555340 |
| Depot ID (Demo) | 4555341 |
| Dev branch → | Preview branch on Steam |
| Master branch → | Default branch on Steam |

---

## When to Intervene

Only perform manual builds if:

1. **CI/CD is broken** and a hotfix is needed urgently
2. **User specifically requests** a manual build
3. **Testing locally** before submitting a PR

### Manual Build Steps (Only If Needed)

```powershell
# Full game
godot --headless --export-release "Steam Windows" export/Huebound.exe

# Demo
# Edit scripts/autoloads/demo_config.gd: const IS_DEMO := true
godot --headless --export-release "Steam Windows" export_demo/Huebound.exe
# Reset: const IS_DEMO := false
```

---

## Common Issues

### "CI/CD failed"
- Check GitHub Actions logs for the specific error
- Usually missing secrets or template issues

### "Wrong branch deployed"
- Verify the trigger was from correct branch
- Dev → preview, Master → default

---

*Last Updated: 2026-03-29*
