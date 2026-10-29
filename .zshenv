# Drop duplicate PATH and fpath entries in every shell, nested ones included.
typeset -U path fpath

# XDG config dir: macOS tools such as lazygit and nushell otherwise read
# ~/Library/Application Support, outside this repo.
export XDG_CONFIG_HOME="$HOME/.config"

# GITHUB_TOKEN for the github MCP server (Codex, OpenCode), read from gh's
# keychain credential so no secret sits in a file. Here, not .zshrc, so
# agents started outside an interactive shell get it too. Full path:
# Homebrew joins PATH later, in .zprofile. An inherited token skips the
# lookup (~30 ms).
if [[ -z $GITHUB_TOKEN && -x /opt/homebrew/bin/gh ]]; then
  export GITHUB_TOKEN="$(/opt/homebrew/bin/gh auth token 2>/dev/null)"
fi

# CONTEXT7_API_KEY for the context7 MCP server, read from the Keychain.
# An inherited key skips the lookup (~14 ms).
[[ -n $CONTEXT7_API_KEY ]] ||
  export CONTEXT7_API_KEY="$(security find-generic-password -a "$USER" -s "context7-api-key" -w 2>/dev/null)"

# Here, not .zshrc, so nu (started without .zshrc) gets them too.
export EDITOR=nvim
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# nu habit: `^cmd` (nu's "run the external command") runs cmd in zsh too.
command_not_found_handler() {
  if [[ $1 == '^'?* ]]; then "${1#^}" "${@:2}"; return; fi
  print -u2 "zsh: command not found: $1"
  return 127
}
