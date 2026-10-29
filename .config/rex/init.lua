-- Rex reads this on `rex config reload`. The actions show in the command
-- palette and run with `rex do NAME`. Keys follow herdr: ctrl+b prefix.
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

-- Pick a folder zoxide knows and go to its session; see rex_session_finder.
rex.action{
  name  = "finder",
  title = "Open Session for Folder",
  keywords = "session project zoxide",
  run   = function(ctx)
    return popup("sessions", { os.getenv("HOME") .. "/.local/bin/rex_session_finder" }, { 0.15, 0.3, 0.7, 0.4 })
  end,
}

-- Copy mode: the pane's scrollback in nvim over the window, at the end.
-- Search, yank and page there; q quits. Rex has no scroll action of its own.
local function scrollback(ctx)
  local target = { session_id = ctx.session_id, block_id = ctx.block_id }
  local args = { format = "text", trim = true, unwrap = true, max_bytes = 983040 }
  for k, v in pairs(target) do args[k] = v end
  local r, err = rex.block.call(terminal, "format", args)
  if not r then error(err, 0) end
  local parts, offset = { r.content }, #r.content
  while r.id and not r.eof do
    r, err = rex.block.call(terminal, "blob_read", { session_id = ctx.session_id, block_id = ctx.block_id, id = r.id, offset = offset })
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
    local nvim = 'nvim -R -c "normal! G" -c "nnoremap <buffer> q <Cmd>qa!<CR>" "$1"; rm -f "$1"'
    return popup("copy", { "sh", "-c", nvim, "sh", path }, { 0, 0, 1, 1 }, pane_dir(ctx))
  end,
}

-- Step through every tab of every session, in sidebar order, wrapping
-- at the ends. The last tab of a session leads to the next session.
local function step_tab(ctx, delta)
  local list, err = rex.call("session.list", {})
  if not list then error(err, 0) end
  local tabs, current = {}, nil
  for _, s in ipairs(list.sessions) do
    -- an action can read only the session it is attached to
    rex.call("session.attach", { session_id = s.session_id })
    local view = rex.call("session.view", { session_id = s.session_id })
    for _, w in ipairs(view and view.windows or {}) do
      tabs[#tabs + 1] = { session_id = s.session_id, window_id = w.window_id }
      if s.session_id == ctx.session_id and w.window_id == view.active_window_id then
        current = #tabs
      end
    end
  end
  rex.call("session.attach", { session_id = ctx.session_id })
  if #tabs == 0 then return end
  local t = tabs[((current or 1) - 1 + delta) % #tabs + 1]
  rex.client.queue("session.select", { session_id = t.session_id, window_id = t.window_id })
end

rex.action{ name = "tab_next", title = "Next Tab Across Sessions", run = function(ctx) step_tab(ctx, 1) end }
rex.action{ name = "tab_previous", title = "Previous Tab Across Sessions", run = function(ctx) step_tab(ctx, -1) end }

-- herdr's keys, prefix ctrl+b. A herdr workspace is a Rex session.
local p = "ctrl+b>"
rex.bind(p .. "ctrl+b", "pane.send_key", { key = "ctrl+b" })

rex.bind(p .. "c", "client.tab.new")
rex.bind(p .. "n", "client.tab.next")
rex.bind(p .. "p", "client.tab.previous")
rex.bind(p .. "shift+7", "client.tab.close")
rex.bind(p .. ",", "client.tab.rename")
rex.bind(p .. "shift+,", "client.tab.move.backward")
rex.bind(p .. "shift+.", "client.tab.move.forward")
for i = 1, 9 do
  rex.bind(p .. i, "client.tab.goto", { index = i })
end

rex.bind(p .. "shift+\\", "pane.split", { direction = "right" })
rex.bind(p .. "-", "pane.split", { direction = "down" })
rex.bind(p .. "x", "pane.close")
rex.bind(p .. "z", "pane.zoom")
rex.bind(p .. "[", "copy_mode")
-- Find previous on shift+cmd+g, as in every Mac app; Rex had Go to
-- Directory there, so it moves to ctrl+b d.
rex.bind("shift+cmd+g", "client.find.previous")
rex.bind(p .. "d", "pane.go_to_directory")
-- As in Ghostty: jump between shell prompts in the scrollback.
rex.bind("cmd+up", "client.prompt.previous")
rex.bind("cmd+down", "client.prompt.next")
rex.bind(p .. "tab", "pane.focus_next")
rex.bind(p .. "shift+tab", "pane.focus_previous")
for key, dir in pairs{ h = "left", j = "down", k = "up", l = "right" } do
  rex.bind(p .. key, "pane.focus", { direction = dir })
  rex.bind("resize/" .. key, "pane.resize", { direction = dir })
end
rex.mode("resize", { exclusive = true })
rex.bind(p .. "r", "client.mode.enter", { name = "resize" })

rex.bind(p .. "w", "session.switch")
rex.bind(p .. "s", "session.switch")
rex.bind(p .. "shift+n", "session.new")
rex.bind(p .. "shift+w", "session.rename")
rex.bind("alt+j", "tab_next")
rex.bind("alt+k", "tab_previous")
rex.bind("alt+h", "session.previous")
rex.bind("alt+l", "session.next")

rex.bind(p .. "g", "lazygit")
rex.bind(p .. "f", "finder")
rex.bind(p .. "b", "client.sidebar.toggle")
rex.bind(p .. "shift+;", "client.palette.toggle")
rex.bind(p .. "shift+r", "client.config.reload")
