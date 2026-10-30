#!/usr/bin/env bash
# NIGHT CITY — optional oh-my-posh + Catppuccin prompt.
#
# Installs, entirely in the user account:
#   ~/.local/bin/oh-my-posh                       (verified release binary)
#   ~/.config/nightcity/catppuccin.omp.json       (bundled theme)
#   ~/.local/share/fonts/NightCityNerdFont/       (JetBrainsMono Nerd Font)
#
# The NIGHT CITY prompt source (~/.config/nightcity/prompt.sh) automatically
# switches to oh-my-posh when both the binary and the theme are present.
# Nothing is installed system-wide and no daemon is started.
set -Eeuo pipefail

NC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$NC_SCRIPT_DIR/lib/common.sh"

OMP_VERSION="${NIGHTCITY_OMP_VERSION:-31.9.1}"
NERD_VERSION="${NIGHTCITY_NERD_FONT_VERSION:-3.5.1}"
WITH_FONT=1
FORCE=0

usage() {
    cat <<EOF
${NC_NAME} oh-my-posh installer v${NC_VERSION}

Usage: ./scripts/install-ohmyposh.sh [options]

Installs oh-my-posh ${OMP_VERSION} and the bundled Catppuccin theme for this
user. It also installs JetBrainsMono Nerd Font ${NERD_VERSION} so the theme's
powerline glyphs render correctly.

  --no-font        Do not download the Nerd Font.
  --force          Replace an existing oh-my-posh binary / font directory.
  --home DIR       Stage into DIR (testing).
  -n, --dry-run    Print actions, change nothing.
  -y, --yes        Do not ask for confirmation.
  --no-color       Disable ANSI colour.
  -h, --help       This text.

Manual opt-out:  export NIGHTCITY_PROMPT=nightcity
Custom theme:    export NIGHTCITY_OMP_CONFIG=/path/theme.omp.json

Uninstall: ./scripts/uninstall.sh (removes files recorded in
           ~/.local/state/nightcity/ohmyposh.tsv, then falls back to the
           native NIGHT CITY prompt).
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --no-font) WITH_FONT=0 ;;
        --force) FORCE=1 ;;
        --home) STAGED_HOME="${2:-}"; shift ;;
        --home=*) STAGED_HOME="${1#*=}" ;;
        -n|--dry-run) DRY_RUN=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
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

OMP_BIN="${XDG_BIN_HOME:-$HOME/.local/bin}/oh-my-posh"
THEME_DIR="$NC_CONFIG/nightcity"
THEME_FILE="$THEME_DIR/catppuccin.omp.json"
FONT_DIR="$NC_DATA/fonts/NightCityNerdFont"
STATE="$NC_STATE/nightcity/ohmyposh.tsv"
THEME_SRC="$NC_ROOT/terminal/oh-my-posh/catppuccin.omp.json"

[ -r "$THEME_SRC" ] || nc_die "missing $THEME_SRC"
python3 -m json.tool "$THEME_SRC" >/dev/null || nc_die "bundled theme is not valid JSON"

case "$(uname -m)" in
    x86_64|amd64)  OMP_ASSET="posh-linux-amd64" ;;
    aarch64|arm64) OMP_ASSET="posh-linux-arm64" ;;
    armv7l|armv6l) OMP_ASSET="posh-linux-arm" ;;
    *) nc_die "unsupported architecture: $(uname -m)" ;;
esac

needs_binary=0
if [ -x "$OMP_BIN" ] && [ "$FORCE" = 0 ]; then
    nc_ok "oh-my-posh already installed: $("$OMP_BIN" --version 2>/dev/null || echo unknown)"
else
    needs_binary=1
fi

needs_font=0
if [ "$WITH_FONT" = 1 ]; then
    _fonts="$(fc-list 2>/dev/null || true)"
    if [ "$FORCE" = 1 ] || ! printf '%s\n' "$_fonts" | grep -i 'JetBrainsMono.*Nerd' >/dev/null; then
        needs_font=1
    fi
fi

nc_step "Plan"
cat <<EOF
  binary        $OMP_BIN  (oh-my-posh ${OMP_VERSION}, ${OMP_ASSET})
  theme         $THEME_FILE  (Catppuccin, bundled)
  nerd font     $([ "$needs_font" = 1 ] && echo "JetBrainsMono Nerd Font ${NERD_VERSION} → $FONT_DIR" || echo "already available / skipped")
  network       github.com release downloads (SHA-256 verified binary)
  system files  none
EOF
nc_confirm "Install oh-my-posh and the Catppuccin prompt for ${NC_USER_HOME}?" || { nc_warn "aborted by user"; exit 0; }

if [ "$DRY_RUN" = 1 ]; then
    nc_warn "dry run only; nothing was downloaded or installed."
    exit 0
fi

nc_have curl || nc_die "curl is required for the download."
nc_have sha256sum || nc_die "sha256sum is required to verify the download."
[ "$needs_font" = 0 ] || { nc_have tar || nc_die "tar is required for the font archive."; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/nightcity-omp.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$THEME_DIR" "$NC_STATE/nightcity" "$(dirname "$OMP_BIN")"

: > "$STATE"

# --- binary -----------------------------------------------------------------
if [ "$needs_binary" = 1 ]; then
    nc_step "Downloading oh-my-posh ${OMP_VERSION}"
    BASE="https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/v${OMP_VERSION}"
    curl -fL --retry 3 --proto '=https' -o "$WORK/posh" "$BASE/$OMP_ASSET" \
        || nc_die "download failed: $BASE/$OMP_ASSET"
    curl -fL --retry 3 --proto '=https' -o "$WORK/checksums.txt" "$BASE/checksums.txt" \
        || nc_die "could not download the release checksums."
    EXPECTED="$(awk -v n="$OMP_ASSET" '$2 == n || $2 == "*" n {print $1; exit}' "$WORK/checksums.txt")"
    [ -n "$EXPECTED" ] || nc_die "no checksum for $OMP_ASSET in checksums.txt"
    ACTUAL="$(sha256sum "$WORK/posh" | awk '{print $1}')"
    [ "$ACTUAL" = "$EXPECTED" ] || nc_die "checksum mismatch for $OMP_ASSET (expected $EXPECTED, got $ACTUAL)"
    install -m 755 "$WORK/posh" "$OMP_BIN"
    "$OMP_BIN" --version >/dev/null || nc_die "installed binary failed to run"
    printf 'binary\t%s\n' "$OMP_BIN" >> "$STATE"
    nc_ok "installed $("$OMP_BIN" --version) with a verified SHA-256"
else
    nc_ok "kept existing oh-my-posh binary"
fi

# --- theme ------------------------------------------------------------------
install -m 644 "$THEME_SRC" "$THEME_FILE"
printf 'theme\t%s\n' "$THEME_FILE" >> "$STATE"
nc_ok "Catppuccin theme installed: $THEME_FILE"

# --- nerd font --------------------------------------------------------------
if [ "$needs_font" = 1 ]; then
    nc_step "Downloading JetBrainsMono Nerd Font ${NERD_VERSION} (7 MiB)"
    FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERD_VERSION}/JetBrainsMono.tar.xz"
    curl -fL --retry 3 --proto '=https' -o "$WORK/JetBrainsMono.tar.xz" "$FONT_URL" \
        || nc_die "font download failed: $FONT_URL"
    mkdir -p "$WORK/font"
    tar -xJf "$WORK/JetBrainsMono.tar.xz" -C "$WORK/font" --wildcards '*.ttf' \
        || nc_die "could not extract the font archive."
    [ -n "$(find "$WORK/font" -name '*.ttf' -print -quit)" ] || nc_die "font archive contained no TTF files."
    mkdir -p "$FONT_DIR"
    cp -f "$WORK/font/"*.ttf "$FONT_DIR/"
    if nc_have fc-cache; then
        fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || nc_warn "fc-cache failed; run it manually."
    else
        nc_warn "fc-cache not found; install fontconfig so the font is visible."
    fi
    printf 'font\t%s\n' "$FONT_DIR" >> "$STATE"
    nc_ok "Nerd Font installed in $FONT_DIR"
elif [ "$WITH_FONT" = 0 ]; then
    nc_warn "Nerd Font not installed (--no-font); powerline glyphs may be missing."
else
    nc_ok "a JetBrainsMono Nerd Font is already available"
fi

# Point the NIGHT CITY terminal profile at the Nerd Font so the powerline
# glyphs render. Only our fixed profile is touched.
if [ "$WITH_FONT" = 1 ]; then
    PROFILE_UUID="6e696768-7420-4369-7479-000000000001"
    if nc_have dconf && nc_key_exists org.gnome.Terminal.ProfilesList default; then
        dconf write "/org/gnome/terminal/legacy/profiles:/:$PROFILE_UUID/font" \
            "'JetBrainsMono Nerd Font 11'" 2>/dev/null || true
    fi
    for cfg in "$NC_CONFIG/kitty/nightcity.conf" "$NC_CONFIG/alacritty/nightcity.toml"; do
        [ -f "$cfg" ] || continue
        sed -i \
            -e 's/^font_family .*/font_family      JetBrainsMono Nerd Font/' \
            -e 's/^bold_font .*/bold_font        JetBrainsMono Nerd Font Bold/' \
            -e 's/^italic_font .*/italic_font      JetBrainsMono Nerd Font Italic/' \
            -e 's/family = "JetBrains Mono"/family = "JetBrainsMono Nerd Font"/' \
            "$cfg"
    done
    nc_ok "terminal profiles point at JetBrainsMono Nerd Font"
fi

cp -f "$NC_ROOT/terminal/shell/nightcity-prompt.sh" "$NC_PROMPT"
nc_ok "prompt source updated; new shells will use oh-my-posh"

printf '\n'
nc_ok "oh-my-posh ready."
nc_log "  Open a new terminal or run: exec zsh   (or: exec bash)"
nc_log "  Native prompt instead:       export NIGHTCITY_PROMPT=nightcity"
nc_log "  Another theme:               export NIGHTCITY_OMP_CONFIG=/path/theme.omp.json"
nc_log "  Remove everything:           ./scripts/uninstall.sh"
