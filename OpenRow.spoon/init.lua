--- === OpenRow ===
--- Keyboard-first clicking prototype inspired by Homerow.
---
--- Install by copying this directory to ~/.hammerspoon/Spoons/OpenRow.spoon
--- and adding `hs.loadSpoon("OpenRow"):bindHotkeys()` to ~/.hammerspoon/init.lua.

local obj = {}
obj.__index = obj

obj.name = "OpenRow"
obj.version = "0.1.0"
obj.author = "OpenRow contributors"
obj.homepage = "https://github.com/openrow/openrow"
obj.license = "MIT"

obj.logger = hs.logger.new("OpenRow", "info")

obj.config = {
  hotkey = { { "cmd", "shift" }, "space" },
  keys = "asdfjkl;ghqwertyuiopzxcvbnm",
  maxDepth = 16,
  maxElements = 500,
  minSize = 4,
  minListItemWidth = 24,
  minListItemHeight = 12,
  maxTargetAreaRatio = 0.85,
  listClickXRatio = 0.18,
  listClickYRatio = 0.42,
  listClickMaxXInset = 64,
  genericClickXRatio = 0.5,
  genericClickYRatio = 0.5,
  overlayTextSize = 14,
  overlayPaddingX = 5,
  overlayPaddingY = 2,
  overlayRadius = 4,
  dimOpacity = 0.08,
  clickDelay = 0.03,
  debug = false,
  scanRoles = {
    AXButton = true,
    AXCheckBox = true,
    AXColorWell = true,
    AXComboBox = true,
    AXDisclosureTriangle = true,
    AXImage = true,
    AXLink = true,
    AXCell = true,
    AXColumn = false,
    AXGroup = false,
    AXOutlineRow = true,
    AXRow = true,
    AXMenuButton = true,
    AXMenuItem = true,
    AXPopUpButton = true,
    AXRadioButton = true,
    AXSlider = true,
    AXStaticText = false,
    AXTextArea = true,
    AXTextField = true,
  },
  roleFallbacks = {
    AXCell = true,
    AXGroup = true,
    AXOutlineRow = true,
    AXRow = true,
    AXStaticText = true,
  },
  childAttributes = {
    "AXChildren",
    "AXVisibleChildren",
    "AXChildrenInNavigationOrder",
    "AXRows",
    "AXColumns",
    "AXCells",
    "AXContents",
  },
  preferMouseRoles = {
    AXCell = true,
    AXGroup = true,
    AXOutlineRow = true,
    AXRow = true,
    AXStaticText = true,
  },
}

obj._active = false
obj._mode = "label"
obj._query = ""
obj._labelInput = ""
obj._allTargets = {}
obj._targets = {}
obj._canvases = {}
obj._eventtap = nil
obj._hotkey = nil
obj._labelLength = 1

local function shallowCopy(value)
  local copy = {}
  for key, item in pairs(value) do copy[key] = item end
  return copy
end

local function normalizeText(value)
  if value == nil then return "" end
  return tostring(value):lower()
end

local function safeAttribute(element, attribute)
  local ok, value = pcall(function() return element:attributeValue(attribute) end)
  if ok then return value end
  return nil
end

local function safeAction(element, action)
  local ok, result = pcall(function() return element:performAction(action) end)
  return ok and result ~= false
end

local function safeSetAttribute(element, attribute, value)
  local ok, result = pcall(function() return element:setAttributeValue(attribute, value) end)
  return ok and result ~= false
end

local function frameCenter(frame)
  return {
    x = frame.x + frame.w / 2,
    y = frame.y + frame.h / 2,
  }
end

local function targetClickPoint(target, config)
  if config.preferMouseRoles[target.role] then
    local xInset = math.min(config.listClickMaxXInset, math.max(8, target.frame.w * config.listClickXRatio))
    return {
      x = target.frame.x + xInset,
      y = target.frame.y + target.frame.h * config.listClickYRatio,
    }
  end

  return {
    x = target.frame.x + target.frame.w * config.genericClickXRatio,
    y = target.frame.y + target.frame.h * config.genericClickYRatio,
  }
end

local function frameVisible(frame, screens)
  if not frame or not frame.x or not frame.y or not frame.w or not frame.h then return false end
  if frame.w <= 0 or frame.h <= 0 then return false end

  for _, screen in ipairs(screens) do
    local visible = screen:fullFrame()
    local intersects = frame.x < visible.x + visible.w
      and frame.x + frame.w > visible.x
      and frame.y < visible.y + visible.h
      and frame.y + frame.h > visible.y
    if intersects then return true end
  end

  return false
end

local function buildSearchText(element, role)
  local parts = {
    role,
    safeAttribute(element, "AXTitle"),
    safeAttribute(element, "AXDescription"),
    safeAttribute(element, "AXValue"),
    safeAttribute(element, "AXHelp"),
  }
  return normalizeText(table.concat(hs.fnutils.imap(parts, function(part)
    return part and tostring(part) or ""
  end), " "))
end

local function safeActionNames(element)
  local ok, value = pcall(function()
    if element.actionNames then return element:actionNames() end
    return element:attributeValue("AXActions")
  end)
  if ok and type(value) == "table" then return value end
  return {}
end

local function hasAction(actionNames, expected)
  for _, action in ipairs(actionNames) do
    if action == expected then return true end
  end
  return false
end

local function targetKind(role, frame, enabled, actionNames, config, screens)
  if not role or enabled == false or not frameVisible(frame, screens) then return nil end
  if frame.w < config.minSize or frame.h < config.minSize then return nil end

  local screenFrame = hs.screen.mainScreen():fullFrame()
  local screenArea = math.max(1, screenFrame.w * screenFrame.h)
  local areaRatio = (frame.w * frame.h) / screenArea
  if areaRatio > config.maxTargetAreaRatio then return nil end

  if config.scanRoles[role] then return "role" end
  if hasAction(actionNames, "AXPress") or hasAction(actionNames, "AXShowMenu") then return "action" end

  if config.roleFallbacks[role]
      and frame.w >= config.minListItemWidth
      and frame.h >= config.minListItemHeight then
    return "fallback"
  end

  return nil
end

local function rectContains(outer, inner)
  return outer.x <= inner.x
    and outer.y <= inner.y
    and outer.x + outer.w >= inner.x + inner.w
    and outer.y + outer.h >= inner.y + inner.h
end

local function dedupeTargets(targets)
  local result = {}

  for _, target in ipairs(targets) do
    local shouldAdd = true

    for index = #result, 1, -1 do
      local existing = result[index]
      local sameCenter = math.abs(frameCenter(existing.frame).x - frameCenter(target.frame).x) < 3
        and math.abs(frameCenter(existing.frame).y - frameCenter(target.frame).y) < 3
      local sameSize = math.abs(existing.frame.w - target.frame.w) < 3
        and math.abs(existing.frame.h - target.frame.h) < 3

      if sameCenter and sameSize then
        if existing.kind == "fallback" and target.kind ~= "fallback" then
          table.remove(result, index)
        else
          shouldAdd = false
        end
        break
      end

      if target.kind == "fallback" and rectContains(existing.frame, target.frame) then
        shouldAdd = false
        break
      end
    end

    if shouldAdd then table.insert(result, target) end
  end

  return result
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

local function collectChildren(element, childAttributes)
  local children = {}
  local seenChildren = {}

  for _, attribute in ipairs(childAttributes) do
    appendUniqueChildren(children, seenChildren, safeAttribute(element, attribute))
  end

  return children
end

local function rankTargets(targets)
  table.sort(targets, function(left, right)
    if math.abs(left.frame.y - right.frame.y) > 8 then return left.frame.y < right.frame.y end
    return left.frame.x < right.frame.x
  end)
  return targets
end

function obj:_labelSequence(index, length)
  local alphabet = self.config.keys
  local base = #alphabet
  local label = ""
  local number = index - 1

  for _ = 1, length do
    local remainder = (number % base) + 1
    label = alphabet:sub(remainder, remainder) .. label
    number = math.floor(number / base)
  end

  return label
end

function obj:_labelLengthForCount(count)
  local base = #self.config.keys
  local length = 1
  local capacity = base

  while count > capacity do
    length = length + 1
    capacity = capacity * base
  end

  return length
end

function obj:_scanElement(element, targets, seen, depth, screens)
  if #targets >= self.config.maxElements or depth > self.config.maxDepth then return end
  if not element then return end

  local identity = tostring(element)
  if seen[identity] then return end
  seen[identity] = true

  local role = safeAttribute(element, "AXRole")
  local frame = safeAttribute(element, "AXFrame")
  local enabled = safeAttribute(element, "AXEnabled")
  local actionNames = safeActionNames(element)
  local kind = targetKind(role, frame, enabled, actionNames, self.config, screens)

  if kind then
    table.insert(targets, {
      element = element,
      role = role,
      kind = kind,
      frame = frame,
      searchText = buildSearchText(element, role),
    })
  end

  local children = collectChildren(element, self.config.childAttributes)
  for _, child in ipairs(children) do
    self:_scanElement(child, targets, seen, depth + 1, screens)
    if #targets >= self.config.maxElements then return end
  end
end

function obj:_scanTargets()
  local app = hs.application.frontmostApplication()
  if not app then return {} end

  local appElement = hs.axuielement.applicationElement(app)
  if not appElement then return {} end

  local windows = safeAttribute(appElement, "AXWindows") or {}
  local rootElements = {}
  local focusedWindow = safeAttribute(appElement, "AXFocusedWindow")

  if focusedWindow then table.insert(rootElements, focusedWindow) end
  for _, window in ipairs(windows) do
    if tostring(window) ~= tostring(focusedWindow) then table.insert(rootElements, window) end
  end
  if #rootElements == 0 then table.insert(rootElements, appElement) end

  local targets = {}
  local seen = {}
  local screens = hs.screen.allScreens()

  for _, root in ipairs(rootElements) do
    self:_scanElement(root, targets, seen, 0, screens)
    if #targets >= self.config.maxElements then break end
  end

  return rankTargets(dedupeTargets(targets))
end

function obj:_assignLabels(targets)
  self._labelLength = self:_labelLengthForCount(#targets)
  for index, target in ipairs(targets) do
    target.label = self:_labelSequence(index, self._labelLength)
  end
  return targets
end

function obj:_filterTargets(query)
  local normalized = normalizeText(query)
  if normalized == "" then
    self._targets = self:_assignLabels(shallowCopy(self._allTargets))
    return
  end

  local filtered = {}
  for _, target in ipairs(self._allTargets) do
    if target.searchText:find(normalized, 1, true) then table.insert(filtered, target) end
  end
  self._targets = self:_assignLabels(filtered)
end

function obj:_clearOverlay()
  for _, canvas in ipairs(self._canvases) do canvas:delete() end
  self._canvases = {}
end

function obj:_drawOverlay()
  self:_clearOverlay()

  for _, screen in ipairs(hs.screen.allScreens()) do
    local fullFrame = screen:fullFrame()
    local dim = hs.canvas.new(fullFrame)
    dim:level(hs.canvas.windowLevels.overlay)
    dim:behavior({ hs.canvas.windowBehaviors.canJoinAllSpaces, hs.canvas.windowBehaviors.stationary })
    dim:appendElements({
      type = "rectangle",
      action = "fill",
      frame = { x = 0, y = 0, w = fullFrame.w, h = fullFrame.h },
      fillColor = { white = 0, alpha = self.config.dimOpacity },
    })
    dim:show()
    table.insert(self._canvases, dim)
  end

  for _, target in ipairs(self._targets) do
    local center = frameCenter(target.frame)
    local textSize = self.config.overlayTextSize
    local width = math.max(22, (#target.label * textSize * 0.62) + self.config.overlayPaddingX * 2)
    local height = textSize + self.config.overlayPaddingY * 2 + 3
    local canvasFrame = {
      x = center.x - width / 2,
      y = center.y - height / 2,
      w = width,
      h = height,
    }

    local canvas = hs.canvas.new(canvasFrame)
    canvas:level(hs.canvas.windowLevels.overlay)
    canvas:behavior({ hs.canvas.windowBehaviors.canJoinAllSpaces, hs.canvas.windowBehaviors.stationary })
    canvas:appendElements({
      {
        type = "rectangle",
        action = "fill",
        roundedRectRadii = { xRadius = self.config.overlayRadius, yRadius = self.config.overlayRadius },
        frame = { x = 0, y = 0, w = width, h = height },
        fillColor = { red = 0.98, green = 0.82, blue = 0.22, alpha = 0.95 },
      },
      {
        type = "text",
        text = target.label,
        textAlignment = "center",
        textSize = textSize,
        textColor = { red = 0.08, green = 0.08, blue = 0.08, alpha = 1 },
        frame = { x = 0, y = 1, w = width, h = height },
      },
    })
    canvas:show()
    table.insert(self._canvases, canvas)
  end
end

function obj:_clickTarget(target)
  if self.config.debug then
    self.logger.i(string.format(
      "click label=%s role=%s kind=%s frame={x=%.1f,y=%.1f,w=%.1f,h=%.1f}",
      target.label or "?",
      target.role or "?",
      target.kind or "?",
      target.frame.x,
      target.frame.y,
      target.frame.w,
      target.frame.h
    ))
  end

  self:_clearOverlay()

  local preferMouse = self.config.preferMouseRoles[target.role] == true

  if not preferMouse and (target.kind == "role" or target.kind == "action") then
    if safeAction(target.element, "AXPress") then
      if self.config.debug then self.logger.i("click via AXPress") end
      return true
    end
  end

  safeSetAttribute(target.element, "AXFocused", true)
  safeSetAttribute(target.element, "AXSelected", true)

  local clickPoint = targetClickPoint(target, self.config)
  if self.config.debug then
    self.logger.i(string.format("mouse fallback point={x=%.1f,y=%.1f}", clickPoint.x, clickPoint.y))
  end
  hs.mouse.absolutePosition(clickPoint)
  hs.timer.usleep(math.floor(self.config.clickDelay * 1000000))
  hs.eventtap.leftClick(clickPoint)
  if self.config.debug then self.logger.i("click via mouse fallback") end
  return true
end

function obj:_targetForLabel(label)
  for _, target in ipairs(self._targets) do
    if target.label == label then return target end
  end
  return nil
end

function obj:_handleInput(event)
  local eventType = event:getType()
  if eventType ~= hs.eventtap.event.types.keyDown then return true end

  local key = hs.keycodes.map[event:getKeyCode()]
  if key == "escape" then
    self:deactivate()
    return true
  end

  if key == "delete" then
    if self._mode == "search" then
      self._query = self._query:sub(1, -2)
      self:_filterTargets(self._query)
      self:_drawOverlay()
    else
      self._labelInput = self._labelInput:sub(1, -2)
    end
    return true
  end

  if key == "return" then
    local target = self._targets[1]
    if target then self:_clickTarget(target) end
    self:deactivate()
    return true
  end

  if key == "/" and self._mode ~= "search" then
    self._mode = "search"
    self._query = ""
    hs.alert.show("OpenRow search")
    return true
  end

  if key and #key == 1 then
    if self._mode == "search" then
      self._query = self._query .. key
      self:_filterTargets(self._query)
      self:_drawOverlay()
    else
      self._labelInput = self._labelInput .. key

      if #self._labelInput >= self._labelLength then
        local exact = self:_targetForLabel(self._labelInput)
        if exact then
          self:_clickTarget(exact)
        end
        self:deactivate()
        return true
      end

      local hasPrefix = false
      for _, target in ipairs(self._targets) do
        if target.label:sub(1, #self._labelInput) == self._labelInput then
          hasPrefix = true
          break
        end
      end

      if not hasPrefix then
        hs.alert.show("OpenRow: no label " .. self._labelInput)
        self:deactivate()
        return true
      end
    end
    return true
  end

  return true
end

function obj:activate()
  if self._active then self:deactivate() return end

  if not hs.accessibilityState(true) then
    hs.alert.show("OpenRow needs Accessibility permission for Hammerspoon")
    return
  end

  self._active = true
  self._mode = "label"
  self._query = ""
  self._labelInput = ""
  self._allTargets = self:_scanTargets()
  self:_filterTargets("")

  if #self._targets == 0 then
    hs.alert.show("OpenRow: no clickable targets found")
    self:deactivate()
    return
  end

  self:_drawOverlay()
  self._eventtap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
    return self:_handleInput(event)
  end)
  self._eventtap:start()
end

function obj:deactivate()
  self._active = false
  self._mode = "label"
  self._query = ""
  self._labelInput = ""
  self._allTargets = {}
  self._targets = {}

  if self._eventtap then
    self._eventtap:stop()
    self._eventtap = nil
  end

  self:_clearOverlay()
end

function obj:bindHotkeys(mapping)
  local hotkey = mapping and mapping.activate or self.config.hotkey
  if self._hotkey then self._hotkey:delete() end
  self._hotkey = hs.hotkey.bind(hotkey[1], hotkey[2], function() self:activate() end)
  return self
end

function obj:init()
  return self
end

return obj
