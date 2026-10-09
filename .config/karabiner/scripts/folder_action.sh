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
HERDR=/Users/xein/.local/bin/herdr

FINDER_ID=com.apple.finder
GHOSTTY_ID=com.mitchellh.ghostty

mode=$1

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
  local clip line trimmed cand first="" target="" pane="" pane_read=0 saw_other=0 saw_url=0
  clip=$("$PBPASTE")
  if [ -z "$(trim "$clip")" ] || [ "$(printf '%s' "$clip" | LC_ALL=C wc -c | tr -d ' ')" -gt 4096 ]; then
    echo "Clipboard isn't a path"
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
      if [ "${cand#/}" != "$cand" ]; then
        if [ -e "$cand" ] || [ -L "$cand" ]; then target=$cand; break; fi
      else
        if [ "$pane_read" -eq 0 ]; then pane=$(herdr_pane_dir 2>/dev/null); pane_read=1; fi
        if [ -n "$pane" ] && { [ -e "$pane/$cand" ] || [ -L "$pane/$cand" ]; }; then target=$pane/$cand; break; fi
        if [ -e "$HOME/$cand" ] || [ -L "$HOME/$cand" ]; then target=$HOME/$cand; break; fi
      fi
    done
  done < <(printf '%s\n' "$clip" | "$HEAD" -n 20)
  if [ -n "$target" ]; then
    if [ -d "$target" ] && [ ! -L "$target" ] && ! is_package "$target"; then
      "$OPEN" "$target"
      echo "Opened $(tilde "${target%/}") in Finder"
    else
      "$OPEN" -R "$target"
      echo "Revealed $(tilde "${target%/}")"
    fi
  elif [ "$saw_other" -eq 0 ] && [ "$saw_url" -eq 1 ]; then
    echo "Not a path"
  else
    echo "Not found: $(tilde "${first:0:60}")"
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
      if [ "$count" -eq 1 ]; then echo "Copied $(tilde "$selection")"; else echo "Copied $count paths"; fi
    else
      folder=$(printf '%s\n' "$paths" | head -n 1)
      printf '%s' "$folder" | "$PBCOPY"
      echo "Copied $(tilde "$folder")"
    fi
    ;;
  "$GHOSTTY_ID":copy)
    dir=$(herdr_pane_dir)
    [ -n "$dir" ] || { echo "No folder in this pane"; exit 1; }
    printf '%s' "$dir" | "$PBCOPY"
    echo "Copied $(tilde "$dir")"
    ;;
  "$FINDER_ID":reveal)
    echo "Already in Finder"
    ;;
  "$GHOSTTY_ID":reveal)
    dir=$(herdr_pane_dir)
    [ -n "$dir" ] || { echo "No folder in this pane"; exit 1; }
    "$OPEN" "$dir"
    echo "Opened $(tilde "$dir") in Finder"
    ;;
  *:reveal-clipboard)
    reveal_clipboard
    ;;
  *)
    echo "No folder here"
    ;;
esac
