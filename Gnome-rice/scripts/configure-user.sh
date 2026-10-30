#!/usr/bin/env bash
# NIGHT CITY — re-apply the user-level theme without touching GDM/Plymouth.
#
# This is a convenience wrapper around install.sh that defaults to Full mode
# and never accepts system-component flags.
set -Eeuo pipefail

NC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$NC_SCRIPT_DIR/lib/common.sh"

MODE="full"
ARGS=()

usage() {
    cat <<EOF
${NC_NAME} user configuration v${NC_VERSION}

Usage: ./scripts/configure-user.sh [options]

  --mode standard|full   Standard = visuals only; Full = visuals + dock,
                         terminal default and shell prompt (default: full).
  --no-gsettings         Install files but leave settings alone.
  --no-shell-prompt      Do not modify .bashrc/.zshrc.
  --no-terminal-default  Do not change the default terminal profile.
  --ohmyposh             Install oh-my-posh + Catppuccin prompt (network).
  --home DIR             Stage into DIR (testing).
  --force                Proceed on a different GNOME major version.
  -n, --dry-run          Print actions, change nothing.
  -y, --yes              Do not ask for confirmation.
  --no-color             Disable ANSI colour.
  -h, --help             This text.

For GDM/Plymouth use install.sh --mode advanced or configure-gdm.sh /
configure-plymouth.sh directly.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --mode) MODE="${2:-}"; shift ;;
        --mode=*) MODE="${1#*=}" ;;
        --no-gsettings) ARGS+=(--no-gsettings) ;;
        --no-shell-prompt) ARGS+=(--no-shell-prompt) ;;
        --no-terminal-default) ARGS+=(--no-terminal-default) ;;
        --ohmyposh) ARGS+=(--ohmyposh) ;;
        --home) ARGS+=(--home "${2:-}"); shift ;;
        --home=*) ARGS+=(--home "${1#*=}") ;;
        --force) ARGS+=(--force) ;;
        -n|--dry-run) ARGS+=(--dry-run) ;;
        -y|--yes) ARGS+=(--yes) ;;
        --no-color) ARGS+=(--no-color) ;;
        -h|--help) usage; exit 0 ;;
        *) nc_die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

case "$MODE" in
    standard|full) ;;
    advanced) nc_die "advanced/system installs belong to install.sh --mode advanced" ;;
    *) nc_die "invalid --mode '$MODE' (standard|full)" ;;
esac

exec "$NC_SCRIPT_DIR/install.sh" --mode "$MODE" "${ARGS[@]}"
