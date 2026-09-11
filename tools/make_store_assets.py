"""Derive every store/launcher asset from branding/coachlyjo-icon-1024.png.

Run from repo root:  python tools/make_store_assets.py

Outputs (all under branding/generated/):
  icon-ios-1024.png          opaque 1024x1024 (Apple rejects icons with alpha)
  adaptive-foreground.png    1024x1024 transparent: only the white/black marks,
                             scaled to sit inside Android's 66% safe zone
  adaptive-background.png    1024x1024 full-bleed brand gradient
  play-icon-512.png          512x512 full-bleed (Play applies its own mask)
  feature-graphic-1024x500.png  Play Store feature graphic

The foreground is extracted by treating low-saturation pixels (white ring, dot,
dark "JO" badge) as the mark and the saturated gradient as transparent, so the
gradient background can show through the launcher's circle/squircle mask.
"""
import colorsys
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "branding", "coachlyjo-icon-1024.png")
OUT = os.path.join(ROOT, "branding", "generated")
GRAD_START = (0xF2, 0x0F, 0xB6)  # #F20FB6 top-left
GRAD_END = (0xFF, 0x77, 0x0F)    # #FF770F bottom-right
SIZE = 1024


def gradient(w, h):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = (x / (w - 1) + y / (h - 1)) / 2
            px[x, y] = tuple(int(a + (b - a) * t) for a, b in zip(GRAD_START, GRAD_END))
    return img


def extract_marks(icon):
    """Keep only unsaturated pixels (white/black marks); make the gradient transparent."""
    icon = icon.convert("RGBA")
    out = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    src, dst = icon.load(), out.load()
    for y in range(icon.height):
        for x in range(icon.width):
            r, g, b, a = src[x, y]
            if a == 0:
                continue
            _, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if v < 0.3:
                s = 0.0  # HSV saturation is noise on near-black pixels (the "JO" badge)
            # ramp: s<=0.2 fully kept, s>=0.6 fully dropped (anti-aliased edges in between)
            keep = max(0.0, min(1.0, (0.6 - s) / 0.4))
            if keep > 0:
                # snap near-white / near-black so edge pixels don't tint pink
                col = (255, 255, 255) if v > 0.5 else (0x1E, 0x1E, 0x1E)
                dst[x, y] = (*col, int(a * keep))
    return out


def main():
    if not os.path.exists(SRC):
        sys.exit(f"missing {SRC}")
    os.makedirs(OUT, exist_ok=True)
    icon = Image.open(SRC).convert("RGBA")
    bg = gradient(SIZE, SIZE)

    # iOS: flatten onto the gradient so the rounded corners become opaque.
    ios = bg.copy()
    ios.paste(icon, (0, 0), icon)
    ios.save(os.path.join(OUT, "icon-ios-1024.png"))

    # Android adaptive layers.
    marks = extract_marks(icon)
    bbox = marks.getbbox()
    marks = marks.crop(bbox)
    # Fit the marks inside the 66% safe zone with a little breathing room.
    target = int(SIZE * 0.58)
    scale = target / max(marks.size)
    marks = marks.resize((int(marks.width * scale), int(marks.height * scale)), Image.LANCZOS)
    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    fg.paste(marks, ((SIZE - marks.width) // 2, (SIZE - marks.height) // 2), marks)
    fg.save(os.path.join(OUT, "adaptive-foreground.png"))
    bg.save(os.path.join(OUT, "adaptive-background.png"))

    # Play listing icon: full-bleed composite, 512x512.
    play = bg.copy().convert("RGBA")
    play.paste(fg, (0, 0), fg)
    play.convert("RGB").resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, "play-icon-512.png"))

    # Feature graphic 1024x500.
    feat = gradient(1024, 500).convert("RGBA")
    badge = ios.resize((300, 300), Image.LANCZOS)
    mask = Image.new("L", (300, 300), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 299, 299), radius=66, fill=255)
    feat.paste(badge, (90, 100), mask)
    draw = ImageDraw.Draw(feat)
    font_path = next((p for p in [r"C:\Windows\Fonts\segoeuib.ttf", r"C:\Windows\Fonts\arialbd.ttf",
                                  "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
                                  "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]
                      if os.path.exists(p)), None)
    title = ImageFont.truetype(font_path, 110) if font_path else ImageFont.load_default()
    sub = ImageFont.truetype(font_path, 44) if font_path else ImageFont.load_default()
    draw.text((440, 150), "CoachlyJo", font=title, fill=(255, 255, 255))
    draw.text((444, 290), "Fitness coaching in Jordan", font=sub, fill=(255, 255, 255, 230))
    feat.convert("RGB").save(os.path.join(OUT, "feature-graphic-1024x500.png"))

    for f in sorted(os.listdir(OUT)):
        im = Image.open(os.path.join(OUT, f))
        print(f"{f:32s} {im.size[0]}x{im.size[1]} {im.mode}")


if __name__ == "__main__":
    main()
