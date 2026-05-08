package.path = package.path .. ";./OpenRow.spoon/?.lua"
local scanner = require("core.scanner")

local function defaultConfig()
  return {
    minSize = 4,
    minListItemWidth = 24,
    minListItemHeight = 12,
    maxTargetAreaRatio = 0.85,
    controlRoles = { AXButton = true, AXLink = true },
    roleFallbacks = { AXCell = true, AXStaticText = true, AXRow = true },
    ignoredActions = { AXShowMenu = true, AXScrollToVisible = true },
  }
end

local function defaultScreens()
  return { { x = 0, y = 0, w = 1000, h = 1000 } }
end

describe("scanner.maxScreenArea", function()
  it("returns at least 1 for empty input", function()
    assert_equals(scanner.maxScreenArea({}), 1)
    assert_equals(scanner.maxScreenArea(nil), 1)
  end)

  it("returns the largest screen area", function()
    assert_equals(scanner.maxScreenArea({ { w = 100, h = 50 }, { w = 200, h = 100 } }), 20000)
  end)
end)

describe("scanner.isChromiumApp", function()
  local patterns = { "^com%.google%.Chrome", "^com%.brave%." }

  it("returns true for matching bundle id", function()
    assert_true(scanner.isChromiumApp("com.google.Chrome", patterns))
    assert_true(scanner.isChromiumApp("com.brave.Browser", patterns))
  end)

  it("returns false for non-matching bundle id", function()
    assert_false(scanner.isChromiumApp("com.apple.finder", patterns))
  end)

  it("returns false on missing input", function()
    assert_false(scanner.isChromiumApp(nil, patterns))
    assert_false(scanner.isChromiumApp("com.google.Chrome", nil))
  end)
end)

describe("scanner.hasActionableAction", function()
  local ignored = { AXShowMenu = true, AXScrollToVisible = true }

  it("returns true when at least one action is not ignored", function()
    assert_true(scanner.hasActionableAction({ "AXShowMenu", "AXPress" }, ignored))
  end)

  it("returns false when only decorative actions are present", function()
    assert_false(scanner.hasActionableAction({ "AXShowMenu", "AXScrollToVisible" }, ignored))
  end)

  it("returns false on empty / nil input", function()
    assert_false(scanner.hasActionableAction({}, ignored))
    assert_false(scanner.hasActionableAction(nil, ignored))
  end)
end)

describe("scanner.hasMeaningfulText", function()
  it("returns true when any part has non-whitespace content", function()
    assert_true(scanner.hasMeaningfulText({ title = "OK" }))
    assert_true(scanner.hasMeaningfulText({ value = "x", title = "" }))
  end)

  it("returns false for whitespace-only parts", function()
    assert_false(scanner.hasMeaningfulText({ title = "   ", value = "\t" }))
    assert_false(scanner.hasMeaningfulText({}))
  end)
end)

describe("scanner.computeSearchText", function()
  it("joins fields with a space and lowercases", function()
    local text = scanner.computeSearchText({
      role = "AXButton", title = "Submit", description = "Send form",
      value = "", help = "ENTER",
    })
    assert_equals(text, "axbutton submit send form  enter")
  end)

  it("handles missing fields", function()
    assert_equals(scanner.computeSearchText({ role = "AXLink" }), "axlink    ")
  end)
end)

describe("scanner.targetKind", function()
  local config = defaultConfig()
  local screens = defaultScreens()
  local screenArea = scanner.maxScreenArea(screens)

  local NIL = {} -- sentinel to allow overriding a field back to nil

  local function classify(overrides)
    local opts = {
      role = "AXButton",
      frame = { x = 10, y = 10, w = 50, h = 30 },
      enabled = true,
      actionNames = {},
      hasMeaningfulText = true,
      hasHintableChildren = false,
      config = config,
      screenFrames = screens,
      screenArea = screenArea,
    }
    for k, v in pairs(overrides or {}) do
      if v == NIL then opts[k] = nil else opts[k] = v end
    end
    return scanner.targetKind(opts)
  end

  it("returns role for known control roles", function()
    assert_equals(classify({}), "role")
  end)

  it("returns nil when role is missing", function()
    assert_nil(classify({ role = NIL }))
  end)

  it("returns nil when disabled", function()
    assert_nil(classify({ enabled = false }))
  end)

  it("returns nil when below minSize", function()
    assert_nil(classify({ frame = { x = 0, y = 0, w = 2, h = 2 } }))
  end)

  it("returns nil when frame is off-screen", function()
    assert_nil(classify({ frame = { x = 2000, y = 2000, w = 50, h = 30 } }))
  end)

  it("returns nil when area exceeds max ratio", function()
    assert_nil(classify({ frame = { x = 0, y = 0, w = 950, h = 950 } }))
  end)

  it("returns nil for fallback role with hintable children", function()
    assert_nil(classify({ role = "AXCell", hasHintableChildren = true }))
  end)

  it("returns action when an actionable action exists", function()
    assert_equals(classify({ role = "AXUnknown", actionNames = { "AXPress" } }), "action")
  end)

  it("ignores decorative actions only", function()
    assert_nil(classify({ role = "AXUnknown", actionNames = { "AXShowMenu" } }))
  end)

  it("returns fallback for large fallback role", function()
    assert_equals(classify({
      role = "AXCell", actionNames = {}, frame = { x = 0, y = 0, w = 100, h = 50 },
    }), "fallback")
  end)

  it("returns nil for fallback role too small for list-item heuristic", function()
    assert_nil(classify({
      role = "AXCell", actionNames = {}, frame = { x = 0, y = 0, w = 20, h = 8 },
    }))
  end)

  it("returns nil for AXStaticText without meaningful text", function()
    assert_nil(classify({
      role = "AXStaticText", actionNames = {}, hasMeaningfulText = false,
      frame = { x = 0, y = 0, w = 100, h = 50 },
    }))
  end)
end)

describe("scanner.dedupeTargets", function()
  it("drops a fallback when a non-fallback occupies the same frame", function()
    local result = scanner.dedupeTargets({
      { kind = "fallback", frame = { x = 0, y = 0, w = 50, h = 30 } },
      { kind = "role",     frame = { x = 0, y = 0, w = 50, h = 30 } },
    })
    assert_equals(#result, 1)
    assert_equals(result[1].kind, "role")
  end)

  it("drops a fallback contained inside an existing non-fallback", function()
    local result = scanner.dedupeTargets({
      { kind = "role",     frame = { x = 0, y = 0, w = 100, h = 100 } },
      { kind = "fallback", frame = { x = 10, y = 10, w = 20, h = 20 } },
    })
    assert_equals(#result, 1)
    assert_equals(result[1].kind, "role")
  end)

  it("keeps two distinct non-fallback targets", function()
    local result = scanner.dedupeTargets({
      { kind = "role",   frame = { x = 0,   y = 0, w = 50, h = 30 } },
      { kind = "action", frame = { x = 100, y = 0, w = 50, h = 30 } },
    })
    assert_equals(#result, 2)
  end)

  it("keeps the first of two near-duplicate non-fallback targets", function()
    local result = scanner.dedupeTargets({
      { kind = "role",   frame = { x = 0, y = 0, w = 50, h = 30 } },
      { kind = "action", frame = { x = 1, y = 1, w = 50, h = 30 } },
    })
    assert_equals(#result, 1)
    assert_equals(result[1].kind, "role")
  end)
end)

describe("scanner.rankTargets", function()
  it("sorts by y then x in reading order", function()
    local targets = {
      { id = "br", frame = { x = 200, y = 200, w = 10, h = 10 } },
      { id = "tl", frame = { x = 0,   y = 0,   w = 10, h = 10 } },
      { id = "tr", frame = { x = 200, y = 0,   w = 10, h = 10 } },
      { id = "bl", frame = { x = 0,   y = 200, w = 10, h = 10 } },
    }
    scanner.rankTargets(targets)
    assert_equals(targets[1].id, "tl")
    assert_equals(targets[2].id, "tr")
    assert_equals(targets[3].id, "bl")
    assert_equals(targets[4].id, "br")
  end)

  it("treats rows within 8px tolerance as the same row", function()
    local targets = {
      { id = "right", frame = { x = 100, y = 0, w = 10, h = 10 } },
      { id = "left",  frame = { x = 0,   y = 5, w = 10, h = 10 } },
    }
    scanner.rankTargets(targets)
    assert_equals(targets[1].id, "left")
    assert_equals(targets[2].id, "right")
  end)
end)
