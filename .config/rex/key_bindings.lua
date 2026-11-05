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
rex.bind(p .. "shift+f", "rex_fingers")
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
