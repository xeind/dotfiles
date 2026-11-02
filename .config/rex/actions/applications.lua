-- Programs that open in a floating pane.
local pane = require("pane")

local large = { 0.1, 0.1, 0.8, 0.8 }

rex.action{
  name  = "lazygit",
  title = "Open lazygit",
  run   = function(ctx) return pane.popup("lazygit", { "lazygit" }, large, pane.directory(ctx)) end,
}

-- Pick a folder zoxide knows and go to its session; see rex_session_finder.
rex.action{
  name  = "finder",
  title = "Open Session for Folder",
  keywords = "session project zoxide",
  run   = function(ctx)
    return pane.popup("sessions", { os.getenv("HOME") .. "/.local/bin/rex_session_finder" }, { 0.15, 0.3, 0.7, 0.4 })
  end,
}
