#!/bin/bash
# Folder actions for the frontmost app, run by Tinycast custom commands.
# Usage: folder_action.sh copy|reveal|reveal-clipboard
# The last line on stdout is the confirmation text Tinycast shows.
# Absolute binary paths: Tinycast may start this without the user's PATH.

OSASCRIPT=/usr/bin/osascript
OPEN=/usr/bin/open
PBCOPY=/usr/bin/pbcopy
PBPASTE=/usr/bin/pbpaste
HEAD=/usr/bin/head
MDLS=/usr/bin/mdls
JQ=/usr/bin/jq
AFPLAY=/usr/bin/afplay
GIT=/usr/bin/git
HERDR=/Users/xein/.local/bin/herdr
REX=/Users/xein/.local/bin/rex

FINDER_ID=com.apple.finder
GHOSTTY_ID=com.mitchellh.ghostty
REX_ID=com.superlogical.rex

mode=$1

# Key sounds from Hex (see sounds/README.md). Each action has its own
# family and a press picks a random variant; a miss is a deeper key twice.
SOUNDS=$(dirname "$0")/sounds
case $mode in
  copy) OK_FAMILY=$SOUNDS/copy ;;
  reveal) OK_FAMILY=$SOUNDS/open ;;
  *) OK_FAMILY=$SOUNDS/reveal ;;
esac
FAIL_SOUND=$SOUNDS/fail.wav

# Plays $1 $2 times, detached, so Tinycast doesn't wait on it and the
# message stays the last line on stdout.
play() {
  ( for (( i = 0; i < ${2:-1}; i++ )); do "$AFPLAY" -v 0.8 "$1"; done >/dev/null 2>&1 & )
}

# Prints a random file from the folder $1. Allows the glob even when the
# caller turned globbing off (reveal_clipboard does), then restores it.
random_sound() {
  local files noglob=0
  case $- in *f*) noglob=1; set +f ;; esac
  files=("$1"/*.wav)
  [ "$noglob" -eq 1 ] && set -f
  printf '%s' "${files[RANDOM % ${#files[@]}]}"
}

# Prints the confirmation text, then plays the matching sound.
ok() { echo "$1"; play "$(random_sound "$OK_FAMILY")"; }
fail() { echo "$1"; play "$FAIL_SOUND" 2; }

# Shows the home folder as ~ in messages only.
tilde() {
  case $1 in
    "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# Prints the window folder, then each selected item, one per line.
finder_paths() {
  "$OSASCRIPT" <<'APPLESCRIPT'
tell application "Finder"
	if (count of Finder windows) > 0 then
		set base to POSIX path of (target of front Finder window as alias)
	else
		set base to POSIX path of (desktop as alias)
	end if
	set out to base
	repeat with anItem in (selection as list)
		set out to out & linefeed & POSIX path of (anItem as alias)
	end repeat
	return out
end tell
APPLESCRIPT
}

# The focused herdr pane's folder; foreground_cwd wins over cwd.
herdr_pane_dir() {
  "$HERDR" pane list | "$JQ" -r '[.result.panes[] | select(.focused)][0] | (.foreground_cwd // .cwd) // empty'
}

# The focused Rex pane's folder. Rex titles its front window
# "<tab> - <session>", and its saved last-focused session goes stale, so
# the title names the session; Rex's API then gives that session's active
# tab, its focused pane, and the folder the pane's shell reported.
rex_pane_dir() {
  local title session block pwd
  title=$("$OSASCRIPT" -e 'tell application "System Events" to tell process "Rex" to get name of window 1') || return
  session=$("$REX" ls --json | "$JQ" -r --arg l "${title##* - }" 'first(.sessions[] | select(.label == $l) | .session_id) // empty')
  [ -n "$session" ] || return
  block=$("$REX" api call session.view "{\"session_id\":\"$session\"}" | "$JQ" -r '.active_window_id as $w | first(.windows[] | select(.window_id == $w) | .focused_block_id) // empty')
  [ -n "$block" ] || return
  pwd=$("$REX" block call -s "$session" -b "$block" pwd | "$JQ" -r '.pwd // empty')
  if [[ $pwd == file://* ]]; then
    pwd=/${pwd#file://*/}
    printf '%b' "${pwd//%/\\x}"
  else
    "$REX" block call -s "$session" -b "$block" process | "$JQ" -r '.foreground.cwd // empty'
  fi
}

# The folder of the frontmost window: the focused Rex or herdr pane, or
# the front Finder window.
front_pane_dir() {
  case $front in
    "$REX_ID") rex_pane_dir ;;
    "$GHOSTTY_ID") herdr_pane_dir ;;
    "$FINDER_ID") finder_paths | "$HEAD" -n 1 ;;
  esac
}

# Sets BASES, the folders a relative path is tried against, in order:
# the frontmost pane or Finder window, its git root, then home.
load_bases() {
  local pane root
  BASES=()
  pane=$(front_pane_dir 2>/dev/null)
  pane=${pane%/}
  if [ -n "$pane" ] && [ -d "$pane" ]; then
    BASES+=("$pane")
    root=$("$GIT" -C "$pane" rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$root" ] && [ "$root" != "$pane" ]; then BASES+=("$root"); fi
  fi
  BASES+=("$HOME")
}

# Prints the first existing path under one of BASES that ends in $1.
# Tries $1 whole, then without its leading folders, up to 8 levels, so
# a path from another machine or worktree still resolves. A shortened
# form keeps at least two parts: a lone file name matches only when it
# was the whole input.
under_bases() {
  local parts n i j rest base
  IFS=/ read -r -a parts <<< "${1#/}"
  n=${#parts[@]}
  for (( i = 0; i < n && i <= 8; i++ )); do
    if [ "$i" -gt 0 ] && [ $((n - i)) -lt 2 ]; then break; fi
    rest=${parts[i]}
    for (( j = i + 1; j < n; j++ )); do rest=$rest/${parts[j]}; done
    for base in "${BASES[@]}"; do
      if [ -e "$base/$rest" ] || [ -L "$base/$rest" ]; then
        printf '%s' "$base/$rest"
        return 0
      fi
    done
  done
  return 1
}

# Trims leading and trailing whitespace from $1.
trim() {
  local t=$1
  t="${t#"${t%%[![:space:]]*}"}"
  printf '%s' "${t%"${t##*[![:space:]]}"}"
}

# Sets CANDIDATE from one clipboard line, and IS_URL=1 for a non-file URL.
# The text is only ever data: never evaluated, never expanded.
clean_candidate() {
  local c prev re='^(.*):[0-9]+(:[0-9]+)?$'
  c=$(trim "$1")
  IS_URL=0
  while :; do
    prev=$c
    case $c in [\"\'\`\(\[\{\<]*) c=${c#?} ;; esac
    case $c in *[\"\'\`\)\]\}\>.,\;:]) c=${c%?} ;; esac
    if [[ $c =~ $re ]]; then c=${BASH_REMATCH[1]}; fi
    [ "$c" != "$prev" ] || break
  done
  if [[ $c == file://* ]]; then
    c=${c#file://}
    c=${c#localhost}
    c=${c//\\/\\\\}
    c=$(printf '%b' "${c//%/\\x}")
  elif [[ $c =~ ^[A-Za-z][A-Za-z0-9+.-]*:// ]] || [[ $c =~ ^(mailto|tel|data|javascript|about): ]]; then
    IS_URL=1
  fi
  case $c in
    "~") c=$HOME ;;
    "~/"*) c=$HOME/${c#"~/"} ;;
  esac
  CANDIDATE=$c
}

# True when `open` would launch $1 instead of showing it in Finder.
is_package() {
  local p=${1%/} ext
  case ${p##*/} in
    *.*) ext=$(printf '%s' "${p##*.}" | tr '[:upper:]' '[:lower:]') ;;
    *) ext= ;;
  esac
  case $ext in
    app|bundle|framework|pkg|mpkg|prefpane|saver|appex|plugin|xpc|workflow|component|kext|action|rtfd|xcodeproj|playground) return 0 ;;
  esac
  [ -e "$p/Contents/Info.plist" ] && return 0
  "$MDLS" -raw -name kMDItemContentTypeTree "$p" 2>/dev/null | grep -q 'com.apple.package\|com.apple.application' && return 0
  return 1
}

# Reveals the first existing path found in the first lines of the clipboard.
reveal_clipboard() {
  set -f
  local clip line trimmed cand first="" target="" bases_read=0 saw_other=0 saw_url=0
  clip=$("$PBPASTE")
  if [ -z "$(trim "$clip")" ] || [ "$(printf '%s' "$clip" | LC_ALL=C wc -c | tr -d ' ')" -gt 4096 ]; then
    fail "Clipboard isn't a path"
    return
  fi
  while IFS= read -r line && [ -z "$target" ]; do
    trimmed=$(trim "$line")
    [ -n "$trimmed" ] || continue
    clean_candidate "$trimmed"
    if [ "$IS_URL" -eq 1 ]; then saw_url=1; continue; fi
    saw_other=1
    [ -n "$first" ] || first=$CANDIDATE
    for cand in "$CANDIDATE" "$trimmed"; do
      [ -n "$cand" ] || continue
      if [ "${cand#/}" != "$cand" ] && { [ -e "$cand" ] || [ -L "$cand" ]; }; then target=$cand; break; fi
      if [ "$bases_read" -eq 0 ]; then load_bases; bases_read=1; fi
      if target=$(under_bases "$cand"); then break; fi
      target=""
    done
  done < <(printf '%s\n' "$clip" | "$HEAD" -n 20)
  if [ -n "$target" ]; then
    if [ -d "$target" ] && [ ! -L "$target" ] && ! is_package "$target"; then
      "$OPEN" "$target"
      ok "Opened $(tilde "${target%/}") in Finder"
    else
      "$OPEN" -R "$target"
      ok "Revealed $(tilde "${target%/}")"
    fi
  elif [ "$saw_other" -eq 0 ] && [ "$saw_url" -eq 1 ]; then
    fail "Not a path"
  else
    fail "Not found: $(tilde "${first:0:60}")"
  fi
}

front=$("$OSASCRIPT" -e 'tell application "System Events" to get bundle identifier of first process whose frontmost is true')

case $front:$mode in
  "$FINDER_ID":copy)
    paths=$(finder_paths)
    selection=$(printf '%s\n' "$paths" | tail -n +2)
    if [ -n "$selection" ]; then
      printf '%s' "$selection" | "$PBCOPY"
      count=$(printf '%s\n' "$selection" | wc -l | tr -d ' ')
      if [ "$count" -eq 1 ]; then ok "Copied $(tilde "$selection")"; else ok "Copied $count paths"; fi
    else
      folder=$(printf '%s\n' "$paths" | head -n 1)
      printf '%s' "$folder" | "$PBCOPY"
      ok "Copied $(tilde "$folder")"
    fi
    ;;
  "$REX_ID":copy)
    dir=$(rex_pane_dir)
    [ -n "$dir" ] || { fail "No folder in this pane"; exit 1; }
    printf '%s' "$dir" | "$PBCOPY"
    ok "Copied $(tilde "$dir")"
    ;;
  "$REX_ID":reveal)
    dir=$(rex_pane_dir)
    [ -n "$dir" ] || { fail "No folder in this pane"; exit 1; }
    "$OPEN" "$dir"
    ok "Opened $(tilde "$dir") in Finder"
    ;;
  "$GHOSTTY_ID":copy)
    dir=$(herdr_pane_dir)
    [ -n "$dir" ] || { fail "No folder in this pane"; exit 1; }
    printf '%s' "$dir" | "$PBCOPY"
    ok "Copied $(tilde "$dir")"
    ;;
  "$FINDER_ID":reveal)
    fail "Already in Finder"
    ;;
  "$GHOSTTY_ID":reveal)
    dir=$(herdr_pane_dir)
    [ -n "$dir" ] || { fail "No folder in this pane"; exit 1; }
    "$OPEN" "$dir"
    ok "Opened $(tilde "$dir") in Finder"
    ;;
  *:reveal-clipboard)
    reveal_clipboard
    ;;
  *)
    fail "No folder here"
    ;;
esac
