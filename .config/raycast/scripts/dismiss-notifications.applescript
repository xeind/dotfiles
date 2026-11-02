#!/usr/bin/osascript

# @raycast.schemaVersion 1
# @raycast.title Dismiss Notifications
# @raycast.mode silent
# @raycast.icon 🔕
# @raycast.packageName System

-- Clears every notification in Notification Center (macOS 15 and 26+).
-- Notes: avoid AppleScript reserved words (it, items, container) as variable names;
-- AX action names are multi-line ("Name:Clear All\nTarget:..."), so match with "contains".

-- A banner or alert on screen is also a NotificationCenter window with this path,
-- but there group 1 of the scroll area is the notification itself.
on panelOpen()
	tell application "System Events" to tell process "NotificationCenter"
		try
			set sr to (subrole of group 1 of scroll area 1 of group 1 of group 1 of window 1) as text
			return sr does not start with "AXNotificationCenter"
		on error
			return false
		end try
	end tell
end panelOpen

on toggleClock()
	-- macOS 27: status items moved from ControlCenter to MenuBarAgent.
	-- macOS 15: the clock is a direct menu bar item of ControlCenter.
	-- pgrep, because System Events' "exists process" takes 1.6 s.
	set hasAgent to true
	try
		do shell script "pgrep -qx MenuBarAgent"
	on error
		set hasAgent to false
	end try
	tell application "System Events"
		if hasAgent then
			tell process "MenuBarAgent"
				repeat with g in every group of menu bar 1
					set mi to menu bar item 1 of g
					if (value of attribute "AXIdentifier" of mi) is "com.apple.menuextra.clock" then
						perform action "AXPress" of mi
						exit repeat
					end if
				end repeat
			end tell
		else
			tell process "ControlCenter"
				repeat with mi in every menu bar item of menu bar 1
					if (value of attribute "AXIdentifier" of mi) is "com.apple.menuextra.clock" then
						perform action "AXPress" of mi
						exit repeat
					end if
				end repeat
			end tell
		end if
	end tell
end toggleClock

-- Close banners and alerts on screen; they stay up while the panel opens.
tell application "System Events" to tell process "NotificationCenter"
	repeat 10 times
		try
			set n to group 1 of scroll area 1 of group 1 of group 1 of window 1
			if (subrole of n as text) does not start with "AXNotificationCenter" then exit repeat
			set closed to false
			repeat with a in actions of n
				if (name of a) contains "Close" then
					perform a
					set closed to true
					exit repeat
				end if
			end repeat
			if not closed then exit repeat
			delay 0.5
		on error
			exit repeat
		end try
	end repeat
end tell

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
					if sr is "AXNotificationCenterBannerStack" or sr is "AXNotificationCenterBanner" or sr is "AXNotificationCenterAlert" then
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
