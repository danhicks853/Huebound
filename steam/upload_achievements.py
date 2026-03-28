"""
Bulk-create Huebound achievements on Steamworks using Selenium browser automation.

This script logs into Steamworks and creates each achievement via the admin UI,
since Steamworks has no public API for creating achievement definitions.

Usage:
    pip install selenium
    python upload_achievements.py

You will be prompted to log in to Steam manually (including Steam Guard).
The script will then create all achievements automatically.

Alternative: Run with --csv to just generate a CSV reference file.
    python upload_achievements.py --csv
"""

import sys
import re
import time
import os

APP_ID = 4459040
ACHIEVEMENTS_URL = f"https://partner.steamworks.com/apps/achievements/{APP_ID}"


def parse_vdf(filepath: str) -> list[dict]:
    """Parse the achievements.vdf file into a list of achievement dicts."""
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    achievements = []
    blocks = re.findall(r'"(\d+)"\s*\{([^}]+)\}', content)

    for block_id, block_body in blocks:
        fields = dict(re.findall(r'"(\w+)"\s+"([^"]*)"', block_body))
        if "name" in fields:
            achievements.append({
                "id": int(block_id),
                "api_name": fields["name"],
                "display_name": fields.get("display_name", fields["name"]),
                "description": fields.get("description", ""),
                "hidden": fields.get("hidden", "0") == "1",
            })

    return achievements


def generate_csv(achievements: list[dict], output_path: str):
    """Generate a CSV reference file."""
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("api_name,display_name,description,hidden\n")
        for a in achievements:
            name = a["api_name"]
            display = a["display_name"].replace('"', '""')
            desc = a["description"].replace('"', '""')
            hidden = "1" if a["hidden"] else "0"
            f.write(f'{name},"{display}","{desc}",{hidden}\n')
    print(f"CSV written to: {output_path}")


def generate_js_console_script(achievements: list[dict], output_path: str):
    """
    Generate a JavaScript snippet that can be pasted into the browser console
    on the Steamworks achievements page to create achievements in bulk.
    This is the most practical approach for 260+ achievements.
    """
    lines = []
    lines.append("// Huebound Achievement Bulk Creator")
    lines.append("// Paste this into the browser console on the Steamworks achievements page:")
    lines.append(f"// {ACHIEVEMENTS_URL}")
    lines.append("//")
    lines.append("// This uses the same AJAX calls that the Steamworks UI makes internally.")
    lines.append("")
    lines.append("const APP_ID = %d;" % APP_ID)
    lines.append("const achievements = [")

    for a in achievements:
        api = a["api_name"].replace("'", "\\'")
        display = a["display_name"].replace("'", "\\'")
        desc = a["description"].replace("'", "\\'")
        hidden = "true" if a["hidden"] else "false"
        lines.append(f"  {{api: '{api}', name: '{display}', desc: '{desc}', hidden: {hidden}}},")

    lines.append("];")
    lines.append("")
    lines.append("""
async function createAchievements() {
    const sessionid = document.cookie.match(/sessionid=([^;]+)/)?.[1];
    if (!sessionid) {
        console.error('No session ID found. Make sure you are logged into Steamworks.');
        return;
    }

    let success = 0;
    let failed = 0;

    for (let i = 0; i < achievements.length; i++) {
        const a = achievements[i];
        const formData = new FormData();
        formData.append('sessionid', sessionid);
        formData.append('appid', APP_ID);
        formData.append('achievement_api_name', a.api);
        formData.append('achievement_display_name', a.name);
        formData.append('achievement_description', a.desc);
        formData.append('achievement_hidden', a.hidden ? '1' : '0');

        try {
            const resp = await fetch(
                `https://partner.steamworks.com/apps/newachievement/${APP_ID}`,
                { method: 'POST', body: formData, credentials: 'include' }
            );

            if (resp.ok) {
                success++;
                if ((i + 1) % 25 === 0) {
                    console.log(`[${i + 1}/${achievements.length}] created...`);
                }
            } else {
                failed++;
                if (failed <= 5) {
                    const text = await resp.text();
                    console.warn(`FAILED: ${a.api} - HTTP ${resp.status}: ${text.substring(0, 200)}`);
                }
            }
        } catch (e) {
            failed++;
            if (failed <= 5) console.warn(`ERROR: ${a.api} -`, e);
        }

        // Small delay to avoid rate limiting
        await new Promise(r => setTimeout(r, 200));
    }

    console.log('Done! Success: ' + success + ', Failed: ' + failed);
    console.log('Refresh the page to see all achievements.');
}

console.log(`Ready to create ${achievements.length} achievements for App ${APP_ID}.`);
console.log('Starting in 3 seconds...');
setTimeout(createAchievements, 3000);
""")

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"JavaScript console script written to: {output_path}")


def main():
    vdf_path = os.path.join(os.path.dirname(__file__), "achievements.vdf")
    achievements = parse_vdf(vdf_path)
    print(f"Parsed {len(achievements)} achievements from achievements.vdf")

    if "--csv" in sys.argv:
        csv_path = os.path.join(os.path.dirname(__file__), "achievements_import.csv")
        generate_csv(achievements, csv_path)
        return

    # Generate the JS console script (most reliable method)
    js_path = os.path.join(os.path.dirname(__file__), "create_achievements.js")
    generate_js_console_script(achievements, js_path)

    print()
    print("=" * 60)
    print("HOW TO USE:")
    print("=" * 60)
    print()
    print(f"1. Open this URL in your browser (logged into Steamworks):")
    print(f"   {ACHIEVEMENTS_URL}")
    print()
    print(f"2. Open browser DevTools (F12) → Console tab")
    print()
    print(f"3. Copy-paste the contents of:")
    print(f"   {js_path}")
    print()
    print(f"4. Press Enter — it will create all {len(achievements)} achievements")
    print(f"   (takes about {len(achievements) * 0.2 / 60:.0f} minutes)")
    print()
    print(f"5. Refresh the page to see them all")
    print("=" * 60)


if __name__ == "__main__":
    main()
