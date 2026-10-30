#!/usr/bin/env python3
"""NIGHT CITY theme compiler.

Builds every generated stylesheet from one design-token source:

  design/tokens.json
  design/base/*.css        (upstream Adwaita / GNOME Shell base, LGPL)
  design/overrides/*.css   (NightCity-authored overrides, token templates)

Outputs:
  themes/NightCity-Shell/gnome-shell/gnome-shell.css
  themes/NightCity-GTK/gtk-3.0/gtk.css, gtk-dark.css
  themes/NightCity-GTK/gtk-4.0/gtk.css, gtk-dark.css
  gtk-4.0-user.css  (installed to ~/.config/gtk-4.0/gtk.css by install.sh)
  assets/branding/palette.html (developer sanity page)

The recolour pass converts Adwaita's blue/neutral palette into NightCity's
carbon + neon-red system while preserving contrast hierarchy. Explicit
overrides then add the cinematic surface treatment.
"""
from __future__ import annotations

import colorsys
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / "design"
BASE = DESIGN / "base"
OVERRIDES = DESIGN / "overrides"

TOKENS = json.loads((DESIGN / "tokens.json").read_text(encoding="utf-8"))
C = TOKENS["colors"]
A = TOKENS["alpha"]

HEX_RE = re.compile(r"#([0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b")
COMMENT_RE = re.compile(r"/\*.*?\*/", re.S)
RGBA_RE = re.compile(r"rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})(?:\s*,\s*([0-9.]+))?\s*\)")
WHITE_WORD_RE = re.compile(r"(?<![-a-zA-Z_])white(?![-a-zA-Z_])")
BLACK_WORD_RE = re.compile(r"(?<![-a-zA-Z_])black(?![-a-zA-Z_])")


def _hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    if len(value) == 3:
        value = "".join(ch * 2 for ch in value)
    if len(value) == 8:
        value = value[:6]
    return int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16)

def _rgb_to_hex(rgb) -> str:
    return "#%02X%02X%02X" % tuple(max(0, min(255, round(v))) for v in rgb)


def _ramp(stops, t):
    t = max(0.0, min(1.0, t))
    for i in range(len(stops) - 1):
        p0, c0 = stops[i]
        p1, c1 = stops[i + 1]
        if p0 <= t <= p1:
            f = (t - p0) / (p1 - p0) if p1 > p0 else 0
            return tuple(c0[j] + (c1[j] - c0[j]) * f for j in range(3))
    return stops[-1][1]


NEUTRAL = [
    (0.00, (0x08, 0x09, 0x0D)),
    (0.035, (0x0B, 0x0D, 0x12)),
    (0.075, (0x10, 0x12, 0x18)),
    (0.12, (0x17, 0x1B, 0x24)),
    (0.19, (0x1C, 0x21, 0x2B)),
    (0.27, (0x25, 0x2B, 0x35)),
    (0.36, (0x34, 0x3B, 0x49)),
    (0.46, (0x4C, 0x53, 0x63)),
    (0.55, (0x6E, 0x75, 0x85)),
    (0.64, (0x92, 0x99, 0xA8)),
    (0.76, (0xB9, 0xBE, 0xC9)),
    (0.88, (0xE8, 0xEA, 0xF0)),
    (1.00, (0xF4, 0xF5, 0xF8)),
]

RED = [
    (0.0, (0x5C, 0x0A, 0x1C)),
    (0.22, (0x8C, 0x10, 0x2B)),
    (0.38, (0xB3, 0x0D, 0x34)),
    (0.52, (0xE6, 0x00, 0x35)),
    (0.66, (0xFF, 0x17, 0x44)),
    (0.80, (0xFF, 0x6B, 0x8A)),
    (1.0, (0xFF, 0xA6, 0xB8)),
]

PURPLE = [
    (0.0, (0x2A, 0x16, 0x4D)),
    (0.3, (0x5C, 0x2E, 0x9E)),
    (0.6, (0x9B, 0x5C, 0xFF)),
    (0.85, (0xC6, 0xA6, 0xFF)),
    (1.0, (0xE4, 0xD4, 0xFF)),
]

GREEN = [
    (0.0, (0x1E, 0x3D, 0x2C)),
    (0.35, (0x3E, 0x7A, 0x55)),
    (0.65, (0xA6, 0xE3, 0xA1)),
    (1.0, (0xD8, 0xF5, 0xD4)),
]

AMBER = [
    (0.0, (0x3D, 0x2A, 0x10)),
    (0.35, (0x8C, 0x5E, 0x1A)),
    (0.65, (0xD9, 0x9A, 0x2B)),
    (1.0, (0xF5, 0xD9, 0xA0)),
]

CYAN = [
    (0.0, (0x05, 0x3A, 0x45)),
    (0.35, (0x00, 0x8F, 0xA8)),
    (0.65, (0x00, 0xE5, 0xFF)),
    (1.0, (0xB8, 0xF6, 0xFF)),
]


def map_rgb(r: int, g: int, b: int) -> tuple[int, int, int]:
    rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
    h, l, s = colorsys.rgb_to_hls(rf, gf, bf)
    hue = h * 360.0

    if s < 0.10:
        return _ramp(NEUTRAL, l)

    if 175 <= hue <= 265:
        # Adwaita blue is the accent/selection family in upstream themes.
        return _ramp(RED, l)
    if 265 < hue <= 330:
        return _ramp(PURPLE, l)
    if 70 <= hue < 175:
        return _ramp(GREEN, l)
    if 35 <= hue < 70:
        return _ramp(AMBER, l)
    if 15 <= hue < 35:
        return _ramp(AMBER if l < 0.55 else AMBER, l)
    # red family
    return _ramp(RED, l)


def recolor(text: str) -> str:
    # Keep comments byte-identical: upstream stylesheets contain issue numbers
    # such as "#1473" that look like colour literals.
    out = []
    pos = 0
    for match in COMMENT_RE.finditer(text):
        out.append(_recolor_css(text[pos:match.start()]))
        out.append(match.group(0))
        pos = match.end()
    out.append(_recolor_css(text[pos:]))
    return "".join(out)


def _recolor_css(text: str) -> str:
    text = text.replace("-st-accent-color", C["neon-red"])
    text = text.replace("-st-accent-fg-color", C["night-black"])

    def repl_hex(m):
        raw = m.group(0)
        r, g, b = _hex_to_rgb(raw)
        return _rgb_to_hex(map_rgb(r, g, b))

    def repl_rgba(m):
        r, g, b = int(m.group(1)), int(m.group(2)), int(m.group(3))
        alpha = m.group(4)
        nr, ng, nb = map_rgb(r, g, b)
        if alpha is None:
            return f"rgb({nr}, {ng}, {nb})"
        return f"rgba({nr}, {ng}, {nb}, {alpha})"

    text = HEX_RE.sub(repl_hex, text)
    text = RGBA_RE.sub(repl_rgba, text)
    text = WHITE_WORD_RE.sub(C["soft-white"], text)
    text = BLACK_WORD_RE.sub(C["night-black"], text)
    return text


TOKEN_RE = re.compile(r"\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}")


def substitute(text: str) -> str:
    def lookup(path: str) -> str:
        cur = TOKENS
        for part in path.split("."):
            cur = cur[part]
        return str(cur)

    return TOKEN_RE.sub(lambda m: lookup(m.group(1)), text)


def build_shell() -> None:
    base = (BASE / "gnome-shell-dark.css").read_text(encoding="utf-8")
    overrides = substitute((OVERRIDES / "shell.css").read_text(encoding="utf-8"))
    head = f"""/* NIGHT CITY Shell — GNOME Shell theme
 * Generated from design/tokens.json by scripts/build-theme.py.
 * Base: GNOME Shell 50 Adwaita dark stylesheet (LGPL-2.1-or-later).
 * NightCity additions are original work, licensed GPL-3.0-or-later.
 * Do not edit this generated file; edit design/overrides/shell.css.
 */
"""
    out = head + "\n" + recolor(base) + "\n\n/* ==== NIGHT CITY OVERRIDES ==== */\n" + overrides
    path = ROOT / "themes" / "NightCity-Shell" / "gnome-shell" / "gnome-shell.css"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(out, encoding="utf-8")
    print(f"shell  {path.relative_to(ROOT)}  {len(out) // 1024} KiB")


def build_gtk3() -> None:
    base = (BASE / "gtk3-adwaita-dark.css").read_text(encoding="utf-8")
    overrides = substitute((OVERRIDES / "gtk3.css").read_text(encoding="utf-8"))
    head = f"""/* NIGHT CITY GTK3 — generated from Adwaita (LGPL-2.1-or-later).
 * NightCity modifications: GPL-3.0-or-later. See LICENSE and licenses/.
 * Generated by scripts/build-theme.py. Do not edit directly.
 */
"""
    out = head + recolor(base) + "\n\n/* ==== NIGHT CITY OVERRIDES ==== */\n" + overrides
    for name in ("gtk.css", "gtk-dark.css"):
        path = ROOT / "themes" / "NightCity-GTK" / "gtk-3.0" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(out, encoding="utf-8")
    print(f"gtk3   themes/NightCity-GTK/gtk-3.0/gtk.css  {len(out) // 1024} KiB")


def build_gtk4() -> None:
    base = (BASE / "gtk4-default-dark.css").read_text(encoding="utf-8")
    overrides = substitute((OVERRIDES / "gtk4.css").read_text(encoding="utf-8"))
    head = """/* NIGHT CITY GTK4 standalone — generated from GTK Default dark (LGPL-2.1-or-later).
 * NightCity modifications: GPL-3.0-or-later. libadwaita apps use gtk-4.0-user.css.
 */
"""
    out = head + recolor(base) + "\n\n/* ==== NIGHT CITY OVERRIDES ==== */\n" + overrides
    for name in ("gtk.css", "gtk-dark.css"):
        path = ROOT / "themes" / "NightCity-GTK" / "gtk-4.0" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(out, encoding="utf-8")
    print(f"gtk4   themes/NightCity-GTK/gtk-4.0/gtk.css  {len(out) // 1024} KiB")


def build_gtk4_user() -> None:
    overrides = substitute((OVERRIDES / "gtk4-user.css").read_text(encoding="utf-8"))
    head = """/* NIGHT CITY — libadwaita user stylesheet.
 * Installed to ~/.config/gtk-4.0/gtk.css (backed up by install.sh).
 * libadwaita does not support third-party GTK themes; this layer overrides
 * Adwaita's named colours and surface selectors instead. Remove this file to
 * return to stock libadwaita.
 */
"""
    out = head + overrides
    path = ROOT / "themes" / "NightCity-GTK" / "gtk-4.0-user.css"
    path.write_text(out, encoding="utf-8")
    print(f"gtk4u  themes/NightCity-GTK/gtk-4.0-user.css  {len(out) // 1024} KiB")


def build_gdm() -> None:
    base = (BASE / "gnome-shell-dark.css").read_text(encoding="utf-8")
    shell_overrides = substitute((OVERRIDES / "shell.css").read_text(encoding="utf-8"))
    gdm_overrides = substitute((OVERRIDES / "gdm.css").read_text(encoding="utf-8"))
    head = """/* NIGHT CITY GDM — compiled into the system gresource by configure-gdm.sh.
 * Same GNOME Shell base as the user theme, plus login-screen specifics.
 * Generated by scripts/build-theme.py. Do not edit directly.
 */
"""
    out = head + "\n" + recolor(base) + "\n\n/* ==== NIGHT CITY OVERRIDES ==== */\n" + shell_overrides + "\n\n/* ==== GDM LAYER ==== */\n" + gdm_overrides
    path = ROOT / "gdm" / "theme" / "gnome-shell.css"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(out, encoding="utf-8")
    print(f"gdm    {path.relative_to(ROOT)}  {len(out) // 1024} KiB")


def build_palette_page() -> None:
    colors = C
    swatches = "\n".join(
        f'<div class="sw"><span style="background:{v}"></span><b>{k}</b><code>{v}</code></div>'
        for k, v in colors.items()
    )
    html = f"""<!doctype html><meta charset="utf-8">
<title>NIGHT CITY palette</title>
<style>
body{{background:#08090D;color:#E8EAF0;font:14px/1.5 monospace;padding:40px}}
h1{{font-family:Orbitron,sans-serif;letter-spacing:6px;color:#FF1744}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px}}
.sw{{background:#101218;border:1px solid #343B49;border-radius:8px;padding:10px;display:flex;gap:10px;align-items:center}}
.sw span{{width:44px;height:44px;border-radius:6px;display:block;border:1px solid #343B49}}
.sw b{{display:block;font-size:12px}} .sw code{{color:#9299A8;font-size:11px}}
</style><h1>NIGHT CITY</h1><div class="grid">{swatches}</div>
"""
    path = ROOT / "assets" / "branding" / "palette.html"
    path.write_text(html, encoding="utf-8")


def main() -> int:
    for required in ("shell.css", "gtk3.css", "gtk4.css", "gtk4-user.css", "gdm.css"):
        if not (OVERRIDES / required).exists():
            print(f"missing override template: design/overrides/{required}", file=sys.stderr)
            return 2
    build_shell()
    build_gtk3()
    build_gtk4()
    build_gtk4_user()
    build_gdm()
    build_palette_page()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
