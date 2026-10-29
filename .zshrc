# Rex has no shell setting and starts a login zsh, so hand its tabs to nu
# here, as terminal_shell does for Ghostty and herdr. `-c` calls stay in zsh.
if [[ -n $REX_BLOCK && -o login && -o interactive && -z $ZSH_EXECUTION_STRING ]] && command -v nu >/dev/null; then
  exec nu
fi

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
DISABLE_AUTO_UPDATE="true"
plugins=(sudo zsh-autosuggestions zsh-syntax-highlighting)

# Instant prompt renders the prompt twice.
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off

source $ZSH/oh-my-zsh.sh

function cling() {
    local folders=()
    for arg in "$@"; do
        if [ -d "$arg" ]; then
            folders+=("$arg")
        elif [ -f "$arg" ]; then
            folders+=("$(dirname "$arg")")
        fi
    done
    open -a Cling "${folders[@]}"
}

# Claude Code snapshots this shell for its tools; colour codes and icons break parsing of ls output.
if [[ -z $CLAUDECODE ]]; then
  alias l='eza -l --colour=always --icons=always'
  alias ls='eza -l --colour=always --icons=always'
  alias ll='eza -lah --colour=always --icons=always --group-directories-first'
  alias la='eza -a --colour=always --icons=always'
fi

bindkey '^E' end-of-line
bindkey '^A' beginning-of-line
bindkey '^N' menu-complete
bindkey '^P' reverse-menu-complete

# fzf: Ctrl + T files, Alt + C cd
source <(fzf --zsh)

# atuin: Ctrl + R history, shared with nushell. Loads after fzf to take
# Ctrl + R; Up stays zsh's own history.
eval "$(atuin init zsh --disable-up-arrow)"

# zoxide: `z <part of a path>` jumps to a folder visited before
eval "$(zoxide init zsh)"

alias skim='/Applications/Skim.app/Contents/MacOS/Skim'
alias vi="$EDITOR"

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

eval "$(mise activate zsh)"
