#!/usr/bin/env bash
# NIGHT CITY — System Dashboard
# Run manually: nightcity-dashboard
# Or add to shell rc: [ -f "$HOME/.config/nightcity/dashboard.sh" ] && . "$HOME/.config/nightcity/dashboard.sh"
# Set NIGHTCITY_DASHBOARD_AUTO=1 to show on shell startup (not recommended for daily use).

set -Eeuo pipefail

_nc_red='\033[38;2;255;23;68m'
_nc_pink='\033[38;2;255;61;129m'
_nc_cyan='\033[38;2;0;229;255m'
_nc_white='\033[38;2;232;234;240m'
_nc_dim='\033[38;2;146;153;168m'
_nc_reset='\033[0m'

_nc_draw_line() {
    local char="${1:-─}"
    local cols=${COLUMNS:-80}
    printf '%b%*s%b\n' "${_nc_dim}" "$cols" '' "${_nc_reset}" | tr ' ' "$char"
}

_nc_section() {
    printf '\n%b%s%b\n' "${_nc_cyan}" "$1" "${_nc_reset}"
    _nc_draw_line "─"
}

_nc_kv() {
    printf '  %b%-18s%b %b%s%b\n' "${_nc_dim}" "$1" "${_nc_reset}" "${_nc_white}" "$2" "${_nc_reset}"
}

_nc_kv_status() {
    local label="$1"
    local value="$2"
    local state="$3"
    local color="${_nc_white}"
    case "$state" in
        ok|good|active|connected|up) color="${_nc_cyan}" ;;
        warn|degraded|high) color="${_nc_pink}" ;;
        critical|down|error|failed) color="${_nc_red}" ;;
    esac
    printf '  %b%-18s%b %b%s%b\n' "${_nc_dim}" "$label" "${_nc_reset}" "$color" "$value" "${_nc_reset}"
}

_nc_cpu() {
    _nc_section "CPU"
    if command -v nproc >/dev/null 2>&1; then
        _nc_kv "Cores:" "$(nproc)"
    fi
    if command -v lscpu >/dev/null 2>&1; then
        local model=$(lscpu | grep 'Model name:' | sed 's/Model name:[[:space:]]*//')
        [ -n "$model" ] && _nc_kv "Model:" "$model"
    fi
    if [ -r /proc/loadavg ]; then
        local load=$(cut -d' ' -f1-3 /proc/loadavg)
        _nc_kv "Load (1/5/15):" "$load"
    fi
    if command -v mpstat >/dev/null 2>&1; then
        local usage=$(mpstat 1 1 2>/dev/null | awk '/Average:/ && $12 ~ /[0-9]/ {printf "%.1f%%", 100-$12}')
        [ -n "$usage" ] && _nc_kv_status "Usage:" "$usage" "ok"
    fi
}

_nc_memory() {
    _nc_section "MEMORY"
    if [ -r /proc/meminfo ]; then
        local total_kb=$(grep 'MemTotal:' /proc/meminfo | awk '{print $2}')
        local avail_kb=$(grep 'MemAvailable:' /proc/meminfo | awk '{print $2}')
        if [ -n "$total_kb" ] && [ -n "$avail_kb" ] && [ "$total_kb" -gt 0 ]; then
            local used_kb=$((total_kb - avail_kb))
            local used_gb=$(awk "BEGIN {printf \"%.1f\", $used_kb/1024/1024}")
            local total_gb=$(awk "BEGIN {printf \"%.1f\", $total_kb/1024/1024}")
            local pct=$(awk "BEGIN {printf \"%.0f\", ($used_kb/$total_kb)*100}")
            local state="ok"
            [ "$pct" -gt 80 ] && state="warn"
            [ "$pct" -gt 95 ] && state="critical"
            _nc_kv_status "RAM:" "${used_gb}G / ${total_gb}G (${pct}%)" "$state"
        fi
    fi
    if [ -r /proc/meminfo ]; then
        local swap_total=$(grep 'SwapTotal:' /proc/meminfo | awk '{print $2}')
        local swap_free=$(grep 'SwapFree:' /proc/meminfo | awk '{print $2}')
        if [ -n "$swap_total" ] && [ "$swap_total" -gt 0 ]; then
            local swap_used=$((swap_total - swap_free))
            local swap_used_gb=$(awk "BEGIN {printf \"%.1f\", $swap_used/1024/1024}")
            local swap_total_gb=$(awk "BEGIN {printf \"%.1f\", $swap_total/1024/1024}")
            _nc_kv "Swap:" "${swap_used_gb}G / ${swap_total_gb}G"
        fi
    fi
}

_nc_disk() {
    _nc_section "DISK"
    if command -v df >/dev/null 2>&1; then
        df -h --output=target,size,used,avail,pcent / /home 2>/dev/null | tail -n +2 | sort -u | while read -r mount size used avail pcent; do
            local pct_num=$(echo "$pcent" | tr -d '%')
            local state="ok"
            [ "$pct_num" -gt 80 ] && state="warn"
            [ "$pct_num" -gt 95 ] && state="critical"
            _nc_kv_status "$mount:" "$used / $size ($pcent)" "$state"
        done
    fi
}

_nc_network() {
    _nc_section "NETWORK"
    local hostname=$(hostname 2>/dev/null || echo "unknown")
    _nc_kv "Hostname:" "$hostname"

    if command -v ip >/dev/null 2>&1; then
        local ips=$(ip -brief addr show scope global 2>/dev/null | awk '{print $3}' | cut -d'/' -f1 | tr '\n' ' ')
        [ -n "$ips" ] && _nc_kv "IPv4:" "$ips"
    fi

    if command -v ip >/dev/null 2>&1; then
        local vpns=$(ip link show type wireguard 2>/dev/null | grep -c '^[0-9]:' || true)
        vpns=$((vpns + $(ip link show type tun 2>/dev/null | grep -c '^[0-9]:' || true)))
        if [ "$vpns" -gt 0 ]; then
            _nc_kv_status "VPN:" "$vpns interface(s) up" "ok"
        else
            _nc_kv "VPN:" "none"
        fi
    fi

    if command -v ss >/dev/null 2>&1; then
        local listening=$(ss -ltn 2>/dev/null | grep -c '^LISTEN' || true)
        _nc_kv "Listening ports:" "$listening"
    fi
}

_nc_system() {
    _nc_section "SYSTEM"
    local os=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Linux")
    local kernel=$(uname -r 2>/dev/null || echo "unknown")
    local uptime=$(uptime -p 2>/dev/null | sed 's/^up //' || echo "unknown")
    local shell=$(basename "${SHELL:-unknown}")
    local user=$(whoami 2>/dev/null || echo "unknown")

    _nc_kv "OS:" "$os"
    _nc_kv "Kernel:" "$kernel"
    _nc_kv "Uptime:" "$uptime"
    _nc_kv "Shell:" "$shell"
    _nc_kv "User:" "$user"
}

nightcity_dashboard() {
    clear
    _nc_draw_line "═"
    printf '%b%*s%b\n' "${_nc_red}" $(( (${COLUMNS:-80} - 38) / 2 )) '' | tr ' ' ' '
    printf '%b     NIGHT CITY // SYSTEM DASHBOARD     %b\n' "${_nc_red}" "${_nc_reset}"
    printf '%b     BEYOND THE SYSTEM. INTO THE CITY.  %b\n' "${_nc_cyan}" "${_nc_reset}"
    _nc_draw_line "═"

    _nc_system
    _nc_cpu
    _nc_memory
    _nc_disk
    _nc_network

    printf '\n'
    _nc_draw_line "═"
    printf '%b  Press any key to continue...%b\n' "${_nc_dim}" "${_nc_reset}"
    read -rn1 -s 2>/dev/null || true
    printf '\n'
}

# Auto-show on startup if requested (and interactive)
if [ "${NIGHTCITY_DASHBOARD_AUTO:-0}" = "1" ] && [[ $- == *i* ]]; then
    nightcity_dashboard
fi