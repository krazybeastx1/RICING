#!/usr/bin/env bash
# NIGHT CITY — Startup Banner
# Source from ~/.bashrc or ~/.zshrc:
#   [ -f "$HOME/.config/nightcity/banner.sh" ] && . "$HOME/.config/nightcity/banner.sh"
#
# Optional: set NIGHTCITY_BANNER_INFO=1 to show system info below the banner.

_nc_red='\033[38;2;255;23;68m'
_nc_pink='\033[38;2;255;61;129m'
_nc_cyan='\033[38;2;0;229;255m'
_nc_white='\033[38;2;232;234;240m'
_nc_dim='\033[38;2;146;153;168m'
_nc_reset='\033[0m'

_nc_banner() {
    local cols=${COLUMNS:-80}
    local width=62
    local padding=$(( (cols - width) / 2 ))
    [ $padding -lt 0 ] && padding=0
    local pad=$(printf '%*s' "$padding" '')

    cat <<EOF
${_nc_dim}${pad}╔══════════════════════════════════════════════════════╗${_nc_reset}
${_nc_dim}${pad}║                                                      ║${_nc_reset}
${_nc_dim}${pad}║${_nc_reset}      ${_nc_red}███╗   ██╗██╗ ██████╗ ██╗  ██╗████████╗${_nc_reset}         ${_nc_dim}║${_nc_reset}
${_nc_dim}${pad}║${_nc_reset}      ${_nc_red}████╗  ██║██║██╔════╝ ██║  ██║╚══██╔══╝${_nc_reset}         ${_nc_dim}║${_nc_reset}
${_nc_dim}${pad}║${_nc_reset}      ${_nc_red}██╔██╗ ██║██║██║  ███╗███████║   ██║${_nc_reset}            ${_nc_dim}║${_nc_reset}
${_nc_dim}${pad}║${_nc_reset}      ${_nc_red}██║╚██╗██║██║██║   ██║██╔══██║   ██║${_nc_reset}            ${_nc_dim}║${_nc_reset}
${_nc_dim}${pad}║${_nc_reset}      ${_nc_red}██║ ╚████║██║╚██████╔╝██║  ██║   ██║${_nc_reset}            ${_nc_dim}║${_nc_reset}
${_nc_dim}${pad}║${_nc_reset}      ${_nc_red}╚═╝  ╚═══╝╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝${_nc_reset}            ${_nc_dim}║${_nc_reset}
${_nc_dim}${pad}║                                                      ║${_nc_reset}
${_nc_dim}${pad}║${_nc_reset}       ${_nc_white}NIGHT CITY // CYBERNETIC CONSOLE${_nc_reset}               ${_nc_dim}║${_nc_reset}
${_nc_dim}${pad}║${_nc_reset}       ${_nc_cyan}BEYOND THE SYSTEM. INTO THE CITY.${_nc_reset}               ${_nc_dim}║${_nc_reset}
${_nc_dim}${pad}║                                                      ║${_nc_reset}
${_nc_dim}${pad}╚══════════════════════════════════════════════════════╝${_nc_reset}
EOF
}

_nc_banner_info() {
    local hostname=$(hostname 2>/dev/null || echo "unknown")
    local os=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Linux")
    local kernel=$(uname -r 2>/dev/null || echo "unknown")
    local shell=$(basename "${SHELL:-unknown}")
    local user=$(whoami 2>/dev/null || echo "unknown")
    local pwd="${PWD/#$HOME/~}"

    printf '\n'
    printf '%b%s%b %b%s%b\n' "${_nc_dim}" "HOST:" "${_nc_reset}" "${_nc_cyan}" "$hostname" "${_nc_reset}"
    printf '%b%s%b %b%s%b\n' "${_nc_dim}" "OS:" "${_nc_reset}" "${_nc_white}" "$os" "${_nc_reset}"
    printf '%b%s%b %b%s%b\n' "${_nc_dim}" "KERNEL:" "${_nc_reset}" "${_nc_white}" "$kernel" "${_nc_reset}"
    printf '%b%s%b %b%s%b\n' "${_nc_dim}" "SHELL:" "${_nc_reset}" "${_nc_white}" "$shell" "${_nc_reset}"
    printf '%b%s%b %b%s%b\n' "${_nc_dim}" "USER:" "${_nc_reset}" "${_nc_cyan}" "$user" "${_nc_reset}"
    printf '%b%s%b %b%s%b\n' "${_nc_dim}" "DIR:" "${_nc_reset}" "${_nc_dim}" "$pwd" "${_nc_reset}"
}

# Only show banner in interactive shells
if [[ $- == *i* ]]; then
    _nc_banner
    if [ "${NIGHTCITY_BANNER_INFO:-0}" = "1" ]; then
        _nc_banner_info
    fi
fi