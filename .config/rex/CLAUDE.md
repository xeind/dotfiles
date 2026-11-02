# rex

Rex config is Lua 5.1. `init.lua` only loads the other files with `require`:

- `pane.lua`: helpers shared by the actions.
- `actions/applications.lua`: lazygit and the session finder.
- `actions/copy_mode.lua`: the scrollback in nvim, through `rex_copy_mode`.
- `actions/tab_navigation.lua`: tab steps across sessions.
- `key_bindings.lua`: every key binding.

Each action file defines its own actions and returns nothing. Shell work
goes in a script in `.local/bin`, not in a Lua string.

App settings are macOS defaults; see `apply_rex_defaults` in `.local/bin`.

## Change and test

1. Edit the file that owns the change.
2. `rex config check` loads it and counts bindings and actions.
3. `rex config reload`. The server reads it again; no restart.
4. `rex do NAME -b "$REX_BLOCK"` runs an action as if from this pane.
   `rex do ~/.config/rex/init.lua --action NAME` tries one without
   reloading.
   Actions that open a pane return its `layer_id`; close it after the
   test with `rex api call session.close_layer`.
5. `rex server logs` shows Lua errors the check misses.

Client actions from the CLI, such as `session.select`, need Remote
Control on in Rex Settings > Rex Server.

Docs: `curl -s https://www.superlogical.com/rex/docs/reference/lua.md`.
Rex is in beta and the API moves between builds.
