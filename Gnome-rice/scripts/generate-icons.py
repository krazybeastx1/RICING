#!/usr/bin/env python3
"""Build NightCity-Icons: an original, curated icon theme.

Design language
  * 256x256 canvas, squircle tile, graphite gradient, hairline steel border
  * a single neon-red rim light on the top edge
  * geometric glyphs, 10px stroke, soft-white with red/cyan accents

The theme intentionally ships a curated set (apps, places, categories) and
inherits Adwaita/hicolor for everything else, so no third-party artwork is
copied and unknown icons still resolve.

Outputs: icons/NightCity-Icons/{scalable,64x64,128x128,256x256}/...
"""
from __future__ import annotations

import json
import math
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOKENS = json.loads((ROOT / "design" / "tokens.json").read_text(encoding="utf-8"))
C = TOKENS["colors"]
OUT = ROOT / "icons" / "NightCity-Icons"

WHITE = C["soft-white"]
RED = C["neon-red"]
CYAN = C["holo-cyan"]
PURPLE = C["electric-purple"]
STEEL = C["border-gray"]
GRAPHITE = C["dark-graphite"]
BLACK = C["night-black"]


def tile(inner: str, accent: str = RED) -> str:
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <defs>
    <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{GRAPHITE}"/>
      <stop offset="1" stop-color="{BLACK}"/>
    </linearGradient>
    <linearGradient id="rim" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="{accent}" stop-opacity="0.15"/>
      <stop offset="0.5" stop-color="{accent}" stop-opacity="0.95"/>
      <stop offset="1" stop-color="{accent}" stop-opacity="0.15"/>
    </linearGradient>
    <radialGradient id="wash" cx="0.5" cy="0.15" r="0.75">
      <stop offset="0" stop-color="{accent}" stop-opacity="0.16"/>
      <stop offset="1" stop-color="{accent}" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect x="12" y="12" width="232" height="232" rx="54" fill="url(#tile)"/>
  <rect x="12" y="12" width="232" height="232" rx="54" fill="url(#wash)"/>
  <rect x="12.75" y="12.75" width="230.5" height="230.5" rx="53.25" fill="none" stroke="{STEEL}" stroke-width="1.5"/>
  <path d="M66 13 H190" stroke="url(#rim)" stroke-width="3" stroke-linecap="round"/>
  <g fill="none" stroke="{WHITE}" stroke-width="9" stroke-linecap="round" stroke-linejoin="round">
{inner}
  </g>
</svg>
"""


def dot(cx, cy, r, color=RED):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{color}" stroke="none"/>'


def gear_path(cx, cy, r_out, r_in, teeth):
    pts = []
    step = 2 * math.pi / teeth
    for i in range(teeth):
        a = i * step
        for frac, r in ((-0.34, r_in), (-0.22, r_out), (0.22, r_out), (0.34, r_in)):
            ang = a + frac * step
            pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"
    return d


GLYPHS: dict[str, str] = {}

GLYPHS["utilities-terminal"] = f"""
    <path d="M62 84 H194 V172 H62 Z" stroke="{STEEL}"/>
    <path d="M78 108 L104 128 L78 148"/>
    <path d="M120 152 H154" stroke="{RED}"/>
    {dot(180, 84, 5)}
"""

GLYPHS["system-file-manager"] = f"""
    <path d="M54 90 H108 L120 76 H202 V176 H54 Z"/>
    <path d="M54 104 H202" stroke="{STEEL}"/>
    <path d="M76 132 H150" stroke="{RED}" stroke-width="7"/>
"""

GLYPHS["preferences-system"] = f"""
    <path d="{gear_path(128, 128, 84, 66, 8)}"/>
    <circle cx="128" cy="128" r="24" stroke="{RED}"/>
"""

GLYPHS["web-browser"] = f"""
    <circle cx="128" cy="128" r="66"/>
    <ellipse cx="128" cy="128" rx="28" ry="66" stroke="{STEEL}"/>
    <path d="M64 108 H192 M64 148 H192" stroke="{STEEL}"/>
    <path d="M70 180 C110 156 152 100 196 82" stroke="{RED}" stroke-width="7"/>
    {dot(196, 82, 8)}
"""

GLYPHS["accessories-text-editor"] = f"""
    <path d="M76 56 H156 L188 88 V200 H76 Z"/>
    <path d="M156 56 V88 H188" stroke="{STEEL}"/>
    <path d="M100 120 H162 M100 146 H162 M100 172 H138" stroke="{STEEL}" stroke-width="7"/>
    <path d="M150 176 L196 130 L210 144 L164 190 L146 194 Z" stroke="{RED}" stroke-width="7"/>
"""

GLYPHS["system-software-install"] = f"""
    <path d="M128 58 L196 96 V168 L128 206 L60 168 V96 Z"/>
    <path d="M60 96 L128 134 L196 96 M128 134 V206" stroke="{STEEL}" stroke-width="7"/>
    <path d="M94 78 L162 116" stroke="{RED}" stroke-width="7"/>
"""

GLYPHS["applications-graphics"] = f"""
    <rect x="58" y="62" width="140" height="132" rx="12"/>
    <circle cx="100" cy="104" r="14" stroke="{RED}"/>
    <path d="M58 168 L104 124 L136 152 L158 132 L198 168" stroke="{STEEL}"/>
"""

GLYPHS["applications-multimedia"] = f"""
    <rect x="56" y="72" width="144" height="112" rx="14"/>
    <path d="M112 104 L160 128 L112 152 Z" stroke="{RED}"/>
"""

GLYPHS["accessories-calculator"] = f"""
    <rect x="66" y="52" width="124" height="152" rx="12"/>
    <rect x="84" y="72" width="88" height="30" rx="4" stroke="{RED}"/>
    <path d="M96 132 H110 M120 132 H134 M144 132 H158 M96 158 H110 M120 158 H134 M144 158 H158 M96 184 H110 M120 184 H134 M144 184 H158" stroke-width="7"/>
"""

GLYPHS["package-x-generic"] = f"""
    <path d="M60 92 H196 V188 H60 Z"/>
    <path d="M60 92 L78 68 H178 L196 92" stroke="{STEEL}"/>
    <path d="M112 92 V188 M144 92 V188" stroke="{STEEL}" stroke-width="5"/>
    <path d="M98 122 H158 M98 152 H158" stroke="{RED}" stroke-width="7"/>
"""

GLYPHS["utilities-system-monitor"] = f"""
    <rect x="54" y="66" width="148" height="124" rx="10"/>
    <path d="M70 150 H94 L108 104 L128 178 L146 128 L160 150 H186" stroke="{RED}"/>
    <path d="M70 88 H104" stroke="{STEEL}" stroke-width="6"/>
"""

GLYPHS["system-shutdown"] = f"""
    <path d="M128 58 V128" stroke="{RED}"/>
    <path d="M92 82 A58 58 0 1 0 164 82" />
"""

GLYPHS["network-wireless"] = f"""
    <path d="M62 112 A96 96 0 0 1 194 112" stroke="{STEEL}"/>
    <path d="M86 138 A62 62 0 0 1 170 138" />
    <path d="M108 162 A32 32 0 0 1 148 162" stroke="{RED}"/>
    {dot(128, 186, 8)}
"""

GLYPHS["preferences-system-time"] = f"""
    <circle cx="128" cy="128" r="70"/>
    <path d="M128 84 V130 L162 152" stroke="{RED}"/>
    <path d="M128 58 V48 M128 208 V198 M58 128 H48 M208 128 H198" stroke="{STEEL}" stroke-width="7"/>
"""

GLYPHS["audio-x-generic"] = f"""
    <path d="M104 164 V82 L176 64 V146" stroke="{WHITE}"/>
    <ellipse cx="88" cy="166" rx="18" ry="14" stroke="{RED}"/>
    <ellipse cx="160" cy="148" rx="18" ry="14" stroke="{RED}"/>
"""

GLYPHS["camera-photo"] = f"""
    <path d="M52 92 H92 L106 74 H150 L164 92 H204 V184 H52 Z"/>
    <circle cx="128" cy="138" r="34"/>
    <circle cx="128" cy="138" r="16" stroke="{RED}"/>
    {dot(184, 108, 5)}
"""

GLYPHS["applications-office"] = f"""
    <path d="M70 60 H150 L186 96 V196 H70 Z"/>
    <path d="M150 60 V96 H186" stroke="{STEEL}"/>
    <path d="M94 124 H162 M94 150 H162 M94 176 H140" stroke-width="7"/>
    {dot(166, 176, 7)}
"""


def gear_path(cx, cy, r_out, r_in, teeth):
    pts = []
    step = 2 * math.pi / teeth
    for i in range(teeth):
        a = i * step
        for frac, r in ((-0.34, r_in), (-0.22, r_out), (0.22, r_out), (0.34, r_in)):
            ang = a + frac * step
            pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"
    return d


# Places -------------------------------------------------------------------
def folder(open_lid=False):
    if open_lid:
        return f"""
    <path d="M44 92 H110 L124 76 H204 L184 186 H44 Z" stroke="{STEEL}"/>
    <path d="M44 92 L74 186" stroke="{STEEL}"/>
    <path d="M64 108 H196 L184 186 H74 Z" fill="{GRAPHITE}" stroke="{RED}" stroke-width="7"/>
"""
    return f"""
    <path d="M44 82 H108 L122 66 H206 V190 H44 Z"/>
    <path d="M44 100 H206" stroke="{STEEL}"/>
    <path d="M70 132 H140" stroke="{RED}" stroke-width="7"/>
"""


PLACES = {
    "folder": folder(False),
    "folder-open": folder(True),
    "folder-drag-accept": folder(True) + f'<path d="M104 138 H176" stroke="{CYAN}" stroke-width="8"/>',
    "folder-visiting": folder(False) + f'{dot(176, 70, 9)}',
    "user-home": f"""
    <path d="M50 124 L128 58 L206 124"/>
    <path d="M74 112 V194 H182 V112" stroke="{STEEL}"/>
    <path d="M108 194 V148 H148 V194" stroke="{RED}"/>
""",
    "user-trash": f"""
    <path d="M72 84 H184 L172 200 H84 Z"/>
    <path d="M62 84 H194 M104 84 V66 H152 V84" stroke="{STEEL}"/>
    <path d="M108 116 V172 M128 116 V172 M148 116 V172" stroke="{RED}" stroke-width="6"/>
""",
    "user-trash-full": f"""
    <path d="M72 84 H184 L172 200 H84 Z"/>
    <path d="M62 84 H194 M104 84 V66 H152 V84" stroke="{STEEL}"/>
    <path d="M100 110 L156 176 M156 110 L100 176" stroke="{RED}" stroke-width="8"/>
""",
    "drive-harddisk": f"""
    <rect x="52" y="82" width="152" height="96" rx="12"/>
    <path d="M52 132 H204" stroke="{STEEL}"/>
    {dot(176, 154, 8)}
    <path d="M74 108 H140" stroke="{CYAN}" stroke-width="6"/>
""",
    "network-server": f"""
    <rect x="66" y="52" width="124" height="58" rx="8"/>
    <rect x="66" y="122" width="124" height="58" rx="8"/>
    <path d="M86 82 H156 M86 152 H156" stroke="{STEEL}" stroke-width="7"/>
    {dot(170, 82, 6)}{dot(170, 152, 6)}
""",
    "user-bookmarks": f"""
    <path d="M72 52 H184 V206 L128 172 L72 206 Z"/>
    <path d="M100 92 H156" stroke="{RED}" stroke-width="7"/>
""",
    "folder-remote": folder(False) + f'<path d="M148 150 A26 26 0 0 1 186 150" stroke="{CYAN}" stroke-width="6"/>{dot(167, 164, 6)}',
}

# Categories ---------------------------------------------------------------
CATEGORIES = {
    "applications-utilities": f"""
    <path d="M76 88 H180 V184 H76 Z"/>
    <path d="M96 112 L114 126 L96 140" stroke="{RED}"/>
    <path d="M126 142 H158" stroke="{STEEL}" stroke-width="7"/>
""",
    "applications-system": f"""
    <rect x="58" y="72" width="140" height="108" rx="10"/>
    <path d="M58 108 H198" stroke="{STEEL}"/>
    <path d="M96 140 H112 M124 140 H140 M152 140 H168" stroke="{RED}" stroke-width="7"/>
""",
    "applications-internet": f"""
    <circle cx="128" cy="128" r="66"/>
    <path d="M62 128 H194 M128 62 C160 92 160 164 128 194 C96 164 96 92 128 62" stroke="{CYAN}" stroke-width="6"/>
""",
    "applications-multimedia": f"""
    <circle cx="128" cy="128" r="66"/>
    <circle cx="128" cy="128" r="18" stroke="{RED}"/>
    <path d="M150 106 L196 82 V174 L150 150" stroke="{STEEL}" stroke-width="7"/>
""",
    "applications-graphics": f"""
    <path d="M62 174 L104 88 L146 174 Z" stroke="{RED}"/>
    <circle cx="166" cy="96" r="22" stroke="{CYAN}"/>
""",
    "applications-office": f"""
    <rect x="58" y="58" width="140" height="140" rx="10"/>
    <path d="M84 96 H168 M84 126 H168 M84 156 H132" stroke="{RED}" stroke-width="7"/>
""",
}


APP_ALIASES = {
    "org.gnome.Terminal": "utilities-terminal",
    "org.gnome.Console": "utilities-terminal",
    "org.gnome.Ptyxis": "utilities-terminal",
    "gnome-terminal": "utilities-terminal",
    "Alacritty": "utilities-terminal",
    "kitty": "utilities-terminal",
    "org.gnome.Nautilus": "system-file-manager",
    "nautilus": "system-file-manager",
    "org.gnome.Settings": "preferences-system",
    "gnome-control-center": "preferences-system",
    "org.gnome.TextEditor": "accessories-text-editor",
    "org.gnome.gedit": "accessories-text-editor",
    "firefox": "web-browser",
    "org.mozilla.firefox": "web-browser",
    "org.gnome.Epiphany": "web-browser",
    "org.gnome.Software": "system-software-install",
    "org.gnome.Evince": "applications-graphics",
    "org.gnome.Loupe": "applications-graphics",
    "org.gnome.Totem": "applications-multimedia",
    "org.gnome.Showtime": "applications-multimedia",
    "org.gnome.Calculator": "accessories-calculator",
    "org.gnome.FileRoller": "package-x-generic",
    "org.gnome.SystemMonitor": "utilities-system-monitor",
    "gnome-system-monitor": "utilities-system-monitor",
    "org.gnome.clocks": "preferences-system-time",
    "org.gnome.Camera": "camera-photo",
    "org.gnome.Logs": "applications-office",
    "system-lock-screen": "system-shutdown",
    "network-wireless-symbolic": "network-wireless",
}

PLACE_ALIASES = {
    "user-desktop": "folder",
    "user-home-symbolic": "user-home",
    "folder-symbolic": "folder",
    "folder-documents": "folder",
    "folder-download": "folder",
    "folder-music": "folder",
    "folder-pictures": "folder",
    "folder-videos": "folder",
    "folder-publicshare": "folder",
    "folder-templates": "folder",
    "network-workgroup": "network-server",
}

PNG_SIZES = (64, 128, 256)


def write_svg(path: Path, body: str, accent: str = RED) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(tile(body, accent), encoding="utf-8")


def render(svg: Path, png: Path, size: int) -> None:
    png.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), "-o", str(png), str(svg)],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def build_group(context: str, items: dict[str, str], accents: dict[str, str] | None = None) -> list[str]:
    names = []
    for name, body in items.items():
        accent = (accents or {}).get(name, RED)
        svg = OUT / "scalable" / context / f"{name}.svg"
        write_svg(svg, body, accent)
        for size in PNG_SIZES:
            render(svg, OUT / f"{size}x{size}" / context / f"{name}.png", size)
        names.append(name)
    return names


def main() -> int:
    if OUT.exists():
        shutil.rmtree(OUT)
    apps = build_group("apps", GLYPHS)
    places = build_group("places", PLACES, {"folder-remote": CYAN, "drive-harddisk": CYAN})
    cats = build_group("categories", CATEGORIES)

    # Aliases are copies, not symlinks: themes are often zipped on Windows.
    for alias, target in APP_ALIASES.items():
        for size in (0, *PNG_SIZES):
            directory = OUT / ("scalable" if size == 0 else f"{size}x{size}") / "apps"
            ext = "svg" if size == 0 else "png"
            src = directory / f"{target}.{ext}"
            dst = directory / f"{alias}.{ext}"
            if src.exists() and not dst.exists():
                shutil.copy2(src, dst)
    for alias, target in PLACE_ALIASES.items():
        for size in (0, *PNG_SIZES):
            directory = OUT / ("scalable" if size == 0 else f"{size}x{size}") / "places"
            ext = "svg" if size == 0 else "png"
            src = directory / f"{target}.{ext}"
            dst = directory / f"{alias}.{ext}"
            if src.exists() and not dst.exists():
                shutil.copy2(src, dst)

    dirs = []
    for context in ("apps", "places", "categories"):
        dirs.append(f"{context}/scalable")
        for size in PNG_SIZES:
            dirs.append(f"{size}x{size}/{context}")

    index = ["[Icon Theme]",
             "Name=NightCity-Icons",
             "Comment=NIGHT CITY — neon-red cyberpunk icon theme",
             "Inherits=Adwaita,hicolor",
             "Example=utilities-terminal",
             "",
             "Directories=" + ",".join(dirs),
             ""]
    for d in dirs:
        parts = d.split("/")
        context = parts[0] if parts[0] in ("apps", "places", "categories") else parts[1]
        ctx = {"apps": "Applications", "places": "Places", "categories": "Categories"}[context]
        if "scalable" in d:
            index += [f"[{d}]", f"Context={ctx}", "Size=256", "MinSize=16", "MaxSize=512",
                      "Type=Scalable", ""]
        else:
            size = int(d.split("x")[0])
            index += [f"[{d}]", f"Context={ctx}", f"Size={size}", f"MinSize={size}",
                      f"MaxSize={size}", "Type=Fixed", ""]
    (OUT / "index.theme").write_text("\n".join(index) + "\n", encoding="utf-8")

    total = sum(1 for _ in OUT.rglob("*") if _.is_file())
    print(f"icons  {len(apps)} apps, {len(places)} places, {len(cats)} categories, "
          f"{len(APP_ALIASES)} app aliases, {len(PLACE_ALIASES)} place aliases")
    print(f"icons  {total} files in {OUT.relative_to(ROOT)}")

    try:
        subprocess.run(["gtk-update-icon-cache", "-f", "-t", str(OUT)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        print("icons  cache built")
    except Exception as exc:  # not fatal for packaging
        print(f"icons  cache skipped: {exc}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
