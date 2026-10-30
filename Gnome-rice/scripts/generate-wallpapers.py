#!/usr/bin/env python3
"""Generate the six original NIGHT CITY 4K wallpapers.

Everything is drawn procedurally from design/tokens.json, so the set can be
rebuilt reproducibly and carries no third-party artwork. Deterministic seeds
mean the same version always produces byte-similar output.

Usage:
  python3 scripts/generate-wallpapers.py [--width 3840] [--height 2160]
"""
from __future__ import annotations

import argparse
import json
import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
TOKENS = json.loads((ROOT / "design" / "tokens.json").read_text(encoding="utf-8"))
C = TOKENS["colors"]
FONTS = ROOT / "assets" / "fonts"
OUT = ROOT / "assets" / "wallpapers"

W, H = 3840, 2160


def font(family: str, size: int) -> ImageFont.FreeTypeFont:
    table = {
        "orbitron": FONTS / "Orbitron" / "Orbitron-Variable.ttf",
        "rajdhani": FONTS / "Rajdhani" / "Rajdhani-SemiBold.ttf",
        "rajdhani-bold": FONTS / "Rajdhani" / "Rajdhani-Bold.ttf",
        "mono": FONTS / "JetBrainsMono" / "JetBrainsMono-Variable.ttf",
    }
    return ImageFont.truetype(str(table[family]), size)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vertical_gradient(size, stops):
    """stops: list of (position 0..1, (r,g,b))"""
    w, h = size
    img = Image.new("RGB", size)
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if p0 <= t <= p1:
                f = (t - p0) / (p1 - p0) if p1 > p0 else 0
                px_col = lerp(c0, c1, f)
                break
        else:
            px_col = stops[-1][1]
        for x in range(w):
            px[x, y] = px_col
    return img


def fast_gradient(size, stops):
    """Same as vertical_gradient but only paints full rows via paste."""
    w, h = size
    img = Image.new("RGB", size)
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        col = stops[-1][1]
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if p0 <= t <= p1:
                f = (t - p0) / (p1 - p0) if p1 > p0 else 0
                col = lerp(c0, c1, f)
                break
        d.line([(0, y), (w, y)], fill=col)
    return img


def radial_glow(size, center, radius, color, strength=1.0):
    """Soft radial light on black, size = (w, h)."""
    w, h = size
    small = (max(1, w // 4), max(1, h // 4))
    layer = Image.new("RGB", small, (0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = center[0] / 4, center[1] / 4
    r = radius / 4
    steps = 18
    for i in range(steps, 0, -1):
        t = i / steps
        rr = r * t
        col = tuple(round(c * strength * (1 - t) ** 1.7) for c in color)
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=col)
    return layer.resize(size, Image.LANCZOS).filter(ImageFilter.GaussianBlur(radius / 12))


def screen(base, layer):
    return ImageChops.screen(base, layer)


def add(a, b):
    return ImageChops.add(a, b)


def grain(img, amount=5, seed=0):
    rnd = random.Random(seed)
    w, h = img.size
    small = Image.new("L", (w // 3, h // 3))
    small.putdata([128 + rnd.randint(-amount, amount) for _ in range((w // 3) * (h // 3))])
    noise = small.resize((w, h), Image.BILINEAR).convert("RGB")
    return Image.blend(img, ImageChops.overlay(img, noise), 0.10)


def scanlines(img, spacing=6, strength=10):
    w, h = img.size
    overlay = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(overlay)
    for y in range(0, h, spacing):
        d.line([(0, y), (w, y)], fill=(strength, strength, strength))
    return ImageChops.subtract(img, overlay)


def vignette(img, power=1.6, strength=0.65):
    w, h = img.size
    small = (w // 8, h // 8)
    mask = Image.new("L", small, 0)
    d = ImageDraw.Draw(mask)
    cx, cy = small[0] / 2, small[1] / 2
    maxd = math.hypot(cx, cy)
    # concentric ellipses, brightest in the middle
    steps = 48
    for i in range(steps, 0, -1):
        t = i / steps
        r = maxd * t
        v = round(255 * (1 - strength * (t ** power)))
        d.ellipse([cx - r, cy - r * 0.72, cx + r, cy + r * 0.72], fill=v)
    mask = mask.resize((w, h), Image.LANCZOS)
    black = Image.new("RGB", (w, h), (0, 0, 0))
    return Image.composite(img, black, mask)


def text_track(draw, xy, text, fnt, fill, tracking=0, anchor="la"):
    """Draw letter-spaced text (Pillow has no tracking)."""
    if len(fill) == 4:
        fill = fill[:3]  # every text_track target is RGB
    if tracking == 0:
        draw.text(xy, text, font=fnt, fill=fill, anchor=anchor)
        return
    x, y = xy
    total = sum(draw.textlength(ch, font=fnt) + tracking for ch in text) - tracking
    if anchor.startswith("m"):
        x -= total / 2
    elif anchor.startswith("r"):
        x -= total
    for ch in text:
        draw.text((x, y), ch, font=fnt, fill=fill, anchor="l" + anchor[1:])
        x += draw.textlength(ch, font=fnt) + tracking


def save(img, name):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    img.convert("RGB").save(path, "PNG", optimize=True)
    print(f"wallpaper  {path.relative_to(ROOT)}  {path.stat().st_size / 1_048_576:.1f} MiB")


# ---------------------------------------------------------------------------
# 01 — NIGHTLINE (skyline)
# ---------------------------------------------------------------------------
def w_nightline(w, h):
    rnd = random.Random(1077)
    img = fast_gradient((w, h), [
        (0.00, (0x08, 0x09, 0x0D)),
        (0.35, (0x10, 0x0C, 0x18)),
        (0.60, (0x2A, 0x0B, 0x18)),
        (0.72, (0x59, 0x0D, 0x24)),
        (0.80, (0x8C, 0x10, 0x2B)),
        (0.84, (0x2A, 0x0B, 0x18)),
        (1.00, (0x08, 0x09, 0x0D)),
    ])

    horizon = int(h * 0.80)
    sun_c = (int(w * 0.62), int(h * 0.72))
    sun_r = int(h * 0.26)
    img = add(img, radial_glow((w, h), sun_c, sun_r * 2.6, (0xFF, 0x17, 0x44), 0.55))

    disc = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(disc)
    d.ellipse([sun_c[0] - sun_r, sun_c[1] - sun_r, sun_c[0] + sun_r, sun_c[1] + sun_r],
              fill=(0xFF, 0x17, 0x44))
    # slice the sun with growing gaps near the bottom
    y = sun_c[1] - sun_r
    gap = 2
    while y < sun_c[1] + sun_r:
        d.rectangle([sun_c[0] - sun_r, y, sun_c[0] + sun_r, y + gap], fill=(0, 0, 0))
        y += gap + 14
        gap = min(34, gap + 2)
    img = add(img, disc.filter(ImageFilter.GaussianBlur(1.2)))

    stars = Image.new("RGB", (w, h), (0, 0, 0))
    sd = ImageDraw.Draw(stars)
    for _ in range(420):
        x = rnd.randrange(w)
        y = rnd.randrange(0, int(h * 0.55))
        v = rnd.choice([40, 60, 90, 130, 180])
        sd.point((x, y), fill=(v, v, min(255, v + 20)))
    img = screen(img, stars.filter(ImageFilter.GaussianBlur(0.6)))

    def skyline(layer_color, base_y, min_h, max_h, alpha_windows):
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        x = -80
        while x < w + 80:
            bw = rnd.randint(int(w * 0.018), int(w * 0.055))
            bh = rnd.randint(min_h, max_h)
            top = base_y - bh
            ld.rectangle([x, top, x + bw, base_y], fill=layer_color)
            # antenna
            if rnd.random() < 0.34:
                ax = x + bw // 2
                ah = rnd.randint(20, 110)
                ld.line([(ax, top), (ax, top - ah)], fill=layer_color, width=3)
            # roof detail
            if rnd.random() < 0.3:
                ld.rectangle([x + bw * 0.2, top - 14, x + bw * 0.8, top], fill=layer_color)
            # windows
            for wy in range(top + 26, base_y - 20, 34):
                for wx in range(int(x + 14), int(x + bw - 14), 26):
                    if rnd.random() < 0.14:
                        col = (0xFF, 0x17, 0x44, alpha_windows) if rnd.random() < 0.72 else (0x00, 0xE5, 0xFF, alpha_windows)
                        ld.rectangle([wx, wy, wx + 7, wy + 9], fill=col)
            x += bw + rnd.randint(6, 34)
        return layer

    for color, base_y, minh, maxh, alpha in [
        ((0x1A, 0x1E, 0x2A, 235), horizon - 40, int(h * 0.10), int(h * 0.24), 90),
        ((0x0F, 0x12, 0x19, 246), horizon, int(h * 0.14), int(h * 0.33), 120),
        ((0x08, 0x09, 0x0D, 255), horizon + 70, int(h * 0.10), int(h * 0.22), 150),
    ]:
        img = Image.alpha_composite(img.convert("RGBA"), skyline(color, base_y, minh, maxh, alpha)).convert("RGB")

    # neon haze on the horizon
    haze = Image.new("RGB", (w, h), (0, 0, 0))
    hd = ImageDraw.Draw(haze)
    hd.rectangle([0, horizon - 8, w, horizon + 7], fill=(0x8C, 0x10, 0x2B))
    img = screen(img, haze.filter(ImageFilter.GaussianBlur(28)))

    # reflective floor
    floor = img.crop((0, horizon - int(h * 0.16), w, horizon)).transpose(Image.FLIP_TOP_BOTTOM)
    floor = floor.filter(ImageFilter.GaussianBlur(7)).resize((w, int(h * 0.20)))
    floor = Image.eval(floor, lambda v: int(v * 0.42))
    img.paste(floor, (0, horizon + 4))

    img = scanlines(img, 5, 8)
    img = vignette(img, 1.8, 0.62)
    img = grain(img, 4, 11)

    d = ImageDraw.Draw(img)
    text_track(d, (170, h - 250), "NIGHT CITY", font("orbitron", 74), (0xE8, 0xEA, 0xF0, 255), 16)
    d.rectangle([170, h - 150, 170 + 760, h - 147], fill=C["neon-red"])
    text_track(d, (170, h - 132), "BEYOND THE SYSTEM. INTO THE CITY.", font("rajdhani", 34), (0x92, 0x99, 0xA8, 255), 7)
    text_track(d, (w - 170, h - 250), "SECTOR 07 // 2077", font("mono", 27), (0x92, 0x99, 0xA8, 220), 2, anchor="ra")
    text_track(d, (w - 170, h - 204), "ALT 0412  //  RAIN 84%", font("mono", 24), (0x92, 0x99, 0xA8, 160), 2, anchor="ra")
    return img


# ---------------------------------------------------------------------------
# 02 — GRID HORIZON
# ---------------------------------------------------------------------------
def w_grid(w, h):
    img = fast_gradient((w, h), [
        (0.00, (0x05, 0x06, 0x0A)),
        (0.40, (0x0B, 0x0E, 0x16)),
        (0.62, (0x1C, 0x0A, 0x18)),
        (0.74, (0x4A, 0x0B, 0x20)),
        (0.78, (0x8C, 0x10, 0x2B)),
        (1.00, (0x08, 0x09, 0x0D)),
    ])
    horizon = int(h * 0.66)
    vp = (w // 2, horizon)

    img = add(img, radial_glow((w, h), (w // 2, horizon), w * 0.42, (0xFF, 0x17, 0x44), 0.42))

    # eclipse ring
    ring = Image.new("RGB", (w, h), (0, 0, 0))
    rd = ImageDraw.Draw(ring)
    r = int(h * 0.22)
    cy = horizon - int(h * 0.24)
    rd.ellipse([vp[0] - r, cy - r, vp[0] + r, cy + r], outline=(0xFF, 0x17, 0x44), width=8)
    rd.ellipse([vp[0] - r + 60, cy - r + 60, vp[0] + r - 60, cy + r - 60], outline=(0x9B, 0x5C, 0xFF), width=2)
    img = add(img, ring.filter(ImageFilter.GaussianBlur(0.4)))
    img = add(img, ring.filter(ImageFilter.GaussianBlur(26)))

    # stars
    rnd = random.Random(2207)
    stars = Image.new("RGB", (w, h), (0, 0, 0))
    sd = ImageDraw.Draw(stars)
    for _ in range(700):
        x, y = rnd.randrange(w), rnd.randrange(0, horizon - 40)
        v = rnd.choice([30, 50, 80, 120, 190])
        sd.rectangle([x, y, x + 1, y + 1], fill=(v, v, v))
    img = add(img, stars)

    # perspective grid
    lines = Image.new("RGB", (w, h), (0, 0, 0))
    ld = ImageDraw.Draw(lines)
    for i in range(-26, 27):
        x_bottom = vp[0] + i * int(w * 0.075)
        ld.line([vp, (x_bottom, h)], fill=(0x8C, 0x10, 0x2B), width=3)
    # horizontals with exponential spacing
    n = 34
    for i in range(1, n + 1):
        t = (i / n) ** 3.1
        y = horizon + int((h - horizon) * t)
        fade = int(30 + 190 * (1 - t))
        ld.line([(0, y), (w, y)], fill=(0xE6, 0x00, 0x35), width=max(1, int(5 - 4 * t)))
    # cyan horizon accent
    ld.line([(0, horizon), (w, horizon)], fill=(0x00, 0xE5, 0xFF), width=3)
    img = add(img, lines)
    img = add(img, lines.filter(ImageFilter.GaussianBlur(18)))

    # angular monoliths on both sides
    mon = Image.new("RGB", (w, h), (0, 0, 0))
    md = ImageDraw.Draw(mon)
    md.polygon([(0, horizon), (int(w * 0.14), horizon), (int(w * 0.08), h), (0, h)], fill=(0x0B, 0x0C, 0x11))
    md.polygon([(w, horizon), (int(w * 0.88), horizon), (int(w * 0.93), h), (w, h)], fill=(0x0B, 0x0C, 0x11))
    md.line([(int(w * 0.14), horizon), (int(w * 0.08), h)], fill=(0xFF, 0x17, 0x44), width=3)
    md.line([(int(w * 0.88), horizon), (int(w * 0.93), h)], fill=(0xFF, 0x17, 0x44), width=3)
    img = Image.composite(mon, img, mon.convert("L").point(lambda v: 255 if v > 4 else 0))

    d = ImageDraw.Draw(img)
    text_track(d, (w // 2, int(h * 0.13)), "NIGHT CITY", font("orbitron", 96), (0xE8, 0xEA, 0xF0, 240), 30, anchor="ma")
    text_track(d, (w // 2, int(h * 0.20)), "DISTRICT GRID // ONLINE", font("mono", 28), (0x00, 0xE5, 0xFF, 190), 5, anchor="ma")

    img = scanlines(img, 6, 7)
    img = vignette(img, 1.7, 0.60)
    return grain(img, 4, 22)


# ---------------------------------------------------------------------------
# 03 — CIRCUIT VEIN
# ---------------------------------------------------------------------------
def w_circuit(w, h):
    img = fast_gradient((w, h), [
        (0.00, (0x0B, 0x0D, 0x12)),
        (0.50, (0x0E, 0x10, 0x17)),
        (1.00, (0x08, 0x09, 0x0D)),
    ])
    # brushed metal diagonals
    rnd = random.Random(3311)
    brush = Image.new("RGB", (w, h), (0, 0, 0))
    bd = ImageDraw.Draw(brush)
    for _ in range(1400):
        x = rnd.randrange(-h, w)
        y = rnd.randrange(h)
        length = rnd.randint(80, 700)
        v = rnd.randint(2, 9)
        bd.line([(x, y), (x + length, y - length)], fill=(v, v, v + 2), width=1)
    img = add(img, brush.filter(ImageFilter.GaussianBlur(0.8)))

    img = add(img, radial_glow((w, h), (w // 2, h // 2), w * 0.5, (0xFF, 0x17, 0x44), 0.22))

    layers = []
    traces = Image.new("RGB", (w, h), (0, 0, 0))
    td = ImageDraw.Draw(traces)
    nodes = Image.new("RGB", (w, h), (0, 0, 0))
    nd = ImageDraw.Draw(nodes)

    def trace(start, color, steps=9, step=90, width=3):
        x, y = start
        pts = [(x, y)]
        horiz = rnd.choice([True, False])
        for _ in range(steps):
            d = rnd.choice([-1, 1])
            if horiz:
                x += d * step * rnd.uniform(0.6, 1.8)
            else:
                y += d * step * rnd.uniform(0.6, 1.8)
            x = max(60, min(w - 60, x))
            y = max(60, min(h - 60, y))
            pts.append((x, y))
            horiz = not horiz
        td.line(pts, fill=color, width=width, joint="curve")
        for px, py in pts[1:-1]:
            s = rnd.choice([5, 7, 9])
            nd.rectangle([px - s, py - s, px + s, py + s], outline=color, width=2)
        return pts

    for _ in range(26):
        trace((rnd.randrange(w), rnd.randrange(h)), (0x8C, 0x10, 0x2B), rnd.randint(5, 12), rnd.randint(70, 150), 2)
    for _ in range(12):
        trace((rnd.randrange(w), rnd.randrange(h)), (0xE6, 0x00, 0x35), rnd.randint(5, 10), rnd.randint(80, 170), 3)
    for _ in range(4):
        trace((rnd.randrange(w), rnd.randrange(h)), (0x00, 0x8F, 0xA8), rnd.randint(4, 8), rnd.randint(90, 160), 2)

    # central processor block
    cw, ch = int(w * 0.34), int(h * 0.30)
    cx, cy = (w - cw) // 2, (h - ch) // 2
    td.rectangle([cx, cy, cx + cw, cy + ch], outline=(0xFF, 0x17, 0x44), width=4)
    td.rectangle([cx + 26, cy + 26, cx + cw - 26, cy + ch - 26], outline=(0x34, 0x3B, 0x49), width=2)
    # pins
    for i in range(14):
        px = cx + 40 + i * (cw - 80) / 13
        td.line([(px, cy - 28), (px, cy)], fill=(0xFF, 0x17, 0x44), width=3)
        td.line([(px, cy + ch), (px, cy + ch + 28)], fill=(0xFF, 0x17, 0x44), width=3)
    for i in range(9):
        py = cy + 40 + i * (ch - 80) / 8
        td.line([(cx - 28, py), (cx, py)], fill=(0xFF, 0x17, 0x44), width=3)
        td.line([(cx + cw, py), (cx + cw + 28, py)], fill=(0xFF, 0x17, 0x44), width=3)

    img = add(img, traces)
    img = add(img, nodes)
    img = add(img, traces.filter(ImageFilter.GaussianBlur(22)))

    d = ImageDraw.Draw(img)
    text_track(d, (cx + 60, cy + 66), "NC//CORE", font("orbitron", 54), (0xE8, 0xEA, 0xF0, 235), 10)
    text_track(d, (cx + 62, cy + 140), "URBAN OPERATING SYSTEM", font("mono", 24), (0x92, 0x99, 0xA8, 190), 3)
    text_track(d, (cx + 62, cy + 186), "BUILD 2077.10  //  RED LINE", font("mono", 24), (0xFF, 0x17, 0x44, 210), 2)

    # corner HUD marks
    m = 110
    for (x0, y0, dx, dy) in [(m, m, 1, 1), (w - m, m, -1, 1), (m, h - m, 1, -1), (w - m, h - m, -1, -1)]:
        d.line([(x0, y0), (x0 + dx * 120, y0)], fill=(0x92, 0x99, 0xA8), width=3)
        d.line([(x0, y0), (x0, y0 + dy * 120)], fill=(0x92, 0x99, 0xA8), width=3)

    img = scanlines(img, 4, 8)
    img = vignette(img, 1.9, 0.58)
    return grain(img, 5, 33)


# ---------------------------------------------------------------------------
# 04 — NEON RAIN
# ---------------------------------------------------------------------------
def w_rain(w, h):
    img = fast_gradient((w, h), [
        (0.00, (0x07, 0x08, 0x0C)),
        (0.45, (0x0C, 0x0A, 0x14)),
        (0.72, (0x1A, 0x0C, 0x1C)),
        (1.00, (0x08, 0x09, 0x0D)),
    ])
    rnd = random.Random(4409)

    # distant neon signs, out of focus
    signs = Image.new("RGB", (w, h), (0, 0, 0))
    sd = ImageDraw.Draw(signs)
    palette = [(0xFF, 0x17, 0x44), (0xFF, 0x3D, 0x81), (0x9B, 0x5C, 0xFF), (0x00, 0xE5, 0xFF)]
    for _ in range(22):
        x = rnd.randrange(-100, w)
        y = rnd.randrange(int(h * 0.12), int(h * 0.72))
        bw = rnd.randint(60, 260)
        bh = rnd.randint(140, 620)
        col = rnd.choice(palette)
        sd.rectangle([x, y, x + bw, y + bh], fill=tuple(int(c * 0.35) for c in col))
    signs = signs.filter(ImageFilter.GaussianBlur(38))
    img = screen(img, signs)

    # wet street reflections
    refl = Image.new("RGB", (w, h), (0, 0, 0))
    rd = ImageDraw.Draw(refl)
    for _ in range(70):
        x = rnd.randrange(w)
        y = rnd.randrange(int(h * 0.62), h)
        ln = rnd.randint(40, 420)
        col = rnd.choice(palette)
        rd.line([(x, y), (x + rnd.randint(-30, 30), y + ln)], fill=tuple(int(c * 0.5) for c in col),
                width=rnd.randint(3, 14))
    img = screen(img, refl.filter(ImageFilter.GaussianBlur(22)))

    # rain streaks
    rain = Image.new("RGB", (w, h), (0, 0, 0))
    rdraw = ImageDraw.Draw(rain)
    for _ in range(2600):
        x = rnd.randrange(-200, w)
        y = rnd.randrange(h)
        ln = rnd.randint(30, 150)
        v = rnd.randint(22, 75)
        rdraw.line([(x, y), (x + ln * 0.34, y + ln)], fill=(v, v, min(255, v + 14)), width=1)
    img = add(img, rain.filter(ImageFilter.GaussianBlur(0.5)))

    # sharp foreground droplets
    fg = Image.new("RGB", (w, h), (0, 0, 0))
    fd = ImageDraw.Draw(fg)
    for _ in range(90):
        x = rnd.randrange(w)
        y = rnd.randrange(h)
        ln = rnd.randint(90, 260)
        fd.line([(x, y), (x + ln * 0.32, y + ln)], fill=(90, 96, 108), width=rnd.randint(1, 3))
    img = add(img, fg.filter(ImageFilter.GaussianBlur(1.6)))

    # typographic sign, left third
    txt = Image.new("RGB", (w, h), (0, 0, 0))
    td = ImageDraw.Draw(txt)
    text_track(td, (240, int(h * 0.30)), "NIGHT", font("orbitron", 170), (0xFF, 0x17, 0x44, 255), 26)
    text_track(td, (240, int(h * 0.30) + 210), "CITY", font("orbitron", 170), (0xE8, 0xEA, 0xF0, 255), 46)
    td.rectangle([246, int(h * 0.30) + 420, 246 + 620, int(h * 0.30) + 426], fill=(0x00, 0xE5, 0xFF))
    text_track(td, (250, int(h * 0.30) + 452), "OPEN ALL NIGHT", font("rajdhani", 46), (0x92, 0x99, 0xA8, 255), 12)
    img = add(img, txt.filter(ImageFilter.GaussianBlur(26)))
    img = add(img, txt.filter(ImageFilter.GaussianBlur(1.0)))

    # awnings / silhouettes lower right
    sil = Image.new("RGB", (w, h), (0, 0, 0))
    sdw = ImageDraw.Draw(sil)
    sdw.polygon([(int(w * 0.62), h), (int(w * 0.78), int(h * 0.68)), (w, int(h * 0.74)), (w, h)],
                fill=(0x06, 0x07, 0x0A))
    sdw.line([(int(w * 0.78), int(h * 0.68)), (w, int(h * 0.74))], fill=(0xFF, 0x3D, 0x81), width=3)
    img = Image.composite(sil, img, sil.convert("L").point(lambda v: 255 if v > 3 else 0))

    img = scanlines(img, 7, 6)
    img = vignette(img, 1.7, 0.66)
    return grain(img, 6, 44)


# ---------------------------------------------------------------------------
# 05 — APERTURE
# ---------------------------------------------------------------------------
def w_aperture(w, h):
    img = fast_gradient((w, h), [
        (0.00, (0x08, 0x09, 0x0D)),
        (0.45, (0x0D, 0x0E, 0x16)),
        (1.00, (0x08, 0x09, 0x0D)),
    ])
    cx, cy = int(w * 0.56), int(h * 0.50)
    img = add(img, radial_glow((w, h), (cx, cy), w * 0.34, (0xFF, 0x17, 0x44), 0.35))
    img = add(img, radial_glow((w, h), (cx - 160, cy + 120), w * 0.22, (0x9B, 0x5C, 0xFF), 0.20))

    def hexagon(cx, cy, r, rot=0.0):
        pts = []
        for i in range(6):
            a = rot + i * math.pi / 3
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a) * 0.92))
        return pts

    layers = Image.new("RGB", (w, h), (0, 0, 0))
    ld = ImageDraw.Draw(layers)
    for i in range(26):
        r = int(h * (0.10 + i * 0.026))
        a = i / 25
        col = lerp((0xFF, 0x17, 0x44), (0x9B, 0x5C, 0xFF), a)
        width = 5 if i % 5 == 0 else 2
        ld.polygon(hexagon(cx, cy, r, rot=math.radians(i * 3.0)), outline=col, width=width)

    # reticle ticks
    for i in range(72):
        a = i * math.pi / 36
        r0 = h * 0.405
        r1 = r0 + (26 if i % 6 else 52)
        ld.line([(cx + r0 * math.cos(a), cy + r0 * math.sin(a)),
                 (cx + r1 * math.cos(a), cy + r1 * math.sin(a))],
                fill=(0x92, 0x99, 0xA8), width=2)

    img = add(img, layers)
    img = add(img, layers.filter(ImageFilter.GaussianBlur(20)))

    # central dark aperture with red iris
    iris = Image.new("RGB", (w, h), (0, 0, 0))
    idraw = ImageDraw.Draw(iris)
    r = int(h * 0.105)
    idraw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(0x08, 0x09, 0x0D), outline=(0xFF, 0x17, 0x44), width=4)
    r2 = int(r * 0.62)
    idraw.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], outline=(0xE6, 0x00, 0x35), width=2)
    idraw.line([(cx - r, cy), (cx - r2, cy)], fill=(0xFF, 0x17, 0x44), width=3)
    idraw.line([(cx + r2, cy), (cx + r, cy)], fill=(0xFF, 0x17, 0x44), width=3)
    img = add(img, iris)
    img = add(img, idraw and iris.filter(ImageFilter.GaussianBlur(18)))

    d = ImageDraw.Draw(img)
    text_track(d, (200, int(h * 0.18)), "NIGHT CITY", font("orbitron", 92), (0xE8, 0xEA, 0xF0, 245), 22)
    text_track(d, (204, int(h * 0.18) + 130), "OPTICS // APERTURE 1.4", font("mono", 26), (0x00, 0xE5, 0xFF, 0xBE), 3)
    text_track(d, (204, h - 210), "BEYOND THE SYSTEM. INTO THE CITY.", font("rajdhani", 36), (0x92, 0x99, 0xA8, 255), 8)

    # corner telemetry
    text_track(d, (w - 200, int(h * 0.18)), "LAT 35.68  LON 139.76", font("mono", 24), (0x92, 0x99, 0xA8, 180), 2, anchor="ra")
    text_track(d, (w - 200, int(h * 0.18) + 44), "FOCUS LOCK // 100%", font("mono", 24), (0xFF, 0x17, 0x44, 200), 2, anchor="ra")

    img = scanlines(img, 6, 7)
    img = vignette(img, 1.8, 0.62)
    return grain(img, 4, 55)


# ---------------------------------------------------------------------------
# 06 — SIGNAL / WORDMARK
# ---------------------------------------------------------------------------
def w_signal(w, h):
    img = fast_gradient((w, h), [
        (0.00, (0x08, 0x09, 0x0D)),
        (0.55, (0x13, 0x08, 0x12)),
        (1.00, (0x08, 0x09, 0x0D)),
    ])
    # diagonal warning stripes
    stripes = Image.new("RGB", (w, h), (0, 0, 0))
    sd = ImageDraw.Draw(stripes)
    step = 220
    for x in range(-h, w + h, step * 2):
        sd.polygon([(x, h), (x + step, h), (x + step + h, 0), (x + h, 0)], fill=(0x1A, 0x0A, 0x14))
    img = Image.blend(img, ImageChops.add(img, stripes), 0.55)

    img = add(img, radial_glow((w, h), (w // 2, h // 2), w * 0.36, (0xFF, 0x17, 0x44), 0.30))

    # horizontal glitch bars
    rnd = random.Random(6607)
    for _ in range(26):
        y = rnd.randrange(h)
        bh = rnd.randint(2, 26)
        dx = rnd.randint(-140, 140)
        band = img.crop((0, y, w, min(h, y + bh)))
        band = ImageChops.offset(band, dx, 0)
        img.paste(band, (0, y))
        if rnd.random() < 0.5:
            d = ImageDraw.Draw(img)
            d.rectangle([0, y, w, y + 1], fill=(0xFF, 0x17, 0x44))

    # wordmark
    logo_path = ROOT / "assets" / "branding" / "nightcity-logo.png"
    if logo_path.exists():
        logo = Image.open(logo_path).convert("RGBA")
        target_w = int(w * 0.46)
        logo = logo.resize((target_w, int(logo.height * target_w / logo.width)), Image.LANCZOS)
        lx, ly = (w - logo.width) // 2, int(h * 0.40)
        glow = Image.new("RGB", (w, h), (0, 0, 0))
        glow.paste(logo.convert("RGB"), (lx, ly), logo)
        img = add(img, glow.filter(ImageFilter.GaussianBlur(30)))
        img = Image.alpha_composite(img.convert("RGBA"), _at(logo, lx, ly, (w, h))).convert("RGB")
    else:
        d = ImageDraw.Draw(img)
        text_track(d, (w // 2, int(h * 0.42)), "NIGHT CITY", font("orbitron", 170), (0xE8, 0xEA, 0xF0, 255), 30, anchor="ma")

    d = ImageDraw.Draw(img)
    d.rectangle([int(w * 0.30), int(h * 0.62), int(w * 0.70), int(h * 0.62) + 3], fill=(0xFF, 0x17, 0x44))
    text_track(d, (w // 2, int(h * 0.665)), "BEYOND THE SYSTEM. INTO THE CITY.", font("rajdhani", 44), (0x92, 0x99, 0xA8, 240), 12, anchor="ma")
    text_track(d, (w // 2, int(h * 0.735)), "TRANSMISSION 07 // SIGNAL LOCKED", font("mono", 26), (0x00, 0xE5, 0xFF, 0xA0), 4, anchor="ma")

    # frame
    m = 90
    d.rectangle([m, m, w - m, h - m], outline=(0x34, 0x3B, 0x49), width=2)
    for x0, y0, dx, dy in [(m, m, 1, 1), (w - m, m, -1, 1), (m, h - m, 1, -1), (w - m, h - m, -1, -1)]:
        d.line([(x0, y0), (x0 + dx * 90, y0)], fill=(0xFF, 0x17, 0x44), width=3)
        d.line([(x0, y0), (x0, y0 + dy * 90)], fill=(0xFF, 0x17, 0x44), width=3)

    img = scanlines(img, 5, 7)
    img = vignette(img, 1.6, 0.60)
    return grain(img, 4, 66)


def _at(rgba, x, y, size):
    """Place an RGBA image on a full-size transparent canvas."""
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.paste(rgba, (x, y), rgba)
    return layer


WALLPAPERS = {
    "nightcity-01-nightline.png": w_nightline,
    "nightcity-02-grid-horizon.png": w_grid,
    "nightcity-03-circuit-vein.png": w_circuit,
    "nightcity-04-neon-rain.png": w_rain,
    "nightcity-05-aperture.png": w_aperture,
    "nightcity-06-signal.png": w_signal,
}


def main() -> int:
    global W, H
    ap = argparse.ArgumentParser()
    ap.add_argument("--width", type=int, default=3840)
    ap.add_argument("--height", type=int, default=2160)
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    W, H = args.width, args.height

    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in WALLPAPERS.items():
        if args.only and args.only not in name:
            continue
        save(fn(W, H), name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
