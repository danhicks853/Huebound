# refresh-steam-secret.ps1
# Refreshes the STEAM_CONFIG_VDF GitHub Actions secret.
# Run this whenever Steam deploys start failing with auth errors.
#
# Requirements: SteamCMD installed somewhere on this machine.
# Usage: .\scripts\ci\refresh-steam-secret.ps1

param(
    [string]$SteamCmdPath = "C:\steamcmd\steamcmd.exe",
    [string]$GithubRepo  = "danhicks853/Huebound"
)

# ── Locate SteamCMD ──────────────────────────────────────────────────────────
if (-not (Test-Path $SteamCmdPath)) {
    $SteamCmdPath = Read-Host "SteamCMD not found at default path. Enter full path to steamcmd.exe"
    if (-not (Test-Path $SteamCmdPath)) {
        Write-Error "SteamCMD not found at '$SteamCmdPath'. Aborting."
        exit 1
    }
}

# ── Run SteamCMD to refresh the session ──────────────────────────────────────
Write-Host "Logging in to Steam via SteamCMD to refresh session..."
Write-Host "(You may be prompted for a Steam Guard code.)"
& $SteamCmdPath +login (Read-Host "Steam username") +quit

# ── Find config.vdf ──────────────────────────────────────────────────────────
$SteamCmdDir = Split-Path $SteamCmdPath
$ConfigVdf   = Join-Path $SteamCmdDir "config\config.vdf"

if (-not (Test-Path $ConfigVdf)) {
    Write-Error "config.vdf not found at '$ConfigVdf'. Did the login succeed?"
    exit 1
}

# ── Base64-encode ─────────────────────────────────────────────────────────────
$Bytes   = [System.IO.File]::ReadAllBytes($ConfigVdf)
$Encoded = [System.Convert]::ToBase64String($Bytes)

$SizeMB = [math]::Round($Bytes.Length / 1KB, 1)
Write-Host "`nEncoded config.vdf ($SizeMB KB). GitHub secret limit is 48 KB."

if ($Bytes.Length / 1KB -gt 48) {
    Write-Error "Encoded value exceeds GitHub's 48 KB secret limit. This is the wrong config.vdf (use SteamCMD's, not the full Steam client's)."
    exit 1
}

# ── Copy to clipboard and open GitHub ────────────────────────────────────────
$Encoded | Set-Clipboard
Write-Host "Copied to clipboard."
Write-Host ""
Write-Host "Opening GitHub secrets page..."
Start-Process "https://github.com/$GithubRepo/settings/secrets/actions"
Write-Host ""
Write-Host "Steps:"
Write-Host "  1. Click STEAM_CONFIG_VDF -> Update"
Write-Host "  2. Paste (Ctrl+V) -> Save"
