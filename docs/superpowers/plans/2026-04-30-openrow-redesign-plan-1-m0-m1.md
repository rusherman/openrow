# OpenRow Redesign — Plan 1 (M0 + M1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a test runner, then extract atomic helpers from the single-file `OpenRow.spoon/init.lua` into bounded modules under `lib/` and `core/`, without changing user-visible behavior.

**Architecture:** Bottom-up extraction. Pure utilities first (log, alphabet, geometry), then data model (element snapshot), then `hs.*` wrappers (element factory, overlay, input). Each commit keeps the spoon working; `init.lua` shrinks one helper at a time.

**Tech Stack:** Hammerspoon Lua 5.4, hand-written `tests/run.lua` assert runner (no external deps), pure-Lua modules, integration via `dofile(hs.spoons.scriptPath() .. ...)` inside the spoon.

---

## Spec Alignment

This plan implements milestones **M0 + M1** from `docs/superpowers/specs/2026-04-30-openrow-redesign-design.md` §7.1. Out of scope for this plan: scan rewrite (M2), mode refactor (M3), polish (M4). Those will be separate plans authored after M0+M1 stabilizes.

---

## File Structure

### Created files

| Path | Purpose | Owner of |
|---|---|---|
| `tests/run.lua` | Minimal assert runner; discovers `tests/unit/**/*_spec.lua`, runs them, reports counts | Test infra |
| `tests/unit/.gitkeep` | Keep dir tracked | — |
| `tests/fixtures/.gitkeep` | Reserved for M2 AX-tree fixtures | — |
| `tests/manual/smoke-checklist.md` | 8-row release-gate manual test list | Human verification |
| `scripts/install.sh` | One-command spoon copy + `hs.reload()` | Dev workflow |
| `OpenRow.spoon/lib/log.lua` | Channelled logger (scan/input/action/error) | Logging |
| `OpenRow.spoon/lib/alphabet.lua` | Equal-length conflict-free hint string generation | Hint label math |
| `OpenRow.spoon/core/geometry.lua` | Frame center / contains / intersect / framesAlmostEqual / visibility | Frame math |
| `OpenRow.spoon/core/element.lua` | Pure data model for an AX element snapshot | Data structure |
| `OpenRow.spoon/core/element_factory.lua` | `hs.axuielement` wrapper: `from`, `rawChildren`, `safeAttribute`, `safeSetAttribute`, `safeActionNames` | Impure AX adapter |
| `OpenRow.spoon/core/overlay.lua` | `hs.canvas` wrapper for dim + label rendering | Drawing |
| `OpenRow.spoon/core/input.lua` | `hs.eventtap` event parsing + modifier-to-action mapping | Input |
| `tests/unit/lib/alphabet_spec.lua` | Pure unit tests for alphabet | — |
| `tests/unit/core/geometry_spec.lua` | Pure unit tests for geometry | — |
| `tests/unit/core/element_spec.lua` | Pure unit tests for element data model | — |
| `tests/unit/core/input_spec.lua` | Pure unit tests for `modifierAction` | — |

### Modified files

| Path | Change |
|---|---|
| `OpenRow.spoon/init.lua` | Progressively shrinks: each module integration replaces inline helpers with `dofile(...)` calls |
| `README.md` | Add a "Development" section pointing at `scripts/install.sh` and `lua tests/run.lua` |

---

## Task 1: Test runner + tests/ scaffolding (M0.1)

**Files:**
- Create: `tests/run.lua`
- Create: `tests/unit/.gitkeep`
- Create: `tests/fixtures/.gitkeep`

- [ ] **Step 1: Write `tests/run.lua`**

```lua
-- tests/run.lua — minimal assert-based test runner for OpenRow.
-- Discovers tests/unit/**/*_spec.lua, runs them, reports counts. No external deps.

package.path = package.path .. ";./?.lua;./tests/?.lua;./OpenRow.spoon/?.lua;./OpenRow.spoon/?/init.lua"

local total, failed, current = 0, 0, ""

function describe(name, fn) current = name; fn() end

function it(name, fn)
  total = total + 1
  local ok, err = pcall(fn)
  if ok then
    print(("  ok   %s > %s"):format(current, name))
  else
    failed = failed + 1
    print(("  FAIL %s > %s\n       %s"):format(current, name, tostring(err)))
  end
end

function assert_equals(actual, expected, msg)
  if actual ~= expected then
    error((msg or "") .. " expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

function assert_true(v, msg)     assert_equals(v, true, msg)  end
function assert_false(v, msg)    assert_equals(v, false, msg) end
function assert_nil(v, msg)
  if v ~= nil then error((msg or "") .. " expected nil, got " .. tostring(v), 2) end
end
function assert_not_nil(v, msg)
  if v == nil then error((msg or "") .. " expected non-nil", 2) end
end

local function deep_equal(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deep_equal(v, b[k]) then return false end end
  for k, v in pairs(b) do if not deep_equal(v, a[k]) then return false end end
  return true
end

function assert_deep_equals(actual, expected, msg)
  if not deep_equal(actual, expected) then
    error((msg or "") .. " tables not equal", 2)
  end
end

local p = io.popen("find tests/unit -name '*_spec.lua' 2>/dev/null | sort")
for file in p:lines() do
  print("\n[" .. file .. "]")
  dofile(file)
end
p:close()

print(("\n%d tests, %d failed"):format(total, failed))
os.exit(failed == 0 and 0 or 1)
```

- [ ] **Step 2: Create `.gitkeep` placeholders so empty dirs are tracked**

```bash
mkdir -p tests/unit tests/fixtures
touch tests/unit/.gitkeep tests/fixtures/.gitkeep
```

- [ ] **Step 3: Run the empty suite to verify it works**

Run: `lua tests/run.lua`
Expected output: `0 tests, 0 failed` and exit code 0.

- [ ] **Step 4: Commit**

```bash
git add tests/run.lua tests/unit/.gitkeep tests/fixtures/.gitkeep
git commit -m "chore: add minimal assert-based test runner

tests/run.lua discovers tests/unit/**/*_spec.lua, runs them with
describe/it globals and assert_equals / assert_true / assert_false /
assert_nil / assert_not_nil / assert_deep_equals helpers. No external
dependencies; runs under /usr/bin/lua."
```

---

## Task 2: Smoke checklist (M0.2)

**Files:**
- Create: `tests/manual/smoke-checklist.md`

- [ ] **Step 1: Create the checklist file**

```bash
mkdir -p tests/manual
```

Write `tests/manual/smoke-checklist.md`:

```markdown
# OpenRow Manual Smoke Checklist

Run before tagging a release. Each row: PASS / FAIL / N/A + one-line note.

| App | Verify | Result |
|---|---|---|
| Finder list view | each row has 1 label; click opens folder | |
| Safari arbitrary page | links / inputs / buttons all labelled; no missed dropdown | |
| Claude Code chat list | each conversation row has exactly 1 label; no AXStaticText label on section headers | |
| VS Code | file tree, tabs, status bar, activity bar all clickable | |
| System Settings | left categories + right toggles labelled and clickable | |
| Top menu bar | File / Edit / etc. each labelled | |
| Status icons (Wi-Fi, battery, IME) | each icon clickable to open its menu | |
| Notification center | dismiss-able items labelled | |

## Steps to run

1. `bash scripts/install.sh` (copies spoon to ~/.hammerspoon and reloads)
2. For each app in the table: open it, focus its main window, press Cmd+Shift+Space, verify the row.
3. Enter findings in the Result column.
```

- [ ] **Step 2: Commit**

```bash
git add tests/manual/smoke-checklist.md
git commit -m "chore: add manual smoke checklist for release gate"
```

---

## Task 3: Install script (M0.3)

**Files:**
- Create: `scripts/install.sh`

- [ ] **Step 1: Write `scripts/install.sh`**

```bash
mkdir -p scripts
```

Write `scripts/install.sh`:

```bash
#!/usr/bin/env bash
# Sync OpenRow.spoon into Hammerspoon's spoons dir and reload Hammerspoon config.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPOON_SRC="$REPO_ROOT/OpenRow.spoon"
SPOON_DST="$HOME/.hammerspoon/Spoons/OpenRow.spoon"

if [[ ! -d "$SPOON_SRC" ]]; then
  echo "error: $SPOON_SRC not found" >&2
  exit 1
fi

mkdir -p "$HOME/.hammerspoon/Spoons"
rm -rf "$SPOON_DST"
cp -R "$SPOON_SRC" "$SPOON_DST"
echo "Installed OpenRow.spoon to $SPOON_DST"

# Reload Hammerspoon config if Hammerspoon is running.
if pgrep -x "Hammerspoon" >/dev/null 2>&1; then
  /usr/bin/osascript -e 'tell application "Hammerspoon" to reload config' >/dev/null
  echo "Reloaded Hammerspoon config"
else
  echo "Hammerspoon not running; skipping reload"
fi
```

- [ ] **Step 2: Make it executable and test it**

```bash
chmod +x scripts/install.sh
bash scripts/install.sh
```

Expected: prints "Installed OpenRow.spoon to ..." and either "Reloaded Hammerspoon config" or "Hammerspoon not running; skipping reload". Exit code 0.

- [ ] **Step 3: Commit**

```bash
git add scripts/install.sh
git commit -m "chore: add install script that syncs spoon and reloads Hammerspoon"
```

---

## Task 4: lib/log.lua (M1.1)

**Files:**
- Create: `OpenRow.spoon/lib/log.lua`
- Modify: `OpenRow.spoon/init.lua` (replace inline `self.logger.i(...)` calls)

- [ ] **Step 1: Write `OpenRow.spoon/lib/log.lua`**

```bash
mkdir -p OpenRow.spoon/lib
```

```lua
-- OpenRow.spoon/lib/log.lua — channelled logger for OpenRow.
-- Channels are off by default; toggle via OpenRow.config.debug.{scan,input,action}.
-- The error channel is always on.

local M = {}

M.config = { scan = false, input = false, action = false }

local _logger = nil
local function logger()
  if _logger == nil then
    if hs and hs.logger then
      _logger = hs.logger.new("OpenRow", "info")
    else
      _logger = { i = function(_, msg) print(msg) end }
    end
  end
  return _logger
end

local function emit(prefix, enabled, fmt, ...)
  if enabled then logger():i(prefix .. ": " .. string.format(fmt, ...)) end
end

function M.scan(fmt, ...)   emit("scan",   M.config.scan,   fmt, ...) end
function M.input(fmt, ...)  emit("input",  M.config.input,  fmt, ...) end
function M.action(fmt, ...) emit("action", M.config.action, fmt, ...) end
function M.error(fmt, ...)  emit("error",  true,            fmt, ...) end

return M
```

- [ ] **Step 2: Replace inline log calls in `OpenRow.spoon/init.lua`**

Add near the top (after the `obj.license = "MIT"` line, before the `obj.logger` line):

```lua
local log = dofile(hs.spoons.scriptPath() .. "lib/log.lua")
```

Remove the `obj.logger = hs.logger.new("OpenRow", "info")` line.

In `obj.config`, replace `debug = false,` with:

```lua
  debug = { scan = false, input = false, action = false },
```

In `obj:_clickTarget(target)`, replace the three `if self.config.debug then self.logger.i(...) end` blocks with direct `log.action(...)` calls (no `if` gate; the log module gates on `log.config.action`). The new body:

```lua
function obj:_clickTarget(target)
  log.action(
    "click label=%s role=%s kind=%s frame={x=%.1f,y=%.1f,w=%.1f,h=%.1f}",
    target.label or "?", target.role or "?", target.kind or "?",
    target.frame.x, target.frame.y, target.frame.w, target.frame.h
  )

  self:_clearOverlay()

  safeSetAttribute(target.element, "AXFocused", true)
  safeSetAttribute(target.element, "AXSelected", true)

  local clickPoint = targetClickPoint(target, self.config)
  log.action("mouse click point={x=%.1f,y=%.1f}", clickPoint.x, clickPoint.y)
  hs.mouse.absolutePosition(clickPoint)
  hs.timer.usleep(math.floor(self.config.clickDelay * 1000000))
  hs.eventtap.leftClick(clickPoint)
  log.action("click via mouse")
  return true
end
```

In `obj:init()`, sync the debug config to the log module:

```lua
function obj:init()
  log.config = self.config.debug
  return self
end
```

- [ ] **Step 3: Install and verify spoon still works**

Run: `bash scripts/install.sh`

In Hammerspoon Console: trigger Cmd+Shift+Space; verify labels appear and a click activates the target. No log output expected (channels default off).

To verify the debug switch: in `~/.hammerspoon/init.lua`, after `local openrow = hs.loadSpoon("OpenRow")`, set `openrow.config.debug.action = true; openrow:init()`. Reload, click a target, verify "click label=... mouse click point=... click via mouse" lines appear in Console. Then set it back to false.

- [ ] **Step 4: Commit**

```bash
git add OpenRow.spoon/lib/log.lua OpenRow.spoon/init.lua
git commit -m "refactor: extract channelled logger into lib/log.lua

Replaces inline self.logger.i / self.config.debug branches with
log.action / log.input / log.scan / log.error. Channels default off;
toggle via OpenRow.config.debug.{scan,input,action}."
```

---

## Task 5: lib/alphabet.lua + tests (M1.2)

**Files:**
- Create: `OpenRow.spoon/lib/alphabet.lua`
- Create: `tests/unit/lib/alphabet_spec.lua`
- Modify: `OpenRow.spoon/init.lua`

- [ ] **Step 1: Write `tests/unit/lib/alphabet_spec.lua`**

```bash
mkdir -p tests/unit/lib
```

```lua
package.path = package.path .. ";./OpenRow.spoon/?.lua"
local alphabet = require("lib.alphabet")

describe("alphabet.lengthFor", function()
  it("returns 1 when count fits in single char", function()
    assert_equals(alphabet.lengthFor(4, "asdf"), 1)
    assert_equals(alphabet.lengthFor(1, "asdf"), 1)
  end)

  it("returns 2 when count exceeds base", function()
    assert_equals(alphabet.lengthFor(5, "abcd"), 2)
    assert_equals(alphabet.lengthFor(5, "abc"), 2)
  end)

  it("scales length to fit count", function()
    -- "ab" base 2: length 1 -> 2, length 2 -> 4, length 3 -> 8, length 4 -> 16
    assert_equals(alphabet.lengthFor(8, "ab"), 3)
    assert_equals(alphabet.lengthFor(9, "ab"), 4)
  end)
end)

describe("alphabet.labelAt", function()
  it("returns single char for index <= base at length 1", function()
    assert_equals(alphabet.labelAt(1, 1, "abc"), "a")
    assert_equals(alphabet.labelAt(2, 1, "abc"), "b")
    assert_equals(alphabet.labelAt(3, 1, "abc"), "c")
  end)

  it("pads with leading first char when length > minimum needed", function()
    assert_equals(alphabet.labelAt(1, 2, "ab"), "aa")
    assert_equals(alphabet.labelAt(2, 2, "ab"), "ab")
    assert_equals(alphabet.labelAt(3, 2, "ab"), "ba")
    assert_equals(alphabet.labelAt(4, 2, "ab"), "bb")
  end)
end)

describe("alphabet.generate", function()
  it("produces exactly count labels", function()
    local labels = alphabet.generate(5, "abc")
    assert_equals(#labels, 5)
  end)

  it("uses equal length so no label is a prefix of another", function()
    local labels = alphabet.generate(5, "abc")
    for _, label in ipairs(labels) do
      assert_equals(#label, 2)
    end
  end)

  it("returns an empty list for count = 0", function()
    local labels = alphabet.generate(0, "abc")
    assert_equals(#labels, 0)
  end)
end)
```

- [ ] **Step 2: Run the tests, verify they fail (module not yet created)**

Run: `lua tests/run.lua`
Expected: failure with "module 'lib.alphabet' not found".

- [ ] **Step 3: Write `OpenRow.spoon/lib/alphabet.lua`**

```lua
-- OpenRow.spoon/lib/alphabet.lua — equal-length conflict-free hint string generation.

local M = {}

function M.lengthFor(count, charset)
  local base = #charset
  if base == 0 then return 0 end
  local length = 1
  local capacity = base
  while count > capacity do
    length = length + 1
    capacity = capacity * base
  end
  return length
end

function M.labelAt(index, length, charset)
  local base = #charset
  local label = ""
  local number = index - 1
  for _ = 1, length do
    local remainder = (number % base) + 1
    label = charset:sub(remainder, remainder) .. label
    number = math.floor(number / base)
  end
  return label
end

function M.generate(count, charset)
  local labels = {}
  if count <= 0 then return labels end
  local length = M.lengthFor(count, charset)
  for i = 1, count do
    labels[i] = M.labelAt(i, length, charset)
  end
  return labels
end

return M
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `lua tests/run.lua`
Expected: all alphabet tests pass; `N tests, 0 failed`.

- [ ] **Step 5: Integrate into `OpenRow.spoon/init.lua`**

Add near the top (next to the `local log = ...` line):

```lua
local alphabet = dofile(hs.spoons.scriptPath() .. "lib/alphabet.lua")
```

Replace the body of `obj:_assignLabels`:

```lua
function obj:_assignLabels(targets)
  self._labelLength = alphabet.lengthFor(#targets, self.config.keys)
  for index, target in ipairs(targets) do
    target.label = alphabet.labelAt(index, self._labelLength, self.config.keys)
  end
  return targets
end
```

Delete the methods `obj:_labelSequence` and `obj:_labelLengthForCount` entirely (no remaining callers). Verify with `grep -n '_labelSequence\|_labelLengthForCount' OpenRow.spoon/init.lua` showing zero matches.

- [ ] **Step 6: Verify spoon still works**

Run: `bash scripts/install.sh`
In Hammerspoon: trigger Cmd+Shift+Space; verify labels are still equal length (e.g. all "aa", "ab" rather than mix of "a", "aa") when there are many targets.

- [ ] **Step 7: Commit**

```bash
git add OpenRow.spoon/lib/alphabet.lua tests/unit/lib/alphabet_spec.lua OpenRow.spoon/init.lua
git commit -m "refactor: extract hint label generation into lib/alphabet.lua

Replaces obj:_labelSequence / obj:_labelLengthForCount with pure
functions lengthFor / labelAt / generate. Adds 8 unit tests covering
equal length, prefix-freeness, and edge cases (empty count)."
```

---

## Task 6: core/geometry.lua + tests (M1.3)

**Files:**
- Create: `OpenRow.spoon/core/geometry.lua`
- Create: `tests/unit/core/geometry_spec.lua`
- Modify: `OpenRow.spoon/init.lua`

- [ ] **Step 1: Write `tests/unit/core/geometry_spec.lua`**

```bash
mkdir -p tests/unit/core
```

```lua
package.path = package.path .. ";./OpenRow.spoon/?.lua"
local geom = require("core.geometry")

describe("geometry.center", function()
  it("returns midpoint", function()
    assert_deep_equals(geom.center({x=0, y=0, w=10, h=20}), {x=5, y=10})
    assert_deep_equals(geom.center({x=100, y=200, w=4, h=8}), {x=102, y=204})
  end)
end)

describe("geometry.contains", function()
  it("is true when inner is fully inside outer", function()
    assert_true(geom.contains({x=0,y=0,w=100,h=100}, {x=10,y=10,w=20,h=20}))
  end)

  it("is true when inner equals outer", function()
    assert_true(geom.contains({x=0,y=0,w=10,h=10}, {x=0,y=0,w=10,h=10}))
  end)

  it("is false when inner extends past outer right edge", function()
    assert_false(geom.contains({x=0,y=0,w=10,h=10}, {x=5,y=0,w=10,h=10}))
  end)
end)

describe("geometry.intersect", function()
  it("returns the overlap rect", function()
    local r = geom.intersect({x=0,y=0,w=10,h=10}, {x=5,y=5,w=10,h=10})
    assert_deep_equals(r, {x=5, y=5, w=5, h=5})
  end)

  it("returns nil for disjoint rects", function()
    assert_nil(geom.intersect({x=0,y=0,w=10,h=10}, {x=20,y=20,w=5,h=5}))
  end)

  it("returns nil for edge-touching rects (no positive area)", function()
    assert_nil(geom.intersect({x=0,y=0,w=10,h=10}, {x=10,y=0,w=5,h=10}))
  end)
end)

describe("geometry.framesAlmostEqual", function()
  it("is true for identical frames", function()
    assert_true(geom.framesAlmostEqual({x=10,y=20,w=30,h=40}, {x=10,y=20,w=30,h=40}))
  end)

  it("is true for sub-eps differences", function()
    assert_true(geom.framesAlmostEqual({x=10,y=20,w=30,h=40}, {x=11,y=21,w=31,h=41}))
  end)

  it("is false for differences >= eps in any dimension", function()
    assert_false(geom.framesAlmostEqual({x=10,y=20,w=30,h=40}, {x=14,y=20,w=30,h=40}))
  end)
end)

describe("geometry.frameValid", function()
  it("is false for nil or zero-sized frames", function()
    assert_false(geom.frameValid(nil))
    assert_false(geom.frameValid({x=0,y=0,w=0,h=10}))
    assert_false(geom.frameValid({x=0,y=0,w=10,h=0}))
    assert_false(geom.frameValid({x=0,y=0,w=-1,h=10}))
  end)

  it("is true for positive-sized frames", function()
    assert_true(geom.frameValid({x=0,y=0,w=1,h=1}))
  end)

  it("is false when missing fields", function()
    assert_false(geom.frameValid({x=0,y=0,w=1}))
  end)
end)
```

- [ ] **Step 2: Run, expect failure**

Run: `lua tests/run.lua`
Expected: "module 'core.geometry' not found".

- [ ] **Step 3: Write `OpenRow.spoon/core/geometry.lua`**

```bash
mkdir -p OpenRow.spoon/core
```

```lua
-- OpenRow.spoon/core/geometry.lua — pure frame math.

local M = {}

function M.center(frame)
  return { x = frame.x + frame.w / 2, y = frame.y + frame.h / 2 }
end

function M.contains(outer, inner)
  return outer.x <= inner.x
    and outer.y <= inner.y
    and outer.x + outer.w >= inner.x + inner.w
    and outer.y + outer.h >= inner.y + inner.h
end

function M.intersect(a, b)
  local x1 = math.max(a.x, b.x)
  local y1 = math.max(a.y, b.y)
  local x2 = math.min(a.x + a.w, b.x + b.w)
  local y2 = math.min(a.y + a.h, b.y + b.h)
  if x2 <= x1 or y2 <= y1 then return nil end
  return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

function M.framesAlmostEqual(a, b, eps)
  eps = eps or 3
  local ca = M.center(a)
  local cb = M.center(b)
  return math.abs(ca.x - cb.x) < eps
    and math.abs(ca.y - cb.y) < eps
    and math.abs(a.w - b.w) < eps
    and math.abs(a.h - b.h) < eps
end

function M.frameValid(frame)
  return frame ~= nil
    and frame.x ~= nil and frame.y ~= nil
    and frame.w ~= nil and frame.h ~= nil
    and frame.w > 0 and frame.h > 0
end

function M.intersectsAnyScreen(frame, screens)
  if not M.frameValid(frame) then return false end
  for _, s in ipairs(screens) do
    local v = s:fullFrame()
    if frame.x < v.x + v.w
        and frame.x + frame.w > v.x
        and frame.y < v.y + v.h
        and frame.y + frame.h > v.y then
      return true
    end
  end
  return false
end

return M
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `lua tests/run.lua`
Expected: alphabet tests still pass; geometry tests pass; total ~16 tests, 0 failed.

- [ ] **Step 5: Integrate into `OpenRow.spoon/init.lua`**

Add near the top:

```lua
local geometry = dofile(hs.spoons.scriptPath() .. "core/geometry.lua")
```

Delete these four local function definitions:
- `local function frameCenter(frame) ... end` (currently lines 110-115)
- `local function frameVisible(frame, screens) ... end` (currently lines 132-146)
- `local function rectContains(outer, inner) ... end` (currently lines 210-215)
- `local function framesAlmostEqual(left, right) ... end` (currently lines 217-222)

Replace callsites:
- `frameCenter(...)` -> `geometry.center(...)`
- `frameVisible(frame, screens)` -> `geometry.intersectsAnyScreen(frame, screens)`
- `rectContains(...)` -> `geometry.contains(...)`
- `framesAlmostEqual(...)` -> `geometry.framesAlmostEqual(...)`

Verify with:

```bash
grep -n 'frameCenter\|rectContains\|framesAlmostEqual\|frameVisible' OpenRow.spoon/init.lua
```

Expect zero matches except imports/comments.

- [ ] **Step 6: Verify spoon still works**

Run: `bash scripts/install.sh`
Trigger Cmd+Shift+Space; confirm labels appear at element centers; click a target, verify it activates.

- [ ] **Step 7: Commit**

```bash
git add OpenRow.spoon/core/geometry.lua tests/unit/core/geometry_spec.lua OpenRow.spoon/init.lua
git commit -m "refactor: extract frame math into core/geometry.lua

center / contains / intersect / framesAlmostEqual / frameValid /
intersectsAnyScreen replace inline helpers in init.lua. Adds unit tests
for all six functions; existing alphabet tests still pass."
```

---

## Task 7: core/element.lua + tests (M1.4a)

**Files:**
- Create: `OpenRow.spoon/core/element.lua`
- Create: `tests/unit/core/element_spec.lua`

- [ ] **Step 1: Write `tests/unit/core/element_spec.lua`**

```lua
package.path = package.path .. ";./OpenRow.spoon/?.lua"
local Element = require("core.element")

local function sample()
  return Element.new({
    rawId = "0xabc",
    role = "AXButton",
    frame = {x=10, y=20, w=30, h=40},
    actions = {"AXPress", "AXShowMenu"},
    title = "OK",
    description = "Confirm dialog",
    value = nil,
    help = nil,
  })
end

describe("Element.new", function()
  it("preserves all fields", function()
    local e = sample()
    assert_equals(Element.role(e), "AXButton")
    assert_deep_equals(Element.frame(e), {x=10, y=20, w=30, h=40})
    assert_deep_equals(Element.actions(e), {"AXPress", "AXShowMenu"})
    assert_equals(Element.rawId(e), "0xabc")
  end)

  it("defaults missing fields", function()
    local e = Element.new({ role = "AXGroup", frame = {x=0,y=0,w=1,h=1} })
    assert_deep_equals(Element.actions(e), {})
    assert_deep_equals(Element.children(e), {})
  end)
end)

describe("Element.searchText", function()
  it("concatenates role/title/description/value/help in lowercase", function()
    local e = sample()
    local txt = Element.searchText(e)
    assert_true(txt:find("axbutton", 1, true) ~= nil, "missing role")
    assert_true(txt:find("ok", 1, true) ~= nil, "missing title")
    assert_true(txt:find("confirm dialog", 1, true) ~= nil, "missing description")
  end)

  it("handles missing fields without erroring", function()
    local e = Element.new({ role = "AXButton", frame = {x=0,y=0,w=1,h=1} })
    local txt = Element.searchText(e)
    assert_true(txt:find("axbutton", 1, true) ~= nil)
  end)

  it("returns the same string on second call (cached)", function()
    local e = sample()
    local first = Element.searchText(e)
    local second = Element.searchText(e)
    assert_equals(first, second)
  end)
end)

describe("Element.children", function()
  it("returns the children list when set", function()
    local child = Element.new({ role = "AXCell", frame = {x=0,y=0,w=1,h=1} })
    local parent = Element.new({
      role = "AXRow", frame = {x=0,y=0,w=10,h=10},
      children = { child },
    })
    assert_equals(#Element.children(parent), 1)
    assert_equals(Element.role(Element.children(parent)[1]), "AXCell")
  end)
end)
```

- [ ] **Step 2: Run, expect failure**

Run: `lua tests/run.lua`
Expected: "module 'core.element' not found".

- [ ] **Step 3: Write `OpenRow.spoon/core/element.lua`**

```lua
-- OpenRow.spoon/core/element.lua — pure data model for an AX element snapshot.
-- An Element is constructed once from raw AX attributes and never mutated
-- after creation (except for the lazy searchText cache).
-- The element_factory module produces Elements from hs.axuielement; tests
-- construct Elements directly with plain tables.

local M = {}

local function lower(s) return s and tostring(s):lower() or "" end

function M.new(t)
  return {
    rawId = t.rawId,
    role = t.role or "",
    frame = t.frame,
    actions = t.actions or {},
    title = t.title,
    description = t.description,
    value = t.value,
    help = t.help,
    enabled = t.enabled,
    children = t.children or {},
  }
end

function M.role(e)     return e.role end
function M.frame(e)    return e.frame end
function M.actions(e)  return e.actions end
function M.children(e) return e.children end
function M.enabled(e)  return e.enabled end
function M.rawId(e)    return e.rawId end

function M.searchText(e)
  if e._searchText then return e._searchText end
  e._searchText = table.concat({
    lower(e.role),
    lower(e.title),
    lower(e.description),
    lower(e.value),
    lower(e.help),
  }, " ")
  return e._searchText
end

return M
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `lua tests/run.lua`
Expected: all tests pass; total ~22 tests, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add OpenRow.spoon/core/element.lua tests/unit/core/element_spec.lua
git commit -m "feat: add core/element.lua pure data model

Element snapshot with role / frame / actions / children / enabled and
a cached searchText. No hs.* dependency; tests construct Elements
directly. Used by element_factory in the next commit and by
scan/tree.lua in M2."
```

---

## Task 8: core/element_factory.lua + integrate (M1.4b)

**Files:**
- Create: `OpenRow.spoon/core/element_factory.lua`
- Modify: `OpenRow.spoon/init.lua`

- [ ] **Step 1: Write `OpenRow.spoon/core/element_factory.lua`**

```lua
-- OpenRow.spoon/core/element_factory.lua — hs.axuielement adapter.
-- Wraps unsafe attribute reads in pcall and produces Element snapshots.
-- This is the only impure module in core/; everything else is testable
-- in plain Lua without Hammerspoon.

local Element = dofile(hs.spoons.scriptPath() .. "core/element.lua")

local M = {}

local CHILD_ATTRS = {
  "AXChildren",
  "AXVisibleChildren",
  "AXChildrenInNavigationOrder",
  "AXRows",
  "AXColumns",
  "AXCells",
  "AXContents",
}

function M.safeAttribute(raw, attr)
  local ok, v = pcall(function() return raw:attributeValue(attr) end)
  if ok then return v end
  return nil
end

function M.safeSetAttribute(raw, attr, value)
  local ok, result = pcall(function() return raw:setAttributeValue(attr, value) end)
  return ok and result ~= false
end

function M.safeActionNames(raw)
  local ok, v = pcall(function()
    if raw.actionNames then return raw:actionNames() end
    return raw:attributeValue("AXActions")
  end)
  if ok and type(v) == "table" then return v end
  return {}
end

function M.from(raw)
  if raw == nil then return nil end
  local role = M.safeAttribute(raw, "AXRole")
  local frame = M.safeAttribute(raw, "AXFrame")
  if role == nil or frame == nil then return nil end
  return Element.new({
    rawId = tostring(raw),
    role = role,
    frame = frame,
    actions = M.safeActionNames(raw),
    title = M.safeAttribute(raw, "AXTitle"),
    description = M.safeAttribute(raw, "AXDescription"),
    value = M.safeAttribute(raw, "AXValue"),
    help = M.safeAttribute(raw, "AXHelp"),
    enabled = M.safeAttribute(raw, "AXEnabled"),
  })
end

function M.rawChildren(raw)
  local children = {}
  local seen = {}
  for _, attr in ipairs(CHILD_ATTRS) do
    local v = M.safeAttribute(raw, attr)
    if type(v) == "table" then
      for _, c in ipairs(v) do
        local id = tostring(c)
        if not seen[id] then
          seen[id] = true
          table.insert(children, c)
        end
      end
    end
  end
  return children
end

return M
```

- [ ] **Step 2: Replace inline helpers in `OpenRow.spoon/init.lua`**

Add near the top:

```lua
local element_factory = dofile(hs.spoons.scriptPath() .. "core/element_factory.lua")
```

Delete these local function definitions (line numbers based on the post-Task 6 state, may have shifted):
- `local function safeAttribute(...)` (was lines 99-103)
- `local function safeSetAttribute(...)` (was lines 105-108)
- `local function safeActionNames(...)` (was lines 161-168)
- `local function appendUniqueChildren(...)` (was lines 263-272)
- `local function collectChildren(...)` (was lines 274-283)

Replace callsites:
- `safeAttribute(elem, attr)` -> `element_factory.safeAttribute(elem, attr)`
- `safeSetAttribute(...)` -> `element_factory.safeSetAttribute(...)`
- `safeActionNames(...)` -> `element_factory.safeActionNames(...)`
- `collectChildren(element, self.config.childAttributes)` -> `element_factory.rawChildren(element)`

The config field `childAttributes` is now unused. Replace its definition with a deprecation comment so external configs don't break silently:

```lua
  -- childAttributes is now owned by core/element_factory.lua. Kept
  -- here as a stub for v1 backward compatibility; safe to remove once
  -- no external code reads it.
  childAttributes = {},
```

Verify:

```bash
grep -n 'safeAttribute\|safeSetAttribute\|safeActionNames\|collectChildren\|appendUniqueChildren' OpenRow.spoon/init.lua
```

Expect only `element_factory.safe*` and `element_factory.rawChildren(...)` references.

- [ ] **Step 3: Verify spoon still works**

Run: `bash scripts/install.sh`
Trigger Cmd+Shift+Space; click a target. Verify nothing regresses.

- [ ] **Step 4: Commit**

```bash
git add OpenRow.spoon/core/element_factory.lua OpenRow.spoon/init.lua
git commit -m "refactor: extract hs.axuielement wrapper into core/element_factory.lua

safeAttribute / safeSetAttribute / safeActionNames / rawChildren plus
Element.from(rawAxElement) for the M2 scan rewrite. The data/wrapper
split keeps 90% of element logic in the pure core/element.lua and
isolates the only untestable code into this single file."
```

---

## Task 9: core/overlay.lua + integrate (M1.5)

**Files:**
- Create: `OpenRow.spoon/core/overlay.lua`
- Modify: `OpenRow.spoon/init.lua`

- [ ] **Step 1: Write `OpenRow.spoon/core/overlay.lua`**

```lua
-- OpenRow.spoon/core/overlay.lua — hs.canvas wrapper.
-- An Overlay owns a list of canvas objects. clear() must :delete() each
-- canvas (not :hide()), otherwise repeated activations leak resources.

local geometry = dofile(hs.spoons.scriptPath() .. "core/geometry.lua")

local Overlay = {}
Overlay.__index = Overlay

local M = {}

function M.new()
  return setmetatable({ _canvases = {} }, Overlay)
end

function Overlay:showDim(opacity)
  for _, screen in ipairs(hs.screen.allScreens()) do
    local frame = screen:fullFrame()
    local dim = hs.canvas.new(frame)
    dim:level(hs.canvas.windowLevels.overlay)
    dim:behavior({
      hs.canvas.windowBehaviors.canJoinAllSpaces,
      hs.canvas.windowBehaviors.stationary,
    })
    dim:appendElements({
      type = "rectangle", action = "fill",
      frame = { x = 0, y = 0, w = frame.w, h = frame.h },
      fillColor = { white = 0, alpha = opacity or 0.08 },
    })
    dim:show()
    table.insert(self._canvases, dim)
  end
end

-- items: list of { frame = {x,y,w,h}, text = "ab" }
-- style: { textSize, paddingX, paddingY, radius }
function Overlay:showLabels(items, style)
  style = style or {}
  local textSize = style.textSize or 14
  local paddingX = style.paddingX or 5
  local paddingY = style.paddingY or 2
  local radius = style.radius or 4

  for _, item in ipairs(items) do
    local center = geometry.center(item.frame)
    local width = math.max(22, (#item.text * textSize * 0.62) + paddingX * 2)
    local height = textSize + paddingY * 2 + 3
    local rect = {
      x = center.x - width / 2,
      y = center.y - height / 2,
      w = width, h = height,
    }
    local canvas = hs.canvas.new(rect)
    canvas:level(hs.canvas.windowLevels.overlay)
    canvas:behavior({
      hs.canvas.windowBehaviors.canJoinAllSpaces,
      hs.canvas.windowBehaviors.stationary,
    })
    canvas:appendElements({
      {
        type = "rectangle", action = "fill",
        roundedRectRadii = { xRadius = radius, yRadius = radius },
        frame = { x = 0, y = 0, w = width, h = height },
        fillColor = { red = 0.98, green = 0.82, blue = 0.22, alpha = 0.95 },
      },
      {
        type = "text", text = item.text,
        textAlignment = "center", textSize = textSize,
        textColor = { red = 0.08, green = 0.08, blue = 0.08, alpha = 1 },
        frame = { x = 0, y = 1, w = width, h = height },
      },
    })
    canvas:show()
    table.insert(self._canvases, canvas)
  end
end

function Overlay:clear()
  for _, c in ipairs(self._canvases) do c:delete() end
  self._canvases = {}
end

return M
```

- [ ] **Step 2: Replace `_drawOverlay` and `_clearOverlay` in `OpenRow.spoon/init.lua`**

Add near the top:

```lua
local Overlay = dofile(hs.spoons.scriptPath() .. "core/overlay.lua")
```

In the obj state block, replace `obj._canvases = {}` with `obj._overlay = nil`.

Replace `obj:_clearOverlay()`:

```lua
function obj:_clearOverlay()
  if self._overlay then self._overlay:clear() end
end
```

Replace `obj:_drawOverlay()`:

```lua
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
    radius   = self.config.overlayRadius,
  })
end
```

In `obj:deactivate()`, after the existing `self:_clearOverlay()` line, add:

```lua
  self._overlay = nil
```

Verify:

```bash
grep -n 'self._canvases' OpenRow.spoon/init.lua
```

Expect zero matches.

- [ ] **Step 3: Verify spoon still works**

Run: `bash scripts/install.sh`
Trigger Cmd+Shift+Space; verify dim background + yellow labels render at element centers exactly as before. Click a label; verify the overlay is removed before the click and the click activates the target.

- [ ] **Step 4: Commit**

```bash
git add OpenRow.spoon/core/overlay.lua OpenRow.spoon/init.lua
git commit -m "refactor: extract overlay rendering into core/overlay.lua

Overlay.new() / overlay:showDim / overlay:showLabels / overlay:clear
replace inline _drawOverlay / _clearOverlay. Canvas list now lives
inside the Overlay instance; init.lua holds a single _overlay
reference cleared and nilled on deactivate."
```

---

## Task 10: core/input.lua + tests + integrate (M1.6)

**Files:**
- Create: `OpenRow.spoon/core/input.lua`
- Create: `tests/unit/core/input_spec.lua`
- Modify: `OpenRow.spoon/init.lua`
- Modify: `README.md`

- [ ] **Step 1: Write `tests/unit/core/input_spec.lua`**

```lua
package.path = package.path .. ";./OpenRow.spoon/?.lua"
local input = require("core.input")

describe("input.modifierAction", function()
  it("returns leftClick when no modifiers", function()
    assert_equals(input.modifierAction({}), "leftClick")
    assert_equals(input.modifierAction({shift=false, cmd=false, alt=false}), "leftClick")
  end)

  it("returns rightClick on shift", function()
    assert_equals(input.modifierAction({shift=true}), "rightClick")
  end)

  it("returns doubleClick on cmd", function()
    assert_equals(input.modifierAction({cmd=true}), "doubleClick")
  end)

  it("returns move on alt/option", function()
    assert_equals(input.modifierAction({alt=true}), "move")
  end)

  it("prefers shift over cmd over alt when multiple are set", function()
    assert_equals(input.modifierAction({shift=true, cmd=true, alt=true}), "rightClick")
    assert_equals(input.modifierAction({cmd=true, alt=true}), "doubleClick")
  end)
end)
```

- [ ] **Step 2: Run, expect failure**

Run: `lua tests/run.lua`
Expected: "module 'core.input' not found".

- [ ] **Step 3: Write `OpenRow.spoon/core/input.lua`**

```lua
-- OpenRow.spoon/core/input.lua — input event parsing.
-- modifierAction is pure (testable). parse() wraps hs.eventtap and is
-- only exercised at runtime inside Hammerspoon.

local M = {}

function M.modifierAction(modifiers)
  modifiers = modifiers or {}
  if modifiers.shift then return "rightClick" end
  if modifiers.cmd   then return "doubleClick" end
  if modifiers.alt   then return "move" end
  return "leftClick"
end

function M.parse(event)
  local kind = "ignore"
  if event:getType() == hs.eventtap.event.types.keyDown then kind = "keyDown" end

  local key = hs.keycodes.map[event:getKeyCode()]
  local flags = event:getFlags()
  return {
    kind = kind,
    key = key,
    shift = flags.shift == true,
    cmd   = flags.cmd   == true,
    alt   = flags.alt   == true,
    ctrl  = flags.ctrl  == true,
  }
end

return M
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `lua tests/run.lua`
Expected: all tests pass; total ~30 tests, 0 failed.

- [ ] **Step 5: Integrate `parse` into `OpenRow.spoon/init.lua`**

Add near the top:

```lua
local input = dofile(hs.spoons.scriptPath() .. "core/input.lua")
```

In `obj:_handleInput(event)`, replace the first three lines:

```lua
function obj:_handleInput(event)
  local eventType = event:getType()
  if eventType ~= hs.eventtap.event.types.keyDown then return true end

  local key = hs.keycodes.map[event:getKeyCode()]
```

with:

```lua
function obj:_handleInput(event)
  local parsed = input.parse(event)
  if parsed.kind ~= "keyDown" then return true end
  local key = parsed.key
```

Note: `modifierAction` is not yet wired into the click flow; right-click / double-click on hint labels will be wired in M3 when the hint mode is extracted. This keeps the M1 patch surgical.

- [ ] **Step 6: Verify spoon still works**

Run: `bash scripts/install.sh`
Trigger Cmd+Shift+Space; type a label; verify the target activates. Press Esc; verify deactivation. Press `/` then type filter text; verify search mode still filters labels.

- [ ] **Step 7: Update `README.md` Development section**

Append to `README.md`:

```markdown

## Development

Requirements:
- macOS with [Hammerspoon](https://www.hammerspoon.org/)
- Lua 5.1+ on `$PATH` (e.g. `brew install lua`)

Workflow:

```bash
# Run unit tests
lua tests/run.lua

# Sync the spoon into ~/.hammerspoon and reload Hammerspoon
bash scripts/install.sh

# Manual smoke (release gate)
open tests/manual/smoke-checklist.md
```

Module layout under `OpenRow.spoon/`:

- `core/` — atomic capabilities: element data model, factory (the only impure file), geometry, overlay, input parsing
- `lib/` — utilities: alphabet (hint label generation), log (channelled debug)
```

- [ ] **Step 8: Commit**

```bash
git add OpenRow.spoon/core/input.lua tests/unit/core/input_spec.lua OpenRow.spoon/init.lua README.md
git commit -m "refactor: extract input parsing into core/input.lua

input.parse(event) wraps hs.eventtap event into a structured kind/key/
modifier record. input.modifierAction(modifiers) is pure and unit-tested
(5 cases covering precedence). README adds a Development section
pointing at tests/run.lua and scripts/install.sh."
```

---

## Verification at end of Plan 1

Run all of the following and verify each passes:

- [ ] **Unit tests:** `lua tests/run.lua` — exit 0; ~30 tests, 0 failed
- [ ] **Spoon installs:** `bash scripts/install.sh` — exits 0
- [ ] **Smoke (Hint mode unchanged):** trigger Cmd+Shift+Space in Finder, type a label, verify the file/folder activates
- [ ] **Smoke (Search mode unchanged):** trigger Cmd+Shift+Space, press `/`, type filter text, verify labels narrow
- [ ] **Module count:** `ls OpenRow.spoon/lib/*.lua OpenRow.spoon/core/*.lua | wc -l` — 7 files
- [ ] **init.lua slimmer:** `wc -l OpenRow.spoon/init.lua` — under 500 lines (was 635 at baseline)
- [ ] **Git log:** `git log --oneline | head -15` — shows 10 new commits since `dc2a61f` (P0/P1 baseline)

If any step fails, do not start Plan 2 (M2). Investigate, fix, and re-run verification.

---

## Stop conditions / hand-off to Plan 2

Plan 1 is complete when all verification steps above pass and a working session has confirmed Hint mode + Search behave as before. Then author Plan 2 (M2 scan rewrite). Plan 2 will:

- Move scan logic from `init.lua::_scanElement / _scanTargets` into `scan/tree.lua`, `scan/traverser.lua`, `scan/dispatch.lua`, `scan/coordinator.lua`.
- Capture AX-tree fixtures from real apps and add regression tests for the Claude Code stacked-label / AXStaticText section-header / focused-window-only cases.
- Add `scan/traverser_table.lua`, `scan/menubar.lua`, `scan/traverser_web.lua`, `scan/extras.lua` as new capabilities.
- Re-run the manual smoke checklist after the swap-in commit (M2.4).
