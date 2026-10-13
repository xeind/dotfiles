-- Hammerspoon: event-driven automation that Karabiner and Rectangle cannot do.
-- Config path is set with:
--   defaults write org.hammerspoon.Hammerspoon MJConfigFile "~/.config/hammerspoon/init.lua"

require("hs.ipc") -- lets the `hs` CLI reload and query this config
hs.menuIcon(false)
hs.autoLaunch(true)

-- Fit windows to their screen after a display connects or disconnects.
-- macOS moves windows off a removed display but keeps their size, so a
-- window sized for the external display overflows the laptop screen.

local SETTLE_SECONDS = 2 -- screens report their final frames shortly after the change

local function fitWindowsToScreens()
  for _, win in ipairs(hs.window.visibleWindows()) do
    if win:isStandard() and not win:isFullScreen() then
      local frame = win:frame()
      local bounds = win:screen():frame()
      local overflows = frame.w > bounds.w or frame.h > bounds.h
        or frame.x < bounds.x or frame.y < bounds.y
        or frame.x + frame.w > bounds.x + bounds.w
        or frame.y + frame.h > bounds.y + bounds.h
      if overflows then
        local w = math.min(frame.w, bounds.w)
        local h = math.min(frame.h, bounds.h)
        local x = math.max(bounds.x, math.min(frame.x, bounds.x + bounds.w - w))
        local y = math.max(bounds.y, math.min(frame.y, bounds.y + bounds.h - h))
        win:setFrame({ x = x, y = y, w = w, h = h }, 0)
      end
    end
  end
end

local settleTimer = nil

-- Global, so the garbage collector does not stop the watcher.
screenWatcher = hs.screen.watcher.new(function()
  if settleTimer then settleTimer:stop() end
  settleTimer = hs.timer.doAfter(SETTLE_SECONDS, fitWindowsToScreens)
end)
screenWatcher:start()
