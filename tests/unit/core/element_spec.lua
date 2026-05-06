package.path = package.path .. ";./OpenRow.spoon/?.lua"
local Element = require("core.element")

local function sample()
  return Element.new({
    rawId = "0xabc",
    role = "AXButton",
    frame = { x = 10, y = 20, w = 30, h = 40 },
    actions = { "AXPress", "AXShowMenu" },
    title = "OK",
    description = "Confirm dialog",
    value = nil,
    help = nil,
    enabled = true,
  })
end

describe("Element.new", function()
  it("preserves all fields", function()
    local element = sample()
    assert_equals(Element.rawId(element), "0xabc")
    assert_equals(Element.role(element), "AXButton")
    assert_deep_equals(Element.frame(element), { x = 10, y = 20, w = 30, h = 40 })
    assert_deep_equals(Element.actions(element), { "AXPress", "AXShowMenu" })
    assert_equals(Element.title(element), "OK")
    assert_equals(Element.description(element), "Confirm dialog")
    assert_nil(Element.value(element))
    assert_nil(Element.help(element))
    assert_true(Element.enabled(element))
  end)
end)

describe("Element.searchText", function()
  it("joins searchable fields and lowercases them", function()
    assert_equals(Element.searchText(sample()), "axbutton ok confirm dialog  ")
  end)

  it("converts non-string values", function()
    local element = Element.new({ role = "AXSlider", value = 42 })
    assert_equals(Element.searchText(element), "axslider   42 ")
  end)
end)
