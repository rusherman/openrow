-- OpenRow.spoon/core/scanner.lua — pure target classification, dedup, ranking,
-- and search-text helpers. No hs.* dependencies; safe to unit test.

local geometry = require("core.geometry")

local M = {}

local function text(value)
  if value == nil then return "" end
  return tostring(value)
end

function M.maxScreenArea(screenFrames)
  local maxArea = 0
  for _, screenFrame in ipairs(screenFrames or {}) do
    maxArea = math.max(maxArea, screenFrame.w * screenFrame.h)
  end
  return math.max(1, maxArea)
end

function M.isChromiumApp(bundleId, patterns)
  if not bundleId or not patterns then return false end
  for _, pattern in ipairs(patterns) do
    if bundleId:match(pattern) then return true end
  end
  return false
end

function M.hasActionableAction(actionNames, ignoredActions)
  for _, action in ipairs(actionNames or {}) do
    if not (ignoredActions and ignoredActions[action]) then return true end
  end
  return false
end

function M.hasMeaningfulText(parts)
  local text = text(parts.title) .. text(parts.value) .. text(parts.description)
  return text:match("%S") ~= nil
end

function M.computeSearchText(parts)
  local pieces = {
    text(parts.role),
    text(parts.title),
    text(parts.description),
    text(parts.value),
    text(parts.help),
  }
  return table.concat(pieces, " "):lower()
end

-- Pure: classify a candidate element. Returns "role" / "action" / "selection" / "fallback" / nil.
-- opts must include role, frame, enabled, actionNames, hasMeaningfulText,
-- hasHintableChildren, config, screenFrames, screenArea.
function M.targetKind(opts)
  local role = opts.role
  local frame = opts.frame
  local config = opts.config

  if not role or opts.enabled == false then return nil end
  if not geometry.visibleOnScreens(frame, opts.screenFrames) then return nil end
  if frame.w < config.minSize or frame.h < config.minSize then return nil end

  local areaRatio = (frame.w * frame.h) / opts.screenArea
  if areaRatio > config.maxTargetAreaRatio then return nil end

  if config.controlRoles[role] then return "role" end
  if M.hasActionableAction(opts.actionNames, config.ignoredActions) then return "action" end
  if opts.selectable then return "selection" end
  if config.roleFallbacks[role] and opts.hasHintableChildren then return nil end

  if config.roleFallbacks[role]
      and frame.w >= config.minListItemWidth
      and frame.h >= config.minListItemHeight then
    if role == "AXStaticText" and not opts.hasMeaningfulText then return nil end
    return "fallback"
  end

  return nil
end

-- Pure: keep semantic controls before generic action nodes sharing their frame.
function M.dedupeTargets(targets)
  local result = {}
  local priority = { role = 3, action = 2, selection = 2, fallback = 1 }

  for _, target in ipairs(targets) do
    local shouldAdd = true

    for _, existing in ipairs(result) do
      if geometry.framesAlmostEqual(existing.frame, target.frame) then
        if (priority[existing.kind] or 0) >= (priority[target.kind] or 0) then
          shouldAdd = false
        end
        break
      end

      if target.kind == "fallback" and geometry.contains(existing.frame, target.frame) then
        shouldAdd = false
        break
      end
    end

    if shouldAdd then
      for index = #result, 1, -1 do
        local existing = result[index]
        local sameFrame = geometry.framesAlmostEqual(existing.frame, target.frame)
        local existingContainsTarget = geometry.contains(existing.frame, target.frame)

        if (sameFrame and (priority[existing.kind] or 0) < (priority[target.kind] or 0))
            or (existing.kind == "fallback" and target.kind ~= "fallback"
              and (existingContainsTarget or geometry.contains(target.frame, existing.frame))) then
          table.remove(result, index)
        end
      end

      table.insert(result, target)
    end
  end

  return result
end

-- Pure: rank by reading order — top-to-bottom, then left-to-right.
function M.rankTargets(targets)
  table.sort(targets, function(left, right)
    if math.abs(left.frame.y - right.frame.y) > 8 then return left.frame.y < right.frame.y end
    return left.frame.x < right.frame.x
  end)
  return targets
end

return M
