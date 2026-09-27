#!/usr/bin/osascript

# @raycast.schemaVersion 1
# @raycast.title Dismiss Notifications
# @raycast.mode silent
# @raycast.icon 🔕
# @raycast.packageName System

-- Clears every notification in Notification Center (macOS 26+).
-- Notes: avoid AppleScript reserved words (it, items, container) as variable names;
-- AX action names are multi-line ("Name:Clear All\nTarget:..."), so match with "contains".

on panelOpen()
	tell application "System Events" to tell process "NotificationCenter"
		try
			get scroll area 1 of group 1 of group 1 of window 1
			return true
		on error
			return false
		end try
	end tell
end panelOpen

on toggleClock()
	-- macOS 27: status items moved from ControlCenter to MenuBarAgent.
	tell application "System Events" to tell process "MenuBarAgent"
		repeat with g in every group of menu bar 1
			set mi to menu bar item 1 of g
			if (value of attribute "AXIdentifier" of mi) is "com.apple.menuextra.clock" then
				perform action "AXPress" of mi
				exit repeat
			end if
		end repeat
	end tell
end toggleClock

if not panelOpen() then
	toggleClock()
	delay 0.8
end if

tell application "System Events" to tell process "NotificationCenter"
	repeat 40 times
		try
			set grp to group 1 of scroll area 1 of group 1 of group 1 of window 1
			set done to true
			-- Expanded app groups show a heading row with an X (clear group) button.
			set xButtons to every button of grp
			if (count of xButtons) > 0 then
				click item 1 of xButtons
				set done to false
			else
				set notes to every group of grp
				repeat with n in notes
					set sr to (subrole of n as text)
					if sr is "AXNotificationCenterBannerStack" or sr is "AXNotificationCenterBanner" then
						set wanted to "Close"
						if sr is "AXNotificationCenterBannerStack" then set wanted to "Clear All"
						repeat with a in actions of n
							if (name of a) contains wanted then
								perform a
								exit repeat
							end if
						end repeat
						set done to false
						exit repeat
					end if
				end repeat
			end if
			if done then exit repeat
			delay 0.5
		on error m
			log "LOOP ERROR: " & m
			exit repeat
		end try
	end repeat
end tell

delay 0.3
if panelOpen() then toggleClock()
