#!/usr/bin/env bash
# NIGHT CITY — install the Plymouth boot theme.
#
# The theme is copied to /usr/share/plymouth/themes/NightCity-Plymouth, made the
# default and compiled into the initramfs. The previous theme is recorded so
# rollback.sh can restore it. Nothing is displayed or restarted live.
set -Eeuo pipefail

NC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$NC_SCRIPT_DIR/lib/common.sh"

NO_INITRAMFS=0
FORCE=0

usage() {
    cat <<EOF
${NC_NAME} Plymouth installer v${NC_VERSION}

Usage: sudo ./scripts/configure-plymouth.sh [options]

  --no-initramfs   Install and select the theme but do not rebuild the
                   initramfs (the boot splash will not change yet).
  --force          Continue even if detection looks unusual.
  -n, --dry-run    Print actions, change nothing.
  -y, --yes        Do not ask for confirmation.
  --no-color       Disable ANSI colour.
  -h, --help       This text.

Requires: root, plymouth-set-default-theme, an initramfs tool
(update-initramfs or dracut).

Rollback: sudo ./scripts/rollback.sh --system
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --no-initramfs) NO_INITRAMFS=1 ;;
        --force) FORCE=1 ;;
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

[ "$(id -u)" -eq 0 ] || nc_die "configure-plymouth.sh must run as root (sudo)."
[ "$NC_PLYMOUTH" = "yes" ] || nc_die "Plymouth was not detected on this system."
nc_have plymouth-set-default-theme || nc_die "plymouth-set-default-theme not found."

SRC="$NC_ROOT/plymouth/NightCity-Plymouth"
[ -d "$SRC" ] || nc_die "missing $SRC; run ./scripts/build-all.sh"
[ -r "$SRC/nightcity.plymouth" ] || nc_die "missing nightcity.plymouth"
[ -r "$SRC/nightcity.script" ] || nc_die "missing nightcity.script"
for img in background.png logo.png progress-track.png progress-pip.png; do
    [ -r "$SRC/$img" ] || nc_die "missing Plymouth asset: $img (run scripts/generate-plymouth.py)"
done

# Static sanity checks: the script must reference the images we ship and use
# the callbacks the script plugin provides.
while IFS= read -r ref; do
    [ -r "$SRC/$ref" ] || nc_die "nightcity.script references missing image: $ref"
done < <(grep -oE 'Image\("[^"]+"\)' "$SRC/nightcity.script" | sed 's/Image("//; s/")//')
for call in Plymouth.SetBootProgressFunction Plymouth.SetMessageFunction Plymouth.SetRefreshFunction; do
    grep -q "$call" "$SRC/nightcity.script" || nc_die "nightcity.script is missing $call"
done

INITRAMFS_TOOL=""
if nc_have update-initramfs; then
    INITRAMFS_TOOL="update-initramfs"
elif nc_have dracut; then
    INITRAMFS_TOOL="dracut"
fi
if [ "$NO_INITRAMFS" = 0 ] && [ -z "$INITRAMFS_TOOL" ] && [ "$DRY_RUN" = 0 ]; then
    nc_warn "no initramfs tool found; the theme will be selected but not bootable yet."
    NC_CONFIRM_EXTRA=1
fi

nc_step "Plan"
cat <<EOF
  Plymouth        ${NC_PLYMOUTH_THEME:-unknown} → NightCity-Plymouth
  target          /usr/share/plymouth/themes/NightCity-Plymouth
  config          /etc/plymouth/plymouthd.conf
  initramfs       $([ "$NO_INITRAMFS" = 1 ] && echo "skipped (--no-initramfs)" || echo "${INITRAMFS_TOOL:-none}")
  rollback        sudo $NC_ROOT/scripts/rollback.sh --system
EOF
nc_confirm "Install the NIGHT CITY boot theme and rebuild the initramfs?" || { nc_warn "aborted by user"; exit 0; }

nc_step "Backing up system files"
nc_system_backup
SYS_BACKUP="${NC_SYS_BACKUP:-}"
if [ "$DRY_RUN" = 0 ]; then
    [ -n "$SYS_BACKUP" ] && [ -d "$SYS_BACKUP" ] || nc_die "system backup failed; refusing to continue."
fi

TARGET="/usr/share/plymouth/themes/NightCity-Plymouth"
if [ "$DRY_RUN" = 1 ]; then
    printf '%s    dry-run: install%s %s → %s\n' "$NC_D" "$NC_0" "$SRC" "$TARGET"
else
    rm -rf "$TARGET"
    mkdir -p "$TARGET"
    cp -a "$SRC/." "$TARGET/"
    chmod 755 "$TARGET"
    chmod 644 "$TARGET"/*.png "$TARGET"/*.plymouth "$TARGET"/*.script
    nc_ok "theme files installed in $TARGET"
fi

# Make sure the .plymouth file points at the installed location.
if [ "$DRY_RUN" = 0 ]; then
    sed -i "s|^ImageDir=.*|ImageDir=$TARGET|; s|^ScriptFile=.*|ScriptFile=$TARGET/nightcity.script|" \
        "$TARGET/nightcity.plymouth"
    grep -qx "ImageDir=$TARGET" "$TARGET/nightcity.plymouth" || nc_die "failed to patch ImageDir"
    grep -qx "ScriptFile=$TARGET/nightcity.script" "$TARGET/nightcity.plymouth" || nc_die "failed to patch ScriptFile"
fi

nc_step "Selecting the theme"
if [ "$DRY_RUN" = 1 ]; then
    printf '%s    dry-run: plymouth-set-default-theme NightCity-Plymouth%s\n' "$NC_D" "$NC_0"
else
    plymouth-set-default-theme NightCity-Plymouth || nc_die "plymouth-set-default-theme failed"
    _theme_list="$(plymouth-set-default-theme -l 2>/dev/null || true)"
    if ! printf '%s\n' "$_theme_list" | grep -Fx "NightCity-Plymouth" >/dev/null; then
        nc_warn "theme is not listed by plymouth-set-default-theme -l; check $TARGET"
    fi
    grep -q '^Theme=NightCity-Plymouth$' /etc/plymouth/plymouthd.conf 2>/dev/null || \
        nc_warn "/etc/plymouth/plymouthd.conf does not record the new theme; inspect it manually."
    nc_ok "Plymouth default theme is NightCity-Plymouth"
fi

if [ "$NO_INITRAMFS" = 0 ]; then
    nc_step "Rebuilding the initramfs (this can take a minute)"
    if [ "$DRY_RUN" = 1 ]; then
        printf '%s    dry-run: %s rebuild%s\n' "$NC_D" "$NC_0" "${INITRAMFS_TOOL:-initramfs}"
    else
        rc=0
        case "$INITRAMFS_TOOL" in
            update-initramfs) update-initramfs -u || rc=$? ;;
            dracut)           dracut -f || rc=$? ;;
            *)
                # Best effort: ask Plymouth's helper, which knows the distro.
                plymouth-set-default-theme -R NightCity-Plymouth || rc=$?
                ;;
        esac
        if [ "$rc" -ne 0 ]; then
            nc_err "initramfs rebuild failed (exit $rc)."
            nc_err "The theme is selected but the boot splash may stay unchanged."
            nc_err "Fix the error, then run: sudo ${INITRAMFS_TOOL:-update-initramfs} $([ "$INITRAMFS_TOOL" = dracut ] && echo -f || echo -u)"
            nc_err "Rollback: sudo $NC_ROOT/scripts/rollback.sh --system"
            exit "$rc"
        fi
        nc_ok "initramfs rebuilt"
    fi
else
    nc_warn "initramfs not rebuilt; run update-initramfs -u or dracut -f before rebooting."
fi

if [ "$DRY_RUN" = 0 ]; then
    mkdir -p /var/lib/nightcity
    {
        echo "component=plymouth"
        echo "installed=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "previous=${NC_PLYMOUTH_THEME:-unknown}"
        echo "backup=$SYS_BACKUP"
    } > /var/lib/nightcity/plymouth.installed
fi

printf '\n'
nc_ok "Plymouth theme installed."
nc_log "  The new splash appears on the next boot."
nc_log "  Rollback: sudo $NC_ROOT/scripts/rollback.sh --system"
[ "$DRY_RUN" = 1 ] && nc_warn "dry run only; nothing was changed."
exit 0
