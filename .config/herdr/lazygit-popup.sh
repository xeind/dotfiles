#!/bin/sh
# Open lazygit in the focused pane's current folder. herdr starts popups
# in the pane's start folder (`cwd`), which goes stale after a cd; the
# shell's live folder is `foreground_cwd`.
# Full paths and XDG_CONFIG_HOME, so it works even when the herdr server
# started with an older environment.
dir=$("$HOME/.local/bin/herdr" pane list 2>/dev/null | python3 -c '
import json, sys
panes = json.load(sys.stdin)["result"]["panes"]
print(next((p.get("foreground_cwd") or p.get("cwd", "") for p in panes if p.get("focused")), ""))
' 2>/dev/null)
[ -d "$dir" ] && cd "$dir"

# Agent panes (Claude, Codex) stay in the folder they started in; their
# own `cd` never reaches herdr. If that folder is not a repo, use the
# repo one level down, or pick with fzf when there are several.
if ! git rev-parse >/dev/null 2>&1; then
  repos=$(for d in */; do [ -e "$d.git" ] && printf '%s\n' "${d%/}"; done)
  count=$(printf '%s' "$repos" | grep -c .)
  if [ "$count" -eq 1 ]; then
    cd "$repos"
  elif [ "$count" -gt 1 ]; then
    pick=$(printf '%s\n' "$repos" | fzf --prompt="repo > " --layout=reverse --border=none \
      --color=bg+:#444444,bg:#181616,fg:#C4B28A,hl:#7ebcfd,hl+:#7ebcfd,pointer:#D27E99,prompt:#7ebcfd)
    [ -n "$pick" ] && cd "$pick"
  fi
fi
XDG_CONFIG_HOME="$HOME/.config" exec "$HOME/.local/share/mise/shims/lazygit"
