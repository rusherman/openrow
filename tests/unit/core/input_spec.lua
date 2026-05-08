package.path = package.path .. ";./OpenRow.spoon/?.lua"
local input = require("core.input")

describe("input.character", function()
  it("returns nil for nil or non-character keys", function()
    assert_nil(input.character(nil, false))
    assert_nil(input.character("escape", false))
    assert_nil(input.character("return", false))
    assert_nil(input.character("delete", false))
  end)

  it("returns the raw key for a single character without shift", function()
    assert_equals(input.character("a", false), "a")
    assert_equals(input.character("/", false), "/")
    assert_equals(input.character(";", false), ";")
  end)

  it("maps the named space key to a space", function()
    assert_equals(input.character("space", false), " ")
    assert_equals(input.character("space", true), " ")
  end)

  it("uppercases letters when shift is held", function()
    assert_equals(input.character("a", true), "A")
    assert_equals(input.character("z", true), "Z")
  end)

  it("maps shifted symbols to their typed character", function()
    assert_equals(input.character("1", true), "!")
    assert_equals(input.character("/", true), "?")
    assert_equals(input.character(";", true), ":")
    assert_equals(input.character("-", true), "_")
  end)
end)
