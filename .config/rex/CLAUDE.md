# rex

`init.lua` is Rex's only config file: Lua 5.1, actions and key bindings.
App settings are macOS defaults; see `apply_rex_defaults` in `.local/bin`.

## Change and test

1. Edit `init.lua`.
2. `rex config check` loads it and counts bindings and actions.
3. `rex config reload`. The server reads it again; no restart.
4. `rex do NAME -b "$REX_BLOCK"` runs an action as if from this pane.
   Actions that open a pane return its `layer_id`; close it after the
   test with `rex api call session.close_layer`.
5. `rex server logs` shows Lua errors the check misses.

Client actions from the CLI, such as `session.select`, need Remote
Control on in Rex Settings > Rex Server.

Docs: `curl -s https://www.superlogical.com/rex/docs/reference/lua.md`.
Rex is in beta and the API moves between builds.
