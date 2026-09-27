. "$HOME/.cargo/env"

# GITHUB_TOKEN for Codex/OpenCode's github MCP server: pulled fresh from gh's
# keychain-backed credential on every shell start (login, interactive, non-interactive,
# scripts) rather than a static secret sitting in a file. Sourced here (not .zshrc)
# so it's set even when codex/opencode are launched outside an interactive shell.
if command -v gh >/dev/null 2>&1; then
  export GITHUB_TOKEN="$(gh auth token 2>/dev/null)"
fi

# CONTEXT7_API_KEY for the context7 MCP server: pulled fresh from macOS Keychain
# on every shell start, never a static secret sitting in a file.
export CONTEXT7_API_KEY="$(security find-generic-password -a "$USER" -s "context7-api-key" -w 2>/dev/null)"
