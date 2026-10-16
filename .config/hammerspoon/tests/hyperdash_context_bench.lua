-- Cost of recording one context event, and of building the app-name map.
--   hs -t 120 -c 'return dofile(os.getenv("HOME").."/.config/hammerspoon/tests/hyperdash_context_bench.lua")'
-- Writes only under $TMPDIR/hyperdash_tests/ctxbench/. Reads app bundles and
-- the running-app list (read-only). Creates no timer, watcher or webview.

local DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$") .. "/.."
local SCRATCH = ((os.getenv("TMPDIR") or "/tmp"):gsub("/$", "")) .. "/hyperdash_tests/ctxbench"
local R = dofile(DIR .. "/hyperdash_core.lua")
os.execute("rm -rf " .. SCRATCH .. " && mkdir -p " .. SCRATCH)
local clock = hs.timer.secondsSinceEpoch
local SAMPLES, EVENTS = 20, 500

local function stats(samples)
  table.sort(samples)
  local function pick(p) return samples[math.max(1, math.ceil(#samples * p))] end
  return pick(0.5), pick(0.95)
end
local out = { string.format("%d samples per row; each sample is the mean over %d events; microseconds per event", SAMPLES, EVENTS) }
local function row(name, perEvent)
  local median, p95 = stats(perEvent)
  out[#out + 1] = string.format("%-58s median %7.1f us   p95 %7.1f us", name, median * 1e6, p95 * 1e6)
end

-- 1. The shipped recorder: open, append one line, close, per event.
do
  local recorder = R.newRecorder({
    path = SCRATCH .. "/shipped.log", now = clock, open = io.open,
    ensureDirectory = function(d) if not hs.fs.attributes(d) then hs.fs.mkdir(d) end end,
  })
  local samples = {}
  for _ = 1, SAMPLES do
    local t0 = clock()
    for i = 1, EVENTS do recorder.app(i % 2 == 0 and "com.apple.finder" or "com.mitchellh.ghostty") end
    samples[#samples + 1] = (clock() - t0) / EVENTS
  end
  row("recorder.app: open + append + close (shipped)", samples)
  local f = io.open(SCRATCH .. "/shipped.log", "rb"); local text = f:read("a"); f:close()
  out[#out + 1] = string.format("   shipped file: %d lines, %d bytes (%d bytes/line)", select(2, text:gsub("\n", "")), #text, #text // select(2, text:gsub("\n", "")))
end

-- 2. A deduplicated repeat (same app again): no file access at all.
do
  local recorder = R.newRecorder({ path = SCRATCH .. "/dedupe.log", now = clock, open = io.open })
  recorder.app("com.apple.finder")
  local samples = {}
  for _ = 1, SAMPLES do
    local t0 = clock()
    for _ = 1, EVENTS do recorder.app("com.apple.finder") end
    samples[#samples + 1] = (clock() - t0) / EVENTS
  end
  row("recorder.app: repeated app (skipped)", samples)
end

-- 3. Alternative: one open handle, flush per event.
do
  local file = io.open(SCRATCH .. "/handle.log", "ab")
  local samples = {}
  for _ = 1, SAMPLES do
    local t0 = clock()
    for i = 1, EVENTS do
      file:write(R.contextLine(clock(), "app", "com.apple.finder"))
      file:flush()
    end
    samples[#samples + 1] = (clock() - t0) / EVENTS
  end
  file:close()
  row("alternative: held handle + flush per event", samples)
end

-- 4. Formatting alone.
do
  local samples = {}
  for _ = 1, SAMPLES do
    local t0 = clock()
    for _ = 1, EVENTS do R.contextLine(clock(), "app", "com.apple.finder") end
    samples[#samples + 1] = (clock() - t0) / EVENTS
  end
  row("contextLine only (format + validate)", samples)
end

-- 5. Building the bundle ID -> name map, as the host does it.
do
  local folders = { "/Applications", "/System/Applications", os.getenv("HOME") .. "/Applications", "/System/Library/CoreServices" }
  local function scan()
    local map, bundles = {}, 0
    for _, folder in ipairs(folders) do
      local ok, iterate, directory = pcall(hs.fs.dir, folder)
      if ok and iterate then
        for entry in iterate, directory do
          if entry:sub(-4) == ".app" then
            bundles = bundles + 1
            local info = hs.application.infoForBundlePath(folder .. "/" .. entry)
            local id = info and info.CFBundleIdentifier
            if R.validBundleId(id) then map[id] = info.CFBundleDisplayName or info.CFBundleName or entry:sub(1, -5) end
          end
        end
      end
    end
    return map, bundles
  end
  local samples, bundles, mapped = {}, 0, 0
  for _ = 1, 5 do
    local t0 = clock()
    local map, n = scan()
    samples[#samples + 1] = clock() - t0
    bundles, mapped = n, 0
    for _ in pairs(map) do mapped = mapped + 1 end
  end
  local median, p95 = stats(samples)
  out[#out + 1] = string.format("%-58s median %7.1f ms   max %7.1f ms   (%d bundles, %d IDs; once per Hammerspoon start)", "installed-app scan (5 samples)", median * 1e3, p95 * 1e3, bundles, mapped)

  local running = {}
  for _ = 1, SAMPLES do
    local t0 = clock()
    local names = {}
    for _, app in ipairs(hs.application.runningApplications()) do
      local id = app:bundleID()
      if R.validBundleId(id) and app:name() then names[id] = app:name() end
    end
    running[#running + 1] = clock() - t0
  end
  local m, p = stats(running)
  out[#out + 1] = string.format("%-58s median %7.2f ms   p95 %7.2f ms   (every sync)", "running-app names", m * 1e3, p * 1e3)
end

os.execute("rm -rf " .. SCRATCH)
return table.concat(out, "\n")
