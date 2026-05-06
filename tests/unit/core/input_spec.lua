package.path = package.path .. ";./OpenRow.spoon/?.lua"
local input = require("core.input")

describe("input.modifierAction", function()
  it("defaults to leftClick", function()
    assert_equals(input.modifierAction({}), "leftClick")
    assert_equals(input.modifierAction(nil), "leftClick")
  end)

  it("maps shift to rightClick", function()
    assert_equals(input.modifierAction({ shift = true }), "rightClick")
  end)

  it("maps cmd to doubleClick", function()
    assert_equals(input.modifierAction({ cmd = true }), "doubleClick")
  end)

  it("maps alt to move", function()
    assert_equals(input.modifierAction({ alt = true }), "move")
  end)

  it("uses shift precedence before cmd and alt", function()
    assert_equals(input.modifierAction({ shift = true, cmd = true, alt = true }), "rightClick")
  end)
end)
