local config = require("config")

local stylesKey = "windowborder.styles"
local cache = { suppressions = {}, styles = hs.settings.get(stylesKey) or {} }
local module = { cache = cache }
local log = hs.logger.new("autoborder", "info")

local function cancel(timer)
  if timer then
    timer:stop()
  end
end

local function hide()
  if cache.border then
    pcall(cache.border.hide, cache.border)
  end
end

local function isSuppressed()
  return next(cache.suppressions) ~= nil
end

local function focusedWindow()
  local window = hs.window.focusedWindow()
  if not window or window:isFullscreen() or window:isMinimized() or not window:isStandard() then
    return
  end

  local app = window:application()
  if not app or not app:isFrontmost() or app:pid() == hs.processInfo.processID then
    return
  end

  return window, app
end

local function styleForApp(app)
  local bundleID = app:bundleID()
  local style = cache.preview and cache.preview.bundleID == bundleID and cache.preview.style
    or cache.styles[bundleID]
    or {}
  return {
    pattern = style.pattern or config.window.borderStyle.pattern,
    color = style.color or config.window.borderStyle.color,
  }
end

local function applyStyle(app, targetChanged)
  local style = styleForApp(app)
  if cache.appliedStyle and cache.appliedStyle.pattern == style.pattern and cache.appliedStyle.color == style.color then
    return true
  end

  if targetChanged then
    hide()
  end

  local border, _, code, message = cache.border:setPattern(style.pattern)
  if not border then
    log.ef("window border pattern failed: %s", message or code)
    return false
  end

  border, _, code, message = cache.border:setColor(style.color)
  if not border then
    log.ef("window border color failed: %s", message or code)
    return false
  end

  cache.appliedStyle = style
  return true
end

local function refresh(full)
  if not cache.running or not config.window.highlightBorder or isSuppressed() then
    hide()
    return
  end

  local window, app = focusedWindow()
  if not window then
    hide()
    return
  end

  local targetChanged = cache.targetID ~= window:id()
  if not applyStyle(app, targetChanged) then
    hide()
    cache.targetID = nil
    return
  end

  local method = targetChanged and cache.border.attach or cache.border.update
  local ok, result, state, code, message
  if method == cache.border.attach then
    ok, result, state, code, message = pcall(method, cache.border, window:id(), app:pid())
  else
    ok, result, state, code, message = pcall(method, cache.border, full)
  end

  if not ok or not result then
    hide()
    cache.targetID = nil
    log.ef("window border update failed: %s", message or code or state or result or "unknown error")
    return
  end

  cache.targetID = window:id()
end

local function schedule(full, delay)
  cancel(cache.refreshTimer)
  local generation = cache.generation
  cache.refreshTimer = hs.timer.doAfter(delay or 0.016, function()
    if cache.generation == generation then
      refresh(full)
    end
  end)
end

module.refresh = function(full)
  schedule(full, 0)
end

module.suspend = function(reason)
  cache.suppressions[reason] = true
  hide()
  cache.targetID = nil
end

module.resume = function(reason)
  cache.suppressions[reason] = nil
  if not isSuppressed() then
    schedule(true, 0.15)
  end
end

module.setPattern = function(pattern)
  if cache.border then
    local border, state, code, message = cache.border:setPattern(pattern)
    if border then
      config.window.borderStyle.pattern = pattern
    end
    return border, state, code, message
  end
  config.window.borderStyle.pattern = pattern
end

module.setColor = function(color)
  if cache.border then
    local border, state, code, message = cache.border:setColor(color)
    if border then
      config.window.borderStyle.color = color
    end
    return border, state, code, message
  end
  config.window.borderStyle.color = color
end

module.beginPreview = function()
  local _, app = focusedWindow()
  if not app or not app:bundleID() then
    return
  end

  local style = styleForApp(app)
  cache.preview = {
    bundleID = app:bundleID(),
    application = app:name(),
    style = { pattern = style.pattern, color = style.color },
  }
  return cache.preview
end

module.preview = function(style)
  if not cache.preview then
    return false, "no active border preview"
  end

  cache.preview.style = { pattern = style.pattern, color = style.color }
  cache.appliedStyle = nil
  refresh(true)
  return true
end

module.commitPreview = function()
  if not cache.preview then
    return
  end

  cache.styles[cache.preview.bundleID] = cache.preview.style
  hs.settings.set(stylesKey, cache.styles)
  cache.preview = nil
end

module.cancelPreview = function()
  if not cache.preview then
    return
  end

  cache.preview = nil
  cache.appliedStyle = nil
  refresh(true)
end

module.removeStyle = function()
  local _, app = focusedWindow()
  if not app or not app:bundleID() then
    return
  end

  cache.styles[app:bundleID()] = nil
  hs.settings.set(stylesKey, cache.styles)
  cache.preview = nil
  cache.appliedStyle = nil
  refresh(true)
  return app:name()
end

module.start = function()
  if cache.running then
    return
  end

  local ok, windowborder = pcall(require, "hs.windowborder")
  if not ok then
    log.ef("native window border is unavailable: %s", windowborder)
    return
  end

  local border, code, message = windowborder.new(config.window.borderStyle)
  if not border then
    log.ef("native window border could not start: %s", message or code)
    return
  end

  cache.border = border
  cache.running = true
  cache.generation = (cache.generation or 0) + 1
  cache.appliedStyle = nil
  cache.filter = hs.window.filter.new():setDefaultFilter()
  cache.filter:subscribe({
    hs.window.filter.windowCreated,
    hs.window.filter.windowDestroyed,
    hs.window.filter.windowMoved,
    hs.window.filter.windowFocused,
    hs.window.filter.windowUnfocused,
  }, function()
    schedule(false)
  end)
  cache.watchdog = hs.timer.doEvery(0.25, function()
    refresh(true)
  end)
  schedule(true, 0)
end

module.stop = function()
  if not cache.running then
    return
  end

  cache.running = false
  cache.generation = cache.generation + 1
  cancel(cache.refreshTimer)
  cancel(cache.watchdog)
  if cache.filter then
    cache.filter:unsubscribeAll()
    cache.filter = nil
  end
  if cache.border then
    pcall(cache.border.delete, cache.border)
    cache.border = nil
  end
  cache.targetID = nil
  cache.appliedStyle = nil
end

return module
