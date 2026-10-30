#!/usr/bin/env bash
# NIGHT CITY — Terminal Uninstallation Script
# Restores backed-up configurations and removes NightCity terminal configs.

set -Eeuo pipefail

NC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$NC_SCRIPT_DIR/lib/common.sh"

NC_VERSION="1.0.0"
NC_NAME="NIGHTCITY TERMINAL"

CONFIG_DIR="$HOME/.config/nightcity"
BACKUP_BASE="$HOME/.config/nightcity/backups"

usage() {
    cat <<EOF
${NC_NAME} Uninstaller v${NC_VERSION}

Usage: ./scripts/uninstall-terminal.sh [options]

Restores terminal and shell configurations from the most recent backup.

Options:
  --backup-dir DIR    Use specific backup directory (default: latest)
  --list-backups      List available backups and exit
  --dry-run           Show what would be restored without changes
  --force             Skip confirmation prompts
  -h, --help          Show this help

EOF
}

list_backups() {
    if [ ! -d "$BACKUP_BASE" ]; then
        nc_warn "No backup directory found at $BACKUP_BASE"
        return 1
    fi

    local backups=()
    while IFS= read -r -d '' dir; do
        backups+=("$dir")
    done < <(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -print0 | sort -zV)

    if [ ${#backups[@]} -eq 0 ]; then
        nc_warn "No backups found"
        return 1
    fi

    echo "Available backups:"
    for backup in "${backups[@]}"; do
        local name=$(basename "$backup")
        local date_str=$(echo "$name" | sed 's/\(....\)\(..\)\(..\)-\(..\)\(..\)\(..\)/\1-\2-\3 \4:\5:\6/')
        echo "  $name  ($date_str)"
    done
}

find_latest_backup() {
    if [ ! -d "$BACKUP_BASE" ]; then
        echo ""
        return 0
    fi
    local output
    output=$(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1) || true
    [ -n "$output" ] && echo "$output" | cut -d' ' -f2- || echo ""
}

restore_file() {
    local backup_file="$1"
    local target_file="$2"

    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            nc_log "[DRY RUN] Would remove NightCity block from $target_file (no backup)"
        else
            remove_nightcity_block "$target_file"
        fi
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        nc_log "[DRY RUN] Would restore $target_file from backup"
        return 0
    fi

    mkdir -p "$(dirname "$target_file")"
    cp "$backup_file" "$target_file"
    nc_log "Restored: $target_file"
}

remove_nightcity_block() {
    local rc_file="$1"

    if [ ! -f "$rc_file" ]; then
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        nc_log "[DRY RUN] Would remove NIGHT CITY block from $rc_file"
        return 0
    fi

    # Remove the block between markers
    sed -i '/# NIGHT CITY TERMINAL/,/# END NIGHT CITY TERMINAL/d' "$rc_file"
    nc_log "Removed NIGHT CITY block from $rc_file"
}

main() {
    local backup_dir=""
    local list_only=0
    DRY_RUN=0
    FORCE=0

    while [[ $# -gt 0 ]]; do
        case $1 in
            --backup-dir) backup_dir="$2"; shift 2 ;;
            --list-backups) list_only=1; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            --force) FORCE=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) nc_die "Unknown option: $1" ;;
        esac
    done

    if [ "$list_only" -eq 1 ]; then
        list_backups
        exit 0
    fi

    if [ -z "$backup_dir" ]; then
        backup_dir=$(find_latest_backup)
        if [ -z "$backup_dir" ]; then
            if [ "$DRY_RUN" -eq 1 ]; then
                nc_warn "No backup found. Dry-run will show what would be removed."
                backup_dir=""
            else {
                nc_die "No backup found. Use --backup-dir to specify one."
            } fi
        fi
    fi

    if [ -n "$backup_dir" ] && [ ! -d "$backup_dir" ]; then
        nc_die "Backup directory not found: $backup_dir"
    fi

    nc_log "${NC_NAME} uninstaller v${NC_VERSION}"
    nc_log "Using backup: $backup_dir"

    if [ "$DRY_RUN" -eq 1 ]; then
        nc_warn "DRY RUN MODE - no changes will be made"
    fi

    if [ "$FORCE" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
        if ! nc_confirm "Restore configurations from backup and remove NightCity configs?"; then
            nc_log "Aborted."
            exit 0
        fi
    fi

    # Restore shell rc files
    for rc in ".bashrc" ".zshrc"; do
        local backup_rc=""
        [ -n "$backup_dir" ] && backup_rc="$backup_dir/$rc"
        local target_rc="$HOME/$rc"
        restore_file "$backup_rc" "$target_rc"
    done

    # Restore terminal configs
    local terminals=(
        ".config/kitty/nightcity.conf"
        ".config/alacritty/nightcity.toml"
        ".local/share/org.gnome.Ptyxis/palettes/nightcity.palette"
        ".config/tilix/nightcity.json"
    )

    for term_config in "${terminals[@]}"; do
        local backup_tc=""
        [ -n "$backup_dir" ] && backup_tc="$backup_dir/$term_config"
        local target_tc="$HOME/$term_config"
        if [ -n "$backup_tc" ] && [ -f "$backup_tc" ]; then
            restore_file "$backup_tc" "$target_tc"
        elif [ -f "$target_tc" ]; then
            if [ "$DRY_RUN" -eq 1 ]; then
                nc_log "[DRY RUN] Would remove $target_tc (no backup)"
            else
                rm -f "$target_tc"
                nc_log "Removed: $target_tc"
            fi
        fi
    done

    # Remove GNOME Terminal profile (optional - user may want to keep)
    if [ "$FORCE" -eq 1 ] || nc_confirm "Remove NIGHT CITY GNOME Terminal profile?"; then
        if [ "$DRY_RUN" -eq 1 ]; then
            nc_log "[DRY RUN] Would remove GNOME Terminal profile"
        else
            local profile_uuid="6e696768-7420-4369-7479-000000000001"
            dconf reset -f "/org/gnome/terminal/legacy/profiles:/:$profile_uuid/" 2>/dev/null || true
            nc_log "Removed GNOME Terminal profile"
        fi
    fi

    # Remove NightCity config directory
    if [ "$DRY_RUN" -eq 1 ]; then
        nc_log "[DRY RUN] Would remove $CONFIG_DIR"
    else
        rm -rf "$CONFIG_DIR"
        nc_log "Removed config directory: $CONFIG_DIR"
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        nc_warn "DRY RUN complete. Run without --dry-run to apply changes."
    else
        nc_log ""
        nc_log "Uninstallation complete!"
        nc_log "Restart your shell: exec \$SHELL"
    fi
}

main "$@"