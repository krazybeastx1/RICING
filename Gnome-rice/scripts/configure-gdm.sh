#!/usr/bin/env bash
# NIGHT CITY — install the GNOME Shell theme into the system gresource used by
# GDM, without replacing any other theme file.
#
# What it does
#   1. detects the GNOME Shell major version and the gresource layout
#   2. backs up the gresource, GDM config and greeter dconf
#   3. extracts every resource from the current gresource
#   4. replaces only gnome-shell-dark.css with the NIGHT CITY greeter sheet
#   5. recompiles the gresource and validates every resource before installing
#   6. installs the greeter wallpaper/logo and an optional greeter dconf snippet
#
# GDM is never restarted here. Reboot (or restart gdm from a TTY) to see it.
set -Eeuo pipefail

NC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$NC_SCRIPT_DIR/lib/common.sh"

FORCE=0
WITH_LOGO=1
SKIP_ASSETS=0

usage() {
    cat <<EOF
${NC_NAME} GDM theme installer v${NC_VERSION}

Usage: sudo ./scripts/configure-gdm.sh [options]

  --force          Install even if the GNOME major version differs.
  --no-logo        Do not change the greeter logo.
  --no-assets      Do not install the greeter wallpaper/logo files.
  -n, --dry-run    Print actions, change nothing.
  -y, --yes        Do not ask for confirmation.
  --no-color       Disable ANSI colour.
  -h, --help       This text.

Requires: root, glib-compile-resources, gresource, an existing
/usr/share/gnome-shell/gnome-shell-theme.gresource.

Rollback: sudo ./scripts/rollback.sh --system
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --force) FORCE=1 ;;
        --no-logo) WITH_LOGO=0 ;;
        --no-assets) SKIP_ASSETS=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        --no-color) NO_COLOR=1; NC_R=''; NC_C=''; NC_W=''; NC_D=''; NC_B=''; NC_0='' ;;
        -h|--help) usage; exit 0 ;;
        *) nc_die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

nc_banner
nc_paths
nc_detect

[ "$(id -u)" -eq 0 ] || nc_die "configure-gdm.sh must run as root (sudo)."
nc_have gresource || nc_die "gresource not found (install libglib2.0-bin)."
nc_have glib-compile-resources || nc_die "glib-compile-resources not found (install libglib2.0-dev-bin)."
[ "$NC_GDM" = "yes" ] || nc_die "GDM was not detected on this system."
[ -e "$NC_GRESOURCE" ] || nc_die "missing $NC_GRESOURCE; is gnome-shell installed?"
[ -r "$NC_ROOT/gdm/theme/gnome-shell.css" ] || nc_die "missing gdm/theme/gnome-shell.css; run ./scripts/build-all.sh"

if ! nc_check_gnome_major 50; then
    if [ "$FORCE" = 1 ]; then
        nc_warn "continuing anyway (--force)."
    else
        nc_die "refusing on GNOME ${NC_GNOME_MAJOR}. Re-run with --force only after checking compatibility."
    fi
fi

RES_PREFIX="/org/gnome/shell/theme"
MAP="$(gresource list "$NC_GRESOURCE")" || nc_die "cannot read $NC_GRESOURCE"
if ! printf '%s\n' "$MAP" | grep -Fx "$RES_PREFIX/gnome-shell-dark.css" >/dev/null; then
    nc_die "this gresource has no $RES_PREFIX/gnome-shell-dark.css; layout unsupported."
fi
if printf '%s\n' "$MAP" | grep -vq "^$RES_PREFIX/"; then
    nc_die "gresource contains resources outside $RES_PREFIX; refusing to rebuild blindly."
fi

nc_step "Plan"
cat <<EOF
  GNOME Shell      ${NC_GNOME_VERSION} (${NC_GNOME_MAJOR})
  gresource       $NC_GRESOURCE
  resources       $(printf '%s\n' "$MAP" | wc -l)
  replacement     $RES_PREFIX/gnome-shell-dark.css
  wallpaper       /usr/share/backgrounds/nightcity/nightline.png
  greeter logo    $([ "$WITH_LOGO" = 1 ] && echo "NightCity mark" || echo "unchanged")
  rollback        sudo $NC_ROOT/scripts/rollback.sh --system
EOF
nc_confirm "Back up and replace the system GDM gresource?" || { nc_warn "aborted by user"; exit 0; }

# --- backup -----------------------------------------------------------------
nc_step "Backing up system files"
nc_system_backup
SYS_BACKUP="${NC_SYS_BACKUP:-}"
if [ "$DRY_RUN" = 0 ]; then
    [ -n "$SYS_BACKUP" ] && [ -d "$SYS_BACKUP" ] || nc_die "system backup failed; refusing to continue."
fi

GREETER_DCONF=""
if [ -d /usr/share/gdm/dconf ]; then
    GREETER_DCONF="/usr/share/gdm/dconf/99-nightcity"
elif [ -d /etc/dconf/db ]; then
    GREETER_DCONF="/etc/dconf/db/gdm.d/99-nightcity"
else
    GREETER_DCONF=""
fi

# Preserve an existing greeter snippet if this is not our own previous run.
if [ -n "$GREETER_DCONF" ] && [ -e "$GREETER_DCONF" ] && ! grep -q "NIGHT CITY" "$GREETER_DCONF" 2>/dev/null; then
    if [ "$DRY_RUN" = 0 ]; then
        mkdir -p "$SYS_BACKUP/files$(dirname "$GREETER_DCONF")"
        cp -a "$GREETER_DCONF" "$SYS_BACKUP/files$GREETER_DCONF"
        printf 'file\t%s\n' "$GREETER_DCONF" >> "$SYS_BACKUP/manifest.txt"
    fi
fi

if [ "$DRY_RUN" = 1 ]; then
    nc_log "    dry-run: extract, patch and recompile $NC_GRESOURCE"
    nc_log "    dry-run: install greeter assets and dconf (if requested)"
    nc_warn "dry run only; nothing was changed."
    exit 0
fi

# --- rebuild ----------------------------------------------------------------
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nightcity-gdm.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/res"
while IFS= read -r res; do
    [ -n "$res" ] || continue
    name="${res##*/}"
    gresource extract "$NC_GRESOURCE" "$res" > "$WORK/res/$name" || nc_die "failed to extract $res"
done <<< "$MAP"

install -m 644 "$NC_ROOT/gdm/theme/gnome-shell.css" "$WORK/res/gnome-shell-dark.css"

python3 - "$WORK" <<'PY'
import sys
from pathlib import Path
from xml.sax.saxutils import escape

work = Path(sys.argv[1])
files = sorted(p.name for p in (work / "res").iterdir() if p.is_file())
xml = ['<?xml version="1.0" encoding="UTF-8"?>', "<gresources>",
       '  <gresource prefix="/org/gnome/shell/theme">']
xml += [f"    <file>{escape(n)}</file>" for n in files]
xml += ["  </gresource>", "</gresources>", ""]
(work / "nightcity.gresource.xml").write_text("\n".join(xml), encoding="utf-8")
PY

glib-compile-resources \
    --sourcedir="$WORK/res" \
    --target="$WORK/gnome-shell-theme.gresource" \
    "$WORK/nightcity.gresource.xml" || nc_die "glib-compile-resources failed"

# --- validate before touching the system ------------------------------------
nc_step "Validating rebuilt gresource"
NEW_LIST="$(gresource list "$WORK/gnome-shell-theme.gresource")" || nc_die "new gresource is not readable"
if [ "$NEW_LIST" != "$MAP" ]; then
    nc_err "resource list changed:"
    diff <(printf '%s\n' "$MAP") <(printf '%s\n' "$NEW_LIST") || true
    nc_die "aborting; system gresource was not modified."
fi

while IFS= read -r res; do
    [ -n "$res" ] || continue
    name="${res##*/}"
    if [ "$name" = "gnome-shell-dark.css" ]; then
        gresource extract "$WORK/gnome-shell-theme.gresource" "$res" > "$WORK/check.css"
        cmp -s "$WORK/check.css" "$NC_ROOT/gdm/theme/gnome-shell.css" || \
            nc_die "rebuilt CSS does not match the built theme; aborting."
    else
        gresource extract "$WORK/gnome-shell-theme.gresource" "$res" > "$WORK/check.bin"
        cmp -s "$WORK/check.bin" "$WORK/res/$name" || nc_die "resource changed unexpectedly: $res"
    fi
done <<< "$MAP"
nc_ok "all $(printf '%s\n' "$MAP" | wc -l) resources preserved; CSS replaced"

# --- install ----------------------------------------------------------------
nc_step "Installing $NC_GRESOURCE"
install -m 644 -o root -g root "$WORK/gnome-shell-theme.gresource" "$NC_GRESOURCE.nightcity-new"
mv -f "$NC_GRESOURCE.nightcity-new" "$NC_GRESOURCE"
if nc_have restorecon; then restorecon "$NC_GRESOURCE" 2>/dev/null || true; fi
_post_list="$(gresource list "$NC_GRESOURCE" || true)"
if ! printf '%s\n' "$_post_list" | grep -Fx "$RES_PREFIX/gnome-shell-dark.css" >/dev/null; then
    nc_die "post-install validation failed; restore with: sudo $NC_ROOT/scripts/rollback.sh --system"
fi
nc_ok "GDM theme installed"

if [ "$SKIP_ASSETS" = 0 ]; then
    nc_step "Installing greeter wallpaper and logo"
    install -d -m 755 /usr/share/backgrounds/nightcity
    install -m 644 "$NC_ROOT/assets/wallpapers/nightcity-01-nightline.png" \
        /usr/share/backgrounds/nightcity/nightline.png
    install -m 644 "$NC_ROOT/assets/branding/nightcity-mark.png" \
        /usr/share/backgrounds/nightcity/nightcity-mark.png
    nc_ok "greeter assets installed under /usr/share/backgrounds/nightcity"
fi

if [ -n "$GREETER_DCONF" ]; then
    nc_step "Writing greeter dconf snippet"
    mkdir -p "$(dirname "$GREETER_DCONF")"
    {
        echo "# NIGHT CITY greeter settings — remove with scripts/rollback.sh --system"
        echo "[org/gnome/desktop/interface]"
        echo "color-scheme='prefer-dark'"
        if [ "$WITH_LOGO" = 1 ]; then
            echo
            echo "[org/gnome/login-screen]"
            echo "logo='/usr/share/backgrounds/nightcity/nightcity-mark.png'"
        fi
    } > "$GREETER_DCONF"
    chmod 644 "$GREETER_DCONF"
    nc_ok "greeter settings written to $GREETER_DCONF"

    # /etc/dconf/db needs a profile and a compiled database; the Debian-style
    # /usr/share/gdm/dconf directory is compiled by GDM itself at startup.
    case "$GREETER_DCONF" in
        /etc/dconf/*)
            if [ ! -e /etc/dconf/profile/gdm ]; then
                mkdir -p /etc/dconf/profile
                {
                    echo "user-db:user"
                    echo "system-db:gdm"
                    [ -e /usr/share/gdm/greeter-dconf-defaults ] && echo "file-db:/usr/share/gdm/greeter-dconf-defaults"
                } > /etc/dconf/profile/gdm
                nc_ok "created /etc/dconf/profile/gdm"
            fi
            dconf update 2>/dev/null || nc_warn "dconf update failed; run it manually."
            ;;
    esac
else
    nc_warn "no greeter dconf location found; only the gresource was changed."
fi

mkdir -p /var/lib/nightcity
{
    echo "component=gdm"
    echo "installed=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "gnome=$NC_GNOME_VERSION"
    echo "backup=$SYS_BACKUP"
} > /var/lib/nightcity/gdm.installed

printf '\n'
nc_ok "GDM greeter theme installed."
nc_log "  Reboot to see the login screen (GDM is not restarted automatically)."
nc_log "  Rollback: sudo $NC_ROOT/scripts/rollback.sh --system"
exit 0
