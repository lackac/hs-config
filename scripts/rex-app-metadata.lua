-- luacheck: globals rex
local sample = rex.args

-- The Mac window doesn't identify its server. Don't match a remote view to a local session.
local hosts = rex.call("hosts.list")
if not hosts or #(hosts.hosts or {}) > 0 then
  return
end

local sessions = rex.call("session.list")
local match
for _, session in ipairs(sessions and sessions.sessions or {}) do
  if session.label == sample.session then
    local attached = rex.session.attach({ session_id = session.session_id })
    if not attached or not attached.view then
      return
    end
    local view = attached.view
    local tab = view.windows[sample.index]
    if #view.windows == sample.count and tab and tab.window_id == view.active_window_id and tab.focused_block_id then
      -- Unnamed tabs use a generated title in the app, not the server's default label.
      if tab.label == sample.label or tab.label == "Window " .. tab.window_id:sub(-8) then
        if match then
          return
        end
        match = { session_id = session.session_id, block_id = tab.focused_block_id, args = {} }
      end
    end
  end
end

if match then
  local process = rex.call("com.superlogical.terminal.process", match)
  if process then
    return { cwd = (process.foreground and process.foreground.cwd) or (process.child and process.child.cwd) }
  end
end
