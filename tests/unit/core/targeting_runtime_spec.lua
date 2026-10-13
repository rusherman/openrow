-- Exercise the actual scanner/click orchestration with AX-shaped elements.
local screens = { { x = 0, y = 0, w = 1000, h = 800 } }
local AX = { __eq = function(a, b) return a.identity == b.identity end }
local function element(role, frame, children, actions)
  local e = setmetatable({ identity = {}, attributes = { AXRole = role, AXFrame = frame, AXChildren = children or {} } }, AX)
  function e:attributeValue(key) return self.attributes[key] end
  function e:actionNames() return actions or {} end
  function e:pid() return self.attributes.pid or 1 end
  function e:parameterizedAttributeValue(key, predicate)
    self.predicate = predicate
    return self.searchResults
  end
  for _, child in ipairs(children or {}) do child.attributes.AXParent = e end
  return e
end
local function runtime(fn, screenFrames)
  screenFrames = screenFrames or screens
  local oldHS = hs
  local clicks = {}
  hs = {
    spoons = { scriptPath = function() return './OpenRow.spoon/' end },
    screen = { allScreens = function()
      local result = {}
      for _, f in ipairs(screenFrames) do
        local frame = f
        result[#result + 1] = { fullFrame = function() return frame end }
      end
      return result
    end },
    fnutils = { imap = function(items, fn)
      local result = {}; for _, item in ipairs(items) do result[#result + 1] = fn(item) end; return result
    end },
    mouse = { absolutePosition = function() end },
    timer = { usleep = function() end },
    eventtap = { leftClick = function(point) clicks[#clicks + 1] = point end },
    axuielement = { systemElementAtPosition = function() return nil end },
    alert = { show = function() end },
  }
  local app = dofile('OpenRow.spoon/init.lua')
  local ok, err = pcall(fn, app, clicks)
  hs = oldHS
  if not ok then error(err, 0) end
end
local function scan(app, root)
  local targets = {}
  app:_scanElement(root, targets, {}, 0, screens, 800000)
  return require('core.scanner').dedupeTargets(targets)
end
local frame = { x = 10, y = 20, w = 100, h = 40 }

describe('AX target regression', function()
  it('finds a button beneath a zero-size structural container', function()
    runtime(function(app)
      local button = element('AXButton', frame)
      local root = element('AXGroup', { x = 0, y = 0, w = 0, h = 0 }, { button })
      assert_equals(#scan(app, root), 1)
    end)
  end)
  it('finds visible rows absent from AXChildren', function()
    runtime(function(app)
      local row = element('AXRow', frame)
      local root = element('AXTable', { x = 0, y = 0, w = 500, h = 400 })
      root.attributes.AXVisibleRows = { row }
      assert_equals(#scan(app, root), 1)
    end)
  end)
  it('finds navigation-only children', function()
    runtime(function(app)
      local root = element('AXWindow', { x = 0, y = 0, w = 500, h = 400 })
      root.attributes.AXChildrenInNavigationOrder = { element('AXButton', frame) }
      assert_equals(#scan(app, root), 1)
    end)
  end)
  it('keeps an actionable row as well as its auxiliary button', function()
    runtime(function(app)
      local button = element('AXButton', { x = 80, y = 20, w = 20, h = 20 })
      local row = element('AXRow', frame, { button }, { 'AXPress' })
      assert_equals(#scan(app, row), 2)
    end)
  end)
  it('finds browser controls through a bounded visible search predicate', function()
    runtime(function(app)
      local root = element('AXWebArea', { x = 0, y = 0, w = 500, h = 400 })
      root.searchResults = { element('AXButton', frame) }
      assert_equals(#scan(app, root), 1)
      assert_true(root.predicate.AXVisibleOnly)
      assert_equals(root.predicate.AXResultsLimit, app.config.maxElements)
    end)
  end)
  it('keeps a semantic link instead of its equally sized actionable text child', function()
    runtime(function(app)
      local text = element('AXStaticText', frame, {}, { 'AXPress' })
      local link = element('AXLink', frame, { text })
      local targets = scan(app, link)
      assert_equals(#targets, 1)
      assert_equals(targets[1].role, 'AXLink')
    end)
  end)
  it('preserves custom clickable children absent from a successful browser search', function()
    runtime(function(app)
      local custom = element('AXUnknown', { x = 150, y = 20, w = 80, h = 30 }, {}, { 'AXPress' })
      local root = element('AXWebArea', { x = 0, y = 0, w = 500, h = 400 }, { custom })
      root.searchResults = { element('AXButton', frame) }
      assert_equals(#scan(app, root), 2)
    end)
  end)
  it('excludes targets clipped entirely by their scroll area', function()
    runtime(function(app)
      local button = element('AXButton', { x = 10, y = 150, w = 80, h = 30 })
      local root = element('AXScrollArea', { x = 0, y = 0, w = 100, h = 100 }, { button })
      assert_equals(#scan(app, root), 0)
    end)
  end)
  it('reads a fresh frame and activation point before clicking', function()
    runtime(function(app, clicks)
      local button = element('AXButton', { x = 200, y = 100, w = 100, h = 40 })
      button.attributes.AXActivationPoint = { x = 210, y = 110 }
      hs.axuielement.systemElementAtPosition = function(point)
        if point.x == 210 and point.y == 110 then return button end
      end
      assert_true(app:_clickTarget({ element = button, role = 'AXButton', frame = frame, kind = 'role' }))
      assert_deep_equals(clicks[1], { x = 210, y = 110 })
    end)
  end)
  it('tries a second link point when its center hits another element', function()
    runtime(function(app, clicks)
      local link = element('AXLink', frame)
      local other = element('AXButton', frame)
      local probes = {}
      hs.axuielement.systemElementAtPosition = function(point)
        probes[#probes + 1] = point
        if point.x == 15 and point.y == 55 then return link end
        return other
      end
      assert_true(app:_clickTarget({ element = link, role = 'AXLink', frame = frame, kind = 'role' }))
      assert_deep_equals(clicks[1], { x = 15, y = 55 })
      assert_deep_equals(probes[1], { x = 60, y = 40 })
    end)
  end)
  it('does not click a covered or stale target', function()
    runtime(function(app, clicks)
      local button = element('AXButton', frame)
      local other = element('AXButton', frame)
      hs.axuielement.systemElementAtPosition = function() return other end
      assert_false(app:_clickTarget({ element = button, role = 'AXButton', frame = frame, kind = 'role' }))
      assert_equals(#clicks, 0)
    end)
  end)
  it('keeps a small link click inside its bounds', function()
    local geometry = require('core.geometry')
    local point = geometry.clickPoint({ role = 'AXLink', frame = { x = 10, y = 20, w = 4, h = 4 } },
      { linkClickInset = 5, genericClickXRatio = 0.5, genericClickYRatio = 0.5 })
    assert_true(point.x > 10 and point.x < 14 and point.y > 20 and point.y < 24)
  end)
  it('keeps selectable rows with an auxiliary child', function()
    runtime(function(app)
      local row = element('AXRow', frame, { element('AXButton', { x = 80, y = 20, w = 20, h = 20 }) })
      row.attributes.AXSelected = false
      assert_equals(#scan(app, row), 2)
    end)
  end)
  it('honors an empty visible-row collection instead of including hidden rows', function()
    runtime(function(app)
      local tableElement = element('AXTable', frame, { element('AXRow', frame) })
      tableElement.attributes.AXVisibleRows = {}
      assert_equals(#scan(app, tableElement), 0)
    end)
  end)
  it('falls back to ordinary children when browser search is unsupported', function()
    runtime(function(app)
      local root = element('AXWebArea', { x = 0, y = 0, w = 500, h = 400 }, { element('AXButton', frame) })
      function root:parameterizedAttributeValue() error('unsupported') end
      assert_equals(#scan(app, root), 1)
    end)
  end)
  it('does not lose an ancestor clip when a nested viewport is outside it', function()
    runtime(function(app)
      local button = element('AXButton', { x = 200, y = 20, w = 40, h = 20 })
      local inner = element('AXScrollArea', { x = 200, y = 0, w = 100, h = 100 }, { button })
      local outer = element('AXScrollArea', { x = 0, y = 0, w = 100, h = 100 }, { inner })
      assert_equals(#scan(app, outer), 0)
    end)
  end)
  it('clicks only the on-screen part of a partially visible element', function()
    runtime(function(app, clicks)
      local f = { x = -100, y = 10, w = 120, h = 20 }
      local button = element('AXButton', f)
      hs.axuielement.systemElementAtPosition = function(point)
        if point.x >= 0 then return button end
      end
      assert_true(app:_clickTarget({ element = button, role = 'AXButton', frame = f, kind = 'role' }))
      assert_deep_equals(clicks[1], { x = 10, y = 20 })
    end)
  end)
  it('accepts a target child hit but not a sibling', function()
    runtime(function(app, clicks)
      local child = element('AXStaticText', frame)
      local button = element('AXButton', frame, { child })
      hs.axuielement.systemElementAtPosition = function() return child end
      assert_true(app:_clickTarget({ element = button, role = 'AXButton', frame = frame, kind = 'role' }))
      assert_equals(#clicks, 1)
    end)
  end)
  it('rechecks a point after hover changes the hit element', function()
    runtime(function(app, clicks)
      local button = element('AXButton', frame)
      local other = element('AXButton', frame)
      local hovered = false
      hs.mouse.absolutePosition = function() hovered = true end
      hs.axuielement.systemElementAtPosition = function() return hovered and other or button end
      assert_false(app:_clickTarget({ element = button, role = 'AXButton', frame = frame, kind = 'role' }))
      assert_equals(#clicks, 0)
    end)
  end)
  it('ignores activation points outside the visible frame', function()
    runtime(function(app, clicks)
      local button = element('AXButton', frame)
      button.attributes.AXActivationPoint = { x = 900, y = 600 }
      hs.axuielement.systemElementAtPosition = function() return button end
      assert_true(app:_clickTarget({ element = button, role = 'AXButton', frame = frame, kind = 'role' }))
      assert_deep_equals(clicks[1], { x = 60, y = 40 })
    end)
  end)

  it('deduplicates different Lua wrappers for the same AX child', function()
    local child = element('AXButton', frame)
    local alias = element('AXButton', frame); alias.identity = child.identity
    local root = element('AXWindow', frame, { child })
    root.attributes.AXChildrenInNavigationOrder = { alias }
    assert_equals(#require('core.element_factory').rawChildren(root, { 'AXChildren' }), 1)
  end)
  it('does not let AX aliases consume the target limit before a distinct button', function()
    runtime(function(app)
      app.config.maxElements = 2
      local first = element('AXButton', frame)
      local alias = element('AXButton', frame); alias.identity = first.identity
      local second = element('AXButton', { x = 150, y = 20, w = 100, h = 40 })
      local root = element('AXWindow', { x = 0, y = 0, w = 500, h = 400 }, { first, alias, second })
      assert_equals(#scan(app, root), 2)
    end)
  end)

  it('finds controls exposing position and size but no AXFrame', function()
    runtime(function(app)
      local button = element('AXButton', nil)
      button.attributes.AXPosition = { x = 10, y = 20 }
      button.attributes.AXSize = { w = 100, h = 40 }
      assert_equals(#scan(app, button), 1)
    end)
  end)
  it('refreshes click geometry from position and size when AXFrame is absent', function()
    runtime(function(app, clicks)
      local button = element('AXButton', nil)
      button.attributes.AXPosition = { x = 200, y = 100 }
      button.attributes.AXSize = { w = 100, h = 40 }
      hs.axuielement.systemElementAtPosition = function() return button end
      assert_true(app:_clickTarget({ element = button, role = 'AXButton', frame = frame, kind = 'role' }))
      assert_deep_equals(clicks[1], { x = 250, y = 120 })
    end)
  end)

  it('removes a structural fallback inside an actionable control regardless of visit order', function()
    runtime(function(app)
      local inner = element('AXGroup', { x = 20, y = 25, w = 60, h = 15 })
      local input = element('AXTextField', frame, { inner })
      assert_equals(#scan(app, input), 1)
    end)
  end)

  it('does not label a whole window just because it can be raised', function()
    runtime(function(app)
      local root = element('AXWindow', { x = 0, y = 0, w = 500, h = 400 },
        { element('AXButton', frame) }, { 'AXRaise' })
      assert_equals(#scan(app, root), 1)
    end)
  end)
  it('clips to ancestors before choosing a screen for a spanning element', function()
    runtime(function(app, clicks)
      local button = element('AXButton', { x = 900, y = 10, w = 200, h = 20 })
      element('AXScrollArea', { x = 1000, y = 0, w = 200, h = 800 }, { button })
      hs.axuielement.systemElementAtPosition = function() return button end
      assert_true(app:_clickTarget({ element = button, role = 'AXButton', frame = frame, kind = 'role' }))
      assert_deep_equals(clicks[1], { x = 1050, y = 20 })
    end, { screens[1], { x = 1000, y = 0, w = 200, h = 800 } })
  end)

end)

-- Captured Codex hit: an empty full-window pointer-events-none AXGroup,
-- while the selected sidebar AXButton is at x=60,y=487,w=272,h=30.
describe('pointer-transparent AX hit regression', function()
  local function scene(overrides)
    local window = element('AXWindow', { x = 0, y = 33, w = 1000, h = 700 })
    local button = element('AXButton', { x = 60, y = 487, w = 272, h = 30 })
    button.attributes.AXWindow = window
    local layer = element('AXGroup', { x = 0, y = 33, w = 1000, h = 700 })
    layer.attributes.AXWindow = window
    layer.attributes.AXDOMClassList = { 'pointer-events-none', 'fixed', 'inset-0' }
    for k, v in pairs(overrides or {}) do layer.attributes[k] = v end
    return button, layer
  end
  it('clicks a button when AX hits an empty pointer-transparent layer in its window', function()
    runtime(function(app, clicks)
      local button, layer = scene()
      hs.axuielement.systemElementAtPosition = function() return layer end
      assert_true(app:_clickTarget({ element = button, role = 'AXButton', frame = button.attributes.AXFrame }))
      assert_deep_equals(clicks[1], { x = 196, y = 502 })
    end)
  end)
  for name, overrides in pairs({
    ['opaque container'] = { AXDOMClassList = { 'fixed', 'inset-0' } },
    ['different process'] = { pid = 2 },
    ['different window'] = { AXWindow = element('AXWindow', frame) },
    ['misplaced hit frame'] = { AXFrame = { x = 800, y = 600, w = 20, h = 20 } },
    ['populated overlay'] = { AXChildren = { element('AXButton', frame) } },
    ['missing child metadata'] = { AXChildren = false },
    ['modal container'] = { AXModal = true },
    ['navigation-only popup'] = { AXChildrenInNavigationOrder = { element('AXButton', frame) } },
  }) do
    it('rejects a ' .. name, function()
      runtime(function(app, clicks)
        local button, layer = scene(overrides)
        hs.axuielement.systemElementAtPosition = function() return layer end
        assert_false(app:_clickTarget({ element = button, role = 'AXButton', frame = button.attributes.AXFrame }))
        assert_equals(#clicks, 0)
      end)
    end)
  end
  it('rejects unverifiable process identities', function()
    runtime(function(app, clicks)
      local button, layer = scene()
      function button:pid() return nil end
      function layer:pid() return nil end
      hs.axuielement.systemElementAtPosition = function() return layer end
      assert_false(app:_clickTarget({ element = button, role = 'AXButton', frame = button.attributes.AXFrame }))
      assert_equals(#clicks, 0)
    end)
  end)
  it('rejects an out-of-bounds point even on an empty transparent layer', function()
    local button, layer = scene()
    assert_false(require('core.element_factory').matchesClickPoint(layer, button, { x = 40, y = 502 }))
  end)
  it('does not apply the button exception to a link bounding box', function()
    runtime(function(app, clicks)
      local button, layer = scene()
      button.attributes.AXRole = 'AXLink'
      hs.axuielement.systemElementAtPosition = function() return layer end
      assert_false(app:_clickTarget({ element = button, role = 'AXLink', frame = button.attributes.AXFrame }))
      assert_equals(#clicks, 0)
    end)
  end)
end)
