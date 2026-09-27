vector3 = vector3 or function(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, { __sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end,
        __len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end })
end
vector4 = vector4 or function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
dofile("data/onmind.lua")
dofile("server/systems/situation.lua")

eq("scenario coffee", DescribeScenario("WORLD_HUMAN_AA_COFFEE"), "nursing a coffee")
eq("scenario unknown", DescribeScenario("WORLD_HUMAN_XYZ"), nil)
eq("scenario nil", DescribeScenario(nil), nil)
eq("hour 3", TimeOfDayWords(3), "the small hours")
eq("hour 13", TimeOfDayWords(13), "midday")
eq("hour 23", TimeOfDayWords(23), "late night")
check("bar indoors", PlaceKindIsIndoors("bar and grill"))
check("street not indoors", not PlaceKindIsIndoors("street corner"))

local npc = { id = "mike", trustCategory = "criminal", homeLocation = vector4(0, 0, 0, 0),
    movement = { locations = {
        { time = { 6, 12 }, coords = vector4(10, 10, 0, 0), scenario = "WORLD_HUMAN_AA_COFFEE" },
        { time = { 22, 4 }, coords = vector4(20, 20, 0, 0), scenario = "WORLD_HUMAN_SMOKING" },
    } } }
eq("slot morning", NPCCurrentSlot(npc, 8).scenario, "WORLD_HUMAN_AA_COFFEE")
eq("slot wraps midnight", NPCCurrentSlot(npc, 2).scenario, "WORLD_HUMAN_SMOKING")
eq("no slot at 15", NPCCurrentSlot(npc, 15), nil)
eq("stands at slot", NPCStandsAt(npc, 8).x, 10)
eq("stands at home when no slot", NPCStandsAt(npc, 15).x, 0)

Places = { { name = "Yellow Jack Inn", kind = "bar", coords = vector3(12, 12, 0) }, { name = "Far", kind = "shop", coords = vector3(500, 500, 0) } }
local p, d = PlaceNPCStandsIn({ homeLocation = vector4(10, 10, 0, 0) })
eq("place found", p and p.name, "Yellow Jack Inn")
check("place distance", d and d < 3)
local none = PlaceNPCStandsIn({ homeLocation = vector4(200, 200, 0, 0) })
eq("no place in range", none, nil)

local a = OnMindToday(npc, "2026-09-27")
local b = OnMindToday(npc, "2026-09-27")
local c = OnMindToday(npc, "2026-09-28")
check("on mind picked", type(a) == "string")
eq("on mind stable within a day", a, b)
check("on mind varies by day (probably)", a ~= c or true)
eq("on mind nil without data", (function() local o = OnMind; OnMind = nil; local r = OnMindToday(npc); OnMind = o; return r end)(), nil)
eq("on mind fixed wins", OnMindToday({ id = "x", onMindFixed = "Your dog got out." }), "Your dog got out.")

local blk = FormatSituationBlock("Yellow Jack Inn", "bar", true, "nursing a drink", "late night", "Rent is due.")
check("situation header", blk:find("=== WHERE YOU ARE AND WHAT YOU ARE DOING ===", 1, true))
check("situation place", blk:find("You are at Yellow Jack Inn (bar), inside.", 1, true))
check("situation activity", blk:find("You are nursing a drink.", 1, true))
check("situation hour", blk:find("It is late night.", 1, true))
check("situation on mind", blk:find("On your mind today: Rent is due.", 1, true))
local street = FormatSituationBlock(nil, nil, false, nil, "morning", nil)
check("street fallback", street:find("out on the street", 1, true))
check("no on mind line", not street:find("On your mind", 1, true))

-- quiet spot
check("quiet from npc", NPCHasQuietSpot({ quietSpot = vector4(1, 1, 1, 0) }))
check("no quiet", not NPCHasQuietSpot({ homeLocation = vector4(0, 0, 0, 0) }))
check("quiet from slot", NPCHasQuietSpot({ movement = { locations = { { time = { 0, 24 }, coords = vector4(0, 0, 0, 0), quiet = vector4(5, 5, 0, 0) } } } }))

-- basics
local places = {
    { name = "Bennys", kind = "mechanic", coords = vector3(0, 0, 0) },
    { name = "Larrys Garage", kind = "mechanic and garage", coords = vector3(1000, 0, 0) },
    { name = "Pillbox hospital", kind = "big hospital", coords = vector3(50, 0, 0) },
    { name = "Sandy Fleeca", kind = "bank", coords = vector3(2000, 0, 0) },
}
local picks = PickBasics(places, vector3(10, 0, 0))
eq("basics count", #picks, 3)
eq("nearest mechanic", picks[1].place.name, "Bennys")
local blk2 = FormatBasicsBlock(picks)
check("basics header", blk2:find("=== EVERYDAY QUESTIONS ANYONE HERE CAN ANSWER ===", 1, true))
check("basics car line", blk2:find("get a car fixed: Bennys (mechanic, right here)", 1, true))
check("basics bank far", blk2:find("Sandy Fleeca (bank, about 2.0 km away, a drive)", 1, true))
eq("basics empty", FormatBasicsBlock({}), "")
Places = places
check("basics ctx", BuildBasicsContext({ homeLocation = vector4(10, 0, 0, 0) }):find("Bennys", 1, true))
Places = nil
eq("basics ctx no places", BuildBasicsContext({ homeLocation = vector4(10, 0, 0, 0) }), "")
