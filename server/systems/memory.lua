--[[
    MEMORY (mold engine slice 1)
    Reads the top memories about a character into the prompt and writes engine memories.
    Globals used from server/main.lua: GetNPCMemories, AddNPCMemory.
]]

function DescribeDaysAgo(days)
    if not days or days < 1 then return "earlier today" end
    if days < 2 then return "yesterday" end
    if days > 30 then return "over a month ago" end
    return ("%d days ago"):format(math.floor(days))
end

local TAGS = { warning = " (you did not like that)", negative = " (it still bothers you)" }

function FormatMemoryBlock(rows, talkCount, lastSeenDays)
    rows = rows or {}
    talkCount = tonumber(talkCount) or 0
    if #rows == 0 and talkCount == 0 then return "" end
    local maxLines = (Config.Memory and Config.Memory.maxLines) or 5
    local out = { "=== WHAT YOU REMEMBER ABOUT THEM ===" }
    if talkCount == 1 then
        out[#out + 1] = "You have talked once before."
    elseif talkCount > 1 then
        out[#out + 1] = ("You have talked %d times. Last time was %s."):format(talkCount, DescribeDaysAgo(lastSeenDays))
    end
    for i = 1, math.min(#rows, maxLines) do
        local r = rows[i]
        out[#out + 1] = "- " .. tostring(r.memory_text) .. (TAGS[r.memory_type] or "")
    end
    out[#out + 1] = "Use these the way a person would: bring one up if it fits, never read them out."
    return table.concat(out, "\n") .. "\n"
end

-- DB-backed: talk count from ai_npc_trust, last seen from the newest memory.
function BuildMemoryContext(npcId, citizenid)
    if not citizenid or not npcId then return "" end
    local maxLines = (Config.Memory and Config.Memory.maxLines) or 5
    local rows = GetNPCMemories(citizenid, npcId, maxLines)
    local count = MySQL.scalar.await([[
        SELECT conversation_count FROM ai_npc_trust WHERE citizenid = ? AND npc_id = ?
    ]], { citizenid, npcId }) or 0
    local lastDays = MySQL.scalar.await([[
        SELECT TIMESTAMPDIFF(HOUR, MAX(created_at), NOW()) / 24 FROM ai_npc_memories
        WHERE citizenid = ? AND npc_id = ?
    ]], { citizenid, npcId })
    return FormatMemoryBlock(rows, count, lastDays and tonumber(lastDays) or nil)
end

-- Engine memory: importance 8, never expires. memoryType: positive | negative | neutral | warning
function RememberEngine(citizenid, npcId, text, memoryType)
    if not citizenid or not npcId or not text then return end
    AddNPCMemory(citizenid, npcId, memoryType or 'neutral', text, 8, nil)
end
