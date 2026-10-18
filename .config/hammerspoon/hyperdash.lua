-- hyperdash: a floating panel that ranks Hyper shortcuts by month.
-- Karabiner logs each press and runs `hs -c 'hyperdash.toggle()'`
-- on Hyper + S + Q. The UI lives in ~/.config/karabiner/hyperdash/.
--
-- The page keeps the log in memory. This file feeds it incrementally:
-- hyperdash.reset() with the whole log at startup and after any
-- replacement, truncation or rejected update, hyperdash.append() with new
-- complete lines otherwise. Calls go out one at a time, and the consumed
-- offset advances only when the page answers { ok = true }.
--
-- A second stream, the context log, goes through the same calls with
-- stream = "context" and its own generation and offset. Hammerspoon writes
-- that log itself, but only when RECORD_CONTEXT is true.

local reader = require("hyperdash_core") -- pure helpers; see that file

local M = {}

local HOME = os.getenv("HOME")
local PAGE = HOME .. "/.config/karabiner/hyperdash/index.html"
local BINDINGS = HOME .. "/.config/karabiner/hyperdash/bindings.json"
local USAGE_LOG = HOME .. "/.local/state/karabiner/usage.log"
local INSIGHTS = HOME .. "/.local/state/karabiner/insights.json"
local INSIGHTS_TOOL = HOME .. "/.local/bin/hyperdash-insights" -- `yarn build:insights`
local INSIGHTS_MAX_AGE = 3600 -- seconds; older insights are recomputed on open
local INSIGHTS_CONTEXT_MIN_AGE = 300 -- seconds; a newer context log reruns a report older than this
local INSIGHTS_TIMEOUT = 120 -- seconds; a run still going after this is stopped and counts as failed
-- Context recording is OFF until the user approves it. When true, this module
-- appends the frontmost app (bundle ID only) and lock, unlock, sleep and wake
-- events to CONTEXT_LOG. No window titles, URLs or keys are recorded.
local RECORD_CONTEXT = false
local CONTEXT_LOG = HOME .. "/.local/state/hyperdash/context.log"
local CALL_TIMEOUT = 5 -- seconds to wait for the page to answer one call
local WIDTH = 408 -- card width plus the shadow margin on both sides
local TOP_FRACTION = 0.18 -- open near the top of the screen, like Spotlight
local THEME_KEY = "hyperdash.theme" -- hs.settings key; survives reloads and restarts
local DEFAULT_THEME = "manila"
local THEMES = { manila = true, kozo = true, nightingale = true, blueprint = true }

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

-- The saved theme, or the default when nothing valid is saved.
local function savedTheme()
  local value = hs.settings.get(THEME_KEY)
  if type(value) == "string" and THEMES[value] then return value end
  return DEFAULT_THEME
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
local insightsFailures = 0 -- consecutive failed runs, start failures included
local insightsRetryAt = nil -- epoch seconds: no new run before this
local insightsAttempt = nil -- identifies the run whose callback may act
local insightsTimer = nil -- stops a run that outlives INSIGHTS_TIMEOUT

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
local ctxState = reader.newState() -- the context stream: its own generation and offset
local fsEnv = reader.defaultEnv()
local logReadError = nil -- message from the last failed read, cleared by the next good one
local ctxReadError = nil

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

-- Context half of `health`: "ok" | "missing" | "unreadable" | "disabled".
-- "disabled" means recording is off; an old file may still exist and still
-- reaches the page.
local function contextHealth()
  local attributes = hs.fs.attributes(CONTEXT_LOG)
  local bytes = attributes and attributes.size or 0
  local modified = attributes and os.date("%Y-%m-%dT%H:%M:%S", attributes.modification) or nil
  if not RECORD_CONTEXT then return { status = "disabled", bytes = bytes, modified = modified } end
  if not attributes then return { status = "missing", bytes = 0 } end
  local file = io.open(CONTEXT_LOG, "r")
  if not file or ctxReadError then
    if file then file:close() end
    return { status = "unreadable", bytes = bytes }
  end
  file:close()
  return { status = "ok", bytes = bytes, modified = modified }
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
  local log, insights, context = logHealth(), insightsHealth(), contextHealth()
  local logExtra = ""
  if log.offset then logExtra = string.format(',"offset":%d,"generation":%d', log.offset, log.generation) end
  return string.format(
    '{"log":{"status":%s,"bytes":%d,"modified":%s%s},"insights":{"status":%s,"message":%s,"retryAt":%s},"bindings":{"status":%s%s},"context":{"status":%s,"bytes":%d,"modified":%s}}',
    jsonString(log.status), log.bytes, jsonString(log.modified), logExtra,
    jsonString(insights.status), jsonString(insights.message), jsonString(insights.retryAt),
    jsonString(bindingsCache.status),
    bindingsCache.invalid > 0 and (',"invalidEntries":' .. bindingsCache.invalid) or "",
    jsonString(context.status), context.bytes, jsonString(context.modified)
  )
end

---------------------------------------------------------------------------
-- Serial delivery to the page
---------------------------------------------------------------------------

local queue = {} -- { code, onResult }
local busy = false
local callToken = 0 -- identifies the call in flight, so a late answer is ignored
local watchdog = nil
local recoverPage -- defined below; reloads the page after its process dies
local recoveryStreak = 0 -- reloads since the last call the page answered

-- A successful call returns an error table with code 0 and no message. A
-- terminated WebContent process returns no result and WKErrorDomain code 5.
local function pageError(err)
  return type(err) == "table" and ((err.code or 0) ~= 0 or err.NSLocalizedDescription ~= nil or err.description ~= nil)
end

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
  local function finish(result, dead)
    if token ~= callToken then return end -- answered after the watchdog gave up
    callToken = callToken + 1
    busy = false
    if watchdog then watchdog:stop(); watchdog = nil end
    local ok, err = pcall(job.onResult, result, dead)
    if not ok then print("hyperdash: " .. tostring(err)) end
    if dead then recoverPage() else recoveryStreak = 0 end
    pump()
  end
  -- Without this, one lost callback would stall every later update.
  watchdog = hs.timer.doAfter(CALL_TIMEOUT, function()
    print("hyperdash: no answer from the page for " .. CALL_TIMEOUT .. " s")
    finish(nil, true)
  end)
  webview:evaluateJavaScript(job.code, function(result, err) finish(result, pageError(err)) end)
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

-- Bundle ID -> display name, for the context stream. Built from the
-- installed bundles (scanned once) and the running apps (every time, since
-- they change).
local installedApps = nil
local function scanInstalledApps()
  local map = {}
  for _, folder in ipairs(APP_FOLDERS) do
    local ok, iterate, directory = pcall(hs.fs.dir, folder)
    if ok and iterate then
      for entry in iterate, directory do
        if entry:sub(-4) == ".app" then
          local info = hs.application.infoForBundlePath(folder .. "/" .. entry)
          local id = info and info.CFBundleIdentifier
          if reader.validBundleId(id) then
            map[id] = info.CFBundleDisplayName or info.CFBundleName or entry:sub(1, -5)
          end
        end
      end
    end
  end
  return map
end

local function collectAppNames(running)
  installedApps = installedApps or scanInstalledApps()
  local map = {}
  for id, name in pairs(installedApps) do map[id] = name end
  for _, app in ipairs(running) do
    local id = app:bundleID()
    if reader.validBundleId(id) and app:name() then map[id] = app:name() end
  end
  return map
end

-- App icons as PNG data URLs. The apps in bindings.json are keyed by name,
-- as before; those and the running regular apps are also keyed by bundle ID.
-- Icons are cached: encoding one is the costly part.
local iconCache = {} -- path -> { url, bundleId }
local function iconFor(path)
  if iconCache[path] == nil then
    local info = hs.application.infoForBundlePath(path)
    iconCache[path] = {
      url = hs.image.iconForFile(path):setSize({ w = 36, h = 36 }):encodeAsURLString(true, "PNG"),
      bundleId = info and info.CFBundleIdentifier,
    }
  end
  return iconCache[path].url, iconCache[path].bundleId
end

local function readAppIcons(running)
  local icons = {}
  for _, binding in ipairs(bindingsCache.list) do
    if binding.app and not icons[binding.app] then
      for _, folder in ipairs(APP_FOLDERS) do
        local path = folder .. "/" .. binding.app .. ".app"
        if hs.fs.attributes(path) then
          local url, bundleId = iconFor(path)
          icons[binding.app] = url
          if reader.validBundleId(bundleId) then icons[bundleId] = url end
          break
        end
      end
    end
  end
  for _, app in ipairs(running) do
    -- path() throws (NSBundle initWithURL: nil) for background processes
    -- that have a bundle ID but no bundle, so ask only regular apps.
    local id = app:bundleID()
    local path = (reader.validBundleId(id) and app:kind() == 1) and app:path() or nil
    if reader.validBundleId(id) and path and app:kind() == 1 and not icons[id] then icons[id] = iconFor(path) end
  end
  return icons
end

-- An empty Lua table encodes as a JSON array; the page expects an object.
local function encodeMap(map)
  if next(map) == nil then return "{}" end
  return hs.json.encode(map)
end

-- What the page holds, as a signature: it is sent again only when it changes.
local sentApps = { names = nil, icons = nil }
local function sendApps()
  local running = hs.application.runningApplications() -- listed once per sync
  local names, icons = collectAppNames(running), readAppIcons(running)
  local iconKeys = {}
  for key in pairs(icons) do iconKeys[key] = 1 end
  local namesSignature, iconsSignature = reader.mapSignature(names), reader.mapSignature(iconKeys)
  if sentApps.names ~= namesSignature then
    sentApps.names = namesSignature
    send("window.hyperdash.setApps(" .. encodeMap(names) .. ")")
  end
  if sentApps.icons ~= iconsSignature then
    sentApps.icons = iconsSignature
    send("setIcons({\"apps\":" .. encodeMap(icons) .. "})")
  end
end

-- Names and icons are not needed for a sync to finish, and building them
-- calls into AppKit, which can raise (app:path() did, for background
-- processes). Running them inside the sync once left `syncing` set forever,
-- so every later open waited on it. They run on their own retained timer: a
-- failure there cannot touch the sync's state. pcall is not enough, because
-- it does not catch a native Objective-C exception; the timer boundary does.
local appsTimer = nil
local function scheduleApps()
  if appsTimer then return end -- one pending run covers every request
  appsTimer = hs.timer.doAfter(0, function()
    appsTimer = nil
    if not pageReady then return end -- the next load sends them again
    local ok, err = pcall(sendApps)
    if not ok then print("hyperdash: apps: " .. tostring(err)) end
  end)
end

local function resetCode(action, which)
  if which == "context" then
    return string.format(
      "window.hyperdash.reset({\"stream\":\"context\",\"generation\":%d,\"text\":%s,\"offset\":%d})",
      action.generation, jsonString(action.text), action.offset
    )
  end
  local health = encodeHealth()
  return string.format(
    "window.hyperdash.reset({\"generation\":%d,\"bindings\":%s,\"text\":%s,\"offset\":%d,\"insights\":%s,\"health\":%s})",
    action.generation, bindingsCache.json, jsonString(action.text), action.offset,
    insightsCache.raw or "null", health
  ), health
end

local function appendCode(action, which)
  local stream = which == "context" and "\"stream\":\"context\"," or ""
  return string.format(
    "window.hyperdash.append({%s\"generation\":%d,\"from\":%d,\"to\":%d,\"text\":%s})",
    stream, action.generation, action.from, action.to, jsonString(action.text)
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

  -- One stream (usage or context): plan, send, and repeat until it is current.
  local function streamPhase(which, after)
    local passes = 0
    local path = which == "usage" and USAGE_LOG or CONTEXT_LOG
    local function setReadError(message)
      if which == "usage" then logReadError = message else ctxReadError = message end
    end
    local function pass()
      passes = passes + 1
      local state = which == "usage" and logState or ctxState
      local action = reader.plan(state, fsEnv, path)
      if action.kind == "retry" and passes < MAX_LOG_PASSES then return pass() end
      -- A context log that never existed has nothing to send.
      if which == "context" and action.kind == "reset" and action.status == "missing" and state.generation == 0 then
        setReadError(nil)
        return after()
      end
      if action.kind == "none" or action.kind == "retry" then
        setReadError(nil)
        return after()
      end
      if action.kind == "error" then
        setReadError(action.message)
        print("hyperdash: " .. action.message)
        return after()
      end
      setReadError(nil)
      local code, healthSent
      if action.kind == "reset" then code, healthSent = resetCode(action, which) else code = appendCode(action, which) end
      send(code, function(result)
        local good = isOk(result)
        if good and action.kind == "reset" then
          good = result.generation == action.generation and result.offset == action.offset
        elseif good then
          good = result.offset == action.to
        end
        if good then
          reader.commit(state, action)
          if action.kind == "reset" and which == "usage" then
            -- The reset carried bindings, insights and health with it.
            sent.bindings, sent.insights = bindingsCache.json, insightsCache.raw or false
            sent.health = healthSent
          end
          adoptHeight(result)
        else
          -- Rejected, lost or unanswered: the page state is unknown.
          reader.fail(state)
        end
        if passes < MAX_LOG_PASSES then return pass() end
        return after()
      end)
    end
    pass()
  end

  scheduleApps()
  streamPhase("usage", function() streamPhase("context", metadata) end)
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
-- A dead page
--
-- hs.webview 1.1.1 does not report the termination of its WebContent process
-- (HSWebViewView does not implement webViewWebContentProcessDidTerminate:),
-- so a dead page shows only as a failed call. Recovery reloads it with
-- html(), which starts a new process, and the navigation handler resends
-- everything with a reset.
---------------------------------------------------------------------------

local PAGE_RELOAD_TIMEOUT = 5 -- seconds to wait for a reloaded page
local MAX_RECOVERIES = 2 -- reloads in a row before giving up until the next toggle
local recovering = false
local pageFailed = false -- the last reload did not finish
local recoveryCallbacks = {}
local recoveryTimer = nil

local function giveUp(reason)
  showing = false
  cancelShow = false
  previousWindow = nil
  pendingOpen = false
  print("hyperdash: page failed to load: " .. reason)
  hs.alert.show("hyperdash: page failed to load")
end

local function recoveryFailed(reason)
  recovering = false
  pageFailed = true
  if recoveryTimer then recoveryTimer:stop(); recoveryTimer = nil end
  recoveryCallbacks = {}
  syncWaiters = {}
  if showing or pendingOpen then giveUp(reason) end
end

-- `onDone(true)` runs once the reloaded page has finished loading.
function recoverPage(onDone)
  if onDone then recoveryCallbacks[#recoveryCallbacks + 1] = onDone end
  if recovering then return end
  recoveryStreak = recoveryStreak + 1
  if recoveryStreak > MAX_RECOVERIES then return recoveryFailed("the page keeps failing") end
  recovering = true
  pageReady = false
  print("hyperdash: page not answering; reloading it")
  -- Queued calls were meant for the dead page. The reload ends in a reset,
  -- which resends everything, so drop them and let a new sync start.
  queue = {}
  syncing, syncAgain = false, false
  recoveryTimer = hs.timer.doAfter(PAGE_RELOAD_TIMEOUT, function() recoveryFailed("reload did not finish") end)
  webview:html(readFile(PAGE) or "")
end

---------------------------------------------------------------------------
-- Background insights
---------------------------------------------------------------------------

-- The context log is passed only when recording is on and the file exists:
-- the tool exits 1 for a missing --context file.
local function insightsArguments()
  local arguments = { "--log", USAGE_LOG, "--bindings", BINDINGS, "--output", INSIGHTS }
  if RECORD_CONTEXT and hs.fs.attributes(CONTEXT_LOG) then
    arguments[#arguments + 1] = "--context"
    arguments[#arguments + 1] = CONTEXT_LOG
  end
  return arguments
end

-- A report is due when it is missing or older than INSIGHTS_MAX_AGE. With
-- recording on, a context log newer than the report also makes it due, but
-- only once the report is INSIGHTS_CONTEXT_MIN_AGE old: opening the panel
-- itself writes a context event, so without the wait every open would rerun.
local function insightsDue()
  local report = hs.fs.attributes(INSIGHTS)
  if not report then return true end
  local age = os.time() - report.modification
  if age >= INSIGHTS_MAX_AGE then return true end
  local context = RECORD_CONTEXT and hs.fs.attributes(CONTEXT_LOG)
  return context and context.modification > report.modification and age >= INSIGHTS_CONTEXT_MIN_AGE or false
end

-- A failed run leaves the old report in place, so the report stays "due".
-- Without a pause every open would start another failing process. Each
-- failure sets the earliest next run (reader.insightsBackoff); a success
-- clears it. The open path only starts the task; it never waits for it.
local function recordInsightsFailure(message)
  insightsFailures = insightsFailures + 1
  insightsRetryAt = os.time() + reader.insightsBackoff(insightsFailures)
  lastRunFailure = {
    status = "failed",
    message = message .. " (next try " .. os.date("%H:%M", insightsRetryAt) .. ")",
    retryAt = os.date("%Y-%m-%dT%H:%M:%S", insightsRetryAt),
  }
  print("hyperdash: insights failed: " .. message)
end

-- The tool runs in the background so a slow disk never delays the panel;
-- the page receives the result through the next reconcile.
local function refreshInsights()
  if insightsTask and insightsTask:isRunning() then return end
  if not hs.fs.attributes(INSIGHTS_TOOL) then return end
  if insightsRetryAt and os.time() < insightsRetryAt then return end
  if not insightsDue() then return end

  local attempt = {}
  insightsAttempt = attempt
  insightsTask = hs.task.new(INSIGHTS_TOOL, function(exitCode, _, stderr)
    if insightsAttempt ~= attempt then return end -- a start failure already counted
    if insightsTimer then insightsTimer:stop(); insightsTimer = nil end
    if attempt.timedOut then
      recordInsightsFailure("timed out after " .. INSIGHTS_TIMEOUT .. " s")
    elseif exitCode ~= 0 then
      local detail = (stderr or ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 200)
      recordInsightsFailure(detail ~= "" and detail or ("exit code " .. tostring(exitCode)))
    else
      lastRunFailure, insightsFailures, insightsRetryAt = nil, 0, nil
    end
    requestSync()
  end, insightsArguments())

  -- start() may raise, return nil, or return a task that is not running.
  local ok, started = pcall(function() return insightsTask:start() end)
  if not ok or not started or not insightsTask:isRunning() then
    insightsAttempt = nil
    recordInsightsFailure("could not start " .. INSIGHTS_TOOL .. (ok and "" or (": " .. tostring(started))))
    requestSync()
    return
  end
  -- A run that never exits would report "running" forever and block every
  -- later run. Stop it; its exit callback records the failure.
  insightsTimer = hs.timer.doAfter(INSIGHTS_TIMEOUT, function()
    insightsTimer = nil
    if insightsAttempt ~= attempt or not insightsTask:isRunning() then return end
    attempt.timedOut = true
    insightsTask:terminate()
  end)
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
  -- A page that does not answer is reloaded once; a window is never shown
  -- for a dead page, because it would be blank and still take focus.
  local attempts = 0
  local function try()
    attempts = attempts + 1
    requestSync(function()
      if not showing then return end -- gave up while the page reloaded
      local now = '{"now":' .. jsonString(nowIso()) .. "}"
      send("window.hyperdash.tick(" .. now .. ")", function() end)
      send("window.hyperdash.open(" .. now .. ")", function(result, dead)
        -- A toggle or close arrived while rendering: the user wanted it closed.
        if cancelShow then
          showing = false
          cancelShow = false
          previousWindow = nil
          return
        end
        if dead or type(result) ~= "table" or type(result.height) ~= "number" then
          if attempts == 1 then
            recoverPage(function(loaded)
              if loaded and showing then try() end
            end)
            return
          end
          return giveUp("no answer after a reload")
        end
        showing = false
        height = result.height
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
  try()
end

local function create()
  local controller = hs.webview.usercontent.new("dashboard")
  controller:setCallback(function(message)
    if message.body.action == "close" then
      if showing then cancelShow = true else hide(true) end
    elseif message.body.action == "theme" then
      -- The page has already applied it; save a valid name and say nothing back.
      local name = message.body.theme
      if type(name) == "string" and THEMES[name] then hs.settings.set(THEME_KEY, name) end
    elseif message.body.action == "resize" then
      height = message.body.height
      if open then place() end
      -- A growing card waits for the taller window before it moves (DESIGN.md §8).
      local id = message.body.transition
      if type(id) == "number" and id >= 1 and id < 2 ^ 31 and id % 1 == 0 then
        send(string.format("window.hyperdash.hostReady(%d)", id))
      end
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
      -- Ends the initial load's timeout as well as a reload's.
      recovering = false
      if recoveryTimer then recoveryTimer:stop(); recoveryTimer = nil end
      pageFailed = false
      refreshBindingsCache()
      pageReady = true
      -- A fresh page holds nothing: send names and icons again, and the
      -- first sync of each stream is a reset.
      sentApps.names, sentApps.icons = nil, nil
      -- A fresh page shows the default theme: apply the saved one first, after
      -- a reload too.
      send("window.hyperdash.setTheme(" .. jsonString(savedTheme()) .. ")")
      logState = reader.newState()
      ctxState = reader.newState()
      sent.bindings, sent.insights, sent.health = nil, nil, nil
      requestSync()
      local callbacks = recoveryCallbacks
      recoveryCallbacks = {}
      for _, callback in ipairs(callbacks) do callback(true) end
      if pendingOpen then
        pendingOpen = false
        show()
      end
    elseif (action == "didFailNavigation" or action == "didFailProvisionalNavigation") and (recovering or not pageReady) then
      -- A failed first load enters the same failed state as a failed reload,
      -- so the next toggle retries instead of waiting for a page that is not coming.
      recoveryFailed("navigation failed")
    end
  end)
  webview:html(readFile(PAGE) or "")
  -- Bound the first load too: without this, a load that never ends leaves
  -- pageReady and pageFailed false, and every toggle just waits.
  recoveryTimer = hs.timer.doAfter(PAGE_RELOAD_TIMEOUT, function() recoveryFailed("initial load did not finish") end)

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
      -- Before the page checks: a page reloading under the open panel must
      -- not turn a close into a second open.
      hide(true)
    elseif not pageReady then
      if pageFailed then
        -- The last reload failed: try again, and open when it works.
        pageFailed = false
        pendingOpen = true
        recoveryStreak = 0
        recoverPage()
      else
        pendingOpen = not pendingOpen
      end
    else
      show()
    end
  end)
  pending[timer] = true
end

---------------------------------------------------------------------------
-- Context recording (off unless RECORD_CONTEXT is true)
---------------------------------------------------------------------------

-- Held at module level: Hammerspoon stops a watcher nothing references.
local contextRecorder = nil
local contextAppWatcher = nil
local contextSleepWatcher = nil

local function startContextRecording()
  contextRecorder = reader.newRecorder({
    path = CONTEXT_LOG,
    now = hs.timer.secondsSinceEpoch,
    open = io.open,
    ensureDirectory = function(directory)
      if not hs.fs.attributes(directory) then hs.fs.mkdir(directory) end
    end,
    stat = hs.fs.attributes,
    frontApp = function()
      local front = hs.application.frontmostApplication()
      return front and front:bundleID()
    end,
  })
  contextRecorder.write("start")
  -- The app that is frontmost now, so the first Hyper events have an app.
  local front = hs.application.frontmostApplication()
  if front then contextRecorder.app(front:bundleID()) end

  contextAppWatcher = hs.application.watcher.new(function(_, event, app)
    if event == hs.application.watcher.activated and app then contextRecorder.app(app:bundleID()) end
  end)
  contextAppWatcher:start()

  local watcher = hs.caffeinate.watcher
  local kinds = {
    [watcher.screensDidLock] = "lock",
    [watcher.screensDidUnlock] = "unlock",
    [watcher.systemWillSleep] = "sleep",
    [watcher.systemDidWake] = "wake",
  }
  contextSleepWatcher = watcher.new(function(event)
    local kind = kinds[event]
    if kind then contextRecorder.write(kind) end
  end)
  contextSleepWatcher:start()

  -- Keep the watchers reachable from the module table. As locals that only
  -- this function referenced, they were garbage-collected after load, which
  -- stops a watcher: only the start line and the first app were recorded.
  M.contextRecording = { recorder = contextRecorder, app = contextAppWatcher, sleep = contextSleepWatcher }
end

create()
if RECORD_CONTEXT then startContextRecording() end

return M
