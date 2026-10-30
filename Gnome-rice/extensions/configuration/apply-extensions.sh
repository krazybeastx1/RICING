#!/usr/bin/env bash
# NIGHT CITY — GNOME Shell extension configuration
# Applies validated GSettings for supported extensions.
# Safe: skips missing extensions/schemas, never overwrites unrelated settings.

set -Eeuo pipefail

NC_NAME="NIGHT CITY"
NC_VERSION="2.0.0"

# Colors for output
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
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

DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"

# Parse common flags
while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        --no-color) NO_COLOR=1; NC_R=''; NC_C=''; NC_W=''; NC_D=''; NC_B=''; NC_0='' ;;
        *) ;;
    esac
    shift
done

nc_run() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '%s    dry-run:%s %s\n' "$NC_D" "$NC_0" "$*"
        return 0
    fi
    "$@"
}

# Check if gsettings is available
if ! command -v gsettings >/dev/null 2>&1; then
    nc_err "gsettings not found; cannot configure extensions."
    exit 1
fi

# Helper: check if schema exists
schema_exists() {
    gsettings list-schemas 2>/dev/null | grep -Fx "$1" >/dev/null
}

# Helper: check if key exists in schema
key_exists() {
    local schema="$1" key="$2"
    schema_exists "$schema" || return 1
    gsettings list-keys "$schema" 2>/dev/null | grep -Fx "$key" >/dev/null
}

# Helper: get key type
key_type() {
    local schema="$1" key="$2"
    gsettings range "$schema" "$key" 2>/dev/null | head -n1 | cut -d' ' -f1
}

# Helper: safely set a gsetting if schema and key exist
# Usage: safe_set SCHEMA KEY VALUE [TYPE_HINT]
safe_set() {
    local schema="$1" key="$2" value="$3" type_hint="${4:-}"
    if ! schema_exists "$schema"; then
        nc_warn "skip: schema '$schema' not found"
        return 0
    fi
    if ! key_exists "$schema" "$key"; then
        nc_warn "skip: key '$key' not found in '$schema'"
        return 0
    fi

    # Validate enum values if we can
    local range
    range="$(gsettings range "$schema" "$key" 2>/dev/null || true)"
    if [ -n "$range" ] && printf '%s' "$range" | grep -q '^enum'; then
        local enum_values
        enum_values="$(printf '%s' "$range" | sed 's/^enum //')"
        if ! printf '%s' "$enum_values" | grep -Fxq "$value"; then
            nc_warn "skip: '$value' not in enum for '$schema' '$key' (valid: $enum_values)"
            return 0
        fi
    fi

    nc_run gsettings set "$schema" "$key" "$value"
    nc_ok "set $schema $key = $value"
}

# Helper: safely append to array-valued gsetting
# Usage: safe_append_array SCHEMA KEY NEW_ELEMENT
safe_append_array() {
    local schema="$1" key="$2" element="$3"
    if ! schema_exists "$schema"; then return 0; fi
    if ! key_exists "$schema" "$key"; then return 0; fi

    local current
    current="$(gsettings get "$schema" "$key" 2>/dev/null || true)"
    case "$current" in
        *"$element"*) ;; # already present
        "[]") nc_run gsettings set "$schema" "$key" "['$element']" ;;
        *) nc_run gsettings set "$schema" "$key" "$(printf '%s' "$current" | sed "s/]$/, '$element']/")" ;;
    esac
    nc_ok "appended '$element' to $schema $key"
}

nc_banner() {
    printf '%s\n' "${NC_R}  ███╗   ██╗██╗ ██████╗ ██╗  ██╗████████╗  ██████╗██╗████████╗██╗   ██╗${NC_0}"
    printf '%s\n' "${NC_R}  ████╗  ██║██║██╔════╝ ██║  ██║╚══██╔══╝ ██╔════╝██║╚══██╔══╝╚██╗ ██╔╝${NC_0}"
    printf '%s\n' "${NC_R}  ██╔██╗ ██║██║██║  ███╗███████║   ██║    ██║     ██║   ██║    ╚████╔╝ ${NC_0}"
    printf '%s\n' "${NC_R}  ██║╚████║██║██║   ██║██╔══██║   ██║    ██║     ██║   ██║     ╚██╔╝  ${NC_0}"
    printf '%s\n' "${NC_R}  ██║ ╚████║██║╚██████╔╝██║  ██║   ██║    ╚██████╗██║   ██║      ██║   ${NC_0}"
    printf '%s\n' "${NC_D}  v${NC_VERSION}  //  ${NC_NAME} Extension Configuration${NC_0}"
    printf '\n'
}

nc_banner

APPLIED=0
SKIPPED=0

# ============================================================================
# 1. Blur My Shell — blur-my-shell@aunetx
# ============================================================================
BLUR_SCHEMA="org.gnome.shell.extensions.blur-my-shell"
if schema_exists "$BLUR_SCHEMA"; then
    nc_step "Configuring Blur My Shell"

    # Panel blur
    safe_set "$BLUR_SCHEMA" panel-blur true
    safe_set "$BLUR_SCHEMA" panel-blur-radius 12
    safe_set "$BLUR_SCHEMA" panel-blur-brightness 0.8
    safe_set "$BLUR_SCHEMA" panel-blur-sigma 30
    safe_set "$BLUR_SCHEMA" panel-blur-noise 0.02

    # Overview blur
    safe_set "$BLUR_SCHEMA" overview-blur true
    safe_set "$BLUR_SCHEMA" overview-blur-radius 20
    safe_set "$BLUR_SCHEMA" overview-blur-brightness 0.6
    safe_set "$BLUR_SCHEMA" overview-blur-sigma 40

    # Disable app/window blur (keep windows sharp)
    safe_set "$BLUR_SCHEMA" window-blur false
    safe_set "$BLUR_SCHEMA" app-folder-blur false

    # Panel tint — subtle red
    safe_set "$BLUR_SCHEMA" panel-tint true
    safe_set "$BLUR_SCHEMA" panel-tint-color "#FF1744"
    safe_set "$BLUR_SCHEMA" panel-tint-opacity 0.08

    APPLIED=$((APPLIED + 1))
else
    nc_warn "Blur My Shell not installed; skipping"
    SKIPPED=$((SKIPPED + 1))
fi

# ============================================================================
# 2. Just Perfection — just-perfection-desktop@shell-extensions.gcampus.dev
# ============================================================================
PERFECTION_SCHEMA="org.gnome.shell.extensions.just-perfection"
if schema_exists "$PERFECTION_SCHEMA"; then
    nc_step "Configuring Just Perfection"

    # Activities button — keep visible (we style it)
    safe_set "$PERFECTION_SCHEMA" activities-button true

    # App menu — enable
    safe_set "$PERFECTION_SCHEMA" app-menu true

    # Clock position — center
    safe_set "$PERFECTION_SCHEMA" clock-position "'CENTER'" enum

    # Workspace popup — disable (we use our own styling)
    safe_set "$PERFECTION_SCHEMA" workspace-popup false

    # Window demands attention — disable focus stealing
    safe_set "$PERFECTION_SCHEMA" window-demands-attention-focus false

    # Panel height — 32px (handled by theme, but ensure extension doesn't override)
    safe_set "$PERFECTION_SCHEMA" panel-size 32

    # Hot corner — disable
    safe_set "$PERFECTION_SCHEMA" hot-corner false

    APPLIED=$((APPLIED + 1))
else
    nc_warn "Just Perfection not installed; skipping"
    SKIPPED=$((SKIPPED + 1))
fi

# ============================================================================
# 3. Dash to Dock — dash-to-dock@micxgx.gmail.com
# ============================================================================
DOCK_SCHEMA="org.gnome.shell.extensions.dash-to-dock"
if schema_exists "$DOCK_SCHEMA"; then
    nc_step "Configuring Dash to Dock"

    # Position: bottom
    safe_set "$DOCK_SCHEMA" dock-position "'BOTTOM'" enum

    # Extend height: false
    safe_set "$DOCK_SCHEMA" extend-height false

    # Background: custom dark
    safe_set "$DOCK_SCHEMA" custom-background-color true
    safe_set "$DOCK_SCHEMA" background-color "'#08090D'"
    safe_set "$DOCK_SCHEMA" background-opacity 0.90

    # Running indicator: dots with custom color
    safe_set "$DOCK_SCHEMA" running-indicator-style "'DOTS'" enum
    safe_set "$DOCK_SCHEMA" running-indicator-dominant-color false
    safe_set "$DOCK_SCHEMA" custom-theme-customize-running-dots true
    safe_set "$DOCK_SCHEMA" custom-theme-running-dots-color "'#FF1744'"
    safe_set "$DOCK_SCHEMA" custom-theme-running-dots-border-color "'#FF1744'"
    safe_set "$DOCK_SCHEMA" custom-theme-running-dots-border-width 1

    # Icon size
    safe_set "$DOCK_SCHEMA" icon-size-fixed false
    safe_set "$DOCK_SCHEMA" dash-max-icon-size 40

    # Behavior
    safe_set "$DOCK_SCHEMA" click-action "'minimize'" enum
    safe_set "$DOCK_SCHEMA" scroll-action "'cycle-windows'" enum
    safe_set "$DOCK_SCHEMA" autohide true
    safe_set "$DOCK_SCHEMA" intellihide true

    # Hide trash and mounted volumes
    safe_set "$DOCK_SCHEMA" show-trash false
    safe_set "$DOCK_SCHEMA" show-mounts false

    APPLIED=$((APPLIED + 1))
else
    nc_warn "Dash to Dock not installed; skipping"
    SKIPPED=$((SKIPPED + 1))
fi

# ============================================================================
# 4. User Themes — user-theme@gnome-shell-extensions.gcampax.github.com
# ============================================================================
USER_THEME_SCHEMA="org.gnome.shell.extensions.user-theme"
if schema_exists "$USER_THEME_SCHEMA"; then
    nc_step "Configuring User Themes"

    # Set the shell theme name
    safe_set "$USER_THEME_SCHEMA" name "'NightCity-Shell'"

    APPLIED=$((APPLIED + 1))
else
    nc_warn "User Themes extension not available; skipping"
    SKIPPED=$((SKIPPED + 1))
fi

# ============================================================================
# Summary
# ============================================================================
printf '\n'
nc_ok "Extension configuration complete."
nc_log "  Applied:   $APPLIED extension(s)"
nc_log "  Skipped:   $SKIPPED extension(s) (not installed)"

if [ "$DRY_RUN" = 1 ]; then
    nc_warn "Dry run — no changes were made."
fi

exit 0