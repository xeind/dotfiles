-- Copy mode: write the pane's scrollback to a file and open it with
-- rex_copy_mode, over the whole window. Rex has no scroll action of its own.
local pane = require("pane")

local function scrollback(ctx)
  local target = { session_id = ctx.session_id, block_id = ctx.block_id }
  local args = { format = "text", trim = true, unwrap = true, max_bytes = 983040 }
  for k, v in pairs(target) do args[k] = v end
  local r, err = rex.block.call(pane.terminal, "format", args)
  if not r then error(err, 0) end
  local parts, offset = { r.content }, #r.content
  while r.id and not r.eof do
    r, err = rex.block.call(pane.terminal, "blob_read", { session_id = ctx.session_id, block_id = ctx.block_id, id = r.id, offset = offset })
    if not r then error(err, 0) end
    parts[#parts + 1] = r.data
    offset = offset + #r.data
  end
  return table.concat(parts)
end

rex.action{
  name  = "copy_mode",
  title = "Copy Mode",
  keywords = "scrollback history copy yank search",
  run   = function(ctx)
    if not ctx.block_id then error("Copy Mode: no focused pane", 0) end
    local path = os.tmpname()
    local f = assert(io.open(path, "w"))
    f:write(scrollback(ctx))
    f:close()
    local command = { os.getenv("HOME") .. "/.local/bin/rex_copy_mode", path, ctx.session_id, ctx.block_id }
    return pane.popup("copy", command, { 0, 0, 1, 1 }, pane.directory(ctx))
  end,
}
