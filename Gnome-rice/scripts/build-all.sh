#!/usr/bin/env bash
# NIGHT CITY — build every generated artifact from design/tokens.json.
#
# Steps: brand marks → icon theme → cursor theme → wallpapers → Plymouth →
#        GTK3/GTK4/shell/GDM stylesheets → validation.
#
#   ./scripts/build-all.sh
#   ./scripts/build-all.sh --skip-wallpapers
#   ./scripts/build-all.sh --assets-only
#   ./scripts/build-all.sh --no-validate
set -Eeuo pipefail

NC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$NC_SCRIPT_DIR/lib/common.sh"

SKIP_WALLPAPERS=0
ASSETS_ONLY=0
DO_VALIDATE=1
RELEASE=0

usage() {
    cat <<EOF
${NC_NAME} build v${NC_VERSION}

Usage: ./scripts/build-all.sh [options]

  --skip-wallpapers   Keep existing wallpapers (saves several minutes).
  --assets-only       Rebuild brand/icons/cursors/plymouth but not CSS.
  --no-validate       Do not run scripts/validate.sh afterwards.
  --release           Validate as a release (requires docs/screenshots).
  -n, --dry-run       Print the build plan, run nothing.
  --no-color          Disable ANSI colour.
  -h, --help          This text.

Requirements: python3, Pillow, rsvg-convert, xcursorgen; gtk-update-icon-cache
is used when present. All outputs are deterministic and live inside this tree.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-wallpapers) SKIP_WALLPAPERS=1 ;;
        --assets-only) ASSETS_ONLY=1 ;;
        --no-validate) DO_VALIDATE=0 ;;
        --release) RELEASE=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        --no-color) NO_COLOR=1; NC_R=''; NC_C=''; NC_W=''; NC_D=''; NC_B=''; NC_0='' ;;
        -h|--help) usage; exit 0 ;;
        *) nc_die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

nc_banner
nc_paths
nc_detect

# ---------------------------------------------------------------------------
# Requirements
# ---------------------------------------------------------------------------
nc_step "Checking build requirements"
nc_have python3 || nc_die "python3 is required."
python3 - <<'PY' || nc_die "Pillow is required (python3-pil or python3-pillow)."
from PIL import Image, ImageDraw, ImageFont, ImageFilter  # noqa: F401
PY
nc_have rsvg-convert || nc_die "rsvg-convert is required for brand and icon PNGs."
nc_have xcursorgen || nc_die "xcursorgen is required for the cursor theme (x11-apps / xorg-xcursorgen)."
nc_have gtk-update-icon-cache || nc_warn "gtk-update-icon-cache not found; the icon cache will be stale."
nc_have glib-compile-resources || nc_warn "glib-compile-resources not found; GDM install will be unavailable."

for f in design/tokens.json; do
    [ -r "$NC_ROOT/$f" ] || nc_die "missing $f"
done

# ---------------------------------------------------------------------------
# Plan
# ---------------------------------------------------------------------------
nc_step "Build plan"
cat <<EOF
  fonts       $(find "$NC_ROOT/assets/fonts" -name '*.ttf' | wc -l) bundled files
  branding    assets/branding/
  icons       icons/NightCity-Icons/
  cursors     cursors/NightCity-Cursor/  (build/ intermediates)
  wallpapers  $([ "$SKIP_WALLPAPERS" = 1 ] && echo "skipped (--skip-wallpapers)" || echo "6 × 3840×2160 PNG")
  plymouth    plymouth/NightCity-Plymouth/
  styles      shell + GTK3 + GTK4 + libadwaita user layer + GDM
  validate    $([ "$DO_VALIDATE" = 1 ] && echo yes || echo no)
EOF
if [ "$DRY_RUN" = 1 ]; then
    nc_warn "dry run only; no artifacts were built."
    exit 0
fi

run_py() {
    local script="$1"
    shift
    [ -r "$NC_ROOT/scripts/$script" ] || nc_die "missing scripts/$script"
    nc_step "Running $script $*"
    python3 "$NC_ROOT/scripts/$script" "$@"
}

# ---------------------------------------------------------------------------
# Assets
# ---------------------------------------------------------------------------
run_py generate-branding.py

run_py generate-icons.py

run_py generate-cursors.py

if [ "$SKIP_WALLPAPERS" = 0 ]; then
    run_py generate-wallpapers.py
else
    nc_step "Wallpapers"
    nc_warn "kept the existing wallpapers."
fi

run_py generate-plymouth.py

if [ "$ASSETS_ONLY" = 0 ]; then
    nc_step "Compiling stylesheets from design/tokens.json"
    python3 "$NC_ROOT/scripts/build-theme.py"
else
    nc_warn "stylesheets not rebuilt (--assets-only)."
fi

# ---------------------------------------------------------------------------
# Post-build sanity (fast, before the full validator)
# ---------------------------------------------------------------------------
nc_step "Post-build sanity"
missing=0
for f in \
    assets/branding/nightcity-mark.png \
    assets/wallpapers/nightcity-01-nightline.png \
    icons/NightCity-Icons/index.theme \
    cursors/NightCity-Cursor/cursor.theme \
    plymouth/NightCity-Plymouth/nightcity.script \
    themes/NightCity-Shell/gnome-shell/gnome-shell.css \
    themes/NightCity-GTK/gtk-3.0/gtk.css \
    themes/NightCity-GTK/gtk-4.0-user.css \
    gdm/theme/gnome-shell.css; do
    if [ -s "$NC_ROOT/$f" ]; then
        printf '  %s✓%s %s\n' "$NC_C" "$NC_0" "$f"
    else
        printf '  %s✗%s %s (missing or empty)\n' "$NC_R" "$NC_0" "$f"
        missing=$((missing + 1))
    fi
done
[ "$missing" -eq 0 ] || nc_die "$missing expected artifact(s) missing."

if [ "$DO_VALIDATE" = 1 ]; then
    nc_step "Validating the build"
    args=(--no-color)
    [ "$RELEASE" = 1 ] && args+=(--release)
    "$NC_SCRIPT_DIR/validate.sh" "${args[@]}" || nc_die "validation failed; see the report above."
else
    nc_warn "validation skipped (--no-validate)."
fi

printf '\n'
nc_ok "build complete."
nc_log "Next: ./scripts/validate.sh --staged     (install rehearsal)"
nc_log "      ./scripts/install.sh --mode full   (apply to this account)"
