local windowMetadata = require("ext.window").windowMetadata
local ensureParentDirectory = require("ext.utils").ensureParentDirectory
local config = require("config")
local rexMetadata = require("mod.app_logger_rex")

local cache = {}
local module = { cache = cache }

local log = hs.logger.new("app-logger", "debug")

module.sleepWatcher = function(_, _, _, _, event)
  if event == hs.caffeinate.watcher.systemWillSleep or event == hs.caffeinate.watcher.systemWillPowerOff then
    log.d("stopping app logger")
    cache.timer:stop()
  end

  if event == hs.caffeinate.watcher.systemDidWake then
    log.d("starting app logger")
    cache.timer:start()
  end
end

local sanitize = function(s)
  return s:gsub([[']], "''")
end

local executeOrError = function(db, statement, description)
  local result = db:execute(statement)

  if result ~= hs.sqlite3.OK then
    error("failed to " .. description .. ": " .. db:errmsg())
  end
end

local prepareSchema = function(db)
  executeOrError(db, "DROP TRIGGER IF EXISTS ft_log_update", "remove legacy app logger FTS trigger")
  executeOrError(db, "DROP TABLE IF EXISTS ft_log", "remove legacy app logger FTS table")
  executeOrError(
    db,
    [[
      CREATE TABLE IF NOT EXISTS log (app TEXT NOT NULL, title TEXT NOT NULL, epoch INTEGER NOT NULL, meta TEXT);
      CREATE INDEX IF NOT EXISTS basic_search_idx ON log (app, title, meta);
    ]],
    "prepare app logger schema"
  )
end

local function insertSample(app, title, time, meta)
  local statement = "INSERT INTO log VALUES('"
    .. sanitize(app)
    .. "', '"
    .. sanitize(title)
    .. "', '"
    .. time
    .. "', '"
    .. sanitize(meta)
    .. "')"
  local insert = cache.db:execute(statement)

  if insert ~= hs.sqlite3.OK then
    local errmsg = cache.db:errmsg()
    if errmsg ~= cache.lastError then
      hs.notify
        .new({
          title = "App Logger failed",
          subTitle = "Look into Hammerspoon Console for more info",
        })
        :send()
      log.e("failed insert: " .. errmsg .. "\n" .. statement)
      cache.lastError = errmsg
    end
  end
end

module.start = function()
  local loggerConfig = config.appLogger or {}
  local path = loggerConfig.path
    or (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/hs/app_logger.db"

  local ok, err = ensureParentDirectory(path)

  if not ok then
    error("failed to prepare app logger path '" .. path .. "': " .. err)
  end

  cache.db = hs.sqlite3.open(path)

  if not cache.db then
    error("failed to open app logger db at '" .. path .. "'")
  end

  prepareSchema(cache.db)

  cache.watcherSleep = hs.watchable.watch("status.sleepEvent", module.sleepWatcher)

  cache.timer = hs.timer.doEvery(10, function()
    -- logging sometimes makes mouse lock up?
    if #hs.mouse.getButtons() ~= 0 then
      return
    end

    local win = hs.window.focusedWindow()
    if not win then
      return
    end

    local app = win:application()
    local name = app and app:name()
    if not name or name == "loginwindow" then
      return
    end

    local time = os.time()
    local title, meta = windowMetadata(win)
    title, meta = title or "", meta or ""
    if meta == "" and app:bundleID() == rexMetadata.bundleID and not cache.rexTask then
      local task
      task = rexMetadata.lookup(win, title, function(directory)
        if task and cache.rexTask == task then
          cache.rexTask = nil
          insertSample(name, title, time, directory or meta)
        end
      end)
      if task then
        cache.rexTask = task
        return
      end
    end

    insertSample(name, title, time, meta)
  end)
end

module.stop = function()
  cache.timer:stop()
  cache.timer = nil

  local task = cache.rexTask
  cache.rexTask = nil
  if task and task:isRunning() then
    task:terminate()
  end

  if cache.db then
    cache.db:close()
    cache.db = nil
  end
end

return module
