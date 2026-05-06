package.path = package.path .. ";./OpenRow.spoon/?.lua"
local geometry = require("core.geometry")

describe("geometry.center", function()
  it("returns the frame center", function()
    assert_deep_equals(geometry.center({ x = 10, y = 20, w = 30, h = 40 }), { x = 25, y = 40 })
  end)
end)

describe("geometry.contains", function()
  it("returns true when inner is fully inside outer", function()
    assert_true(geometry.contains({ x = 0, y = 0, w = 100, h = 100 }, { x = 10, y = 10, w = 20, h = 20 }))
  end)

  it("returns false when inner extends outside outer", function()
    assert_false(geometry.contains({ x = 0, y = 0, w = 100, h = 100 }, { x = 90, y = 90, w = 20, h = 20 }))
  end)
end)

describe("geometry.intersects", function()
  it("returns true for overlapping frames", function()
    assert_true(geometry.intersects({ x = 0, y = 0, w = 10, h = 10 }, { x = 9, y = 9, w = 10, h = 10 }))
  end)

  it("returns false for touching but not overlapping frames", function()
    assert_false(geometry.intersects({ x = 0, y = 0, w = 10, h = 10 }, { x = 10, y = 0, w = 10, h = 10 }))
  end)
end)

describe("geometry.framesAlmostEqual", function()
  it("returns true when center and size are within tolerance", function()
    assert_true(geometry.framesAlmostEqual({ x = 0, y = 0, w = 10, h = 10 }, { x = 1, y = 1, w = 11, h = 11 }))
  end)

  it("returns false when center differs beyond tolerance", function()
    assert_false(geometry.framesAlmostEqual({ x = 0, y = 0, w = 10, h = 10 }, { x = 10, y = 10, w = 10, h = 10 }))
  end)
end)

describe("geometry.visibleOnScreens", function()
  it("returns false for malformed or empty frames", function()
    assert_false(geometry.visibleOnScreens(nil, { { x = 0, y = 0, w = 100, h = 100 } }))
    assert_false(geometry.visibleOnScreens({ x = 0, y = 0, w = 0, h = 10 }, { { x = 0, y = 0, w = 100, h = 100 } }))
  end)

  it("returns true when frame intersects a screen", function()
    assert_true(geometry.visibleOnScreens({ x = 90, y = 90, w = 20, h = 20 }, { { x = 0, y = 0, w = 100, h = 100 } }))
  end)

  it("returns false when frame is outside all screens", function()
    assert_false(geometry.visibleOnScreens({ x = 120, y = 120, w = 20, h = 20 }, { { x = 0, y = 0, w = 100, h = 100 } }))
  end)
end)

describe("geometry.clickPoint", function()
  local config = { linkClickInset = 5, genericClickXRatio = 0.5, genericClickYRatio = 0.5 }

  it("uses the lower-left inset for links", function()
    assert_deep_equals(geometry.clickPoint({ role = "AXLink", frame = { x = 10, y = 20, w = 30, h = 40 } }, config), { x = 15, y = 55 })
  end)

  it("uses configured ratios for generic targets", function()
    assert_deep_equals(geometry.clickPoint({ role = "AXButton", frame = { x = 10, y = 20, w = 30, h = 40 } }, config), { x = 25, y = 40 })
  end)
end)
