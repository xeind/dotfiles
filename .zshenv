# Drop duplicate PATH and fpath entries in every shell, nested ones included.
typeset -U path fpath

# XDG config dir: macOS tools such as lazygit and nushell otherwise read
# ~/Library/Application Support, outside this repo.
export XDG_CONFIG_HOME="$HOME/.config"

# GITHUB_TOKEN for Codex/OpenCode's github MCP server: pulled fresh from gh's
# keychain-backed credential on every shell start (login, interactive, non-interactive,
# scripts) rather than a static secret sitting in a file. Sourced here (not .zshrc)
# so it's set even when codex/opencode are launched outside an interactive shell.
# Full path: .zshenv runs before .zprofile puts Homebrew on PATH.
if [[ -x /opt/homebrew/bin/gh ]]; then
  export GITHUB_TOKEN="$(/opt/homebrew/bin/gh auth token 2>/dev/null)"
fi

# CONTEXT7_API_KEY for the context7 MCP server: pulled fresh from macOS Keychain
# on every shell start, never a static secret sitting in a file.
export CONTEXT7_API_KEY="$(security find-generic-password -a "$USER" -s "context7-api-key" -w 2>/dev/null)"

# Here, not .zshrc, so nu (started without .zshrc) gets them too.
export EDITOR=nvim
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export TMUX_CONF="$HOME/.config/tmux/tmux.conf"
