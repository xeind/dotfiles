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
local open = false -- our own record of "panel shown"; isVisible() can lag
local showing = false -- true from show() until its render callback runs
local cancelShow = false -- the user closed the panel while it was rendering

local function readFile(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("a")
  file:close()
  return content
end

-- hs.json.decode logs an error and returns nil on bad JSON; it does not throw.
local function isJson(raw)
  local ok, value = pcall(hs.json.decode, raw or "")
  return ok and value ~= nil
end

-- The page expects JSON null when there are no insights yet.
local function readInsights()
  local raw = readFile(INSIGHTS)
  if isJson(raw) then return raw end
  return "null"
end

-- Outcome of the last background insights run: { status, message }.
-- Cleared by the next successful run.
local lastRunFailure = nil

local function jsonString(value)
  if value == nil then return "null" end
  return hs.json.encode({ value }):sub(2, -2)
end

-- Log half of the page's `health` object (status "ok" | "missing" | "unreadable").
-- Opens the file but does not read it.
local function logHealth()
  local attributes = hs.fs.attributes(USAGE_LOG)
  if not attributes then return { status = "missing", bytes = 0 } end
  local file = io.open(USAGE_LOG, "r")
  if not file then return { status = "unreadable", bytes = attributes.size } end
  file:close()
  return {
    status = "ok",
    bytes = attributes.size,
    modified = os.date("%Y-%m-%dT%H:%M:%S", attributes.modification),
  }
end

-- Insights half of `health`: "ok" | "stale" | "running" | "missing-tool" | "failed".
local function insightsHealth()
  if insightsTask and insightsTask:isRunning() then return { status = "running" } end
  if lastRunFailure then return lastRunFailure end
  local attributes = hs.fs.attributes(INSIGHTS)
  if attributes and not isJson(readFile(INSIGHTS)) then
    return { status = "failed", message = INSIGHTS .. " is not valid JSON" }
  end
  local fresh = attributes and os.time() - attributes.modification < INSIGHTS_MAX_AGE
  if fresh then return { status = "ok" } end
  if not hs.fs.attributes(INSIGHTS_TOOL) then
    return { status = "missing-tool", message = INSIGHTS_TOOL .. " not found; run `yarn build:insights`" }
  end
  return { status = "stale" }
end

-- Decoded bindings plus raw JSON text. A missing or corrupt file gives an
-- empty list and status "missing" | "invalid" instead of breaking the page.
local function readBindings()
  local raw = readFile(BINDINGS)
  if not raw then return {}, "[]", "missing" end
  local ok, list = pcall(hs.json.decode, raw)
  if not ok or type(list) ~= "table" or (#list == 0 and next(list) ~= nil) then return {}, "[]", "invalid" end
  return list, raw, "ok"
end

local function encodeHealth(log)
  local insights = insightsHealth()
  local _, _, bindingsStatus = readBindings()
  return string.format(
    '{"log":{"status":%s,"bytes":%d,"modified":%s},"insights":{"status":%s,"message":%s},"bindings":{"status":%s}}',
    jsonString(log.status), log.bytes, jsonString(log.modified),
    jsonString(insights.status), jsonString(insights.message),
    jsonString(bindingsStatus)
  )
end

local function readData()
  local health = logHealth()
  local _, bindingsJson = readBindings()
  local data = hs.json.encode({ log = health.status == "ok" and readFile(USAGE_LOG) or "" })
  -- hs.json.encode drops nil values, so splice these in as raw JSON.
  return data:sub(1, -2) .. ',"bindings":' .. bindingsJson .. ',"insights":' .. readInsights()
    .. ',"health":' .. encodeHealth(health) .. "}"
end

-- Sends fresh insights and health to the page, visible or not.
local function pushInsights()
  webview:evaluateJavaScript("setInsights(" .. readInsights() .. "," .. encodeHealth(logHealth()) .. ")")
end

local APP_FOLDERS = { "/Applications", "/System/Applications", HOME .. "/Applications", "/System/Library/CoreServices" }

-- App icons as PNG data URLs, keyed by the app names in bindings.json.
-- Sent once after the page loads, since they never change between opens.
local function readAppIcons()
  local icons = {}
  for _, binding in ipairs((readBindings())) do
    if binding.app and not icons[binding.app] then
      for _, folder in ipairs(APP_FOLDERS) do
        local path = folder .. "/" .. binding.app .. ".app"
        if hs.fs.attributes(path) then
          icons[binding.app] = hs.image.iconForFile(path):setSize({ w = 36, h = 36 }):encodeAsURLString(true, "PNG")
          break
        end
      end
    end
  end
  return icons
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
      local detail = (stderr or ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 200)
      lastRunFailure = {
        status = "failed",
        message = detail ~= "" and detail or ("exit code " .. tostring(exitCode)),
      }
      print("hyperdash: insights failed: " .. lastRunFailure.message)
    else
      lastRunFailure = nil
    end
    pushInsights()
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
  if not open then return end
  open = false
  webview:hide()
  appWatcher:stop()
  if restoreFocus and previousWindow then previousWindow:focus() end
  previousWindow = nil
end

local function show()
  showing = true
  cancelShow = false
  previousWindow = hs.window.focusedWindow()
  -- Start the refresh first, so the page opens with insights.status "running".
  refreshInsights()
  -- Render first, then show: the panel appears complete, with no fade.
  -- place() runs after the render so it uses the new page height.
  webview:evaluateJavaScript("update(" .. readData() .. ")", function(pageHeight)
    showing = false
    -- A toggle or close arrived while rendering: the user wanted it closed.
    if cancelShow then
      cancelShow = false
      previousWindow = nil
      return
    end
    if type(pageHeight) == "number" then height = pageHeight end
    place()
    -- Activating Hammerspoon is enough for the panel to take keyboard
    -- focus. Do not call hswindow():focus(): that Accessibility call to
    -- our own window blocks for about 3 s.
    hs.focus()
    webview:show()
    appWatcher:start()
    open = true
  end)
end

local function create()
  local controller = hs.webview.usercontent.new("dashboard")
  controller:setCallback(function(message)
    if message.body.action == "close" then
      if showing then cancelShow = true else hide(true) end
    elseif message.body.action == "resize" then
      height = message.body.height
      if open then place() end
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
  webview:navigationCallback(function(action)
    if action == "didFinishNavigation" then
      webview:evaluateJavaScript("setIcons(" .. hs.json.encode({ apps = readAppIcons() }) .. ")")
    end
  end)
  webview:html(readFile(PAGE) or "")

  -- Clicking another app closes the panel, like a popover.
  appWatcher = hs.application.watcher.new(function(name, event)
    if name == "Hammerspoon" and event == hs.application.watcher.deactivated then
      hide(false)
    end
  end)
end

-- Deferred, so the `hs -c` call from Karabiner returns at once.
-- The timers sit in `pending`: Hammerspoon stops a timer that nothing
-- references, which silently dropped toggles.
local pending = {}
function M.toggle()
  local timer
  timer = hs.timer.doAfter(0, function()
    pending[timer] = nil
    if showing then
      -- Each toggle during the render flips the intent, so an even number
      -- of toggles always ends hidden.
      cancelShow = not cancelShow
    elseif open then
      hide(true)
    else
      show()
    end
  end)
  pending[timer] = true
end

create()

return M
