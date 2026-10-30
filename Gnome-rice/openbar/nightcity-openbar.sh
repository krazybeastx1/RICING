#!/usr/bin/env bash
# =====================================================================
# NIGHT CITY — OPENBAR + VPN PANEL INDICATOR
# Cyberpunk floating / Trilands panel, rounded menus and GTK corners.
# Installs OpenBar if missing, configures it, and installs a small local
# GNOME Shell extension that displays the active VPN IPv4 address.
#
# Run: bash ./nightcity-openbar-stylish.sh
# Restore OpenBar settings: dconf load /org/gnome/shell/extensions/openbar/ < BACKUP
# =====================================================================

# Be forgiving when accidentally invoked as: sh script.sh
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

set -Eeuo pipefail

readonly OPENBAR_UUID="openbar@neuromorph"
readonly OPENBAR_SCHEMA="org.gnome.shell.extensions.openbar"
readonly OPENBAR_DCONF="/org/gnome/shell/extensions/openbar/"
readonly VPN_UUID="nightcity-vpn@nightcity.local"
readonly VPN_NAME="NightCity VPN Indicator"
readonly DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
readonly CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly EXT_HOME="$DATA_HOME/gnome-shell/extensions"
readonly VPN_EXT_DIR="$EXT_HOME/$VPN_UUID"
readonly BACKUP_DIR="$CONFIG_HOME/nightcity/backups"

RED='\033[0;31m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

TMP_DIR=""
SCHEMA_CACHE=""
OPENBAR_DIR=""
OPENBAR_BRANCH=""
BACKUP_FILE=""
APPLIED=0
SKIPPED=0
FAILED=0

info()    { printf '%b[NIGHTCITY]%b %s\n' "$CYAN" "$RESET" "$*"; }
success() { printf '%b[ OK ]%b %s\n' "$GREEN" "$RESET" "$*"; }
warn()    { printf '%b[WARN]%b %s\n' "$YELLOW" "$RESET" "$*"; }
error()   { printf '%b[FAIL]%b %s\n' "$RED" "$RESET" "$*" >&2; }
die()     { error "$*"; exit 1; }

cleanup() {
    [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT

# -----------------------------
# 1. Dependencies and platform
# -----------------------------
for cmd in gnome-shell gnome-extensions gsettings dconf glib-compile-schemas ip python3; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
done
if ! command -v git >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
    die "Install git or curl to download OpenBar."
fi

SHELL_VERSION_RAW="$(gnome-shell --version 2>/dev/null || true)"
GNOME_VERSION="$(printf '%s\n' "$SHELL_VERSION_RAW" | sed -nE 's/.* ([0-9]+)(\..*)?$/\1/p')"
[[ "$GNOME_VERSION" =~ ^[0-9]+$ ]] || die "Could not parse GNOME version from: $SHELL_VERSION_RAW"
(( GNOME_VERSION >= 42 )) || die "OpenBar requires GNOME Shell 42 or newer."

if (( GNOME_VERSION <= 44 )); then
    OPENBAR_BRANCH="g42-44"
else
    OPENBAR_BRANCH="main"
fi

SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
IP_BIN="$(command -v ip)"
info "GNOME $GNOME_VERSION detected ($SESSION_TYPE session)."
info "OpenBar branch selected: $OPENBAR_BRANCH"

# -----------------------------
# 2. Find or install OpenBar
# -----------------------------
mkdir -p "$EXT_HOME" "$BACKUP_DIR"

DATA_DIRS=("$DATA_HOME")
IFS=: read -r -a EXTRA_DATA_DIRS <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for base in "${EXTRA_DATA_DIRS[@]}"; do
    [[ -n "$base" ]] && DATA_DIRS+=("$base")
done

for base in "${DATA_DIRS[@]}"; do
    candidate="$base/gnome-shell/extensions/$OPENBAR_UUID"
    if [[ -f "$candidate/metadata.json" && -f "$candidate/schemas/$OPENBAR_SCHEMA.gschema.xml" ]]; then
        OPENBAR_DIR="$candidate"
        break
    fi
done

if [[ -z "$OPENBAR_DIR" ]]; then
    info "OpenBar not found; installing it for the current user..."
    TMP_DIR="$(mktemp -d)"
    DOWNLOAD_DIR="$TMP_DIR/openbar-download"

    if command -v git >/dev/null 2>&1 && git clone --depth 1 --single-branch \
        --branch "$OPENBAR_BRANCH" \
        https://github.com/neuromorph/openbar.git "$DOWNLOAD_DIR"; then
        :
    elif command -v curl >/dev/null 2>&1; then
        warn "Git clone failed or unavailable; trying GitHub source archive."
        mkdir -p "$DOWNLOAD_DIR"
        curl -fL --retry 3 \
            "https://github.com/neuromorph/openbar/archive/refs/heads/${OPENBAR_BRANCH}.tar.gz" \
            -o "$TMP_DIR/openbar.tar.gz" || die "Could not download OpenBar."
        tar -xzf "$TMP_DIR/openbar.tar.gz" -C "$DOWNLOAD_DIR" --strip-components=1
    else
        die "Unable to download OpenBar."
    fi

    [[ -f "$DOWNLOAD_DIR/metadata.json" ]] || die "Downloaded OpenBar has no metadata.json."
    [[ -f "$DOWNLOAD_DIR/schemas/$OPENBAR_SCHEMA.gschema.xml" ]] || die "OpenBar schema XML is missing."

    if [[ -e "$EXT_HOME/$OPENBAR_UUID" ]]; then
        mv -- "$EXT_HOME/$OPENBAR_UUID" "$EXT_HOME/${OPENBAR_UUID}.backup.$(date +%Y%m%d-%H%M%S)"
    fi
    mv -- "$DOWNLOAD_DIR" "$EXT_HOME/$OPENBAR_UUID"
    OPENBAR_DIR="$EXT_HOME/$OPENBAR_UUID"
    success "OpenBar installed at $OPENBAR_DIR"
else
    success "Found OpenBar at $OPENBAR_DIR"
fi

# Verify metadata UUID and declared GNOME support.
python3 - "$OPENBAR_DIR/metadata.json" "$OPENBAR_UUID" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
if data.get("uuid") != sys.argv[2]:
    raise SystemExit("OpenBar metadata UUID does not match its extension directory")
PY

OPENBAR_COMPATIBLE="$(python3 - "$OPENBAR_DIR/metadata.json" "$GNOME_VERSION" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
print("yes" if sys.argv[2] in data.get("shell-version", []) else "no")
PY
)"
if [[ "$OPENBAR_COMPATIBLE" != "yes" ]]; then
    warn "OpenBar metadata does not declare GNOME $GNOME_VERSION support. Settings will be prepared, but activation may fail."
fi

# Compile schema in a temporary directory; never write into a system extension.
TMP_DIR="${TMP_DIR:-$(mktemp -d)}"
SCHEMA_CACHE="$TMP_DIR/openbar-schema"
mkdir -p "$SCHEMA_CACHE"
cp "$OPENBAR_DIR/schemas/$OPENBAR_SCHEMA.gschema.xml" "$SCHEMA_CACHE/"
glib-compile-schemas --strict "$SCHEMA_CACHE" || die "Could not compile OpenBar GSettings schema."

GSETTINGS=(gsettings --schemadir "$SCHEMA_CACHE")
"${GSETTINGS[@]}" list-keys "$OPENBAR_SCHEMA" >/dev/null 2>&1 || die "OpenBar GSettings schema cannot be loaded."
success "OpenBar schema loaded and validated."

# -----------------------------
# 3. Backup current OpenBar config
# -----------------------------
BACKUP_FILE="$BACKUP_DIR/openbar-$(date +%Y%m%d-%H%M%S).dconf"
dconf dump "$OPENBAR_DCONF" > "$BACKUP_FILE"
success "OpenBar settings backed up to $BACKUP_FILE"

# -----------------------------
# 4. Safe schema-aware settings
# -----------------------------
set_key() {
    local key="$1" value="$2"
    if ! "${GSETTINGS[@]}" range "$OPENBAR_SCHEMA" "$key" >/dev/null 2>&1; then
        warn "This OpenBar version has no '$key' key; skipping."
        SKIPPED=$((SKIPPED + 1))
        return 0
    fi
    if "${GSETTINGS[@]}" set "$OPENBAR_SCHEMA" "$key" "$value" >/dev/null 2>&1; then
        APPLIED=$((APPLIED + 1))
    else
        warn "Could not set '$key' to $value (type/value may differ in this version)."
        FAILED=$((FAILED + 1))
    fi
}

set_color() {
    local key="$1" value="$2"
    set_key "$key" "$value"
    set_key "dark-$key" "$value"
    set_key "light-$key" "$value"
}

# NIGHT CITY RGB triples (GSettings type: string array).
NC_BLACK="['0.0314','0.0353','0.0510']"      # #08090D
NC_CARBON="['0.0627','0.0706','0.0941']"     # #101218
NC_GRAPHITE="['0.0902','0.1059','0.1412']"   # #171B24
NC_STEEL="['0.1451','0.1686','0.2078']"      # #252B35
NC_BORDER="['0.2039','0.2314','0.2863']"     # #343B49
NC_MUTED="['0.5725','0.6000','0.6588']"     # #9299A8
NC_TEXT="['0.9098','0.9176','0.9412']"      # #E8EAF0
NC_RED="['1.0000','0.0902','0.2667']"        # #FF1744
NC_CYAN="['0.0000','0.8980','1.0000']"      # #00E5FF

info "Applying Night City floating Trilands layout..."

# Floating three-part bar: left / center / right islands.
set_key bartype "'Trilands'"
set_key position "'Top'"
set_key height "38.0"
set_key margin "9.0"
set_key set-bottom-margin "false"
set_key font "'JetBrains Mono Medium 10'"
set_key default-font "'JetBrains Mono Medium 10'"

# Main panel backing stays almost invisible; each island gets its own surface.
set_color bgcolor "$NC_BLACK"
set_key bgalpha "0.08"
set_color boxcolor "$NC_BLACK"
set_key boxalpha "0.0"
set_color iscolor "$NC_CARBON"
set_key isalpha "0.97"

# Rounded crimson outline around islands.
set_key bordertype "'solid'"
set_key bradius "20.0"
set_key bwidth "1.2"
set_color bcolor "$NC_RED"
set_key balpha "0.90"
set_key neon "true"
set_key width-top "true"
set_key width-bottom "true"
set_key width-left "true"
set_key width-right "true"
set_key radius-topleft "true"
set_key radius-topright "true"
set_key radius-bottomleft "true"
set_key radius-bottomright "true"

# Text, hover and spacing.
set_color fgcolor "$NC_TEXT"
set_key fgalpha "1.0"
set_color hcolor "$NC_RED"
set_key halpha "0.14"
set_key heffect "true"
set_key hpad "8.0"
set_key vpad "6.0"
set_key autofg-bar "false"
set_key gradient "false"
set_key shadow "true"
set_color shcolor "$NC_BLACK"
set_key shalpha "0.38"

# Rounded menus, quick-settings tiles and notifications.
set_key menustyle "true"
set_color mfgcolor "$NC_TEXT"
set_key mfgalpha "1.0"
set_color mbgcolor "$NC_CARBON"
set_key mbgalpha "0.98"
set_key smbgoverride "true"
set_color smbgcolor "$NC_GRAPHITE"
set_key smbgalpha "0.98"
set_color mbcolor "$NC_BORDER"
set_key mbalpha "0.75"
set_color mhcolor "$NC_RED"
set_key mhalpha "0.14"
set_color mscolor "$NC_RED"
set_key msalpha "0.88"
set_color mshcolor "$NC_BLACK"
set_key mshalpha "0.48"
set_key menu-radius "18.0"
set_key notif-radius "12.0"
set_key qtoggle-radius "14.0"
set_key slider-height "5.0"
set_key handle-border "2.0"
set_key set-overview "true"
set_key set-notifications "true"
set_key apply-menu-shell "true"
set_key apply-accent-shell "true"
set_key apply-all-shell "true"
set_key apply-menu-notif "true"

# Rounded GTK app window treatment supported by OpenBar.
set_key corner-radius "true"
set_key winbradius "18.0"
set_key winbwidth "1.0"
set_color winbcolor "$NC_RED"
set_key winbalpha "0.42"
set_key apply-gtk "false"       # Keep the existing NightCity GTK theme in charge.
set_key apply-flatpak "false"   # Do not inject app styling into Flatpaks automatically.

# Optional dock styling, if OpenBar supports these keys.
set_key dashdock-style "'Menu'"
set_color dbgcolor "$NC_BLACK"
set_key dbgalpha "0.94"
set_key dbradius "24.0"
set_key disize "40.0"
set_key dborder "true"
set_key dshadow "true"

# Ask OpenBar to rebuild its stylesheet using its own reload key.
if "${GSETTINGS[@]}" range "$OPENBAR_SCHEMA" reloadstyle >/dev/null 2>&1; then
    set_key reloadstyle "true"
    set_key reloadstyle "false"
fi

# Enable OpenBar. If it was just installed, a logout/login may be required.
if [[ "$OPENBAR_COMPATIBLE" == "yes" ]]; then
    if gnome-extensions enable "$OPENBAR_UUID"; then
        success "OpenBar enabled."
    else
        warn "OpenBar could not be enabled in this session; log out and back in, then enable it."
    fi
else
    warn "Not forcing OpenBar activation on an undeclared GNOME version."
fi

# -----------------------------
# 5. Install NightCity VPN label
# -----------------------------
info "Installing the Night City VPN panel indicator..."
mkdir -p "$EXT_HOME" "$VPN_EXT_DIR"

# Back up an existing copy of this custom extension before replacing it.
if [[ -f "$VPN_EXT_DIR/extension.js" ]]; then
    cp -a "$VPN_EXT_DIR" "$BACKUP_DIR/nightcity-vpn-extension-$(date +%Y%m%d-%H%M%S)"
fi

cat > "$VPN_EXT_DIR/metadata.json" <<EOF
{
  "uuid": "$VPN_UUID",
  "name": "$VPN_NAME",
  "description": "Displays the active VPN interface IPv4 address in the GNOME top panel for the Night City theme.",
  "version": 1,
  "shell-version": ["$GNOME_VERSION"]
}
EOF

if (( GNOME_VERSION >= 45 )); then
cat > "$VPN_EXT_DIR/extension.js" <<EOF
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';
import PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import Main from 'resource:///org/gnome/shell/ui/main.js';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';

const IP_BIN = '$IP_BIN';
const VPN_RE = /^(tun|tap|wg|ppp|tailscale|zt|proton|mullvad|nordlynx|vpn)/i;

function findVpnAddress() {
    try {
        const proc = Gio.Subprocess.new(
            [IP_BIN, '-4', '-o', 'addr', 'show', 'scope', 'global'],
            Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
        );
        const [communicated, stdout] = proc.communicate_utf8(null, null);
        if (!communicated || !proc.get_successful())
            return null;

        const results = [];
        for (const line of stdout.split('\\n')) {
            const match = line.match(/^\\d+:\\s+([^@\\s]+)(?:@\\S+)?\\s+inet\\s+([0-9.]+)\\//);
            if (!match)
                continue;
            const iface = match[1];
            const address = match[2];
            if (!VPN_RE.test(iface))
                continue;
            let priority = 5;
            if (/^(tun|tap)/i.test(iface)) priority = 0;
            else if (/^wg/i.test(iface)) priority = 1;
            else if (/^ppp/i.test(iface)) priority = 2;
            else if (/^tailscale/i.test(iface)) priority = 3;
            results.push({ iface, address, priority });
        }
        results.sort((a, b) => a.priority - b.priority || a.iface.localeCompare(b.iface));
        return results.length ? results[0] : null;
    } catch (error) {
        logError(error, 'NightCity VPN: unable to read local interface addresses');
        return null;
    }
}

export default class NightCityVpnExtension extends Extension {
    enable() {
        this._button = new PanelMenu.Button(0.0, 'NightCity VPN', false);
        this._box = new St.BoxLayout({ style_class: 'panel-status-menu-box' });
        this._dot = new St.Label({ text: '●', y_align: Clutter.ActorAlign.CENTER });
        this._text = new St.Label({ text: 'VPN CHECK', y_align: Clutter.ActorAlign.CENTER });
        this._dot.set_style('color: #FF1744; font-size: 8pt; padding-left: 5px;');
        this._text.set_style("color: #00E5FF; font-family: 'JetBrains Mono'; font-size: 9pt; font-weight: 600; padding: 0 7px 0 5px;");
        this._box.add_child(this._dot);
        this._box.add_child(this._text);
        this._button.add_child(this._box);
        this._menuItem = new PopupMenu.PopupMenuItem('Checking VPN interfaces…', { reactive: false });
        this._button.menu.addMenuItem(this._menuItem);
        Main.panel.addToStatusArea('nightcity-vpn', this._button, 1, 'right');
        this._refresh();
        this._timeout = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 5, () => {
            this._refresh();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _refresh() {
        if (!this._button)
            return;
        const vpn = findVpnAddress();
        if (vpn) {
            this._text.set_text('VPN ' + vpn.address);
            this._text.set_style("color: #00E5FF; font-family: 'JetBrains Mono'; font-size: 9pt; font-weight: 600; padding: 0 7px 0 5px;");
            this._dot.set_style('color: #FF1744; font-size: 8pt; padding-left: 5px;');
            this._menuItem.label.set_text('Interface: ' + vpn.iface + '  •  IPv4: ' + vpn.address);
            this._button.set_tooltip_text('Night City VPN · ' + vpn.iface + ' · ' + vpn.address);
        } else {
            this._text.set_text('VPN OFF');
            this._text.set_style("color: #9299A8; font-family: 'JetBrains Mono'; font-size: 9pt; font-weight: 600; padding: 0 7px 0 5px;");
            this._dot.set_style('color: #9299A8; font-size: 8pt; padding-left: 5px;');
            this._menuItem.label.set_text('No active VPN IPv4 interface detected');
            this._button.set_tooltip_text('Night City VPN · disconnected');
        }
    }

    disable() {
        if (this._timeout) {
            GLib.Source.remove(this._timeout);
            this._timeout = 0;
        }
        if (this._button) {
            this._button.destroy();
            this._button = null;
        }
    }
}
EOF
else
cat > "$VPN_EXT_DIR/extension.js" <<EOF
const { Clutter, Gio, GLib, St } = imports.gi;
const Main = imports.ui.main;
const PanelMenu = imports.ui.panelMenu;
const PopupMenu = imports.ui.popupMenu;
const IP_BIN = '$IP_BIN';
const VPN_RE = /^(tun|tap|wg|ppp|tailscale|zt|proton|mullvad|nordlynx|vpn)/i;

function findVpnAddress() {
    try {
        const proc = Gio.Subprocess.new([IP_BIN, '-4', '-o', 'addr', 'show', 'scope', 'global'],
            Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
        const [communicated, stdout] = proc.communicate_utf8(null, null);
        if (!communicated || !proc.get_successful()) return null;
        const results = [];
        for (const line of stdout.split('\\n')) {
            const match = line.match(/^\\d+:\\s+([^@\\s]+)(?:@\\S+)?\\s+inet\\s+([0-9.]+)\\//);
            if (!match || !VPN_RE.test(match[1])) continue;
            const iface = match[1];
            let priority = /^(tun|tap)/i.test(iface) ? 0 : (/^wg/i.test(iface) ? 1 : 2);
            results.push({ iface, address: match[2], priority });
        }
        results.sort((a, b) => a.priority - b.priority || a.iface.localeCompare(b.iface));
        return results.length ? results[0] : null;
    } catch (e) {
        logError(e, 'NightCity VPN: interface lookup failed');
        return null;
    }
}

class NightCityVpnExtension {
    enable() {
        this._button = new PanelMenu.Button(0.0, 'NightCity VPN', false);
        this._box = new St.BoxLayout({ style_class: 'panel-status-menu-box' });
        this._dot = new St.Label({ text: '●', y_align: Clutter.ActorAlign.CENTER });
        this._text = new St.Label({ text: 'VPN CHECK', y_align: Clutter.ActorAlign.CENTER });
        this._dot.set_style('color: #FF1744; font-size: 8pt; padding-left: 5px;');
        this._text.set_style("color: #00E5FF; font-family: 'JetBrains Mono'; font-size: 9pt; font-weight: 600; padding: 0 7px 0 5px;");
        this._box.add_child(this._dot);
        this._box.add_child(this._text);
        this._button.add_child(this._box);
        this._menuItem = new PopupMenu.PopupMenuItem('Checking VPN interfaces…', { reactive: false });
        this._button.menu.addMenuItem(this._menuItem);
        Main.panel.addToStatusArea('nightcity-vpn', this._button, 1, 'right');
        this._refresh();
        this._timeout = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 5, () => {
            this._refresh(); return GLib.SOURCE_CONTINUE;
        });
    }
    _refresh() {
        if (!this._button) return;
        const vpn = findVpnAddress();
        if (vpn) {
            this._text.set_text('VPN ' + vpn.address);
            this._text.set_style("color: #00E5FF; font-family: 'JetBrains Mono'; font-size: 9pt; font-weight: 600; padding: 0 7px 0 5px;");
            this._dot.set_style('color: #FF1744; font-size: 8pt; padding-left: 5px;');
            this._menuItem.label.set_text('Interface: ' + vpn.iface + '  •  IPv4: ' + vpn.address);
            this._button.set_tooltip_text('Night City VPN · ' + vpn.iface + ' · ' + vpn.address);
        } else {
            this._text.set_text('VPN OFF');
            this._text.set_style("color: #9299A8; font-family: 'JetBrains Mono'; font-size: 9pt; font-weight: 600; padding: 0 7px 0 5px;");
            this._dot.set_style('color: #9299A8; font-size: 8pt; padding-left: 5px;');
            this._menuItem.label.set_text('No active VPN IPv4 interface detected');
            this._button.set_tooltip_text('Night City VPN · disconnected');
        }
    }
    disable() {
        if (this._timeout) { GLib.Source.remove(this._timeout); this._timeout = 0; }
        if (this._button) { this._button.destroy(); this._button = null; }
    }
}
function init() { return new NightCityVpnExtension(); }
EOF
fi

success "NightCity VPN extension files created."

# Enable indicator. If GNOME has not picked up the new extension yet,
# the user can log out and back in and run the enable command below.
if gnome-extensions enable "$VPN_UUID"; then
    success "NightCity VPN indicator enabled."
else
    warn "VPN indicator could not be enabled in this session yet."
    warn "After logging out and back in, run: gnome-extensions enable $VPN_UUID"
fi

# -----------------------------
# 6. Report and recovery command
# -----------------------------
printf '\n%b================================================%b\n' "$RED" "$RESET"
printf '%b NIGHT CITY — OPENBAR UPGRADED%b\n' "$RED" "$RESET"
printf '%b================================================%b\n' "$RED" "$RESET"
printf 'OpenBar layout : Trilands floating islands\n'
printf 'Bar corners    : rounded, radius 20px\n'
printf 'Menu corners   : radius 18px\n'
printf 'GTK corners    : radius 18px (where OpenBar supports them)\n'
printf 'VPN indicator  : %s\n' "$VPN_UUID"
printf 'Settings set   : %s\n' "$APPLIED"
printf 'Skipped keys   : %s\n' "$SKIPPED"
printf 'Failed values  : %s\n' "$FAILED"
printf '\nBackup file:\n%s\n' "$BACKUP_FILE"
printf '\nRestore OpenBar settings with:\n'
printf 'dconf load %s < "%s"\n' "$OPENBAR_DCONF" "$BACKUP_FILE"
printf '\nVPN indicator status:\n'
printf 'gnome-extensions info %s\n' "$VPN_UUID"
printf '\n'
if [[ "$SESSION_TYPE" == "wayland" ]]; then
    warn "Wayland: log out and log back in to load newly installed extensions."
else
    info "If the panel does not refresh, restart GNOME Shell or log out and back in."
fi
success "Configuration finished."
