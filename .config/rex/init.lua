-- Rex reads this on `rex config reload`. The actions show in the command
-- palette and run with `rex do NAME`. No keys bound yet.
local terminal = "com.superlogical.terminal"

-- The focused pane's folder: what its shell last reported (OSC 7), else
-- where its foreground process is.
local function pane_dir(ctx)
  if not ctx.block_id then return nil end
  local target = { session_id = ctx.session_id, block_id = ctx.block_id }
  local status = rex.block.call(terminal, "pwd", target)
  local path = status and status.pwd or ""
  path = path:match("^file://[^/]*(/.*)$") or path
  path = path:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
  if path ~= "" then return path end
  local proc = rex.block.call(terminal, "process", target)
  return proc and proc.foreground and proc.foreground.cwd or nil
end

-- A command in a floating pane over the window, like a tmux popup. The
-- pane closes when the command exits.
local function popup(label, command, bounds, cwd)
  local layer, err = rex.session.new_layer{
    bounds = bounds,
    focus  = true,
    layout = rex.layout.block{
      flavor  = terminal .. ".shell",
      label   = label,
      options = { command = command, cwd = cwd, exit = { on_completion = true } },
    },
  }
  if err ~= nil then error(err, 0) end
  return { layer_id = layer.layer_id }
end

local large = { 0.1, 0.1, 0.8, 0.8 }

rex.action{
  name  = "lazygit",
  title = "Open lazygit",
  run   = function(ctx) return popup("lazygit", { "lazygit" }, large, pane_dir(ctx)) end,
}

rex.action{
  name  = "vallow",
  title = "Open vallow",
  run   = function(ctx) return popup("vallow", { "vallow" }, large, pane_dir(ctx)) end,
}

-- Pick a folder zoxide knows and go to its session; see rex_session_finder.
rex.action{
  name  = "finder",
  title = "Open Session for Folder",
  keywords = "session project zoxide",
  run   = function(ctx)
    return popup("sessions", { os.getenv("HOME") .. "/.local/bin/rex_session_finder" }, { 0.15, 0.3, 0.7, 0.4 })
  end,
}
