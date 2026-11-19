-- Letter hints over paths, URLs, and hashes in the focused pane; see
-- ~/dev/rex-fingers. A hint copies the pick, Shift pastes, Ctrl shows it
-- in Finder or the browser.
-- The key is in key_bindings.lua.
local home = os.getenv("HOME")
local fingers = dofile(home .. "/dev/rex-fingers/lua/rex-fingers/init.lua")
fingers.setup{
  binary = home .. "/dev/rex-fingers/bin/rex-fingers",
  -- Testing: plain chords beside the ctrl+b ones in key_bindings.lua.
  key = "alt+f",
  -- Hints in every pane of the window at once.
  window_key = "alt+shift+f",
  -- Theme palette slots: hints on bright red (9), the match in red (1).
  -- Both follow the Rex theme.
  hint_style = "1;38;5;0;48;5;9",
  highlight_style = "1;38;5;1",
  -- "pane" draws in the pane itself, with no key mode and no key list.
  -- "float" opens a floating pane over it, two rows shorter.
  overlay = "pane",
  -- Hint the rows a scrolled pane shows, not its live screen. Each
  -- trigger flashes copy mode and saves and restores the clipboard.
  follow_scroll = true,
  -- Ctrl+hint: a URL to the browser, a folder or file to Finder.
  ctrl_action = ":reveal:",
  -- Show the pick in reverse video for 150 ms.
  flash = true,
}
