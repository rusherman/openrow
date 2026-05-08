# OpenRow Hammerspoon Prototype

OpenRow is a small Hammerspoon prototype for keyboard-first clicking on macOS. It scans the frontmost app through the macOS Accessibility API, draws short labels over clickable UI elements, and clicks the selected element from the keyboard.

This is a validation prototype, not a polished app. The goal is to test whether the Homerow-style interaction works well enough before building a native Swift version.

## Requirements

- macOS
- [Hammerspoon](https://www.hammerspoon.org/)
- Accessibility permission granted to Hammerspoon

## Install

```bash
bash scripts/install.sh
```

Add this to `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("OpenRow"):bindHotkeys()
```

Reload Hammerspoon config.

## Usage

- Press `Cmd+Shift+Space` to activate OpenRow.
- Type the yellow label shown over a target to click it.
- When many targets are visible, labels are equal length to avoid prefix conflicts such as `a` versus `aa`.
- Press `/` to enter search mode, then type text to filter targets by title, description, value, help text, or role. Search supports spaces and shifted symbols.
- Press `Return` to click the first visible target.
- Press `Delete` to remove the last label/search character.
- Press `Esc` to exit.

## Custom Hotkey

```lua
hs.loadSpoon("OpenRow"):bindHotkeys({
  activate = { { "ctrl", "alt" }, "space" },
})
```

## Current Limitations

- Scans the frontmost app's focused window tree, including common visible/navigation child collections.
- Some apps expose poor or incomplete Accessibility metadata.
- Browser/Electron pages with huge Accessibility trees may scan slowly.
- Overlay layout is intentionally simple.
- No scroll mode yet.

Clicking uses a real mouse click at the resolved target point. Some Accessibility roles report a successful `AXPress` without actually activating the visual item, so OpenRow does not rely on `AXPress`.

## Target Detection Notes

OpenRow marks an element as targetable when it matches one of these signals:

- Known control roles such as buttons, links, text fields, menu items, sliders, and pop-up buttons.
- Accessibility actions after ignoring decorative actions such as `AXShowMenu` and `AXScrollToVisible`.
- Fallback list-like containers such as `AXRow`, `AXOutlineRow`, `AXCell`, `AXGroup`, and meaningful `AXStaticText` only when they do not already contain a targetable child.

If an app still misses list items, inspect which actions, roles, and child attributes that app exposes through Accessibility.

## Debugging Clicks

Enable click-path logging from your Hammerspoon config:

```lua
local openrow = hs.loadSpoon("OpenRow")
openrow.config.debug.action = true
openrow:init()
openrow:bindHotkeys()
```

Then open the Hammerspoon Console and retry the failing target. The log prints the selected label, role, target kind, frame, and mouse click point.

Some Accessibility roles can report a successful `AXPress` without actually activating the visual item. OpenRow avoids that false-positive path and clicks the selected target with the mouse.

OpenRow clicks the center of each target frame, except links, which use a small lower-left inset. Tune the link inset if a specific app exposes shifted link frames:

```lua
local openrow = hs.loadSpoon("OpenRow")
openrow.config.linkClickInset = 5
openrow:bindHotkeys()
```

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

- `core/` — atomic capabilities:
  - `scanner.lua` — pure target classification, dedup, ranking, search-text helpers
  - `element_factory.lua` — `hs.axuielement` safe-call wrappers (the only impure file)
  - `geometry.lua` — frame math
  - `overlay.lua` — `hs.canvas` wrapper
  - `input.lua` — keyboard event parsing (pure `character` mapping is unit tested)
- `lib/` — utilities: `alphabet.lua` (hint label generation), `log.lua` (channelled debug)

## Next Validation Steps

Test in Finder, Safari/Chrome, VS Code, Terminal, System Settings, and Electron apps. Record which apps expose useful `AXFrame`, `AXTitle`, `AXRole`, actions, and mouse-click behavior before moving the design into a native Swift app.
