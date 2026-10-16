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

-- Open the panel against `home`, answer the page, and return the data call.
local function openPanel(home, answerWith)
  local env = sandbox.new({ moduleDir = MODULE_DIR, home = home })
  env.module.toggle()
  env.advance(0)
  return env
end

local function dataCall(env)
  for _, call in ipairs(env.js) do
    if call.code:find("^update%(") then return call.code end
  end
end
local function payload(env)
  local code = dataCall(env)
  if not code then return nil end
  return hs.json.decode(code:sub(#"update(" + 1, -2))
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

os.execute("rm -rf " .. SCRATCH)
report[#report + 1] = string.format("passed=%d failed=%d", passed, failed)
return table.concat(report, "\n")
