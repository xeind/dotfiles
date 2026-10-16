-- Lua-side benchmark: whole-file read (baseline) against the incremental reader.
--   hs -t 600 -c 'return dofile(os.getenv("HOME").."/.config/hammerspoon/tests/hyperdash_core_bench.lua")'
-- Generates logs in $TMPDIR/hyperdash_tests/bench/ in the real line
-- format. Never touches the real log. Creates no timer, watcher or webview.
--
-- Per scenario it times the work the host does before it hands a string to
-- evaluateJavaScript: reading bytes and JSON-encoding the text. Page-side
-- parsing and rendering are not included.

local SAMPLES = 20
local SIZES = { 4000, 100000, 500000 }
local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$") .. "/.."
local SCRATCH = ((os.getenv("TMPDIR") or "/tmp"):gsub("/$", "")) .. "/hyperdash_tests/bench"
local R = dofile(DIR .. "/hyperdash_core.lua")
local LOG = SCRATCH .. "/usage.log"
os.execute("rm -rf " .. SCRATCH .. " && mkdir -p " .. SCRATCH)

local clock = hs.timer.secondsSinceEpoch

local function jsonString(value) return hs.json.encode({ value }):sub(2, -2) end

local function line(i)
  local day = 1 + (i // 3000) % 28
  local second = i % 86400
  return string.format("2026-09-%02dT%02d:%02d:%02d\t%s\t%s\n", day, (second // 3600) % 24, (second // 60) % 60, second % 60,
    string.char(97 + i % 26), string.char(97 + (i * 7) % 26))
end

local function writeLog(entries)
  local f = assert(io.open(LOG, "wb"))
  local batch = {}
  for i = 1, entries do
    batch[#batch + 1] = line(i)
    if #batch == 5000 then f:write(table.concat(batch)); batch = {} end
  end
  f:write(table.concat(batch))
  f:close()
end

local function appendTen(base)
  local f = assert(io.open(LOG, "ab"))
  for i = 1, 10 do f:write(line(base + i)) end
  f:close()
end

local function stats(samples)
  table.sort(samples)
  local function pick(p) return samples[math.max(1, math.ceil(#samples * p))] end
  return pick(0.5) * 1000, pick(0.95) * 1000
end

-- Baseline: what readData() did on every open.
local function baselineOpen()
  local t0 = clock()
  local f = io.open(LOG, "r")
  local text = f:read("a")
  f:close()
  local encoded = jsonString(text)
  return clock() - t0, #text, #encoded
end

local bytesRead = 0
local function countingEnv()
  return {
    stat = hs.fs.attributes,
    chunk = 1024 * 1024,
    open = function(path, mode)
      local f = io.open(path, mode)
      if not f then return nil end
      return setmetatable({}, { __index = function(_, k)
        if k == "read" then
          return function(_, n)
            local piece = f:read(n)
            if piece then bytesRead = bytesRead + #piece end
            return piece
          end
        end
        return function(_, ...) return f[k](f, ...) end
      end })
    end,
  }
end

local rows = {}
for _, entries in ipairs(SIZES) do
  writeLog(entries)
  local size = hs.fs.attributes(LOG, "size")

  -- 1. Full load: first open of a fresh page.
  local base, new = {}, {}
  local baseChars, newChars
  for _ = 1, SAMPLES do
    local t, _, chars = baselineOpen()
    base[#base + 1] = t
    baseChars = chars
  end
  local fullBytes
  for _ = 1, SAMPLES do
    local state, env = R.newState(), countingEnv()
    bytesRead = 0
    local t0 = clock()
    local action = R.plan(state, env, LOG)
    local encoded = jsonString(action.text)
    R.commit(state, action)
    new[#new + 1] = clock() - t0
    newChars, fullBytes = #encoded, bytesRead
  end
  local bm, bp = stats(base)
  local nm, np = stats(new)
  rows[#rows + 1] = { entries, size, "full load", bm, bp, nm, np, size, fullBytes, baseChars, newChars }

  -- 2. Unchanged reopen: nothing new in the file.
  base, new = {}, {}
  local state, env = R.newState(), countingEnv()
  R.commit(state, R.plan(state, env, LOG))
  local reopenBytes
  for _ = 1, SAMPLES do base[#base + 1] = (baselineOpen()) end
  for _ = 1, SAMPLES do
    bytesRead = 0
    local t0 = clock()
    local action = R.plan(state, env, LOG)
    new[#new + 1] = clock() - t0
    assert(action.kind == "none", action.kind)
    reopenBytes = bytesRead
  end
  bm, bp = stats(base)
  nm, np = stats(new)
  rows[#rows + 1] = { entries, size, "unchanged reopen", bm, bp, nm, np, size, reopenBytes, baseChars, 0 }

  -- 3. Append of 10 lines, then reopen.
  base, new = {}, {}
  local appendBytes, appendChars, counter = 0, 0, entries
  for _ = 1, SAMPLES do
    appendTen(counter)
    counter = counter + 10
    base[#base + 1] = (baselineOpen())
    bytesRead = 0
    local t0 = clock()
    local action = R.plan(state, env, LOG)
    assert(action.kind == "append", action.kind)
    local encoded = jsonString(action.text)
    R.commit(state, action)
    new[#new + 1] = clock() - t0
    appendBytes, appendChars = bytesRead, #encoded
  end
  bm, bp = stats(base)
  nm, np = stats(new)
  rows[#rows + 1] = { entries, size, "append 10 lines", bm, bp, nm, np, size, appendBytes, baseChars, appendChars }
end

local out = { string.format("samples=%d per cell; times in ms; baseline = whole-file read + JSON string encode", SAMPLES),
  "entries | log bytes | scenario | baseline median | baseline p95 | new median | new p95 | baseline bytes read | new bytes read | baseline string chars | new string chars" }
for _, r in ipairs(rows) do
  out[#out + 1] = string.format("%d | %d | %s | %.2f | %.2f | %.3f | %.3f | %d | %d | %d | %d", r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10], r[11])
end
os.execute("rm -rf " .. SCRATCH)
return table.concat(out, "\n")
