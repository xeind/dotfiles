#!/bin/bash
# System actions run by Tinycast custom commands.
# Usage: system_action.sh awake
# The last line on stdout is the confirmation text Tinycast shows.
# Absolute binary paths: Tinycast may start this without the user's PATH.

OSASCRIPT=/usr/bin/osascript
PMSET=/usr/bin/pmset

mode=$1

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
      echo "Awake didn't change"
    elif [ "$now" = 1 ]; then
      echo "Awake on"
    else
      echo "Awake off"
    fi
    ;;
  *)
    echo "Unknown action: $mode"
    ;;
esac
