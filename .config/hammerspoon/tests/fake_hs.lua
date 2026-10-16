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
  }

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
    function wv:html(text) self.page = text; return self end
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
  function env.answer(result)
    for _, call in ipairs(env.js) do
      if not call.answered then
        call.answered = true
        if call.callback then call.callback(result, {}) end
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
                 calls = {}, mode = {} }
  env.page = page
  function env.respond(code)
    local method, args = code:match("^window%.hyperdash%.(%w+)%((.*)%)$")
    if not method then
      method, args = code:match("^(setIcons)%((.*)%)$")
      if method then page.calls[#page.calls + 1] = { method = method, args = {}, bytes = #code } end
      return nil
    end
    -- hs.json.decode drops nulls from arrays, which would shift arguments.
    local leadingNull = args:sub(1, 5) == "null,"
    local list = hs.json.decode("[" .. (leadingNull and args:sub(6) or args) .. "]")
    if leadingNull then table.insert(list, 1, false) end
    local a = list[1]
    page.calls[#page.calls + 1] = { method = method, args = list, bytes = #code }
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
  -- Answer pending calls until none are left. Calls the page is told to
  -- ignore (mode.silent) stay pending, so tests can exercise the watchdog.
  function env.flush(limit)
    for _ = 1, limit or 200 do
      local call
      for _, c in ipairs(env.js) do if not c.answered then call = c; break end end
      if not call or page.mode.silent then return end
      call.answered = true
      local result = env.respond(call.code)
      if call.callback then call.callback(result, {}) end
    end
  end

  ---------------------------------------------------------------- hs
  local fakeHs = {
    json = hs.json,
    fs = { attributes = hs.fs.attributes },
    timer = {
      doAfter = function(delay, fn) return newTimer(delay, fn, false) end,
      doEvery = function(interval, fn) return newTimer(interval, fn, true) end,
      secondsSinceEpoch = function() return env.clock end,
    },
    webview = {
      new = function() return newWebview() end,
      usercontent = { new = function() return { setCallback = function(self, fn) self.callback = fn; env.controller = self end } end },
    },
    drawing = { windowLevels = { floating = 3 } },
    application = {
      watcher = {
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
        systemDidWake = 0, screensDidWake = 2, systemWillSleep = 1,
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
    time = function(t) if t then return os.time(t) end return env.clock end,
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

  local chunk, err = loadfile(options.moduleDir .. "/hyperdash.lua", "t", globals)
  assert(chunk, err)
  env.module = chunk()
  env.webview = env.webviews[1]
  return env
end

return sandbox
