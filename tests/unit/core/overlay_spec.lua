local overlay = require('core.overlay')

describe('screen overlay geometry', function()
  it('draws labels in local screen coordinates and releases every shared canvas', function()
    local oldHS = hs
    local frames = { { x = -1000, y = -100, w = 1000, h = 800 }, { x = 0, y = 0, w = 1000, h = 800 } }
    local canvases = {}
    hs = {
      screen = { allScreens = function()
        local result = {}; for _, f in ipairs(frames) do local frame = f; result[#result + 1] = { fullFrame = function() return frame end } end
        return result
      end },
      canvas = { windowLevels = {}, windowBehaviors = {}, new = function(frame)
        local c = { frame = frame, elements = {}, deleted = false }
        function c:level() end; function c:behavior() end; function c:show() end
        function c:appendElements(values)
          if values.type then values = { values } end
          for _, value in ipairs(values) do self.elements[#self.elements + 1] = value end
        end
        function c:delete() self.deleted = true end
        canvases[#canvases + 1] = c; return c
      end },
    }
    local ok, err = pcall(function()
      local view = overlay.new()
      view:showDim(0.1)
      view:showLabels({
        { frame = { x = -900, y = -50, w = 40, h = 20 }, text = 'a' },
        { frame = { x = 100, y = 50, w = 40, h = 20 }, text = 'b' },
      })
      assert_equals(#canvases, 2)
      for i, c in ipairs(canvases) do
        assert_equals(#c.elements, 3)
        local label = c.elements[2].frame
        assert_equals(label.x + label.w / 2, 120)
        assert_equals(label.y + label.h / 2, 60)
        assert_equals(c.elements[3].text, i == 1 and 'a' or 'b')
      end
      view:clear(); for _, c in ipairs(canvases) do assert_true(c.deleted) end
      assert_equals(#view._canvases, 0)
    end)
    hs = oldHS
    if not ok then error(err, 0) end
  end)
end)
