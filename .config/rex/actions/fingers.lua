-- Letter hints over paths, URLs, and hashes in the focused pane; see
-- ~/dev/rex-fingers. A hint copies the pick, Shift pastes, Ctrl opens.
-- The key is in key_bindings.lua.
local home = os.getenv("HOME")
local fingers = dofile(home .. "/dev/rex-fingers/lua/rex-fingers/init.lua")
fingers.setup{
  binary = home .. "/dev/rex-fingers/bin/rex-fingers",
  -- Testing: plain chords beside the ctrl+b ones in key_bindings.lua.
  key = "alt+f",
  -- Window scope needs the key mode and its popup; off for now.
  -- window_key = "alt+shift+f",
  -- Theme palette slots: hints on bright red (9), the match in red (1).
  -- Both follow the Rex theme.
  hint_style = "1;38;5;0;48;5;9",
  highlight_style = "1;38;5;1",
  -- A floating pane over the pane: no key list popup, two rows hidden.
  -- "pane" draws in the pane itself, but Rex shows its key list popup.
  overlay = "float",
}
