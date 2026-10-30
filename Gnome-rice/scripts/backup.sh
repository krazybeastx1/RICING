#!/usr/bin/env bash
# NIGHT CITY — make a backup on demand.
#
#   ./scripts/backup.sh                 # user files + snapshotted gsettings
#   sudo ./scripts/backup.sh --system   # GDM gresource, greeter dconf, Plymouth
#
# Backups are timestamped and never overwritten:
#   user:   ${XDG_STATE_HOME:-$HOME/.local/state}/nightcity/backups/<ts>
#   system: /var/backups/nightcity/<ts>
set -Eeuo pipefail

NC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$NC_SCRIPT_DIR/lib/common.sh"

SCOPE="user"
LABEL=""
LIST=0

usage() {
    cat <<EOF
${NC_NAME} backup v${NC_VERSION}

Usage: ./scripts/backup.sh [--user|--system] [options]

  --user            Back up the current user's config (default).
  --system          Back up GDM/Plymouth system files (requires root).
  --label TEXT      Add a note to the backup manifest.
  --list            List existing backups and exit.
  --home DIR        Operate on a staged HOME (testing).
  -n, --dry-run     Print actions, change nothing.
  -y, --yes         Do not ask for confirmation.
  --no-color        Disable ANSI colour.
  -h, --help        This text.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --user) SCOPE="user" ;;
        --system) SCOPE="system" ;;
        --label) LABEL="${2:-}"; shift ;;
        --label=*) LABEL="${1#*=}" ;;
        --list) LIST=1 ;;
        --home) STAGED_HOME="${2:-}"; shift ;;
        --home=*) STAGED_HOME="${1#*=}" ;;
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

if [ "$LIST" = 1 ]; then
    if [ "$SCOPE" = "system" ]; then
        root="${NC_SYS_BACKUP_DIR:-/var/backups/nightcity}"
        nc_step "System backups in $root"
        [ -d "$root" ] && ls -1d "$root"/*/ 2>/dev/null | sed 's:/$::' || nc_log "  (none)"
    else
        nc_step "User backups in $NC_USER_BACKUP_ROOT"
        [ -d "$NC_USER_BACKUP_ROOT" ] && ls -1d "$NC_USER_BACKUP_ROOT"/*/ 2>/dev/null | sed 's:/$::' || nc_log "  (none)"
    fi
    exit 0
fi

if [ "$SCOPE" = "system" ]; then
    [ "$(id -u)" -eq 0 ] || nc_die "--system backup must run as root (sudo)."
    nc_step "Backing up system theme files"
    nc_system_backup
    if [ -n "$LABEL" ] && [ "$DRY_RUN" = 0 ]; then
        printf 'label=%s\n' "$LABEL" >> "$NC_SYS_BACKUP/manifest.txt"
    fi
    nc_ok "system backup complete: ${NC_SYS_BACKUP:-<dry-run>}"
else
    nc_require_user
    nc_step "Backing up user configuration for ${NC_USER_HOME}"
    nc_user_backup
    if [ -n "$LABEL" ] && [ "$DRY_RUN" = 0 ]; then
        printf 'label=%s\n' "$LABEL" >> "$NC_USER_BACKUP/manifest.txt"
    fi
    nc_ok "user backup complete: ${NC_USER_BACKUP:-<dry-run>}"
fi
[ "$DRY_RUN" = 1 ] && nc_warn "dry run only; no backup was written."
exit 0
