local resolveExecutable = require("ext.utils").resolveExecutable

local module = { bundleID = "com.superlogical.rex" }

local function findTabs(element, depth)
  if not element or depth > 6 then
    return
  end
  local role = element:attributeValue("AXRole")
  if role == "AXTextArea" then
    return
  end
  if role == "AXGroup" and element:attributeValue("AXDescription") == "Tabs" then
    return element
  end
  for _, child in ipairs(element:attributeValue("AXChildren") or {}) do
    local tabs = findTabs(child, depth + 1)
    if tabs then
      return tabs
    end
  end
end

local function snapshot(win, title)
  if not win or win:subrole() ~= "AXStandardWindow" or win:title() ~= title then
    return
  end
  local tabs = findTabs(hs.axuielement.windowElement(win), 0)
  if not tabs then
    return
  end
  local count, index, label = 0, nil, nil
  for _, tab in ipairs(tabs:attributeValue("AXChildren") or {}) do
    if tab:attributeValue("AXRole") == "AXRadioButton" then
      count = count + 1
      if tab:attributeValue("AXSelected") then
        if index then
          return
        end
        index, label = count, tab:attributeValue("AXDescription")
      end
    end
  end
  if type(label) == "string" and label ~= "" then
    local prefix = label .. " - "
    if title:sub(1, #prefix) == prefix and #title > #prefix then
      return { session = title:sub(#prefix + 1), label = label, index = index, count = count }
    end
  end
end

local function directoryURL(path)
  if type(path) ~= "string" or path:sub(1, 1) ~= "/" then
    return
  end
  if path:sub(-1) ~= "/" then
    path = path .. "/"
  end
  return "file://"
    .. path:gsub("([^A-Za-z0-9._~/%-])", function(byte)
      return string.format("%%%02X", byte:byte())
    end)
end

module.lookup = function(win, title, complete)
  local sample = snapshot(win, title)
  if not sample then
    return
  end
  local cli = resolveExecutable({
    os.getenv("HOME")
      .. "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current"
      .. "/Rex Server.app/Contents/MacOS/rex",
    "/Applications/Rex.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex",
  })
  if not cli then
    return
  end
  local id = win:id()
  local task = hs.task.new("/usr/bin/env", function(code, stdout)
    if code == 0 then
      local focused = hs.window.focusedWindow()
      local current = focused and focused:id() == id and snapshot(focused, title)
      if current and current.index == sample.index and current.count == sample.count then
        local ok, result = pcall(hs.json.decode, stdout)
        if ok and type(result) == "table" then
          return complete(directoryURL(result.cwd))
        end
      end
    end
    complete()
  end, {
    "-u",
    "XDG_RUNTIME_DIR",
    "-u",
    "REX_RUNTIME_DIR",
    "-u",
    "REX_HOME",
    "-u",
    "REX_SERVER",
    "-u",
    "REX_CLIENT",
    "-u",
    "REX_SESSION",
    "-u",
    "REX_BLOCK",
    cli,
    "--autostart=false",
    "--timeout",
    "1s",
    "do",
    hs.configdir .. "/scripts/rex-app-metadata.lua",
    "--args",
    hs.json.encode(sample),
    "--json",
  })
  return task and task:start()
end

return module
