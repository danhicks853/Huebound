"""
Generate Steam Library assets for Huebound.

Library Capsule: 600x900 (PNG)
Library Header: 920x430 (PNG)
Library Hero: 3840x1240 (PNG, NO text/logos)
Library Logo: 1280x720 max, transparent PNG with logo only

Output: steam/library_assets/
"""

import os
import math
import random
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT_PATH = "C:/Windows/Fonts/segoeui.ttf"
FONT_BOLD_PATH = "C:/Windows/Fonts/segoeuib.ttf"
BG_COLOR = (12, 12, 20)
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "library_assets")

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


def draw_glow_circle(img, x, y, radius, color, alpha=100):
    """Draw a glowing circle on an RGBA image."""
    r, g, b = color
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    gr = radius + int(radius * 0.6)
    draw.ellipse([x - gr, y - gr, x + gr, y + gr], fill=(r, g, b, alpha // 2))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=max(1, radius // 2)))
    img = Image.alpha_composite(img, glow)
    core = Image.new("RGBA", img.size, (0, 0, 0, 0))
    core_draw = ImageDraw.Draw(core)
    core_draw.ellipse([x - radius, y - radius, x + radius, y + radius],
                       fill=(r, g, b, 220))
    hr = radius // 3
    hx, hy = x - radius // 4, y - radius // 4
    core_draw.ellipse([hx - hr, hy - hr, hx + hr, hy + hr],
                       fill=(min(255, r + 80), min(255, g + 80), min(255, b + 80), 100))
    img = Image.alpha_composite(img, core)
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

    # Connection lines
    line_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(line_layer)
    max_dist = min(w, h) * 0.3
    for i in range(len(points)):
        for j in range(i + 1, len(points)):
            dist = math.hypot(points[i][0] - points[j][0], points[i][1] - points[j][1])
            if dist < max_dist:
                draw.line([(points[i][0], points[i][1]), (points[j][0], points[j][1])],
                          fill=(60, 60, 80, 50), width=2)
    img = Image.alpha_composite(img, line_layer)

    # Circles
    for x, y, radius in points:
        color = random.choice(PALETTE)
        img = draw_glow_circle(img, x, y, radius, color, alpha=random.randint(60, 140))

    return img


def draw_title_on_image(img, text, font_size, y_pos=None, subtitle=None, sub_size=None):
    """Draw centered title text with glow."""
    w, h = img.size
    try:
        font = ImageFont.truetype(FONT_BOLD_PATH, font_size)
    except:
        font = ImageFont.truetype(FONT_PATH, font_size)

    draw = ImageDraw.Draw(img)
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (w - tw) // 2
    ty = y_pos if y_pos is not None else (h - th) // 2

    # Glow
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).text((tx, ty), text, font=font, fill=(200, 200, 255, 120))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=10))
    img = Image.alpha_composite(img, glow)

    # Text
    text_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(text_layer).text((tx, ty), text, font=font, fill=(255, 255, 255, 255))
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
        sty = ty + th + int(sub_size * 0.6)
        sub_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(sub_layer).text((stx, sty), subtitle, font=sub_font,
                                        fill=(180, 180, 200, 200))
        img = Image.alpha_composite(img, sub_layer)

    return img


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # ── Library Capsule 600x900 ──
    # Key art + logo, graphically-centric
    print("Generating library assets...")

    random.seed(42)
    img = Image.new("RGBA", (600, 900), (*BG_COLOR, 255))
    img = scatter_with_connections(img, 30, 10, 40, margin=15)
    img = draw_title_on_image(img, "HUEBOUND", 64, y_pos=380)
    img.convert("RGB").save(os.path.join(OUTPUT_DIR, "library_capsule_600x900.png"), "PNG")
    print("  library_capsule_600x900.png")

    # ── Library Header 920x430 ──
    # Branding focused, logo legible
    random.seed(42)
    img = Image.new("RGBA", (920, 430), (*BG_COLOR, 255))
    img = scatter_with_connections(img, 25, 10, 35, margin=10)
    img = draw_title_on_image(img, "HUEBOUND", 80, y_pos=140)
    img.convert("RGB").save(os.path.join(OUTPUT_DIR, "library_header_920x430.png"), "PNG")
    print("  library_header_920x430.png")

    # ── Library Hero 3840x1240 ──
    # NO text, NO logos. Just artwork. Safe area 860x380 centered.
    random.seed(55)
    img = Image.new("RGBA", (3840, 1240), (*BG_COLOR, 255))
    img = scatter_with_connections(img, 100, 20, 90, margin=30)
    img.convert("RGB").save(os.path.join(OUTPUT_DIR, "library_hero_3840x1240.png"), "PNG")
    print("  library_hero_3840x1240.png")

    # ── Library Logo (transparent, 1280 wide or 720 tall) ──
    # Transparent PNG, logo only, with drop shadow for legibility
    width, height = 1280, 360  # wide format, fits 1280 width requirement
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))

    font_size = 180
    try:
        font = ImageFont.truetype(FONT_BOLD_PATH, font_size)
    except:
        font = ImageFont.truetype(FONT_PATH, font_size)

    draw = ImageDraw.Draw(img)
    bbox = draw.textbbox((0, 0), "HUEBOUND", font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (width - tw) // 2
    ty = (height - th) // 2

    # Drop shadow for legibility against hero
    shadow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((tx + 3, ty + 3), "HUEBOUND", font=font,
                                 fill=(0, 0, 0, 160))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=6))
    img = Image.alpha_composite(img, shadow)

    # Subtle color glow behind text
    glow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    ImageDraw.Draw(glow).text((tx, ty), "HUEBOUND", font=font,
                               fill=(100, 120, 255, 80))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=12))
    img = Image.alpha_composite(img, glow)

    # Main white text
    text_layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    ImageDraw.Draw(text_layer).text((tx, ty), "HUEBOUND", font=font,
                                     fill=(255, 255, 255, 255))
    img = Image.alpha_composite(img, text_layer)

    img.save(os.path.join(OUTPUT_DIR, "library_logo_1280x360.png"), "PNG")
    print("  library_logo_1280x360.png")

    print(f"\nDone! All library assets saved to {OUTPUT_DIR}")
    print("\nUpload guide:")
    print("  Library Capsule  -> library_capsule_600x900.png")
    print("  Library Header   -> library_header_920x430.png")
    print("  Library Hero     -> library_hero_3840x1240.png (NO text)")
    print("  Library Logo     -> library_logo_1280x360.png (transparent, position bottom-left)")


if __name__ == "__main__":
    main()
