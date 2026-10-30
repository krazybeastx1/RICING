#!/usr/bin/env python3
"""Generate the original NIGHT CITY brand marks.

The wordmark is drawn as geometry (not text) so it renders identically on any
machine, with or without the bundled fonts installed.
"""
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "branding"
OUT.mkdir(parents=True, exist_ok=True)

RED = "#FF1744"
WHITE = "#E8EAF0"
DARK = "#08090D"
SILVER = "#9299A8"

# 40 x 60 stencil grid. Drawn with stroked paths to keep the geometry crisp.
GLYPHS = {
    "N": "M4 56 V4 L36 56 V4",
    "I": "M12 4 H28 M20 4 V56 M12 56 H28",
    "G": "M36 12 H12 V48 H36 V30 H23",
    "H": "M6 4 V56 M34 4 V56 M6 30 H34",
    "T": "M4 4 H36 M20 4 V56",
    "C": "M36 8 H12 V52 H36",
    "Y": "M4 4 L20 30 L36 4 M20 30 V56",
    " ": "",
}

LETTER_W = 40
ADVANCE = 58
STROKE = 7


def wordmark(word, x0, y0, scale, fill, accent_index=None, accent=RED):
    parts = []
    x = x0
    for i, ch in enumerate(word):
        d = GLYPHS[ch]
        if d:
            color = accent if accent_index is not None and i >= accent_index else fill
            parts.append(
                f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{STROKE}" '
                f'stroke-linecap="square" stroke-linejoin="miter" />'
            )
        x += ADVANCE
    return (
        f'<g transform="translate({x0} {y0}) scale({scale}) translate({-x0} {-y0})">'
        + "".join(parts)
        + "</g>"
    )


def logo_svg(fg=WHITE, accent=RED, glow=True, width=1560, height=300):
    # Place NIGHT and CITY on one line with a divider.
    g1 = wordmark("NIGHT", 40, 90, 2.55, fg)
    g2 = wordmark("CITY", 40 + 5 * ADVANCE * 2.55 + 66, 90, 2.55, fg, accent_index=0, accent=accent)
    divider_x = 40 + 5 * ADVANCE * 2.55 + 24
    filt = f"""
  <defs>
    <filter id="glow" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="10" result="b"/>
      <feColorMatrix in="b" type="matrix" values="1 0 0 0 0  0 0.09 0 0 0  0 0.27 0 0 0  0 0 0 0.8 0" result="r"/>
      <feMerge><feMergeNode in="r"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>""" if glow else ""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
  <title>NIGHT CITY</title>{filt}
  <g {'filter="url(#glow)"' if glow else ''}>
    {g1}
    <rect x="{divider_x}" y="84" width="4" height="150" fill="{accent}"/>
    {g2}
  </g>
  <rect x="40" y="252" width="{width - 160}" height="2" fill="{SILVER}" opacity="0.35"/>
  <text x="44" y="286" font-family="Rajdhani, sans-serif" font-size="20" letter-spacing="9" fill="{SILVER}">BEYOND THE SYSTEM. INTO THE CITY.</text>
</svg>
"""


def mark_svg(fg=WHITE, accent=RED, glow=True):
    filt = """
  <defs>
    <linearGradient id="metal" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#E8EAF0"/>
      <stop offset="0.55" stop-color="#9299A8"/>
      <stop offset="1" stop-color="#E8EAF0"/>
    </linearGradient>
    <linearGradient id="red" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#FF3D81"/>
      <stop offset="0.5" stop-color="#FF1744"/>
      <stop offset="1" stop-color="#8C102B"/>
    </linearGradient>
    <filter id="mglow" x="-40%" y="-40%" width="180%" height="180%">
      <feGaussianBlur stdDeviation="7" result="b"/>
      <feColorMatrix in="b" type="matrix" values="1 0 0 0 0  0 0.09 0 0 0  0 0.27 0 0 0  0 0 0 0.9 0" result="r"/>
      <feMerge><feMergeNode in="r"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>""" if glow else """
  <defs>
    <linearGradient id="metal" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#E8EAF0"/><stop offset="1" stop-color="#9299A8"/>
    </linearGradient>
    <linearGradient id="red" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#FF1744"/><stop offset="1" stop-color="#8C102B"/>
    </linearGradient>
  </defs>"""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <title>NIGHT CITY mark</title>{filt}
  <g {'filter="url(#mglow)"' if glow else ''}>
    <!-- angled city-gate frame -->
    <path d="M128 12 L222 62 L222 194 L128 244 L34 194 L34 62 Z"
          fill="{DARK}" stroke="url(#red)" stroke-width="5"/>
    <path d="M128 30 L204 70 L204 186 L128 226 L52 186 L52 70 Z"
          fill="none" stroke="{fg}" stroke-opacity="0.22" stroke-width="1.5"/>
    <!-- skyline N: three towers and a light trail -->
    <path d="M76 186 V98 L92 98 V186 Z" fill="url(#metal)"/>
    <path d="M164 186 V74 L180 74 V186 Z" fill="url(#metal)"/>
    <path d="M92 98 L164 74 L164 96 L92 120 Z" fill="url(#red)"/>
    <path d="M112 186 V126 L128 126 V186 Z" fill="url(#red)" opacity="0.9"/>
    <rect x="76" y="192" width="104" height="4" fill="url(#red)"/>
    <rect x="118" y="100" width="20" height="4" fill="{fg}" opacity="0.9"/>
    <!-- circuit node -->
    <circle cx="128" cy="48" r="5" fill="{accent}"/>
    <path d="M128 36 V22 M128 60 V74" stroke="{accent}" stroke-width="2"/>
  </g>
</svg>
"""


def main():
    (OUT / "nightcity-logo.svg").write_text(logo_svg(), encoding="utf-8")
    (OUT / "nightcity-logo-mono.svg").write_text(
        logo_svg(fg=WHITE, accent=WHITE, glow=False), encoding="utf-8")
    (OUT / "nightcity-mark.svg").write_text(mark_svg(), encoding="utf-8")
    (OUT / "nightcity-mark-mono.svg").write_text(
        mark_svg(fg=WHITE, accent=WHITE, glow=False), encoding="utf-8")

    if not shutil.which("rsvg-convert"):
        raise SystemExit("rsvg-convert is required to render the brand PNGs "
                         "(install librsvg2-bin / librsvg2-tools)")
    for svg, png, width, height in (
        ("nightcity-logo.svg", "nightcity-logo.png", 1560, 300),
        ("nightcity-mark.svg", "nightcity-mark.png", 512, 512),
    ):
        subprocess.run(
            ["rsvg-convert", "-w", str(width), "-h", str(height),
             "-o", str(OUT / png), str(OUT / svg)],
            check=True,
        )
    print("branding written to", OUT)


if __name__ == "__main__":
    main()
