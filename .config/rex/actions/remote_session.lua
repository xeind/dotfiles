-- Sessions whose panes live on another machine. A new pane or tab in a
-- session listed here starts ssh to its host instead of a local shell.
-- Session label -> ssh host, as named in ~/.ssh/config.
local pane = require("pane")

local hosts = { cordovan = "cordovan" }

local function remote_host()
  local view = rex.session.view{}
  return view and hosts[view.label]
end

local function shell_block(host)
  return rex.layout.block{
    flavor  = pane.terminal .. ".shell",
    options = { command = { "ssh", host } },
  }
end

rex.action{
  name  = "split_pane",
  title = "Split Pane",
  description = "Split the pane; in a remote session the new pane opens ssh.",
  args  = { direction = "string" },
  run   = function(ctx, args)
    local host = remote_host()
    if not host then return rex.client.queue("pane.split", { direction = args.direction }) end
    local _, err = rex.session.new_split{
      anchor_id = ctx.block_id,
      direction = args.direction == "down" and "vertical" or "horizontal",
      side      = "after",
      focus     = true,
      layout    = shell_block(host),
    }
    if err ~= nil then error(err, 0) end
  end,
}

rex.action{
  name  = "new_tab",
  title = "New Tab",
  description = "Open a tab; in a remote session it opens ssh.",
  run   = function(ctx)
    local host = remote_host()
    if not host then return rex.client.queue("client.tab.new") end
    local _, err = rex.session.new_window{ layout = shell_block(host) }
    if err ~= nil then error(err, 0) end
  end,
}
