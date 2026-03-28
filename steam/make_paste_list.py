import re

with open("achievements.vdf", "r") as f:
    content = f.read()

entries = re.findall(
    r'"name"\s+"([^"]+)"\s+"display_name"\s+"([^"]+)"\s+"description"\s+"([^"]+)"\s+"hidden"\s+"([^"]+)"',
    content
)

lines = []
for name, display, desc, hidden in entries:
    lines.append(f"{name}\n{display}\n{desc}\n{hidden}")

with open("achievement_paste_list.txt", "w", encoding="utf-8") as f:
    f.write("\n\n".join(lines))

print(f"Wrote {len(entries)} achievements to achievement_paste_list.txt")
