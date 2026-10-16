-- hyperdash: a floating panel that ranks Hyper shortcuts by month.
-- Karabiner logs each press and runs `hs -c 'hyperdash.toggle()'`
-- on Hyper + S + Q. The UI lives in ~/.config/karabiner/hyperdash/.
--
-- The page keeps the log in memory. This file feeds it incrementally:
-- hyperdash.reset() with the whole log at startup and after any
-- replacement, truncation or rejected update, hyperdash.append() with new
-- complete lines otherwise. Calls go out one at a time, and the consumed
-- offset advances only when the page answers { ok = true }.

local reader = require("hyperdash_core") -- pure helpers; see that file

local M = {}

local HOME = os.getenv("HOME")
local PAGE = HOME .. "/.config/karabiner/hyperdash/index.html"
local BINDINGS = HOME .. "/.config/karabiner/hyperdash/bindings.json"
local USAGE_LOG = HOME .. "/.local/state/karabiner/usage.log"
local INSIGHTS = HOME .. "/.local/state/karabiner/insights.json"
local INSIGHTS_TOOL = HOME .. "/.local/bin/hyperdash-insights" -- `yarn build:insights`
local INSIGHTS_MAX_AGE = 3600 -- seconds; older insights are recomputed on open
local CALL_TIMEOUT = 5 -- seconds to wait for the page to answer one call
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
local pageReady = false -- the page finished loading, so hyperdash.* exists
local pendingOpen = false -- a toggle arrived before the page was ready

local function readFile(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("a")
  file:close()
  return content
end

local function nowIso()
  return os.date("%Y-%m-%dT%H:%M:%S", os.time())
end

local function jsonString(value)
  if value == nil then return "null" end
  return hs.json.encode({ value }):sub(2, -2)
end

-- Modification time, size and inode: enough to notice a changed small file.
local function statKey(path)
  local a = hs.fs.attributes(path)
  if not a then return nil end
  return string.format("%s:%s:%s", a.modification, a.size, a.ino)
end

---------------------------------------------------------------------------
-- Cached inputs. Each is re-read only when its file changed.
---------------------------------------------------------------------------

-- Outcome of the last background insights run: { status, message }.
-- Cleared by the next successful run.
local lastRunFailure = nil

local insightsCache = { key = false, raw = nil, message = nil } -- raw: valid version 2 report
local bindingsCache = { key = false, list = {}, json = "[]", status = "missing", invalid = 0 }

-- Raw JSON of a valid version 2 report. Returns nil when the file is
-- missing, and nil plus a message when it is unusable. hs.json.decode logs
-- an error and returns nil on bad JSON; it does not throw.
local function readInsightsReport()
  local raw = readFile(INSIGHTS)
  if not raw then return nil end
  local ok, decoded = pcall(hs.json.decode, raw)
  if not ok or decoded == nil then return nil, INSIGHTS .. " is not valid JSON" end
  local valid, message = reader.checkInsights(decoded)
  if not valid then return nil, message end
  return raw
end

local function refreshInsightsCache()
  local key = statKey(INSIGHTS)
  if key == insightsCache.key then return end
  insightsCache.key = key
  insightsCache.raw, insightsCache.message = nil, nil
  if key then
    local raw, message = readInsightsReport()
    insightsCache.raw = raw
    insightsCache.message = raw and nil or message or ("cannot read " .. INSIGHTS)
  end
end

-- A missing or corrupt file gives an empty list and status "missing" |
-- "invalid". Entries with the wrong field types are dropped and reported as
-- status "invalid" with a count; the rest still reach the page.
local function refreshBindingsCache()
  local key = statKey(BINDINGS)
  if key == bindingsCache.key then return end
  bindingsCache.key = key
  local raw = readFile(BINDINGS)
  if not raw then
    bindingsCache.list, bindingsCache.json, bindingsCache.status, bindingsCache.invalid = {}, "[]", "missing", 0
    return
  end
  local ok, decoded = pcall(hs.json.decode, raw)
  local list, dropped = reader.sanitizeBindings(ok and decoded or nil)
  if not list then
    bindingsCache.list, bindingsCache.json, bindingsCache.status, bindingsCache.invalid = {}, "[]", "invalid", 0
  elseif dropped == 0 then
    bindingsCache.list, bindingsCache.json, bindingsCache.status, bindingsCache.invalid = list, raw, "ok", 0
  else
    bindingsCache.list, bindingsCache.json, bindingsCache.status, bindingsCache.invalid =
      list, hs.json.encode(list), "invalid", dropped
  end
end

---------------------------------------------------------------------------
-- Health
---------------------------------------------------------------------------

local logState = reader.newState()
local fsEnv = reader.defaultEnv()
local logReadError = nil -- message from the last failed read, cleared by the next good one

-- Log half of the page's `health` object (status "ok" | "missing" | "unreadable").
-- Opens the file but does not read it.
local function logHealth()
  local attributes = hs.fs.attributes(USAGE_LOG)
  if not attributes then return { status = "missing", bytes = 0 } end
  local file = io.open(USAGE_LOG, "r")
  if not file or logReadError then
    if file then file:close() end
    return { status = "unreadable", bytes = attributes.size }
  end
  file:close()
  return {
    status = "ok",
    bytes = attributes.size,
    modified = os.date("%Y-%m-%dT%H:%M:%S", attributes.modification),
    offset = logState.offset,
    generation = logState.generation,
  }
end

-- Insights half of `health`: "ok" | "stale" | "running" | "missing-tool" | "failed".
local function insightsHealth()
  if insightsTask and insightsTask:isRunning() then return { status = "running" } end
  if lastRunFailure then return lastRunFailure end
  if insightsCache.key and not insightsCache.raw then
    return { status = "failed", message = insightsCache.message }
  end
  local attributes = hs.fs.attributes(INSIGHTS)
  local fresh = attributes and os.time() - attributes.modification < INSIGHTS_MAX_AGE
  if fresh then return { status = "ok" } end
  if not hs.fs.attributes(INSIGHTS_TOOL) then
    return { status = "missing-tool", message = INSIGHTS_TOOL .. " not found; run `yarn build:insights`" }
  end
  return { status = "stale" }
end

local function encodeHealth()
  local log, insights = logHealth(), insightsHealth()
  local logExtra = ""
  if log.offset then logExtra = string.format(',"offset":%d,"generation":%d', log.offset, log.generation) end
  return string.format(
    '{"log":{"status":%s,"bytes":%d,"modified":%s%s},"insights":{"status":%s,"message":%s},"bindings":{"status":%s%s}}',
    jsonString(log.status), log.bytes, jsonString(log.modified), logExtra,
    jsonString(insights.status), jsonString(insights.message),
    jsonString(bindingsCache.status),
    bindingsCache.invalid > 0 and (',"invalidEntries":' .. bindingsCache.invalid) or ""
  )
end

---------------------------------------------------------------------------
-- Serial delivery to the page
---------------------------------------------------------------------------

local queue = {} -- { code, onResult }
local busy = false
local callToken = 0 -- identifies the call in flight, so a late answer is ignored
local watchdog = nil

local function pump()
  if busy or #queue == 0 then return end
  local job = table.remove(queue, 1)
  if not job.code then
    -- A barrier: it runs when every earlier call has been answered.
    pcall(job.onResult)
    return pump()
  end
  busy = true
  callToken = callToken + 1
  local token = callToken
  local function finish(result)
    if token ~= callToken then return end -- answered after the watchdog gave up
    callToken = callToken + 1
    busy = false
    if watchdog then watchdog:stop(); watchdog = nil end
    local ok, err = pcall(job.onResult, result)
    if not ok then print("hyperdash: " .. tostring(err)) end
    pump()
  end
  -- Without this, one lost callback would stall every later update.
  watchdog = hs.timer.doAfter(CALL_TIMEOUT, function()
    print("hyperdash: no answer from the page for " .. CALL_TIMEOUT .. " s")
    finish(nil)
  end)
  -- The second callback argument is not an error flag, so judge by the result.
  webview:evaluateJavaScript(job.code, function(result) finish(result) end)
end

local function send(code, onResult)
  queue[#queue + 1] = { code = code, onResult = onResult or function() end }
  pump()
end

-- Runs `fn` after every call queued so far has been answered.
local function afterQueued(fn)
  queue[#queue + 1] = { onResult = fn }
  pump()
end

local function isOk(result)
  return type(result) == "table" and result.ok == true
end

-- A data update may change the page height. Only a visible panel resizes.
local place
local function adoptHeight(result)
  if type(result) == "table" and type(result.height) == "number" then
    height = result.height
    if open then place() end
  end
end

---------------------------------------------------------------------------
-- Reconciling the page with the files
---------------------------------------------------------------------------

local sent = { bindings = nil, insights = nil, health = nil } -- what the page holds
local APP_FOLDERS = { "/Applications", "/System/Applications", HOME .. "/Applications", "/System/Library/CoreServices" }

-- App icons as PNG data URLs, keyed by the app names in bindings.json.
-- Sent once after the page loads, since they never change between opens.
local function readAppIcons()
  local icons = {}
  for _, binding in ipairs(bindingsCache.list) do
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

local function resetCode(action)
  local health = encodeHealth()
  return string.format(
    "window.hyperdash.reset({\"generation\":%d,\"bindings\":%s,\"text\":%s,\"offset\":%d,\"insights\":%s,\"health\":%s})",
    action.generation, bindingsCache.json, jsonString(action.text), action.offset,
    insightsCache.raw or "null", health
  ), health
end

local function appendCode(action)
  return string.format(
    "window.hyperdash.append({\"generation\":%d,\"from\":%d,\"to\":%d,\"text\":%s})",
    action.generation, action.from, action.to, jsonString(action.text)
  )
end

local MAX_LOG_PASSES = 6

-- Bring the page up to date: log first, then bindings, insights and health.
-- `forceHealth` sends health even for a hidden panel (used when opening).
local function runSync(forceHealth, done)
  refreshBindingsCache()
  refreshInsightsCache()

  local function metadata()
    local function afterCall(result)
      adoptHeight(result)
    end
    local health = encodeHealth()
    local insights = insightsCache.raw
    if sent.bindings ~= bindingsCache.json then
      sent.bindings, sent.health = bindingsCache.json, health
      send("window.hyperdash.setBindings(" .. bindingsCache.json .. "," .. health .. ")", function(result)
        if not isOk(result) then sent.bindings = nil end
        afterCall(result)
      end)
    end
    if sent.insights ~= (insights or false) then
      sent.insights, sent.health = insights or false, health
      send("window.hyperdash.setInsights(" .. (insights or "null") .. "," .. health .. ")", function(result)
        if not isOk(result) then sent.insights = nil end
        afterCall(result)
      end)
    end
    if sent.health ~= health and (open or forceHealth) then
      sent.health = health
      send("window.hyperdash.setHealth(" .. health .. ")", function(result)
        if not isOk(result) then sent.health = nil end
        afterCall(result)
      end)
    end
    afterQueued(done)
  end

  local passes = 0
  local function logPhase()
    passes = passes + 1
    local action = reader.plan(logState, fsEnv, USAGE_LOG)
    if action.kind == "retry" and passes < MAX_LOG_PASSES then return logPhase() end
    if action.kind == "none" or action.kind == "retry" then
      logReadError = nil
      return metadata()
    end
    if action.kind == "error" then
      logReadError = action.message
      print("hyperdash: " .. action.message)
      return metadata()
    end
    logReadError = nil
    local code, healthSent
    if action.kind == "reset" then code, healthSent = resetCode(action) else code = appendCode(action) end
    send(code, function(result)
      local good = isOk(result)
      if good and action.kind == "reset" then
        good = result.generation == action.generation and result.offset == action.offset
      elseif good then
        good = result.offset == action.to
      end
      if good then
        reader.commit(logState, action)
        if action.kind == "reset" then
          -- The reset carried bindings, insights and health with it.
          sent.bindings, sent.insights = bindingsCache.json, insightsCache.raw or false
          sent.health = healthSent
        end
        adoptHeight(result)
      else
        -- Rejected, lost or unanswered: the page state is unknown.
        reader.fail(logState)
      end
      if passes < MAX_LOG_PASSES then return logPhase() end
      return metadata()
    end)
  end
  logPhase()
end

-- Only one reconcile runs at a time. A request that arrives mid-run asks for
-- another pass, and its callback runs after that pass.
local syncing, syncAgain, syncWaiters, syncForce = false, false, {}, false
local function requestSync(callback, forceHealth)
  if callback then syncWaiters[#syncWaiters + 1] = callback end
  if forceHealth then syncForce = true end
  if not pageReady then
    -- The page calls back into us once it loads.
    return
  end
  if syncing then
    syncAgain = true
    return
  end
  syncing = true
  local force = syncForce
  syncForce = false
  runSync(force, function()
    syncing = false
    if syncAgain then
      syncAgain = false
      return requestSync()
    end
    local waiters = syncWaiters
    syncWaiters = {}
    for _, waiter in ipairs(waiters) do waiter() end
  end)
end

---------------------------------------------------------------------------
-- Background insights
---------------------------------------------------------------------------

-- The tool runs in the background so a slow disk never delays the panel;
-- the page receives the result through the next reconcile.
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
    requestSync()
  end, { "--log", USAGE_LOG, "--bindings", BINDINGS, "--output", INSIGHTS })
  insightsTask:start()
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

-- Size the window to the card, so the transparent area never blocks clicks.
function place()
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
  -- Reconcile first, then render and show: the panel appears complete, with
  -- no fade. place() runs after the render so it uses the new page height.
  requestSync(function()
    local now = '{"now":' .. jsonString(nowIso()) .. "}"
    send("window.hyperdash.tick(" .. now .. ")", function() end)
    send("window.hyperdash.open(" .. now .. ")", function(result)
      showing = false
      -- A toggle or close arrived while rendering: the user wanted it closed.
      if cancelShow then
        cancelShow = false
        previousWindow = nil
        return
      end
      if type(result) == "table" and type(result.height) == "number" then height = result.height end
      place()
      -- Activating Hammerspoon is enough for the panel to take keyboard
      -- focus. Do not call hswindow():focus(): that Accessibility call to
      -- our own window blocks for about 3 s.
      hs.focus()
      webview:show()
      appWatcher:start()
      open = true
    end)
  end, true)
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

  -- Load the page once and keep it hidden; later calls only send new data.
  webview:navigationCallback(function(action)
    if action == "didFinishNavigation" then
      refreshBindingsCache()
      pageReady = true
      -- setIcons is a plain page function, not a window.hyperdash method.
      send("setIcons(" .. hs.json.encode({ apps = readAppIcons() }) .. ")")
      -- A fresh page holds nothing: the first sync is a reset.
      logState = reader.newState()
      sent.bindings, sent.insights, sent.health = nil, nil, nil
      requestSync()
      if pendingOpen then
        pendingOpen = false
        show()
      end
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
    if not pageReady then
      pendingOpen = not pendingOpen
    elseif showing then
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
