-- OpenRow.spoon/core/geometry.lua — pure frame math.

local M = {}

function M.center(frame)
  return {
    x = frame.x + frame.w / 2,
    y = frame.y + frame.h / 2,
  }
end

function M.contains(outer, inner)
  return outer.x <= inner.x
    and outer.y <= inner.y
    and outer.x + outer.w >= inner.x + inner.w
    and outer.y + outer.h >= inner.y + inner.h
end

function M.intersects(left, right)
  return left.x < right.x + right.w
    and left.x + left.w > right.x
    and left.y < right.y + right.h
    and left.y + left.h > right.y
end

function M.framesAlmostEqual(left, right, tolerance)
  tolerance = tolerance or 3
  local leftCenter = M.center(left)
  local rightCenter = M.center(right)
  local sameCenter = math.abs(leftCenter.x - rightCenter.x) < tolerance
    and math.abs(leftCenter.y - rightCenter.y) < tolerance
  local sameSize = math.abs(left.w - right.w) < tolerance
    and math.abs(left.h - right.h) < tolerance
  return sameCenter and sameSize
end

function M.visibleOnScreens(frame, screenFrames)
  if not frame or not frame.x or not frame.y or not frame.w or not frame.h then return false end
  if frame.w <= 0 or frame.h <= 0 then return false end
  for _, screenFrame in ipairs(screenFrames) do
    if M.intersects(frame, screenFrame) then return true end
  end
  return false
end

function M.clickPoint(target, config)
  if target.role == "AXLink" then
    local inset = config.linkClickInset
    return {
      x = target.frame.x + inset,
      y = target.frame.y + target.frame.h - inset,
    }
  end

  return {
    x = target.frame.x + target.frame.w * config.genericClickXRatio,
    y = target.frame.y + target.frame.h * config.genericClickYRatio,
  }
end

return M
