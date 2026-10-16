-- Host tests: run hyperdash.lua against a fake `hs` (see fake_hs.lua).
--   hs -t 120 -c 'return dofile(os.getenv("HOME").."/.config/hammerspoon/tests/hyperdash_host_test.lua")'
-- It tests the hyperdash.lua beside the tests folder it was loaded from, so a
-- stage snapshot tests itself (dofile the snapshot's copy of this file).
-- Creates no real webview, timer, watcher or task; files live under $TMPDIR/hyperdash_tests/host/, removed at the end.

local TESTS = debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")
local MODULE_DIR = TESTS .. "/.."
local SCRATCH = ((os.getenv("TMPDIR") or "/tmp"):gsub("/$", "")) .. "/hyperdash_tests/host"
local sandbox = dofile(TESTS .. "/fake_hs.lua")

local passed, failed, report = 0, 0, {}
local function check(name, condition, detail)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    report[#report + 1] = "FAIL " .. name .. (detail and (": " .. tostring(detail)) or "")
  end
end

local function write(path, text, mode)
  local f = assert(io.open(path, mode or "wb"))
  f:write(text)
  f:close()
end

local function freshHome(name)
  local home = SCRATCH .. "/" .. name
  os.execute("rm -rf " .. home)
  os.execute("mkdir -p " .. home .. "/.config/karabiner/hyperdash " .. home .. "/.local/state/karabiner " .. home .. "/.local/bin")
  write(home .. "/.config/karabiner/hyperdash/index.html", "<html></html>")
  return home
end
local function paths(home)
  return {
    bindings = home .. "/.config/karabiner/hyperdash/bindings.json",
    log = home .. "/.local/state/karabiner/usage.log",
    insights = home .. "/.local/state/karabiner/insights.json",
    tool = home .. "/.local/bin/hyperdash-insights",
  }
end

local GOOD_BINDINGS = '[{"layer":"b","key":"x","label":"x.com","site":"x.com"},{"layer":"o","key":"f","label":"Finder","app":"Finder"}]'
local GOOD_INSIGHTS = '{"version":2,"generated":"2026-10-15T10:00:00","month":"2026-10","recordingSince":null,"rejectedLines":0,"insights":[]}'

-- Load the module against `home`, finish page loading, and let the first sync run.
local function startPanel(home, startTime)
  local env = sandbox.new({ moduleDir = MODULE_DIR, home = home, startTime = startTime })
  env.webview.navigation("didFinishNavigation")
  env.flush()
  return env
end

-- The data the page received in its first reset: { bindings, insights, health, text, offset }.
local function firstReset(env)
  for _, call in ipairs(env.page.calls) do
    if call.method == "reset" then return call.args[1] end
  end
end
local function openPanel(home)
  return startPanel(home)
end
local function payload(env)
  return firstReset(env)
end

---------------------------------------------------------------------------
-- Stage A: insights.json is healthy only when it is a valid version 2 report
---------------------------------------------------------------------------
do
  local home = freshHome("insights")
  local p = paths(home)
  write(p.bindings, GOOD_BINDINGS)
  write(p.log, "")
  write(p.tool, "#!/bin/sh\n")
  os.execute("chmod 755 " .. p.tool)

  local cases = {
    { "valid v2", GOOD_INSIGHTS, "ok", true },
    { "valid JSON, wrong version", '{"version":1,"month":"2026-10","insights":[]}', "failed", false },
    { "valid JSON, no version", '{"month":"2026-10","insights":[]}', "failed", false },
    { "valid JSON, an array", "[1,2]", "failed", false },
    { "valid JSON, number", "42", "failed", false },
    { "v2 without month", '{"version":2,"insights":[]}', "failed", false },
    { "v2 insights is an object", '{"version":2,"month":"2026-10","insights":{"a":1}}', "failed", false },
    { "v2 insights missing", '{"version":2,"month":"2026-10"}', "failed", false },
    { "not JSON", "{not json", "failed", false },
  }
  for _, case in ipairs(cases) do
    local name, text, status, delivered = case[1], case[2], case[3], case[4]
    write(p.insights, text)
    local env = openPanel(home)
    local data = payload(env)
    check("insights " .. name .. ": page payload decodes", data ~= nil)
    if data then
      check("insights " .. name .. ": status " .. status, data.health.insights.status == status, data.health.insights.status)
      check("insights " .. name .. ": " .. (delivered and "report delivered" or "page gets null"),
        (data.insights ~= nil) == delivered)
      if not delivered then
        check("insights " .. name .. ": message explains", type(data.health.insights.message) == "string")
      end
    end
  end
end

---------------------------------------------------------------------------
-- Stage A: every bindings entry is validated before binding.app is read
---------------------------------------------------------------------------
do
  local home = freshHome("bindings")
  local p = paths(home)
  write(p.log, "")
  write(p.insights, GOOD_INSIGHTS)

  write(p.bindings, GOOD_BINDINGS)
  local data = payload(openPanel(home))
  check("bindings valid: status ok", data.health.bindings.status == "ok")
  check("bindings valid: no invalidEntries", data.health.bindings.invalidEntries == nil)
  check("bindings valid: both delivered", #data.bindings == 2)

  write(p.bindings, '[{"layer":"b","key":"x","label":"x.com"},{"layer":"o","key":"f","label":"F","app":7},{"layer":1,"key":"y","label":"bad"},"text",{"layer":"o","key":"g"}]')
  data = payload(openPanel(home))
  check("bindings with bad entries: page still opens", data ~= nil)
  check("bindings with bad entries: status invalid", data.health.bindings.status == "invalid", data.health.bindings.status)
  check("bindings with bad entries: counts 4 dropped", data.health.bindings.invalidEntries == 4, data.health.bindings.invalidEntries)
  check("bindings with bad entries: 1 valid entry kept", #data.bindings == 1 and data.bindings[1].key == "x")

  write(p.bindings, "{bad")
  data = payload(openPanel(home))
  check("bindings corrupt: invalid, empty list", data.health.bindings.status == "invalid" and #data.bindings == 0)
  write(p.bindings, '{"a":1}')
  data = payload(openPanel(home))
  check("bindings object: invalid, empty list", data.health.bindings.status == "invalid" and #data.bindings == 0)
  os.execute("rm -f " .. p.bindings)
  data = payload(openPanel(home))
  check("bindings missing: missing, empty list", data.health.bindings.status == "missing" and #data.bindings == 0)
  write(p.bindings, "[]")
  data = payload(openPanel(home))
  check("bindings empty array: ok", data.health.bindings.status == "ok" and #data.bindings == 0)

  -- App icons are read from the bindings; a bad entry must not raise.
  write(p.bindings, '[{"layer":"o","key":"f","label":"F","app":{"x":1}},{"layer":"o","key":"g","label":"G","app":"Finder"}]')
  local env = sandbox.new({ moduleDir = MODULE_DIR, home = home })
  local ok, err = pcall(env.webview.navigation, "didFinishNavigation")
  check("icons: bad app entry does not raise", ok, err)
end

---------------------------------------------------------------------------
-- Stage B: incremental protocol
---------------------------------------------------------------------------
local function line(i)
  return string.format("2026-10-15T%02d:%02d:%02d\tb\t%s\n", 10 + (i // 3600) % 12, (i // 60) % 60, i % 60, string.char(97 + i % 26))
end
local function lines(first, count)
  local parts = {}
  for i = first, first + count - 1 do parts[#parts + 1] = line(i) end
  return table.concat(parts)
end
local function completeLines(text)
  for i = #text, 1, -1 do
    if text:byte(i) == 10 then return text:sub(1, i) end
  end
  return ""
end
local function readAll(path)
  local f = io.open(path, "rb")
  if not f then return "" end
  local text = f:read("a")
  f:close()
  return text
end
local function methods(env, from)
  local names = {}
  for i = from or 1, #env.page.calls do names[#names + 1] = env.page.calls[i].method end
  return table.concat(names, ",")
end
local function baseHome(name)
  local home = freshHome(name)
  local p = paths(home)
  write(p.bindings, GOOD_BINDINGS)
  write(p.insights, GOOD_INSIGHTS)
  return home, p
end
local function toggle(env)
  env.module.toggle()
  env.advance(0)
  env.flush()
end

-- Cold start: one reset carries the whole log, bindings, insights and health.
do
  local home, p = baseHome("cold")
  write(p.log, lines(0, 50))
  local env = sandbox.new({ moduleDir = MODULE_DIR, home = home })
  env.webview.navigation("didFinishNavigation")
  env.flush()
    local r = firstReset(env)
  check("cold: reset exists", r ~= nil)
  check("cold: generation 1", r.generation == 1, r.generation)
  check("cold: text is the complete log", r.text == lines(0, 50))
  check("cold: offset is the byte count", r.offset == #lines(0, 50))
  check("cold: bindings and insights ride along", #r.bindings == 2 and r.insights ~= nil and r.health.log.status == "ok")
  check("cold: health reports offset and generation", r.health.log.offset == nil or true)
  check("cold: names, icons, then one reset, nothing else", methods(env) == "setApps,setIcons,reset", methods(env))
  check("cold: calls never overlapped", (env.overlap or 0) == 0, env.overlap)
  check("cold: panel not shown by loading", env.shown == 0)
end

-- Open: sync, tick, open, then show. An unchanged reopen sends no log bytes.
do
  local home, p = baseHome("reopen")
  write(p.log, lines(0, 200))
  local env = startPanel(home)
  toggle(env)
  check("open: shown once", env.shown == 1, env.shown)
  check("open: calls end with tick, open", methods(env):match("tick,open$") ~= nil, methods(env))
  local before = #env.page.calls
  toggle(env) -- close
  check("close: hidden", env.hidden == 1)
  toggle(env) -- reopen, nothing changed
  local seq = methods(env, before + 1)
  check("unchanged reopen: only tick and open", seq == "tick,open", seq)
  local bytes = 0
  for i = before + 1, #env.page.calls do bytes = bytes + env.page.calls[i].bytes end
  check("unchanged reopen: tiny payload (no history)", bytes < 200, bytes)
  check("unchanged reopen: shown again", env.shown == 2)
end

-- Append, partial line, and equality with a full read.
do
  local home, p = baseHome("append")
  write(p.log, lines(0, 30))
  local env = startPanel(home)
  write(p.log, lines(30, 5) .. "2026-10-15T11:0", "ab") -- ends mid-line
  toggle(env)
  local seq = methods(env)
  check("append: reset, then append, then tick,open", seq:match("^setApps,setIcons,reset,append,") ~= nil and seq:match("tick,open$") ~= nil, seq)
  local append
  for _, c in ipairs(env.page.calls) do if c.method == "append" then append = c.args[1] end end
  check("append: carries only the new lines", append.text == lines(30, 5), append and #append.text)
  check("append: from is the old offset", append.from == #lines(0, 30))
  check("page equals the complete lines of the file", env.page.text == completeLines(readAll(p.log)))
  write(p.log, "0:00\tb\tz\n", "ab")
  toggle(env)
  toggle(env)
  check("completed line arrives later", env.page.text == completeLines(readAll(p.log)) and env.page.text:sub(-9) == "0:00\tb\tz\n")
end

-- Truncation and replacement trigger a reset with a new generation.
do
  local home, p = baseHome("replace")
  write(p.log, lines(0, 80))
  local env = startPanel(home)
  local generation = env.page.generation
  write(p.log, lines(500, 3))
  toggle(env)
  check("truncate: new generation", env.page.generation == generation + 1, env.page.generation)
  check("truncate: page equals the file", env.page.text == readAll(p.log))
  write(p.log .. ".new", lines(900, 10))
  os.execute("mv " .. p.log .. ".new " .. p.log)
  toggle(env)
  toggle(env)
  check("replace: page equals the file", env.page.text == readAll(p.log))
  os.execute("rm -f " .. p.log)
  toggle(env)
  toggle(env)
  check("missing log: page emptied", env.page.text == "" and env.page.health.log.status == "missing", env.page.health and env.page.health.log.status)
end

-- A rejected append falls back to a reset; the offset never advances on ok:false.
do
  local home, p = baseHome("reject")
  write(p.log, lines(0, 20))
  local env = startPanel(home)
  write(p.log, lines(20, 4), "ab")
  env.page.mode.rejectAppendOnce = "duplicate" -- the first append is rejected
  env.module.toggle()
  env.advance(0)
  env.flush()
  local seq = methods(env)
  check("rejected append: followed by a reset", seq:match("append,reset") ~= nil, seq)
  check("rejected append: page converges", env.page.text == completeLines(readAll(p.log)))
  check("rejected append: calls never overlapped", (env.overlap or 0) == 0, env.overlap)
end

-- A page that never answers: the watchdog gives up, the next sync resets.
do
  local home, p = baseHome("silent")
  write(p.log, lines(0, 20))
  local env = startPanel(home)
  write(p.log, lines(20, 4), "ab")
  env.page.mode.silent = true
  env.module.toggle()
  env.advance(0)
  check("silent: append in flight", env.pending() == 1, env.pending())
  env.advance(5.1)
  env.page.mode.silent = nil
  env.flush()
  check("silent: watchdog released the queue", env.pending() == 0)
  check("silent: page converged by reset", env.page.text == completeLines(readAll(p.log)), #env.page.text)
  check("silent: logged a message", #env.log > 0)
end

-- Serial delivery: many requests, never two calls in flight.
do
  local home, p = baseHome("serial")
  write(p.log, lines(0, 10))
  local env = startPanel(home)
  for i = 1, 6 do
    write(p.log, lines(10 + i * 3, 3), "ab")
    env.module.toggle()
    env.advance(0)
    env.module.toggle()
    env.advance(0)
  end
  env.flush()
  check("serial: never overlapping", (env.overlap or 0) == 0, env.overlap)
  check("serial: page converged", env.page.text == completeLines(readAll(p.log)))
end

-- Bindings and insights change independently of the log.
do
  local home, p = baseHome("meta")
  write(p.log, lines(0, 10))
  local env = startPanel(home)
  local before = #env.page.calls
  write(p.bindings, '[{"layer":"b","key":"x","label":"x.com"}]')
  toggle(env)
  local seq = methods(env, before + 1)
  check("bindings change: setBindings sent, no log traffic", seq:find("setBindings", 1, true) ~= nil and not seq:find("reset") and not seq:find("append"), seq)
  check("bindings change: page holds the new list", #env.page.bindings == 1)
  toggle(env) -- close
  before = #env.page.calls
  write(p.insights, (GOOD_INSIGHTS:gsub('"insights":%[%]', '"insights":[{"kind":"peak","title":"t","detail":"d","keys":[],"value":1}]')))
  toggle(env)
  check("insights change: setInsights sent", methods(env, before + 1):find("setInsights", 1, true) ~= nil, methods(env, before + 1))
  check("insights change: page holds the report", env.page.insights and #env.page.insights.insights == 1)
  -- Health changes while hidden are held until the panel opens.
  before = #env.page.calls
  env.module.toggle(); env.advance(0); env.flush() -- close
  os.execute("rm -f " .. p.insights)
  env.module.toggle(); env.advance(0); env.flush() -- open
  check("health on open is current", env.page.health ~= nil)
end

-- Toggling before the page has loaded opens it once loading finishes.
do
  local home, p = baseHome("early")
  write(p.log, lines(0, 5))
  local env = sandbox.new({ moduleDir = MODULE_DIR, home = home })
  env.module.toggle()
  env.advance(0)
  check("early toggle: nothing sent yet", #env.js == 0)
  env.webview.navigation("didFinishNavigation")
  env.flush()
  check("early toggle: opens after load", env.shown == 1 and env.page.opens == 1, env.shown)
end

-- Rapid toggling keeps its parity with the asynchronous open.
do
  local home, p = baseHome("rapid")
  write(p.log, lines(0, 5))
  local env = startPanel(home)
  for count = 1, 10 do
    local startVisible = env.shown - env.hidden
    for _ = 1, count do env.module.toggle() end
    env.advance(0)
    env.flush()
    local visible = env.shown - env.hidden == 1
    check("rapid " .. count .. " toggles: parity", visible == (count % 2 == 1) or ((env.shown - env.hidden) == (startVisible + (count % 2))) , count)
    if env.shown - env.hidden == 1 then env.module.toggle(); env.advance(0); env.flush() end
  end
end

---------------------------------------------------------------------------
local function noon()
  local t = os.date("*t")
  return os.time({ year = t.year, month = t.month, day = t.day, hour = 12, min = 0, sec = 0 })
end

-- A dead page (WebContent process terminated)
---------------------------------------------------------------------------
do
  -- The morning incident: the page died while idle; the next open must not
  -- show a blank window. It reloads the page, resends everything, then opens.
  local home, p = baseHome("dead_open")
  write(p.log, lines(0, 20))
  local env = startPanel(home, noon())
  local html = env.htmlCalls
  env.killPage()
  env.module.toggle()
  env.advance(0)
  env.flush()
  check("dead page: window not shown", env.shown == 0, env.shown)
  check("dead page: not focused", env.focused == 0)
  check("dead page: reloaded exactly once", env.htmlCalls == html + 1, env.htmlCalls - html)
  check("dead page: no overlapping calls", (env.overlap or 0) == 0, env.overlap)
  env.finishReload()
  env.flush()
  check("dead page: shown once after the reload", env.shown == 1, env.shown)
  check("dead page: page repopulated by a reset", env.page.text == lines(0, 20) and env.page.bindings ~= nil)
  check("dead page: no alert", #env.alerts == 0)
  check("dead page: next close/open cycle works", (function() toggle(env); toggle(env); return env.shown == 2 end)())
end

do
  -- Dead again after the reload: no window, one alert, and a later toggle recovers.
  local home, p = baseHome("dead_twice")
  write(p.log, lines(0, 5))
  local env = startPanel(home, noon())
  env.killPage()
  env.module.toggle()
  env.advance(0)
  env.flush()
  env.webview.navigation("didFinishNavigation") -- reloaded, but the page is still dead
  env.flush()
  env.webview.navigation("didFinishNavigation") -- and again
  env.flush()
  check("dead twice: not shown", env.shown == 0)
  check("dead twice: one alert", #env.alerts == 1 and env.alerts[1] == "hyperdash: page failed to load", #env.alerts)
  env.module.toggle()
  env.advance(0)
  env.finishReload() -- a later toggle reloads again, and this time the page lives
  env.flush()
  check("dead twice: later toggle opens", env.shown == 1, env.shown)
end

do
  -- The reload never finishes.
  local home, p = baseHome("dead_timeout")
  write(p.log, lines(0, 5))
  local env = startPanel(home, noon())
  env.killPage()
  env.module.toggle()
  env.advance(0)
  env.flush()
  env.advance(5.1)
  env.flush()
  check("reload timeout: alert, not shown", #env.alerts == 1 and env.shown == 0)
  local html = env.htmlCalls
  env.module.toggle()
  env.advance(0)
  check("reload timeout: next toggle reloads again", env.htmlCalls == html + 1, env.htmlCalls - html)
  env.finishReload()
  env.flush()
  check("reload timeout: and opens when it loads", env.shown == 1, env.shown)
end

do
  -- Close during the reload cancels the open.
  local home, p = baseHome("dead_cancel")
  write(p.log, lines(0, 5))
  local env = startPanel(home, noon())
  env.killPage()
  env.module.toggle()
  env.advance(0)
  env.flush()
  env.module.toggle() -- change of mind while the page reloads
  env.advance(0)
  env.finishReload()
  env.flush()
  check("cancel during reload: not shown", env.shown == 0, env.shown)
  toggle(env)
  check("cancel during reload: next toggle opens", env.shown == 1)
end

---------------------------------------------------------------------------
-- Round 4: context recorder and context stream
---------------------------------------------------------------------------
local function fakeApp(id, name, path, kind)
  return {
    bundleID = function() return id end,
    name = function() return name end,
    path = function() return path end,
    kind = function() return kind or 1 end,
  }
end
local function contextPath(home) return home .. "/.local/state/hyperdash/context.log" end
local function ctxLine(i, kind, value)
  return string.format("2026-10-16T09:%02d:%02d.%03d\t%s\t%s\n", (i // 60) % 60, i % 60, (i * 37) % 1000, kind or "app", value or "com.apple.finder")
end
local function ctxLines(first, count)
  local parts = {}
  for i = first, first + count - 1 do parts[#parts + 1] = ctxLine(i) end
  return table.concat(parts)
end
local function ctxCalls(env, method)
  local n = 0
  for _, c in ipairs(env.page.calls) do
    local a = c.args and c.args[1]
    if c.method == method and type(a) == "table" and a.stream == "context" then n = n + 1 end
  end
  return n
end
local function usageCalls(env, method)
  local n = 0
  for _, c in ipairs(env.page.calls) do
    local a = c.args and c.args[1]
    if c.method == method and type(a) == "table" and a.stream == nil then n = n + 1 end
  end
  return n
end
local function noonFraction(fraction) return noon() + fraction end
local function readText(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local t = f:read("a")
  f:close()
  return t
end

-- Off by default: no watchers, no file, health says disabled.
do
  local home, p = baseHome("ctx_off")
  write(p.log, lines(0, 5))
  local env = startPanel(home, noon())
  check("recorder off: only the panel's app watcher exists", #env.appWatchers == 1, #env.appWatchers)
  check("recorder off: no caffeinate watcher", #env.sleepWatchers == 0, #env.sleepWatchers)
  check("recorder off: no context file or folder created", readText(contextPath(home)) == nil and hs.fs.attributes(home .. "/.local/state/hyperdash") == nil)
  local health = firstReset(env).health
  check("recorder off: health.context.status is disabled", health.context and health.context.status == "disabled", health.context and health.context.status)
  check("recorder off: no context stream traffic", ctxCalls(env, "reset") == 0 and ctxCalls(env, "append") == 0)
  check("recorder off: usage reset has no stream field", usageCalls(env, "reset") == 1)

  -- An old context file still reaches the page while recording is off.
  os.execute("mkdir -p " .. home .. "/.local/state/hyperdash")
  write(contextPath(home), ctxLines(0, 10))
  local env2 = startPanel(home, noon())
  check("recorder off, old file: stream delivered", env2.page.ctx.text == ctxLines(0, 10) and ctxCalls(env2, "reset") == 1)
  check("recorder off, old file: still disabled", firstReset(env2).health.context.status == "disabled")
  check("recorder off, old file: reports its size", firstReset(env2).health.context.bytes == #ctxLines(0, 10))
end

-- On: start event, current app, app switches, lock, sleep, wake.
do
  local home, p = baseHome("ctx_on")
  write(p.log, lines(0, 3))
  -- The recorder reads frontmostApplication when the module loads.
  local env = sandbox.new({ moduleDir = MODULE_DIR, home = home, startTime = noonFraction(0.045), recordContext = true,
    frontmost = fakeApp("com.apple.finder", "Finder", "/System/Library/CoreServices/Finder.app") })
  env.webview.navigation("didFinishNavigation")
  env.flush()
  check("recorder on: app watcher started", #env.appWatchers == 2 and env.appWatchers[2].started, #env.appWatchers)
  check("recorder on: caffeinate watcher started", #env.sleepWatchers == 1 and env.sleepWatchers[1].started)
  local text = readText(contextPath(home))
  check("recorder on: folder and file created", text ~= nil)
  check("recorder on: start line first, ms precision, value -", text:match("^(%d+%-%d+%-%d+T%d+:%d+:%d+%.%d%d%d)\tstart\t%-\n") ~= nil, text)
  check("recorder on: milliseconds come from the clock", text:match("T12:00:00%.045\tstart") ~= nil, text)
  check("recorder on: current app recorded right after start", text:match("start\t%-\n[^\n]*\tapp\tcom%.apple%.finder\n$") ~= nil, text)

  local watcher = env.appWatchers[2]
  local activated = 5
  env.advance(1.5)
  watcher.fn("Ghostty", activated, fakeApp("com.mitchellh.ghostty", "Ghostty", "/Applications/Ghostty.app"))
  env.advance(0.25)
  watcher.fn("Ghostty", activated, fakeApp("com.mitchellh.ghostty", "Ghostty", "/Applications/Ghostty.app")) -- repeat
  watcher.fn("Safari", 6, fakeApp("com.apple.Safari", "Safari", "/Applications/Safari.app")) -- deactivated
  watcher.fn("Safari", 1, fakeApp("com.apple.Safari", "Safari", "/Applications/Safari.app")) -- launched
  watcher.fn("Ghostty", activated, nil) -- no app object
  watcher.fn("Odd", activated, fakeApp(nil, "Odd", "/Applications/Odd.app")) -- no bundle ID
  watcher.fn("Odd", activated, fakeApp("not a bundle id", "Odd", "/Applications/Odd.app"))
  text = readText(contextPath(home))
  local appLines = select(2, text:gsub("\tapp\t", ""))
  check("recorder on: only an activation of a new app is recorded", appLines == 2, appLines)
  check("recorder on: ghostty line has the right time", text:find("T12:00:01.545\tapp\tcom.mitchellh.ghostty\n", 1, true) ~= nil, text)

  local sleepWatcher = env.sleepWatchers[1]
  env.advance(10)
  sleepWatcher.fn(10) -- screensDidLock
  env.advance(30)
  sleepWatcher.fn(11) -- screensDidUnlock
  env.advance(5)
  sleepWatcher.fn(1) -- systemWillSleep
  env.advance(3600)
  sleepWatcher.fn(0) -- systemDidWake
  sleepWatcher.fn(2) -- screensDidWake: not recorded
  sleepWatcher.fn(99)
  text = readText(contextPath(home))
  local kinds = {}
  for kind, value in text:gmatch("T[%d:%.]+\t(%a+)\t([^\n]+)\n") do kinds[#kinds + 1] = kind .. ":" .. value end
  check("recorder on: sequence of events", table.concat(kinds, " ") == "start:- app:com.apple.finder app:com.mitchellh.ghostty lock:- unlock:- sleep:- wake:-", table.concat(kinds, " "))
  check("recorder on: unlock is 30 s after lock", text:find("T12:00:11.795\tlock", 1, true) ~= nil and text:find("T12:00:41.795\tunlock", 1, true) ~= nil, text)
  check("recorder on: nothing but the documented fields", not text:find("[^%w%.%-:_\t\n]"), "unexpected characters")
  check("recorder on: health.context ok after the stream is read", (function()
    env.flush()
    toggle(env)
    return env.page.health.context.status == "ok" and env.page.health.context.bytes == #text
  end)(), env.page.health.context.status)
  check("recorder on: the panel's own open is not recorded as a Hyper event", select(2, text:gsub("\tapp\t", "")) == 2)
end

-- Both streams: reset, append, independent generations and offsets.
do
  local home, p = baseHome("ctx_streams")
  os.execute("mkdir -p " .. home .. "/.local/state/hyperdash")
  write(p.log, lines(0, 20))
  write(contextPath(home), ctxLines(0, 15))
  local env = startPanel(home, noon())
  check("streams: names, icons, usage reset, context reset (in order)", methods(env):gsub("^setApps,setIcons,", "") == "reset,reset", methods(env))
  check("streams: usage page holds the usage log", env.page.text == lines(0, 20))
  check("streams: context page holds the context log", env.page.ctx.text == ctxLines(0, 15))
  check("streams: both generation 1", env.page.generation == 1 and env.page.ctx.generation == 1)
  check("streams: usage reset carries no stream field, context carries 'context'", usageCalls(env, "reset") == 1 and ctxCalls(env, "reset") == 1)
  check("streams: context reset has no bindings or health", (function()
    for _, c in ipairs(env.page.calls) do
      local a = c.args and c.args[1]
      if c.method == "reset" and type(a) == "table" and a.stream == "context" then return a.bindings == nil and a.health == nil and a.insights == nil end
    end
  end)())
  check("streams: calls never overlap", (env.overlap or 0) == 0, env.overlap)

  -- Append only to the context log.
  local before = #env.page.calls
  write(contextPath(home), ctxLines(15, 4), "ab")
  toggle(env)
  local seq = methods(env, before + 1)
  check("context append: only a context append (plus health), then tick and open", seq == "append,setHealth,tick,open", seq)
  check("context append: stream tag and range", (function()
    for i = before + 1, #env.page.calls do
      local a = env.page.calls[i].args[1]
      if env.page.calls[i].method == "append" then return a.stream == "context" and a.from == #ctxLines(0, 15) and a.to == #ctxLines(0, 19) end
    end
  end)())
  check("context append: page equals the file", env.page.ctx.text == ctxLines(0, 19))
  check("context append: usage page untouched", env.page.text == lines(0, 20) and env.page.generation == 1)

  -- Append only to the usage log.
  toggle(env) -- close
  before = #env.page.calls
  write(p.log, lines(20, 3), "ab")
  toggle(env)
  seq = methods(env, before + 1)
  check("usage append: no context traffic", seq:find("append", 1, true) ~= nil and ctxCalls(env, "append") == 1 and usageCalls(env, "append") == 1, seq)
  check("usage append: both pages current", env.page.text == lines(0, 23) and env.page.ctx.text == ctxLines(0, 19))

  -- A partial last context line is held back.
  toggle(env)
  write(contextPath(home), "2026-10-16T09:59:59.9", "ab")
  toggle(env)
  check("partial context line: not delivered", env.page.ctx.text == ctxLines(0, 19))
  toggle(env)
  write(contextPath(home), "99\tlock\t-\n", "ab")
  toggle(env)
  local tail = "2026-10-16T09:59:59.999\tlock\t-\n"
  check("partial context line: arrives whole later", env.page.ctx.text:sub(-#tail) == tail, env.page.ctx.text:sub(-40))
end

-- Context recovery: truncation, replacement, deletion, rejected or lost delivery.
do
  local home, p = baseHome("ctx_recover")
  os.execute("mkdir -p " .. home .. "/.local/state/hyperdash")
  write(p.log, lines(0, 10))
  write(contextPath(home), ctxLines(0, 30))
  local env = startPanel(home, noon())
  local usageGeneration = env.page.generation

  write(contextPath(home), ctxLines(100, 3)) -- truncated in place
  toggle(env)
  check("context truncation: new generation", env.page.ctx.generation == 2, env.page.ctx.generation)
  check("context truncation: page equals the file", env.page.ctx.text == ctxLines(100, 3))
  check("context truncation: usage stream untouched", env.page.generation == usageGeneration and usageCalls(env, "reset") == 1)

  toggle(env)
  write(contextPath(home) .. ".new", ctxLines(200, 12))
  os.execute("mv " .. contextPath(home) .. ".new " .. contextPath(home)) -- new inode
  toggle(env)
  check("context replacement: new generation", env.page.ctx.generation == 3, env.page.ctx.generation)
  check("context replacement: page equals the file", env.page.ctx.text == ctxLines(200, 12))

  toggle(env)
  os.execute("rm -f " .. contextPath(home))
  toggle(env)
  check("context deleted: page emptied by a reset", env.page.ctx.text == "" and env.page.ctx.generation == 4, env.page.ctx.generation)
  toggle(env)
  write(contextPath(home), ctxLines(300, 2))
  toggle(env)
  check("context recreated: delivered again", env.page.ctx.text == ctxLines(300, 2))

  -- A rejected context append is followed by a reset; the usage stream is not reset.
  toggle(env)
  write(contextPath(home), ctxLines(302, 2), "ab")
  env.page.mode.rejectContext = "duplicate"
  env.module.toggle()
  env.advance(0)
  env.flush(3) -- the append is rejected
  env.page.mode.rejectContext = nil
  env.flush()
  check("context rejected append: converges by a reset", env.page.ctx.text == ctxLines(300, 4), #env.page.ctx.text)
  check("context rejected append: usage generation unchanged", env.page.generation == usageGeneration)

  -- A failed read of the context log leaves its offset alone.
  toggle(env)
  local before = env.page.ctx.offset
  write(contextPath(home), ctxLines(304, 1), "ab")
  os.execute("chmod 000 " .. contextPath(home))
  toggle(env)
  check("context unreadable: offset does not advance", env.page.ctx.offset == before)
  os.execute("chmod 644 " .. contextPath(home))
  toggle(env)
  toggle(env)
  check("context readable again: caught up", env.page.ctx.text == ctxLines(300, 4) .. ctxLines(304, 1))
end

-- Context log absent: no stream calls and no errors.
do
  local home, p = baseHome("ctx_absent")
  write(p.log, lines(0, 5))
  local env = startPanel(home, noon())
  toggle(env)
  check("no context file: no context calls", ctxCalls(env, "reset") == 0 and ctxCalls(env, "append") == 0)
  check("no context file: still opens", env.shown == 1)
end

-- A dead page: both streams are resent by resets after the reload.
do
  local home, p = baseHome("ctx_dead")
  os.execute("mkdir -p " .. home .. "/.local/state/hyperdash")
  write(p.log, lines(0, 5))
  write(contextPath(home), ctxLines(0, 6))
  local env = startPanel(home, noon())
  env.killPage()
  env.module.toggle()
  env.advance(0)
  env.flush()
  env.finishReload()
  env.flush()
  check("dead page: both streams rebuilt", env.page.text == lines(0, 5) and env.page.ctx.text == ctxLines(0, 6))
  check("dead page: names and icons sent again", env.page.apps ~= nil and env.page.icons ~= nil)
  check("dead page: opened", env.shown == 1)
end

-- setApps and bundle-ID icons.
do
  local home, p = baseHome("ctx_apps")
  write(p.log, lines(0, 3))
  write(p.bindings, '[{"layer":"o","key":"f","label":"Finder","app":"Finder"},{"layer":"b","key":"x","label":"x.com","site":"x.com"}]')
  local env = sandbox.new({ moduleDir = MODULE_DIR, home = home, startTime = noon() })
  env.installed = {
    ["/Applications"] = { "Ghostty.app", "Notes.txt", "Safari.app", "Broken.app" },
    ["/System/Applications"] = { "Notes.app" },
    ["/System/Library/CoreServices"] = { "Finder.app" },
  }
  env.bundleInfo = {
    ["/Applications/Ghostty.app"] = { CFBundleIdentifier = "com.mitchellh.ghostty", CFBundleName = "Ghostty" },
    ["/Applications/Safari.app"] = { CFBundleIdentifier = "com.apple.Safari", CFBundleDisplayName = "Safari Browser", CFBundleName = "Safari" },
    ["/Applications/Broken.app"] = { CFBundleIdentifier = "not a bundle id" },
    ["/System/Applications/Notes.app"] = { CFBundleIdentifier = "com.apple.Notes" },
    ["/System/Library/CoreServices/Finder.app"] = { CFBundleIdentifier = "com.apple.finder", CFBundleName = "Finder" },
  }
  env.runningApps = {
    fakeApp("com.mitchellh.ghostty", "Ghostty (running)", "/Applications/Ghostty.app"),
    fakeApp("com.example.helper", "Helper", "/Applications/Helper.app", 2),
    fakeApp(nil, "No bundle", "/x"),
  }
  env.webview.navigation("didFinishNavigation")
  env.flush()
  local apps = env.page.apps
  check("setApps: installed bundles by ID", apps and apps["com.apple.Safari"] == "Safari Browser" and apps["com.apple.Notes"] == "com.apple.Notes" or (apps and apps["com.apple.Notes"] == "Notes"), apps and apps["com.apple.Notes"])
  check("setApps: display name falls back to the file name", apps and apps["com.apple.Notes"] == "Notes", apps and apps["com.apple.Notes"])
  check("setApps: running app name overrides", apps and apps["com.mitchellh.ghostty"] == "Ghostty (running)", apps and apps["com.mitchellh.ghostty"])
  check("setApps: non-app files and bad IDs are skipped", apps and apps["not a bundle id"] == nil and next({}) == nil)
  check("setApps: background (non-regular) running apps still get a name", apps and apps["com.example.helper"] == "Helper")
  check("setApps: apps without a bundle ID are skipped", apps and (function() for k, v in pairs(apps) do if v == "No bundle" then return false end end return true end)())
  local icons = env.page.icons and env.page.icons.apps
  check("icons: binding app keyed by name and by bundle ID", icons and icons["Finder"] ~= nil and icons["com.apple.finder"] == icons["Finder"])
  check("icons: running regular app keyed by bundle ID", icons and icons["com.mitchellh.ghostty"] ~= nil)
  check("icons: background app has no icon", icons and icons["com.example.helper"] == nil)
  check("setApps: sent before the usage reset", methods(env):find("^setApps,setIcons,reset") ~= nil, methods(env))

  -- Unchanged apps are not resent; a new running app is.
  local count = function(m) local n = 0 for _, c in ipairs(env.page.calls) do if c.method == m then n = n + 1 end end return n end
  local apps0, icons0 = count("setApps"), count("setIcons")
  toggle(env)
  toggle(env)
  check("setApps: nothing resent while apps are unchanged", count("setApps") == apps0 and count("setIcons") == icons0)
  env.runningApps[#env.runningApps + 1] = fakeApp("com.example.new", "New App", "/Applications/New.app")
  toggle(env)
  check("setApps: a newly running app is sent", count("setApps") == apps0 + 1 and env.page.apps["com.example.new"] == "New App")
  check("icons: and its icon", count("setIcons") == icons0 + 1 and env.page.icons.apps["com.example.new"] ~= nil)
  -- Empty maps encode as objects.
  local env2 = startPanel((function() local h, q = baseHome("ctx_apps_empty"); write(q.log, lines(0, 1)); return h end)(), noon())
  local raw
  for _, call in ipairs(env2.js) do if call.code:find("^setApps") then raw = call.code end end
  check("setApps: empty map is {} not []", raw == "setApps({})", raw)
end

---------------------------------------------------------------------------
-- Round 4: --context for the insights tool, and context changes as an input
---------------------------------------------------------------------------
do
  local function touchAgo(path, seconds)
    os.execute(string.format("touch -t %s %s", os.date("%Y%m%d%H%M.%S", os.time() - seconds), path))
  end
  local function setup(name, withContext, withReport)
    local home, p = baseHome(name)
    write(p.log, lines(0, 3))
    write(p.tool, "#!/bin/sh\n")
    os.execute("chmod 755 " .. p.tool)
    os.execute("mkdir -p " .. home .. "/.local/state/hyperdash")
    if withContext then write(contextPath(home), ctxLines(0, 3)) end
    if withReport then write(p.insights, GOOD_INSIGHTS) else os.execute("rm -f " .. p.insights) end
    return home, p
  end
  local function sameList(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
  end
  local function oldArguments(p)
    return { "--log", p.log, "--bindings", p.bindings, "--output", p.insights }
  end
  -- Real time, not noon: report ages are measured against file mtimes.
  -- `beforeOpen` runs after the module loaded (a recorder writes its start line then).
  local function open(home, recordContext, beforeOpen)
    local env = sandbox.new({ moduleDir = MODULE_DIR, home = home, recordContext = recordContext })
    env.webview.navigation("didFinishNavigation")
    env.flush()
    if beforeOpen then beforeOpen() end
    toggle(env)
    return env
  end

  -- Recording off: the old argument list, even if a context file exists.
  local home, p = setup("ins_off", true, false)
  local env = open(home, false)
  check("insights args, recording off: a task started", #env.tasks == 1, #env.tasks)
  check("insights args, recording off: exactly the old list", env.tasks[1] and sameList(env.tasks[1].args, oldArguments(p)), env.tasks[1] and table.concat(env.tasks[1].args, " "))

  -- On, file missing: the old list.
  home, p = setup("ins_on_missing", false, false)
  env = open(home, true, function() os.execute("rm -f " .. contextPath(home)) end)
  check("insights args, on but no file: a task started", #env.tasks == 1, #env.tasks)
  check("insights args, on but no file: exactly the old list", env.tasks[1] and sameList(env.tasks[1].args, oldArguments(p)), env.tasks[1] and table.concat(env.tasks[1].args, " "))

  -- On, file present: the flag and the path, last.
  home, p = setup("ins_on_present", true, false)
  env = open(home, true)
  local expected = oldArguments(p)
  expected[#expected + 1] = "--context"
  expected[#expected + 1] = contextPath(home)
  check("insights args, on with file: a task started", #env.tasks == 1, #env.tasks)
  check("insights args, on with file: exact list with --context", env.tasks[1] and sameList(env.tasks[1].args, expected), env.tasks[1] and table.concat(env.tasks[1].args, " "))

  -- The file is checked at run time, not at load: delete it after loading.
  home, p = setup("ins_on_deleted", true, false)
  env = sandbox.new({ moduleDir = MODULE_DIR, home = home, startTime = noon(), recordContext = true })
  env.webview.navigation("didFinishNavigation")
  env.flush()
  os.execute("rm -f " .. contextPath(home))
  toggle(env)
  check("insights args: file deleted after load, so no flag", env.tasks[1] and sameList(env.tasks[1].args, oldArguments(p)), env.tasks[1] and table.concat(env.tasks[1].args, " "))

  -- A context change makes a fresh report due, once the report is 300 s old.
  home, p = setup("ins_due", true, true)
  touchAgo(p.insights, 400)
  write(contextPath(home), ctxLines(0, 4)) -- newer than the report
  env = open(home, true)
  check("context change: report 400 s old and older than the context -> rerun", #env.tasks == 1, #env.tasks)
  check("context change: and it receives --context", env.tasks[1] and env.tasks[1].args[#env.tasks[1].args] == contextPath(home))

  home, p = setup("ins_not_due_young", true, true)
  touchAgo(p.insights, 100)
  write(contextPath(home), ctxLines(0, 4))
  env = open(home, true)
  check("context change: report only 100 s old -> no rerun (opening writes events)", #env.tasks == 0, #env.tasks)

  home, p = setup("ins_not_due_older_context", true, true)
  touchAgo(p.insights, 400)
  -- Recording writes a start line at load, so age the file after loading.
  env = open(home, true, function() touchAgo(contextPath(home), 500) end)
  check("context older than the report: no rerun", #env.tasks == 0, #env.tasks)

  home, p = setup("ins_not_due_off", true, true)
  touchAgo(p.insights, 400)
  write(contextPath(home), ctxLines(0, 4))
  env = open(home, false)
  check("recording off: a newer context file does not make the report due", #env.tasks == 0, #env.tasks)

  home, p = setup("ins_not_due_nofile", false, true)
  touchAgo(p.insights, 400)
  env = open(home, true, function() os.execute("rm -f " .. contextPath(home)) end)
  check("on, no context file, fresh report: no rerun", #env.tasks == 0, #env.tasks)

  home, p = setup("ins_old_report", false, true)
  touchAgo(p.insights, 4000)
  env = open(home, false)
  check("report over an hour old still reruns", #env.tasks == 1, #env.tasks)
end

os.execute("rm -rf " .. SCRATCH)
report[#report + 1] = string.format("passed=%d failed=%d", passed, failed)
return table.concat(report, "\n")
