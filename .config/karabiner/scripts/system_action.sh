#!/bin/bash
# System actions run by Tinycast custom commands.
# Usage: system_action.sh awake|screen-on|screen-off
# The last line on stdout is the confirmation text Tinycast shows.
# Absolute binary paths: Tinycast may start this without the user's PATH.

OSASCRIPT=/usr/bin/osascript
PMSET=/usr/bin/pmset

mode=$1

# Runs AppleScript lines against Amphetamine.
amphetamine() {
  local args=(-e 'tell application "Amphetamine"')
  for line in "$@"; do args+=(-e "$line"); done
  "$OSASCRIPT" "${args[@]}" -e 'end tell'
}

# Turns the screen off in 1.5 s; the hotkey's own key releases would wake it
# straight back up. Detached, so Tinycast can show its message.
sleep_screen_soon() {
  nohup /bin/sh -c "sleep 1.5; $PMSET displaysleepnow" >/dev/null 2>&1 &
}

# True while an Amphetamine session holds its sleep block.
amphetamine_asserting() {
  "$PMSET" -g assertions | grep -q 'named: "Amphetamine'
}

# True while Mole holds its Keep Screen On sleep block.
mole_awake() {
  "$PMSET" -g assertions | grep -q 'named: "Mole Keep Screen On"'
}

# Presses Mole's Keep Screen On shortcut, ctrl-option-shift-command-A.
press_mole_shortcut() {
  "$OSASCRIPT" -e 'tell application "System Events" to keystroke "a" using {control down, option down, shift down, command down}'
}

case $mode in
  awake)
    # An Amphetamine session with no end that lets the screen sleep and keeps
    # the Mac running with the lid closed; closed-display mode is set for this
    # session only, so Amphetamine's own default stays as it is.
    pgrep -xq Amphetamine || { echo "Amphetamine isn't running"; exit 1; }
    # A failed query must not read as "no session" and start one over a live one.
    active=$(amphetamine 'session is active') || { echo "Amphetamine didn't answer"; exit 1; }
    # A fast off-and-on would otherwise leave the old watcher beside the new one.
    /usr/bin/pkill -f 'system_action.sh lid-watch'
    if [ "$active" = true ]; then
      amphetamine 'end session' >/dev/null
      # Tinycast shows a line led by "~ " in its neutral gray instead of success green.
      echo "~ Amphetamine OFF"
    else
      amphetamine 'start new session with options {duration:0, interval:0, displaySleepAllowed:true}' \
        'enable closed display mode' >/dev/null || { echo "Amphetamine didn't start"; exit 1; }
      nohup /bin/bash "$0" lid-watch >/dev/null 2>&1 &
      # Tinycast's HUD gives a trailing ON or OFF one width, so toggling doesn't shift it.
      echo "Amphetamine ON"
    fi
    ;;
  lid-watch)
    # Amphetamine's closed-lid session sets disablesleep, which also stops macOS
    # turning the display off when the lid closes, so do that here. Runs for as
    # long as the session holds its sleep block, which can register just after
    # the session starts. Repeats while closed, since anything that wakes the
    # display under a shut lid would otherwise leave it lit.
    for _ in 1 2 3 4 5; do
      amphetamine_asserting && break
      sleep 1
    done
    while amphetamine_asserting; do
      if /usr/sbin/ioreg -r -k AppleClamshellState -d 1 | grep -q '"AppleClamshellState" = Yes'; then
        "$PMSET" displaysleepnow
      fi
      sleep 2
    done
    ;;
  screen-on)
    pgrep -xq Mole || { echo "Mole isn't running"; exit 1; }
    if mole_awake; then before=1; else before=0; fi
    press_mole_shortcut
    # Mole takes a moment to create or release its assertion.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      if mole_awake; then now=1; else now=0; fi
      [ "$now" != "$before" ] && break
      sleep 0.1
    done
    if [ "$now" = "$before" ]; then
      echo "Screen Hold didn't change"
    elif [ "$now" = 1 ]; then
      echo "Screen Hold ON"
    else
      echo "~ Screen Hold OFF"
    fi
    ;;
  screen-off)
    sleep_screen_soon
    echo "Screen OFF"
    ;;
  *)
    echo "Unknown action: $mode"
    ;;
esac
