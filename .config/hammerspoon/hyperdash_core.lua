-- Pure helpers for hyperdash.lua. Loading this file has no side effects:
-- no webview, watcher, timer or global. `hs` is touched only inside
-- R.defaultEnv(), which the host calls; the tests inject their own.
--
-- Sections:
--   1. validation of bindings.json entries and insights.json (stage A)
--   2. incremental log reader (stage B), retention cuts
--   3. context log: line format and the recorder

local R = {}

---------------------------------------------------------------------------
-- 1. Validation
---------------------------------------------------------------------------

local function isArray(value)
  return type(value) == "table" and (#value > 0 or next(value) == nil)
end

local function isOptionalString(value)
  return value == nil or type(value) == "string"
end

-- Accepts a decoded version 2 insights report: { version = 2, month = "YYYY-MM",
-- insights = [...] }. Returns true, or false and a message for the health object.
function R.checkInsights(decoded)
  if type(decoded) ~= "table" then return false, "insights.json is not a JSON object" end
  if decoded.version ~= 2 and decoded.version ~= 3 then
    return false, "insights.json is version " .. tostring(decoded.version) .. ", expected 2 or 3"
  end
  if type(decoded.month) ~= "string" then return false, "insights.json has no month" end
  if not isArray(decoded.insights) then return false, "insights.json insights is not an array" end
  return true
end

-- Keeps the entries whose layer, key and label are strings and whose app
-- and site are absent or strings. Returns the valid list and the number of
-- dropped entries, or nil when `list` is not an array.
function R.sanitizeBindings(list)
  if not isArray(list) then return nil end
  local valid, dropped = {}, 0
  for _, entry in ipairs(list) do
    if type(entry) == "table"
      and type(entry.layer) == "string"
      and type(entry.key) == "string"
      and type(entry.label) == "string"
      and isOptionalString(entry.app)
      and isOptionalString(entry.site)
    then
      valid[#valid + 1] = entry
    else
      dropped = dropped + 1
    end
  end
  return valid, dropped
end

---------------------------------------------------------------------------
-- 2. Incremental log reader
--
-- A reader state tracks what the page has acknowledged:
--   generation  id of the log generation the page holds
--   offset      bytes [0, offset) are in the page; always ends after a "\n"
--   dev, ino    identity of the file those bytes came from
--   needReset   the page content is unknown or suspect: next plan is a reset
--   status      "ok" | "missing"
--
-- plan() reads the file and changes the state only to set needReset when it
-- finds the file changed under it. The host delivers the action, then calls
-- commit() on `ok: true` or fail() on anything else.
---------------------------------------------------------------------------

local DEFAULT_CHUNK = 1024 * 1024

function R.newState()
  return { generation = 0, offset = 0, dev = nil, ino = nil, needReset = true, status = "ok" }
end

-- env = { stat = function(path) -> {dev, ino, size, modification} | nil,
--         open = io.open, chunk = bytes per read call }
function R.defaultEnv()
  return { stat = hs.fs.attributes, open = io.open, chunk = DEFAULT_CHUNK }
end

-- Reads bytes [from, to) of `path`. Returns the string, or nil and a message
-- when the file cannot be opened or holds fewer bytes than expected.
local function readRange(env, path, from, to)
  local file = env.open(path, "rb")
  if not file then return nil, "cannot open " .. path end
  local parts, remaining = {}, to - from
  local ok, seekError = file:seek("set", from)
  if not ok then
    file:close()
    return nil, "seek failed: " .. tostring(seekError)
  end
  local chunk = env.chunk or DEFAULT_CHUNK
  while remaining > 0 do
    local piece = file:read(math.min(chunk, remaining))
    if not piece or #piece == 0 then
      file:close()
      return nil, "short read"
    end
    parts[#parts + 1] = piece
    remaining = remaining - #piece
  end
  file:close()
  return table.concat(parts)
end

-- Position of the last "\n" in `text`, or 0.
local function lastNewline(text)
  for i = #text, 1, -1 do
    if text:byte(i) == 10 then return i end
  end
  return 0
end

local function sameIdentity(a, b)
  return a and b and a.dev == b.dev and a.ino == b.ino
end

-- Retention (docs/RETENTION.md). A manifest written by the insights tool
-- names a cut in each log: bytes [0, offset) are archived and summarised
-- there, the tail starts at the offset. A cut is used only when the file has
-- the cut's (dev, ino), holds at least `offset` bytes, and the line
-- `lastLine` ends exactly at `offset`; otherwise the log is read from 0.
R.RETENTION_VERSION = 1

local function isCut(cut)
  return type(cut) == "table" and type(cut.dev) == "number" and type(cut.ino) == "number"
    and math.type(cut.offset) == "integer" and cut.offset > 0 and type(cut.lastLine) == "string"
end

-- Accepts a decoded manifest. `now` is "YYYY-MM-DDTHH:MM:SS": a clock set back
-- before the tail start makes the whole log the safe reading. Returns true, or
-- false and a message.
function R.checkRetention(decoded, now)
  if type(decoded) ~= "table" then return false, "retention manifest is not a JSON object" end
  if decoded.version ~= R.RETENTION_VERSION then
    return false, "retention manifest is version " .. tostring(decoded.version) .. ", expected " .. R.RETENTION_VERSION
  end
  if type(decoded.tailStart) ~= "string" or not decoded.tailStart:match("^%d%d%d%d%-%d%d%-01T00:00:00$") then
    return false, "retention manifest has no tail start"
  end
  if now < decoded.tailStart then return false, "the clock is before the retention tail start" end
  if not isCut(decoded.usage) then return false, "retention manifest has no usage cut" end
  if decoded.context ~= nil and not isCut(decoded.context) then return false, "retention manifest has a bad context cut" end
  return true
end

-- "YYYY-MM-01T00:00:00" of the month that holds the day 31 days before `date`
-- (os.date("*t") fields). The insights tool computes the same (Retention.swift).
function R.retentionTailStart(date)
  local day = os.date("*t", os.time({ year = date.year, month = date.month, day = date.day - 31, hour = 12 }))
  return string.format("%04d-%02d-01T00:00:00", day.year, day.month)
end

-- The offset to read `path` from: the cut's offset when it belongs to the
-- file whose attributes are `stat`, else 0.
function R.cutOffset(cut, env, path, stat)
  if not isCut(cut) or not stat or stat.dev ~= cut.dev or stat.ino ~= cut.ino or stat.size < cut.offset then return 0 end
  local expected = cut.lastLine .. "\n"
  local lineStart = cut.offset - #expected
  if lineStart < 0 then return 0 end
  -- The archived line, and the byte before it, which must end the line before.
  local raw = readRange(env, path, math.max(lineStart - 1, 0), cut.offset)
  if not raw or raw:sub(-#expected) ~= expected then return 0 end
  if lineStart > 0 and raw:byte(1) ~= 10 then return 0 end
  return cut.offset
end

-- A fresh reset action: complete lines of bytes [from, size), where `from` is
-- the retention cut of `base` = { cut, archive } when it applies, else 0.
-- `archive` (the manifest's JSON text) goes with the action only when the cut
-- was used.
local function planReset(state, env, path, stat, base)
  local from = base and R.cutOffset(base.cut, env, path, stat) or 0
  local raw, err = readRange(env, path, from, stat.size)
  if not raw then return { kind = "error", message = err } end
  local cut = lastNewline(raw)
  return {
    kind = "reset",
    generation = state.generation + 1,
    text = raw:sub(1, cut),
    offset = from + cut,
    from = from,
    archive = from > 0 and base.archive or nil,
    dev = stat.dev,
    ino = stat.ino,
    size = stat.size,
    status = "ok",
  }
end

-- File identity. A file is "the same" when its (dev, ino) match the ones
-- recorded at the last reset and its size has not shrunk below the offset.
-- Replacing the log by rename (write elsewhere, mv over it) gives a new inode,
-- so it always starts a new generation. Two further guards catch what
-- (dev, ino) cannot: a size below the offset (truncation), and the byte at
-- offset-1, which must still be the "\n" that ended the last consumed line
-- (an in-place rewrite that kept the inode and grew the file).
--
-- Returns one of:
--   { kind = "none" }                       nothing new (a partial line stays unread)
--   { kind = "reset", generation, text, offset, from, archive, dev, ino, size, status }
--                                           text holds bytes [from, offset)
--   { kind = "append", generation, from, to, text }
--   { kind = "error", message }             read failed; state unchanged
--   { kind = "retry" }                      file changed during the read; plan again
-- `base` = { cut, archive } is the retention cut a reset may start from (nil: 0).
function R.plan(state, env, path, base)
  local stat = env.stat(path)
  if not stat then
    if state.status == "missing" and not state.needReset then return { kind = "none" } end
    return {
      kind = "reset", generation = state.generation + 1, text = "", offset = 0,
      dev = nil, ino = nil, size = 0, status = "missing",
    }
  end

  if state.needReset or state.status == "missing" or not sameIdentity(state, stat) or stat.size < state.offset then
    local action = planReset(state, env, path, stat, base)
    if action.kind ~= "reset" then return action end
    local after = env.stat(path)
    if not sameIdentity(stat, after) or after.size < action.offset then
      return { kind = "retry" }
    end
    return action
  end

  if stat.size == state.offset then return { kind = "none" } end

  -- Read one byte before the offset as well: it must be the "\n" that ended
  -- the last consumed line. Anything else means the file was rewritten.
  local from = math.max(state.offset - 1, 0)
  local raw, err = readRange(env, path, from, stat.size)
  if not raw then return { kind = "error", message = err } end
  local skip = state.offset - from
  if skip == 1 and raw:byte(1) ~= 10 then
    state.needReset = true
    return { kind = "retry" }
  end
  local fresh = raw:sub(skip + 1)
  local cut = lastNewline(fresh)
  if cut == 0 then return { kind = "none" } end

  local after = env.stat(path)
  if not sameIdentity(stat, after) or after.size < state.offset + cut then
    state.needReset = true
    return { kind = "retry" }
  end
  return {
    kind = "append",
    generation = state.generation,
    from = state.offset,
    to = state.offset + cut,
    text = fresh:sub(1, cut),
  }
end

-- Record that the page acknowledged `action` with ok = true.
function R.commit(state, action)
  if action.kind == "reset" then
    state.generation = action.generation
    state.offset = action.offset
    state.dev, state.ino = action.dev, action.ino
    state.status = action.status
    state.needReset = false
  elseif action.kind == "append" and action.from == state.offset then
    state.offset = action.to
  else
    state.needReset = true
  end
end

-- Delivery failed, was rejected, or the callback never reported ok.
function R.fail(state)
  state.needReset = true
end

---------------------------------------------------------------------------
-- 3. Context log
--
-- ~/.local/state/hyperdash/context.log, one event per line:
--   YYYY-MM-DDTHH:MM:SS.mmm<TAB>kind<TAB>value<LF>   (local time)
-- kind is app (value: a bundle ID), or lock, unlock, sleep, wake, start
-- (value: "-"). No window titles, URLs, keys or names are ever written.
---------------------------------------------------------------------------

R.CONTEXT_KINDS = { app = true, lock = true, unlock = true, sleep = true, wake = true, start = true }

-- "2026-10-16T09:30:12.045" for an epoch time with a fraction of a second.
function R.contextTime(epoch)
  local seconds = math.floor(epoch)
  local millis = math.floor((epoch - seconds) * 1000 + 0.5)
  if millis >= 1000 then seconds, millis = seconds + 1, 0 end
  return os.date("%Y-%m-%dT%H:%M:%S", seconds) .. string.format(".%03d", millis)
end

-- A bundle ID is reverse-DNS text. Anything else could break the line format.
function R.validBundleId(value)
  return type(value) == "string" and #value > 0 and #value <= 255 and value ~= "-" and value:match("^[%w%.%-_]+$") ~= nil
end

-- The line to append, or nil and a reason.
function R.contextLine(epoch, kind, value)
  if not R.CONTEXT_KINDS[kind] then return nil, "unknown kind " .. tostring(kind) end
  if kind == "app" then
    if not R.validBundleId(value) then return nil, "invalid bundle ID" end
  else
    value = "-"
  end
  return R.contextTime(epoch) .. "\t" .. kind .. "\t" .. value .. "\n"
end

-- env = { path, now = function() -> epoch with fraction, open = io.open,
--         ensureDirectory = function(path), stat = hs.fs.attributes,
--         frontApp = function() -> bundle ID or nil }
-- Each event opens the file, appends one line and closes it, so a log that
-- was deleted or replaced is recreated on the next event. Readers attribute
-- app events only after a start line, so the first write, a write after a
-- failure, and a write to a new file (missing, another (dev, ino), or shorter
-- than after the last write) begin with start and the front app.
function R.newRecorder(env)
  local recorder = { lastApp = nil, written = 0, failed = 0, lastError = nil }
  local directory = env.path:match("^(.*)/[^/]+$")
  local needStart, dev, ino, size = true, nil, nil, 0

  function recorder.write(kind, value)
    local now = env.now()
    local line, reason = R.contextLine(now, kind, value)
    if not line then
      recorder.lastError = reason
      return false
    end
    local stat = env.stat and env.stat(env.path)
    local seeded = nil
    -- A smaller file was truncated in place: same (dev, ino), start lost.
    if env.stat and (not stat or stat.dev ~= dev or stat.ino ~= ino or stat.size < size) then needStart = true end
    if needStart and kind ~= "start" then
      local prefix = R.contextLine(now, "start")
      if kind ~= "app" and env.frontApp then
        local bundleId = env.frontApp()
        local front = R.contextLine(now, "app", bundleId)
        if front then prefix, seeded = prefix .. front, bundleId end
      end
      line = prefix .. line
    end
    if env.ensureDirectory then env.ensureDirectory(directory) end
    local file = env.open(env.path, "ab")
    if not file then
      recorder.failed = recorder.failed + 1
      recorder.lastError = "cannot open " .. env.path
      needStart = true
      return false
    end
    local wrote = file:write(line)
    -- Buffered output can fail only at close, after write looked fine.
    local closed = file:close()
    if not wrote or not closed then
      recorder.failed = recorder.failed + 1
      recorder.lastError = (wrote and "cannot close " or "cannot write ") .. env.path
      needStart = true
      return false
    end
    recorder.written = recorder.written + 1
    needStart = false
    if seeded then recorder.lastApp = seeded end
    stat = env.stat and env.stat(env.path)
    if stat then dev, ino, size = stat.dev, stat.ino, stat.size end
    return true
  end

  -- Repeated activation of the same app is one event.
  function recorder.app(bundleId)
    if bundleId == recorder.lastApp then return false end
    if recorder.write("app", bundleId) then
      recorder.lastApp = bundleId
      return true
    end
    return false
  end

  return recorder
end

-- Seconds to wait before the insights tool runs again after `failures`
-- failures in a row: 5 minutes after one, 30 minutes after two or more.
R.INSIGHTS_RETRY_FIRST = 300
R.INSIGHTS_RETRY_LATER = 1800
function R.insightsBackoff(failures)
  if failures <= 0 then return 0 end
  if failures == 1 then return R.INSIGHTS_RETRY_FIRST end
  return R.INSIGHTS_RETRY_LATER
end

-- Order-independent text for a bundle ID to name map, to see whether it changed.
function R.mapSignature(map)
  local keys = {}
  for key in pairs(map) do keys[#keys + 1] = key end
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do parts[#parts + 1] = key .. "=" .. tostring(map[key]) end
  return table.concat(parts, "\n")
end

return R
