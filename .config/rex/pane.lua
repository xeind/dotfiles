-- Helpers shared by the actions.
local pane = {}

pane.terminal = "com.superlogical.terminal"

-- The focused pane's folder: what its shell last reported (OSC 7), else
-- where its foreground process is.
function pane.directory(ctx)
  if not ctx.block_id then return nil end
  local target = { session_id = ctx.session_id, block_id = ctx.block_id }
  local status = rex.block.call(pane.terminal, "pwd", target)
  local path = status and status.pwd or ""
  path = path:match("^file://[^/]*(/.*)$") or path
  path = path:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
  if path ~= "" then return path end
  local proc = rex.block.call(pane.terminal, "process", target)
  return proc and proc.foreground and proc.foreground.cwd or nil
end

-- A command in a floating pane over the window, like a tmux popup. The
-- pane closes when the command exits.
function pane.popup(label, command, bounds, cwd)
  local layer, err = rex.session.new_layer{
    bounds = bounds,
    focus  = true,
    layout = rex.layout.block{
      flavor  = pane.terminal .. ".shell",
      label   = label,
      options = { command = command, cwd = cwd, exit = { on_completion = true } },
    },
  }
  if err ~= nil then error(err, 0) end
  return { layer_id = layer.layer_id }
end

return pane
