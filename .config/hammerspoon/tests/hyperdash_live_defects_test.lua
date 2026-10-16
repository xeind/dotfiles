-- Regression tests for two defects found only after round 4 went live, and
-- for the safety net around the app-name sync.
--   hs -t 60 -c 'return dofile(os.getenv("HOME").."/.config/hammerspoon/tests/hyperdash_live_defects_test.lua")'
-- Self-contained: fake `hs` (fake_hs.lua), scratch files under $TMPDIR.
-- The fake page exposes only the real page's API (see fake_hs.lua).

local TESTS = debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")
local MODULE_DIR = TESTS .. "/.."
local SCRATCH = ((os.getenv("TMPDIR") or "/tmp"):gsub("/$", "")) .. "/hyperdash_tests/live_defects"
local sandbox = dofile(TESTS .. "/fake_hs.lua")

local passed, failed, report = 0, 0, {}
local function check(name, condition, detail)
  if condition then passed = passed + 1 else
    failed = failed + 1
    report[#report + 1] = "FAIL " .. name .. (detail and (": " .. tostring(detail)) or "")
  end
end
local function write(path, text, mode)
  local f = assert(io.open(path, mode or "wb"))
  f:write(text)
  f:close()
end
local function noon()
  local t = os.date("*t")
  return os.time({ year = t.year, month = t.month, day = t.day, hour = 12, min = 0, sec = 0 })
end
local function lines(first, count)
  local parts = {}
  for i = first, first + count - 1 do
    parts[#parts + 1] = string.format("2026-10-15T%02d:%02d:%02d\tb\t%s\n", 10 + (i // 3600) % 12, (i // 60) % 60, i % 60, string.char(97 + i % 26))
  end
  return table.concat(parts)
end
local function baseHome(name)
  local home = SCRATCH .. "/" .. name
  os.execute("rm -rf " .. home)
  os.execute("mkdir -p " .. home .. "/.config/karabiner/hyperdash " .. home .. "/.local/state/karabiner")
  write(home .. "/.config/karabiner/hyperdash/index.html", "<html></html>")
  local p = {
    bindings = home .. "/.config/karabiner/hyperdash/bindings.json",
    log = home .. "/.local/state/karabiner/usage.log",
    insights = home .. "/.local/state/karabiner/insights.json",
  }
  write(p.bindings, '[{"layer":"b","key":"x","label":"x.com","site":"x.com"}]')
  write(p.insights, '{"version":2,"generated":"2026-10-15T10:00:00","month":"2026-10","recordingSince":null,"rejectedLines":0,"insights":[]}')
  return home, p
end
local function toggle(env)
  env.module.toggle()
  local ok, err = pcall(function() env.advance(0); env.flush() end)
  if not ok then env.log[#env.log + 1] = "raised: " .. tostring(err) end
end
-- app:path() on a background process with a bundle ID but no bundle raises
-- NSInvalidArgumentException (-[NSBundle initWithURL:]: nil URL argument).
local function fakeApp(id, name, path, kind, pathThrows)
  return {
    bundleID = function() return id end,
    name = function() return name end,
    path = function()
      if pathThrows then error("NSInvalidArgumentException: -[NSBundle initWithURL:]: nil URL argument") end
      return path
    end,
    kind = function() return kind or 1 end,
  }
end

---------------------------------------------------------------------------
-- Live-only defects found after applying round 4 (each fails on the old code)
---------------------------------------------------------------------------
do
  -- 1. Background processes with a bundle ID but no bundle: path() raises.
  local home, p = baseHome("live_path")
  write(p.log, lines(0, 4))
  local env = sandbox.new({ moduleDir = MODULE_DIR, home = home, startTime = noon() })
  env.runningApps = {
    fakeApp("com.apple.chronod", "chronod", nil, 2, true),
    fakeApp("com.apple.sharingd", "sharingd", nil, 2, true),
    fakeApp("com.apple.finder", "Finder", "/System/Library/CoreServices/Finder.app"),
  }
  local ok, err = pcall(env.webview.navigation, "didFinishNavigation")
  check("background process: the load callback does not raise", ok, err)
  env.flush()
  check("background process: the first sync completes", env.page.text == lines(0, 4), #env.page.text)
  check("background process: names still include it", env.page.apps and env.page.apps["com.apple.chronod"] == "chronod")
  check("background process: it gets no icon, the regular app does", env.page.icons and env.page.icons.apps["com.apple.chronod"] == nil and env.page.icons.apps["com.apple.finder"] ~= nil)
  write(p.log, lines(4, 2), "ab")
  toggle(env)
  check("background process: the panel opens", env.shown == 1, env.shown)
  check("background process: later syncs are not stuck", env.page.text == lines(0, 6))
  toggle(env)
  toggle(env)
  check("background process: second open works too", env.shown == 2, env.shown)
end

do
  -- 2. Only the page's real API exists: setApps is window.hyperdash.setApps.
  local home, p = baseHome("live_api")
  write(p.log, lines(0, 3))
  local env = sandbox.new({ moduleDir = MODULE_DIR, home = home, startTime = noon() })
  env.runningApps = { fakeApp("com.apple.finder", "Finder", "/System/Library/CoreServices/Finder.app") }
  local html = env.htmlCalls
  env.webview.navigation("didFinishNavigation")
  env.flush()
  toggle(env)
  check("page API: no script errors from the host", (env.scriptErrors or 0) == 0, env.scriptErrors)
  check("page API: the page was never reloaded", env.htmlCalls == html, env.htmlCalls - html)
  check("page API: names delivered through window.hyperdash.setApps", env.page.apps ~= nil)
  check("page API: panel opened, no alert", env.shown == 1 and #env.alerts == 0)
  local sawGlobalSetApps = false
  for _, call in ipairs(env.js) do if call.code:find("^setApps") then sawGlobalSetApps = true end end
  check("page API: no global setApps call", not sawGlobalSetApps)
  -- The fake rejects what the real page does not define.
  local _, err = env.respond("window.hyperdash.setIcons({})")
  check("page API: the fake rejects window.hyperdash.setIcons", err and err.code == 4)
  _, err = env.respond("setApps({})")
  check("page API: the fake rejects a global setApps", err and err.code == 4)
end

do
  -- 3. Safety net: a failure while building names or icons never blocks the sync.
  -- (A Lua error stands in for a native exception, which pcall may not catch.)
  local home, p = baseHome("live_net")
  write(p.log, lines(0, 4))
  local env = sandbox.new({ moduleDir = MODULE_DIR, home = home, startTime = noon() })
  env.runningApps = { fakeApp("com.example.broken", "Broken", nil, 1, true) } -- a regular app whose path() raises
  local ok, err = pcall(env.webview.navigation, "didFinishNavigation")
  check("throwing sendApps: the load callback does not raise", ok, err)
  env.flush()
  env.advance(0)
  env.flush()
  check("throwing sendApps: usage stream still delivered", env.page.text == lines(0, 4), #env.page.text)
  write(p.log, lines(4, 2), "ab")
  toggle(env)
  check("throwing sendApps: the panel opens", env.shown == 1, env.shown)
  check("throwing sendApps: later syncs work", env.page.text == lines(0, 6))
  check("throwing sendApps: the failure is logged", (function() for _, l in ipairs(env.log) do if l:find("apps", 1, true) then return true end end return false end)())
  env.runningApps = { fakeApp("com.apple.finder", "Finder", "/System/Library/CoreServices/Finder.app") }
  toggle(env)
  toggle(env)
  check("throwing sendApps: recovers once the app is gone", env.page.apps ~= nil and env.page.apps["com.apple.finder"] == "Finder")
end

os.execute("rm -rf " .. SCRATCH)
report[#report + 1] = string.format("passed=%d failed=%d", passed, failed)
return table.concat(report, "\n")
