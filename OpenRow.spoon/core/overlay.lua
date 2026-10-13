-- OpenRow.spoon/core/overlay.lua — hs.canvas wrapper.
-- An Overlay owns one canvas per screen. clear() must :delete() each
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
    table.insert(self._canvases, { canvas = dim, frame = frame })
  end
end

function Overlay:showLabels(items, style)
  style = style or {}
  local textSize = style.textSize or 14
  local paddingX = style.paddingX or 5
  local paddingY = style.paddingY or 2
  local radius = style.radius or 4

  if #self._canvases == 0 then self:showDim(0) end
  for _, layer in ipairs(self._canvases) do
    local elements = {}
    for _, item in ipairs(items) do
      local center = geometry.center(item.frame)
      if geometry.pointInFrame(center, layer.frame) then
        local width = math.max(22, (#item.text * textSize * 0.62) + paddingX * 2)
        local height = textSize + paddingY * 2 + 3
        local x = center.x - width / 2 - layer.frame.x
        local y = center.y - height / 2 - layer.frame.y
        elements[#elements + 1] = {
          type = "rectangle", action = "fill",
          roundedRectRadii = { xRadius = radius, yRadius = radius },
          frame = { x = x, y = y, w = width, h = height },
          fillColor = { red = 0.98, green = 0.82, blue = 0.22, alpha = 0.95 },
        }
        elements[#elements + 1] = {
          type = "text", text = item.text,
          textAlignment = "center", textSize = textSize,
          textColor = { red = 0.08, green = 0.08, blue = 0.08, alpha = 1 },
          frame = { x = x, y = y + 1, w = width, h = height },
        }
      end
    end
    if #elements > 0 then layer.canvas:appendElements(elements) end
  end
end

function Overlay:clear()
  for _, layer in ipairs(self._canvases) do layer.canvas:delete() end
  self._canvases = {}
end

return M
