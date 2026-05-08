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
obj.license = "MIT"

local spoonPath = hs.spoons.scriptPath()
package.path = package.path .. ";" .. spoonPath .. "?.lua;" .. spoonPath .. "?/init.lua"

local log = require("lib.log")
local alphabet = require("lib.alphabet")
local geometry = require("core.geometry")
local elementFactory = require("core.element_factory")
local scanner = require("core.scanner")
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
obj._labelMap = {}
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

local function searchTextFor(element, role)
  return scanner.computeSearchText({
    role = role,
    title = elementFactory.safeAttribute(element, "AXTitle"),
    description = elementFactory.safeAttribute(element, "AXDescription"),
    value = elementFactory.safeAttribute(element, "AXValue"),
    help = elementFactory.safeAttribute(element, "AXHelp"),
  })
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
  if config.wakeChromium or scanner.isChromiumApp(app:bundleID(), config.chromiumBundlePatterns) then
    elementFactory.safeSetAttribute(appElement, "AXEnhancedUserInterface", true)
  end
end

function obj:_scanElement(element, targets, seen, depth, screenFrames, screenArea)
  if #targets >= self.config.maxElements or depth > self.config.maxDepth then return end
  if not element then return end

  local identity = tostring(element)
  if seen[identity] then return end
  seen[identity] = true

  local role = elementFactory.safeAttribute(element, "AXRole")
  local frame = elementFactory.safeAttribute(element, "AXFrame")
  local enabled = elementFactory.safeAttribute(element, "AXEnabled")
  local actionNames = elementFactory.safeActionNames(element)

  -- Prune subtrees with zero-area frame (collapsed menus, hidden controls).
  if frame and (frame.w <= 0 or frame.h <= 0) then return end

  local children = elementFactory.rawChildren(element, self.config.childAttributes)
  local childStart = #targets

  for _, child in ipairs(children) do
    self:_scanElement(child, targets, seen, depth + 1, screenFrames, screenArea)
    if #targets >= self.config.maxElements then return end
  end

  local hasHintableChildren = #targets > childStart

  local hasMeaningful = false
  if role == "AXStaticText" then
    hasMeaningful = scanner.hasMeaningfulText({
      title = elementFactory.safeAttribute(element, "AXTitle"),
      value = elementFactory.safeAttribute(element, "AXValue"),
      description = elementFactory.safeAttribute(element, "AXDescription"),
    })
  end

  local kind = scanner.targetKind({
    role = role,
    frame = frame,
    enabled = enabled,
    actionNames = actionNames,
    hasMeaningfulText = hasMeaningful,
    hasHintableChildren = hasHintableChildren,
    config = self.config,
    screenFrames = screenFrames,
    screenArea = screenArea,
  })

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
  local screenArea = scanner.maxScreenArea(screenFrames)

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

  if scanner.isChromiumApp(app:bundleID(), self.config.chromiumBundlePatterns)
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

  return scanner.rankTargets(scanner.dedupeTargets(targets))
end

function obj:_assignLabels(targets)
  self._labelLength = alphabet.lengthFor(#targets, self.config.keys)
  self._labelMap = {}
  for index, target in ipairs(targets) do
    target.label = alphabet.labelAt(index, self._labelLength, self.config.keys)
    self._labelMap[target.label] = target
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
      target.searchText = searchTextFor(target.element, target.role)
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

  local clickPoint = geometry.clickPoint(target, self.config)
  log.action("mouse click point={x=%.1f,y=%.1f}", clickPoint.x, clickPoint.y)
  hs.mouse.absolutePosition(clickPoint)
  hs.timer.usleep(math.floor(self.config.clickDelay * 1000000))
  hs.eventtap.leftClick(clickPoint)
  log.action("click via mouse")
  return true
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

  -- "/" enters search mode in label mode. In search mode "/" falls through and
  -- becomes a regular search character (input.character maps it to "/").
  if key == "/" and self._mode ~= "search" then
    self._mode = "search"
    self._query = ""
    hs.alert.show("OpenRow search")
    return true
  end

  local character = parsed.character
  if not character then return true end

  if self._mode == "search" then
    self._query = self._query .. character
    self:_filterTargets(self._query)
    self:_drawOverlay()
    return true
  end

  -- Label mode only accepts characters from the configured alphabet.
  if not self.config.keys:find(character, 1, true) then return true end

  self._labelInput = self._labelInput .. character

  if #self._labelInput >= self._labelLength then
    local exact = self._labelMap[self._labelInput]
    if exact then self:_clickTarget(exact) end
    self:deactivate()
    return true
  end

  local hasPrefix = false
  for label, _ in pairs(self._labelMap) do
    if label:sub(1, #self._labelInput) == self._labelInput then
      hasPrefix = true
      break
    end
  end

  if not hasPrefix then
    hs.alert.show("OpenRow: no label " .. self._labelInput)
    self:deactivate()
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
  self._labelMap = {}

  if self._eventtap then
    self._eventtap:stop()
    self._eventtap = nil
  end

  self:_clearOverlay()
  self._overlay = nil
end

function obj:_startAppWatcher()
  if self._appWatcher then return end
  self._appWatcher = hs.application.watcher.new(function(_, eventType, app)
    if not app then return end

    if eventType == hs.application.watcher.terminated then
      local pid = app:pid()
      if pid then self._scannedPids[pid] = nil end
      return
    end

    if eventType ~= hs.application.watcher.activated then return end
    if not (self.config.wakeNonNative or self.config.wakeChromium) then return end
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
