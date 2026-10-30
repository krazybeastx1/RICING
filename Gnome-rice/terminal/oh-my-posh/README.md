# oh-my-posh — Catppuccin prompt

`catppuccin.omp.json` is the upstream Catppuccin theme for
[oh-my-posh](https://ohmyposh.dev/):

  https://github.com/JanDeDobbeleer/oh-my-posh/blob/main/themes/catppuccin.omp.json

It is redistributed unmodified. SHA-256 of the bundled copy:

  246afe25702d919dfc301c754380cf5b2b1b4dce1b5a234725444b31250b818d

The theme uses Nerd Font powerline glyphs. `scripts/install-ohmyposh.sh`
installs JetBrainsMono Nerd Font (from ryanoasis/nerd-fonts) into the user's
font directory and verifies the oh-my-posh release binary against the
upstream SHA-256 checksums.

The NIGHT CITY prompt source switches to oh-my-posh automatically when
`~/.local/bin/oh-my-posh` and `~/.config/nightcity/catppuccin.omp.json`
exist. Set `NIGHTCITY_PROMPT=nightcity` to keep the native red prompt.

License: MIT (oh-my-posh), see `licenses/MIT-oh-my-posh.txt`. Nerd Fonts are
distributed under the SIL Open Font License 1.1.
