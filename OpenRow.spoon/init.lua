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

local spoonPath = hs.spoons.scriptPath()
package.path = package.path .. ";" .. spoonPath .. "?.lua;" .. spoonPath .. "?/init.lua"

local log = require("lib.log")
local alphabet = require("lib.alphabet")
local geometry = require("core.geometry")
local Element = require("core.element")
local elementFactory = require("core.element_factory")
local Overlay = require("core.overlay")
local input = require("core.input")

obj.config = {
  hotkey = { { "cmd", "shift" }, "space" },
  keys = "asdfjkl;ghqwertyuiopzxcvbnm",
  maxDepth = 32,
  maxElements = 1500,
  minSize = 4,
  minListItemWidth = 24,
  minListItemHeight = 12,
  maxTargetAreaRatio = 0.85,
  genericClickXRatio = 0.5,
  genericClickYRatio = 0.5,
  linkClickInset = 5,
  overlayTextSize = 14,
  overlayPaddingX = 5,
  overlayPaddingY = 2,
  overlayRadius = 4,
  dimOpacity = 0.08,
  clickDelay = 0.03,
  debug = { scan = false, input = false, action = false },
  wakeNonNative = true,
  wakeChromium = false,
  chromiumBundlePatterns = {
    "^com%.google%.Chrome",
    "^com%.brave%.",
    "^com%.microsoft%.edgemac",
    "^org%.chromium%.",
    "^org%.mozilla%.firefox",
    "^company%.thebrowser%.Browser",
    "^com%.vivaldi%.",
    "^com%.operasoftware%.",
  },
  chromiumScanThreshold = 40,
  chromiumRescanDelay = 0.2,
  controlRoles = {
    AXButton = true,
    AXCheckBox = true,
    AXColorWell = true,
    AXComboBox = true,
    AXDisclosureTriangle = true,
    AXImage = true,
    AXLink = true,
    AXMenuBarItem = true,
    AXMenuButton = true,
    AXMenuItem = true,
    AXPopUpButton = true,
    AXRadioButton = true,
    AXSlider = true,
    AXTab = true,
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
  ignoredActions = {
    AXShowMenu = true,
    AXScrollToVisible = true,
    AXShowDefaultUI = true,
    AXShowAlternateUI = true,
  },
  childAttributes = {
    "AXChildren",
    "AXContents",
  },
}

obj._active = false
obj._mode = "label"
obj._query = ""
obj._labelInput = ""
obj._allTargets = {}
obj._targets = {}
obj._overlay = nil
obj._eventtap = nil
obj._hotkey = nil
obj._labelLength = 1
obj._appWatcher = nil
obj._scannedPids = {}

local function shallowCopy(value)
  local copy = {}
  for key, item in pairs(value) do copy[key] = item end
  return copy
end

local function normalizeText(value)
  if value == nil then return "" end
  return tostring(value):lower()
end

local function hasActionableAction(actionNames, ignoredActions)
  for _, action in ipairs(actionNames) do
    if not ignoredActions[action] then return true end
  end
  return false
end

local function hasMeaningfulText(element)
  local text = table.concat({
    tostring(elementFactory.safeAttribute(element, "AXTitle") or ""),
    tostring(elementFactory.safeAttribute(element, "AXValue") or ""),
    tostring(elementFactory.safeAttribute(element, "AXDescription") or ""),
  }, "")
  return text:match("%S") ~= nil
end

local function computeSearchText(element, role)
  local title = tostring(elementFactory.safeAttribute(element, "AXTitle") or "")
  local desc  = tostring(elementFactory.safeAttribute(element, "AXDescription") or "")
  local value = tostring(elementFactory.safeAttribute(element, "AXValue") or "")
  local help  = tostring(elementFactory.safeAttribute(element, "AXHelp") or "")
  return ((role or "") .. " " .. title .. " " .. desc .. " " .. value .. " " .. help):lower()
end

local function isChromiumApp(app, patterns)
  if not app or not patterns then return false end
  local bid = app:bundleID() or ""
  for _, pattern in ipairs(patterns) do
    if bid:match(pattern) then return true end
  end
  return false
end

-- AXManualAccessibility wakes Electron's lazy AX tree without side effects.
-- AXEnhancedUserInterface wakes Chromium/Firefox but breaks some window managers,
-- so it is only set for known browser bundles (or via the wakeChromium override).
local function wakeApp(app, config)
  if not app then return end
  local appElement = hs.axuielement.applicationElement(app)
  if not appElement then return end
  if config.wakeNonNative then
    elementFactory.safeSetAttribute(appElement, "AXManualAccessibility", true)
  end
  if config.wakeChromium or isChromiumApp(app, config.chromiumBundlePatterns) then
    elementFactory.safeSetAttribute(appElement, "AXEnhancedUserInterface", true)
  end
end

local function maxScreenArea(screenFrames)
  local maxArea = 0
  for _, screenFrame in ipairs(screenFrames) do
    maxArea = math.max(maxArea, screenFrame.w * screenFrame.h)
  end
  return math.max(1, maxArea)
end

local function targetKind(element, role, frame, enabled, actionNames, config, screenFrames, screenArea, hasHintableChildren)
  if not role or enabled == false or not geometry.visibleOnScreens(frame, screenFrames) then return nil end
  if frame.w < config.minSize or frame.h < config.minSize then return nil end

  local areaRatio = (frame.w * frame.h) / screenArea
  if areaRatio > config.maxTargetAreaRatio then return nil end

  if config.roleFallbacks[role] and hasHintableChildren then return nil end

  if config.controlRoles[role] then return "role" end
  if hasActionableAction(actionNames, config.ignoredActions) then return "action" end

  if config.roleFallbacks[role]
      and frame.w >= config.minListItemWidth
      and frame.h >= config.minListItemHeight then
    if role == "AXStaticText" and not hasMeaningfulText(element) then return nil end
    return "fallback"
  end

  return nil
end

local function dedupeTargets(targets)
  local result = {}

  for _, target in ipairs(targets) do
    local shouldAdd = true

    for _, existing in ipairs(result) do
      if geometry.framesAlmostEqual(existing.frame, target.frame) then
        if not (existing.kind == "fallback" and target.kind ~= "fallback") then
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

        if existing.kind == "fallback" and target.kind ~= "fallback"
            and (sameFrame or existingContainsTarget) then
          table.remove(result, index)
        end
      end

      table.insert(result, target)
    end
  end

  return result
end

local function rankTargets(targets)
  table.sort(targets, function(left, right)
    if math.abs(left.frame.y - right.frame.y) > 8 then return left.frame.y < right.frame.y end
    return left.frame.x < right.frame.x
  end)
  return targets
end

function obj:_scanElement(element, targets, seen, depth, screenFrames, screenArea)
  if #targets >= self.config.maxElements or depth > self.config.maxDepth then return end
  if not element then return end

  local identity = tostring(element)
  if seen[identity] then return end
  seen[identity] = true

  local snapshot = elementFactory.from(element)
  local role = Element.role(snapshot)
  local frame = Element.frame(snapshot)
  local enabled = Element.enabled(snapshot)
  local actionNames = Element.actions(snapshot)

  -- Prune subtrees with zero-area frame (collapsed menus, hidden controls).
  if frame and (frame.w <= 0 or frame.h <= 0) then return end

  local children = elementFactory.rawChildren(element, self.config.childAttributes)

  for _, child in ipairs(children) do
    self:_scanElement(child, targets, seen, depth + 1, screenFrames, screenArea)
    if #targets >= self.config.maxElements then return end
  end

  local hasHintableChildren = false
  if frame then
    for _, target in ipairs(targets) do
      if target.depth > depth and geometry.contains(frame, target.frame) then
        hasHintableChildren = true
        break
      end
    end
  end

  local kind = targetKind(element, role, frame, enabled, actionNames, self.config, screenFrames, screenArea, hasHintableChildren)

  if kind then
    table.insert(targets, {
      element = element,
      role = role,
      kind = kind,
      frame = frame,
      depth = depth,
    })
  end
end

function obj:_scanTargets()
  local app = hs.application.frontmostApplication()
  if not app then return {} end

  local appElement = hs.axuielement.applicationElement(app)
  if not appElement then return {} end

  wakeApp(app, self.config)

  local rootElements = {}
  local focusedWindow = elementFactory.safeAttribute(appElement, "AXFocusedWindow")
  if focusedWindow then table.insert(rootElements, focusedWindow) end

  local menuBar = elementFactory.safeAttribute(appElement, "AXMenuBar")
  if menuBar then table.insert(rootElements, menuBar) end
  local extrasMenuBar = elementFactory.safeAttribute(appElement, "AXExtrasMenuBar")
  if extrasMenuBar then table.insert(rootElements, extrasMenuBar) end

  if #rootElements == 0 then table.insert(rootElements, appElement) end

  local screens = hs.screen.allScreens()
  local screenFrames = hs.fnutils.imap(screens, function(screen) return screen:fullFrame() end)
  local screenArea = maxScreenArea(screenFrames)

  local function collectOnce()
    local targets = {}
    local seen = {}
    for _, root in ipairs(rootElements) do
      self:_scanElement(root, targets, seen, 0, screenFrames, screenArea)
      if #targets >= self.config.maxElements then break end
    end
    return targets
  end

  local targets = collectOnce()

  local pid = app:pid()
  local pidWasHealthy = pid and self._scannedPids[pid]
      and self._scannedPids[pid] >= self.config.chromiumScanThreshold

  if isChromiumApp(app, self.config.chromiumBundlePatterns)
      and #targets < self.config.chromiumScanThreshold
      and not pidWasHealthy then
    log.scan("chromium retry: initial=%d threshold=%d delay=%.0fms",
      #targets, self.config.chromiumScanThreshold, self.config.chromiumRescanDelay * 1000)
    hs.timer.usleep(math.floor(self.config.chromiumRescanDelay * 1000000))
    local fresh = collectOnce()
    if #fresh > #targets then
      log.scan("chromium retry yielded %d -> %d", #targets, #fresh)
      targets = fresh
    end
  end

  if pid then
    self._scannedPids[pid] = math.max(#targets, self._scannedPids[pid] or 0)
  end

  return rankTargets(dedupeTargets(targets))
end

function obj:_assignLabels(targets)
  self._labelLength = alphabet.lengthFor(#targets, self.config.keys)
  for index, target in ipairs(targets) do
    target.label = alphabet.labelAt(index, self._labelLength, self.config.keys)
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
    if not target.searchText then
      target.searchText = computeSearchText(target.element, target.role)
    end
    if target.searchText:find(normalized, 1, true) then table.insert(filtered, target) end
  end
  self._targets = self:_assignLabels(filtered)
end

function obj:_clearOverlay()
  if self._overlay then self._overlay:clear() end
end

function obj:_drawOverlay()
  self:_clearOverlay()
  if not self._overlay then self._overlay = Overlay.new() end
  self._overlay:showDim(self.config.dimOpacity)

  local items = {}
  for _, target in ipairs(self._targets) do
    items[#items + 1] = { frame = target.frame, text = target.label }
  end
  self._overlay:showLabels(items, {
    textSize = self.config.overlayTextSize,
    paddingX = self.config.overlayPaddingX,
    paddingY = self.config.overlayPaddingY,
    radius = self.config.overlayRadius,
  })
end

function obj:_clickTarget(target)
  log.action(
    "click label=%s role=%s kind=%s frame={x=%.1f,y=%.1f,w=%.1f,h=%.1f}",
    target.label or "?", target.role or "?", target.kind or "?",
    target.frame.x, target.frame.y, target.frame.w, target.frame.h
  )

  self:_clearOverlay()

  elementFactory.safeSetAttribute(target.element, "AXFocused", true)
  elementFactory.safeSetAttribute(target.element, "AXSelected", true)

  local clickPoint = geometry.clickPoint(target, self.config)
  log.action("mouse click point={x=%.1f,y=%.1f}", clickPoint.x, clickPoint.y)
  hs.mouse.absolutePosition(clickPoint)
  hs.timer.usleep(math.floor(self.config.clickDelay * 1000000))
  hs.eventtap.leftClick(clickPoint)
  log.action("click via mouse")
  return true
end

function obj:_targetForLabel(label)
  for _, target in ipairs(self._targets) do
    if target.label == label then return target end
  end
  return nil
end

function obj:_handleInput(event)
  local parsed = input.parse(event)
  if parsed.kind ~= "keyDown" then return true end
  local key = parsed.key
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
  self._overlay = nil
end

function obj:_startAppWatcher()
  if self._appWatcher then return end
  if not (self.config.wakeNonNative or self.config.wakeChromium) then return end
  self._appWatcher = hs.application.watcher.new(function(_, eventType, app)
    if eventType ~= hs.application.watcher.activated or not app then return end
    wakeApp(app, self.config)
    log.scan("wake app=%s bundle=%s", app:name() or "?", app:bundleID() or "?")
  end)
  self._appWatcher:start()
end

function obj:bindHotkeys(mapping)
  local hotkey = mapping and mapping.activate or self.config.hotkey
  if self._hotkey then self._hotkey:delete() end
  self._hotkey = hs.hotkey.bind(hotkey[1], hotkey[2], function() self:activate() end)
  return self
end

function obj:init()
  if type(self.config.debug) == "boolean" then
    log.config = { scan = self.config.debug, input = self.config.debug, action = self.config.debug }
  else
    log.config = self.config.debug
  end
  self:_startAppWatcher()
  return self
end

return obj
