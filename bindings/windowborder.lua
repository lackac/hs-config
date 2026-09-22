local autoborder = require("mod.autoborder")

local cache = {}
local module = { cache = cache }

local function clamp(value)
  return math.max(0, math.min(1, value))
end

local function hexFromHSB(hsb)
  local rgb = hs.drawing.color.asRGB(hsb)
  return string.format(
    "#%02X%02X%02X",
    math.floor(rgb.red * 255 + 0.5),
    math.floor(rgb.green * 255 + 0.5),
    math.floor(rgb.blue * 255 + 0.5)
  )
end

local function showGuide()
  local window = hs.window.get(cache.draft.windowID)
  local frame = window and window:frame() or hs.screen.mainScreen():frame()
  local width = 440
  local height = 152
  local guideFrame = { x = frame.x + (frame.w - width) / 2, y = frame.y + 32, w = width, h = height }

  if not cache.guide then
    cache.guide = hs.canvas
      .new(guideFrame)
      :level(hs.canvas.windowLevels.overlay)
      :behavior({ hs.canvas.windowBehaviors.transient, hs.canvas.windowBehaviors.moveToActiveSpace })
    cache.guide[1] = {
      type = "rectangle",
      action = "fill",
      fillColor = { red = 0.08, green = 0.08, blue = 0.08, alpha = 0.92 },
      roundedRectRadii = { xRadius = 12, yRadius = 12 },
    }
    cache.guide[2] = {
      type = "text",
      textAlignment = "center",
      textColor = { white = 1, alpha = 1 },
      textFont = "AppleSystemUIFont",
      textSize = 14,
      frame = { x = 12, y = 10, w = width - 24, h = height - 20 },
    }
  end

  cache.guide:frame(guideFrame)
  cache.guide[2].text = table.concat({
    cache.draft.application,
    string.format("%s  %s", cache.draft.style.pattern, cache.draft.style.color),
    "Left/Right pattern",
    "Up/Down hue",
    "[ / ] saturation",
    "{ / } brightness",
    "Backspace/Delete reset",
    "Enter save  Esc cancel"
  }, "\n")
  cache.guide:show()
end

local function hideGuide()
  if cache.guide then
    cache.guide:hide()
  end
end

local function applyDraft()
  autoborder.preview(cache.draft.style)
  showGuide()
end

local function cyclePattern(step)
  cache.patternIndex = (cache.patternIndex - 1 + step) % #cache.patterns + 1
  cache.draft.style.pattern = cache.patterns[cache.patternIndex]
  applyDraft()
end

local function adjustColor(key, amount, wraps)
  local hsb = hs.drawing.color.asHSB({ hex = cache.draft.style.color })
  local value = hsb[key] + amount
  hsb[key] = wraps and value % 1 or clamp(value)
  cache.draft.style.color = hexFromHSB(hsb)
  applyDraft()
end

local function finish(save)
  if save then
    autoborder.commitPreview()
  else
    autoborder.cancelPreview()
  end
  cache.draft = nil
  hideGuide()
  cache.modal:exit()
end

local function removeStyle()
  local application = autoborder.removeStyle()
  if application then
    cache.draft = nil
    hideGuide()
    cache.modal:exit()
    hs.alert.show("Reset border style for " .. application)
  end
end

local function begin()
  local window = hs.window.focusedWindow()
  local draft = autoborder.beginPreview()
  if not draft or not window then
    hs.alert.show("No eligible focused window")
    return
  end

  cache.draft = {
    bundleID = draft.bundleID,
    application = draft.application,
    windowID = window:id(),
    style = { pattern = draft.style.pattern, color = draft.style.color },
  }
  cache.patterns = require("hs.windowborder").patterns()
  cache.patternIndex = hs.fnutils.indexOf(cache.patterns, cache.draft.style.pattern) or 1
  hyper:exit()
  cache.modal:enter()
  showGuide()
end

module.start = function()
  cache.modal = hs.hotkey.modal.new()
  hyper.multiBind("b", begin)
  cache.modal:bind({}, "left", function()
    cyclePattern(-1)
  end)
  cache.modal:bind({}, "right", function()
    cyclePattern(1)
  end)
  cache.modal:bind({}, "up", function()
    adjustColor("hue", 0.02, true)
  end)
  cache.modal:bind({}, "down", function()
    adjustColor("hue", -0.02, true)
  end)
  cache.modal:bind({}, "[", function()
    adjustColor("saturation", -0.05)
  end)
  cache.modal:bind({}, "]", function()
    adjustColor("saturation", 0.05)
  end)
  cache.modal:bind({ "shift" }, "[", function()
    adjustColor("brightness", -0.05)
  end)
  cache.modal:bind({ "shift" }, "]", function()
    adjustColor("brightness", 0.05)
  end)
  cache.modal:bind({}, "return", function()
    finish(true)
  end)
  cache.modal:bind({}, "escape", function()
    finish(false)
  end)
  cache.modal:bind({}, "delete", removeStyle)
  cache.modal:bind({}, "forwarddelete", removeStyle)
  cache.appWatcher = hs.application.watcher
    .new(function(_, event, app)
      if
        cache.draft
        and app
        and event == hs.application.watcher.activated
        and app:bundleID() ~= cache.draft.bundleID
      then
        finish(false)
      end
    end)
    :start()
end

module.stop = function()
  if cache.modal then
    cache.modal:exit()
  end
  if cache.guide then
    cache.guide:delete()
    cache.guide = nil
  end
  if cache.appWatcher then
    cache.appWatcher:stop()
    cache.appWatcher = nil
  end
end

return module
