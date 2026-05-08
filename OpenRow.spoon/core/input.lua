-- OpenRow.spoon/core/input.lua — input event parsing.
-- M.character is pure (testable). M.parse wraps hs.eventtap and is only
-- exercised at runtime inside Hammerspoon.

local M = {}

local SHIFT_MAP = {
  ["1"] = "!", ["2"] = "@", ["3"] = "#", ["4"] = "$", ["5"] = "%",
  ["6"] = "^", ["7"] = "&", ["8"] = "*", ["9"] = "(", ["0"] = ")",
  ["-"] = "_", ["="] = "+", [";"] = ":", ["'"] = '"',
  [","] = "<", ["."] = ">", ["/"] = "?", ["\\"] = "|",
  ["["] = "{", ["]"] = "}", ["`"] = "~",
}

local NAMED_TO_CHAR = {
  space = " ",
}

-- Pure: map (rawKey, shift) to the character a user expects to type.
-- Returns nil for non-character keys (escape, return, delete, arrow keys, etc.).
function M.character(rawKey, shift)
  if not rawKey then return nil end
  if NAMED_TO_CHAR[rawKey] then return NAMED_TO_CHAR[rawKey] end
  if #rawKey ~= 1 then return nil end
  if shift then return SHIFT_MAP[rawKey] or rawKey:upper() end
  return rawKey
end

function M.parse(event)
  local kind = "ignore"
  if event:getType() == hs.eventtap.event.types.keyDown then kind = "keyDown" end

  local rawKey = hs.keycodes.map[event:getKeyCode()]
  local flags = event:getFlags()
  local shift = flags.shift == true

  return {
    kind = kind,
    key = rawKey,
    character = M.character(rawKey, shift),
    shift = shift,
    cmd = flags.cmd == true,
    alt = flags.alt == true,
    ctrl = flags.ctrl == true,
  }
end

return M
