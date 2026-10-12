-- OpenRow.spoon/core/element_factory.lua — hs.axuielement safe-call helpers.
-- All exports wrap raw axuielement calls in pcall so that scanner / runtime
-- code can stay simple. No snapshot type — callers read attributes on demand.

local geometry = require("core.geometry")

local M = {}

function M.safeAttribute(element, attribute)
  local ok, value = pcall(function() return element:attributeValue(attribute) end)
  if ok then return value end
  return nil
end

function M.frame(element)
  local frame = M.safeAttribute(element, "AXFrame")
  if frame then return frame end
  local position = M.safeAttribute(element, "AXPosition")
  local size = M.safeAttribute(element, "AXSize")
  if position and size then
    return { x = position.x, y = position.y, w = size.w, h = size.h }
  end
  return nil
end

function M.safeSetAttribute(element, attribute, value)
  local ok, result = pcall(function() return element:setAttributeValue(attribute, value) end)
  -- hs.axuielement returns the element on success, nil on failure.
  return ok and result ~= nil and result ~= false
end

function M.safeActionNames(element)
  local ok, value = pcall(function()
    if element.actionNames then return element:actionNames() end
    return element:attributeValue("AXActions")
  end)
  if ok and type(value) == "table" then return value end
  return {}
end

-- ponytail: AX identity comparisons are linear within role buckets; add stable
-- identity keys only if large-tree profiling shows this is a bottleneck.
function M.markSeen(seen, element, role)
  role = role or M.safeAttribute(element, "AXRole") or ""
  local bucket = seen[role] or {}
  for _, existing in ipairs(bucket) do if existing == element then return false end end
  bucket[#bucket + 1] = element
  seen[role] = bucket
  return true
end

local function appendUniqueChildren(children, seenChildren, values)
  if type(values) ~= "table" then return end
  for _, child in ipairs(values) do
    if M.markSeen(seenChildren, child) then children[#children + 1] = child end
  end
end

local visibleCollections = { AXTable = 'AXVisibleRows', AXOutline = 'AXVisibleRows', AXTabGroup = 'AXVisibleChildren' }
M.clippingRoles = { AXWindow = true, AXScrollArea = true, AXWebArea = true }

function M.rawChildren(element, childAttributes, maxResults)
  local role = M.safeAttribute(element, 'AXRole')
  local preferred = visibleCollections[role]
  if preferred then
    local values = M.safeAttribute(element, preferred)
    if type(values) == 'table' then return values end
  end
  local children = {}
  local seenChildren = {}
  if role == 'AXWebArea' then
    local ok, values = pcall(function()
      return element:parameterizedAttributeValue('AXUIElementsForSearchPredicate', {
        AXDirection = 'AXDirectionNext', AXImmediateDescendantsOnly = false,
        AXVisibleOnly = true, AXResultsLimit = maxResults or 1500,
        AXSearchKey = { 'AXControlSearchKey', 'AXLinkSearchKey', 'AXKeyboardFocusableSearchKey', 'AXGraphicSearchKey' },
      })
    end)
    -- Search adds browser-specific paths without hiding custom AXPress nodes.
    if ok then appendUniqueChildren(children, seenChildren, values) end
  end

  appendUniqueChildren(children, seenChildren, M.safeAttribute(element, "AXChildrenInNavigationOrder"))
  for _, attribute in ipairs(childAttributes) do
    appendUniqueChildren(children, seenChildren, M.safeAttribute(element, attribute))
  end

  return children
end

function M.matchesTarget(hit, target)
  local seen = {}
  for _ = 1, 32 do
    if not hit then return false end
    if hit == target then return true end
    if not M.markSeen(seen, hit) then return false end
    hit = M.safeAttribute(hit, 'AXParent')
  end
  return false
end

function M.visibleFrame(element, screenFrames)
  local frame = M.frame(element)
  if M.safeAttribute(element, 'AXEnabled') == false then return nil end
  if not geometry.visibleOnScreens(frame, screenFrames) then return nil end
  local parent = M.safeAttribute(element, 'AXParent')
  local seen = {}
  for _ = 1, 32 do
    if not frame or not parent or not M.markSeen(seen, parent) then break end
    if M.clippingRoles[M.safeAttribute(parent, 'AXRole')] then
      local bounds = M.frame(parent)
      if bounds and bounds.w > 0 and bounds.h > 0 then frame = geometry.intersection(frame, bounds) end
    end
    parent = M.safeAttribute(parent, 'AXParent')
  end
  return geometry.visibleFrame(frame, screenFrames)
end

return M
