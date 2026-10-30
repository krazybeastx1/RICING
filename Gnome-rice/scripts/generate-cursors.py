#!/usr/bin/env python3
"""Build NightCity-Cursor with xcursorgen.

Design: carbon-black fills, neon-red keyline, soft-white highlights. Static
cursors are rendered at 4x and downsampled; wait/progress are 12-frame
animations. Every common X11/GTK cursor name is aliased to a real cursor.

Requires: python3-pil, xcursorgen.
"""
from __future__ import annotations

import json
import math
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
TOKENS = json.loads((ROOT / "design" / "tokens.json").read_text(encoding="utf-8"))
C = TOKENS["colors"]
OUT = ROOT / "cursors" / "NightCity-Cursor"
FRAMES = ROOT / "build" / "cursor-frames"
FONT = ROOT / "assets" / "fonts" / "JetBrainsMono" / "JetBrainsMono-Variable.ttf"

RED = C["neon-red"]
WHITE = C["soft-white"]
BLACK = C["night-black"]
STEEL = C["border-gray"]
CYAN = C["holo-cyan"]
SIZES = (24, 32, 48, 64)
SS = 8  # supersampling factor


def new_canvas(size: int) -> tuple[Image.Image, ImageDraw.ImageDraw, int]:
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img), s


def finish(img: Image.Image, size: int) -> Image.Image:
    return img.resize((size, size), Image.LANCZOS)


def outline_polygon(d, pts, fill, outline, width):
    d.polygon(pts, fill=fill)
    d.line(list(pts) + [pts[0]], fill=outline, width=width, joint="curve")


# ---------------------------------------------------------------------------
# Static cursor painters. Each receives (draw, S, scale) and returns hotspot
# as normalized coordinates.
# ---------------------------------------------------------------------------
def arrow(d, s):
    pts = [(0.10, 0.04), (0.10, 0.78), (0.28, 0.62), (0.41, 0.94),
           (0.55, 0.87), (0.42, 0.57), (0.66, 0.55)]
    P = [(x * s, y * s) for x, y in pts]
    outline_polygon(d, P, BLACK, RED, max(2, int(s * 0.035)))
    d.line([P[0], (P[1][0] + s * 0.02, P[1][1] - s * 0.04)], fill=WHITE, width=max(1, int(s * 0.012)))
    return (0.10, 0.04)


def crosshair(d, s):
    w = max(2, int(s * 0.028))
    gap = s * 0.13
    for a, b in [((0.5, 0.06), (0.5, 0.38)), ((0.5, 0.62), (0.5, 0.94)),
                 ((0.06, 0.5), (0.38, 0.5)), ((0.62, 0.5), (0.94, 0.5))]:
        d.line([(a[0] * s, a[1] * s), (b[0] * s, b[1] * s)], fill=RED, width=w)
    d.ellipse([s * 0.5 - s * 0.035, s * 0.5 - s * 0.035,
               s * 0.5 + s * 0.035, s * 0.5 + s * 0.035], fill=WHITE)
    return (0.5, 0.5)


def text_cursor(d, s):
    w = max(2, int(s * 0.03))
    d.line([(0.5 * s, 0.10 * s), (0.5 * s, 0.90 * s)], fill=WHITE, width=w)
    d.line([(0.30 * s, 0.10 * s), (0.70 * s, 0.10 * s)], fill=RED, width=w)
    d.line([(0.30 * s, 0.90 * s), (0.70 * s, 0.90 * s)], fill=RED, width=w)
    return (0.5, 0.5)


def hand(d, s, closed=False):
    o = max(2, int(s * 0.03))
    # palm
    d.rounded_rectangle([0.28 * s, 0.44 * s, 0.78 * s, 0.94 * s], radius=0.14 * s,
                        fill=BLACK, outline=RED, width=o)
    if closed:
        d.rounded_rectangle([0.30 * s, 0.40 * s, 0.76 * s, 0.62 * s], radius=0.10 * s,
                            fill=BLACK, outline=RED, width=o)
        d.line([(0.38 * s, 0.50 * s), (0.68 * s, 0.50 * s)], fill=WHITE, width=max(1, int(s * 0.012)))
    else:
        # extended index finger
        d.rounded_rectangle([0.34 * s, 0.10 * s, 0.50 * s, 0.56 * s], radius=0.07 * s,
                            fill=BLACK, outline=RED, width=o)
        # remaining fingers
        for i, x in enumerate((0.52, 0.63, 0.74)):
            top = 0.24 + i * 0.035
            d.rounded_rectangle([x * s, top * s, (x + 0.10) * s, 0.58 * s], radius=0.05 * s,
                                fill=BLACK, outline=RED, width=max(1, o - 1))
        # thumb
        d.rounded_rectangle([0.14 * s, 0.48 * s, 0.36 * s, 0.68 * s], radius=0.09 * s,
                            fill=BLACK, outline=RED, width=o)
    return (0.38, 0.12)


def resize(d, s, angle=0):
    w = max(2, int(s * 0.03))
    # draw vertical double arrow, rotated via an overlay
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.line([(0.5 * s, 0.12 * s), (0.5 * s, 0.88 * s)], fill=RED, width=w)
    ld.polygon([(0.5 * s, 0.04 * s), (0.38 * s, 0.20 * s), (0.62 * s, 0.20 * s)], fill=RED)
    ld.polygon([(0.5 * s, 0.96 * s), (0.38 * s, 0.80 * s), (0.62 * s, 0.80 * s)], fill=RED)
    ld.line([(0.5 * s, 0.28 * s), (0.5 * s, 0.72 * s)], fill=WHITE, width=max(1, int(s * 0.012)))
    if angle:
        layer = layer.rotate(angle, resample=Image.BICUBIC, center=(s / 2, s / 2))
    return layer, (0.5, 0.5)


def not_allowed(d, s):
    w = max(2, int(s * 0.05))
    d.ellipse([0.08 * s, 0.08 * s, 0.92 * s, 0.92 * s], outline=RED, width=w)
    d.line([(0.24 * s, 0.24 * s), (0.76 * s, 0.76 * s)], fill=RED, width=w)
    return (0.5, 0.5)


def move(d, s):
    w = max(2, int(s * 0.028))
    d.line([(0.5 * s, 0.12 * s), (0.5 * s, 0.88 * s)], fill=WHITE, width=w)
    d.line([(0.12 * s, 0.5 * s), (0.88 * s, 0.5 * s)], fill=WHITE, width=w)
    for pts in (
        [(0.5, 0.04), (0.40, 0.18), (0.60, 0.18)],
        [(0.5, 0.96), (0.40, 0.82), (0.60, 0.82)],
        [(0.04, 0.5), (0.18, 0.40), (0.18, 0.60)],
        [(0.96, 0.5), (0.82, 0.40), (0.82, 0.60)],
    ):
        d.polygon([(x * s, y * s) for x, y in pts], fill=RED)
    return (0.5, 0.5)


def help_cursor(d, s):
    arrow(d, s)
    f = ImageFont.truetype(str(FONT), int(0.34 * s))
    d.ellipse([0.52 * s, 0.52 * s, 0.98 * s, 0.98 * s], fill=BLACK, outline=RED,
              width=max(2, int(s * 0.03)))
    d.text((0.75 * s, 0.75 * s), "?", font=f, fill=WHITE, anchor="mm")
    return (0.10, 0.04)


def zoom(d, s, sign="+"):
    d.ellipse([0.10 * s, 0.10 * s, 0.68 * s, 0.68 * s], outline=RED, width=max(2, int(s * 0.04)))
    d.line([(0.62 * s, 0.62 * s), (0.92 * s, 0.92 * s)], fill=RED, width=max(3, int(s * 0.06)))
    d.line([(0.25 * s, 0.39 * s), (0.53 * s, 0.39 * s)], fill=WHITE, width=max(2, int(s * 0.03)))
    if sign == "+":
        d.line([(0.39 * s, 0.25 * s), (0.39 * s, 0.53 * s)], fill=WHITE, width=max(2, int(s * 0.03)))
    return (0.39, 0.39)


def context_menu(d, s):
    arrow(d, s)
    d.rounded_rectangle([0.48 * s, 0.44 * s, 0.96 * s, 0.86 * s], radius=0.05 * s,
                        fill=BLACK, outline=RED, width=max(2, int(s * 0.025)))
    for i, y in enumerate((0.54, 0.64, 0.74)):
        d.line([(0.56 * s, y * s), (0.60 * s, y * s)], fill=RED, width=max(2, int(s * 0.02)))
        d.line([(0.64 * s, y * s), (0.88 * s, y * s)], fill=WHITE, width=max(1, int(s * 0.015)))
    return (0.10, 0.04)


def spinner(d, s, phase, full=False):
    w = max(3, int(s * 0.075))
    box = [0.14 * s, 0.14 * s, 0.86 * s, 0.86 * s]
    if full:
        d.ellipse(box, outline=STEEL, width=w)
    d.arc(box, start=phase, end=phase + (110 if not full else 90), fill=RED, width=w)
    dot_r = 0.035 * s
    for i, a in enumerate((phase + 200, phase + 260, phase + 320)):
        x = 0.5 * s + 0.26 * s * math.cos(math.radians(a))
        y = 0.5 * s + 0.26 * s * math.sin(math.radians(a))
        d.ellipse([x - dot_r, y - dot_r, x + dot_r, y + dot_r], fill=WHITE)
    return (0.5, 0.5)


# ---------------------------------------------------------------------------
CURSORS = {
    "left_ptr": {"hot": (0.10, 0.04), "kind": "arrow"},
    "left-ptr": {"alias": "left_ptr"},
    "default": {"alias": "left_ptr"},
    "arrow": {"alias": "left_ptr"},
    "top_left_arrow": {"alias": "left_ptr"},
    "text": {"hot": (0.5, 0.5), "kind": "text"},
    "xterm": {"alias": "text"},
    "ibeam": {"alias": "text"},
    "crosshair": {"hot": (0.5, 0.5), "kind": "cross"},
    "cross": {"alias": "crosshair"},
    "tcross": {"alias": "crosshair"},
    "diamond_cross": {"alias": "crosshair"},
    "pointer": {"hot": (0.38, 0.12), "kind": "hand"},
    "hand1": {"alias": "pointer"},
    "hand": {"alias": "pointer"},
    "pointing_hand": {"alias": "pointer"},
    "openhand": {"hot": (0.5, 0.5), "kind": "openhand"},
    "closedhand": {"hot": (0.5, 0.5), "kind": "closedhand"},
    "grab": {"alias": "openhand"},
    "grabbing": {"alias": "closedhand"},
    "fleur": {"hot": (0.5, 0.5), "kind": "move"},
    "move": {"alias": "fleur"},
    "all-scroll": {"alias": "fleur"},
    "n-resize": {"hot": (0.5, 0.5), "kind": "resize", "angle": 0},
    "s-resize": {"alias": "n-resize"},
    "ns-resize": {"alias": "n-resize"},
    "vertical-resize": {"alias": "n-resize"},
    "top_side": {"alias": "n-resize"},
    "bottom_side": {"alias": "n-resize"},
    "e-resize": {"hot": (0.5, 0.5), "kind": "resize", "angle": 90},
    "w-resize": {"alias": "e-resize"},
    "ew-resize": {"alias": "e-resize"},
    "horizontal-resize": {"alias": "e-resize"},
    "left_side": {"alias": "e-resize"},
    "right_side": {"alias": "e-resize"},
    "ne-resize": {"hot": (0.5, 0.5), "kind": "resize", "angle": 45},
    "sw-resize": {"alias": "ne-resize"},
    "nesw-resize": {"alias": "ne-resize"},
    "nw-resize": {"hot": (0.5, 0.5), "kind": "resize", "angle": -45},
    "se-resize": {"alias": "nw-resize"},
    "nwse-resize": {"alias": "nw-resize"},
    "not-allowed": {"hot": (0.5, 0.5), "kind": "notallowed"},
    "forbidden": {"alias": "not-allowed"},
    "crossed_circle": {"alias": "not-allowed"},
    "no-drop": {"alias": "not-allowed"},
    "help": {"hot": (0.10, 0.04), "kind": "help"},
    "question_arrow": {"alias": "help"},
    "whats_this": {"alias": "help"},
    "context-menu": {"hot": (0.10, 0.04), "kind": "context"},
    "zoom-in": {"hot": (0.39, 0.39), "kind": "zoomplus"},
    "zoom-out": {"hot": (0.39, 0.39), "kind": "zoomminus"},
    "wait": {"hot": (0.5, 0.5), "kind": "wait", "frames": 12, "delay": 70},
    "watch": {"alias": "wait"},
    "left_ptr_watch": {"alias": "wait"},
    "progress": {"hot": (0.5, 0.5), "kind": "progress", "frames": 12, "delay": 70},
    "half-busy": {"alias": "progress"},
}


def draw_static(kind: str, size: int, angle: int = 0) -> tuple[Image.Image, tuple]:
    img, d, s = new_canvas(size)
    if kind == "arrow":
        hot = arrow(d, s)
    elif kind == "cross":
        hot = crosshair(d, s)
    elif kind == "text":
        hot = text_cursor(d, s)
    elif kind == "hand":
        hot = hand(d, s, False)
    elif kind == "openhand":
        hot = hand(d, s, False)
    elif kind == "closedhand":
        hot = hand(d, s, True)
    elif kind == "move":
        hot = move(d, s)
    elif kind == "notallowed":
        hot = not_allowed(d, s)
    elif kind == "help":
        hot = help_cursor(d, s)
    elif kind == "context":
        hot = context_menu(d, s)
    elif kind == "zoomplus":
        hot = zoom(d, s, "+")
    elif kind == "zoomminus":
        hot = zoom(d, s, "-")
    elif kind == "resize":
        hot = (0.5, 0.5)
    else:
        raise ValueError(kind)
    if kind == "resize":
        layer, hot = resize(d, s, angle)
        img = Image.alpha_composite(img, layer)
    return finish(img, size), hot


def draw_animated(kind: str, size: int, frame: int, frames: int) -> tuple[Image.Image, tuple]:
    img, d, s = new_canvas(size)
    phase = frame * (360 / frames)
    hot = spinner(d, s, phase, full=(kind == "progress"))
    return finish(img, size), hot


def write_config(path: Path, entries: list[tuple[int, float, float, Path, int | None]]) -> None:
    lines = []
    for size, hx, hy, png, delay in entries:
        hx_i = max(0, min(size - 1, round(hx * size)))
        hy_i = max(0, min(size - 1, round(hy * size)))
        if delay is None:
            lines.append(f"{size} {hx_i} {hy_i} {png}")
        else:
            lines.append(f"{size} {hx_i} {hy_i} {png} {delay}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    if not shutil.which("xcursorgen"):
        print("xcursorgen not found (install x11-apps / xcursorgen)")
        return 2
    if OUT.exists():
        shutil.rmtree(OUT)
    if FRAMES.exists():
        shutil.rmtree(FRAMES)
    (OUT / "cursors").mkdir(parents=True)

    for name, spec in CURSORS.items():
        if "alias" in spec:
            continue
        kind = spec["kind"]
        angle = spec.get("angle", 0)
        frames = spec.get("frames", 1)
        delay = spec.get("delay")
        entries = []
        for f in range(frames):
            for size in SIZES:
                if frames == 1:
                    img, hot = draw_static(kind, size, angle)
                else:
                    img, hot = draw_animated(kind, size, f, frames)
                png = FRAMES / name / f"{size}-{f}.png"
                png.parent.mkdir(parents=True, exist_ok=True)
                img.save(png)
                entries.append((size, hot[0], hot[1], png, delay))
        cfg = FRAMES / name / "cursor.cfg"
        write_config(cfg, entries)
        subprocess.run(["xcursorgen", str(cfg), str(OUT / "cursors" / name)], check=True)

    # aliases
    for name, spec in CURSORS.items():
        if "alias" not in spec:
            continue
        target = OUT / "cursors" / spec["alias"]
        link = OUT / "cursors" / name
        if not target.exists():
            print(f"warning: alias target missing: {spec['alias']}")
            continue
        try:
            link.symlink_to(spec["alias"])
        except FileExistsError:
            link.unlink()
            link.symlink_to(spec["alias"])

    (OUT / "cursor.theme").write_text(
        "[Icon Theme]\nName=NightCity-Cursor\nComment=NIGHT CITY — neon-red cursor set\n"
        "Inherits=Adwaita\nExample=left_ptr\n", encoding="utf-8")
    (OUT / "index.theme").write_text(
        "[Icon Theme]\nName=NightCity-Cursor\nComment=NIGHT CITY — neon-red cursor set\n"
        "Inherits=Adwaita\n", encoding="utf-8")

    count = len(list((OUT / "cursors").iterdir()))
    print(f"cursor {count} cursor names, {len(SIZES)} sizes, "
          f"2 animations × {CURSORS['wait']['frames']} frames")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
