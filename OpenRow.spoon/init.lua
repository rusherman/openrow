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
  maxScanNodes = 6000,
  scanSlice = 0.008,
  scanTimeout = 3,
  axTimeout = 0.05,
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
    AXRaise = true,
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
obj._wokenPids = {}
obj._scanStats = {}

local function shallowCopy(value)
  local copy = {}
  for key, item in pairs(value) do copy[key] = item end
  return copy
end

local function normalizeText(value)
  if value == nil then return "" end
  return tostring(value):lower()
end

local function searchTextFor(element, role, checkpoint)
  return scanner.computeSearchText({
    role = role,
    title = elementFactory.safeAttribute(element, "AXTitle", checkpoint),
    description = elementFactory.safeAttribute(element, "AXDescription", checkpoint),
    value = elementFactory.safeAttribute(element, "AXValue", checkpoint),
    help = elementFactory.safeAttribute(element, "AXHelp", checkpoint),
  })
end

-- AXManualAccessibility wakes Electron's lazy AX tree without side effects.
-- AXEnhancedUserInterface wakes Chromium/Firefox but breaks some window managers,
-- so it is only set for known browser bundles (or via the wakeChromium override).
local function wakeApp(app, config, checkpoint)
  if not app then return end
  local appElement = hs.axuielement.applicationElement(app)
  if not appElement then return end
  elementFactory.setTimeout(appElement, config.axTimeout)
  if config.wakeNonNative then
    elementFactory.safeSetAttribute(appElement, "AXManualAccessibility", true, checkpoint)
  end
  if config.wakeChromium or scanner.isChromiumApp(app:bundleID(), config.chromiumBundlePatterns) then
    elementFactory.safeSetAttribute(appElement, "AXEnhancedUserInterface", true, checkpoint)
  end
end

function obj:_scanElement(element, targets, seen, depth, screenFrames, screenArea, clipBounds, checkpoint)
  if #targets >= self.config.maxElements or depth > self.config.maxDepth then return end
  if not element then return end
  if (seen._count or 0) >= self.config.maxScanNodes then self._scanTruncated = true; return end
  if checkpoint then checkpoint() end
  elementFactory.setTimeout(element, self.config.axTimeout)

  local role = elementFactory.safeAttribute(element, "AXRole", checkpoint)
  if not elementFactory.markSeen(seen, element, role, checkpoint) then return end
  seen._count = (seen._count or 0) + 1
  local frame = elementFactory.frame(element, checkpoint)
  local enabled = elementFactory.safeAttribute(element, "AXEnabled", checkpoint)
  local actionNames = self.config.controlRoles[role] and {} or elementFactory.safeActionNames(element, checkpoint)

  -- Structural containers can have empty frames while their children are visible.
  local childClip = clipBounds
  if elementFactory.clippingRoles[role] and frame and frame.w > 0 and frame.h > 0 then
    childClip = frame
    if clipBounds then childClip = geometry.intersection(frame, clipBounds) end
    if not geometry.visibleOnScreens(childClip, screenFrames) then return end
  end
  local children = elementFactory.rawChildren(element, self.config.childAttributes, self.config.maxElements, checkpoint, role)
  local childStart = #targets

  for _, child in ipairs(children) do
    self:_scanElement(child, targets, seen, depth + 1, screenFrames, screenArea, childClip, checkpoint)
    if #targets >= self.config.maxElements or self._scanTruncated then return end
  end

  local hasHintableChildren = #targets > childStart

  local hasMeaningful = false
  if role == "AXStaticText" then
    hasMeaningful = scanner.hasMeaningfulText({
      title = elementFactory.safeAttribute(element, "AXTitle", checkpoint),
      value = elementFactory.safeAttribute(element, "AXValue", checkpoint),
      description = elementFactory.safeAttribute(element, "AXDescription", checkpoint),
    })
  end

  frame = geometry.visibleFrame(frame, screenFrames, clipBounds)
  local kind = scanner.targetKind({
    role = role,
    frame = frame,
    enabled = enabled,
    actionNames = actionNames,
    hasMeaningfulText = hasMeaningful,
    hasHintableChildren = hasHintableChildren,
    selectable = (role == 'AXRow' or role == 'AXOutlineRow' or role == 'AXCell')
      and elementFactory.safeAttribute(element, 'AXSelected', checkpoint) ~= nil,
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
      searchText = searchTextFor(element, role, checkpoint),
    })
  end
end

function obj:_scanTargets(checkpoint, app)
  self._scanTruncated = false
  app = app or hs.application.frontmostApplication()
  if not app then return {} end

  local appElement = hs.axuielement.applicationElement(app)
  if not appElement then return {} end

  elementFactory.setTimeout(appElement, self.config.axTimeout)
  local pid = app:pid()
  if not pid or not self._wokenPids[pid] then
    wakeApp(app, self.config, checkpoint)
    if pid then self._wokenPids[pid] = true end
  end

  local rootElements = {}
  local focusedWindow = elementFactory.safeAttribute(appElement, "AXFocusedWindow", checkpoint)
  if focusedWindow then table.insert(rootElements, focusedWindow) end

  local menuBar = elementFactory.safeAttribute(appElement, "AXMenuBar", checkpoint)
  if menuBar then table.insert(rootElements, menuBar) end
  local extrasMenuBar = elementFactory.safeAttribute(appElement, "AXExtrasMenuBar", checkpoint)
  if extrasMenuBar then table.insert(rootElements, extrasMenuBar) end

  if #rootElements == 0 then table.insert(rootElements, appElement) end

  local screens = hs.screen.allScreens()
  local screenFrames = hs.fnutils.imap(screens, function(screen) return screen:fullFrame() end)
  local screenArea = scanner.maxScreenArea(screenFrames)

  local function collectOnce()
    local targets = {}
    local seen = {}
    for _, root in ipairs(rootElements) do
      self:_scanElement(root, targets, seen, 0, screenFrames, screenArea, nil, checkpoint)
      if #targets >= self.config.maxElements or self._scanTruncated then break end
    end
    self._scanStats.nodes = seen._count or 0
    return targets
  end

  local targets = collectOnce()

  local pidWasHealthy = pid and self._scannedPids[pid]
      and self._scannedPids[pid] >= self.config.chromiumScanThreshold

  if scanner.isChromiumApp(app:bundleID(), self.config.chromiumBundlePatterns)
      and #targets < self.config.chromiumScanThreshold
      and not pidWasHealthy then
    log.scan("chromium retry: initial=%d threshold=%d delay=%.0fms",
      #targets, self.config.chromiumScanThreshold, self.config.chromiumRescanDelay * 1000)
    if checkpoint then coroutine.yield(self.config.chromiumRescanDelay) end
    local fresh = collectOnce()
    if #fresh > #targets then
      log.scan("chromium retry yielded %d -> %d", #targets, #fresh)
      targets = fresh
    end
  end

  if pid then
    self._scannedPids[pid] = math.max(#targets, self._scannedPids[pid] or 0)
  end

  if focusedWindow and focusedWindow ~= elementFactory.safeAttribute(appElement, 'AXFocusedWindow', checkpoint) then
    return {}
  end
  return scanner.rankTargets(scanner.dedupeTargets(targets, checkpoint))
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

  local screenFrames = hs.fnutils.imap(hs.screen.allScreens(), function(screen) return screen:fullFrame() end)
  local frame = elementFactory.visibleFrame(target.element, screenFrames)
  local function matches(point)
    local ok, hit = pcall(hs.axuielement.systemElementAtPosition, point)
    return ok and elementFactory.matchesClickPoint(hit, target.element, point)
  end
  if frame then
    local current = { role = target.role, frame = frame,
      activationPoint = elementFactory.safeAttribute(target.element, 'AXActivationPoint') }
    for _, point in ipairs(geometry.clickPoints(current, self.config)) do
      if matches(point) then
        hs.mouse.absolutePosition(point)
        hs.timer.usleep(math.floor(self.config.clickDelay * 1000000))
        -- Hover can reveal another window/control; check again before posting input.
        if matches(point) then
          log.action('verified mouse click point={x=%.1f,y=%.1f}', point.x, point.y)
          hs.eventtap.leftClick(point)
          return true
        end
      end
    end
  end
  log.error('no verified click point for role=%s', target.role or '?')
  hs.alert.show('OpenRow: could not verify the target. Activate again.')
  return false
end

function obj:_handleInput(event)
  local parsed = input.parse(event)
  if parsed.kind ~= "keyDown" then return true end
  local key = parsed.key

  if key == "escape" then
    self:deactivate()
    return true
  end
  if self._scanning then return true end

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
  self._eventtap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
    return self:_handleInput(event)
  end)
  self._eventtap:start()
  self:_startScan(hs.application.frontmostApplication())
end

function obj:_startScan(app)
  local task = { started = hs.timer.absoluteTime(), sliceStarted = hs.timer.absoluteTime() }
  self._scanTask, self._scanning = task, true
  self._scanStats = { nodes = 0, maxSliceMs = 0 }
  local function checkpoint()
    local now = hs.timer.absoluteTime()
    if now - task.started > self.config.scanTimeout * 1e9 then error('scan timed out', 0) end
    if now - task.sliceStarted >= self.config.scanSlice * 1e9 then
      coroutine.yield(0.001)
    end
  end
  task.thread = coroutine.create(function() return self:_scanTargets(checkpoint, app) end)
  local function pump()
    if self._scanTask ~= task then return end
    self._scanTimer = nil
    task.sliceStarted = hs.timer.absoluteTime()
    local ok, result = coroutine.resume(task.thread)
    self._scanStats.maxSliceMs = math.max(self._scanStats.maxSliceMs,
      (hs.timer.absoluteTime() - task.sliceStarted) / 1e6)
    if not ok then
      log.error('scan failed: %s', tostring(result))
      hs.alert.show('OpenRow: scan failed or timed out. Try again.')
      self:deactivate()
      return
    end
    if coroutine.status(task.thread) ~= 'dead' then
      self._scanTimer = hs.timer.doAfter(result or 0.001, pump)
      return
    end
    self._scanTask, self._scanning = nil, false
    self._scanStats.elapsedMs = (hs.timer.absoluteTime() - task.started) / 1e6
    log.scan('nodes=%d targets=%d elapsed=%.0fms maxSlice=%.1fms', self._scanStats.nodes,
      #result, self._scanStats.elapsedMs, self._scanStats.maxSliceMs)
    local rendered, err = pcall(function()
      self._allTargets = result
      self:_filterTargets('')
      if #self._targets == 0 then
        hs.alert.show('OpenRow: no clickable targets found')
        self:deactivate()
        return
      end
      if self._scanTruncated then hs.alert.show('OpenRow: scan limit reached; showing collected targets') end
      self:_drawOverlay()
    end)
    if not rendered then
      log.error('overlay failed: %s', tostring(err))
      self:deactivate()
    end
  end
  self._scanTimer = hs.timer.doAfter(0, pump)
end

function obj:deactivate()
  if self._scanTimer then self._scanTimer:stop(); self._scanTimer = nil end
  self._scanTask, self._scanning = nil, false
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
      if pid then self._scannedPids[pid], self._wokenPids[pid] = nil, nil end
      return
    end

    if eventType ~= hs.application.watcher.activated then return end
    if self._active then self:deactivate() end
    if not (self.config.wakeNonNative or self.config.wakeChromium) then return end
    local pid = app:pid()
    if not pid or not self._wokenPids[pid] then
      wakeApp(app, self.config)
      if pid then self._wokenPids[pid] = true end
    end
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
