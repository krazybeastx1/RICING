# NIGHT CITY — Extension Configuration

This directory contains the GNOME Shell extension configuration for the NIGHT CITY theme.

## Files

| File | Purpose |
|------|---------|
| `apply-extensions.sh` | Interactive script that safely applies extension settings via `gsettings` |
| `night-city.dconf` | dconf dump format for bulk loading all settings at once |

## Supported Extensions

The configuration targets these extensions (install separately):

| Extension | ID | Required Version |
|-----------|-----|------------------|
| **Blur My Shell** | `blur-my-shell@aunetx` | Latest |
| **Just Perfection** | `just-perfection-desktop@shell-extensions.gcampus.dev` | Latest |
| **Dash to Dock** | `dash-to-dock@micxgx.gmail.com` | Latest |
| **User Themes** | `user-theme@gnome-shell-extensions.gcampax.github.com` | Built into GNOME |

## Installation

### Option 1: Interactive script (recommended)
```bash
# From the NightCity repo root
./extensions/configuration/apply-extensions.sh

# Dry run (preview changes)
./extensions/configuration/apply-extensions.sh --dry-run

# Unattended
./extensions/configuration/apply-extensions.sh -y
```

### Option 2: dconf load (bulk)
```bash
dconf load / < extensions/configuration/night-city.dconf
```
> **Note**: `dconf load` will write all keys unconditionally. Use the script for safer application that validates schemas first.

### Option 3: Via install.sh
The main installer (`scripts/install.sh --mode full`) automatically runs the extension configuration after installing themes.

## What Gets Configured

### Blur My Shell
- Panel blur: enabled, radius 12, brightness 0.8
- Overview blur: enabled, radius 20, brightness 0.6
- Window/app blur: **disabled** (keep windows sharp)
- Panel tint: subtle red (#FF1744 at 8% opacity)

### Just Perfection
- Activities button: visible (styled as "NIGHTCITY" branding)
- App menu: enabled
- Clock position: center
- Workspace popup: disabled
- Window demands attention focus: disabled
- Panel height: 32px
- Hot corner: disabled

### Dash to Dock
- Position: bottom
- Background: #08090D (NC_BLACK) at 90% opacity
- Running indicator: red dots (#FF1744)
- Border radius: 8px
- Icon size: 40px max
- Click action: minimize
- Scroll action: cycle windows
- Auto-hide: enabled with intellihide
- Trash & mounts: hidden

### User Themes
- Shell theme: `NightCity-Shell`

## Validation

The `apply-extensions.sh` script:
1. Checks if each extension's GSettings schema exists
2. Validates each key exists before writing
3. Verifies enum values against the schema's allowed values
4. Skips missing extensions gracefully (no errors)
5. Reports a summary of applied vs skipped

## Restoring Previous Settings

The main installer (`scripts/install.sh`) creates a backup of all modified GSettings keys before applying NightCity settings. To restore:

```bash
# Automatic restore via uninstall
./scripts/uninstall.sh

# Manual restore from latest backup
BACKUP=$(ls -1d ~/.local/state/nightcity/backups/*/ | sort | tail -n1)
while IFS=$'\t' read -r schema key value; do
    gsettings set "$schema" "$key" "$value"
done < "$BACKUP/keys.tsv"
```

## Troubleshooting

### "Schema not found" warnings
The extension is not installed. Install it via:
- GNOME Extensions app
- `gnome-extensions-cli` (if available)
- Your distribution's package manager (e.g., `gnome-shell-extension-blur-my-shell`)

### "Key not found" warnings
The extension version differs from what this config expects. Check the extension's schema:
```bash
gsettings list-keys org.gnome.shell.extensions.blur-my-shell
```
Then update the script/dconf accordingly.

### Settings not taking effect
Some extensions require a Shell restart:
- Press `Alt+F2`, type `r`, press Enter (X11 only)
- Or log out and back in
- On Wayland: log out/in is required

## Version Compatibility

| GNOME Shell | Tested |
|-------------|--------|
| 44 | ⚠️ Partial |
| 45 | ✅ Yes |
| 46 | ✅ Yes |
| 47+ | ⚠️ Untested |

Extension schemas may change between GNOME versions. If you encounter issues, run the script with `--dry-run` to see what would be applied, then check the extension's actual schema.