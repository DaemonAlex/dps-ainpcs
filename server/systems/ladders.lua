--[[
    LADDERS engine (mold engine slice 3)
    Data in data/ladders.lua (Config.Ladders[ladder][region].rungs). State per character in
    ai_npc_ladders. AdvanceLadder runs inside GrantQuestReward; BuildLadderContext feeds the prompt.
    Globals used: CreateReferral, RememberEngine, GetNPCById (server/main.lua), exports.ox_inventory.
]]

function FindRungForQuest(npcId, questId)
    for lk, ladder in pairs(Config.Ladders or {}) do
        for rk, region in pairs(ladder) do
            if type(region) == "table" and region.rungs then
                for i, rung in ipairs(region.rungs) do
                    if rung.npc == npcId then
                        for _, q in ipairs(rung.quests or {}) do
                            if q == questId then return lk, rk, i, rung end
                        end
                    end
                end
            end
        end
    end
    return nil
end

function RungIsComplete(citizenid, npcId, rung)
    local ids = rung.quests or {}
    if #ids == 0 then return true end
    local marks = {}
    for i = 1, #ids do marks[i] = "?" end
    local params = { citizenid, npcId }
    for _, id in ipairs(ids) do params[#params + 1] = id end
    local n = MySQL.scalar.await(([[
        SELECT COUNT(DISTINCT quest_id) FROM ai_npc_quests
        WHERE citizenid = ? AND npc_id = ? AND status = 'completed' AND quest_id IN (%s)
    ]]):format(table.concat(marks, ",")), params) or 0
    return (tonumber(n) or 0) >= #ids
end

function GetLadderRow(citizenid, ladder, region)
    local rows = MySQL.query.await([[
        SELECT ladder, region, rung, status FROM ai_npc_ladders
        WHERE citizenid = ? AND ladder = ? AND region = ?
    ]], { citizenid, ladder, region })
    return rows and rows[1] or nil
end

-- A rung payoff. DPS 2026-10-31 (Damon: "nothing here needs the engine touched, apart from
-- teaching payoffs to pay in something other than items"). Four kinds now, and a payoff may
-- carry several at once - items for the tools, money for the earner, standing for the status
-- ("the payoff is increased reputation that escalates your priority and status among the
-- NPCs"), and a word that opens a door. Standing goes through the existing faction trust
-- system rather than a parallel one, so it reaches every face in that faction.
local function runPayoff(src, payoff, citizenid, npcId)
    if not payoff then return end
    local kinds = payoff.kind and { payoff } or payoff   -- one payoff, or a list of them
    if payoff.kind then kinds = { payoff } end

    for _, p in ipairs(kinds) do
        if type(p) ~= "table" or not p.kind then goto continue end

        if p.kind == "items" then
            for _, it in ipairs(p.items or {}) do
                pcall(function() exports.ox_inventory:AddItem(src, it.name, it.amount or 1) end)
            end

        elseif p.kind == "money" then
            local amount = tonumber(p.amount) or 0
            if amount > 0 then
                local Player = exports.qbx_core:GetPlayer(src)
                if Player then
                    Player.Functions.AddMoney(p.account or 'cash', amount, 'ai-npc-ladder:' .. tostring(npcId))
                end
            end

        elseif p.kind == "standing" then
            -- Faction reputation. Reaches every NPC in the faction, which is the point:
            -- finish the street ladder and the whole street knows you, not just the last face.
            for faction, delta in pairs(p.factions or {}) do
                local d = tonumber(delta) or 0
                if d ~= 0 then
                    pcall(function()
                        exports['dps-ainpcs']:AddFactionTrust(citizenid, faction, d, 'ladder:' .. tostring(npcId))
                    end)
                end
            end

        elseif p.kind == "word" then
            -- No goods, no money: the face simply vouches for the player from here on. The line
            -- is written into the NPC's memory so it colours every later conversation.
            if RememberEngine and p.line then
                RememberEngine(citizenid, npcId, p.line, 'positive')
            end

        elseif Config.Debug and Config.Debug.enabled then
            print(("[AI NPCs] payoff kind %s not wired yet"):format(tostring(p.kind)))
        end

        ::continue::
    end
end

-- Returns nil (nothing to do), "advanced" or "done".
function AdvanceLadder(src, citizenid, npcId, questId)
    local lk, rk, idx, rung = FindRungForQuest(npcId, questId)
    if not lk then return nil end
    if not RungIsComplete(citizenid, npcId, rung) then return nil end
    local row = GetLadderRow(citizenid, lk, rk)
    -- done and burned ladders never move again (no payoff farming); rungs go in order, no skipping
    if row and row.status ~= "active" then return nil end
    if ((row and tonumber(row.rung)) or 1) ~= idx then return nil end
    local total = #Config.Ladders[lk][rk].rungs
    local owner = GetNPCById(npcId)
    local ownerName = owner and owner.name or npcId

    if rung.breadcrumb and rung.breadcrumb.npc then
        CreateReferral(citizenid, npcId, rung.breadcrumb.npc, 'ladder')
        local nextNpc = GetNPCById(rung.breadcrumb.npc)
        RememberEngine(citizenid, npcId, ("You put in a word for them with %s."):format(nextNpc and nextNpc.name or rung.breadcrumb.npc), 'positive')
        RememberEngine(citizenid, rung.breadcrumb.npc, ("%s vouched for them."):format(ownerName), 'neutral')
        if rung.breadcrumb.line then
            TriggerClientEvent('ox_lib:notify', src, { title = ownerName, description = rung.breadcrumb.line, type = 'inform', duration = 10000 })
        end
    end

    local status = (idx >= total) and "done" or "active"
    MySQL.insert.await([[
        INSERT INTO ai_npc_ladders (citizenid, ladder, region, rung, status) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE rung = VALUES(rung), status = VALUES(status)
    ]], { citizenid, lk, rk, math.min(idx + 1, total), status })

    if status == "done" then
        runPayoff(src, rung.payoff, citizenid, npcId)
        RememberEngine(citizenid, npcId, "They went all the way with you. You owe them nothing now, and they know it.", 'positive')
        return "done"
    end
    return "advanced"
end

-- One block for the face that owns this character's current rung.
function BuildLadderContext(npc, citizenid)
    if not npc or not citizenid then return "" end
    for lk, ladder in pairs(Config.Ladders or {}) do
        for rk, region in pairs(ladder) do
            if type(region) == "table" and region.rungs then
                local row = GetLadderRow(citizenid, lk, rk)
                local cur = row and tonumber(row.rung) or 1
                local status = row and row.status or "active"
                local rung = region.rungs[cur]
                if rung and rung.npc == npc.id and status == "active" then
                    local line = ("=== WHERE THEY ARE WITH YOU ===\nThey are on step %d of %d with you (%s)."):format(cur, #region.rungs, region.label or lk)
                    if rung.breadcrumb and rung.breadcrumb.line then
                        line = line .. (" When they have done your work, the only new thing you give them is this: %s Until then, deflect."):format(rung.breadcrumb.line)
                    end
                    return line .. "\n"
                end
            end
        end
    end
    return ""
end
