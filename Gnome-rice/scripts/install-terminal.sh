#!/usr/bin/env bash
# NIGHT CITY — Terminal Installation Script
# Installs terminal configurations for detected emulators and shell.

set -Eeuo pipefail

NC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NC_ROOT_DIR="$(dirname "$NC_SCRIPT_DIR")"
# shellcheck source=lib/common.sh
. "$NC_SCRIPT_DIR/lib/common.sh"

NC_VERSION="1.0.0"
NC_NAME="NIGHTCITY TERMINAL"

CONFIG_DIR="$HOME/.config/nightcity"
BACKUP_DIR="$HOME/.config/nightcity/backups/$(date +%Y%m%d-%H%M%S)"

TERMINAL_DIR="$NC_ROOT_DIR/terminal"
SHELL_DIR="$TERMINAL_DIR/shell"

usage() {
    cat <<EOF
${NC_NAME} v${NC_VERSION}

Usage: ./scripts/install-terminal.sh [options]

Installs NIGHT CITY terminal configurations for your shell and terminal emulator.

Options:
  --shell bash|zsh|auto    Target shell (default: auto-detect)
  --terminal all|gnome|kitty|alacritty|ptyxis|tilix|auto
                           Terminal emulator(s) to configure (default: auto-detect)
  --prompt native|omp|auto Prompt system (default: auto - use omp if installed)
  --banner                 Install startup banner (default: yes)
  --dashboard              Install system dashboard alias (default: yes)
  --dry-run                Show what would be done without changes
  --force                  Overwrite existing configs without prompting
  -h, --help               Show this help

Examples:
  ./scripts/install-terminal.sh                    # Auto-detect everything
  ./scripts/install-terminal.sh --shell zsh --terminal kitty
  ./scripts/install-terminal.sh --dry-run
  ./scripts/install-terminal.sh --force

EOF
}

SHELL_CHOICE="auto"
TERMINAL_CHOICE="auto"
PROMPT_CHOICE="auto"
INSTALL_BANNER=1
INSTALL_DASHBOARD=1
DRY_RUN=0
FORCE=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --shell) SHELL_CHOICE="$2"; shift 2 ;;
        --terminal) TERMINAL_CHOICE="$2"; shift 2 ;;
        --prompt) PROMPT_CHOICE="$2"; shift 2 ;;
        --banner) INSTALL_BANNER=1; shift ;;
        --no-banner) INSTALL_BANNER=0; shift ;;
        --dashboard) INSTALL_DASHBOARD=1; shift ;;
        --no-dashboard) INSTALL_DASHBOARD=0; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --force) FORCE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) nc_die "Unknown option: $1" ;;
    esac
done

detect_shell() {
    if [ "$SHELL_CHOICE" != "auto" ]; then
        echo "$SHELL_CHOICE"
        return
    fi
    case "$SHELL" in
        */zsh) echo "zsh" ;;
        */bash) echo "bash" ;;
        *) echo "bash" ;;
    esac
}

detect_terminals() {
    local detected=()
    if [ "$TERMINAL_CHOICE" != "auto" ]; then
        if [ "$TERMINAL_CHOICE" = "all" ]; then
            echo "gnome kitty alacritty ptyxis tilix"
            return
        fi
        echo "$TERMINAL_CHOICE"
        return
    fi

    command -v gnome-terminal >/dev/null 2>&1 && detected+=("gnome")
    command -v kitty >/dev/null 2>&1 && detected+=("kitty")
    command -v alacritty >/dev/null 2>&1 && detected+=("alacritty")
    command -v ptyxis >/dev/null 2>&1 && detected+=("ptyxis")
    command -v tilix >/dev/null 2>&1 && detected+=("tilix")

    echo "${detected[*]}"
}

backup_file() {
    local file="$1"
    [ -e "$file" ] || return 0
    mkdir -p "$BACKUP_DIR"
    local rel="${file#$HOME/}"
    cp -a "$file" "$BACKUP_DIR/$rel"
    nc_log "Backed up: $rel"
}

install_shell_configs() {
    local target_shell="$1"
    local rc_file
    case "$target_shell" in
        zsh) rc_file="$HOME/.zshrc" ;;
        bash) rc_file="$HOME/.bashrc" ;;
        *) nc_die "Unknown shell: $target_shell" ;;
    esac

    nc_log "Installing shell configs for $target_shell..."

    mkdir -p "$CONFIG_DIR"

    # Copy prompt, banner, dashboard to config dir
    for f in nightcity-prompt.sh banner.sh dashboard.sh; do
        if [ -f "$SHELL_DIR/$f" ]; then
            if [ "$DRY_RUN" -eq 1 ]; then
                nc_log "[DRY RUN] Would copy $f to $CONFIG_DIR/"
            else
                cp "$SHELL_DIR/$f" "$CONFIG_DIR/"
                nc_log "Installed: $CONFIG_DIR/$f"
            fi
        fi
    done

    # Copy palette
    if [ -f "$TERMINAL_DIR/colors/nightcity-palette.conf" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            nc_log "[DRY RUN] Would copy palette to $CONFIG_DIR/"
        else
            cp "$TERMINAL_DIR/colors/nightcity-palette.conf" "$CONFIG_DIR/"
            nc_log "Installed: $CONFIG_DIR/nightcity-palette.conf"
        fi
    fi

    # Backup and update shell rc
    if [ "$DRY_RUN" -eq 1 ]; then
        nc_log "[DRY RUN] Would backup and update $rc_file"
        return
    fi

    backup_file "$rc_file"

    # Build source block
    local source_block="
# NIGHT CITY TERMINAL
[ -f \"$CONFIG_DIR/nightcity-palette.conf\" ] && . \"$CONFIG_DIR/nightcity-palette.conf\"
[ -f \"$CONFIG_DIR/nightcity-prompt.sh\" ] && . \"$CONFIG_DIR/nightcity-prompt.sh\"
"

    if [ "$INSTALL_BANNER" -eq 1 ]; then
        source_block+="[ -f \"$CONFIG_DIR/banner.sh\" ] && . \"$CONFIG_DIR/banner.sh\"
"
    fi

    if [ "$INSTALL_DASHBOARD" -eq 1 ]; then
        source_block+="[ -f \"$CONFIG_DIR/dashboard.sh\" ] && . \"$CONFIG_DIR/dashboard.sh\"
alias ncd='nightcity_dashboard'
"
    fi

    # Check if already present
    if grep -q "NIGHT CITY TERMINAL" "$rc_file" 2>/dev/null; then
        if [ "$FORCE" -eq 1 ]; then
            # Remove old block
            sed -i '/# NIGHT CITY TERMINAL/,/^# END NIGHT CITY TERMINAL/d' "$rc_file"
        else
            nc_warn "NIGHT CITY config already in $rc_file. Use --force to overwrite."
            return
        fi
    fi

    # Append new block
    {
        echo "$source_block"
        echo "# END NIGHT CITY TERMINAL"
    } >> "$rc_file"

    nc_log "Updated $rc_file"
}

install_gnome_terminal() {
    nc_log "Installing GNOME Terminal profile..."

    local profile_uuid="6e696768-7420-4369-7479-000000000001"
    local profile_path="/org/gnome/terminal/legacy/profiles:/:$profile_uuid/"

    if [ "$DRY_RUN" -eq 1 ]; then
        nc_log "[DRY RUN] Would load dconf profile to $profile_path"
        return
    fi

    if ! command -v dconf >/dev/null 2>&1; then
        nc_warn "dconf not found, skipping GNOME Terminal profile"
        return
    fi

    dconf load "$profile_path" < "$TERMINAL_DIR/gnome-terminal/nightcity.dconf"
    nc_log "Loaded GNOME Terminal profile"

    # Optionally set as default
    if [ "$FORCE" -eq 1 ] || nc_confirm "Set NIGHT CITY as default GNOME Terminal profile?"; then
        gsettings set org.gnome.Terminal.ProfilesList default "'$profile_uuid'"
        nc_log "Set as default profile"
    fi
}

install_kitty() {
    nc_log "Installing Kitty configuration..."

    local kitty_dir="$HOME/.config/kitty"
    local target="$kitty_dir/nightcity.conf"

    if [ "$DRY_RUN" -eq 1 ]; then
        nc_log "[DRY RUN] Would copy kitty config to $target"
        return
    fi

    mkdir -p "$kitty_dir"
    backup_file "$target"
    cp "$TERMINAL_DIR/kitty/nightcity.conf" "$target"
    nc_log "Installed: $target"

    # Check if included in kitty.conf
    local main_conf="$kitty_dir/kitty.conf"
    if [ -f "$main_conf" ] && ! grep -q "include nightcity.conf" "$main_conf"; then
        nc_warn "Add 'include nightcity.conf' to your $main_conf to activate"
    elif [ ! -f "$main_conf" ]; then
        nc_warn "Create $main_conf with 'include nightcity.conf' to activate"
    fi
}

install_alacritty() {
    nc_log "Installing Alacritty configuration..."

    local alacritty_dir="$HOME/.config/alacritty"
    local target="$alacritty_dir/nightcity.toml"

    if [ "$DRY_RUN" -eq 1 ]; then
        nc_log "[DRY RUN] Would copy alacritty config to $target"
        return
    fi

    mkdir -p "$alacritty_dir"
    backup_file "$target"
    cp "$TERMINAL_DIR/alacritty/nightcity.toml" "$target"
    nc_log "Installed: $target"

    local main_conf="$alacritty_dir/alacritty.toml"
    if [ -f "$main_conf" ] && ! grep -q "import = \[\"~/.config/alacritty/nightcity.toml\"\]" "$main_conf"; then
        nc_warn "Add 'import = [\"~/.config/alacritty/nightcity.toml\"]' to your $main_conf (at top) to activate"
    elif [ ! -f "$main_conf" ]; then
        nc_warn "Create $main_conf with import statement to activate"
    fi
}

install_ptyxis() {
    nc_log "Installing Ptyxis palette..."

    local palette_dir="$HOME/.local/share/org.gnome.Ptyxis/palettes"
    local target="$palette_dir/nightcity.palette"

    if [ "$DRY_RUN" -eq 1 ]; then
        nc_log "[DRY RUN] Would copy ptyxis palette to $target"
        return
    fi

    mkdir -p "$palette_dir"
    backup_file "$target"
    cp "$TERMINAL_DIR/ptyxis/nightcity.palette" "$target"
    nc_log "Installed: $target"
    nc_log "Select 'NIGHT CITY' in Ptyxis → Preferences → Appearance → Palette"
}

install_tilix() {
    nc_log "Installing Tilix profile..."

    local target="$HOME/.config/tilix/nightcity.json"

    if [ "$DRY_RUN" -eq 1 ]; then
        nc_log "[DRY RUN] Would copy tilix profile to $target"
        return
    fi

    mkdir -p "$(dirname "$target")"
    backup_file "$target"
    cp "$TERMINAL_DIR/tilix/nightcity.json" "$target"
    nc_log "Installed: $target"
    nc_log "Import in Tilix → Preferences → Profiles → Import"
}

install_oh_my_posh() {
    if [ "$PROMPT_CHOICE" = "native" ]; then
        return
    fi

    if [ -f "$NC_SCRIPT_DIR/install-ohmyposh.sh" ]; then
        nc_log "oh-my-posh installer available at scripts/install-ohmyposh.sh"
        if [ "$FORCE" -eq 1 ] || nc_confirm "Run oh-my-posh installer (installs binary, theme, Nerd Font)?"; then
            if [ "$DRY_RUN" -eq 1 ]; then
                nc_log "[DRY RUN] Would run install-ohmyposh.sh"
            else
                "$NC_SCRIPT_DIR/install-ohmyposh.sh"
            fi
        fi
    fi
}

main() {
    nc_log "${NC_NAME} installer v${NC_VERSION}"

    local target_shell
    target_shell=$(detect_shell)
    nc_log "Target shell: $target_shell"

    local terminals
    terminals=$(detect_terminals)
    nc_log "Detected terminals: ${terminals:-none}"

    if [ "$DRY_RUN" -eq 1 ]; then
        nc_warn "DRY RUN MODE - no changes will be made"
    fi

    # Install shell configs
    install_shell_configs "$target_shell"

    # Install terminal emulator configs
    for term in $terminals; do
        case "$term" in
            gnome) install_gnome_terminal ;;
            kitty) install_kitty ;;
            alacritty) install_alacritty ;;
            ptyxis) install_ptyxis ;;
            tilix) install_tilix ;;
            *) nc_warn "Unknown terminal: $term" ;;
        esac
    done

    # Optional oh-my-posh
    install_oh_my_posh

    if [ "$DRY_RUN" -eq 1 ]; then
        nc_warn "DRY RUN complete. Run without --dry-run to apply changes."
    else {
        nc_log ""
        nc_log "Installation complete!"
        nc_log "Backups stored in: $BACKUP_DIR"
        nc_log ""
        nc_log "Next steps:"
        nc_log "  1. Restart your shell: exec \$SHELL"
        nc_log "  2. For GNOME Terminal: select 'NIGHT CITY' profile in Preferences"
        nc_log "  3. For Kitty: add 'include nightcity.conf' to ~/.config/kitty/kitty.conf"
        nc_log "  4. For Alacritty: add import to ~/.config/alacritty/alacritty.toml"
        nc_log "  5. For Ptyxis: select palette in Preferences → Appearance"
        nc_log "  6. For Tilix: import profile in Preferences → Profiles"
        nc_log ""
        nc_log "Run 'ncd' for system dashboard, or set NIGHTCITY_BANNER_INFO=1 for startup info."
    } fi
}

main "$@"