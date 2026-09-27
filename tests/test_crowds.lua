vector3 = vector3 or function(x, y, z) return { x = x, y = y, z = z } end
vector4 = vector4 or function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
Config.NPCs = { { id = "informant_yellowjack" } }
Config.Voices = { male_street = "v" }
dofile("data/crowds.lua")

local n = 0
for _, npc in ipairs(Config.NPCs) do if npc.crowd then n = n + 1 end end
eq("crowd count", n, #CrowdPersonas.yellowjack)
eq("expand again adds none", ExpandCrowds(), 0)

local ids = {}
for _, npc in ipairs(Config.NPCs) do
    if npc.crowd then
        check("unique id " .. npc.id, not ids[npc.id]); ids[npc.id] = true
        eq("pattern " .. npc.id, npc.movement.pattern, "crowd")
        check("has samples " .. npc.id, #npc.voiceSamples >= 1)
        check("rumors only " .. npc.id, npc.facts.rumors and not npc.facts.basic)
        check("prompt names bar " .. npc.id, npc.systemPrompt:find("Yellow Jack", 1, true))
    end
end
local first = Config.NPCs[2]
eq("day regular has no schedule", first.schedule, nil)
local last = Config.NPCs[#Config.NPCs]
if Config.Crowds.yellowjack.hours then
    check("night regular has schedule", last.schedule ~= nil and last.schedule[1].active == true and last.schedule[2].active == false)
    eq("night hours", last.schedule[1].time[1], Config.Crowds.yellowjack.hours[1])
else
    eq("no gating: last regular has no schedule", last.schedule, nil)
end
-- gating logic itself, on a throwaway crowd
Config.Crowds.testbar = { label = "Test Bar", center = vector4(0, 0, 0, 0), radius = 5, hours = { 18, 4 }, dayCount = 1, rumors = {} }
CrowdPersonas.testbar = { { key = "a", name = "A", model = "m", samples = {} }, { key = "b", name = "B", model = "m", samples = {} } }
eq("expand test bar", ExpandCrowds(), 2)
local a, b
for _, npc in ipairs(Config.NPCs) do if npc.id == "crowd_testbar_a" then a = npc end if npc.id == "crowd_testbar_b" then b = npc end end
eq("day slot no schedule", a.schedule, nil)
check("night slot gated", b.schedule ~= nil and b.schedule[1].time[1] == 18 and b.schedule[2].active == false)
Config.Crowds.testbar = nil; CrowdPersonas.testbar = nil
-- hand-set spot is carried into the NPC entry
CrowdPersonas.testbar = { { key = "p", name = "P", model = "m", samples = {}, spot = vector4(1, 2, 3, 90.0) } }
Config.Crowds.testbar = { label = "Test Bar", center = vector4(0, 0, 0, 0), radius = 5, rumors = {} }
eq("expand pinned", ExpandCrowds(), 1)
for _, npc in ipairs(Config.NPCs) do if npc.id == "crowd_testbar_p" then eq("pinned spot x", npc.crowd.spot.x, 1); eq("pinned heading", npc.crowd.spot.w, 90.0) end end
Config.Crowds.testbar = nil; CrowdPersonas.testbar = nil
