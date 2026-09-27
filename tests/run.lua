-- Runs every tests/test_*.lua under lua5.4. Exit code 1 on any failure.
package.path = "./?.lua;" .. package.path
dofile("tests/stubs.lua")
local p = io.popen('ls tests/test_*.lua')
for f in p:lines() do print("== " .. f); dofile(f) end
p:close()
print(("%d passed, %d failed"):format(TESTS.pass, TESTS.fail))
os.exit(TESTS.fail == 0 and 0 or 1)
