-- Open targeting-smoke.html in Chrome, then run this from Hammerspoon Console.
local source = debug.getinfo(1, 'S').source:sub(2)
local root = assert(source:match('^(.*)/tests/manual/[^/]+$'), 'Use the absolute path to this script') .. '/'
package.path = root .. 'OpenRow.spoon/?.lua;' .. package.path
for _, name in ipairs({ 'core.geometry', 'core.element_factory', 'core.scanner' }) do package.loaded[name] = nil end
local factory = require('core.element_factory')
local scanner = require('core.scanner')
if _openrowQA and _openrowQA.web then _openrowQA.web:delete() end
_openrowQA = { app = dofile(root .. 'OpenRow.spoon/init.lua') }
local qa = _openrowQA
function qa.scan()
  local chrome = assert(hs.application.find('com.google.Chrome'), 'Open the fixture in Chrome first')
  local application = hs.axuielement.applicationElement(chrome)
  factory.safeSetAttribute(application, 'AXEnhancedUserInterface', true)
  local window = assert(factory.safeAttribute(application, 'AXFocusedWindow'))
  assert((factory.safeAttribute(window, 'AXTitle') or ''):find('OpenRow Targeting QA', 1, true), 'Focus the QA browser tab')
  local frames = hs.fnutils.imap(hs.screen.allScreens(), function(screen) return screen:fullFrame() end)
  local targets = {}
  qa.app:_scanElement(window, targets, {}, 0, frames, scanner.maxScreenArea(frames))
  qa.targets = scanner.dedupeTargets(targets)
  for _, t in ipairs(qa.targets) do
    t.name = scanner.computeSearchText({role=t.role,title=factory.safeAttribute(t.element,'AXTitle'),
      description=factory.safeAttribute(t.element,'AXDescription'),value=factory.safeAttribute(t.element,'AXValue')})
    if t.name:find('qa', 1, true) then print('QA TARGET', t.role, t.name, hs.inspect(t.frame)) end
  end
  print('QA COUNT', #qa.targets)
end
function qa.click(name)
  for _, t in ipairs(qa.targets or {}) do
    if t.name:find(name:lower(), 1, true) then print('QA CLICK',name,qa.app:_clickTarget(t)); return end
  end
  error('QA target missing: ' .. name)
end
print('QA READY: _openrowQA.scan(), then click a target with the browser window frontmost')
