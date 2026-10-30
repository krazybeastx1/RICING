#!/usr/bin/env bash
# NIGHT CITY — project validator.
#
# Checks the source tree, every generated artifact and (optionally) a complete
# staged install/uninstall cycle in a throw-away HOME. It never touches the
# real desktop, GDM, Plymouth, the initramfs or system files.
#
#   ./scripts/validate.sh              # source + artifacts
#   ./scripts/validate.sh --staged     # + install/uninstall rehearsal
#   ./scripts/validate.sh --release    # + require documentation set
#   ./scripts/validate.sh --quick      # skip CSS parsing (no GTK needed)
set -Eeuo pipefail

NC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$NC_SCRIPT_DIR/lib/common.sh"

RELEASE=0
STAGED=0
QUICK=0

usage() {
    cat <<EOF
${NC_NAME} validator v${NC_VERSION}

Usage: ./scripts/validate.sh [options]

  --staged      Also install into a temporary HOME, verify, uninstall.
  --release     Require README/CHANGELOG/VERSION/docs (release gate).
  --quick       Skip GTK CSS parsing.
  --no-color    Disable ANSI colour.
  -h, --help    This text.

Exit status: 0 when every required check passes, 1 otherwise.
Nothing is installed outside a temporary directory.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --staged) STAGED=1 ;;
        --release) RELEASE=1 ;;
        --quick) QUICK=1 ;;
        --no-color) NO_COLOR=1; NC_R=''; NC_C=''; NC_W=''; NC_D=''; NC_B=''; NC_0='' ;;
        -h|--help) usage; exit 0 ;;
        *) nc_die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

nc_banner
nc_paths
nc_detect

FAILED=0
WARNED=0
PASSED=0
QUIET_SECTION=""

section() {
    printf '\n%s%s%s\n' "$NC_B" "$*" "$NC_0"
}

pass() {
    PASSED=$((PASSED + 1))
    printf '  %s✓%s %s\n' "$NC_C" "$NC_0" "$*"
}

fail() {
    FAILED=$((FAILED + 1))
    printf '  %s✗%s %s\n' "$NC_R" "$NC_0" "$*"
}

warn() {
    WARNED=$((WARNED + 1))
    printf '  %s!%s %s\n' "$NC_R" "$NC_0" "$*"
}

# ---------------------------------------------------------------------------
# 1. Shell script syntax and executable bits
# ---------------------------------------------------------------------------
section "Shell scripts"

shopt -s nullglob
sh_files=("$NC_ROOT"/scripts/*.sh "$NC_ROOT"/scripts/lib/*.sh)
if [ "${#sh_files[@]}" -eq 0 ]; then
    fail "no shell scripts found"
fi
for f in "${sh_files[@]}"; do
    rel="${f#"$NC_ROOT"/}"
    if bash -n "$f" 2>/tmp/nightcity-bashn.$$; then
        pass "bash -n $rel"
    else
        fail "bash -n $rel"
        sed 's/^/      /' "/tmp/nightcity-bashn.$$"
    fi
    if [ -x "$f" ] && [ "$rel" != "scripts/lib/common.sh" ]; then
        :
    elif [ "$rel" != "scripts/lib/common.sh" ]; then
        warn "$rel is not executable (chmod +x)"
    fi
done
rm -f "/tmp/nightcity-bashn.$$"
shopt -u nullglob

# ---------------------------------------------------------------------------
# 2. Python syntax
# ---------------------------------------------------------------------------
section "Python build tools"

py_files=("$NC_ROOT"/scripts/*.py)
for f in "${py_files[@]}"; do
    rel="${f#"$NC_ROOT"/}"
    if python3 -m py_compile "$f" 2>/tmp/nightcity-py.$$; then
        pass "python $rel"
    else
        fail "python $rel"
        sed 's/^/      /' "/tmp/nightcity-py.$$"
    fi
done
rm -f "/tmp/nightcity-py.$$"
find "$NC_ROOT/scripts" -maxdepth 2 -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3. Artifact and content validation
# ---------------------------------------------------------------------------
section "Artifacts, palette, CSS and assets"

COUNT_FILE="$(mktemp "${TMPDIR:-/tmp}/nightcity-counts.XXXXXX")"
set +e
python3 - "$NC_ROOT" "$RELEASE" "$QUICK" "$COUNT_FILE" <<'PY'
from __future__ import annotations

import configparser
import json
import re
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(sys.argv[1])
release = sys.argv[2] == "1"
quick = sys.argv[3] == "1"
count_file = Path(sys.argv[4])

passed = 0
failed = 0
warned = 0


def ok(msg: str) -> None:
    global passed
    passed += 1
    print(f"  \033[38;2;0;229;255m✓\033[0m {msg}")


def bad(msg: str) -> None:
    global failed
    failed += 1
    print(f"  \033[38;2;255;23;68m✗\033[0m {msg}")


def maybe(msg: str) -> None:
    global warned
    warned += 1
    print(f"  \033[38;2;255;23;68m!\033[0m {msg}")
def read(rel: str) -> str:
    return (root / rel).read_text(encoding="utf-8", errors="replace")


# --- tokens -----------------------------------------------------------------
tokens_path = root / "design" / "tokens.json"
try:
    tokens = json.loads(tokens_path.read_text(encoding="utf-8"))
    required = {"colors", "typography", "geometry"}
    if required - set(tokens):
        bad(f"design/tokens.json missing groups: {sorted(required - set(tokens))}")
    else:
        palette = tokens["colors"]
        for key in ("night-black", "neon-red", "soft-white", "holo-cyan"):
            if key not in palette:
                bad(f"design/tokens.json missing color '{key}'")
            elif not re.fullmatch(r"#[0-9A-Fa-f]{6}", str(palette[key])):
                bad(f"design/tokens.json color '{key}' is not #RRGGBB")
        if palette.get("neon-red", "").upper() != "#FF1744":
            bad("design/tokens.json: neon-red must remain #FF1744")
        else:
            ok("design tokens parse; palette signature intact")
except FileNotFoundError:
    bad("design/tokens.json is missing")
except Exception as exc:  # noqa: BLE001
    bad(f"design/tokens.json is invalid: {exc}")

for rel in (
    "design/base/gnome-shell-dark.css",
    "design/base/gtk3-adwaita-dark.css",
    "design/base/gtk4-default-dark.css",
    "design/overrides/shell.css",
    "design/overrides/gtk3.css",
    "design/overrides/gtk4.css",
    "design/overrides/gtk4-user.css",
    "design/overrides/gdm.css",
):
    p = root / rel
    if p.is_file() and p.stat().st_size > 100:
        ok(f"{rel} present ({p.stat().st_size // 1024} KiB)")
    else:
        bad(f"{rel} missing or empty")

# --- generated CSS ----------------------------------------------------------
css_outputs = {
    "themes/NightCity-Shell/gnome-shell/gnome-shell.css": "shell",
    "themes/NightCity-GTK/gtk-3.0/gtk.css": "gtk3",
    "themes/NightCity-GTK/gtk-3.0/gtk-dark.css": "gtk3",
    "themes/NightCity-GTK/gtk-4.0/gtk.css": "gtk4",
    "themes/NightCity-GTK/gtk-4.0/gtk-dark.css": "gtk4",
    "themes/NightCity-GTK/gtk-4.0-user.css": "gtk4-user",
    "gdm/theme/gnome-shell.css": "shell",
}
for rel, kind in css_outputs.items():
    p = root / rel
    if not p.is_file():
        bad(f"missing generated stylesheet: {rel}")
        continue
    text = p.read_text(encoding="utf-8", errors="replace")
    if p.stat().st_size < 20_000:
        bad(f"{rel} is suspiciously small ({p.stat().st_size} bytes)")
    elif "{{" in text or "}}" in text:
        bad(f"{rel} still contains unresolved template placeholders")
    elif "#FF1744" not in text and "#ff1744" not in text:
        bad(f"{rel} does not contain the neon-red signal colour")
    elif "/home/" in text:
        bad(f"{rel} contains an absolute home path")
    else:
        ok(f"{rel} ({p.stat().st_size // 1024} KiB, {kind})")

# shell/gdm specific selectors
shell_css = read("themes/NightCity-Shell/gnome-shell/gnome-shell.css") if (root / "themes/NightCity-Shell/gnome-shell/gnome-shell.css").is_file() else ""
for needle in ("-st-accent-color", "#panel", ".popup-menu", ".overview"):
    if needle not in shell_css:
        bad(f"shell stylesheet lacks expected selector/token: {needle}")
if shell_css.count("{") != shell_css.count("}"):
    bad("shell stylesheet has unbalanced braces")
else:
    ok("shell stylesheet structure and GNOME 50 accent tokens present")

gdm_css_path = root / "gdm/theme/gnome-shell.css"
if gdm_css_path.is_file():
    gdm_css = gdm_css_path.read_text(encoding="utf-8", errors="replace")
    if "file:///usr/share/backgrounds/nightcity/nightline.png" not in gdm_css:
        bad("GDM stylesheet does not reference the installed greeter wallpaper path")
    elif "nightcity-01-nightline.png" in gdm_css:
        bad("GDM stylesheet references a source-tree wallpaper path")
    elif "#lockDialogGroup" not in gdm_css:
        bad("GDM stylesheet lacks #lockDialogGroup background")
    else:
        ok("GDM stylesheet references /usr/share/backgrounds/nightcity/nightline.png")

# CSS parse through the actual GTK parsers, in isolated processes.
def parse_css(toolkit: str, rel: str) -> tuple[bool, str]:
    code = f"""
import gi, sys
gi.require_version("Gtk", "{toolkit}")
from gi.repository import Gtk
provider = Gtk.CssProvider()
errors = []
provider.connect("parsing-error", lambda p, section, error: errors.append(str(error)))
provider.load_from_path(sys.argv[1])
if errors:
    print("\\n".join(errors[:5]))
    raise SystemExit(1)
"""
    proc = subprocess.run(
        [sys.executable, "-c", code, str(root / rel)],
        capture_output=True, text=True,
    )
    return proc.returncode == 0, (proc.stderr or proc.stdout).strip()


if quick:
    maybe("CSS parsing skipped (--quick)")
else:
    parse_plan = [
        ("3.0", "themes/NightCity-GTK/gtk-3.0/gtk.css"),
        ("3.0", "themes/NightCity-GTK/gtk-3.0/gtk-dark.css"),
        ("4.0", "themes/NightCity-GTK/gtk-4.0/gtk.css"),
        ("4.0", "themes/NightCity-GTK/gtk-4.0/gtk-dark.css"),
        ("4.0", "themes/NightCity-GTK/gtk-4.0-user.css"),
    ]
    for toolkit, rel in parse_plan:
        if not (root / rel).is_file():
            continue
        good, detail = parse_css(toolkit, rel)
        if good:
            ok(f"GTK {toolkit} parsed {rel.split('/')[-2]}/{rel.split('/')[-1]} with 0 errors")
        else:
            bad(f"GTK {toolkit} rejected {rel}: {detail[:400]}")

# --- themes metadata --------------------------------------------------------
for rel in ("themes/NightCity-GTK/index.theme", "themes/NightCity-Shell/index.theme"):
    p = root / rel
    if not p.is_file():
        bad(f"missing {rel}")
        continue
    cp = configparser.ConfigParser()
    try:
        cp.read(p)
        if cp.get("Desktop Entry", "Type", fallback="") != "X-GNOME-Metatheme":
            bad(f"{rel}: Type is not X-GNOME-Metatheme")
        else:
            ok(f"{rel}: valid metatheme")
    except Exception as exc:  # noqa: BLE001
        bad(f"{rel}: {exc}")

# --- icon theme -------------------------------------------------------------
icon_root = root / "icons/NightCity-Icons"
icon_index = icon_root / "index.theme"
if not icon_index.is_file():
    bad("icons/NightCity-Icons/index.theme is missing")
else:
    cp = configparser.ConfigParser()
    cp.read(icon_index)
    if cp.get("Icon Theme", "Name", fallback="") != "NightCity-Icons":
        bad("icon index.theme: wrong Name")
    dirs = [d.strip() for d in cp.get("Icon Theme", "Directories", fallback="").split(",") if d.strip()]
    if not dirs:
        bad("icon index.theme: no Directories")
    missing = []
    empty = []
    for d in dirs:
        dp = icon_root / d
        if not dp.is_dir():
            missing.append(d)
        elif not any(p.is_file() for p in dp.iterdir()):
            empty.append(d)
    if missing:
        bad(f"icon theme: missing directories {missing[:4]}")
    elif empty:
        bad(f"icon theme: empty directories {empty[:4]}")
    else:
        pngs = list(icon_root.rglob("*.png"))
        svgs = list(icon_root.rglob("*.svg"))
        apps = list((icon_root / "256x256/apps").glob("*.png"))
        if len(pngs) < 200 or len(svgs) < 20:
            bad(f"icon theme too small: {len(pngs)} PNG, {len(svgs)} SVG")
        elif len(apps) < 15:
            bad(f"icon theme: only {len(apps)} app icons at 256px")
        else:
            ok(f"icon theme: {len(pngs)} PNG + {len(svgs)} SVG across {len(dirs)} directories")
        # Validate PNG headers and declared sizes.
        bad_png = 0
        for p in pngs:
            with p.open("rb") as fh:
                head = fh.read(24)
            if head[:8] != b"\x89PNG\r\n\x1a\n":
                bad_png += 1
                continue
            w, h = struct.unpack(">II", head[16:24])
            parent = p.parent.name
            m = re.fullmatch(r"(\d+)x\1", parent)
            if m and (w != int(m.group(1)) or h != int(m.group(1))):
                bad_png += 1
            if w > 512 or h > 512:
                bad_png += 1
        if bad_png:
            bad(f"icon theme: {bad_png} malformed or mis-sized PNG file(s)")
        else:
            ok("icon theme: every PNG header and declared size is valid")

# --- cursors ----------------------------------------------------------------
cursor_root = root / "cursors/NightCity-Cursor"
cursor_files = sorted((cursor_root / "cursors").glob("*")) if (cursor_root / "cursors").is_dir() else []
if len(cursor_files) < 40:
    bad(f"cursor theme: only {len(cursor_files)} cursor names")
else:
    broken = []
    bad_magic = []
    for p in cursor_files:
        if p.is_symlink():
            if not p.exists():
                broken.append(p.name)
            continue
        if not p.is_file():
            continue
        with p.open("rb") as fh:
            if fh.read(4) != b"Xcur":
                bad_magic.append(p.name)
    if broken:
        bad(f"cursor theme: broken symlinks {broken[:4]}")
    elif bad_magic:
        bad(f"cursor theme: invalid Xcursor files {bad_magic[:4]}")
    else:
        ok(f"cursor theme: {len(cursor_files)} names, valid Xcursor headers, no broken links")
for rel in ("cursors/NightCity-Cursor/index.theme", "cursors/NightCity-Cursor/cursor.theme"):
    if not (root / rel).is_file():
        bad(f"missing {rel}")
if (cursor_root / "cursor.theme").is_file():
    cp = configparser.ConfigParser()
    cp.read(cursor_root / "cursor.theme")
    if cp.get("Icon Theme", "Name", fallback="") != "NightCity-Cursor":
        bad("cursor cursor.theme: wrong Name")
    else:
        ok("cursor theme metadata is valid")

# --- wallpapers -------------------------------------------------------------
wall_root = root / "assets/wallpapers"
walls = sorted(wall_root.glob("nightcity-*.png"))
if len(walls) < 6:
    bad(f"only {len(walls)} wallpapers; at least 6 required")
else:
    problems = []
    try:
        from PIL import Image, ImageStat
    except Exception:  # noqa: BLE001
        Image = None  # type: ignore[assignment]
    for p in walls:
        with p.open("rb") as fh:
            head = fh.read(24)
        if head[:8] != b"\x89PNG\r\n\x1a\n":
            problems.append(f"{p.name}: bad PNG header")
            continue
        w, h = struct.unpack(">II", head[16:24])
        if (w, h) != (3840, 2160):
            problems.append(f"{p.name}: {w}x{h}, expected 3840x2160")
        if p.stat().st_size < 300_000:
            problems.append(f"{p.name}: only {p.stat().st_size // 1024} KiB")
        if Image is not None:
            im = Image.open(p).convert("RGB")
            im.thumbnail((480, 480))
            stat = ImageStat.Stat(im)
            r, g, b = stat.mean
            if not (r > g * 1.08 and r > b * 1.08):
                problems.append(f"{p.name}: not red-dominant (R={r:.0f} G={g:.0f} B={b:.0f})")
            im.close()
    if problems:
        for msg in problems[:8]:
            bad(f"wallpaper {msg}")
    else:
        ok(f"{len(walls)} wallpapers: 3840x2160, red-dominant, valid PNG")

# --- branding, fonts, licenses ---------------------------------------------
for rel in (
    "assets/branding/nightcity-logo.svg",
    "assets/branding/nightcity-mark.svg",
    "assets/branding/nightcity-logo.png",
    "assets/branding/nightcity-mark.png",
    "assets/branding/palette.html",
):
    p = root / rel
    if p.is_file() and p.stat().st_size > 500:
        try:
            if p.suffix == ".svg":
                ET.parse(p)
        except Exception as exc:  # noqa: BLE001
            bad(f"{rel}: invalid SVG ({exc})")
        else:
            ok(f"{rel} present")
    else:
        bad(f"{rel} missing or empty")

font_root = root / "assets/fonts"
families = [p for p in font_root.iterdir() if p.is_dir()] if font_root.is_dir() else []
ttfs = list(font_root.rglob("*.ttf"))
if len(families) < 4:
    bad(f"font families: found {len(families)}, expected 4")
elif len(ttfs) < 8:
    bad(f"font files: found {len(ttfs)}, expected at least 8")
elif any(not (d / "OFL.txt").is_file() for d in families):
    bad("font families: an OFL.txt is missing")
else:
    ok(f"fonts: {len(ttfs)} files in {len(families)} families, each with OFL.txt")

for rel in ("licenses/OFL-1.1.txt", "licenses/LGPL-2.1.txt"):
    p = root / rel
    if p.is_file() and p.stat().st_size > 5_000:
        ok(f"{rel} present ({p.stat().st_size // 1024} KiB)")
    else:
        bad(f"{rel} missing or truncated")

# --- terminal ---------------------------------------------------------------
terminal_checks = {
    "terminal/kitty/nightcity.conf": ("#FF1744", "background"),
    "terminal/alacritty/nightcity.toml": ("#FF1744", "background"),
    "terminal/ptyxis/nightcity.palette": ("#FF1744", "Background"),
    "terminal/tilix/nightcity.json": ("#FF1744", "background"),
    "terminal/gnome-terminal/nightcity.dconf": ("#FF1744", "use-theme-colors"),
    "terminal/shell/nightcity-prompt.sh": ("PROMPT", "NightCity"),
}
for rel, needles in terminal_checks.items():
    p = root / rel
    if not p.is_file() or p.stat().st_size < 100:
        bad(f"{rel} missing or empty")
        continue
    text = p.read_text(encoding="utf-8", errors="replace")
    missing = [n for n in needles if n.lower() not in text.lower()]
    if missing:
        bad(f"{rel} lacks {missing}")
    else:
        ok(f"{rel} complete")
try:
    json.loads(read("terminal/tilix/nightcity.json"))
    ok("tilix JSON parses")
except Exception as exc:  # noqa: BLE001
    bad(f"terminal/tilix/nightcity.json invalid: {exc}")

# --- plymouth ---------------------------------------------------------------
ply = root / "plymouth/NightCity-Plymouth"
ply_images = ["background.png", "logo.png", "progress-track.png", "progress-pip.png"]
for name in ply_images:
    p = ply / name
    if p.is_file() and p.stat().st_size > 1_000:
        with p.open("rb") as fh:
            if fh.read(8) != b"\x89PNG\r\n\x1a\n":
                bad(f"Plymouth {name}: bad PNG header")
    else:
        bad(f"Plymouth asset missing: {name}")
script = (ply / "nightcity.script").read_text(encoding="utf-8", errors="replace") if (ply / "nightcity.script").is_file() else ""
if not script:
    bad("Plymouth nightcity.script missing")
else:
    refs = re.findall(r'Image\("([^"]+)"\)', script)
    missing = [r for r in refs if not (ply / r).is_file()]
    if missing:
        bad(f"Plymouth script references missing images: {missing}")
    for call in ("Plymouth.SetBootProgressFunction", "Plymouth.SetMessageFunction", "Plymouth.SetRefreshFunction"):
        if call not in script:
            bad(f"Plymouth script lacks {call}")
    if not missing:
        ok(f"Plymouth script references {len(set(refs))} bundled images and all callbacks")
ply_conf = (ply / "nightcity.plymouth").read_text(encoding="utf-8", errors="replace") if (ply / "nightcity.plymouth").is_file() else ""
if "ImageDir=/usr/share/plymouth/themes/NightCity-Plymouth" not in ply_conf:
    bad("Plymouth .plymouth file has the wrong ImageDir")
else:
    ok("Plymouth theme descriptor paths are correct")

# --- portability / placeholder scan ----------------------------------------
scan_roots = [
    root / "scripts",
    root / "design" / "overrides",
    root / "terminal",
    root / "gdm",
    root / "plymouth",
    root / "themes",
]
bad_words = re.compile(r"\b(TODO|FIXME|PLACEHOLDER|CHANGEME|lorem ipsum)\b", re.IGNORECASE)
bad_hits: list[str] = []
home_hits: list[str] = []
for base in scan_roots:
    for p in base.rglob("*"):
        if not p.is_file() or p.suffix.lower() in {".png", ".ttf", ".otf", ".pyc", ".xcur"}:
            continue
        if "__pycache__" in p.parts:
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        rel = p.relative_to(root).as_posix()
        for lineno, line in enumerate(text.splitlines(), 1):
            if bad_words.search(line):
                bad_hits.append(f"{rel}:{lineno}")
            if re.search(r"/home/(krazy|user)\b", line):
                home_hits.append(f"{rel}:{lineno}")
if bad_hits:
    bad(f"placeholder markers remain: {bad_hits[:6]}")
else:
    ok("no TODO/FIXME/placeholder markers in authored files")
if home_hits:
    bad(f"hard-coded home paths: {home_hits[:6]}")
else:
    ok("no hard-coded home paths in authored files")

# --- release docs -----------------------------------------------------------
if release:
    required_docs = [
        "README.md", "CHANGELOG.md", "VERSION", "LICENSE",
        "docs/COMPATIBILITY.md", "docs/TROUBLESHOOTING.md", "docs/RECOVERY.md",
        "docs/INSTALL.md", "docs/DESIGN.md", "docs/QA.md",
    ]
    missing = [rel for rel in required_docs if not (root / rel).is_file()]
    if missing:
        bad(f"release docs missing: {missing}")
    else:
        for rel in required_docs:
            if (root / rel).stat().st_size < 200:
                bad(f"{rel} is too short to be useful")
        if not [p for p in (root / "screenshots").glob("*.png")]:
            bad("release: no screenshots/*.png present")
        else:
            ok(f"release docs and {len(list((root / 'screenshots').glob('*.png')))} screenshot(s) present")
else:
    missing = [rel for rel in ("README.md", "CHANGELOG.md", "VERSION", "LICENSE") if not (root / rel).is_file()]
    if missing:
        maybe(f"docs not written yet: {missing}")

print(f"__SUMMARY__ {passed} {failed} {warned}")
count_file.write_text(f"{passed} {failed} {warned}\n", encoding="utf-8")
raise SystemExit(0 if failed == 0 else 1)
PY
py_rc=$?
set -e

read -r py_passed py_failed py_warned < "$COUNT_FILE" 2>/dev/null || true
rm -f "$COUNT_FILE"
PASSED=$((PASSED + ${py_passed:-0}))
WARNED=$((WARNED + ${py_warned:-0}))
if [ "$py_rc" -ne 0 ] || [ "${py_failed:-1}" -ne 0 ]; then
    FAILED=$((FAILED + 1))
    nc_err "artifact validation reported one or more failures."
fi

# ---------------------------------------------------------------------------
# 4. Optional staged install / uninstall rehearsal
# ---------------------------------------------------------------------------
if [ "$STAGED" = 1 ]; then
    section "Staged install rehearsal"
    STAGE="$(mktemp -d "${TMPDIR:-/tmp}/nightcity-validate.XXXXXX")"
    cleanup() { [ "$DRY_RUN" = 1 ] || rm -rf "$STAGE"; }
    trap cleanup EXIT

    mkdir -p "$STAGE/.config" "$STAGE/.local/share" "$STAGE/.local/state"
    printf '# staged test shell\n' > "$STAGE/.bashrc"

    export HOME="$STAGE"
    export XDG_CONFIG_HOME="$STAGE/.config"
    export XDG_DATA_HOME="$STAGE/.local/share"
    export XDG_STATE_HOME="$STAGE/.local/state"
    # Keep gsettings writes inside the staged config; never touch the live dconf.
    export GSETTINGS_BACKEND=keyfile

    if "$NC_ROOT/scripts/install.sh" --mode full --home "$STAGE" -y --no-color >"$STAGE/install.log" 2>&1; then
        pass "install.sh --mode full completed in staged HOME"
    else
        fail "staged install failed; log:"
        sed 's/^/      /' "$STAGE/install.log" | tail -n 40
    fi

    staged_checks=(
        "$STAGE/.local/share/themes/NightCity-GTK/gtk-3.0/gtk.css"
        "$STAGE/.local/share/themes/NightCity-Shell/gnome-shell/gnome-shell.css"
        "$STAGE/.local/share/icons/NightCity-Icons/index.theme"
        "$STAGE/.local/share/icons/NightCity-Cursor/cursor.theme"
        "$STAGE/.local/share/backgrounds/nightcity/nightcity-01-nightline.png"
        "$STAGE/.config/gtk-4.0/gtk.css"
        "$STAGE/.config/nightcity/prompt.sh"
        "$STAGE/.local/state/nightcity/installed.tsv"
    )
    for p in "${staged_checks[@]}"; do
        if [ -e "$p" ]; then
            pass "staged: ${p#"$STAGE"/}"
        else
            fail "staged: missing ${p#"$STAGE"/}"
        fi
    done
    if [ -f "$STAGE/.local/state/nightcity/installed.tsv" ] && \
       grep -q '^gtk4' "$STAGE/.local/state/nightcity/installed.tsv"; then
        pass "staged: install manifest records the GTK4 layer"
    else
        warn "staged: manifest looks incomplete"
    fi

    # gsettings must have been written to the staged keyfile backend, not dconf.
    if [ -f "$STAGE/.config/glib-2.0/settings/keyfile" ]; then
        pass "staged: gsettings written to the disposable keyfile backend"
    else
        warn "staged: no staged gsettings keyfile (settings may have been skipped)"
    fi

    if "$NC_ROOT/scripts/uninstall.sh" --home "$STAGE" -y --no-color >"$STAGE/uninstall.log" 2>&1; then
        pass "uninstall.sh completed in staged HOME"
    else
        fail "staged uninstall failed; log:"
        sed 's/^/      /' "$STAGE/uninstall.log" | tail -n 40
    fi
    for p in \
        "$STAGE/.local/share/themes/NightCity-GTK" \
        "$STAGE/.local/share/icons/NightCity-Icons" \
        "$STAGE/.config/nightcity/prompt.sh"; do
        if [ ! -e "$p" ]; then
            pass "staged: removed ${p#"$STAGE"/}"
        else
            fail "staged: still present after uninstall: ${p#"$STAGE"/}"
        fi
    done
    if grep -q 'NIGHT CITY PROMPT' "$STAGE/.bashrc" 2>/dev/null; then
        fail "staged: shell prompt block survived uninstall"
    else
        pass "staged: shell prompt block removed from .bashrc"
    fi
    if [ -f "$STAGE/.config/gtk-4.0/gtk.css" ]; then
        warn "staged: a gtk-4.0/gtk.css remains (was it a pre-existing file?)"
    else
        pass "staged: GTK4 override removed"
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n'
if [ "$FAILED" -eq 0 ]; then
    nc_ok "validation passed (${WARNED} warning(s))."
    exit 0
fi
nc_err "validation failed (${FAILED} failing area(s), ${WARNED} warning(s))."
exit 1
