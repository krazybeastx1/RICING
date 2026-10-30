#!/usr/bin/env python3
"""Build the Plymouth boot theme assets (background, logo, progress pip)."""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
TOKENS = json.loads((ROOT / "design" / "tokens.json").read_text(encoding="utf-8"))
C = TOKENS["colors"]
OUT = ROOT / "plymouth" / "NightCity-Plymouth"
W, H = 1920, 1080


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)

    # Background: vertical graphite gradient, faint horizon glow, scanlines.
    bg = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(bg)
    top, bottom = (8, 9, 13), (16, 18, 24)
    for y in range(H):
        t = y / (H - 1)
        col = lerp(top, bottom, t)
        d.line([(0, y), (W, y)], fill=col)

    glow = Image.new("RGB", (W, H), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([W // 2 - 640, H // 2 - 360, W // 2 + 640, H // 2 + 360],
               fill=(70, 8, 22))
    bg = Image.blend(bg, Image.blend(bg, glow, 0.55), 0.6)

    # faint perspective floor lines
    grid = Image.new("RGB", (W, H), (0, 0, 0))
    gd = ImageDraw.Draw(grid)
    for i in range(-16, 17):
        x = W // 2 + i * 120
        gd.line([(W // 2, int(H * 0.62)), (x * 3, H)], fill=(40, 5, 14), width=2)
    for i in range(1, 14):
        y = int(H * 0.62 + (H * 0.38) * (i / 13) ** 2.4)
        gd.line([(0, y), (W, y)], fill=(40, 5, 14), width=2)
    bg = Image.blend(bg, Image.blend(bg, grid, 0.5), 0.35)

    # scanlines
    sl = Image.new("RGB", (W, H), (0, 0, 0))
    sd = ImageDraw.Draw(sl)
    for y in range(0, H, 4):
        sd.line([(0, y), (W, y)], fill=(4, 4, 6))
    bg = Image.blend(bg, Image.blend(bg, sl, 0.5), 0.35)
    bg.save(OUT / "background.png", optimize=True)

    # Logo: mark + wordmark drawn with the bundled fonts.
    mark = Image.open(ROOT / "assets" / "branding" / "nightcity-mark.png").convert("RGBA")
    target = 300
    mark = mark.resize((target, int(mark.height * target / mark.width)), Image.LANCZOS)

    logo = Image.new("RGBA", (W, 420), (0, 0, 0, 0))
    lx = (W - mark.width) // 2
    logo.alpha_composite(mark, (lx, 20))

    from PIL import ImageFont
    f_brand = ImageFont.truetype(str(ROOT / "assets" / "fonts" / "Orbitron" / "Orbitron-Variable.ttf"), 74)
    f_sub = ImageFont.truetype(str(ROOT / "assets" / "fonts" / "Rajdhani" / "Rajdhani-SemiBold.ttf"), 32)
    ld = ImageDraw.Draw(logo)
    text = "NIGHT CITY"
    tracking = 18
    widths = [ld.textlength(ch, font=f_brand) for ch in text]
    total = sum(widths) + tracking * (len(text) - 1)
    x = (W - total) / 2
    y = 330
    for ch, w in zip(text, widths):
        ld.text((x, y), ch, font=f_brand, fill=(232, 234, 240, 255))
        x += w + tracking
    sub = "BEYOND THE SYSTEM. INTO THE CITY."
    sw = ld.textlength(sub, font=f_sub)
    ld.text(((W - sw) / 2, y + 90), sub, font=f_sub, fill=(146, 153, 168, 255))
    logo.save(OUT / "logo.png", optimize=True)

    # Progress track + pip
    track = Image.new("RGBA", (1200, 4), (0, 0, 0, 0))
    td = ImageDraw.Draw(track)
    td.rectangle([0, 0, 1200, 4], fill=(52, 59, 73, 210))
    track.save(OUT / "progress-track.png")

    pip = Image.new("RGBA", (220, 4), (0, 0, 0, 0))
    pd = ImageDraw.Draw(pip)
    for x in range(220):
        t = x / 219
        col = lerp((140, 16, 43), (255, 23, 68), min(1, t * 1.6))
        pd.line([(x, 0), (x, 4)], fill=col + (255,))
    pip.save(OUT / "progress-pip.png")

    print("plymouth  background.png, logo.png, progress-track.png, progress-pip.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
