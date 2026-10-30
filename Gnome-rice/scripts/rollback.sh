#!/usr/bin/env bash
# NIGHT CITY — roll back system changes made by configure-gdm.sh and
# configure-plymouth.sh, or hand off to restore.sh for user settings.
#
# GDM and Plymouth are never restarted by this script. A reboot (or, for GDM,
# a manual "systemctl restart gdm" from a TTY) is left to the operator so a
# broken session cannot lock you out.
set -Eeuo pipefail

NC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$NC_SCRIPT_DIR/lib/common.sh"

SCOPE=""
BACKUP=""
LIST=0
NO_INITRAMFS=0
USER_ARGS=()

usage() {
    cat <<EOF
${NC_NAME} rollback v${NC_VERSION}

Usage:
  sudo ./scripts/rollback.sh --system [options]   restore GDM + Plymouth
       ./scripts/rollback.sh --user   [options]   restore user backup

System options
  --backup DIR       Use a specific backup (default: newest).
  --no-initramfs     Do not rebuild the initramfs after restoring Plymouth.
  --list             List system backups and exit.

User options
  --backup DIR, -n, -y, --home DIR, --files-only, --settings-only
                     Passed through to scripts/restore.sh.

Common
  -n, --dry-run      Print actions, change nothing.
  -y, --yes          Do not ask for confirmation.
  --no-color         Disable ANSI colour.
  -h, --help         This text.

Nothing reboots or restarts GDM automatically.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --system) SCOPE="system" ;;
        --user) SCOPE="user" ;;
        --backup) BACKUP="${2:-}"; USER_ARGS+=(--backup "${2:-}"); shift ;;
        --backup=*) BACKUP="${1#*=}"; USER_ARGS+=("$1") ;;
        --list) LIST=1 ;;
        --no-initramfs) NO_INITRAMFS=1 ;;
        --files-only|--settings-only) USER_ARGS+=("$1") ;;
        --home) USER_ARGS+=(--home "${2:-}"); STAGED_HOME="${2:-}"; shift ;;
        --home=*) USER_ARGS+=("$1"); STAGED_HOME="${1#*=}" ;;
        -n|--dry-run) DRY_RUN=1; USER_ARGS+=(--dry-run) ;;
        -y|--yes) ASSUME_YES=1; USER_ARGS+=(--yes) ;;
        --no-color) NO_COLOR=1; NC_R=''; NC_C=''; NC_W=''; NC_D=''; NC_B=''; NC_0=''; USER_ARGS+=(--no-color) ;;
        -h|--help) usage; exit 0 ;;
        *) nc_die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

[ -n "$SCOPE" ] || { usage; exit 1; }

if [ "$SCOPE" = "user" ]; then
    exec "$NC_SCRIPT_DIR/restore.sh" "${USER_ARGS[@]}"
fi

nc_banner
nc_paths
nc_detect

if [ "$LIST" = 1 ]; then
    root="${NC_SYS_BACKUP_DIR:-/var/backups/nightcity}"
    nc_step "System backups in $root"
    if [ -d "$root" ]; then
        for d in "$root"/*/; do
            [ -d "$d" ] || continue
            d="${d%/}"
            printf '  %s  %s\n' "$(basename "$d")" "$(sed -n 's/^created=//p' "$d/manifest.txt" 2>/dev/null | head -n1)"
        done
    else
        nc_log "  (none)"
    fi
    exit 0
fi

[ "$(id -u)" -eq 0 ] || nc_die "system rollback must run as root (sudo)."

if [ -z "$BACKUP" ]; then
    BACKUP="$(nc_system_backup_latest || true)"
    [ -n "$BACKUP" ] || nc_die "no system backup found in ${NC_SYS_BACKUP_DIR:-/var/backups/nightcity}"
fi
[ -d "$BACKUP" ] || nc_die "backup not found: $BACKUP"
[ -r "$BACKUP/manifest.txt" ] || nc_die "not a NightCity system backup: $BACKUP"

nc_step "System rollback from $(basename "$BACKUP")"
sed 's/^/  /' "$BACKUP/manifest.txt"
nc_confirm "Restore these system files and remove NightCity system assets?" || { nc_warn "aborted by user"; exit 0; }

restore_file() {
    local path="$1" src="$BACKUP/files$1"
    [ -e "$src" ] || { nc_warn "not in backup: $path"; return 0; }
    if [ "$DRY_RUN" = 1 ]; then
        printf '%s    dry-run: restore%s %s\n' "$NC_D" "$NC_0" "$path"
        return 0
    fi
    mkdir -p "$(dirname "$path")"
    # Atomic replace so a running GDM never reads a half-written gresource.
    cp -a "$src" "$path.nightcity-restore"
    mv -f "$path.nightcity-restore" "$path"
    chmod 644 "$path"
    nc_ok "restored $path"
}

while IFS=$'\t' read -r kind path; do
    [ "$kind" = "file" ] || continue
    [ -n "$path" ] || continue
    restore_file "$path"
done < "$BACKUP/manifest.txt"

# Remove files this project added that are not part of the backup.
nc_step "Removing NIGHT CITY system assets"
for p in /usr/share/plymouth/themes/NightCity-Plymouth \
         /usr/share/backgrounds/nightcity \
         /usr/share/gdm/dconf/99-nightcity; do
    [ -e "$p" ] || continue
    if [ "$DRY_RUN" = 1 ]; then
        printf '%s    dry-run: remove%s %s\n' "$NC_D" "$NC_0" "$p"
    else
        rm -rf "$p"
        nc_ok "removed $p"
    fi
done

if [ "$DRY_RUN" = 0 ] && nc_have dconf; then
    dconf update 2>/dev/null || nc_warn "dconf update failed; run it manually."
fi

# Restore the previous Plymouth theme (recorded by configure-plymouth.sh).
OLD_THEME="$(awk -F '\t' '$1=="plymouth-theme"{print $2; exit}' "$BACKUP/manifest.txt" 2>/dev/null || true)"
if [ -z "$OLD_THEME" ] && [ -r "$BACKUP/files/etc/plymouth/plymouthd.conf" ]; then
    OLD_THEME="$(sed -n 's/^Theme=//p' "$BACKUP/files/etc/plymouth/plymouthd.conf" | head -n1)"
fi
if [ "$NO_INITRAMFS" = 1 ]; then
    nc_warn "initramfs not rebuilt (--no-initramfs); the old theme may need one manual build."
elif nc_have plymouth-set-default-theme; then
    nc_step "Restoring Plymouth theme"
    if [ -n "$OLD_THEME" ] && [ -d "/usr/share/plymouth/themes/$OLD_THEME" ]; then
        nc_run plymouth-set-default-theme -R "$OLD_THEME" || nc_warn "Plymouth rebuild failed; run: sudo update-initramfs -u"
        nc_ok "Plymouth theme restored to $OLD_THEME"
    else
        nc_run update-initramfs -u || nc_warn "initramfs rebuild failed; run: sudo update-initramfs -u"
        nc_warn "previous Plymouth theme unknown; boot theme is now the distribution default."
    fi
fi

# Validate the restored gresource if it exists.
if [ "$DRY_RUN" = 0 ] && [ -e "$NC_GRESOURCE" ] && nc_have gresource; then
    if gresource list "$NC_GRESOURCE" >/dev/null 2>&1; then
        nc_ok "restored gresource is readable ($(gresource list "$NC_GRESOURCE" | wc -l) resources)"
    else
        nc_err "restored gresource failed validation: $NC_GRESOURCE"
        nc_err "restore it manually from $BACKUP/files$NC_GRESOURCE"
        exit 1
    fi
fi

printf '\n'
nc_ok "system rollback complete."
nc_log "Reboot to load the restored GDM and boot themes."
[ "$DRY_RUN" = 1 ] && nc_warn "dry run only; nothing was restored."
exit 0
