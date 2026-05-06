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
