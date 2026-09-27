#!/usr/bin/osascript

# @raycast.schemaVersion 1
# @raycast.title Undo Recording Mode
# @raycast.mode silent
# @raycast.icon 🎬
# @raycast.packageName System

tell application "System Events" to tell dock preferences
	set autohide menu bar to false
end tell
