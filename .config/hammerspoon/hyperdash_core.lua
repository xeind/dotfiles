-- Pure helpers for hyperdash.lua. Loading this file has no side effects:
-- no webview, watcher, timer or global. `hs` is touched only inside
-- R.defaultEnv(), which the host calls; the tests inject their own.
--
-- Sections:
--   1. validation of bindings.json entries and insights.json (stage A)

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
  if decoded.version ~= 2 then
    return false, "insights.json is version " .. tostring(decoded.version) .. ", expected 2"
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

return R
