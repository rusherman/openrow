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
