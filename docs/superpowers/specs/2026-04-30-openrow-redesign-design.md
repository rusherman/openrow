# OpenRow Redesign — Design Spec

- Date: 2026-04-30
- Status: Approved (brainstorming complete, ready for implementation planning)
- Scope: Hammerspoon Lua re-architecture of the existing single-file `OpenRow.spoon/init.lua` prototype

---

## 1. Goal & Scope

### 1.1 Why a redesign

The current `init.lua` is a 600-line single file. Recent debugging surfaced root causes that are not isolated bugs but architectural smell:

- Click-point logic disagrees with overlay placement (visual offset).
- Background windows are scanned alongside the focused one.
- Parent containers and child controls coexist in the target list (multi-label stacking).
- `AXPress` is attempted opportunistically and silently succeeds without UI activation.
- The fallback role list (`AXStaticText`, `AXGroup`) introduces noise that no amount of dedupe heuristics fully resolves.

Patching each symptom invites the next. The redesign moves to bounded modules where each rule lives in exactly one place.

### 1.2 In scope

- Hammerspoon Lua only (no Swift native rewrite this round).
- Two top-level modes: Hint (with a Search sub-state) and Scroll.
- Target apps: native AppKit, system surfaces (menu bar, status icons, notification center), Electron, WebKit Safari.
- Modular file layout, hand-written assert-based test runner, fixture-based regression tests.

### 1.3 Out of scope

- Swift native rewrite.
- Chromium-specific browser specialization (Chrome / Edge / Arc).
- Terminal / TUI specialization.
- Grid mode, keyboard-mouse simulation, tab cycling between matches.
- Element re-read between scan and click (frame snapshot is treated as authoritative for the click).
- IME candidate windows.
- Stage Manager / Mission Control activation.
- CI, luarocks, lint tooling.

---

## 2. High-Level Architecture

### 2.1 Three layers

| Layer | Files | Owns | Does Not Own |
|---|---|---|---|
| Coordinator | `init.lua` | Mode switching, hotkey, Accessibility check | Element scanning, label drawing |
| Mode | `modes/*.lua` | State machine for the active mode, intent handling, action requests | AX scanning, canvas drawing |
| Service | `core/*`, `scan/*`, `lib/*` | Atomic capabilities (scan, geometry, overlay, input parsing, alphabet generation) | Business workflow, mode transitions |

### 2.2 Lifecycle (Hint mode example)

```
[Hotkey] -> Coordinator -> Mode (Hint)
                 |
                 +-> 1. Scan
                 |     - scan/coordinator merges three sources:
                 |       window traverser (focused window only, dispatch by role)
                 |       menubar traverser (current app)
                 |       extras traverser (status icons + notification center)
                 |     - tree.hintableElements() applies isHintable rules
                 |
                 +-> 2. Render
                 |     overlay.showDim + overlay.showLabels
                 |
                 +-> 3. Input
                 |     eventtap -> InputEvent -> mode.onIntent
                 |
                 +-> 4. Action
                       overlay.clear -> eventtap.stop -> execute click
```

### 2.3 Invariants

1. Exactly one active mode at any time. Switching deactivates the previous mode first.
2. Coordinator owns the single eventtap. Modes declare which intents they accept; they never hook keys directly.
3. Service layer is stateless across calls. State lives in Coordinator and Mode.
4. Action execution order is fixed: clear overlay -> stop eventtap -> simulate click.

---

## 3. Module Map & Contracts

### 3.1 Layout

```
OpenRow.spoon/
  init.lua                     # Coordinator + config + hotkey
  core/
    element.lua                # Element data model (snapshot)
    element_factory.lua        # hs.axuielement wrapper (only impure code)
    geometry.lua               # frame math
    overlay.lua                # canvas dim + labels
    input.lua                  # NSEvent -> structured InputEvent
  scan/
    tree.lua                   # parent-child relations + isHintable
    traverser.lua              # generic DFS + clipBounds
    traverser_web.lua          # AXUIElementsForSearchPredicate
    traverser_table.lua        # AXVisibleRows for AXTable / AXOutline
    dispatch.lua               # role -> traverser
    menubar.lua                # current-app menu bar
    extras.lua                 # status icons + notification center
    coordinator.lua            # merges all three sources
  modes/
    controller.lua             # interface contract
    hint.lua                   # Label state + Search sub-state
    scroll.lua                 # PickArea + Active states
  lib/
    alphabet.lua               # equal-length conflict-free hint strings
    log.lua                    # channelled debug logging
```

### 3.2 Public interfaces (selected)

```lua
-- core/element.lua
M.from(rawAxElement) -> Element | nil
M.role(element) -> string
M.frame(element) -> {x, y, w, h}
M.actions(element) -> string[]
M.searchText(element) -> string
M.children(element) -> Element[]

-- core/geometry.lua
M.center(frame) -> {x, y}
M.contains(outer, inner) -> bool
M.intersect(a, b) -> frame | nil
M.framesAlmostEqual(a, b, eps) -> bool
M.visibleOnAnyScreen(frame) -> bool

-- core/overlay.lua
local overlay = M.new()
overlay:showDim(opacity)
overlay:showLabels({ {frame, text, style}, ... })
overlay:clear()       -- must :delete() each canvas, not :hide()

-- scan/tree.lua
local tree = M.new()
tree:insert(element, parentRawId | nil) -> bool
tree:children(rawId) -> Element[]
tree:hintableElements() -> Element[]

-- modes/controller.lua (interface)
ModeController = {
  activate(self, ctx),         -- ctx provides overlay, scan, exec
  onIntent(self, intent),      -- returns { action?, exit? }
  deactivate(self),
}
```

### 3.3 Dependency rule

Dependencies point downward only:

```
init.lua -> modes/* -> {core/*, scan/*, lib/*}
                            scan/coordinator -> scan/{tree, traverser*, dispatch, menubar, extras}
                                                 traverser* -> core/{element, geometry}
```

`scan/` cannot import `modes/`. `core/` cannot import `scan/` or `modes/`. Circular imports are a review failure.

---

## 4. Mode State Machines

### 4.1 Coordinator

```
[Idle] --hotkey--> [Activating] --scan ok--> [Hint:Label]
                       |
                       +--scan fail/empty--> [Idle] (alert "no targets")
```

On entering any active state: acquire eventtap, draw dim, clear residual canvases.
On leaving any active state: release eventtap, clear canvases, reset internal buffers.

### 4.2 Hint mode (with Search sub-state)

```
[Hint:Label]
  buffer = ""

  on char c:
    buffer += c
    if exact match: execute action; exit
    if prefix-of any visible label: redraw filtered labels
    else: alert "no label X"; exit

  on "/":
    -> [Hint:Search]; query = ""; buffer = ""

[Hint:Search]
  query = ""

  on char c:
    query += c
    matches = filter(_allTargets, query)
    re-assign hint strings via lib/alphabet.generate(#matches)
    redraw

  on Return:
    if 0 matches: alert; exit
    if 1 match:   execute action; exit
    if >1:        -> [Hint:Label] with the filtered set

  on "/" or Esc:  -> [Hint:Label]; restore full target set; buffer = ""

Universal in both substates:
  Esc        -> Coordinator deactivate
  Backspace  -> drop last char from active buffer/query
  Modifiers  -> Shift+Enter = right-click, Cmd+Enter = double-click,
                Option+Enter = move only, default = left-click
```

Search filters in-memory only; no re-scan. Hint strings are regenerated for the filtered set so labels stay short.

### 4.3 Scroll mode

```
[Scroll:PickArea]
  scan AXScrollArea elements; assign hint labels

  on hint match: -> [Scroll:Active] with chosen area

[Scroll:Active]
  active = ScrollArea

  h/j/k/l           -> single-step scroll (delta = line)
  Shift + h/j/k/l   -> half page (delta = height/2)
  d / u             -> half page down / up (vim style)
  Space / b         -> full page down / up
  g / G             -> top / bottom
  Tab               -> -> [Scroll:PickArea]
  Esc               -> deactivate

  Display: small corner indicator showing the active area name; no hint labels.
```

Scroll events use `hs.eventtap.event.newScrollEvent`, not synthetic mouse-wheel events. Some Electron apps respond unreliably to wheel synthesis; `newScrollEvent` is the more compatible primitive.

### 4.4 Inter-mode transitions

Hint and Scroll have separate hotkeys (`Cmd+Shift+Space` and `Cmd+Shift+S` respectively). No direct in-mode jump from Hint to Scroll in v1.

### 4.5 Modifier key mapping

Adopted directly from Vimac / Homerow muscle memory:

| Modifier + label key | Action |
|---|---|
| (none) | left click |
| Shift | right click |
| Cmd | double left click |
| Option | move mouse to target only |

---

## 5. Error Handling

### 5.1 Fail loudly

| Situation | Action | Layer |
|---|---|---|
| Accessibility permission missing | alert + open System Settings hint; do not enter any mode | Coordinator pre-check |
| No frontmost app | alert "No active app"; do not enter mode | Coordinator pre-check |
| Scan returns empty | alert "No clickable targets"; idle | scan/coordinator -> Coordinator |
| Hint:Label dead-end prefix | alert "no label X"; exit | hint mode |
| Hint:Search no match | inline "no match" indicator; user keeps typing or Esc | hint mode (search) |

### 5.2 Fail safe (silent degradation)

| Situation | Behavior | Reason |
|---|---|---|
| `safeAttribute` raises | return nil; element dropped upstream | AX flickers during app switches |
| `Element.from` cannot read role/frame | return nil; filtered out | same |
| WebArea lacks `AXUIElementsForSearchPredicate` | dispatch falls back to generic traverser | Firefox / older WebKit / some Electron |
| Selected target frame off-screen | clamp click point to nearest screen edge | better than failing outright |
| `hs.eventtap.leftClick` rejected by system | silent; debug log only | nothing to recover to |
| Multi-display with negative sub-screen coords | trust AX frame and `hs.canvas` (same coordinate space) | Hammerspoon already abstracts this |
| Fullscreen on secondary display where `NSScreen.main` is wrong | overlay uses `frame intersect allScreens` rather than `main` alone | Vimac has the same workaround |
| Hammerspoon config reload while spoon active | no top-level mutable state; Coordinator on `init` force-deactivates if `_active` was true | prevents canvas/eventtap leaks |

### 5.3 Explicitly unsupported

| Case | Why deferred |
|---|---|
| Element movement between scan and click | adds complexity for a rare event (sub-second window) |
| Sandboxed apps without AX | not solvable from the Hammerspoon side |
| Terminal character-level pseudo-clickability | out of scope |
| IME candidate windows | typically not AX-enumerable |
| Stage Manager / Mission Control activation | OS-level conflicts |
| Multi-keyboard or stuck modifier states | user must restart Hammerspoon |

### 5.4 Resource lifecycle

Mode `deactivate` must release:

- All canvases (`overlay:clear` deletes, not hides)
- Any cached Element references (assign nil)
- Any pending `hs.timer.doAfter` handles

Coordinator must:

- Hold a single eventtap; start on activate, stop and nil on deactivate
- Make double-deactivate a no-op
- Wrap activate body in `xpcall` to ensure deactivate runs on exception

### 5.5 Logging

`lib/log.lua` provides four channels:

```lua
log.scan(fmt, ...)    -- on when config.debug.scan = true
log.input(fmt, ...)   -- on when config.debug.input = true
log.action(fmt, ...)  -- on when config.debug.action = true
log.error(fmt, ...)   -- always on
```

All channels default off. Required logging points:

- Each scan: `n_targets / time_ms / app_name`
- Each click: `label / role / kind / frame / point / source(hint|search)`
- Each dispatch: chosen traverser name (diagnose "why is Safari not using search predicate")

---

## 6. Testing Strategy

### 6.1 Pyramid

```
Top    : Manual smoke against ~10 target apps
Middle : Mode state-machine tests with mock services
Base   : Unit tests on geometry, alphabet, tree, dispatch
```

No automated integration. Real AX in CI is high effort, low ROI.

### 6.2 Tooling

- Hand-written assert-based runner under `tests/run.lua` (< 50 lines, no external deps).
- Layout: `tests/unit/`, `tests/fixtures/`, `tests/manual/`.
- Run locally: `lua tests/run.lua`.

### 6.3 Per-module testability

| Module | Coverage target | What to test |
|---|---|---|
| `lib/alphabet.lua` | 100% (pure) | equal length, prefix-free, char-set exhaustion |
| `core/geometry.lua` | 100% (pure) | center, contains, intersect, framesAlmostEqual, multi-screen union |
| `scan/tree.lua` | 100% (pure on Element snapshots) | isHintable, isRowWithoutHintableChildren, hintableElements ordering |
| `scan/traverser.lua` | 90% (mock Element.children) | clipBounds propagation, maxDepth / maxElements caps |
| `scan/dispatch.lua` | 100% | role -> traverser mapping |
| `modes/hint.lua` | 80% (mock services) | advance / backspace / rotate / search substate / no-match |
| `modes/scroll.lua` | 80% | pickArea -> active -> emit scroll |
| `core/element.lua` (factory) | 0% | manual smoke only |
| `core/overlay.lua` | 0% | manual smoke only |
| `core/input.lua` | 30% | parse modifier flags only |

Element data model and the hs.axuielement wrapper are split into two files so 90% of the logic sits in the pure side.

### 6.4 Fixture workflow

- `core/element_factory.lua` exposes a `dumpTree(rawRoot)` helper used only in dev.
- Capture process: open target app -> Hammerspoon Console runs `OpenRow.dumpFocused()` -> save Lua table to `tests/fixtures/<app>_<view>.lua`.
- Required fixtures (v1): Finder list view, Safari article, VS Code editor, Claude Code chat list, System Settings.
- Tests load fixtures, feed them through `tree`/`traverser`, and assert on hintable count and identity.

### 6.5 Regression cases (must exist)

```
tests/unit/scan/tree_spec.lua
  isRowWithoutHintableChildren
    excludes AXRow when it has a hintable AXCell child   (Claude Code stacked-label regression)
    includes AXRow when it has no hintable child
  AXStaticText
    is never hintable on its own                          (Section header label regression)
  focused window only
    does not scan background windows
```

### 6.6 Manual smoke checklist (release gate)

| App | Verify |
|---|---|
| Finder list view | each row has 1 label; click opens folder |
| Safari arbitrary page | links / inputs / buttons all labelled; no missed dropdown |
| Claude Code chat list | each item has exactly 1 label; no AXStaticText label |
| VS Code | file tree, tabs, status bar, activity bar all clickable |
| System Settings | left categories + right toggles |
| Top menu bar | File/Edit/etc. each labelled |
| Status icons (Wi-Fi/battery) | clickable to open menu |
| Notification center | dismiss-able items labelled |

### 6.7 Not tested

| Skipped | Reason |
|---|---|
| `hs.canvas` visual diffs | low ROI; eyeball it |
| Multi-display scenarios | no rig; manual check |
| Performance benchmarks | not a perf product; profile on demand |
| Hard 80% coverage gate | encourages chasing coverage over meaning |

---

## 7. Migration Plan

### 7.0 Baseline commit

Current working tree carries the P0 + P1 fixes (center click, focused-window-only, AXPress removal, AXStaticText fallback removed, parent-child suppression). Land these first:

```
commit 1  feat: stabilize P0/P1 prior to redesign
commit 2  chore: scaffold tests/ structure (run.lua, unit/, fixtures/, manual/)
```

### 7.1 Milestones

#### M0 Infrastructure (small, ~1h)

- `tests/run.lua` minimal assert runner (< 50 lines).
- Skeleton directories with placeholders.
- `tests/manual/smoke-checklist.md` (Section 6.6 table).
- `scripts/install.sh`: copy spoon to `~/.hammerspoon/Spoons` and `hs.reload()`.

End condition: empty test suite passes; spoon behavior unchanged.

#### M1 Bottom-up extraction (medium, ~4-6h)

```
M1.1 lib/log.lua             channelled logger; replace inline calls
M1.2 lib/alphabet.lua        + tests/unit/alphabet_spec.lua
M1.3 core/geometry.lua       + tests/unit/geometry_spec.lua
M1.4 core/element.lua + element_factory.lua  data/wrapper split
M1.5 core/overlay.lua        extract _drawOverlay/_clearOverlay
M1.6 core/input.lua          extract _handleInput parsing
```

Each module is one commit; spoon must continue to work after each.

End condition: `init.lua` is now thin orchestration; atomic capabilities are external and tested.

#### M2 Scan rewrite (large, ~6-8h, highest risk)

```
M2.1 scan/tree.lua + isHintable                     + tree_spec.lua
M2.2 scan/traverser.lua (generic + clipBounds)
M2.3 scan/dispatch.lua
M2.4 scan/coordinator.lua scan() entry              -- swap-in commit
       capture fixtures: Finder, Claude Code, Safari, VS Code, System Settings
       + regression_spec.lua
M2.5 scan/traverser_table.lua (AXVisibleRows)
M2.6 scan/menubar.lua
M2.7 scan/traverser_web.lua (search predicate)
M2.8 scan/extras.lua
```

M2.4 is the swap-in commit. Manual smoke checklist must be re-run; if Claude Code stacked labels regress, M2.4 is reverted and reattempted.

End condition: smoke coverage equals or exceeds the previous implementation; regression fixtures pass.

**Stage gate before M3**: pause for staged testing. Confirm M2 stability across the smoke checklist for at least one working session before starting M3.

#### M3 Mode refactor (medium, ~6-8h)

```
M3.1 modes/controller.lua interface
M3.2 modes/hint.lua Label state               (extracted from init.lua)
M3.3 modes/hint.lua Search substate           + hint_spec.lua
M3.4 init.lua reduced to Coordinator (< 100 lines)
M3.5 modes/scroll.lua PickArea + Active       + scroll_spec.lua
M3.6 bind Cmd+Shift+S to Scroll mode
```

End condition: Hint+Search+Scroll run independently; key state transitions covered by tests.

#### M4 Polish (small, ~2-3h)

- Manual smoke across all eight target-app classes.
- Tune defaults (hint character set, scroll step sizes, modifier keys).
- Update README; remove obsolete config keys.
- Tag v0.2.0.

### 7.2 Risk and rollback

| Risk | Trigger | Rollback |
|---|---|---|
| M2.4 swap-in causes coverage regression | smoke fail | revert M2.4; fixture-ize the failing case; tweak isHintable; redo |
| `core/element` extraction breaks attribute reads | spoon startup error | revert M1.4; resplit data vs wrapper differently |
| Test runner blocks dev | runtime errors | runner is < 50 lines; rewrite rather than patch |
| New architecture diverges from current P0/P1 behavior | smoke produces new bugs | freeze the old behavior in fixture tests; new code must pass |

### 7.3 Stop conditions

- After M0 + M1 (~30%): code already modular; safe stopping point.
- After M2 (~60%): all current pain points resolved; spoon is materially better even without M3.
- After M3 (~90%): adds Scroll mode; stable shape.
- M4 is polish; never blocking.

User-confirmed staging: M2 and M3 proceed sequentially with explicit testing between them.

### 7.4 Not introduced

- luarocks / package manager.
- CI (local runner is sufficient; revisit when repo grows).
- Lua linter (no de facto standard; rely on review).
- Cross-platform abstraction (Hammerspoon-specific by design).

---

## 8. Appendices

### 8.1 Glossary

- **Hintable**: an element that gets a label and can be acted upon. Defined in `scan/tree.lua::isHintable`.
- **Actionable**: subset of hintable; the element has at least one non-decorative AX action.
- **Decorative actions**: `AXShowMenu`, `AXScrollToVisible`, `AXShowDefaultUI`, `AXShowAlternateUI`. Their presence does not count toward actionability.
- **clipBounds**: the visible rectangle inherited from a parent, used to skip elements outside the parent's visible area.
- **Sub-state**: a distinct phase within a mode, sharing the same activation context (e.g., Hint:Label and Hint:Search).

### 8.2 Reference material

- Vimac source (Homerow's open-source predecessor by the same author): https://github.com/nchudleigh/vimac
- Notable Vimac files studied: `Modes/HintModeController.swift`, `Accessibility/ElementTree.swift`, `Accessibility/HintMode/TraverseGenericElementService.swift`, `Accessibility/HintMode/TraverseSearchPredicateCompatibleWebAreaElementService.swift`, `GeometryUtils.swift`, `Accessibility/HintMode/HintModeQueryService.swift`.
- AXorcist (Swift AX wrapper for reference of typed wrapper API): https://github.com/steipete/AXorcist
