#!/usr/bin/env bash
# NIGHT CITY — portable installer.
#
# Standard : user themes, icons, cursors, fonts, wallpapers, GTK4 layer,
#            shell theme, appearance settings.  No root, no system files.
# Full     : Standard + extension tuning, terminal profiles/default,
#            shell prompt, lock-screen wallpaper.
# Advanced : Full + optional GDM greeter and Plymouth boot theme (root,
#            explicitly confirmed, backed up, reversible).
#
# Examples:
#   ./scripts/install.sh                       # interactive, Standard
#   ./scripts/install.sh --mode full -y        # unattended Full
#   ./scripts/install.sh --mode advanced       # asks before GDM/Plymouth
#   ./scripts/install.sh --mode advanced --gdm --plymouth -y
#   ./scripts/install.sh --home /tmp/stage     # file-only staged test
set -Eeuo pipefail

NC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$NC_SCRIPT_DIR/lib/common.sh"

MODE="standard"
WITH_GDM=0
WITH_PLYMOUTH=0
APPLY_GSETTINGS=1
WITH_PROMPT="auto"
TERMINAL_DEFAULT="auto"
WITH_OHMYPOSH=0
SYSTEM_ONLY=0
FORCE=0

usage() {
    cat <<EOF
${NC_NAME} installer v${NC_VERSION}

Usage: ./scripts/install.sh [options]

Modes (default: standard)
  --mode standard   User-level visual install. No root.
  --mode full       Standard + extension tuning, terminal default, shell prompt.
  --mode advanced   Full + optional GDM greeter / Plymouth boot theme.

System components (advanced; each is confirmed and backed up)
  --gdm             Install the GDM greeter theme (requires root).
  --plymouth        Install the Plymouth boot theme (requires root).
  --system-only     Only run the system component(s) above.
  --force           Proceed even if the GNOME major version differs.

Fine tuning
  --ohmyposh        Also install oh-my-posh + the bundled Catppuccin theme
                    and JetBrainsMono Nerd Font (user-level, network download).
  --no-gsettings    Install files only; do not touch gsettings.
  --no-shell-prompt Do not add the prompt source line to .bashrc/.zshrc.
  --no-terminal-default  Do not make the NIGHT CITY terminal profile default.
  --home DIR        Stage into DIR instead of \$HOME (testing only).
  -n, --dry-run     Print actions, change nothing.
  -y, --yes         Assume yes for confirmations (not a substitute for sudo).
  --no-color        Disable ANSI colour.
  -h, --help        This text.

Backups
  User:   \${XDG_STATE_HOME:-\$HOME/.local/state}/nightcity/backups/<timestamp>
  System: /var/backups/nightcity/<timestamp>

Rollback: ./scripts/uninstall.sh          (user)
          sudo ./scripts/rollback.sh --system
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --mode) MODE="${2:-}"; shift ;;
        --mode=*) MODE="${1#*=}" ;;
        --gdm|--with-gdm) WITH_GDM=1 ;;
        --plymouth|--with-plymouth) WITH_PLYMOUTH=1 ;;
        --system-only) SYSTEM_ONLY=1 ;;
        --no-gsettings) APPLY_GSETTINGS=0 ;;
        --no-shell-prompt) WITH_PROMPT=0 ;;
        --no-terminal-default) TERMINAL_DEFAULT=0 ;;
        --ohmyposh|--with-ohmyposh) WITH_OHMYPOSH=1 ;;
        --force) FORCE=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        --home) STAGED_HOME="${2:-}"; shift ;;
        --home=*) STAGED_HOME="${1#*=}" ;;
        --no-color) NO_COLOR=1; NC_R=''; NC_C=''; NC_W=''; NC_D=''; NC_B=''; NC_0='' ;;
        -h|--help) usage; exit 0 ;;
        *) nc_die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

case "$MODE" in
    standard|full|advanced) ;;
    *) nc_die "invalid --mode '$MODE' (standard|full|advanced)" ;;
esac

nc_banner
nc_paths
nc_detect
nc_step "System"
nc_print_detect

if [ "$SYSTEM_ONLY" = 1 ]; then
    [ "$(id -u)" -eq 0 ] || nc_die "--system-only must run as root (use sudo)."
    if [ "$WITH_GDM" = 0 ] && [ "$WITH_PLYMOUTH" = 0 ]; then
        nc_die "--system-only needs --gdm and/or --plymouth."
    fi
else
    nc_require_user
fi

# --- preflight --------------------------------------------------------------
need_file() { [ -e "$1" ] || nc_die "missing build artifact: ${1#$NC_ROOT/}. Run ./scripts/build-all.sh first."; }
if [ "$SYSTEM_ONLY" = 0 ]; then
    need_file "$NC_ROOT/themes/NightCity-GTK/gtk-3.0/gtk.css"
    need_file "$NC_ROOT/themes/NightCity-GTK/gtk-4.0-user.css"
    need_file "$NC_ROOT/themes/NightCity-Shell/gnome-shell/gnome-shell.css"
    need_file "$NC_ROOT/icons/NightCity-Icons/index.theme"
    need_file "$NC_ROOT/cursors/NightCity-Cursor/cursor.theme"
    need_file "$NC_ROOT/assets/wallpapers/nightcity-01-nightline.png"
fi

if [ "$MODE" = "advanced" ] || [ "$SYSTEM_ONLY" = 1 ]; then
    if [ "$WITH_GDM" = 0 ] && [ "$WITH_PLYMOUTH" = 0 ] && [ "$ASSUME_YES" = 0 ] && [ -t 0 ]; then
        nc_confirm "Configure the GDM login screen? (root, backed up)" && WITH_GDM=1 || true
        nc_confirm "Configure the Plymouth boot theme? (root, backed up)" && WITH_PLYMOUTH=1 || true
    fi
fi

if [ "$SYSTEM_ONLY" = 0 ]; then
    nc_confirm "Install ${NC_NAME} (${MODE}) for ${NC_USER_HOME}?" || { nc_warn "aborted by user"; exit 0; }
    if [ "$APPLY_GSETTINGS" = 0 ]; then
        nc_warn "gsettings will not be changed (files only)."
    fi
    if ! nc_check_gnome_major 50; then
        [ "$FORCE" = 1 ] || nc_die "refusing to apply on GNOME ${NC_GNOME_MAJOR}. Re-run with --force to override."
    fi
fi

# --- system-only branch -----------------------------------------------------
if [ "$SYSTEM_ONLY" = 1 ]; then
    if [ "$WITH_GDM" = 1 ]; then
        args=()
        [ "$FORCE" = 1 ] && args+=(--force)
        [ "$ASSUME_YES" = 1 ] && args+=(--yes)
        [ "$DRY_RUN" = 1 ] && args+=(--dry-run)
        "$NC_SCRIPT_DIR/configure-gdm.sh" "${args[@]}"
    fi
    [ "$WITH_PLYMOUTH" = 1 ] && "$NC_SCRIPT_DIR/configure-plymouth.sh"
    nc_ok "system components complete. Reboot to see GDM/Plymouth changes."
    exit 0
fi

# --- user install -----------------------------------------------------------
MANIFEST="$NC_STATE/nightcity/installed.tsv"
PRIOR_BACKUP=""
if [ -f "$MANIFEST" ]; then
    PRIOR_BACKUP="$(sed -n 's/^backup=//p' "$MANIFEST" | head -n1)"
fi
if [ -n "$PRIOR_BACKUP" ] && [ -d "$PRIOR_BACKUP" ]; then
    # Re-installing over NIGHT CITY must not snapshot NIGHT CITY as the
    # "previous" state, or uninstall would restore the theme it should remove.
    NC_USER_BACKUP="$PRIOR_BACKUP"
    nc_step "Reusing the original user backup"
    nc_ok "original backup: $NC_USER_BACKUP"
else
    nc_step "Backing up user state"
    nc_user_backup
fi
nc_mkdir "$(dirname "$MANIFEST")"
if [ "$DRY_RUN" = 0 ]; then
    {
        echo "# NIGHT CITY installed paths"
        echo "version=$NC_VERSION"
        echo "mode=$MODE"
        echo "installed=$NC_TIMESTAMP"
        echo "backup=$NC_USER_BACKUP"
    } > "$MANIFEST"
fi
nc_manifest() {
    [ "$DRY_RUN" = 1 ] && return 0
    printf '%s\t%s\n' "$1" "$2" >> "$MANIFEST"
}

nc_step "Installing themes"
nc_gtk_theme_install
nc_manifest theme "$NC_THEMES/NightCity-GTK"
nc_manifest theme "$NC_THEMES/NightCity-Shell"

nc_step "Installing icons and cursors"
nc_icon_install
nc_manifest icons "$NC_ICONS/NightCity-Icons"
nc_cursor_install
nc_manifest cursors "$NC_ICONS/NightCity-Cursor"

nc_step "Installing fonts"
nc_font_install
nc_manifest fonts "$NC_FONTS"

nc_step "Installing wallpapers"
nc_wallpaper_install
nc_manifest wallpapers "$NC_BG"
nc_manifest gtk4 "$NC_GTK4_CSS"

nc_step "Installing libadwaita (GTK4) layer"
nc_gtk4_user_install

nc_step "Installing terminal profiles"
nc_terminal_install
nc_manifest terminal "$NC_CONFIG/kitty/nightcity.conf"

if [ "$WITH_OHMYPOSH" = 1 ]; then
    nc_step "Installing oh-my-posh prompt"
    omp_args=(--home "$NC_USER_HOME")
    [ "$ASSUME_YES" = 1 ] && omp_args+=(--yes)
    [ "$DRY_RUN" = 1 ] && omp_args+=(--dry-run)
    "$NC_SCRIPT_DIR/install-ohmyposh.sh" "${omp_args[@]}"
    nc_manifest ohmyposh "$NC_CONFIG/nightcity/catppuccin.omp.json"
fi

# --- appearance -------------------------------------------------------------
if [ "$APPLY_GSETTINGS" = 1 ]; then
    nc_step "Applying appearance settings"
    nc_gset org.gnome.desktop.interface gtk-theme "NightCity-GTK"
    nc_gset org.gnome.desktop.interface icon-theme "NightCity-Icons"
    nc_gset org.gnome.desktop.interface cursor-theme "NightCity-Cursor"
    nc_gset org.gnome.desktop.interface cursor-size 24
    nc_gset org.gnome.desktop.interface color-scheme "'prefer-dark'"
    nc_gset org.gnome.desktop.interface accent-color "'red'"
    nc_gset org.gnome.desktop.interface enable-animations true
    nc_gset org.gnome.desktop.interface font-name "Space Grotesk 10.5"
    nc_gset org.gnome.desktop.interface document-font-name "Space Grotesk 11"
    nc_gset org.gnome.desktop.interface monospace-font-name "JetBrains Mono 10.5"
    nc_gset org.gnome.desktop.wm.preferences titlebar-font "Rajdhani Bold 10.5"

    WALL="file://$NC_BG/nightcity-01-nightline.png"
    LOCK="file://$NC_BG/nightcity-06-signal.png"
    nc_gset org.gnome.desktop.background picture-uri "\"$WALL\""
    nc_gset org.gnome.desktop.background picture-uri-dark "\"$WALL\""
    nc_gset org.gnome.desktop.background picture-options "'zoom'"
    nc_gset org.gnome.desktop.screensaver picture-uri "\"$LOCK\""

    if [ "$NC_HAVE_USER_THEME" = "yes" ]; then
        nc_gset org.gnome.shell.extensions.user-theme name "NightCity-Shell"
        nc_ok "GNOME Shell theme set (loads live through user-theme)"
    else
        nc_warn "user-theme extension is not available; shell theme was installed but not activated."
        nc_warn "Install gnome-shell-extensions (or your distro's equivalent), then re-run."
    fi
else
    nc_warn "skipped appearance settings; theme files are installed but inactive."
fi

# --- full / advanced extras --------------------------------------------------
if [ "$MODE" = "full" ] || [ "$MODE" = "advanced" ]; then
    if [ "$APPLY_GSETTINGS" = 1 ]; then
        nc_step "Configuring GNOME Shell extensions"
        # Run the centralized extension configuration script
        ext_args=()
        [ "$DRY_RUN" = 1 ] && ext_args+=(--dry-run)
        [ "$ASSUME_YES" = 1 ] && ext_args+=(--yes)
        [ -n "$NO_COLOR" ] && ext_args+=(--no-color)
        "$NC_SCRIPT_DIR/../extensions/configuration/apply-extensions.sh" "${ext_args[@]}"

        # Terminal default profile
        if [ "$TERMINAL_DEFAULT" != 0 ] && nc_key_exists org.gnome.Terminal.ProfilesList default; then
            nc_gset org.gnome.Terminal.ProfilesList default "'6e696768-7420-4369-7479-000000000001'"
            nc_ok "GNOME Terminal: NIGHT CITY profile is default"
        fi
    fi

    if [ "$WITH_PROMPT" != 0 ]; then
        nc_step "Installing shell prompt"
        for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
            [ -f "$rc" ] || continue
            if ! grep -qF '# >>> NIGHT CITY PROMPT >>>' "$rc"; then
                if [ "$DRY_RUN" = 1 ]; then
                    printf '%s    dry-run: append prompt source to %s%s\n' "$NC_D" "$NC_0" "$rc"
                else
                    {
                        printf '\n# >>> NIGHT CITY PROMPT >>>\n'
                        printf '[ -f "%s" ] && . "%s"\n' "$NC_PROMPT" "$NC_PROMPT"
                        printf '# <<< NIGHT CITY PROMPT <<<\n'
                    } >> "$rc"
                fi
                nc_ok "prompt added to $rc (open a new shell)"
            fi
        done
    fi
fi

# --- advanced: system components --------------------------------------------
if [ "$MODE" = "advanced" ]; then
    SUDO=""
    if [ "$(id -u)" -ne 0 ]; then
        nc_have sudo || nc_die "advanced system install needs sudo (or run as root)."
        SUDO="sudo"
    fi

    if [ "$WITH_GDM" = 1 ]; then
        nc_step "GDM greeter (system)"
        if nc_confirm "Replace the system GNOME Shell gresource for GDM? A backup will be kept."; then
            args=()
            [ "$FORCE" = 1 ] && args+=(--force)
            [ "$ASSUME_YES" = 1 ] && args+=(--yes)
            [ "$DRY_RUN" = 1 ] && args+=(--dry-run)
            $SUDO "$NC_SCRIPT_DIR/configure-gdm.sh" "${args[@]}"
        else
            nc_warn "GDM step skipped."
        fi
    fi
    if [ "$WITH_PLYMOUTH" = 1 ]; then
        nc_step "Plymouth boot theme (system)"
        if nc_confirm "Install the Plymouth theme and rebuild the initramfs?"; then
            args=()
            [ "$ASSUME_YES" = 1 ] && args+=(--yes)
            [ "$DRY_RUN" = 1 ] && args+=(--dry-run)
            $SUDO "$NC_SCRIPT_DIR/configure-plymouth.sh" "${args[@]}"
        else
            nc_warn "Plymouth step skipped."
        fi
    fi
fi

# --- summary ----------------------------------------------------------------
printf '\n'
nc_ok "${NC_NAME} ${MODE} install complete."
nc_log "  Backup:    $NC_USER_BACKUP"
[ "$MODE" = "advanced" ] && nc_log "  Restore:   sudo $NC_ROOT/scripts/rollback.sh --system"
nc_log "  Uninstall: $NC_ROOT/scripts/uninstall.sh"
nc_log ""
nc_log "Some applications cache their theme. Sign out and back in for the full effect."
nc_log "GTK4/libadwaita apps, the lock screen and GDM need a new session/reboot."
if [ "$DRY_RUN" = 1 ]; then
    nc_warn "This was a dry run; nothing was changed."
fi
