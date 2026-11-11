-- Put text that a program copies with OSC 52 on the Mac clipboard. Rex
-- parses the escape and raises clipboard_written, but the app doesn't
-- apply it, so programs over ssh copy into nothing. Runs for every session:
--   rex do ~/.config/rex/clipboard_sync.lua --all
-- A launch agent keeps it running; see com.xein.rex-clipboard-sync.plist.
local terminal = "com.superlogical.terminal"

-- The event carries the text when it is small. Larger copies are read back
-- from the server, which keeps each one for about a minute.
local function copied_text(ctx, ev)
  if ev.text and #ev.text >= (ev.bytes or 0) then return ev.text end
  local parts, offset = {}, 0
  repeat
    local r, err = rex.block.call(terminal, "clipboard_read", {
      session_id = ctx.session_id, block_id = ctx.block_id,
      id = ev.id, offset = offset, max_bytes = 983040,
    })
    if not r then error(err, 0) end
    parts[#parts + 1] = r.data
    offset = offset + #r.data
  until r.eof
  return table.concat(parts)
end

rex.on("terminal.clipboard_written", function(ctx, ev)
  local text = copied_text(ctx, ev)
  local r, err = rex.exec({ "/usr/bin/pbcopy" }, { stdin = text, timeout = 5 })
  if not r then error(err, 0) end
  if not r.ok then error("pbcopy failed: " .. r.stderr, 0) end
end)
