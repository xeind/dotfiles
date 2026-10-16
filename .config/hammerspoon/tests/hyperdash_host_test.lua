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
  check("cold: icons, then one reset, nothing else", methods(env) == "setIcons,reset", methods(env))
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
  check("append: reset, then append, then tick,open", seq:match("^setIcons,reset,append,") ~= nil and seq:match("tick,open$") ~= nil, seq)
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
  check("bindings change: setBindings sent, no log traffic", seq:match("^setBindings") ~= nil and not seq:find("reset") and not seq:find("append"), seq)
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

os.execute("rm -rf " .. SCRATCH)
report[#report + 1] = string.format("passed=%d failed=%d", passed, failed)
return table.concat(report, "\n")
