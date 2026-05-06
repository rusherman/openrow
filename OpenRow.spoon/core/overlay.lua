-- OpenRow.spoon/core/overlay.lua — hs.canvas wrapper.
-- An Overlay owns a list of canvas objects. clear() must :delete() each
-- canvas (not :hide()), otherwise repeated activations leak resources.

local geometry = require("core.geometry")

local Overlay = {}
Overlay.__index = Overlay

local M = {}

function M.new()
  return setmetatable({ _canvases = {} }, Overlay)
end

function Overlay:showDim(opacity)
  for _, screen in ipairs(hs.screen.allScreens()) do
    local frame = screen:fullFrame()
    local dim = hs.canvas.new(frame)
    dim:level(hs.canvas.windowLevels.overlay)
    dim:behavior({
      hs.canvas.windowBehaviors.canJoinAllSpaces,
      hs.canvas.windowBehaviors.stationary,
    })
    dim:appendElements({
      type = "rectangle", action = "fill",
      frame = { x = 0, y = 0, w = frame.w, h = frame.h },
      fillColor = { white = 0, alpha = opacity or 0.08 },
    })
    dim:show()
    table.insert(self._canvases, dim)
  end
end

function Overlay:showLabels(items, style)
  style = style or {}
  local textSize = style.textSize or 14
  local paddingX = style.paddingX or 5
  local paddingY = style.paddingY or 2
  local radius = style.radius or 4

  for _, item in ipairs(items) do
    local center = geometry.center(item.frame)
    local width = math.max(22, (#item.text * textSize * 0.62) + paddingX * 2)
    local height = textSize + paddingY * 2 + 3
    local rect = {
      x = center.x - width / 2,
      y = center.y - height / 2,
      w = width, h = height,
    }
    local canvas = hs.canvas.new(rect)
    canvas:level(hs.canvas.windowLevels.overlay)
    canvas:behavior({
      hs.canvas.windowBehaviors.canJoinAllSpaces,
      hs.canvas.windowBehaviors.stationary,
    })
    canvas:appendElements({
      {
        type = "rectangle", action = "fill",
        roundedRectRadii = { xRadius = radius, yRadius = radius },
        frame = { x = 0, y = 0, w = width, h = height },
        fillColor = { red = 0.98, green = 0.82, blue = 0.22, alpha = 0.95 },
      },
      {
        type = "text", text = item.text,
        textAlignment = "center", textSize = textSize,
        textColor = { red = 0.08, green = 0.08, blue = 0.08, alpha = 1 },
        frame = { x = 0, y = 1, w = width, h = height },
      },
    })
    canvas:show()
    table.insert(self._canvases, canvas)
  end
end

function Overlay:clear()
  for _, canvas in ipairs(self._canvases) do canvas:delete() end
  self._canvases = {}
end

return M
