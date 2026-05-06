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
