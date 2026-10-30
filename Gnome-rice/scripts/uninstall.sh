#!/usr/bin/env bash
# NIGHT CITY — user-level uninstall.
#
# Removes only files this project installed, restores the appearance settings
# that still point at NIGHT CITY, and leaves unrelated themes, extensions,
# terminals and user settings untouched. Backups are kept unless --purge-backups
# is given. System components (GDM/Plymouth) are reverted by rollback.sh.
set -Eeuo pipefail

NC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$NC_SCRIPT_DIR/lib/common.sh"

KEEP_TERMINAL=0
KEEP_SETTINGS=0
RESTORE_ALL=0
PURGE_BACKUPS=0

usage() {
    cat <<EOF
${NC_NAME} uninstall v${NC_VERSION}

Usage: ./scripts/uninstall.sh [options]

Removes NightCity themes, icons, cursors, fonts, wallpapers, terminal
profiles and prompt, then restores appearance settings that still point at
NIGHT CITY. Everything else is preserved.

  -y, --yes             Do not ask for confirmation.
  --keep-terminal       Keep terminal profiles and the shell prompt.
  --keep-settings       Do not touch any gsettings value.
  --restore-all-settings  Restore every key from the install snapshot
                        (may undo changes made after installing).
  --purge-backups       Delete NightCity user backups (irreversible).
  --home DIR            Operate on a staged HOME (testing).
  -n, --dry-run         Print actions, change nothing.
  --no-color            Disable ANSI colour.
  -h, --help            This text.

System themes:
  sudo ./scripts/rollback.sh --system
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        --keep-terminal) KEEP_TERMINAL=1 ;;
        --keep-settings) KEEP_SETTINGS=1 ;;
        --restore-all-settings) RESTORE_ALL=1 ;;
        --purge-backups) PURGE_BACKUPS=1 ;;
        --home) STAGED_HOME="${2:-}"; shift ;;
        --home=*) STAGED_HOME="${1#*=}" ;;
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
nc_require_user

nc_step "Uninstalling ${NC_NAME} from ${NC_USER_HOME}"
nc_confirm "Remove NIGHT CITY from this user account?" || { nc_warn "aborted by user"; exit 0; }

nc_rm() {
    local p
    for p in "$@"; do
        [ -e "$p" ] || [ -L "$p" ] || continue
        if [ "$DRY_RUN" = 1 ]; then
            printf '%s    dry-run: remove%s %s\n' "$NC_D" "$NC_0" "$p"
        else
            rm -rf "$p"
        fi
    done
}

nc_rmdir_empty() {
    local p
    for p in "$@"; do
        [ -d "$p" ] || continue
        if [ "$DRY_RUN" = 0 ] && rmdir "$p" 2>/dev/null; then
            nc_log "  removed empty directory $p"
        fi
    done
}

# ---------------------------------------------------------------------------
# 1. Restore appearance settings, but only where they still point at us.
# ---------------------------------------------------------------------------
if [ "$KEEP_SETTINGS" = 0 ]; then
    nc_step "Restoring appearance settings"
    BACKUP="$(nc_user_backup_latest || true)"
    if [ -z "$BACKUP" ] || [ ! -r "$BACKUP/keys.tsv" ]; then
        nc_warn "no install snapshot found; leaving gsettings unchanged."
        nc_warn "reset manually if needed: gsettings reset org.gnome.desktop.interface gtk-theme"
    elif [ "$RESTORE_ALL" = 1 ]; then
        nc_restore_keys "$BACKUP" && nc_ok "all snapshotted keys restored"
    else
        # key -> value the installer wrote (quoted gsettings form)
        restore_if() {
            local schema="$1" key="$2" expected="$3"
            nc_key_exists "$schema" "$key" || return 0
            local current old
            current="$(gsettings get "$schema" "$key" 2>/dev/null || true)"
            if [ "$current" != "$expected" ]; then
                printf '%s  keep%s %s %s (changed since install)\n' "$NC_D" "$NC_0" "$schema $key" "$current"
                return 0
            fi
            old="$(awk -F '\t' -v s="$schema" -v k="$key" '$1==s && $2==k {print $3; exit}' "$BACKUP/keys.tsv")"
            if [ -z "$old" ]; then
                printf '%s  reset%s %s %s\n' "$NC_D" "$NC_0" "$schema" "$key"
                [ "$DRY_RUN" = 1 ] || gsettings reset "$schema" "$key" 2>/dev/null || true
            else
                nc_gset "$schema" "$key" "$old"
            fi
        }

        restore_if org.gnome.desktop.interface gtk-theme "'NightCity-GTK'"
        restore_if org.gnome.desktop.interface icon-theme "'NightCity-Icons'"
        restore_if org.gnome.desktop.interface cursor-theme "'NightCity-Cursor'"
        restore_if org.gnome.desktop.interface cursor-size "24"
        restore_if org.gnome.desktop.interface font-name "'Space Grotesk 10.5'"
        restore_if org.gnome.desktop.interface document-font-name "'Space Grotesk 11'"
        restore_if org.gnome.desktop.interface monospace-font-name "'JetBrains Mono 10.5'"
        restore_if org.gnome.desktop.wm.preferences titlebar-font "'Rajdhani Bold 10.5'"
        restore_if org.gnome.shell.extensions.user-theme name "'NightCity-Shell'"

        for pair in "org.gnome.desktop.background picture-uri" \
                    "org.gnome.desktop.background picture-uri-dark" \
                    "org.gnome.desktop.screensaver picture-uri"; do
            schema="${pair% *}"; key="${pair##* }"
            nc_key_exists "$schema" "$key" || continue
            current="$(gsettings get "$schema" "$key" 2>/dev/null || true)"
            case "$current" in
                *nightcity*) restore_if "$schema" "$key" "$current" ;;
            esac
        done
        nc_ok "appearance restored (values changed after install were left alone)"
    fi
fi

# ---------------------------------------------------------------------------
# 2. Remove files
# ---------------------------------------------------------------------------
nc_step "Removing theme and asset files"
nc_rm "$NC_THEMES/NightCity-GTK" "$NC_THEMES/NightCity-Shell" \
      "$NC_ICONS/NightCity-Icons" "$NC_ICONS/NightCity-Cursor" \
      "$NC_FONTS" "$NC_BG"

# libadwaita override: only delete if it is still ours.
if [ -f "$NC_GTK4_CSS" ] && head -n 3 "$NC_GTK4_CSS" | grep "NIGHT CITY" >/dev/null; then
    nc_rm "$NC_GTK4_CSS"
fi
if [ -f "$NC_GTK4_CSS.nightcity-prev" ]; then
    if [ "$DRY_RUN" = 1 ]; then
        printf '%s    dry-run: restore previous gtk-4.0/gtk.css%s\n' "$NC_D" "$NC_0"
    else
        mv -f "$NC_GTK4_CSS.nightcity-prev" "$NC_GTK4_CSS"
        nc_ok "previous ~/.config/gtk-4.0/gtk.css restored"
    fi
fi

if [ "$KEEP_TERMINAL" = 0 ]; then
    nc_step "Removing terminal profiles and prompt"
    nc_rm "$NC_CONFIG/kitty/nightcity.conf" \
          "$NC_CONFIG/alacritty/nightcity.toml" \
          "${XDG_DATA_HOME:-$HOME/.local/share}/org.gnome.Ptyxis/palettes/nightcity.palette" \
          "${XDG_DATA_HOME:-$HOME/.local/share}/tilix/schemes/nightcity.json" \
          "$NC_PROMPT"

    # Remove the marked include block from kitty.conf, nothing else.
    if [ -f "$NC_CONFIG/kitty/kitty.conf" ] && grep -qF '# >>> NIGHT CITY >>>' "$NC_CONFIG/kitty/kitty.conf"; then
        if [ "$DRY_RUN" = 1 ]; then
            printf '%s    dry-run: strip NIGHT CITY include from kitty.conf%s\n' "$NC_D" "$NC_0"
        else
            python3 - "$NC_CONFIG/kitty/kitty.conf" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
out, skip = [], False
for line in p.read_text(encoding="utf-8").splitlines(True):
    if line.strip() == "# >>> NIGHT CITY >>>":
        skip = True
        continue
    if line.strip() == "# <<< NIGHT CITY <<<":
        skip = False
        continue
    if not skip:
        out.append(line)
p.write_text("".join(out), encoding="utf-8")
PY
        fi
    fi

    # Remove the marked prompt block from shell rc files.
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [ -f "$rc" ] || continue
        grep -qF '# >>> NIGHT CITY PROMPT >>>' "$rc" || continue
        if [ "$DRY_RUN" = 1 ]; then
            printf '%s    dry-run: strip NIGHT CITY prompt from %s%s\n' "$NC_D" "$NC_0" "$rc"
        else
            python3 - "$rc" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
out, skip = [], False
for line in p.read_text(encoding="utf-8").splitlines(True):
    if line.strip() == "# >>> NIGHT CITY PROMPT >>>":
        skip = True
        continue
    if line.strip() == "# <<< NIGHT CITY PROMPT <<<":
        skip = False
        continue
    if not skip:
        out.append(line)
p.write_text("".join(out), encoding="utf-8")
PY
            nc_ok "prompt block removed from $rc"
        fi
    done

    # GNOME Terminal profile
    if nc_have dconf; then
        uuid="6e696768-7420-4369-7479-000000000001"
        nc_run dconf reset -f "/org/gnome/terminal/legacy/profiles:/:$uuid/" || true
        if nc_key_exists org.gnome.Terminal.ProfilesList list; then
            list="$(gsettings get org.gnome.Terminal.ProfilesList list 2>/dev/null || true)"
            case "$list" in
                *"$uuid"*)
                    cleaned="$(printf '%s' "$list" | sed "s/, *'$uuid'//; s/'$uuid', *//; s/'$uuid'//")"
                    nc_gset org.gnome.Terminal.ProfilesList list "$cleaned"
                    ;;
            esac
        fi
    fi
    nc_rmdir_empty "$NC_CONFIG/nightcity"
else
    nc_warn "kept terminal profiles and shell prompt (--keep-terminal)"
fi

# ---------------------------------------------------------------------------
# 3. oh-my-posh (only files recorded as installed by us)
# ---------------------------------------------------------------------------
OMP_STATE="$NC_STATE/nightcity/ohmyposh.tsv"
if [ -f "$OMP_STATE" ]; then
    nc_step "Removing oh-my-posh prompt files"
    while IFS=$'\t' read -r kind path; do
        [ -n "$path" ] || continue
        case "$path" in
            "$HOME"/*) nc_rm "$path" ;;
            *) nc_warn "refusing to remove path outside HOME: $path" ;;
        esac
    done < "$OMP_STATE"
    nc_rm "$HOME/.cache/oh-my-posh"
    nc_ok "oh-my-posh removed; the native NIGHT CITY prompt returns in new shells"
fi

# ---------------------------------------------------------------------------
# 4. State and backups
# ---------------------------------------------------------------------------
nc_rm "$NC_STATE/nightcity/installed.tsv" "$OMP_STATE"
if [ "$PURGE_BACKUPS" = 1 ]; then
    nc_warn "--purge-backups also deletes the snapshots that rollback depends on."
    if nc_confirm "Delete ALL NightCity user backups?"; then
        nc_rm "$NC_USER_BACKUP_ROOT"
    else
        nc_warn "backups kept."
    fi
fi

nc_rmdir_empty "$NC_THEMES" "$NC_ICONS" "$NC_BG" "$NC_CONFIG/nightcity" \
               "$(dirname "$NC_USER_BACKUP")" "$NC_STATE/nightcity"

printf '\n'
nc_ok "NIGHT CITY removed for ${NC_USER_HOME}."
[ "$KEEP_SETTINGS" = 0 ] && nc_log "Sign out and back in to fully drop the shell theme."
[ -d "${NC_SYS_BACKUP_DIR:-/var/backups/nightcity}" ] && \
    nc_log "System changes (GDM/Plymouth) are reverted with: sudo $NC_ROOT/scripts/rollback.sh --system"
[ "$DRY_RUN" = 1 ] && nc_warn "dry run only; nothing was removed."
exit 0
