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
