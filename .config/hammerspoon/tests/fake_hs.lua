-- A sandbox that runs hyperdash.lua against a fake `hs`, so the host logic can
-- be tested without a webview, watcher or timer in the live Hammerspoon.
-- Only hs.json and hs.fs.attributes are the real, side-effect-free modules.
--
--   local sandbox = dofile(".../fake_hs.lua")
--   local env = sandbox.new{ moduleDir = ".../hammerspoon", home = "/tmp/..." }
--   env.module.toggle(); env.advance(0)   -- run timers due now
--
-- Everything the module creates is recorded on `env` for assertions.

local sandbox = {}

function sandbox.new(options)
  local env = {
    frontmost = options.frontmost,
    clock = options.startTime or os.time(), -- real time, so file mtimes line up
    timers = {},
    watchers = {}, -- path watchers
    appWatchers = {},
    sleepWatchers = {},
    tasks = {},
    js = {}, -- every evaluateJavaScript call: { code, callback }
    webviews = {},
    shown = 0,
    hidden = 0,
    focused = 0,
    log = {},
    alerts = {},
    runningApps = {},
    settings = options.settings or {},
    installed = {},
    bundleInfo = {},
    htmlCalls = 0,
  }

  -- Garbage-collection tests: hold watchers weakly, so only the module keeps them alive.
  if options.weakWatchers then
    setmetatable(env.appWatchers, { __mode = "v" })
    setmetatable(env.sleepWatchers, { __mode = "v" })
  end

  ---------------------------------------------------------------- timers
  local function newTimer(delay, fn, repeating)
    local timer = { fn = fn, due = env.clock + delay, interval = repeating and delay or nil, running = true }
    function timer:stop() self.running = false; return self end
    function timer:start() self.running = true; return self end
    function timer:running_() return self.running end
    function timer:fire() self.fn(self) end
    env.timers[#env.timers + 1] = timer
    return timer
  end

  -- Run every running timer whose time has come, advancing the clock by `seconds`.
  function env.advance(seconds)
    local target = env.clock + seconds
    while true do
      local next
      for _, t in ipairs(env.timers) do
        if t.running and t.due <= target and (not next or t.due < next.due) then next = t end
      end
      if not next then break end
      env.clock = math.max(env.clock, next.due)
      if next.interval then next.due = next.due + next.interval else next.running = false end
      next.fn(next)
    end
    env.clock = target
  end

  -- Long waits behave like real time: the page answers between timer events,
  -- so a call is never left unanswered across minutes.
  local rawAdvance = env.advance
  function env.advance(seconds)
    if seconds <= 4 then return rawAdvance(seconds) end
    local target = env.clock + seconds
    for _ = 1, 1000000 do
      if env.clock >= target - 1e-9 then break end
      local nextDue = target
      for _, t in ipairs(env.timers) do
        if t.running and t.due < nextDue then nextDue = t.due end
      end
      rawAdvance(math.max(0, nextDue - env.clock))
      env.flush()
    end
    env.clock = target
  end

  function env.runningTimers()
    local n = 0
    for _, t in ipairs(env.timers) do if t.running then n = n + 1 end end
    return n
  end

  ---------------------------------------------------------------- webview
  local function newWebview()
    local wv = { visible = false, frameSet = nil }
    local chain = { "windowStyle", "transparent", "shadow", "allowTextEntry", "level", "behaviorAsLabels" }
    for _, name in ipairs(chain) do wv[name] = function(self) return self end end
    function wv:navigationCallback(fn) self.navigation = fn; return self end
    function wv:html(text) self.page = text; env.htmlCalls = env.htmlCalls + 1; return self end
    function wv:frame(f) self.frameSet = f; return self end
    function wv:isVisible() return self.visible end
    function wv:show() self.visible = true; env.shown = env.shown + 1; return self end
    function wv:hide() self.visible = false; env.hidden = env.hidden + 1; return self end
    function wv:evaluateJavaScript(code, callback)
      if env.pending() > 0 then env.overlap = (env.overlap or 0) + 1 end
      env.js[#env.js + 1] = { code = code, callback = callback }
    end
    env.webviews[#env.webviews + 1] = wv
    return wv
  end

  -- Answer the oldest unanswered evaluateJavaScript call with `result`.
  function env.answer(result, err)
    for _, call in ipairs(env.js) do
      if not call.answered then
        call.answered = true
        if call.callback then call.callback(result, err or { code = 0 }) end
        return call
      end
    end
  end
  function env.pending()
    local n = 0
    for _, call in ipairs(env.js) do if not call.answered then n = n + 1 end end
    return n
  end


  ---------------------------------------------------------------- fake page
  -- A model of window.hyperdash for the host tests. env.respond(code) returns
  -- what the page would answer; env.flush() answers every pending call.
  local page = { generation = nil, offset = 0, text = "", bindings = nil, insights = nil, health = nil,
                 calls = {}, mode = {}, ctx = { generation = nil, offset = 0, text = "" } }
  env.page = page
  -- The page API, read from index.html: window.hyperdash has exactly these
  -- methods, and setIcons is the only plain global function. Anything else
  -- is a ReferenceError or TypeError in the page, which evaluateJavaScript
  -- reports as WKErrorDomain code 4.
  local PAGE_METHODS = { reset = true, append = true, setBindings = true, setApps = true,
                         setInsights = true, setHealth = true, open = true, tick = true, setTheme = true }
  local JS_ERROR = { code = 4, domain = "WKErrorDomain" }
  -- Returns the page's answer and, for a script error, the error table.
  function env.respond(code)
    if code == "typeof window.hyperdash" then return "object" end
    local method, args = code:match("^window%.hyperdash%.(%w+)%((.*)%)$")
    if method and not PAGE_METHODS[method] then
      env.scriptErrors = (env.scriptErrors or 0) + 1
      return nil, JS_ERROR
    end
    if not method then
      method, args = code:match("^(setIcons)%((.*)%)$")
      if method then
        local decoded = hs.json.decode(args)
        page.calls[#page.calls + 1] = { method = method, args = { decoded }, bytes = #code, at = env.clock }
        page.icons = decoded
        return nil
      end
      env.scriptErrors = (env.scriptErrors or 0) + 1
      return nil, JS_ERROR
    end
    -- hs.json.decode drops nulls from arrays, which would shift arguments.
    local leadingNull = args:sub(1, 5) == "null,"
    if method == "setTheme" then
      page.theme = hs.json.decode("[" .. args .. "]")[1]
      page.themeCalls = (page.themeCalls or 0) + 1
      return { ok = true, height = 600 } -- not recorded in page.calls: the order tests ignore it
    end
    local list = hs.json.decode("[" .. (leadingNull and args:sub(6) or args) .. "]")
    if leadingNull then table.insert(list, 1, false) end
    local a = list[1]
    page.calls[#page.calls + 1] = { method = method, args = list, bytes = #code, at = env.clock }
    if (method == "reset" or method == "append") and type(a) == "table" and a.stream == "context" then
      local ctx = page.ctx
      if method == "reset" then
        if page.mode.rejectContext then return { ok = false, reason = "generation", offset = ctx.offset } end
        ctx.generation, ctx.offset, ctx.text = a.generation, a.offset, a.text
        return { ok = true, generation = a.generation, offset = a.offset, height = 600 }
      end
      if page.mode.rejectContext then return { ok = false, reason = page.mode.rejectContext, offset = ctx.offset } end
      if a.generation ~= ctx.generation then return { ok = false, reason = "generation", offset = ctx.offset } end
      if a.from < ctx.offset then return { ok = false, reason = "duplicate", offset = ctx.offset } end
      if a.from > ctx.offset then return { ok = false, reason = "gap", offset = ctx.offset } end
      ctx.text = ctx.text .. a.text
      ctx.offset = a.to
      return { ok = true, offset = a.to, height = 600 }
    end
    if method == "reset" then
      if page.mode.rejectReset then return { ok = false, reason = "generation", offset = page.offset } end
      page.generation, page.offset, page.text = a.generation, a.offset, a.text
      page.bindings, page.insights, page.health = a.bindings, a.insights, a.health
      return { ok = true, generation = a.generation, offset = a.offset, height = 600 }
    elseif method == "append" then
      if page.mode.rejectAppendOnce then
        local reason = page.mode.rejectAppendOnce
        page.mode.rejectAppendOnce = nil
        return { ok = false, reason = reason, offset = page.offset }
      end
      if page.mode.rejectAppend then return { ok = false, reason = page.mode.rejectAppend, offset = page.offset } end
      if a.generation ~= page.generation then return { ok = false, reason = "generation", offset = page.offset } end
      if a.from < page.offset then return { ok = false, reason = "duplicate", offset = page.offset } end
      if a.from > page.offset then return { ok = false, reason = "gap", offset = page.offset } end
      page.text = page.text .. a.text
      page.offset = a.to
      return { ok = true, offset = a.to, height = 600 }
    elseif method == "setApps" then
      page.apps = a
      return { ok = true, height = 600 }
    elseif method == "setBindings" then
      page.bindings, page.health = list[1], list[2]
      return { ok = true, height = 600 }
    elseif method == "setInsights" then
      page.insights, page.health = list[1] or nil, list[2]
      return { ok = true, height = 600 }
    elseif method == "setHealth" then
      page.health = a
      return { ok = true, height = 600 }
    elseif method == "tick" then
      page.ticks = (page.ticks or 0) + 1
      return { ok = true, height = 600 }
    elseif method == "open" then
      page.opens = (page.opens or 0) + 1
      return { height = page.openHeight or 600 }
    end
    return nil -- setIcons and anything else: no answer value
  end
  -- The page process dies: every call from now on fails with code 5.
  function env.killPage() page.mode.dead = true end
  -- html() started a fresh process: the page is empty and answers again.
  function env.finishReload()
    page.mode.dead = false
    page.generation, page.offset, page.text = nil, 0, ""
    page.bindings, page.insights, page.health = nil, nil, nil
    page.ctx = { generation = nil, offset = 0, text = "" }
    page.apps, page.icons = nil, nil
    page.theme = nil
    env.webview.navigation("didFinishNavigation")
  end
  -- Answer pending calls until none are left. Calls the page is told to
  -- ignore (mode.silent) stay pending, so tests can exercise the watchdog.
  function env.flush(limit)
    for _ = 1, limit or 200 do
      -- Each turn of the run loop first runs timers that are due now, as the
      -- real one does; the page answers after that.
      env.advance(0)
      local call
      for _, c in ipairs(env.js) do if not c.answered then call = c; break end end
      if not call or page.mode.silent then return end
      call.answered = true
      if page.mode.dead then
        -- A terminated WebContent process: no result, WKErrorDomain code 5.
        if call.callback then call.callback(nil, { code = 5, domain = "WKErrorDomain" }) end
      else
        local result, err = env.respond(call.code)
        if call.callback then call.callback(result, err or { code = 0 }) end
      end
    end
  end

  ---------------------------------------------------------------- hs
  local fakeHs = {
    json = hs.json,
    fs = {
      attributes = hs.fs.attributes,
      pathToAbsolute = hs.fs.pathToAbsolute,
      mkdir = hs.fs.mkdir,
      -- Installed bundles come from env.installed[folder], never from the disk.
      dir = function(folder)
        local names = env.installed[folder]
        if not names then error("no such folder " .. folder) end
        local i = 0
        return function() i = i + 1; return names[i] end, {}
      end,
    },
    timer = {
      doAfter = function(delay, fn) return newTimer(delay, fn, false) end,
      doEvery = function(interval, fn) return newTimer(interval, fn, true) end,
      secondsSinceEpoch = function() return env.clock end,
    },
    webview = {
      new = function() return newWebview() end,
      usercontent = { new = function() return { setCallback = function(self, fn) self.callback = fn; env.controller = self end } end },
    },
    settings = {
      get = function(key) return env.settings[key] end,
      set = function(key, value) env.settings[key] = value end,
    },
    alert = { show = function(message) env.alerts[#env.alerts + 1] = message end },
    drawing = { windowLevels = { floating = 3 } },
    application = {
      runningApplications = function() return env.runningApps end,
      frontmostApplication = function() return env.frontmost end,
      infoForBundlePath = function(path) return env.bundleInfo[path] end,
      watcher = {
        activated = 5,
        deactivated = 6,
        new = function(fn)
          local w = { fn = fn, started = false }
          function w:start() self.started = true; return self end
          function w:stop() self.started = false; return self end
          env.appWatchers[#env.appWatchers + 1] = w
          return w
        end,
      },
    },
    window = { focusedWindow = function() return nil end },
    screen = { mainScreen = function() return { frame = function() return { x = 0, y = 0, w = 1440, h = 900 } end } end },
    focus = function() env.focused = env.focused + 1 end,
    image = { iconForFile = function() return { setSize = function(self) return self end, encodeAsURLString = function() return "data:image/png;base64,AAAA" end } end },
    task = {
      new = function(path, callback, args)
        local task = { path = path, callback = callback, args = args, running = false }
        function task:start()
          if env.taskStartFails then return nil end
          self.running = true
          env.tasks[#env.tasks + 1] = self
          return self
        end
        function task:isRunning() return self.running end
        -- Like hs.task: the exit callback runs once the process has gone.
        function task:terminate()
          if not self.running then return self end
          self.terminated = true
          self:finish(15, "", "")
          return self
        end
        function task:finish(exitCode, stdout, stderr)
          self.running = false
          self.callback(exitCode, stdout or "", stderr or "")
        end
        return task
      end,
    },
    pathwatcher = {
      new = function(path, fn)
        local w = { path = path, fn = fn, started = false }
        function w:start() self.started = true; return self end
        function w:stop() self.started = false; return self end
        env.watchers[#env.watchers + 1] = w
        return w
      end,
    },
    caffeinate = {
      watcher = {
        systemDidWake = 0, screensDidWake = 2, systemWillSleep = 1, screensDidLock = 10, screensDidUnlock = 11,
        new = function(fn)
          local w = { fn = fn, started = false }
          function w:start() self.started = true; return self end
          function w:stop() self.started = false; return self end
          env.sleepWatchers[#env.sleepWatchers + 1] = w
          return w
        end,
      },
    },
  }

  ---------------------------------------------------------------- environment
  local sandboxOs = setmetatable({
    getenv = function(name) if name == "HOME" then return options.home end return os.getenv(name) end,
    time = function(t) if t then return os.time(t) end return math.floor(env.clock) end,
    date = os.date,
  }, { __index = os })

  local globals = setmetatable({
    hs = fakeHs,
    os = sandboxOs,
    require = function(name)
      if name == "hyperdash_core" then return dofile(options.moduleDir .. "/hyperdash_core.lua") end
      return require(name)
    end,
    print = function(...)
      local parts = {}
      for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
      env.log[#env.log + 1] = table.concat(parts, " ")
    end,
  }, { __index = _G })

  local path = options.moduleDir .. "/" .. (options.moduleFile or "hyperdash.lua")
  local source = assert(io.open(path, "rb")):read("a")
  -- Tests choose the recording setting; the file's own value (the user's
  -- switch) must not change their results.
  local edited, count = source:gsub("local RECORD_CONTEXT = %a+", "local RECORD_CONTEXT = " .. (options.recordContext and "true" or "false"), 1)
  assert(count == 1, "RECORD_CONTEXT line not found")
  source = edited
  local chunk, err = load(source, "@" .. path, "t", globals)
  assert(chunk, err)
  env.module = chunk()
  env.webview = env.webviews[1]
  return env
end

return sandbox
