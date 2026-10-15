-- hyperdash: a floating panel that ranks Hyper shortcuts by month.
-- Karabiner logs each press and runs `hs -c 'hyperdash.toggle()'`
-- on Hyper + S + Q. The UI lives in ~/.config/karabiner/hyperdash/.

local M = {}

local HOME = os.getenv("HOME")
local PAGE = HOME .. "/.config/karabiner/hyperdash/index.html"
local BINDINGS = HOME .. "/.config/karabiner/hyperdash/bindings.json"
local USAGE_LOG = HOME .. "/.local/state/karabiner/usage.log"
local INSIGHTS = HOME .. "/.local/state/karabiner/insights.json"
local INSIGHTS_TOOL = HOME .. "/.local/bin/hyperdash-insights" -- `yarn build:insights`
local INSIGHTS_MAX_AGE = 3600 -- seconds; older insights are recomputed on open
local WIDTH = 408 -- card width plus the shadow margin on both sides
local TOP_FRACTION = 0.18 -- open near the top of the screen, like Spotlight

local webview = nil
local height = 600 -- replaced by the page's own height after each render
local previousWindow = nil
local appWatcher = nil
local insightsTask = nil

local function readFile(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("a")
  file:close()
  return content
end

-- The page expects JSON null when there are no insights yet.
local function readInsights()
  local raw = readFile(INSIGHTS)
  if raw and pcall(hs.json.decode, raw) then return raw end
  return "null"
end

local function readData()
  local data = hs.json.encode({
    bindings = hs.json.decode(readFile(BINDINGS) or "[]"),
    log = readFile(USAGE_LOG) or "",
  })
  -- hs.json.encode drops nil values, so splice the insights in as raw JSON.
  return data:sub(1, -2) .. ',"insights":' .. readInsights() .. "}"
end

-- The tool runs in the background so a slow disk never delays the panel;
-- the open panel receives the result through setInsights().
local function refreshInsights()
  if insightsTask and insightsTask:isRunning() then return end
  if not hs.fs.attributes(INSIGHTS_TOOL) then return end
  local attributes = hs.fs.attributes(INSIGHTS)
  if attributes and os.time() - attributes.modification < INSIGHTS_MAX_AGE then return end

  insightsTask = hs.task.new(INSIGHTS_TOOL, function(exitCode, _, stderr)
    if exitCode ~= 0 then
      print("hyperdash: insights failed: " .. stderr)
    elseif webview:isVisible() then
      webview:evaluateJavaScript("setInsights(" .. readInsights() .. ")")
    end
  end, { "--log", USAGE_LOG, "--bindings", BINDINGS, "--output", INSIGHTS })
  insightsTask:start()
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
  refreshInsights()
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
