-- OpenRow.spoon/core/element.lua — pure data model for an AX element snapshot.

local Element = {}

function Element.new(fields)
  fields = fields or {}
  return {
    rawId = fields.rawId,
    role = fields.role,
    frame = fields.frame,
    actions = fields.actions or {},
    title = fields.title,
    description = fields.description,
    value = fields.value,
    help = fields.help,
    enabled = fields.enabled,
  }
end

function Element.rawId(element) return element.rawId end
function Element.role(element) return element.role end
function Element.frame(element) return element.frame end
function Element.actions(element) return element.actions end
function Element.title(element) return element.title end
function Element.description(element) return element.description end
function Element.value(element) return element.value end
function Element.help(element) return element.help end
function Element.enabled(element) return element.enabled end

function Element.searchText(element)
  local text = {
    element.role and tostring(element.role) or "",
    element.title and tostring(element.title) or "",
    element.description and tostring(element.description) or "",
    element.value and tostring(element.value) or "",
    element.help and tostring(element.help) or "",
  }
  return table.concat(text, " "):lower()
end

return Element
