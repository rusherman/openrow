-- OpenRow.spoon/core/element_factory.lua — hs.axuielement safe-call helpers.
-- All exports wrap raw axuielement calls in pcall so that scanner / runtime
-- code can stay simple. No snapshot type — callers read attributes on demand.

local geometry = require("core.geometry")

local M = {}

function M.safeAttribute(element, attribute, checkpoint)
  local ok, value = pcall(function() return element:attributeValue(attribute) end)
  if checkpoint then checkpoint() end
  if ok then return value end
  return nil
end

function M.frame(element, checkpoint)
  local frame = M.safeAttribute(element, "AXFrame", checkpoint)
  if frame then return frame end
  local position = M.safeAttribute(element, "AXPosition", checkpoint)
  local size = M.safeAttribute(element, "AXSize", checkpoint)
  if position and size then
    return { x = position.x, y = position.y, w = size.w, h = size.h }
  end
  return nil
end

function M.safeSetAttribute(element, attribute, value, checkpoint)
  local ok, result = pcall(function() return element:setAttributeValue(attribute, value) end)
  if checkpoint then checkpoint() end
  -- hs.axuielement returns the element on success, nil on failure.
  return ok and result ~= nil and result ~= false
end

function M.setTimeout(element, seconds)
  pcall(function() element:setTimeout(seconds) end)
end

function M.safeActionNames(element, checkpoint)
  local ok, value = pcall(function()
    if element.actionNames then return element:actionNames() end
    return element:attributeValue("AXActions")
  end)
  if checkpoint then checkpoint() end
  if ok and type(value) == "table" then return value end
  return {}
end

-- ponytail: AX identity comparisons are linear within role buckets; add stable
-- identity keys only if large-tree profiling shows this is a bottleneck.
function M.markSeen(seen, element, role, checkpoint)
  role = role or M.safeAttribute(element, "AXRole", checkpoint) or ""
  local bucket = seen[role] or {}
  for index, existing in ipairs(bucket) do
    if existing == element then return false end
    if checkpoint and index % 64 == 0 then checkpoint() end
  end
  bucket[#bucket + 1] = element
  seen[role] = bucket
  return true
end

local function appendUniqueChildren(children, seenChildren, values, checkpoint)
  if type(values) ~= "table" then return end
  for _, child in ipairs(values) do
    if M.markSeen(seenChildren, child, '', checkpoint) then children[#children + 1] = child end
  end
end

local visibleCollections = { AXTable = 'AXVisibleRows', AXOutline = 'AXVisibleRows', AXTabGroup = 'AXVisibleChildren' }
M.clippingRoles = { AXWindow = true, AXScrollArea = true, AXWebArea = true }

function M.rawChildren(element, childAttributes, maxResults, checkpoint, role)
  role = role or M.safeAttribute(element, 'AXRole', checkpoint)
  local preferred = visibleCollections[role]
  if preferred then
    local values = M.safeAttribute(element, preferred, checkpoint)
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
    if checkpoint then checkpoint() end
    -- Search adds browser-specific paths without hiding custom AXPress nodes.
    if ok then appendUniqueChildren(children, seenChildren, values, checkpoint) end
  end

  appendUniqueChildren(children, seenChildren, M.safeAttribute(element, "AXChildrenInNavigationOrder", checkpoint), checkpoint)
  for _, attribute in ipairs(childAttributes) do
    appendUniqueChildren(children, seenChildren, M.safeAttribute(element, attribute, checkpoint), checkpoint)
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

function M.matchesClickPoint(hit, target, point)
  if M.matchesTarget(hit, target) then return true end
  -- Electron can report an empty pointer-events-none portal instead of the
  -- button underneath it. Do not extend this exception to links or fallback
  -- containers: their bounding boxes can contain non-clickable space.
  if not hit or M.safeAttribute(hit, 'AXRole') ~= 'AXGroup'
      or M.safeAttribute(target, 'AXRole') ~= 'AXButton' then return false end
  local transparent = false
  local classes = M.safeAttribute(hit, 'AXDOMClassList')
  if type(classes) == 'table' then
    for _, class in ipairs(classes) do if class == 'pointer-events-none' then transparent = true end end
  end
  if not transparent or M.safeAttribute(hit, 'AXModal') == true then return false end
  local ok, sameProcess = pcall(function()
    local pid = hit:pid()
    return type(pid) == 'number' and pid > 0 and pid == target:pid()
  end)
  if not ok or not sameProcess then return false end
  local window = M.safeAttribute(target, 'AXWindow')
  if not window or M.safeAttribute(hit, 'AXWindow') ~= window then return false end
  local children = M.safeAttribute(hit, 'AXChildren')
  if type(children) ~= 'table' or next(children) ~= nil then return false end
  for _, attribute in ipairs({ 'AXContents', 'AXChildrenInNavigationOrder' }) do
    local values = M.safeAttribute(hit, attribute)
    if values ~= nil and (type(values) ~= 'table' or next(values) ~= nil) then return false end
  end
  local frame = M.frame(target)
  local hitFrame = M.frame(hit)
  return frame ~= nil and hitFrame ~= nil and M.safeAttribute(target, 'AXEnabled') ~= false
    and geometry.pointInFrame(point, frame) == true and geometry.pointInFrame(point, hitFrame) == true
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
