export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
DISABLE_AUTO_UPDATE="true"
plugins=(sudo zsh-autosuggestions zsh-syntax-highlighting)

# Ensure p10k instant prompt is disabled early to avoid double-rendering prompt
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

alias l='eza -l --colour=always --icons=always'
alias ls='eza -l --colour=always --icons=always'
alias ll='eza -lah --colour=always --icons=always --group-directories-first'
alias la='eza -a --colour=always --icons=always'

# Keybinds
bindkey '^E' end-of-line                # Ctrl + E: Move cursor to the end of the line
bindkey '^A' beginning-of-line          # Ctrl + A: Move cursor to the start of the line
bindkey '^N' menu-complete              # Ctrl + N: Move to the next suggestion
bindkey '^P' reverse-menu-complete      # Ctrl + P: Move to the previous suggestion

# fzf: Ctrl + T files, Alt + C cd
source <(fzf --zsh)

# atuin: Ctrl + R history, shared with nushell. Loads after fzf to take
# Ctrl + R; Up stays zsh's own history.
eval "$(atuin init zsh --disable-up-arrow)"

# zoxide: `z <part of a path>` jumps to a folder visited before
eval "$(zoxide init zsh)"

alias skim='/Applications/Skim.app/Contents/MacOS/Skim'
alias vi="$EDITOR"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

eval "$(mise activate zsh)"
