#!/usr/bin/env bash
# NIGHT CITY — shared installer library.
# Sourced by install.sh, uninstall.sh, rollback.sh, backup.sh, restore.sh,
# configure-user.sh, configure-gdm.sh, configure-plymouth.sh.
# Never executed directly.

NC_NAME="NIGHT CITY"
NC_VERSION="1.0.0"
NC_TAGLINE="Beyond the system. Into the city."

NC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NC_ROOT="$(cd "$NC_LIB_DIR/../.." && pwd)"

export NO_COLOR="${NO_COLOR:-}"
if [ -t 1 ] && [ -z "$NO_COLOR" ]; then
    NC_R=$'\033[38;2;255;23;68m'
    NC_C=$'\033[38;2;0;229;255m'
    NC_W=$'\033[38;2;232;234;240m'
    NC_D=$'\033[38;2;146;153;168m'
    NC_B=$'\033[1m'
    NC_0=$'\033[0m'
else
    NC_R=''; NC_C=''; NC_W=''; NC_D=''; NC_B=''; NC_0=''
fi

nc_log()  { printf '%s\n' "$*"; }
nc_step() { printf '%s▸%s %s\n' "$NC_R" "$NC_0" "$*"; }
nc_ok()   { printf '%s✓%s %s\n' "$NC_C" "$NC_0" "$*"; }
nc_warn() { printf '%s!%s %s\n' "$NC_R" "$NC_0" "$*" >&2; }
nc_err()  { printf '%s✗%s %s\n' "$NC_R" "$NC_0" "$*" >&2; }
nc_die()  { nc_err "$*"; exit 1; }
nc_have() { command -v "$1" >/dev/null 2>&1; }

nc_banner() {
    printf '%s\n' "${NC_R}  ███╗   ██╗██╗ ██████╗ ██╗  ██╗████████╗  ██████╗██╗████████╗██╗   ██╗${NC_0}"
    printf '%s\n' "${NC_R}  ████╗  ██║██║██╔════╝ ██║  ██║╚══██╔══╝ ██╔════╝██║╚══██╔══╝╚██╗ ██╔╝${NC_0}"
    printf '%s\n' "${NC_R}  ██╔██╗ ██║██║██║  ███╗███████║   ██║    ██║     ██║   ██║    ╚████╔╝ ${NC_0}"
    printf '%s\n' "${NC_R}  ██║╚██╗██║██║██║   ██║██╔══██║   ██║    ██║     ██║   ██║     ╚██╔╝  ${NC_0}"
    printf '%s\n' "${NC_R}  ██║ ╚████║██║╚██████╔╝██║  ██║   ██║    ╚██████╗██║   ██║      ██║   ${NC_0}"
    printf '%s\n' "${NC_D}  v${NC_VERSION}  //  ${NC_TAGLINE}${NC_0}"
    printf '\n'
}

# ---------------------------------------------------------------------------
# Options shared by every entry point
# ---------------------------------------------------------------------------
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
STAGED_HOME="${STAGED_HOME:-}"

nc_parse_common() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -n|--dry-run) DRY_RUN=1 ;;
            -y|--yes)     ASSUME_YES=1 ;;
            --no-color)   NO_COLOR=1; NC_R=''; NC_C=''; NC_W=''; NC_D=''; NC_B=''; NC_0='' ;;
            --home)       STAGED_HOME="$2"; shift ;;
            --home=*)     STAGED_HOME="${1#*=}" ;;
            --help|-h)    return 0 ;;
            *) ;;
        esac
        shift
    done
}

nc_run() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '%s    dry-run:%s %s\n' "$NC_D" "$NC_0" "$*"
        return 0
    fi
    "$@"
}

nc_mkdir() { [ "$DRY_RUN" = 1 ] || mkdir -p "$@"; }

nc_copy() {
    local src="$1" dst="$2"
    if [ ! -e "$src" ]; then
        nc_warn "missing source: $src"
        return 1
    fi
    if [ "$DRY_RUN" = 1 ]; then
        printf '%s    dry-run: copy%s %s → %s\n' "$NC_D" "$NC_0" "$src" "$dst"
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    rm -rf "$dst"
    cp -a "$src" "$dst"
}

nc_confirm() {
    local prompt="$1"
    [ "$ASSUME_YES" = 1 ] && return 0
    if [ ! -t 0 ]; then
        return 1
    fi
    local answer
    printf '%s?%s %s [y/N] ' "$NC_C" "$NC_0" "$prompt"
    read -r answer
    case "$answer" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# Paths (respect a staged HOME for CI / dry testing)
# ---------------------------------------------------------------------------
nc_paths() {
    if [ -n "$STAGED_HOME" ]; then
        HOME="$STAGED_HOME"
        export HOME
    fi
    NC_USER_HOME="$HOME"
    NC_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
    NC_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
    NC_STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
    NC_THEMES="$NC_DATA/themes"
    NC_ICONS="$NC_DATA/icons"
    NC_FONTS="$NC_DATA/fonts/NightCity"
    NC_BG="$NC_DATA/backgrounds/nightcity"
    NC_GTK4_CSS="$NC_CONFIG/gtk-4.0/gtk.css"
    NC_PROMPT="$NC_CONFIG/nightcity/prompt.sh"
    NC_USER_BACKUP_ROOT="$NC_STATE/nightcity/backups"
    NC_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
    NC_USER_BACKUP="$NC_USER_BACKUP_ROOT/$NC_TIMESTAMP"
}

nc_require_user() {
    if [ "$(id -u)" -eq 0 ] && [ -z "$STAGED_HOME" ]; then
        nc_die "Run this as your desktop user, not root. Only --system operations use sudo."
    fi
    [ -n "${HOME:-}" ] || nc_die "HOME is not set."
}

# ---------------------------------------------------------------------------
# System detection
# ---------------------------------------------------------------------------
nc_detect() {
    NC_OS_ID="unknown"; NC_OS_NAME="unknown"; NC_OS_VERSION="unknown"; NC_OS_LIKE=""
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        NC_OS_ID="${ID:-unknown}"
        NC_OS_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
        NC_OS_VERSION="${VERSION_ID:-unknown}"
        NC_OS_LIKE="${ID_LIKE:-}"
    fi

    NC_FAMILY="other"
    case " $NC_OS_ID $NC_OS_LIKE " in
        *" debian "*|*" ubuntu "*|*" linuxmint "*|*" kali "*) NC_FAMILY="debian" ;;
        *" fedora "*|*" rhel "*|*" centos "*) NC_FAMILY="fedora" ;;
        *" arch "*) NC_FAMILY="arch" ;;
        *" suse "*|*" opensuse "*) NC_FAMILY="suse" ;;
    esac

    NC_GNOME_VERSION=""
    if nc_have gnome-shell; then
        NC_GNOME_VERSION="$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -n1)"
    fi
    if [ -z "$NC_GNOME_VERSION" ] && nc_have dpkg-query; then
        NC_GNOME_VERSION="$(dpkg-query -W -f='${Version}' gnome-shell 2>/dev/null | grep -oE '^[0-9]+' || true)"
    fi
    NC_GNOME_VERSION="${NC_GNOME_VERSION:-unknown}"
    NC_GNOME_MAJOR="${NC_GNOME_VERSION%%.*}"

    NC_SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
    NC_DESKTOP="${XDG_CURRENT_DESKTOP:-unknown}"

    NC_GTK3="$(pkg-config --modversion gtk+-3.0 2>/dev/null || true)"
    NC_GTK4="$(pkg-config --modversion gtk-4.0 2>/dev/null || true)"
    [ -n "$NC_GTK3" ] || NC_GTK3="$([ -d /usr/lib/*/gtk-3.0 ] && echo present || echo unknown)"
    [ -n "$NC_GTK4" ] || NC_GTK4="$([ -d /usr/lib/*/gtk-4.0 ] && echo present || echo unknown)"

    NC_GDM="no"
    NC_GDM_SERVICE=""
    for svc in gdm3 gdm; do
        local units
        units="$(systemctl list-unit-files "${svc}.service" 2>/dev/null || true)"
        if printf '%s\n' "$units" | grep -E "^${svc}\.service" >/dev/null; then
            NC_GDM_SERVICE="$svc"
            NC_GDM="yes"
            break
        fi
    done

    NC_GDM_CONF=""
    for f in /etc/gdm3/daemon.conf /etc/gdm/custom.conf; do
        [ -e "$f" ] && NC_GDM_CONF="$f" && break
    done
    NC_GRESOURCE="/usr/share/gnome-shell/gnome-shell-theme.gresource"

    NC_PLYMOUTH="no"
    NC_PLYMOUTH_THEME=""
    if nc_have plymouth-set-default-theme; then
        NC_PLYMOUTH="yes"
        NC_PLYMOUTH_THEME="$(plymouth-set-default-theme 2>/dev/null || true)"
        [ -n "$NC_PLYMOUTH_THEME" ] || NC_PLYMOUTH_THEME="$(
            sed -n 's/^Theme=//p' /etc/plymouth/plymouthd.conf 2>/dev/null | head -n1)"
    fi

    NC_HAVE_USER_THEME="no"
    if nc_have gsettings; then
        local schemas
        schemas="$(gsettings list-schemas 2>/dev/null || true)"
        if printf '%s\n' "$schemas" | grep -Fx 'org.gnome.shell.extensions.user-theme' >/dev/null; then
            NC_HAVE_USER_THEME="yes"
        fi
    fi

    NC_HAVE_DOCK="no"
    if nc_have gsettings; then
        local schemas
        schemas="$(gsettings list-schemas 2>/dev/null || true)"
        if printf '%s\n' "$schemas" | grep -Fx 'org.gnome.shell.extensions.dash-to-dock' >/dev/null; then
            NC_HAVE_DOCK="yes"
        fi
    fi

    NC_ENABLED_EXTENSIONS=""
    if nc_have gsettings; then
        NC_ENABLED_EXTENSIONS="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || true)"
    fi
}

nc_print_detect() {
    cat <<EOF
Distribution      ${NC_OS_NAME} (${NC_OS_ID}, family=${NC_FAMILY})
GNOME Shell       ${NC_GNOME_VERSION} (major ${NC_GNOME_MAJOR})
Session           ${NC_SESSION_TYPE} / ${NC_DESKTOP}
GTK 3             ${NC_GTK3}
GTK 4             ${NC_GTK4}
GDM               ${NC_GDM}${NC_GDM_SERVICE:+ (${NC_GDM_SERVICE})}
GDM config        ${NC_GDM_CONF:-not found}
Shell gresource   $([ -e "$NC_GRESOURCE" ] && echo present || echo missing)
Plymouth          ${NC_PLYMOUTH}${NC_PLYMOUTH_THEME:+ (current theme: ${NC_PLYMOUTH_THEME})}
user-theme ext    ${NC_HAVE_USER_THEME}
Dash to Dock      ${NC_HAVE_DOCK}
Home              ${NC_USER_HOME}
EOF
}

# ---------------------------------------------------------------------------
# gsettings helpers
# ---------------------------------------------------------------------------
nc_schema_exists() {
    nc_have gsettings || return 1
    local schemas
    schemas="$(gsettings list-schemas 2>/dev/null || true)"
    printf '%s\n' "$schemas" | grep -Fx "$1" >/dev/null
}

nc_key_exists() {
    local schema="$1" key="$2" keys
    nc_schema_exists "$schema" || return 1
    keys="$(gsettings list-keys "$schema" 2>/dev/null || true)"
    printf '%s\n' "$keys" | grep -Fx "$key" >/dev/null
}

nc_gset() {
    local schema="$1" key="$2" value="$3"
    if ! nc_key_exists "$schema" "$key"; then
        nc_warn "skip (no such setting): ${schema} ${key}"
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        printf '%s    dry-run: gsettings set %s %s %s%s\n' "$NC_D" "$NC_0" "$schema" "$key" "$value"
        return 0
    fi
    gsettings set "$schema" "$key" "$value"
}

# Settings this project may write. Backed up before install, restored on uninstall.
NC_GKEYS=(
    "org.gnome.desktop.interface gtk-theme"
    "org.gnome.desktop.interface icon-theme"
    "org.gnome.desktop.interface cursor-theme"
    "org.gnome.desktop.interface cursor-size"
    "org.gnome.desktop.interface font-name"
    "org.gnome.desktop.interface document-font-name"
    "org.gnome.desktop.interface monospace-font-name"
    "org.gnome.desktop.wm.preferences titlebar-font"
    "org.gnome.desktop.interface color-scheme"
    "org.gnome.desktop.interface accent-color"
    "org.gnome.desktop.interface enable-animations"
    "org.gnome.desktop.background picture-uri"
    "org.gnome.desktop.background picture-uri-dark"
    "org.gnome.desktop.background picture-options"
    "org.gnome.desktop.screensaver picture-uri"
    "org.gnome.shell enabled-extensions"
    "org.gnome.shell.extensions.user-theme name"
    "org.gnome.shell.extensions.dash-to-dock dock-position"
    "org.gnome.shell.extensions.dash-to-dock dock-fixed"
    "org.gnome.shell.extensions.dash-to-dock autohide"
    "org.gnome.shell.extensions.dash-to-dock intellihide"
    "org.gnome.shell.extensions.dash-to-dock background-opacity"
    "org.gnome.shell.extensions.dash-to-dock running-indicator-style"
    "org.gnome.shell.extensions.dash-to-dock click-action"
    "org.gnome.shell.extensions.dash-to-dock scroll-action"
    "org.gnome.shell.extensions.dash-to-dock show-trash"
    "org.gnome.shell.extensions.dash-to-dock show-mounts"
    "org.gnome.shell.extensions.dash-to-dock custom-theme-shrink"
)

nc_snapshot_keys() {
    local out="$1/keys.tsv"
    : > "$out"
    local schema key value
    for pair in "${NC_GKEYS[@]}"; do
        schema="${pair% *}"; key="${pair##* }"
        if nc_key_exists "$schema" "$key"; then
            value="$(gsettings get "$schema" "$key" 2>/dev/null || true)"
            printf '%s\t%s\t%s\n' "$schema" "$key" "$value" >> "$out"
        fi
    done
    # Full dump as a second safety net (manual restore only; not auto-loaded).
    if nc_have dconf; then
        dconf dump /org/gnome/ > "$1/gnome.dconf" 2>/dev/null || true
    fi
}

nc_restore_keys() {
    local file="$1/keys.tsv"
    [ -r "$file" ] || { nc_warn "no key snapshot at $file"; return 1; }
    local schema key value
    while IFS=$'\t' read -r schema key value; do
        [ -n "$schema" ] || continue
        [ -n "$value" ] || continue
        nc_gset "$schema" "$key" "$value"
    done < "$file"
}

# ---------------------------------------------------------------------------
# Backups
# ---------------------------------------------------------------------------
nc_user_backup() {
    nc_mkdir "$NC_USER_BACKUP"
    if [ "$DRY_RUN" = 1 ]; then return 0; fi
    {
        echo "# NIGHT CITY user backup"
        echo "version=$NC_VERSION"
        echo "created=$NC_TIMESTAMP"
        echo "home=$NC_USER_HOME"
        echo "gnome=$NC_GNOME_VERSION"
        echo "os=$NC_OS_NAME"
    } > "$NC_USER_BACKUP/manifest.txt"

    nc_snapshot_keys "$NC_USER_BACKUP"

    local p
    for p in "$NC_GTK4_CSS" "$NC_CONFIG/gtk-3.0/settings.ini" \
             "$NC_CONFIG/kitty/kitty.conf" "$NC_CONFIG/alacritty/alacritty.toml" \
             "$HOME/.bashrc" "$HOME/.zshrc" "$NC_PROMPT"; do
        if [ -e "$p" ]; then
            mkdir -p "$NC_USER_BACKUP/files$(dirname "$p")"
            cp -a "$p" "$NC_USER_BACKUP/files$p"
            printf 'file\t%s\n' "$p" >> "$NC_USER_BACKUP/manifest.txt"
        fi
    done
    for p in "$NC_THEMES/NightCity-GTK" "$NC_THEMES/NightCity-Shell" \
             "$NC_ICONS/NightCity-Icons" "$NC_ICONS/NightCity-Cursor" \
             "$NC_FONTS" "$NC_BG"; do
        if [ -e "$p" ]; then
            mkdir -p "$NC_USER_BACKUP/previous"
            cp -a "$p" "$NC_USER_BACKUP/previous/"
            printf 'previous\t%s\n' "$p" >> "$NC_USER_BACKUP/manifest.txt"
        fi
    done
    nc_ok "user backup: $NC_USER_BACKUP"
}

nc_user_backup_latest() {
    [ -d "$NC_USER_BACKUP_ROOT" ] || return 1
    ls -1d "$NC_USER_BACKUP_ROOT"/*/ 2>/dev/null | sort | tail -n1 | sed 's:/$::'
}

nc_system_backup() {
    [ "$(id -u)" -eq 0 ] || nc_die "system backup requires root"
    NC_SYS_BACKUP="${NC_SYS_BACKUP_DIR:-/var/backups/nightcity}/$NC_TIMESTAMP"
    if [ "$DRY_RUN" = 1 ]; then
        printf '%s    dry-run: system backup → %s%s\n' "$NC_D" "$NC_0" "$NC_SYS_BACKUP"
        return 0
    fi
    mkdir -p "$NC_SYS_BACKUP"
    {
        echo "# NIGHT CITY system backup"
        echo "version=$NC_VERSION"
        echo "created=$NC_TIMESTAMP"
        echo "os=$NC_OS_NAME"
        echo "gnome=$NC_GNOME_VERSION"
    } > "$NC_SYS_BACKUP/manifest.txt"
    local p
    for p in "$NC_GRESOURCE" /etc/plymouth/plymouthd.conf "$NC_GDM_CONF"; do
        [ -e "$p" ] || continue
        mkdir -p "$NC_SYS_BACKUP/files$(dirname "$p")"
        cp -a "$p" "$NC_SYS_BACKUP/files$p"
        printf 'file\t%s\n' "$p" >> "$NC_SYS_BACKUP/manifest.txt"
    done
    if [ -d /etc/dconf/db/gdm.d ]; then
        mkdir -p "$NC_SYS_BACKUP/dconf-gdm.d"
        cp -a /etc/dconf/db/gdm.d/. "$NC_SYS_BACKUP/dconf-gdm.d/" 2>/dev/null || true
    fi
    if [ -d /usr/share/plymouth/themes ] && [ -n "$NC_PLYMOUTH_THEME" ]; then
        printf 'plymouth-theme\t%s\n' "$NC_PLYMOUTH_THEME" >> "$NC_SYS_BACKUP/manifest.txt"
    fi
    nc_ok "system backup: $NC_SYS_BACKUP"
}

nc_system_backup_latest() {
    local root="${NC_SYS_BACKUP_DIR:-/var/backups/nightcity}"
    [ -d "$root" ] || return 1
    ls -1d "$root"/*/ 2>/dev/null | sort | tail -n1 | sed 's:/$::'
}

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------
nc_check_gnome_major() {
    local expected="${1:-50}"
    if [ "$NC_GNOME_MAJOR" = "unknown" ]; then
        nc_warn "GNOME version could not be detected; continuing cautiously."
        return 0
    fi
    if [ "$NC_GNOME_MAJOR" != "$expected" ]; then
        nc_warn "theme was authored against GNOME ${expected}, this system runs GNOME ${NC_GNOME_MAJOR}."
        return 1
    fi
    return 0
}

nc_font_cache() {
    if nc_have fc-cache; then
        nc_run fc-cache -f "$NC_FONTS" >/dev/null 2>&1 || true
    fi
}

nc_gtk_theme_install() {
    local src="$NC_ROOT/themes"
    nc_copy "$src/NightCity-GTK" "$NC_THEMES/NightCity-GTK"
    nc_copy "$src/NightCity-Shell" "$NC_THEMES/NightCity-Shell"
}

nc_icon_install() {
    nc_copy "$NC_ROOT/icons/NightCity-Icons" "$NC_ICONS/NightCity-Icons"
    if nc_have gtk-update-icon-cache; then
        nc_run gtk-update-icon-cache -f -t "$NC_ICONS/NightCity-Icons" >/dev/null 2>&1 || true
    fi
}

nc_cursor_install() {
    nc_copy "$NC_ROOT/cursors/NightCity-Cursor" "$NC_ICONS/NightCity-Cursor"
}

nc_font_install() {
    nc_mkdir "$NC_FONTS"
    if [ "$DRY_RUN" = 1 ]; then return 0; fi
    find "$NC_ROOT/assets/fonts" -type f \( -name '*.ttf' -o -name '*.otf' \) -print0 |
        while IFS= read -r -d '' f; do
            cp -f "$f" "$NC_FONTS/"
        done
    cp -f "$NC_ROOT/licenses/OFL-1.1.txt" "$NC_FONTS/OFL-1.1.txt" 2>/dev/null || true
    nc_font_cache
}

nc_wallpaper_install() {
    nc_mkdir "$NC_BG"
    if [ "$DRY_RUN" = 1 ]; then return 0; fi
    cp -f "$NC_ROOT/assets/wallpapers/"*.png "$NC_BG/"
}

nc_gtk4_user_install() {
    local src="$NC_ROOT/themes/NightCity-GTK/gtk-4.0-user.css"
    [ -f "$src" ] || { nc_warn "missing $src; run scripts/build-theme.py"; return 1; }
    nc_mkdir "$(dirname "$NC_GTK4_CSS")"
    if [ "$DRY_RUN" = 1 ]; then return 0; fi
    # Only snapshot a foreign gtk.css. Re-installing must not overwrite the
    # original backup with NIGHT CITY's own file.
    if [ -f "$NC_GTK4_CSS" ] && [ ! -f "$NC_GTK4_CSS.nightcity-prev" ]; then
        if ! head -n 3 "$NC_GTK4_CSS" | grep "NIGHT CITY" >/dev/null; then
            cp -a "$NC_GTK4_CSS" "$NC_GTK4_CSS.nightcity-prev"
        fi
    fi
    cp -f "$src" "$NC_GTK4_CSS"
}

nc_terminal_install() {
    nc_mkdir "$NC_CONFIG/kitty" "$NC_CONFIG/alacritty" "$NC_CONFIG/nightcity"
    nc_copy "$NC_ROOT/terminal/kitty/nightcity.conf" "$NC_CONFIG/kitty/nightcity.conf"
    nc_copy "$NC_ROOT/terminal/alacritty/nightcity.toml" "$NC_CONFIG/alacritty/nightcity.toml"
    nc_copy "$NC_ROOT/terminal/shell/nightcity-prompt.sh" "$NC_PROMPT"

    # Ptyxis palette
    local ptyxis_dir="${XDG_DATA_HOME:-$HOME/.local/share}/org.gnome.Ptyxis/palettes"
    nc_mkdir "$ptyxis_dir"
    nc_copy "$NC_ROOT/terminal/ptyxis/nightcity.palette" "$ptyxis_dir/nightcity.palette"

    # Tilix scheme
    local tilix_dir="${XDG_DATA_HOME:-$HOME/.local/share}/tilix/schemes"
    nc_mkdir "$tilix_dir"
    nc_copy "$NC_ROOT/terminal/tilix/nightcity.json" "$tilix_dir/nightcity.json"

    # GNOME Terminal profile (fixed UUID, idempotent)
    if nc_have dconf && nc_key_exists org.gnome.Terminal.ProfilesList default; then
        local uuid="6e696768-7420-4369-7479-000000000001"
        if [ "$DRY_RUN" = 1 ]; then
            printf '%s    dry-run: dconf load gnome-terminal profile %s%s\n' "$NC_D" "$NC_0" "$uuid"
        else
            dconf load "/org/gnome/terminal/legacy/profiles:/:$uuid/" \
                < "$NC_ROOT/terminal/gnome-terminal/nightcity.dconf" || true
            local list
            list="$(gsettings get org.gnome.Terminal.ProfilesList list)"
            case "$list" in
                *"$uuid"*) ;;
                *) gsettings set org.gnome.Terminal.ProfilesList list \
                       "$(printf '%s' "$list" | sed "s/]$/, '$uuid']/; s/\[\]/['$uuid']/")" || true ;;
            esac
        fi
    fi

    # Append opt-in includes exactly once.
    local marker="# >>> NIGHT CITY >>>"
    if [ -f "$NC_CONFIG/kitty/kitty.conf" ] && ! grep -qF "$marker" "$NC_CONFIG/kitty/kitty.conf"; then
        if [ "$DRY_RUN" = 1 ]; then
            printf '%s    dry-run: append kitty include%s\n' "$NC_D" "$NC_0"
        else
            printf '\n%s\ninclude nightcity.conf\n%s\n' "$marker" "# <<< NIGHT CITY <<<" \
                >> "$NC_CONFIG/kitty/kitty.conf"
        fi
    fi
}
