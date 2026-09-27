dofile("server/systems/memory.lua")

eq("days ago today", DescribeDaysAgo(0), "earlier today")
eq("days ago 1", DescribeDaysAgo(1), "yesterday")
eq("days ago 5", DescribeDaysAgo(5), "5 days ago")
eq("days ago 40", DescribeDaysAgo(40), "over a month ago")

eq("empty block", FormatMemoryBlock({}, 0, nil), "")

local rows = {
    { memory_text = "Brought the five joints you asked for.", memory_type = "positive", importance = 8 },
    { memory_text = "Asked about Walter, too eager.", memory_type = "warning", importance = 5 },
}
local block = FormatMemoryBlock(rows, 3, 2)
check("has header", block:find("=== WHAT YOU REMEMBER ABOUT THEM ===", 1, true))
check("has count", block:find("talked 3 times", 1, true))
check("has last seen", block:find("2 days ago", 1, true))
check("has memory 1", block:find("Brought the five joints", 1, true))
check("warning tagged", block:find("(you did not like that)", 1, true))

local many = {}
for i = 1, 9 do many[i] = { memory_text = "m" .. i, memory_type = "neutral", importance = 5 } end
local capped = FormatMemoryBlock(many, 9, 0)
local n = 0; for _ in capped:gmatch("\n%- ") do n = n + 1 end
eq("capped to 5", n, 5)

local first = FormatMemoryBlock({}, 1, 0)
check("first talk mentions once", first:find("talked once", 1, true))

-- engine memories go through AddNPCMemory with importance 8 and no expiry
MySQL.__writes = {}
GetNPCById = function(id) return { id = id, name = (id == "a" and "Alice" or "Bob") } end
AddNPCMemory = function(cid, npc, mtype, text, imp, exp) MySQL.__writes[#MySQL.__writes + 1] = { npc = npc, text = text, imp = imp, exp = exp, mtype = mtype } end
RememberEngine("cid1", "a", "hello", "positive")
eq("engine importance 8", MySQL.__writes[1].imp, 8)
eq("engine no expiry", MySQL.__writes[1].exp, nil)
eq("engine type", MySQL.__writes[1].mtype, "positive")
RememberEngine(nil, "a", "hello")
eq("engine ignores nil citizen", #MySQL.__writes, 1)

-- BuildMemoryContext: no rows, no trust row -> empty
GetNPCMemories = function() return {} end
MySQL.__scalars = {}
eq("context empty for stranger", BuildMemoryContext("a", "cid1"), "")
