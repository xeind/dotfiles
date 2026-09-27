#!/usr/bin/osascript

# @raycast.schemaVersion 1
# @raycast.title Recording Mode
# @raycast.mode silent
# @raycast.icon 🎥
# @raycast.packageName System

tell application "System Events" to tell dock preferences
	set autohide menu bar to true
end tell
