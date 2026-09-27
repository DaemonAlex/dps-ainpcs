--[[
    SITUATION (real-people pass, 2026-09-27)
    Where the NPC is and what it is doing right now, in plain words for the model:
    the place it stands in, its current pose, indoors or out, the hour, and one thing
    on its mind today (data/onmind.lua, same pick for every player that day).
    Globals: Places (data/places.lua), OnMind (data/onmind.lua).
]]

SCENARIO_WORDS = {
    WORLD_HUMAN_AA_COFFEE = "nursing a coffee",
    WORLD_HUMAN_DRINKING = "nursing a drink",
    WORLD_HUMAN_SMOKING = "smoking",
    WORLD_HUMAN_SMOKING_POT = "smoking a joint",
    WORLD_HUMAN_LEANING = "leaning against the wall",
    WORLD_HUMAN_CLIPBOARD = "going through a clipboard",
    WORLD_HUMAN_STAND_MOBILE = "on your phone",
    WORLD_HUMAN_TOURIST_MOBILE = "looking at your phone",
    WORLD_HUMAN_HANG_OUT_STREET = "hanging around with nothing much to do",
    WORLD_HUMAN_STAND_IMPATIENT = "waiting on someone who is late",
    WORLD_HUMAN_GUARD_STAND = "standing guard",
    WORLD_HUMAN_SIT_UPS = "working out",
    WORLD_HUMAN_MUSCLE_FLEX = "flexing",
    WORLD_HUMAN_BUM_STANDING = "standing around, half asleep",
    WORLD_HUMAN_BUM_SLUMPED = "slumped against the wall",
    WORLD_HUMAN_DRUG_DEALER = "watching the street",
    WORLD_HUMAN_DRUG_DEALER_HARD = "watching the street, hard",
    WORLD_HUMAN_WELDING = "welding",
    WORLD_HUMAN_HAMMERING = "hammering at something",
    WORLD_HUMAN_JANITOR = "sweeping",
    WORLD_HUMAN_MAID_CLEAN = "cleaning",
    WORLD_HUMAN_COP_IDLES = "on duty, bored",
    WORLD_HUMAN_BINOCULARS = "looking through binoculars",
    WORLD_HUMAN_PAPARAZZI = "waiting with a camera",
    WORLD_HUMAN_MUSICIAN = "playing music",
    WORLD_HUMAN_SEAT_WALL = "sitting on the wall",
    PROP_HUMAN_SEAT_BAR = "sitting at the bar",
    PROP_HUMAN_SEAT_BENCH = "sitting on a bench",
    PROP_HUMAN_SEAT_CHAIR = "sitting down",
    PROP_HUMAN_BUM_SHOPPING_CART = "pushing a shopping cart",
    PROP_HUMAN_PARKING_METER = "feeding a parking meter",
    PROP_HUMAN_BBQ = "working a grill",
}

local INDOOR_KINDS = { "bar", "club", "shop", "store", "hospital", "office", "casino", "hotel", "restaurant", "cafe", "diner", "station", "bank", "garage", "market", "hall", "clinic", "pawn", "dealership", "gym", "inn", "motel", "church", "depot", "terminal" }

function DescribeScenario(scenario)
    if not scenario then return nil end
    return SCENARIO_WORDS[scenario] or nil
end

function TimeOfDayWords(hour)
    hour = tonumber(hour) or 12
    if hour < 5 then return "the small hours" end
    if hour < 9 then return "early morning" end
    if hour < 12 then return "morning" end
    if hour < 14 then return "midday" end
    if hour < 18 then return "afternoon" end
    if hour < 22 then return "evening" end
    return "late night"
end

function PlaceKindIsIndoors(kind)
    if type(kind) ~= "string" then return false end
    local k = kind:lower()
    for _, word in ipairs(INDOOR_KINDS) do
        if k:find(word, 1, true) then return true end
    end
    return false
end

-- The schedule slot the NPC is in right now (or nil for a stationary/wander NPC).
function NPCCurrentSlot(npc, hour)
    if not npc or not npc.movement or not npc.movement.locations then return nil end
    hour = tonumber(hour) or tonumber(os.date("%H")) or 12
    for _, slot in ipairs(npc.movement.locations) do
        local t = slot.time
        if t and slot.coords then
            local from, to = t[1], t[2]
            local inSlot = (from <= to) and (hour >= from and hour < to) or (from > to and (hour >= from or hour < to))
            if inSlot then return slot end
        end
    end
    return nil
end

-- Where the NPC stands (slot coords, else homeLocation) as a vector3.
function NPCStandsAt(npc, hour)
    if not npc then return nil end
    local slot = NPCCurrentSlot(npc, hour)
    local loc = (slot and slot.coords) or npc.homeLocation
    if not loc then return nil end
    return vector3(loc.x, loc.y, loc.z)
end

-- The place (data/places.lua) the NPC is standing in, within `radius` metres.
function PlaceNPCStandsIn(npc, radius)
    if not Places or not npc then return nil, nil end
    local here = NPCStandsAt(npc)
    if not here then return nil, nil end
    radius = radius or 45.0
    local best, bestD = nil, radius
    for _, p in ipairs(Places) do
        local d = #(vector3(p.coords.x, p.coords.y, here.z) - here)
        if d < bestD then best, bestD = p, d end
    end
    return best, best and bestD or nil
end

-- Deterministic daily pick: the same line for every player on the same day.
local function hashString(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return h
end

function OnMindToday(npc, dateKey)
    if not npc then return nil end
    if npc.onMindFixed then return npc.onMindFixed end -- crowd regulars carry their own line
    if not OnMind then return nil end
    dateKey = dateKey or os.date("%Y-%m-%d")
    local cat = npc.trustCategory or "social"
    local pool = {}
    for _, line in ipairs(OnMind.everyone or {}) do pool[#pool + 1] = line end
    local mine = OnMind[cat] or OnMind.social or {}
    for _, line in ipairs(mine) do pool[#pool + 1] = line end
    if #pool == 0 then return nil end
    local idx = (hashString((npc.id or "npc") .. dateKey) % #pool) + 1
    return pool[idx]
end

function FormatSituationBlock(placeName, placeKind, indoors, activity, hourWords, onMind)
    local out = { "=== WHERE YOU ARE AND WHAT YOU ARE DOING ===" }
    local where
    if placeName then
        where = ("You are at %s (%s), %s."):format(placeName, placeKind or "a place", indoors and "inside" or "outside")
    else
        where = "You are out on the street."
    end
    if activity then where = where .. (" You are %s."):format(activity) end
    out[#out + 1] = where
    out[#out + 1] = ("It is %s. They walked up to you here; this is where the talk happens."):format(hourWords or "daytime")
    if onMind then
        out[#out + 1] = ("On your mind today: %s Let it colour how you talk. Mention it if it fits, do not make it the whole talk."):format(onMind)
    end
    return table.concat(out, "\n") .. "\n"
end

-- Does this face have somewhere quiet to walk a player to? (slot.quiet or npc.quietSpot)
function NPCHasQuietSpot(npc)
    if not npc then return false end
    if npc.quietSpot then return true end
    local slot = NPCCurrentSlot(npc)
    return slot ~= nil and slot.quiet ~= nil
end

-----------------------------------------------------------
-- EVERYDAY BASICS: the random questions anyone gets asked ("where do I get my car fixed?").
-- Nearest real place per need, from data/places.lua, matched on words in `kind`.
-----------------------------------------------------------
BASICS = {
    { need = "get a car fixed", words = { "mechanic", "customs", "garage" } },
    { need = "buy a car", words = { "dealership", "car dealer" } },
    { need = "get patched up", words = { "hospital", "clinic" } },
    { need = "bank or cash", words = { "bank" } },
    { need = "find honest work", words = { "get hired", "job centre" } },
    { need = "licences and paperwork", words = { "city hall", "licence" } },
    { need = "clothes", words = { "clothing" } },
    { need = "a phone or electronics", words = { "electronics", "phone" } },
    { need = "medicine", words = { "pharmacy" } },
    { need = "the cops", words = { "station" } },
    { need = "a drink", words = { "bar", "roadhouse", "club" } },
    { need = "food", words = { "diner", "burger", "pizza", "restaurant", "grocery", "general store" } },
}

local function kindMatches(kind, words)
    if type(kind) ~= "string" then return false end
    local k = kind:lower()
    for _, w in ipairs(words) do
        if k:find(w, 1, true) then return true end
    end
    return false
end

local function distanceWords(d)
    if not d then return "" end
    if d < 150 then return ", right here" end
    if d < 1200 then return (", about %d metres away"):format(math.floor(d / 50 + 0.5) * 50) end
    return (", about %.1f km away, a drive"):format(d / 1000)
end

function PickBasics(places, here)
    local out = {}
    for _, b in ipairs(BASICS) do
        local best, bestD = nil, nil
        for _, p in ipairs(places or {}) do
            if kindMatches(p.kind, b.words) then
                local d = here and #(vector3(p.coords.x, p.coords.y, here.z) - here) or nil
                if not best or (d and bestD and d < bestD) or (d and not bestD) then best, bestD = p, d end
            end
        end
        if best then out[#out + 1] = { need = b.need, place = best, d = bestD } end
    end
    return out
end

function FormatBasicsBlock(picks)
    if not picks or #picks == 0 then return "" end
    local out = { "=== EVERYDAY QUESTIONS ANYONE HERE CAN ANSWER ===" }
    for _, pk in ipairs(picks) do
        out[#out + 1] = ("- If they need to %s: %s (%s%s)."):format(pk.need, pk.place.name, pk.place.kind, distanceWords(pk.d))
    end
    out[#out + 1] = "Answer these plainly, the way anyone who lives here would, in your own voice. They are common knowledge, not secrets."
    return table.concat(out, "\n") .. "\n"
end

function BuildBasicsContext(npc)
    if not Places or #Places == 0 then return "" end
    return FormatBasicsBlock(PickBasics(Places, NPCStandsAt(npc)))
end

function BuildSituationContext(npc)
    if not npc then return "" end
    local hour = tonumber(os.date("%H")) or 12
    local slot = NPCCurrentSlot(npc, hour)
    local scenario = (slot and slot.scenario) or npc.scenario
    local place, _ = PlaceNPCStandsIn(npc)
    local indoors
    if slot and slot.indoors ~= nil then indoors = slot.indoors
    elseif place then indoors = PlaceKindIsIndoors(place.kind)
    else indoors = false end
    return FormatSituationBlock(place and place.name, place and place.kind, indoors, DescribeScenario(scenario), TimeOfDayWords(hour), OnMindToday(npc))
end
