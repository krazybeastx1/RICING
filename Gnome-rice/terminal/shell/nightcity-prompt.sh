# NIGHT CITY — shell prompt
# Source from ~/.bashrc or ~/.zshrc:
#   [ -f "$HOME/.config/nightcity/prompt.sh" ] && . "$HOME/.config/nightcity/prompt.sh"
#
# If oh-my-posh and the bundled Catppuccin theme are installed, that prompt is
# used automatically. Set NIGHTCITY_PROMPT=nightcity to force the native
# prompt below instead. Set NIGHTCITY_OMP_CONFIG to use another theme.
# Set NIGHTCITY_PROMPT_STYLE=single for single-line prompt (default: two-line).
# No patched fonts, no background daemons, no network calls at prompt time.

_nc_omp_config="${NIGHTCITY_OMP_CONFIG:-$HOME/.config/nightcity/catppuccin.omp.json}"
if [ "${NIGHTCITY_PROMPT:-auto}" != "nightcity" ] \
   && [ -r "$_nc_omp_config" ] \
   && command -v oh-my-posh >/dev/null 2>&1; then
    if [ -n "${ZSH_VERSION:-}" ]; then
        _nc_omp_init="$(oh-my-posh init zsh --config "$_nc_omp_config" 2>/dev/null)" && eval "$_nc_omp_init" && return 0
    elif [ -n "${BASH_VERSION:-}" ]; then
        _nc_omp_init="$(oh-my-posh init bash --config "$_nc_omp_config" 2>/dev/null)" && eval "$_nc_omp_init" && return 0
    fi
    unset _nc_omp_init
fi
unset _nc_omp_config

_nc_red='\033[38;2;255;23;68m'
_nc_pink='\033[38;2;255;61;129m'
_nc_cyan='\033[38;2;0;229;255m'
_nc_white='\033[38;2;232;234;240m'
_nc_dim='\033[38;2;146;153;168m'
_nc_reset='\033[0m'

# Prompt style: "single" or "two-line" (default)
_nc_prompt_style="${NIGHTCITY_PROMPT_STYLE:-two-line}"

# Ensure command errors don't exit the terminal
set +o errexit

# Git branch, silent outside a repo.
_nc_git_branch() {
    command -v git >/dev/null 2>&1 || return 0
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    local branch
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    [ -n "$branch" ] || return 0
    local dirty=''
    [ -n "$(git status --porcelain 2>/dev/null | head -n 1)" ] && dirty='*'
    printf '%s' "$branch$dirty"
}

# Compact current directory: ~ plus last two components.
_nc_dir() {
    local pwd="${PWD/#$HOME/~}"
    case "$pwd" in
        '~'|'/'|'~/'*) printf '%s' "$pwd" ;;
        *) printf '…/%s' "${pwd##*/}" ;;
    esac
}

if [ -n "${BASH_VERSION:-}" ]; then
    _nc_prompt_command() {
        local status=$?
        local branch
        branch=$(_nc_git_branch)
        local gitpart=''
        [ -n "$branch" ] && gitpart=" ${_nc_dim}on ${_nc_cyan}${branch}"
        local errpart=''
        [ "$status" -ne 0 ] && errpart="\[${_nc_pink}\][${status}]\[${_nc_reset}\] "

        if [ "$_nc_prompt_style" = "single" ]; then
            PS1="${errpart}\[${_nc_red}\]NIGHTCITY\[${_nc_reset}\] \[${_nc_cyan}\]\u@\h\[${_nc_reset}\]:\[${_nc_dim}\]\$(_nc_dir)\[${_nc_reset}\]${gitpart} \[${_nc_pink}\]λ\[${_nc_reset}\] "
        else
            PS1="${errpart}\[${_nc_red}\]┌─\[${_nc_dim}\](\[${_nc_white}\]\u@\h\[${_nc_dim}\])─(\[${_nc_cyan}\]\$(_nc_dir)\[${_nc_dim}\])${gitpart}\n\[${_nc_red}\]└─\[${_nc_pink}\]λ\[${_nc_reset}\] "
        fi
        return "$status"
    }
    PROMPT_COMMAND="_nc_prompt_command${PROMPT_COMMAND:+;$PROMPT_COMMAND}"

elif [ -n "${ZSH_VERSION:-}" ]; then
    autoload -Uz colors 2>/dev/null || true
    setopt PROMPT_SUBST 2>/dev/null || true
    precmd() {
        local _status=$?
        local branch
        branch=$(_nc_git_branch)
        local gitpart=''
        [ -n "$branch" ] && gitpart=" %F{244}on %F{51}${branch}"
        local prefix=''
        [ "$_status" -ne 0 ] && prefix="%F{205}[${_status}]%f "

        if [ "$_nc_prompt_style" = "single" ]; then
            PROMPT="${prefix}%F{197}NIGHTCITY%f %F{51}%n@%m%f:%F{244}%2~%f${gitpart} %F{205}λ%f "
        else
            PROMPT="${prefix}%F{197}┌─%F{244}(%F{255}%n@%m%F{244})─(%F{51}%2~%F{244})${gitpart}
%F{197}└─%F{205}λ%f "
        fi
        return "$_status"
    }
    precmd_functions=(precmd)
fi
