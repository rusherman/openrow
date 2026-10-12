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

function M.intersection(left, right)
  if not left or not right or not M.intersects(left, right) then return nil end
  local x, y = math.max(left.x, right.x), math.max(left.y, right.y)
  return { x = x, y = y,
    w = math.min(left.x + left.w, right.x + right.w) - x,
    h = math.min(left.y + left.h, right.y + right.h) - y }
end

function M.visibleFrame(frame, screenFrames, clipBounds)
  if not M.visibleOnScreens(frame, screenFrames) then return nil end
  if clipBounds then frame = M.intersection(frame, clipBounds) end
  if not frame then return nil end
  local best
  for _, screen in ipairs(screenFrames) do
    local visible = M.intersection(frame, screen)
    if visible and (not best or visible.w * visible.h > best.w * best.h) then best = visible end
  end
  return best
end

function M.pointInFrame(point, frame)
  return point and type(point.x) == 'number' and type(point.y) == 'number'
    and point.x >= frame.x and point.x < frame.x + frame.w
    and point.y >= frame.y and point.y < frame.y + frame.h
end

function M.clickPoint(target, config)
  if target.role == "AXLink" then
    local inset = config.linkClickInset
    return {
      x = target.frame.x + math.min(inset, target.frame.w / 2),
      y = target.frame.y + target.frame.h - math.min(inset, target.frame.h / 2),
    }
  end

  return {
    x = target.frame.x + target.frame.w * config.genericClickXRatio,
    y = target.frame.y + target.frame.h * config.genericClickYRatio,
  }
end

function M.clickPoints(target, config)
  local points = {}
  local function add(point)
    if not M.pointInFrame(point, target.frame) then return end
    for _, existing in ipairs(points) do
      if existing.x == point.x and existing.y == point.y then return end
    end
    points[#points + 1] = point
  end
  add(target.activationPoint)
  if target.role ~= 'AXLink' then add(M.clickPoint(target, config)) end
  add(M.center(target.frame))
  if target.role == 'AXLink' then add(M.clickPoint(target, config)) end
  if target.role == 'AXLink' then
    local f = target.frame
    add({ x = f.x + f.w - math.min(config.linkClickInset, f.w / 2),
      y = f.y + math.min(config.linkClickInset, f.h / 2) })
  end
  return points
end

return M
