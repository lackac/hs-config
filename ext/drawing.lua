local config = require("config")

local module = {}

module.getHighlightWindowColor = function()
  return { red = 254 / 255, green = 129 / 255, blue = 8 / 255, alpha = 1.0 }
end

module.drawBorder = function()
  require("mod.autoborder").refresh(true)
end

module.highlightWindow = function(win)
  if config.window.highlightBorder then
    module.drawBorder()
  end

  if config.window.highlightMouse then
    local focusedWindow = win or hs.window.focusedWindow()
    if not focusedWindow or focusedWindow:role() ~= "AXWindow" then
      return
    end

    hs.mouse.absolutePosition(hs.geometry.getcenter(focusedWindow:frame()))
  end
end

return module
