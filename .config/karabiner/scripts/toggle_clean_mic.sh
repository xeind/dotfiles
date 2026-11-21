#!/bin/sh
# Toggle Audio Hijack's "Clean Mic" session (Hyper s v).
# Audio Hijack running: open clean_mic_toggle.ahcommand in the background, which starts or
# stops the session and reports On or Off. The app stays open, so a toggle costs no launch.
# Audio Hijack closed: launch it; the session has Auto Run: On Launch, so this turns it on.

APP='Audio Hijack'
COMMAND_FILE="$(dirname "$0")/clean_mic_toggle.ahcommand"

notify() {
  osascript -e "display notification \"$1\" with title \"Clean Mic\""
}

if pgrep -xq "$APP"; then
  open -g -b com.rogueamoeba.audiohijack "$COMMAND_FILE" || notify "Failed: Audio Hijack did not run the toggle"
else
  open -g -a "$APP.app" || {
    notify "Failed: Audio Hijack did not open"
    exit 1
  }
  notify "On"
fi
