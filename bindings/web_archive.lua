local config = require("config").web_archive
local resolveExecutable = require("ext.utils").resolveExecutable
local windowMetadata = require("ext.window").windowMetadata

local cache = { busy = {}, timer = nil, watcher = nil }
local module = { cache = cache }
local log = hs.logger.new("web-archive", "debug")

local function notify(message)
  hs.notify.new({ title = "Web archive", informativeText = message }):send()
end

local function isBrowser(win)
  local app = win and win:application()
  return app and hs.fnutils.contains(require("config").apps.browsers, app:name())
end

local function runFinalizer(path)
  if cache.busy[path] then
    return
  end

  local obsidian = resolveExecutable("obsidian")
  if not obsidian then
    notify("Obsidian CLI is unavailable")
    return
  end

  cache.busy[path] = true
  hs.task.new(obsidian, function(code, stdout, stderr)
    cache.busy[path] = nil
    if code == 0 then
      log.df("Finalized %s: %s", path, stdout)
      return
    end
    local message = (stderr ~= "" and stderr or stdout):gsub("%s+$", "")
    log.ef("Could not finalize %s: %s", path, message)
    notify("Capture needs review: " .. path:match("([^/]+)$"))
  end, {
    "vault=" .. config.vault,
    "quickadd:run",
    "choice=" .. config.finalizeChoice,
    "value-webStagingPath=" .. path,
  }):start()
end

local function processStaging()
  for name in hs.fs.dir(config.stagingPath) do
    if name:match("%.md$") then
      runFinalizer("+Inbox/Web/" .. name)
    end
  end
end

local function scheduleStagingProcess()
  if cache.timer then
    cache.timer:stop()
  end
  cache.timer = hs.timer.doAfter(1, processStaging)
end

local function archivePage()
  local win = hs.window.frontmostWindow()
  if not isBrowser(win) then
    notify("Focus a browser page first")
    return
  end

  hs.eventtap.keyStroke({ "cmd", "shift" }, "o", 0)
end

local function cleanBrowserTitle(title)
  return title:gsub(" %- Brave.*$", "")
end

local function logCurrentPage()
  local win = hs.window.frontmostWindow()
  if not isBrowser(win) then
    notify("Focus a browser page first")
    return
  end

  local title, url = windowMetadata(win)
  title = title and cleanBrowserTitle(title)
  if not title or title == "" or not url or url == "" then
    notify("The current browser page cannot be logged")
    return
  end

  local obsidian = resolveExecutable("obsidian")
  if not obsidian then
    notify("Obsidian CLI is unavailable")
    return
  end

  hs.application.launchOrFocus("Obsidian")
  hs.task.new(obsidian, function(code, stdout, stderr)
    if code ~= 0 then
      log.ef("Could not log %s: %s", url, stderr ~= "" and stderr or stdout)
      notify("Could not log the current page")
    end
  end, {
    "vault=" .. config.vault,
    "quickadd:run",
    "choice=" .. config.logChoice,
    "value-webTitle=" .. title,
    "value-webUrl=" .. url,
    "ui",
  }):start()
end

module.start = function()
  local ok, err = require("ext.utils").ensureDirectory(config.stagingPath)
  if not ok then
    error("Could not create Web staging directory: " .. err)
  end

  hyper.multiBind("y", function()
    archivePage()
  end)
  hyper.multiBind("h", logCurrentPage)

  cache.watcher = hs.pathwatcher.new(config.stagingPath, scheduleStagingProcess)
  cache.watcher:start()
  scheduleStagingProcess()
end

module.stop = function()
  if cache.timer then cache.timer:stop() end
  if cache.watcher then cache.watcher:stop() end
end

return module
