# NIGHT CITY — Terminal Configuration

> **NIGHTCITY TERMINAL** — "Access the City. Control the System."

Complete terminal theming for the NIGHT CITY GNOME desktop. Provides a unified cyberpunk aesthetic across all supported terminal emulators with a native shell prompt, startup banner, and optional system dashboard.

---

## Components

```
terminal/
├── README.md                    # This file
├── colors/
│   └── nightcity-palette.conf   # Unified color palette (sourceable)
├── gnome-terminal/
│   └── nightcity.dconf          # GNOME Terminal profile (dconf)
├── kitty/
│   └── nightcity.conf           # Kitty configuration
├── alacritty/
│   └── nightcity.toml           # Alacritty configuration (TOML)
├── ptyxis/
│   └── nightcity.palette        # Ptyxis palette file
├── tilix/
│   └── nightcity.json           # Tilix profile JSON
├── shell/
│   ├── nightcity-prompt.sh      # Native Bash/Zsh prompt (primary)
│   ├── banner.sh                # Startup banner
│   └── dashboard.sh             # System dashboard (on-demand)
├── oh-my-posh/
│   ├── catppuccin.omp.json      # Catppuccin Mocha theme for oh-my-posh
│   └── README.md                # oh-my-posh setup guide
└── scripts/
    ├── install-terminal.sh      # Install terminal configs
    └── uninstall-terminal.sh    # Remove terminal configs
```

---

## Quick Start

### 1. Install All Terminal Configurations

```bash
# From repository root
./scripts/install-terminal.sh
```

This will:
- Detect your shell (Bash/Zsh)
- Detect installed terminal emulators
- Back up existing configurations
- Install NightCity configs for detected terminals
- Set up shell prompt, banner, and dashboard

### 2. Manual Installation

#### Shell Prompt (Bash)

```bash
# Add to ~/.bashrc
[ -f "$HOME/.config/nightcity/prompt.sh" ] && . "$HOME/.config/nightcity/prompt.sh"
```

#### Shell Prompt (Zsh)

```zsh
# Add to ~/.zshrc
[ -f "$HOME/.config/nightcity/prompt.sh" ] && . "$HOME/.config/nightcity/prompt.sh"
```

#### Startup Banner

```bash
# Add to ~/.bashrc or ~/.zshrc (after prompt)
[ -f "$HOME/.config/nightcity/banner.sh" ] && . "$HOME/.config/nightcity/banner.sh"
```

Optional: show system info below banner:
```bash
export NIGHTCITY_BANNER_INFO=1
```

#### System Dashboard

```bash
# Run manually anytime
nightcity-dashboard

# Or add to shell rc for on-demand alias
alias ncd='nightcity_dashboard'
```

Auto-show on startup (not recommended for daily use):
```bash
export NIGHTCITY_DASHBOARD_AUTO=1
```

---

## Terminal Emulator Setup

### GNOME Terminal

```bash
# Load the profile (creates "NIGHT CITY" profile with fixed UUID)
dconf load /org/gnome/terminal/legacy/profiles:/:6e696768-7420-4369-7479-000000000001/ \
  < terminal/gnome-terminal/nightcity.dconf

# Set as default profile
gsettings set org.gnome.Terminal.ProfilesList default \
  '6e696768-7420-4369-7479-000000000001'
```

Or use the installer script which handles this automatically.

### Ptyxis

```bash
# Copy palette to Ptyxis palettes directory
mkdir -p ~/.local/share/org.gnome.Ptyxis/palettes
cp terminal/ptyxis/nightcity.palette ~/.local/share/org.gnome.Ptyxis/palettes/

# Then select "NIGHT CITY" in Ptyxis → Preferences → Appearance → Palette
```

### Kitty

```bash
# Include in ~/.config/kitty/kitty.conf
include nightcity.conf

# Or copy directly
cp terminal/kitty/nightcity.conf ~/.config/kitty/nightcity.conf
```

### Alacritty

```bash
# Add to ~/.config/alacritty/alacritty.toml (at top, before your settings)
[general]
import = ["~/.config/alacritty/nightcity.toml"]

# Or copy directly
cp terminal/alacritty/nightcity.toml ~/.config/alacritty/nightcity.toml
```

### Tilix

```bash
# Import profile in Tilix → Preferences → Profiles → Import
# Select terminal/tilix/nightcity.json
```

---

## Shell Prompt Details

### Native Prompt (Default)

The native two-line prompt (`nightcity-prompt.sh`) provides:

```
┌─(user@host)─(~/path) on branch*
└─λ
```

**Features:**
- Red NIGHTCITY branding
- Cyan username@hostname
- Muted current directory (compact: `~/path` or `…/last`)
- Cyan Git branch with `*` for dirty working tree
- Red error code prefix when last command failed: `[1]`
- Works in Bash and Zsh
- No external dependencies, no Nerd Fonts required
- No background daemons

**Environment Variables:**
- `NIGHTCITY_PROMPT=nightcity` — Force native prompt (disable oh-my-posh)
- `NIGHTCITY_PROMPT=auto` — Default: use oh-my-posh if available

### oh-my-posh (Optional)

If you prefer oh-my-posh with a Catppuccin theme:

```bash
# Install oh-my-posh + Catppuccin theme + JetBrainsMono Nerd Font
./scripts/install-ohmyposh.sh
```

The native prompt script automatically detects and uses oh-my-posh when both the binary and theme are present.

---

## Color Palette

All configurations use the official NIGHT CITY palette:

| Role | Color | Hex |
|------|-------|-----|
| Main Background | ██████ | `#08090D` |
| Secondary Background | ██████ | `#101218` |
| Elevated Surface | ██████ | `#171B24` |
| Border | ██████ | `#343B49` |
| Primary Text | ██████ | `#E8EAF0` |
| Muted Text | ██████ | `#9299A8` |
| Primary Red | ██████ | `#FF1744` |
| Active Red | ██████ | `#E60035` |
| Dark Red | ██████ | `#8C102B` |
| Cyan | ██████ | `#00E5FF` |
| Purple (optional) | ██████ | `#9B5CFF` |

**Cursor:** `#FF1744` (neon red) on `#08090D`
**Selection:** `#57202F` (dark crimson) on `#E8EAF0`

---

## Font

**Primary:** JetBrains Mono (11.5pt, 105% line height)

Install on Debian/Ubuntu/Kali:
```bash
sudo apt install fonts-jetbrains-mono
```

Or download from: https://github.com/JetBrains/JetBrainsMono

**Nerd Font variant** (for oh-my-posh): Installed by `install-ohmyposh.sh`

---

## Transparency

All terminals configured with ~96% opacity (`background_opacity = 0.96`) where supported:
- Kitty: native `background_opacity` + `background_blur`
- Alacritty: native `window.opacity`
- GNOME Terminal: `use-transparent-background=true` + `background-transparency-percent=6`
- Ptyxis: follows GTK theme (configured via shell.css)
- Tilix: uses profile background color (opacity via compositor)

---

## Cybersecurity Tool Compatibility

The theme preserves semantic colors in command output. No global color overrides that hide warnings, errors, or security findings.

Tested compatible with:
- **Nmap** — port scan output unchanged
- **Burp Suite CLI** — logging intact
- **Impacket** — SMB/Kerberos output unchanged
- **NetExec** — enumeration output intact
- **BloodHound** — Cypher queries unaffected
- **Python venv** — prompt integration works
- **Git** — diff/status colors preserved
- **Docker** — container output unchanged
- **SSH** — remote session colors unaffected
- **Tmux** — status bar integrates with palette

---

## Uninstall

```bash
# Restore all backed-up configurations
./scripts/uninstall-terminal.sh
```

This restores:
- `~/.bashrc` / `~/.zshrc` (original files)
- Terminal emulator profiles/configs
- Removes NightCity config directory

---

## Integration with NIGHT CITY GNOME

This terminal theme is designed to work seamlessly with the NIGHT CITY GNOME Shell theme:

- **GTK Terminal Widgets** — Uses same palette as `design/overrides/shell.css`
- **GDM/Plymouth** — Consistent boot/login experience
- **Extension Config** — Quick Settings, Notifications, Overview match terminal aesthetic

---

## Customization

### Disable Transparency
```bash
export NIGHTCITY_OPACITY=1.0
```

### Change Font Size
```bash
export NIGHTCITY_FONT_SIZE=12
```

### Force Native Prompt
```bash
export NIGHTCITY_PROMPT=nightcity
```

### Custom oh-my-posh Theme
```bash
export NIGHTCITY_OMP_CONFIG="$HOME/.config/nightcity/my-theme.omp.json"
```

---

## Troubleshooting

### Prompt not showing
- Ensure `~/.config/nightcity/prompt.sh` exists
- Check shell rc sources it correctly
- Restart shell: `exec $SHELL`

### Colors wrong in terminal
- Verify terminal emulator config loaded
- Check terminal supports truecolor: `echo $COLORTERM`
- For GNOME Terminal: ensure profile is selected in Preferences

### Banner/dashboard not appearing
- Only shows in interactive shells (`[[ $- == *i* ]]`)
- Check `NIGHTCITY_BANNER_INFO` / `NIGHTCITY_DASHBOARD_AUTO` env vars

### oh-my-posh not activating
- Run `./scripts/install-ohmyposh.sh`
- Verify `~/.config/nightcity/catppuccin.omp.json` exists
- Verify `oh-my-posh` in PATH (`~/.local/bin`)

---

## License

Part of the NIGHT CITY GNOME theme project. MIT License.