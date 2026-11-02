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
