"""
Generate all Steam store page assets for Huebound.

Aesthetic: Dark background with scattered glowing colored circles,
matching the game's procedural/geometric look. Title text "HUEBOUND"
rendered in clean white with a subtle glow.

Output: steam/store_assets/
"""

import os
import math
import random
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageEnhance

FONT_PATH = "C:/Windows/Fonts/segoeui.ttf"
FONT_BOLD_PATH = "C:/Windows/Fonts/segoeuib.ttf"
BG_COLOR = (12, 12, 20)
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "store_assets")

# Representative colors from the game palette
PALETTE = [
    (255, 0, 0), (0, 0, 255), (255, 255, 0),
    (128, 0, 128), (255, 128, 0), (128, 255, 0),
    (0, 255, 255), (255, 0, 192), (128, 0, 255),
    (0, 128, 255), (255, 215, 0), (0, 192, 64),
    (220, 20, 60), (64, 224, 208), (192, 128, 255),
    (255, 96, 64), (0, 128, 128), (200, 170, 50),
    (120, 40, 180), (100, 255, 180), (255, 80, 0),
    (138, 7, 7), (200, 60, 100), (60, 200, 255),
]

random.seed(42)  # Reproducible layouts


def draw_glow_circle(img, x, y, radius, color, alpha=100):
    """Draw a glowing circle on an RGBA image."""
    r, g, b = color
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    # Outer glow
    gr = radius + int(radius * 0.6)
    draw.ellipse([x - gr, y - gr, x + gr, y + gr], fill=(r, g, b, alpha // 2))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=radius // 2))
    img_out = Image.alpha_composite(img, glow)
    # Core circle
    core = Image.new("RGBA", img.size, (0, 0, 0, 0))
    core_draw = ImageDraw.Draw(core)
    core_draw.ellipse([x - radius, y - radius, x + radius, y + radius],
                       fill=(r, g, b, 220))
    # Highlight
    hr = radius // 3
    hx, hy = x - radius // 4, y - radius // 4
    core_draw.ellipse([hx - hr, hy - hr, hx + hr, hy + hr],
                       fill=(min(255, r + 80), min(255, g + 80), min(255, b + 80), 100))
    img_out = Image.alpha_composite(img_out, core)
    return img_out


def scatter_circles(img, count, min_r, max_r, margin=0):
    """Scatter random glowing circles across the image."""
    w, h = img.size
    for _ in range(count):
        color = random.choice(PALETTE)
        radius = random.randint(min_r, max_r)
        x = random.randint(margin + radius, w - margin - radius)
        y = random.randint(margin + radius, h - margin - radius)
        img = draw_glow_circle(img, x, y, radius, color, alpha=random.randint(60, 140))
    return img


def draw_connection_lines(img, points, color=(40, 40, 60)):
    """Draw subtle connection lines between some circle centers."""
    draw = ImageDraw.Draw(img)
    for i in range(len(points)):
        for j in range(i + 1, len(points)):
            dist = math.hypot(points[i][0] - points[j][0], points[i][1] - points[j][1])
            if dist < 300:
                draw.line([points[i], points[j]], fill=(*color, 40), width=1)
    return img


def scatter_with_connections(img, count, min_r, max_r, margin=0):
    """Scatter circles and draw connection lines between nearby ones."""
    w, h = img.size
    points = []
    for _ in range(count):
        radius = random.randint(min_r, max_r)
        x = random.randint(margin + radius, w - margin - radius)
        y = random.randint(margin + radius, h - margin - radius)
        points.append((x, y, radius))

    # Draw connection lines first (behind circles)
    line_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(line_layer)
    for i in range(len(points)):
        for j in range(i + 1, len(points)):
            dist = math.hypot(points[i][0] - points[j][0], points[i][1] - points[j][1])
            if dist < 350:
                draw.line([(points[i][0], points[i][1]), (points[j][0], points[j][1])],
                          fill=(60, 60, 80, 50), width=2)
    img = Image.alpha_composite(img, line_layer)

    # Draw circles
    for x, y, radius in points:
        color = random.choice(PALETTE)
        img = draw_glow_circle(img, x, y, radius, color, alpha=random.randint(60, 140))

    return img, points


def draw_title(img, text, font_size, y_pos=None, subtitle=None, sub_size=None):
    """Draw centered title text with a glow effect."""
    draw = ImageDraw.Draw(img)
    w, h = img.size

    try:
        font = ImageFont.truetype(FONT_BOLD_PATH, font_size)
    except:
        font = ImageFont.truetype(FONT_PATH, font_size)

    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (w - tw) // 2
    ty = y_pos if y_pos is not None else (h - th) // 2

    # Text glow
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.text((tx, ty), text, font=font, fill=(200, 200, 255, 120))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=10))
    img = Image.alpha_composite(img, glow)

    # Main text
    text_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    text_draw = ImageDraw.Draw(text_layer)
    text_draw.text((tx, ty), text, font=font, fill=(255, 255, 255, 255))
    img = Image.alpha_composite(img, text_layer)

    # Subtitle
    if subtitle and sub_size:
        try:
            sub_font = ImageFont.truetype(FONT_PATH, sub_size)
        except:
            sub_font = ImageFont.load_default()
        sub_bbox = draw.textbbox((0, 0), subtitle, font=sub_font)
        stw = sub_bbox[2] - sub_bbox[0]
        stx = (w - stw) // 2
        sty = ty + th + int(sub_size * 0.5)
        sub_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        sub_draw = ImageDraw.Draw(sub_layer)
        sub_draw.text((stx, sty), subtitle, font=sub_font, fill=(180, 180, 200, 200))
        img = Image.alpha_composite(img, sub_layer)

    return img


def make_capsule(width, height, title_size, circle_count, circle_min_r, circle_max_r,
                 subtitle=None, sub_size=None, title_y_ratio=None):
    """Generic capsule generator."""
    random.seed(42)
    img = Image.new("RGBA", (width, height), (*BG_COLOR, 255))
    img, _ = scatter_with_connections(img, circle_count, circle_min_r, circle_max_r, margin=10)
    if title_size > 0:
        y_pos = int(height * title_y_ratio) if title_y_ratio else None
        img = draw_title(img, "HUEBOUND", title_size, y_pos=y_pos,
                         subtitle=subtitle, sub_size=sub_size)
    return img.convert("RGB")


def make_logo(width, height):
    """Transparent logo - just the title text on transparent background."""
    random.seed(42)
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))

    font_size = height // 3
    try:
        font = ImageFont.truetype(FONT_BOLD_PATH, font_size)
    except:
        font = ImageFont.truetype(FONT_PATH, font_size)

    draw = ImageDraw.Draw(img)
    bbox = draw.textbbox((0, 0), "HUEBOUND", font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (width - tw) // 2
    ty = (height - th) // 2

    # Glow
    glow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.text((tx, ty), "HUEBOUND", font=font, fill=(150, 150, 255, 80))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=8))
    img = Image.alpha_composite(img, glow)

    # Text
    text_layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    text_draw = ImageDraw.Draw(text_layer)
    text_draw.text((tx, ty), "HUEBOUND", font=font, fill=(255, 255, 255, 255))
    img = Image.alpha_composite(img, text_layer)

    return img


def make_screenshot(width, height, seed, density="normal"):
    """Generate a fake screenshot showing a factory-like layout."""
    random.seed(seed)
    img = Image.new("RGBA", (width, height), (*BG_COLOR, 255))

    if density == "dense":
        count, min_r, max_r = 60, 12, 40
    elif density == "sparse":
        count, min_r, max_r = 20, 20, 50
    else:
        count, min_r, max_r = 35, 15, 45

    img, points = scatter_with_connections(img, count, min_r, max_r, margin=30)

    # Add some UI-like elements at the top
    ui_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ui_draw = ImageDraw.Draw(ui_layer)

    # Top bar
    ui_draw.rectangle([0, 0, width, 40], fill=(20, 20, 30, 180))

    try:
        ui_font = ImageFont.truetype(FONT_PATH, 18)
    except:
        ui_font = ImageFont.load_default()

    # Currency display
    currency = random.randint(500, 50000)
    ui_draw.text((15, 10), f"Light: {currency:,}", font=ui_font, fill=(255, 215, 0, 220))

    # Collection counter
    discovered = random.randint(30, 200)
    ui_draw.text((width - 200, 10), f"Collection: {discovered}/256", font=ui_font,
                 fill=(180, 180, 200, 220))

    # CPS
    cps = random.randint(10, 500)
    ui_draw.text((width // 2 - 40, 10), f"{cps} Light/s", font=ui_font,
                 fill=(200, 200, 200, 180))

    img = Image.alpha_composite(img, ui_layer)

    # Bottom bar with node buttons
    bottom = Image.new("RGBA", img.size, (0, 0, 0, 0))
    bottom_draw = ImageDraw.Draw(bottom)
    bottom_draw.rectangle([0, height - 50, width, height], fill=(20, 20, 30, 180))

    node_types = ["Source", "Combiner", "Splitter", "Seller", "Shop", "Collection"]
    btn_w = 120
    start_x = (width - len(node_types) * btn_w) // 2
    for i, label in enumerate(node_types):
        bx = start_x + i * btn_w
        bottom_draw.rounded_rectangle([bx, height - 45, bx + btn_w - 10, height - 8],
                                       radius=5, fill=(40, 40, 55, 200))
        bottom_draw.text((bx + 10, height - 40), label, font=ui_font,
                         fill=(180, 180, 200, 220))

    img = Image.alpha_composite(img, bottom)

    return img.convert("RGB")


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("Generating store capsule images...")

    # Header Capsule 920x430 - required
    img = make_capsule(920, 430, 80, 25, 10, 35,
                       subtitle="Mix colors. Build factories. Discover 256 hues.",
                       sub_size=20, title_y_ratio=0.3)
    img.save(os.path.join(OUTPUT_DIR, "header_capsule_920x430.jpg"), "JPEG", quality=95)
    print("  header_capsule_920x430.jpg")

    # Small Capsule 462x174 - required (logo should nearly fill it)
    img = make_capsule(462, 174, 60, 10, 6, 18, title_y_ratio=0.15)
    img.save(os.path.join(OUTPUT_DIR, "small_capsule_462x174.jpg"), "JPEG", quality=95)
    print("  small_capsule_462x174.jpg")

    # Main Capsule 1232x706 - required
    img = make_capsule(1232, 706, 120, 40, 15, 50,
                       title_y_ratio=0.3)
    img.save(os.path.join(OUTPUT_DIR, "main_capsule_1232x706.jpg"), "JPEG", quality=95)
    print("  main_capsule_1232x706.jpg")

    # Vertical Capsule 748x896 - required
    img = make_capsule(748, 896, 72, 35, 12, 40,
                       title_y_ratio=0.4)
    img.save(os.path.join(OUTPUT_DIR, "vertical_capsule_748x896.jpg"), "JPEG", quality=95)
    print("  vertical_capsule_748x896.jpg")

    # Hero Graphic 3840x1240 - required
    img = make_capsule(3840, 1240, 160, 80, 20, 80,
                       subtitle="Mix colors. Build factories. Discover 256 hues.",
                       sub_size=40, title_y_ratio=0.35)
    img.save(os.path.join(OUTPUT_DIR, "hero_3840x1240.jpg"), "JPEG", quality=95)
    print("  hero_3840x1240.jpg")

    # Logo (transparent PNG, ~940x400)
    logo = make_logo(940, 400)
    logo.save(os.path.join(OUTPUT_DIR, "logo_940x400.png"), "PNG")
    print("  logo_940x400.png")

    # Page Background 1438x810 - ambient, low contrast
    random.seed(77)
    img = make_capsule(1438, 810, 0, 50, 15, 50)
    img.save(os.path.join(OUTPUT_DIR, "page_background_1438x810.jpg"), "JPEG", quality=95)
    print("  page_background_1438x810.jpg")

    # Library Capsule 600x900 - recommended
    img = make_capsule(600, 900, 56, 30, 10, 35,
                       title_y_ratio=0.4)
    img.save(os.path.join(OUTPUT_DIR, "library_capsule_600x900.jpg"), "JPEG", quality=95)
    print("  library_capsule_600x900.jpg")

    # Library Hero 3840x1240 - recommended (no text)
    random.seed(99)
    img = make_capsule(3840, 1240, 0, 80, 20, 80)
    img.save(os.path.join(OUTPUT_DIR, "library_hero_3840x1240.jpg"), "JPEG", quality=95)
    print("  library_hero_3840x1240.jpg")

    # Screenshots (1920x1080, need at least 5)
    print("\nGenerating screenshots...")
    screenshot_configs = [
        (100, "normal", "Early game - first connections"),
        (200, "sparse", "Building a simple factory"),
        (300, "dense", "Complex color mixing network"),
        (400, "normal", "Mid-game factory expansion"),
        (500, "dense", "Late game - hunting rare colors"),
    ]
    for i, (seed, density, desc) in enumerate(screenshot_configs, 1):
        img = make_screenshot(1920, 1080, seed, density)
        fname = f"screenshot_{i}.jpg"
        img.save(os.path.join(OUTPUT_DIR, fname), "JPEG", quality=95)
        print(f"  {fname} - {desc}")

    print(f"\nDone! All assets saved to {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
