-- Rex reads this on `rex config reload`. The actions show in the command
-- palette and run with `rex do NAME`. Keys follow herdr: ctrl+b prefix.
require("actions.applications")
require("actions.copy_mode")
require("actions.tab_navigation")
require("actions.fingers")
require("actions.remote_session")
require("key_bindings")
-- rex-undo begin
do
  local ok, err = pcall(function()
    dofile("/Users/xein/dev/rex-undo-extension/rex-undo/undo.lua").setup{
      dir = "/Users/xein/dev/rex-undo-extension/rex-undo",
      rex = "/Users/xein/.local/bin/rex",
      key = "cmd+shift+t",
      history = 50,
    }
  end)
  if not ok then rex.log("rex-undo: not loaded: " .. tostring(err)) end
end
-- rex-undo end
