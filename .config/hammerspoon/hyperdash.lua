-- hyperdash: a floating panel that ranks Hyper shortcuts by month.
-- Karabiner logs each press and runs `hs -c 'hyperdash.toggle()'`
-- on Hyper + S + Q. The UI lives in ~/.config/karabiner/hyperdash/.

local M = {}

local HOME = os.getenv("HOME")
local PAGE = HOME .. "/.config/karabiner/hyperdash/index.html"
local BINDINGS = HOME .. "/.config/karabiner/hyperdash/bindings.json"
local USAGE_LOG = HOME .. "/.local/state/karabiner/usage.log"
local WIDTH = 408 -- card width plus the shadow margin on both sides
local TOP_FRACTION = 0.18 -- open near the top of the screen, like Spotlight

local webview = nil
local height = 600 -- replaced by the page's own height after each render
local previousWindow = nil
local appWatcher = nil

local function readFile(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("a")
  file:close()
  return content
end

local function readData()
  return hs.json.encode({
    bindings = hs.json.decode(readFile(BINDINGS) or "[]"),
    log = readFile(USAGE_LOG) or "",
  })
end

-- Size the window to the card, so the transparent area never blocks clicks.
local function place()
  local screen = (previousWindow and previousWindow:screen() or hs.screen.mainScreen()):frame()
  webview:frame({
    x = screen.x + (screen.w - WIDTH) / 2,
    y = screen.y + screen.h * TOP_FRACTION,
    w = WIDTH,
    h = height,
  })
end

local function hide(restoreFocus)
  if not webview:isVisible() then return end
  webview:hide()
  webview:evaluateJavaScript("conceal()")
  appWatcher:stop()
  if restoreFocus and previousWindow then previousWindow:focus() end
  previousWindow = nil
end

local function show()
  previousWindow = hs.window.focusedWindow()
  place()
  webview:show()
  webview:evaluateJavaScript("update(" .. readData() .. ")")
  hs.focus()
  webview:hswindow():focus()
  appWatcher:start()
end

local function create()
  local controller = hs.webview.usercontent.new("dashboard")
  controller:setCallback(function(message)
    if message.body.action == "close" then
      hide(true)
    elseif message.body.action == "resize" then
      height = message.body.height
      if webview:isVisible() then place() end
    end
  end)

  webview = hs.webview.new({ x = 0, y = 0, w = WIDTH, h = height }, {}, controller)
    :windowStyle({ "borderless" })
    :transparent(true)
    :shadow(false)
    :allowTextEntry(true)
    :level(hs.drawing.windowLevels.floating)
    :behaviorAsLabels({ "moveToActiveSpace" })

  -- Load the page once and keep it hidden; show() only sends new data.
  webview:html(readFile(PAGE) or "")

  -- Clicking another app closes the panel, like a popover.
  appWatcher = hs.application.watcher.new(function(name, event)
    if name == "Hammerspoon" and event == hs.application.watcher.deactivated then
      hide(false)
    end
  end)
end

-- Deferred, so the `hs -c` call from Karabiner returns at once.
function M.toggle()
  hs.timer.doAfter(0, function()
    if webview:isVisible() then hide(true) else show() end
  end)
end

create()

return M
