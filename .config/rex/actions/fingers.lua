-- Letter hints over paths, URLs, and hashes in the focused pane; see
-- ~/dev/rex-fingers. A hint copies the pick, Shift pastes, Ctrl opens.
-- The key is in key_bindings.lua.
local home = os.getenv("HOME")
local fingers = dofile(home .. "/dev/rex-fingers/lua/rex-fingers/init.lua")
fingers.setup{
  binary = home .. "/dev/rex-fingers/bin/rex-fingers",
  key = false,
  -- Theme palette slot 13, the bright magenta, follows the Rex theme.
  hint_style = "1;38;5;0;48;5;13",
  highlight_style = "1;38;5;13",
}
