#!/usr/bin/env bash
# NIGHT CITY — restore a user backup created by install.sh or backup.sh.
#
# Restores the snapshotted gsettings values and the files that existed before
# installation. Files added by NIGHT CITY that did not exist before are not
# deleted here; run uninstall.sh for a clean removal.
set -Eeuo pipefail

NC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$NC_SCRIPT_DIR/lib/common.sh"

BACKUP=""
DO_FILES=1
DO_SETTINGS=1
LIST=0

usage() {
    cat <<EOF
${NC_NAME} restore v${NC_VERSION}

Usage: ./scripts/restore.sh [options]

  --list               List available user backups and exit.
  --backup DIR         Restore a specific backup directory
                       (default: the newest one).
  --files-only         Restore files, leave gsettings alone.
  --settings-only      Restore gsettings, leave files alone.
  --home DIR           Operate on a staged HOME (testing).
  -n, --dry-run        Print actions, change nothing.
  -y, --yes            Do not ask for confirmation.
  --no-color           Disable ANSI colour.
  -h, --help           This text.

System files: sudo ./scripts/rollback.sh --system
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --list) LIST=1 ;;
        --backup) BACKUP="${2:-}"; shift ;;
        --backup=*) BACKUP="${1#*=}" ;;
        --files-only) DO_SETTINGS=0 ;;
        --settings-only) DO_FILES=0 ;;
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
nc_require_user

if [ "$LIST" = 1 ]; then
    nc_step "User backups in $NC_USER_BACKUP_ROOT"
    if [ -d "$NC_USER_BACKUP_ROOT" ]; then
        for d in "$NC_USER_BACKUP_ROOT"/*/; do
            [ -d "$d" ] || continue
            d="${d%/}"
            created="$(sed -n 's/^created=//p' "$d/manifest.txt" 2>/dev/null | head -n1)"
            mode="$(sed -n 's/^mode=//p' "$d/manifest.txt" 2>/dev/null | head -n1)"
            label="$(sed -n 's/^label=//p' "$d/manifest.txt" 2>/dev/null | head -n1)"
            printf '  %s  %-9s %s\n' "$(basename "$d")" "${mode:-?}" "${label:-$created}"
        done
    else
        nc_log "  (none)"
    fi
    exit 0
fi

if [ -z "$BACKUP" ]; then
    BACKUP="$(nc_user_backup_latest || true)"
    [ -n "$BACKUP" ] || nc_die "no user backup found in $NC_USER_BACKUP_ROOT"
fi
[ -d "$BACKUP" ] || nc_die "backup not found: $BACKUP"
[ -r "$BACKUP/manifest.txt" ] || nc_die "not a NightCity backup (no manifest.txt): $BACKUP"
if [ "$DO_FILES" = 1 ] && [ "$DO_SETTINGS" = 1 ]; then
    : # both
elif [ "$DO_FILES" = 0 ] && [ "$DO_SETTINGS" = 0 ]; then
    nc_die "--files-only and --settings-only are mutually exclusive"
fi

nc_step "Restoring $(basename "$BACKUP")"
sed 's/^/  /' "$BACKUP/manifest.txt"
nc_confirm "Apply this backup to ${NC_USER_HOME}?" || { nc_warn "aborted by user"; exit 0; }

if [ "$DO_SETTINGS" = 1 ]; then
    nc_step "Restoring gsettings"
    if [ -r "$BACKUP/keys.tsv" ]; then
        nc_restore_keys "$BACKUP"
        nc_ok "settings restored"
    else
        nc_warn "backup has no keys.tsv; settings skipped."
    fi
fi

if [ "$DO_FILES" = 1 ]; then
    nc_step "Restoring files"
    restored=0
    while IFS=$'\t' read -r kind path; do
        [ "$kind" = "file" ] || continue
        [ -n "$path" ] || continue
        src="$BACKUP/files$path"
        [ -e "$src" ] || { nc_warn "missing from backup: $path"; continue; }
        if [ "$DRY_RUN" = 1 ]; then
            printf '%s    dry-run: restore%s %s\n' "$NC_D" "$NC_0" "$path"
        else
            mkdir -p "$(dirname "$path")"
            rm -rf "$path"
            cp -a "$src" "$path"
        fi
        restored=$((restored + 1))
    done < "$BACKUP/manifest.txt"

    while IFS=$'\t' read -r kind path; do
        [ "$kind" = "previous" ] || continue
        [ -n "$path" ] || continue
        src="$BACKUP/previous/$(basename "$path")"
        [ -e "$src" ] || { nc_warn "missing previous theme: $path"; continue; }
        if [ "$DRY_RUN" = 1 ]; then
            printf '%s    dry-run: restore previous theme%s %s\n' "$NC_D" "$NC_0" "$path"
        else
            mkdir -p "$(dirname "$path")"
            rm -rf "$path"
            cp -a "$src" "$path"
        fi
        restored=$((restored + 1))
    done < "$BACKUP/manifest.txt"
    nc_ok "restored $restored item(s)"
fi

if [ "$DRY_RUN" = 0 ] && nc_have gtk-update-icon-cache && [ -d "$NC_ICONS" ]; then
    for d in "$NC_ICONS"/*/; do
        [ -f "$d/index.theme" ] && gtk-update-icon-cache -f -t "$d" >/dev/null 2>&1 || true
    done
fi
if [ "$DRY_RUN" = 0 ] && nc_have fc-cache && [ -d "$HOME/.local/share/fonts" ]; then
    fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true
fi

printf '\n'
nc_ok "restore complete."
nc_log "Sign out and back in so applications and GNOME Shell reload the restored state."
[ "$DRY_RUN" = 1 ] && nc_warn "dry run only; nothing was restored."
exit 0
