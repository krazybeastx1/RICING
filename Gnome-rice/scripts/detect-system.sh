#!/usr/bin/env bash
# NIGHT CITY — print environment detection, dependency status and advice.
# Read-only. No root required; some checks are skipped without it.
set -Eeuo pipefail

NC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$NC_SCRIPT_DIR/lib/common.sh"

STRICT=0
usage() {
    cat <<EOF
${NC_NAME} detect v${NC_VERSION}

Usage: ./scripts/detect-system.sh [--strict]

  --strict   Exit 1 if a required build/runtime dependency is missing.

Prints distribution, GNOME/GTK versions, GDM/Plymouth state, extension
availability, build artifacts and NightCity install markers.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --strict) STRICT=1 ;;
        -h|--help) usage; exit 0 ;;
        *) nc_die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

nc_paths
nc_detect

MISSING=()

check_cmd() {
    local cmd="$1" hint="$2" required="${3:-1}"
    if nc_have "$cmd"; then
        printf '  %-26s %s\n' "$cmd" "$(command -v "$cmd")"
    else
        printf '  %-26s MISSING — %s\n' "$cmd" "$hint"
        [ "$required" = 1 ] && MISSING+=("$cmd")
    fi
}

echo "${NC_B}${NC_NAME} detection${NC_0}"
echo
nc_print_detect
echo

echo "${NC_B}Build tools${NC_0}"
check_cmd python3 "install python3"
check_cmd rsvg-convert "install librsvg2-bin" 1
check_cmd xcursorgen "install xcursorgen / x11-apps" 1
check_cmd gtk-update-icon-cache "install libgtk-3-bin or libgtk-4-bin" 0
check_cmd glib-compile-resources "install libglib2.0-dev-bin (GDM only)" 0
check_cmd gresource "install libglib2.0-bin (GDM only)" 0
python3 - <<'PY' 2>/dev/null || true
try:
    import PIL
    print(f"  {'Pillow':<26} {PIL.__version__}")
except Exception:
    print(f"  {'Pillow':<26} MISSING — install python3-pil")
PY
echo

echo "${NC_B}System components${NC_0}"
printf '  %-26s %s\n' "gdm service" "${NC_GDM_SERVICE:-not found}"
printf '  %-26s %s\n' "gresource" "$([ -e "$NC_GRESOURCE" ] && echo "$NC_GRESOURCE" || echo "missing")"
printf '  %-26s %s\n' "Plymouth tool" "$(nc_have plymouth-set-default-theme && command -v plymouth-set-default-theme || echo missing)"
printf '  %-26s %s\n' "Plymouth theme" "${NC_PLYMOUTH_THEME:-unknown}"
printf '  %-26s %s\n' "initramfs tool" "$(nc_have update-initramfs && echo update-initramfs || (nc_have dracut && echo dracut || echo missing))"
if [ -e /var/lib/nightcity/gdm.installed ]; then
    printf '  %-26s %s\n' "NightCity GDM" "$(tr '\n' ' ' < /var/lib/nightcity/gdm.installed)"
fi
if [ -e /var/lib/nightcity/plymouth.installed ]; then
    printf '  %-26s %s\n' "NightCity Plymouth" "$(tr '\n' ' ' < /var/lib/nightcity/plymouth.installed)"
fi
echo

echo "${NC_B}Shell extensions${NC_0}"
for ext in user-theme@gnome-shell-extensions.gcampax.github.com \
           dash-to-dock@micxgx.gmail.com \
           ubuntu-appindicators@ubuntu.com \
           apps-menu@gnome-shell-extensions.gcampax.github.com \
           places-menu@gnome-shell-extensions.gcampax.github.com \
           drive-menu@gnome-shell-extensions.gcampax.github.com \
           ding@rastersoft.com; do
    state="not installed"
    for base in "$HOME/.local/share/gnome-shell/extensions" /usr/share/gnome-shell/extensions; do
        [ -d "$base/$ext" ] && state="installed ($base)"
    done
    printf '  %-58s %s\n' "$ext" "$state"
done
echo

echo "${NC_B}Build artifacts${NC_0}"
ARTIFACTS=(
    "themes/NightCity-Shell/gnome-shell/gnome-shell.css"
    "themes/NightCity-GTK/gtk-3.0/gtk.css"
    "themes/NightCity-GTK/gtk-4.0-user.css"
    "gdm/theme/gnome-shell.css"
    "icons/NightCity-Icons/index.theme"
    "cursors/NightCity-Cursor/cursor.theme"
    "assets/wallpapers/nightcity-01-nightline.png"
    "plymouth/NightCity-Plymouth/nightcity.script"
)
for rel in "${ARTIFACTS[@]}"; do
    if [ -e "$NC_ROOT/$rel" ]; then
        printf '  %-58s ok (%s)\n' "$rel" "$(du -h "$NC_ROOT/$rel" | cut -f1)"
    else
        printf '  %-58s MISSING\n' "$rel"
        MISSING+=("$rel")
    fi
done
echo

echo "${NC_B}NightCity user install${NC_0}"
if [ -e "$NC_STATE/nightcity/installed.tsv" ]; then
    sed 's/^/  /' "$NC_STATE/nightcity/installed.tsv"
else
    echo "  not installed for $NC_USER_HOME"
fi
echo

echo "${NC_B}Advice${NC_0}"
if [ "$NC_FAMILY" = "debian" ]; then
    echo "  Build deps: sudo apt install python3-pil librsvg2-bin xcursorgen libglib2.0-dev-bin gtk-update-icon-cache"
elif [ "$NC_FAMILY" = "fedora" ]; then
    echo "  Build deps: sudo dnf install python3-pillow librsvg2-tools xcursorgen glib2-devel gtk-update-icon-cache"
elif [ "$NC_FAMILY" = "arch" ]; then
    echo "  Build deps: sudo pacman -S python-pillow librsvg xorg-xcursorgen glib2 gtk-update-icon-cache"
fi
[ "${#MISSING[@]}" -gt 0 ] && echo "  Missing: ${MISSING[*]}"
[ "$NC_HAVE_USER_THEME" = "no" ] && echo "  user-theme extension missing: install gnome-shell-extensions to load the shell theme."
[ "$NC_HAVE_DOCK" = "no" ] && echo "  Dash to Dock not detected: Full mode will skip dock tuning."

if [ "$STRICT" = 1 ] && [ "${#MISSING[@]}" -gt 0 ]; then
    exit 1
fi
exit 0
