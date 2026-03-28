"""
Generate Steam achievement icons for Huebound.

For each color achievement: a glowing circle of that color on a dark background.
For gameplay achievements: simple geometric icons.

Achieved = full color
Unachieved = grayscale version

Output: steam/icons/{api_name}.jpg and steam/icons/{api_name}_gray.jpg
Size: 256x256 (Steam recommended)

Usage:
    pip install Pillow
    python generate_icons.py
"""

import re
import os
import math
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

ICON_SIZE = 256
BG_COLOR = (15, 15, 25)
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "icons")


def parse_colors_from_gdscript(filepath: str) -> dict:
    """Parse color names and RGB values from color_palette.gd."""
    colors = {}
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            m = re.search(
                r'_add\("([^"]+)",\s*Color8\((\d+),\s*(\d+),\s*(\d+)\)',
                line
            )
            if m:
                name = m.group(1)
                r, g, b = int(m.group(2)), int(m.group(3)), int(m.group(4))
                api_name = "color_" + name.lower().replace(" ", "_")
                colors[api_name] = {"name": name, "rgb": (r, g, b)}
    return colors


def make_color_icon(color: tuple) -> Image.Image:
    """Create a color achievement icon: glowing circle on dark bg. All work in RGBA, convert at end."""
    r, g, b = color
    img = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (*BG_COLOR, 255))
    cx, cy = ICON_SIZE // 2, ICON_SIZE // 2
    radius = 70

    # Soft glow: draw a big blurred circle behind
    glow = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_r = radius + 40
    glow_draw.ellipse(
        [cx - glow_r, cy - glow_r, cx + glow_r, cy + glow_r],
        fill=(r, g, b, 100)
    )
    glow = glow.filter(ImageFilter.GaussianBlur(radius=30))
    img = Image.alpha_composite(img, glow)

    # Main circle
    draw = ImageDraw.Draw(img)
    # Dark ring
    draw.ellipse(
        [cx - radius - 2, cy - radius - 2, cx + radius + 2, cy + radius + 2],
        fill=(max(0, r - 40), max(0, g - 40), max(0, b - 40), 255)
    )
    # Fill
    draw.ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius],
        fill=(r, g, b, 255)
    )
    # Highlight spot
    hl_r = radius // 3
    hx, hy = cx - radius // 4, cy - radius // 4
    highlight = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    hl_draw = ImageDraw.Draw(highlight)
    hl_draw.ellipse([hx - hl_r, hy - hl_r, hx + hl_r, hy + hl_r],
                     fill=(255, 255, 255, 60))
    highlight = highlight.filter(ImageFilter.GaussianBlur(radius=8))
    img = Image.alpha_composite(img, highlight)

    return img.convert("RGB")


def make_gameplay_icon(icon_type: str, color: tuple) -> Image.Image:
    """Create a gameplay achievement icon."""
    img = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (*BG_COLOR, 255))
    draw = ImageDraw.Draw(img)
    cx, cy = ICON_SIZE // 2, ICON_SIZE // 2
    r, g, b = color

    if icon_type == "star":
        points = []
        for i in range(10):
            angle = math.radians(i * 36 - 90)
            rad = 80 if i % 2 == 0 else 35
            points.append((cx + rad * math.cos(angle), cy + rad * math.sin(angle)))
        draw.polygon(points, fill=(r, g, b, 255))

    elif icon_type == "diamond":
        size = 75
        points = [(cx, cy - size), (cx + size, cy), (cx, cy + size), (cx - size, cy)]
        draw.polygon(points, fill=(r, g, b, 255))

    elif icon_type == "grid":
        size = 18
        spacing = 48
        start_x = cx - int(spacing * 1.5)
        start_y = cy - spacing
        count = 0
        for row in range(3):
            for col in range(4):
                if count >= 10:
                    break
                x = start_x + col * spacing
                y = start_y + row * spacing
                draw.ellipse([x - size, y - size, x + size, y + size], fill=(r, g, b, 255))
                count += 1

    elif icon_type == "coins":
        for i in range(4):
            y_off = 30 - i * 20
            fill_c = (max(0, r - i * 15), max(0, g - i * 15), max(0, b - i * 15), 255)
            outline_c = (min(255, r + 30), min(255, g + 30), min(255, b + 30), 255)
            draw.ellipse(
                [cx - 60, cy + y_off - 15, cx + 60, cy + y_off + 15],
                fill=fill_c, outline=outline_c, width=2
            )

    elif icon_type == "rainbow":
        palette = [
            (255, 0, 0), (255, 128, 0), (255, 255, 0),
            (0, 255, 0), (0, 128, 255), (128, 0, 255)
        ]
        for i, c in enumerate(palette):
            angle = math.radians(i * 60 - 90)
            x = int(cx + 55 * math.cos(angle))
            y = int(cy + 55 * math.sin(angle))
            draw.ellipse([x - 28, y - 28, x + 28, y + 28], fill=(*c, 255))
        draw.ellipse([cx - 22, cy - 22, cx + 22, cy + 22], fill=(255, 255, 255, 255))

    return img.convert("RGB")


def to_grayscale(img: Image.Image) -> Image.Image:
    """Convert to dark grayscale for unachieved icon."""
    gray = img.convert("L").convert("RGB")
    return ImageEnhance.Brightness(gray).enhance(0.5)


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    palette_path = os.path.join(
        os.path.dirname(__file__), "..", "scripts", "autoloads", "color_palette.gd"
    )
    colors = parse_colors_from_gdscript(palette_path)
    print(f"Parsed {len(colors)} colors from color_palette.gd")

    gameplay = {
        "all_colors": {"icon": "rainbow", "color": (255, 255, 255)},
        "first_color": {"icon": "star", "color": (100, 170, 255)},
        "ten_colors": {"icon": "star", "color": (100, 200, 100)},
        "fifty_colors": {"icon": "star", "color": (200, 170, 50)},
        "hundred_colors": {"icon": "star", "color": (200, 100, 255)},
        "tier_5": {"icon": "diamond", "color": (180, 100, 255)},
        "ten_nodes": {"icon": "grid", "color": (100, 170, 255)},
        "rich": {"icon": "coins", "color": (255, 215, 0)},
    }

    total = len(colors) + len(gameplay)
    generated = 0

    for api_name, data in colors.items():
        img = make_color_icon(data["rgb"])
        img.save(os.path.join(OUTPUT_DIR, f"{api_name}.jpg"), "JPEG", quality=95)
        to_grayscale(img).save(os.path.join(OUTPUT_DIR, f"{api_name}_gray.jpg"), "JPEG", quality=95)
        generated += 1
        if generated % 50 == 0:
            print(f"  [{generated}/{total}] generated...")

    for api_name, data in gameplay.items():
        img = make_gameplay_icon(data["icon"], data["color"])
        img.save(os.path.join(OUTPUT_DIR, f"{api_name}.jpg"), "JPEG", quality=95)
        to_grayscale(img).save(os.path.join(OUTPUT_DIR, f"{api_name}_gray.jpg"), "JPEG", quality=95)
        generated += 1

    print(f"\nDone! {generated * 2} icons in {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
