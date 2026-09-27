--[[
    FACTS (mold engine slice 2)
    Written truths per trust tier on each NPC (npc.facts = { rumors, basic, detailed, secret }).
    Only the tiers this character has unlocked reach the prompt.
]]

local TIERS = { "rumors", "basic", "detailed", "secret" }
local LEVEL_TO_TIER = { ["Stranger"] = 1, ["Acquaintance"] = 2, ["Trusted"] = 3, ["Inner Circle"] = 4 }

function TierIndexForLevel(levelName)
    return LEVEL_TO_TIER[levelName] or 1
end

function FormatFactsBlock(facts, tierIndex)
    if type(facts) ~= "table" then return "" end
    tierIndex = tierIndex or 1
    local out = { "=== WHAT YOU KNOW AND MAY SAY ===" }
    local lockedAbove = false
    for i, tier in ipairs(TIERS) do
        local list = facts[tier]
        if type(list) == "table" and #list > 0 then
            if i <= tierIndex then
                for _, line in ipairs(list) do out[#out + 1] = tostring(line) end
            else
                lockedAbove = true
            end
        end
    end
    if #out == 1 and not lockedAbove then return "" end
    if lockedAbove then
        out[#out + 1] = "There is more you know that you are not telling them yet. Deflect, change the subject, or lie the way you would. Do not hint at what it is."
    end
    return table.concat(out, "\n") .. "\n"
end

function BuildFactsContext(npc, trustLevelName)
    if not npc or not npc.facts then return "" end
    return FormatFactsBlock(npc.facts, TierIndexForLevel(trustLevelName))
end
