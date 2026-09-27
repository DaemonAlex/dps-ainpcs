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
check("night regular has schedule", last.schedule ~= nil and last.schedule[1].active == true and last.schedule[2].active == false)
eq("night hours", last.schedule[1].time[1], 18)
