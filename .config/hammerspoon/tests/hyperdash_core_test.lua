-- Tests for hyperdash_core.lua. Run inside Hammerspoon:
--   hs -t 120 -c 'return dofile(os.getenv("HOME").."/.config/hammerspoon/tests/hyperdash_core_test.lua")'
-- Uses only temporary files under $TMPDIR/hyperdash_tests/core/, removed at the end.
-- Creates no webview, timer, watcher or global.

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$") .. "/.."
local SCRATCH = ((os.getenv("TMPDIR") or "/tmp"):gsub("/$", "")) .. "/hyperdash_tests/core"
local R = dofile(DIR .. "/hyperdash_core.lua")
local LOG = SCRATCH .. "/usage.log"

os.execute("rm -rf " .. SCRATCH .. " && mkdir -p " .. SCRATCH)

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
local function read(path)
  local f = assert(io.open(path, "rb"))
  local text = f:read("a")
  f:close()
  return text
end
local function completeLines(text)
  local cut = 0
  for i = #text, 1, -1 do
    if text:byte(i) == 10 then cut = i; break end
  end
  return text:sub(1, cut)
end

-- Deterministic pseudo-random numbers, so a failure reproduces.
local seed = 12345
local function rand(n)
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed % n + 1
end

local function makeLines(count, first)
  local parts = {}
  for i = first, first + count - 1 do
    parts[#parts + 1] = string.format("2026-10-15T%02d:%02d:%02d\t%s\t%s\n", (i // 3600) % 24, (i // 60) % 60, i % 60,
      string.char(97 + i % 26), string.char(97 + (i * 7) % 26))
  end
  return table.concat(parts)
end

-- A model of the page's reset/append contract.
local function newPage()
  local page = { generation = nil, offset = 0, text = "", resets = 0, appends = 0 }
  function page.reset(a)
    page.generation, page.offset, page.text = a.generation, a.offset, a.text
    page.resets = page.resets + 1
    return { ok = true, generation = a.generation, offset = a.offset }
  end
  function page.append(a)
    if a.generation ~= page.generation then return { ok = false, reason = "generation", offset = page.offset } end
    if a.from < page.offset then return { ok = false, reason = "duplicate", offset = page.offset } end
    if a.from > page.offset then return { ok = false, reason = "gap", offset = page.offset } end
    page.text = page.text .. a.text
    page.offset = a.to
    page.appends = page.appends + 1
    return { ok = true, offset = a.to }
  end
  return page
end

local function deliver(page, action)
  if action.kind == "reset" then return page.reset(action) end
  if action.kind == "append" then return page.append(action) end
end

-- The host loop: plan, deliver, commit or fail; repeat until nothing is left.
-- `lose` makes the next delivery return no acknowledgement.
local function sync(state, env, page, opts)
  opts = opts or {}
  local last
  for _ = 1, 8 do
    local action = R.plan(state, env, LOG)
    last = action
    if action.kind == "none" or action.kind == "error" then return action end
    if action.kind ~= "retry" then
      local result
      if opts.lose then
        opts.lose = false
        deliver(page, action) -- the page applied it, but the host never heard back
        result = nil
      else
        result = deliver(page, action)
      end
      if result and result.ok then R.commit(state, action) else R.fail(state) end
    end
  end
  return last
end

local function env(chunk, overrides)
  local e = { stat = hs.fs.attributes, open = io.open, chunk = chunk }
  for k, v in pairs(overrides or {}) do e[k] = v end
  return e
end

local function converged(name, page, state)
  local expected = completeLines(read(LOG))
  check(name .. ": page text equals a full read", page.text == expected,
    string.format("page %d bytes, expected %d", #page.text, #expected))
  check(name .. ": page offset equals state offset", page.offset == state.offset)
  check(name .. ": offset ends on a newline or is 0", state.offset == 0 or expected:byte(state.offset) == 10)
end

---------------------------------------------------------------------------
-- 1. Chunk boundaries and random append sizes, for several read chunk sizes
---------------------------------------------------------------------------
for _, chunk in ipairs({ 1, 3, 7, 64, 4096, 1024 * 1024 }) do
  write(LOG, "")
  local state, page = R.newState(), newPage()
  local e = env(chunk)
  sync(state, e, page)
  local source = makeLines(120, 0)
  local position = 1
  while position <= #source do
    local size = rand(90) -- cuts lines mid-field and mid-timestamp
    write(LOG, source:sub(position, position + size - 1), "ab")
    position = position + size
    sync(state, e, page)
    if rand(5) == 1 then converged("chunk " .. chunk .. " mid-run", page, state) end
  end
  converged("chunk " .. chunk, page, state)
  check("chunk " .. chunk .. ": all bytes consumed", state.offset == #source, state.offset)
  check("chunk " .. chunk .. ": one reset, many appends", page.resets == 1 and page.appends > 1,
    page.resets .. "/" .. page.appends)
end

---------------------------------------------------------------------------
-- 2. A split final line is held back, not lost and not corrupt
---------------------------------------------------------------------------
do
  write(LOG, "2026-10-15T10:00:00\ta\tb\n2026-10-15T10:00:0")
  local state, page = R.newState(), newPage()
  local e = env()
  sync(state, e, page)
  check("split: only the complete line is delivered", page.text == "2026-10-15T10:00:00\ta\tb\n", page.text)
  check("split: offset stops after the newline", state.offset == 24, state.offset)
  local again = R.plan(state, e, LOG)
  check("split: second plan sees nothing new", again.kind == "none", again.kind)
  write(LOG, "1\tc\td\n", "ab")
  local action = R.plan(state, e, LOG)
  check("split: completed line arrives whole", action.kind == "append" and action.text == "2026-10-15T10:00:01\tc\td\n", action.text)
  check("split: append starts at the held-back byte", action.from == 24)
  sync(state, e, page)
  converged("split", page, state)
  write(LOG, "no newline at all")
  local s2, p2 = R.newState(), newPage()
  sync(s2, e, p2)
  check("only a partial line: nothing delivered", p2.text == "" and s2.offset == 0)
end

---------------------------------------------------------------------------
-- 3. Truncation
---------------------------------------------------------------------------
do
  write(LOG, makeLines(50, 0))
  local state, page = R.newState(), newPage()
  local e = env(100)
  sync(state, e, page)
  local generation = state.generation
  write(LOG, makeLines(5, 1000)) -- same inode, smaller
  sync(state, e, page)
  check("truncate: new generation", state.generation == generation + 1)
  converged("truncate", page, state)
  check("truncate: old rows are gone", not page.text:find("T00:00:00", 1, true) or page.text == read(LOG))
  write(LOG, "")
  sync(state, e, page)
  converged("truncate to empty", page, state)
  check("truncate to empty: offset 0", state.offset == 0 and page.text == "")
end

---------------------------------------------------------------------------
-- 4. Replacement by a new inode (rename over the log), larger and smaller
---------------------------------------------------------------------------
for _, count in ipairs({ 8, 80 }) do
  write(LOG, makeLines(30, 0))
  local state, page = R.newState(), newPage()
  local e = env()
  sync(state, e, page)
  local before = hs.fs.attributes(LOG, "ino")
  write(SCRATCH .. "/replacement", makeLines(count, 5000))
  os.execute("mv " .. SCRATCH .. "/replacement " .. LOG)
  check("replace " .. count .. ": inode changed", hs.fs.attributes(LOG, "ino") ~= before)
  local generation = state.generation
  sync(state, e, page)
  check("replace " .. count .. ": new generation", state.generation == generation + 1)
  converged("replace " .. count, page, state)
end

-- Same size, new inode.
do
  local original = makeLines(10, 0)
  write(LOG, original)
  local state, page = R.newState(), newPage()
  local e = env()
  sync(state, e, page)
  write(SCRATCH .. "/replacement", (original:gsub("T00", "T01")))
  os.execute("mv " .. SCRATCH .. "/replacement " .. LOG)
  sync(state, e, page)
  converged("replace same size", page, state)
  check("replace same size: content really changed", page.text:find("T01", 1, true) ~= nil)
end

-- Same inode, rewritten and grown: the byte before the offset is no longer "\n".
do
  write(LOG, "aaaa\nbbbb\n")
  local state, page = R.newState(), newPage()
  local e = env()
  sync(state, e, page)
  write(LOG, "aaaa\nbbbbXXXX\nzz\n") -- in place, longer than before
  sync(state, e, page)
  converged("in-place rewrite", page, state)
  check("in-place rewrite: reset, not append", page.resets == 2, page.resets)
end

---------------------------------------------------------------------------
-- 5. Failed read, missing file, failed delivery
---------------------------------------------------------------------------
do
  write(LOG, makeLines(20, 0))
  local state, page = R.newState(), newPage()
  sync(state, env(), page)
  write(LOG, makeLines(5, 100), "ab")
  local before = state.offset
  local broken = env(nil, { open = function() return nil end })
  local action = R.plan(state, broken, LOG)
  check("failed read: reports an error", action.kind == "error", action.kind)
  check("failed read: offset does not move", state.offset == before)
  local short = env(nil, { open = function(path, mode)
    local f = io.open(path, mode)
    return setmetatable({}, { __index = function(_, k)
      if k == "read" then return function() return nil end end
      return function(_, ...) return f[k](f, ...) end
    end })
  end })
  local action2 = R.plan(state, short, LOG)
  check("short read: reports an error", action2.kind == "error", action2.kind)
  sync(state, env(), page)
  converged("after failed read", page, state)
end

do
  os.execute("rm -f " .. LOG)
  local state, page = R.newState(), newPage()
  local e = env()
  local action = R.plan(state, e, LOG)
  check("missing: reset with status missing", action.kind == "reset" and action.status == "missing" and action.text == "")
  sync(state, e, page)
  check("missing: settled, nothing more to send", R.plan(state, e, LOG).kind == "none")
  write(LOG, makeLines(4, 0))
  sync(state, e, page)
  converged("missing then created", page, state)
  check("missing then created: status ok", state.status == "ok")
  os.execute("rm -f " .. LOG)
  sync(state, e, page)
  check("created then removed: page emptied", page.text == "" and state.status == "missing")
end

do
  write(LOG, makeLines(10, 0))
  local state, page = R.newState(), newPage()
  local e = env()
  sync(state, e, page)
  write(LOG, makeLines(3, 50), "ab")
  sync(state, e, page, { lose = true }) -- page applied the append; the host never saw the ack
  sync(state, e, page)
  converged("lost ack", page, state)
  check("lost ack: recovered with a reset, no duplicate rows", page.resets >= 2)
end

---------------------------------------------------------------------------
-- 6. Duplicate and out-of-order delivery
---------------------------------------------------------------------------
do
  write(LOG, makeLines(10, 0))
  local state, page = R.newState(), newPage()
  local e = env()
  sync(state, e, page)
  write(LOG, makeLines(4, 20), "ab")
  local action = R.plan(state, e, LOG)
  local first = page.append(action)
  local second = page.append(action)
  check("duplicate: first ok", first.ok)
  check("duplicate: second rejected", second.ok == false and second.reason == "duplicate", second.reason)
  check("duplicate: page applied it once", page.text == completeLines(read(LOG)))
  local gap = page.append({ generation = page.generation, from = page.offset + 50, to = page.offset + 60, text = "x\n" })
  check("gap: rejected", gap.ok == false and gap.reason == "gap")
  local old = page.append({ generation = page.generation - 1, from = page.offset, to = page.offset, text = "" })
  check("stale generation: rejected", old.ok == false and old.reason == "generation")
  R.fail(state)
  sync(state, e, page)
  converged("after rejection", page, state)
end

---------------------------------------------------------------------------
-- 7. Appends while the file grows between stat and read
---------------------------------------------------------------------------
do
  write(LOG, makeLines(10, 0))
  local state, page = R.newState(), newPage()
  sync(state, env(), page)
  local grew = 0
  local racing = env(nil, { stat = function(path)
    local stat = hs.fs.attributes(path)
    if stat and grew < 3 then
      grew = grew + 1
      -- A writer lands bytes after we took the size, ending mid-line.
      write(LOG, makeLines(2, 200 + grew * 10) .. "2026-10-15T09:0", "ab")
      write(LOG, "0:00\tq\tr\n", "ab")
    end
    return stat
  end })
  write(LOG, makeLines(2, 90), "ab")
  for _ = 1, 12 do sync(state, racing, page) end
  sync(state, env(), page)
  converged("growing file", page, state)
  check("growing file: no line cut or doubled", select(2, page.text:gsub("\n", "")) == select(2, read(LOG):gsub("\n", "")))
end

---------------------------------------------------------------------------
-- 8. A larger randomized run: appends, partial lines, truncation, replacement
---------------------------------------------------------------------------
do
  write(LOG, "")
  local state, page = R.newState(), newPage()
  local e = env(rand(200))
  for step = 1, 300 do
    local roll = rand(100)
    if roll <= 70 then
      write(LOG, makeLines(rand(4), step * 10):sub(1, rand(120)), "ab")
    elseif roll <= 80 then
      write(LOG, makeLines(rand(3), step * 10), "ab")
    elseif roll <= 85 then
      write(LOG, makeLines(rand(5), step * 10))
    elseif roll <= 90 then
      write(SCRATCH .. "/replacement", makeLines(rand(20), step * 10))
      os.execute("mv " .. SCRATCH .. "/replacement " .. LOG)
    end
    if rand(3) > 1 then
      sync(state, e, page, { lose = rand(25) == 1 })
      if state.needReset == false then
        local expected = completeLines(read(LOG))
        if page.text ~= expected then
          check("random step " .. step, false, "page " .. #page.text .. " vs " .. #expected)
          break
        end
      end
    end
  end
  sync(state, e, page)
  sync(state, e, page)
  converged("randomized run", page, state)
end

---------------------------------------------------------------------------
-- 9. Validation (stage A)
---------------------------------------------------------------------------
do
  local ok, message = R.checkInsights({ version = 2, month = "2026-10", insights = {} })
  check("insights v2 with empty array", ok == true, message)
  ok = R.checkInsights({ version = 2, month = "2026-10", insights = { { kind = "peak" } } })
  check("insights v2 with entries", ok == true)
  ok = R.checkInsights({ version = 3, month = "2026-10", insights = {} })
  check("insights v3 accepted", ok == true)
  ok = R.checkInsights({ version = 4, month = "2026-10", insights = {} })
  check("insights v4 rejected", ok == false)
  check("bundle ID: a bare dash is rejected (readers reject it)", R.validBundleId("-") == false and R.validBundleId("a-") == true)
  ok, message = R.checkInsights({ version = 1, month = "2026-10", insights = {} })
  check("insights v1 rejected", ok == false and message:find("version 1", 1, true) ~= nil, message)
  ok = R.checkInsights({ month = "2026-10", insights = {} })
  check("insights without version rejected", ok == false)
  ok = R.checkInsights({ version = 2, insights = {} })
  check("insights without month rejected", ok == false)
  ok = R.checkInsights({ version = 2, month = 202610, insights = {} })
  check("insights with numeric month rejected", ok == false)
  ok = R.checkInsights({ version = 2, month = "2026-10", insights = { a = 1 } })
  check("insights object instead of array rejected", ok == false)
  ok = R.checkInsights({ version = 2, month = "2026-10" })
  check("insights missing array rejected", ok == false)
  ok = R.checkInsights("text")
  check("insights non-table rejected", ok == false)
  ok = R.checkInsights(nil)
  check("insights nil rejected", ok == false)

  local list = {
    { layer = "b", key = "x", label = "x.com", site = "x.com" },
    { layer = "o", key = "f", label = "Finder", app = "Finder" },
    { layer = "o", key = "g", label = "plain" },
    { layer = 1, key = "x", label = "bad layer" },
    { layer = "b", key = "y" },
    { layer = "b", key = "z", label = "bad app", app = 5 },
    { layer = "b", key = "w", label = "bad site", site = {} },
    "not a table",
  }
  local valid, dropped = R.sanitizeBindings(list)
  check("bindings: keeps 3 valid", #valid == 3, #valid)
  check("bindings: drops 5 invalid", dropped == 5, dropped)
  local none = R.sanitizeBindings({ a = 1 })
  check("bindings: object rejected", none == nil)
  check("bindings: nil rejected", R.sanitizeBindings(nil) == nil)
  local emptyValid, emptyDropped = R.sanitizeBindings({})
  check("bindings: empty array is valid", emptyValid and #emptyValid == 0 and emptyDropped == 0)
  local real = hs.json.decode(read(os.getenv("HOME") .. "/.config/karabiner/hyperdash/bindings.json"))
  local realValid, realDropped = R.sanitizeBindings(real)
  check("bindings: all 94 real entries valid", #realValid == #real and realDropped == 0, #realValid .. "/" .. #real)
end

---------------------------------------------------------------------------
-- 11. Context log: format, validation, recorder
---------------------------------------------------------------------------
do
  local base = os.time({ year = 2026, month = 10, day = 16, hour = 9, min = 30, sec = 12 })
  check("contextTime: milliseconds", R.contextTime(base + 0.045) == "2026-10-16T09:30:12.045", R.contextTime(base + 0.045))
  check("contextTime: whole second", R.contextTime(base) == "2026-10-16T09:30:12.000")
  check("contextTime: rounds to the nearest ms", R.contextTime(base + 0.0004) == "2026-10-16T09:30:12.000" and R.contextTime(base + 0.0006) == "2026-10-16T09:30:12.001")
  check("contextTime: .9996 rolls into the next second", R.contextTime(base + 0.9996) == "2026-10-16T09:30:13.000", R.contextTime(base + 0.9996))
  check("contextTime: 23:59:59.9996 rolls into the next day", R.contextTime(os.time({ year = 2026, month = 10, day = 16, hour = 23, min = 59, sec = 59 }) + 0.9996) == "2026-10-17T00:00:00.000")

  check("contextLine: app", R.contextLine(base + 0.5, "app", "com.mitchellh.ghostty") == "2026-10-16T09:30:12.500\tapp\tcom.mitchellh.ghostty\n")
  for _, kind in ipairs({ "lock", "unlock", "sleep", "wake", "start" }) do
    check("contextLine: " .. kind .. " value is -", R.contextLine(base, kind) == "2026-10-16T09:30:12.000\t" .. kind .. "\t-\n")
    check("contextLine: " .. kind .. " ignores a given value", R.contextLine(base, kind, "secret title") == "2026-10-16T09:30:12.000\t" .. kind .. "\t-\n")
  end
  local line, why = R.contextLine(base, "focus", "x")
  check("contextLine: unknown kind rejected", line == nil and why:find("unknown kind", 1, true) ~= nil, why)
  for _, bad in ipairs({ "", "has space", "tab\there", "line\nbreak", "title: Inbox (3)", "a/b", string.rep("a", 256) }) do
    check("contextLine: bad bundle ID rejected (" .. #bad .. " chars)", R.contextLine(base, "app", bad) == nil)
  end
  check("contextLine: nil bundle ID rejected", R.contextLine(base, "app", nil) == nil)
  for _, good in ipairs({ "com.apple.finder", "org.hammerspoon.Hammerspoon", "com.example.my-app_2", "net.shinyfrog.bear" }) do
    check("validBundleId: " .. good, R.validBundleId(good))
  end

  -- Recorder against a real file.
  local dir = SCRATCH .. "/ctx"
  local path = dir .. "/context.log"
  local clock = base + 0.001
  local ensured = {}
  local recorder = R.newRecorder({
    path = path,
    now = function() return clock end,
    open = io.open,
    stat = hs.fs.attributes,
    ensureDirectory = function(d) ensured[#ensured + 1] = d; os.execute("mkdir -p " .. d) end,
  })
  check("recorder: starts empty", recorder.written == 0 and recorder.lastApp == nil)
  check("recorder: start", recorder.write("start") == true)
  check("recorder: ensured its directory", ensured[1] == dir, ensured[1])
  clock = base + 1.25
  check("recorder: first app written", recorder.app("com.apple.finder") == true)
  clock = base + 2
  check("recorder: same app again is one event", recorder.app("com.apple.finder") == false)
  clock = base + 3
  check("recorder: next app written", recorder.app("com.mitchellh.ghostty") == true)
  check("recorder: invalid app not written, not remembered", recorder.app("bad id") == false and recorder.lastApp == "com.mitchellh.ghostty")
  clock = base + 4
  check("recorder: lock", recorder.write("lock"))
  clock = base + 5
  check("recorder: back to the same app after a lock still writes", recorder.app("com.apple.finder") == true)
  local f = io.open(path, "rb"); local text = f:read("a"); f:close()
  local expected = table.concat({
    "2026-10-16T09:30:12.001\tstart\t-\n",
    "2026-10-16T09:30:13.250\tapp\tcom.apple.finder\n",
    "2026-10-16T09:30:15.000\tapp\tcom.mitchellh.ghostty\n",
    "2026-10-16T09:30:16.000\tlock\t-\n",
    "2026-10-16T09:30:17.000\tapp\tcom.apple.finder\n",
  })
  check("recorder: file content", text == expected, text)
  check("recorder: written count", recorder.written == 5, recorder.written)
  -- Every line parses by the documented format and times never go backwards.
  local last = ""
  local formatOk, ordered = true, true
  for stamp, kind, value in text:gmatch("(%d+%-%d+%-%d+T%d+:%d+:%d+%.%d+)\t(%a+)\t([^\t\n]+)\n") do
    if not R.CONTEXT_KINDS[kind] then formatOk = false end
    if stamp < last then ordered = false end
    last = stamp
  end
  check("recorder: lines match the format", formatOk and select(2, text:gsub("\n", "")) == 5)
  check("recorder: times non-decreasing", ordered)

  -- A deleted log is recreated by the next event, as a new session. With no
  -- frontApp in env there is no app line to seed.
  os.execute("rm -f " .. path)
  check("recorder: writes again after the file was deleted", recorder.write("wake") == true)
  f = io.open(path, "rb"); text = f:read("a"); f:close()
  check("recorder: new file holds start, then the new line", text == R.contextLine(clock, "start") .. R.contextLine(clock, "wake"), text)

  -- A log truncated in place keeps its (dev, ino), and it is a new session too.
  check("recorder: one more line before the truncation", recorder.write("lock") == true)
  f = io.open(path, "wb"); f:close()
  clock = base + 6
  check("recorder: writes after the truncation", recorder.write("unlock") == true)
  f = io.open(path, "rb"); text = f:read("a"); f:close()
  check("recorder: truncated file holds start, then the new line", text == R.contextLine(clock, "start") .. R.contextLine(clock, "unlock"), text)
  recorder.write("lock")
  f = io.open(path, "rb"); text = f:read("a"); f:close()
  check("recorder: the next line adds no second start", select(2, text:gsub("\tstart\t", "")) == 1, text)

  -- Failures are counted, never raised.
  local failing = R.newRecorder({ path = "/nonexistent-dir/x/context.log", now = function() return base end, open = io.open })
  check("recorder: unwritable path returns false", failing.write("start") == false and failing.failed == 1 and failing.lastError ~= nil)
  check("recorder: failed app is not remembered", failing.app("com.apple.finder") == false and failing.lastApp == nil)
  local noWrite = R.newRecorder({ path = path, now = function() return base end,
    open = function() return { write = function() return nil end, close = function() end } end })
  check("recorder: failed write counted", noWrite.write("start") == false and noWrite.failed == 1)

  -- mapSignature does not depend on key order.
  check("mapSignature: order independent", R.mapSignature({ b = "2", a = "1" }) == R.mapSignature({ a = "1", b = "2" }))
  check("mapSignature: sees a changed name", R.mapSignature({ a = "1" }) ~= R.mapSignature({ a = "2" }))
  check("mapSignature: sees a new key", R.mapSignature({ a = "1" }) ~= R.mapSignature({ a = "1", b = "1" }))
  check("mapSignature: empty map", R.mapSignature({}) == "")
end

-- 12. The context stream uses the same reader state machine as the usage log.
do
  local logPath = SCRATCH .. "/context-stream.log"
  local function put(text, mode) local h = assert(io.open(logPath, mode or "wb")); h:write(text); h:close() end
  put("")
  local state = R.newState()
  local env = { stat = hs.fs.attributes, open = io.open, chunk = 5 }
  local lines = {}
  for i = 0, 29 do lines[#lines + 1] = string.format("2026-10-16T09:%02d:00.%03d\tapp\tcom.apple.finder\n", i, i * 7 % 1000) end
  local source = table.concat(lines)
  local pagetext = ""
  local pos, size = 1, 0
  while pos <= #source do
    size = (size % 37) + 11
    put(source:sub(pos, pos + size - 1), "ab")
    pos = pos + size
    local action = R.plan(state, env, logPath)
    if action.kind == "reset" then pagetext = action.text elseif action.kind == "append" then pagetext = pagetext .. action.text end
    if action.kind == "reset" or action.kind == "append" then R.commit(state, action) end
  end
  local final = R.plan(state, env, logPath)
  if final.kind == "append" then pagetext = pagetext .. final.text; R.commit(state, final) end
  check("context stream: incremental text equals the file", pagetext == source, #pagetext .. " vs " .. #source)
end

do
  check("insightsBackoff: no failures, no wait", R.insightsBackoff(0) == 0)
  check("insightsBackoff: one failure, 5 minutes", R.insightsBackoff(1) == 300)
  check("insightsBackoff: two failures, 30 minutes", R.insightsBackoff(2) == 1800)
  check("insightsBackoff: many failures stay at 30 minutes", R.insightsBackoff(50) == 1800)
end

do
  -- A write that looks fine can still fail when the file closes.
  local base = os.time({ year = 2026, month = 10, day = 16, hour = 9, min = 30, sec = 12 })
  local function recorderWith(close)
    return R.newRecorder({ path = "/x/context.log", now = function() return base end,
      open = function() return { write = function() return true end, close = close } end })
  end
  local good = recorderWith(function() return true end)
  check("close ok: counted", good.app("com.apple.finder") == true and good.written == 1 and good.failed == 0)
  local bad = recorderWith(function() return nil, "disk full" end)
  check("close fails: the event is not counted", bad.app("com.apple.finder") == false and bad.written == 0 and bad.failed == 1)
  check("close fails: the app is not remembered, so the next event retries", bad.lastApp == nil)
  check("close fails: the error names the close", bad.lastError:find("close", 1, true) ~= nil, bad.lastError)
  local both = R.newRecorder({ path = "/x/c.log", now = function() return base end,
    open = function() return { write = function() return nil end, close = function() return true end } end })
  check("write fails: still reported as a write failure", both.write("start") == false and both.lastError:find("write", 1, true) ~= nil, both.lastError)
end

do
  -- A replaced or deleted log has no start line, and readers attribute app
  -- events only inside a session, so the recorder must open a new one.
  local base = os.time({ year = 2026, month = 10, day = 16, hour = 9, min = 30, sec = 12 })
  local path = "/fake/context.log"
  local files, inode, openOk = {}, 100, true
  local front = "com.apple.finder"
  local function create() inode = inode + 1; files[path] = { ino = inode, text = "" } end
  local env = {
    path = path,
    now = function() return base end,
    stat = function(p) local f = files[p]; return f and { dev = 1, ino = f.ino, size = #f.text } end,
    frontApp = function() return front end,
    open = function(p)
      if not openOk then return nil end
      if not files[p] then create() end
      local f = files[p]
      return { write = function(_, s) f.text = f.text .. s; return true end, close = function() return true end }
    end,
  }
  local function L(kind, value) return R.contextLine(base, kind, value) end

  local recorder = R.newRecorder(env)
  recorder.write("start")
  recorder.app("com.apple.finder")
  check("rotation: first session written once", files[path].text == L("start") .. L("app", "com.apple.finder"), files[path].text)

  files[path] = nil
  create()
  front = "com.mitchellh.ghostty"
  check("rotation: replaced file, event written", recorder.write("lock") == true)
  check("rotation: replaced file begins a session with the front app",
    files[path].text == L("start") .. L("app", "com.mitchellh.ghostty") .. L("lock"), files[path].text)
  check("rotation: same file appends only the event", recorder.write("unlock") and files[path].text:sub(-#L("unlock")) == L("unlock")
    and select(2, files[path].text:gsub("\tstart\t", "")) == 1, files[path].text)
  check("rotation: seeded front app is remembered", recorder.app("com.mitchellh.ghostty") == false)

  files[path] = nil
  check("rotation: deleted file, app event written", recorder.app("com.apple.Safari") == true)
  check("rotation: deleted file begins with start, app not repeated",
    files[path].text == L("start") .. L("app", "com.apple.Safari"), files[path].text)

  files[path] = nil
  openOk = false
  local late = R.newRecorder(env)
  check("rotation: initial start fails", late.write("start") == false and late.failed == 1)
  openOk = true
  front = "com.apple.finder"
  check("rotation: next write after a failed start succeeds", late.write("wake") == true)
  check("rotation: recovery write begins with start",
    files[path].text == L("start") .. L("app", "com.apple.finder") .. L("wake"), files[path] and files[path].text)
end

---------------------------------------------------------------------------
-- Retention: manifest checks, cuts, and resets that start at a cut
---------------------------------------------------------------------------
do
  local good = { version = 1, tailStart = "2026-09-01T00:00:00", usage = { dev = 1, ino = 2, offset = 24, lastLine = "x" } }
  check("retention: a good manifest passes", R.checkRetention(good, "2026-10-17T18:00:00") == true)
  good.version = 2
  check("retention: a version 2 manifest passes", R.checkRetention(good, "2026-10-17T18:00:00") == true)
  good.version = 1
  local function bad(name, change, now)
    local copy = { version = good.version, tailStart = good.tailStart, usage = good.usage }
    for k, v in pairs(change) do copy[k] = v end
    local ok, message = R.checkRetention(copy, now or "2026-10-17T18:00:00")
    check("retention: " .. name .. " is refused with a message", ok == false and type(message) == "string", message)
  end
  bad("another version", { version = 3 })
  bad("a tail start that is not a month start", { tailStart = "2026-09-02T00:00:00" })
  bad("a missing usage cut", { usage = false })
  bad("a fractional offset", { usage = { dev = 1, ino = 2, offset = 2.5, lastLine = "x" } })
  bad("a zero offset", { usage = { dev = 1, ino = 2, offset = 0, lastLine = "x" } })
  bad("a bad context cut", { context = { dev = 1 } })
  bad("a clock before the tail start", {}, "2026-08-31T23:59:59")
  check("retention: not a table", R.checkRetention("x", "2026-10-17T18:00:00") == false)

  local starts = {
    { { year = 2026, month = 10, day = 17 }, "2026-09-01T00:00:00" },
    { { year = 2026, month = 3, day = 1 }, "2026-01-01T00:00:00" },
    { { year = 2026, month = 3, day = 31 }, "2026-02-01T00:00:00" },
    { { year = 2026, month = 1, day = 15 }, "2025-12-01T00:00:00" },
    { { year = 2026, month = 12, day = 31 }, "2026-11-01T00:00:00" },
    { { year = 2026, month = 11, day = 1 }, "2026-10-01T00:00:00" },
  }
  for _, case in ipairs(starts) do
    local got = R.retentionTailStart(case[1])
    check("retention: tail start for " .. case[1].month .. "/" .. case[1].day, got == case[2], got)
  end
end

do
  local old = "2026-08-30T10:00:00\tw\tu\n2026-08-31T23:59:59\to\tt\n"
  local new = "2026-09-01T00:00:00\tw\tu\n2026-09-02T00:00:00\tw\tv\n"
  write(LOG, old .. new)
  local e = env(5)
  local stat = hs.fs.attributes(LOG)
  local cut = { dev = stat.dev, ino = stat.ino, offset = #old, lastLine = "2026-08-31T23:59:59\to\tt" }
  check("cut: a matching cut gives its offset", R.cutOffset(cut, e, LOG, stat) == #old)
  local function refused(name, change)
    local copy = { dev = cut.dev, ino = cut.ino, offset = cut.offset, lastLine = cut.lastLine }
    for k, v in pairs(change) do copy[k] = v end
    check("cut: " .. name .. " reads from 0", R.cutOffset(copy, e, LOG, stat) == 0)
  end
  refused("another inode", { ino = stat.ino + 1 })
  refused("another device", { dev = stat.dev + 1 })
  refused("another last line", { lastLine = "2026-08-31T23:59:58\to\tt" })
  refused("a last line that is only the end of the line", { lastLine = "31T23:59:59\to\tt" })
  refused("an offset past the end", { offset = #old + #new + 1 })
  refused("an offset off the line end", { offset = #old + 1 })
  check("cut: no stat reads from 0", R.cutOffset(cut, e, LOG, nil) == 0)
  local first = { dev = stat.dev, ino = stat.ino, offset = 24, lastLine = "2026-08-30T10:00:00\tw\tu" }
  check("cut: a cut after the first line is accepted", R.cutOffset(first, e, LOG, stat) == 24)

  -- A reset from the cut: the page holds bytes [cut, end) and the absolute offset.
  local state, page = R.newState(), newPage()
  local base = { cut = cut, archive = '{"version":1}' }
  local action = R.plan(state, e, LOG, base)
  check("cut reset: starts at the cut", action.kind == "reset" and action.from == #old and action.text == new, action.text)
  check("cut reset: offset is absolute", action.offset == #old + #new, action.offset)
  check("cut reset: carries the archive", action.archive == base.archive)
  deliver(page, action)
  R.commit(state, action)
  write(LOG, "2026-09-03T00:00:00\tw\tu\n", "ab")
  local append = R.plan(state, e, LOG, base)
  check("cut reset: later lines arrive as an append", append.kind == "append" and append.from == #old + #new, append.kind)
  deliver(page, append)
  R.commit(state, append)
  check("cut reset: page holds the tail", page.text == completeLines(read(LOG)):sub(#old + 1), page.text)

  -- A newer manifest does not disturb the generation the page holds: appends go on.
  local later = { cut = { dev = stat.dev, ino = stat.ino, offset = #old + 24, lastLine = "2026-09-01T00:00:00\tw\tu" }, archive = '{"version":1,"n":2}' }
  write(LOG, "2026-09-04T00:00:00\tw\tu\n", "ab")
  local more = R.plan(state, e, LOG, later)
  check("new manifest: the held generation keeps appending", more.kind == "append" and more.generation == action.generation, more.kind)
  deliver(page, more)
  R.commit(state, more)
  R.fail(state)
  local again = R.plan(state, e, LOG, later)
  check("new manifest: the next reset starts at the new cut", again.kind == "reset" and again.from == #old + 24 and again.archive == later.archive, again.from)

  -- A cut that no longer fits the file: the reset reads from 0 without the archive.
  R.fail(state)
  local wrong = { cut = { dev = stat.dev, ino = stat.ino, offset = #old, lastLine = "nope" }, archive = "{}" }
  local full = R.plan(state, e, LOG, wrong)
  check("bad cut: the reset reads the whole log", full.kind == "reset" and full.from == 0 and full.text == completeLines(read(LOG)), full.from)
  check("bad cut: no archive goes with it", full.archive == nil)

  -- The archived part rewritten in place, same size: the last line no longer matches.
  write(LOG, (old:gsub("23:59:59", "23:59:58")) .. new)
  local rewritten = R.plan(R.newState(), e, LOG, base)
  check("rewritten archive: reads from 0", rewritten.kind == "reset" and rewritten.from == 0 and rewritten.archive == nil)
  -- Replaced by rename: a new inode, so the cut is not used.
  write(LOG .. ".new", old .. new)
  os.rename(LOG .. ".new", LOG)
  local replaced = R.plan(R.newState(), e, LOG, base)
  check("replaced log: reads from 0", replaced.kind == "reset" and replaced.from == 0 and replaced.archive == nil)
  -- Truncated below the cut.
  write(LOG, old:sub(1, 10))
  local short = R.plan(R.newState(), e, LOG, { cut = { dev = hs.fs.attributes(LOG).dev, ino = hs.fs.attributes(LOG).ino, offset = #old, lastLine = cut.lastLine }, archive = "{}" })
  check("truncated log: reads from 0", short.kind == "reset" and short.from == 0 and short.archive == nil)
end

---------------------------------------------------------------------------
-- Retention: archived days read back through the day index, on the shared
-- fixture (karabiner/hyperdash/tests/retention_cases, written by the insights tool)
---------------------------------------------------------------------------
do
  local CASES = DIR .. "/../karabiner/hyperdash/tests/retention_cases"
  local usageBytes, contextBytes = read(CASES .. "/usage.log"), read(CASES .. "/context.log")
  local manifest = read(CASES .. "/retention.json")
  local headerLine, indexLine = manifest:match("^([^\n]*)\n[^\n]*\n([^\n]*)\n?$")
  local header = hs.json.decode(headerLine)
  local CTX = SCRATCH .. "/context.log"
  -- The fixture's cuts carry dev = ino = 0; give them the copies' identity.
  local function copies()
    write(LOG, usageBytes)
    write(CTX, contextBytes)
    local u, c = hs.fs.attributes(LOG), hs.fs.attributes(CTX)
    return {
      index = indexLine,
      usage = { dev = u.dev, ino = u.ino, offset = header.usage.offset, lastLine = header.usage.lastLine },
      context = { dev = c.dev, ino = c.ino, offset = header.context.offset, lastLine = header.context.lastLine },
    }
  end
  local held = copies()
  local e = env(4096)
  local function span(bytes, from, to) return bytes:sub(from + 1, to == -1 and #completeLines(bytes) or to) end
  local function readDay(date, contextFrom) return R.readArchivedDay(e, held, date, LOG, CTX, contextFrom == nil and header.context.offset or contextFrom) end

  check("day index: entry for the first day", select(1, R.dayEntry(indexLine, "2026-07-20")) == 0)
  check("day index: no entry after the tail start", R.dayEntry(indexLine, "2026-09-01") == nil)
  check("day index: no entry for a date that is not one", R.dayEntry(indexLine, "2026-07-2.") == nil and R.dayEntry(indexLine, nil) == nil)
  check("day index: no entry without an index", R.dayEntry(nil, "2026-07-20") == nil)
  check("day index: a backwards span is refused", R.dayEntry('{"days":{"2026-07-20":[9,3,0,1]}}', "2026-07-20") == nil)
  local a, b, c, d = R.dayEntry('{"days":{"2026-07-20":[0,0,5,-1]}}', "2026-07-20")
  check("day index: contextTo -1 is kept", a == 0 and b == 0 and c == 5 and d == -1)

  -- Each case: the date, then what the read must hold.
  local cases = {
    { "2026-07-20", "the first day of the log" },
    { "2026-07-21", "a day inside the session of the day before" },
    { "2026-08-13", "a day with no presses" },
    { "2026-08-25", "the day at the cut" },
    { "2026-08-28", "a day whose session starts at the context cut" },
  }
  for _, case in ipairs(cases) do
    local date, name = case[1], case[2]
    local u0, u1, c0, c1 = R.dayEntry(indexLine, date)
    local day, message = readDay(date)
    check("day read: " .. name .. " reads", day ~= nil, message)
    if day then
      check("day read: " .. name .. ": the usage span", day.usage == span(usageBytes, u0, u1), #day.usage)
      check("day read: " .. name .. ": the context span", day.context == span(contextBytes, c0, c1), day.context and #day.context)
      -- Whole lines that start with the session's start line or the log's first line.
      check("day read: " .. name .. ": context starts a session", day.context:match("^[^\n]*\tstart\t%-\n") ~= nil, day.context:sub(1, 40))
      local pressed = 0
      for line in day.usage:gmatch("[^\n]+") do if line:sub(1, 10) == date then pressed = pressed + 1 end end
      -- 08-13 has none; the presses of 08-28 all sit after the cut, in the page's own tail.
      check("day read: " .. name .. ": presses of the day", (date == "2026-08-13" or date == "2026-08-28") == (pressed == 0), pressed)
    end
  end
  check("day read: the day at the cut ends there", select(2, R.dayEntry(indexLine, "2026-08-25")) == header.usage.offset)
  check("day read: a day starting inside the session of the day before reads from its start", select(3, R.dayEntry(indexLine, "2026-07-21")) == 0)
  check("day read: from 08-28 the context starts at its cut", select(3, R.dayEntry(indexLine, "2026-08-28")) == header.context.offset)

  local own = readDay("2026-07-21", 0)
  check("day read: a page that holds the whole context gets no context", own and own.context == nil and own.usage ~= "")
  local none = R.readArchivedDay(e, held, "2026-07-21", LOG, CTX, nil)
  check("day read: no context stream either", none and none.context == nil)

  local noIndex = { usage = held.usage, context = held.context }
  check("day read: a version 1 manifest has no days", R.readArchivedDay(e, noIndex, "2026-07-21", LOG, CTX, 1) == nil)
  check("day read: no manifest", R.readArchivedDay(e, nil, "2026-07-21", LOG, CTX, 1) == nil)
  check("day read: a day after the tail start", readDay("2026-09-02") == nil)

  -- To the end of the file when no line follows the day yet.
  local tail = R.readArchivedDay(e, { index = '{"days":{"2026-08-31":[0,0,' .. header.context.offset .. ',-1]}}', usage = held.usage, context = held.context }, "2026-08-31", LOG, CTX, 1)
  check("day read: contextTo -1 reads the complete lines to the end", tail and tail.context == span(contextBytes, header.context.offset, -1))
  write(CTX, "2026-10-17T18:00:00.000\tapp\tcom.a", "ab")
  tail = R.readArchivedDay(e, { index = '{"days":{"2026-08-31":[0,0,' .. header.context.offset .. ',-1]}}', usage = held.usage, context = held.context }, "2026-08-31", LOG, CTX, 1)
  check("day read: a partial last line is left out", tail and tail.context == span(contextBytes, header.context.offset, -1))

  -- Every failure answers nil and a message.
  local function refused(name, prepare)
    held = copies()
    prepare()
    local day, message = readDay("2026-07-21")
    check("day read refused: " .. name, day == nil and type(message) == "string", message)
  end
  refused("the usage log rewritten under its cut", function() write(LOG, (usageBytes:gsub("2026%-08%-25T12:20:32", "2026-08-25T12:20:33"))) end)
  refused("the usage log replaced", function()
    write(LOG .. ".new", usageBytes)
    os.rename(LOG .. ".new", LOG)
  end)
  refused("the usage log truncated", function() write(LOG, usageBytes:sub(1, 100)) end)
  refused("the context log replaced", function()
    write(CTX .. ".new", contextBytes)
    os.rename(CTX .. ".new", CTX)
  end)
  refused("a span that does not start a line", function() held.index = '{"days":{"2026-07-21":[1,144,0,254]}}' end)
  refused("a span that does not end a line", function() held.index = '{"days":{"2026-07-21":[0,143,0,254]}}' end)
  refused("a usage span past the cut", function() held.index = '{"days":{"2026-07-21":[0,' .. (header.usage.offset + 24) .. ',0,254]}}' end)
  refused("a context span past the end", function() held.index = '{"days":{"2026-07-21":[0,144,0,' .. (#contextBytes + 10) .. ']}}' end)
  refused("a day larger than the limit", function() R.DAY_READ_LIMIT = 100 end)
  R.DAY_READ_LIMIT = 4 * 1024 * 1024
  refused("a missing context cut", function() held.context = nil end)
  refused("a usage log that cannot be opened", function() e = env(4096, { open = function() return nil end }) end)
  e = env(4096)
end

os.execute("rm -rf " .. SCRATCH)
report[#report + 1] = string.format("passed=%d failed=%d", passed, failed)
return table.concat(report, "\n")
