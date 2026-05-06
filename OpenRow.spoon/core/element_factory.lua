-- OpenRow.spoon/core/element_factory.lua — hs.axuielement adapter.

local Element = require("core.element")

local M = {}

function M.safeAttribute(element, attribute)
  local ok, value = pcall(function() return element:attributeValue(attribute) end)
  if ok then return value end
  return nil
end

function M.safeSetAttribute(element, attribute, value)
  local ok, result = pcall(function() return element:setAttributeValue(attribute, value) end)
  return ok and result ~= false
end

function M.safeActionNames(element)
  local ok, value = pcall(function()
    if element.actionNames then return element:actionNames() end
    return element:attributeValue("AXActions")
  end)
  if ok and type(value) == "table" then return value end
  return {}
end

local function appendUniqueChildren(children, seenChildren, values)
  if type(values) ~= "table" then return end
  for _, child in ipairs(values) do
    local identity = tostring(child)
    if not seenChildren[identity] then
      seenChildren[identity] = true
      table.insert(children, child)
    end
  end
end

function M.rawChildren(element, childAttributes)
  local children = {}
  local seenChildren = {}

  for _, attribute in ipairs(childAttributes) do
    appendUniqueChildren(children, seenChildren, M.safeAttribute(element, attribute))
  end

  return children
end

function M.from(element)
  return Element.new({
    rawId = tostring(element),
    role = M.safeAttribute(element, "AXRole"),
    frame = M.safeAttribute(element, "AXFrame"),
    actions = M.safeActionNames(element),
    enabled = M.safeAttribute(element, "AXEnabled"),
  })
end

return M
