-- Simulate AX IPC latency on the real activate/render paths without wall-clock sleeps.
local function withRuntime(fn)
  local oldHS = hs
  local now, queue, canvases, reads = 0, {}, 0, 0
  local frame = { x = 0, y = 0, w = 1000, h = 800 }
  local function element(role, children, index)
    local attrs = { AXRole = role, AXFrame = index and { x = index % 20 * 45, y = math.floor(index / 20) * 30, w = 40, h = 25 } or frame,
      AXChildren = children or {} }
    return {
      attributeValue = function(_, key) now = now + 0.001; reads = reads + 1; return attrs[key] end,
      actionNames = function() now = now + 0.001; return {} end,
      setAttributeValue = function(self) return self end,
    }
  end
  local buttons = {}; for i = 1, 300 do buttons[i] = element('AXButton', nil, i) end
  local window = element('AXWindow', buttons)
  local application = element('AXApplication'); function application:attributeValue(key) return key == 'AXFocusedWindow' and window end
  local app = { pid = function() return 1 end, bundleID = function() return 'test.app' end }
  hs = {
    accessibilityState = function() return true end,
    spoons = { scriptPath = function() return './OpenRow.spoon/' end },
    timer = {
      absoluteTime = function() return now * 1e9 end,
      secondsSinceEpoch = function() return now end,
      usleep = function(us) now = now + us / 1e6 end,
      doAfter = function(delay, callback)
        local t = { callback = callback, delay = delay, stopped = false, stop = function(self) self.stopped = true end }
        queue[#queue + 1] = t; return t
      end,
    },
    application = { frontmostApplication = function() return app end },
    axuielement = { applicationElement = function() return application end },
    screen = { allScreens = function() return {{ fullFrame = function() return frame end }} end },
    fnutils = { imap = function(items, f) local out = {}; for _, v in ipairs(items) do out[#out + 1] = f(v) end; return out end },
    alert = { show = function() end },
    eventtap = { event = { types = { keyDown = 1 } }, new = function(_, callback)
      return { callback = callback, start = function() end, stop = function() end }
    end },
    canvas = { windowLevels = { overlay = 1 }, windowBehaviors = {}, new = function()
      canvases = canvases + 1
      return { level = function() end, behavior = function() end, appendElements = function() end,
        show = function() end, delete = function() end }
    end },
  }
  local product = dofile('OpenRow.spoon/init.lua')
  product.config.scanTimeout = 10
  local function drain()
    local count, maxBlock = 0, 0
    while #queue > 0 do
      count = count + 1; assert(count < 10000, 'scan did not terminate')
      local t = table.remove(queue, 1)
      if not t.stopped then
        now = now + t.delay
        local start = now; t.callback(); maxBlock = math.max(maxBlock, now - start)
      end
    end
    return maxBlock
  end
  local ok, err = pcall(fn, product, function() return now, canvases, reads end, drain)
  product:deactivate()
  hs = oldHS
  if not ok then error(err, 0) end
end

describe('responsive activation', function()
  it('returns control promptly before a large AX scan completes', function()
    withRuntime(function(app, metrics, drain)
      app:activate()
      local elapsed = metrics()
      assert_true(elapsed < 0.05, 'hotkey blocked for ' .. elapsed .. ' simulated seconds')
      assert_true(app._scanning)
      assert_not_nil(app._eventtap)
      local maxBlock = drain()
      assert_true(maxBlock < 0.05, 'a timer callback monopolized the event loop')
      assert_equals(#app._targets, 300)
    end)
  end)
  it('cancels a pending scan without drawing stale labels', function()
    withRuntime(function(app, metrics, drain)
      app:activate(); app:deactivate(); drain()
      local _, canvases = metrics()
      assert_equals(canvases, 0)
      assert_false(app._active)
    end)
  end)
  it('renders hundreds of labels using a bounded number of native windows', function()
    withRuntime(function(app, metrics, drain)
      app:activate(); drain()
      local _, canvases = metrics()
      assert_equals(canvases, 1, 'native windows for one screen')
    end)
  end)
  it('can reactivate after cancelling without finishing the old job', function()
    withRuntime(function(app, metrics, drain)
      app:activate(); app:deactivate(); app:activate(); drain()
      local _, canvases = metrics()
      assert_equals(canvases, 1)
      assert_equals(#app._targets, 300)
    end)
  end)
  it('filters search text without additional AX calls during typing', function()
    withRuntime(function(app, metrics, drain)
      app:activate(); drain()
      local _, _, before = metrics()
      app:_filterTargets('button')
      local _, _, after = metrics()
      assert_equals(after, before)
      assert_equals(#app._targets, 300)
    end)
  end)
  it('stops a slow scan and releases the keyboard hook', function()
    withRuntime(function(app, metrics, drain)
      app.config.scanTimeout = 0.01
      app:activate(); drain()
      assert_false(app._active)
      assert_nil(app._eventtap)
      local _, canvases = metrics()
      assert_equals(canvases, 0)
    end)
  end)
  it('bounds visits even when targets do not reach their separate limit', function()
    withRuntime(function(app, metrics, drain)
      app.config.maxScanNodes = 20
      app:activate(); drain()
      assert_equals(app._scanStats.nodes, 20)
      assert_true(app._scanTruncated)
      assert_equals(#app._targets, 19)
    end)
  end)
  it('releases the keyboard hook if rendering fails', function()
    withRuntime(function(app, metrics, drain)
      hs.canvas.new = function() error('display unavailable') end
      app:activate(); drain()
      assert_false(app._active)
      assert_nil(app._eventtap)
    end)
  end)
end)
