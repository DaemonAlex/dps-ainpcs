--[[
    QUEST ENGINE (H3)  — server-authoritative

    quests.lua is data-only: ~820 lines of Config.Quests with reward/objectives/
    factionTrust that NOTHING consumed. The old OfferQuest/AcceptQuest/CompleteQuest
    in server/main.lua were generic DB stubs that only granted trust.

    This file wires a real lifecycle on top of the existing ai_npc_quests table:
        offer -> accept (persist objectives) -> track/report -> complete + reward

    EVERYTHING is validated server-side. The client never supplies rewards, never
    decides completion, and objective "report" calls are re-validated here
    (proximity / item possession / elapsed time) before an objective is accepted.

    Globals used from server/main.lua (same resource, main.lua loads first):
        GetNPCById, IsPlayerNearNPC, IsPlayerInQuestRange, AddPlayerTrust,
        CreateReferral, HasReferral
    From quests.lua (shared_script, loaded before server): GetQuestById, Config.Quests
]]

-----------------------------------------------------------
-- OBJECTIVE TYPE SUPPORT MATRIX
-----------------------------------------------------------
-- FULLY implemented (hard server validation):
--   goto / return-to-coords : player ped within radius of coords
--   deliver                 : possess item(s) + (optional) proximity, consumes item
--   pickup / collect / retrieve : possess required item (ox_inventory)
--   wait                    : real elapsed time >= duration
-- PARTIALLY implemented (can't fully simulate the world action, so we require the
-- player to physically be AT the objective coords, or next to the quest-giver, to
-- report it — this blocks trivial remote spoofing but does not verify the kill/
-- intimidation/theft actually happened):
--   kill / intimidate / beat / find / find_npc / find_target / stay_in_area /
--   report_police / talk_to / interact / take / everything else
-----------------------------------------------------------

-- Map rich quest.type -> ai_npc_quests.quest_type ENUM (fallback 'other').
local QUEST_TYPE_ENUM = {
    delivery = 'item_delivery', item_delivery = 'item_delivery',
    task = 'task', payment = 'payment', kill = 'kill',
    frame = 'frame', escort = 'escort',
}
local function dbQuestType(t)
    return QUEST_TYPE_ENUM[t] or 'other'
end

-- Which Config.Quests bucket does this NPC draw from? Prefer an explicit
-- questSet, else the NPC's role. Returns nil if the NPC has no quest set.
local function GetNPCQuestSet(npc)
    if not npc then return nil end
    local key = npc.questSet or npc.role
    if key and Config.Quests[key] then return key end
    return nil
end

-----------------------------------------------------------
-- HELPERS
-----------------------------------------------------------
local function getCitizenId(src)
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return nil, nil end
    return Player.PlayerData.citizenid, Player
end

local function playerNearCoords(src, coords, radius)
    if not coords then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pc = GetEntityCoords(ped)
    local d = #(vector3(pc.x, pc.y, pc.z) - vector3(coords.x, coords.y, coords.z))
    return d <= (radius or 5.0)
end

local function playerHasItem(src, itemName, amount)
    if not itemName then return false end
    local ok, count = pcall(function()
        return exports.ox_inventory:Search(src, 'count', itemName)
    end)
    return ok and (count or 0) >= (amount or 1)
end

-- Build the normalized, server-owned progress list from a quest definition.
local function buildProgress(quest)
    local progress = {}
    for i, obj in ipairs(quest.objectives or {}) do
        progress[i] = {
            idx = i,
            type = obj.type,
            done = false,
            coords = obj.coords,       -- vector3 or nil
            radius = obj.radius or 5.0,
            item = obj.item,           -- string or nil
            amount = obj.amount or obj.count or 1,
            duration = obj.duration,   -- seconds (wait)
            location = obj.location,   -- named zone (informational only)
        }
    end
    return progress
end

-- Player already has an active row for this quest?
local function getQuestRow(citizenid, npcId, questId)
    return MySQL.single.await([[
        SELECT * FROM ai_npc_quests
        WHERE citizenid = ? AND npc_id = ? AND quest_id = ?
    ]], {citizenid, npcId, questId})
end

-----------------------------------------------------------
-- OFFER: what can this NPC offer this player right now?
-----------------------------------------------------------
local function getOfferableQuests(src, npcId)
    local citizenid = getCitizenId(src)
    if not citizenid then return {} end

    local npc = GetNPCById(npcId)
    local setKey = GetNPCQuestSet(npc)
    if not setKey then return {} end

    -- Player trust with this NPC (used for trust gates).
    local trust = GetPlayerTrust(citizenid, npc.trustCategory, npcId)

    -- Completed quests for this player (for oneTime gating).
    local completedRows = MySQL.query.await([[
        SELECT quest_id FROM ai_npc_quests WHERE citizenid = ? AND status = 'completed'
    ]], {citizenid}) or {}
    local completed = {}
    for _, r in ipairs(completedRows) do completed[r.quest_id] = true end

    local offerable = {}
    for _, quest in ipairs(Config.Quests[setKey]) do
        local ok = true

        if quest.trustRequired and trust < quest.trustRequired then ok = false end
        if ok and quest.referralRequired and not HasReferral(citizenid, npcId) then
            -- referralRequired means another NPC must have vouched for the player to THIS npc
            ok = false
        end
        if ok and quest.oneTime and completed[quest.id] then ok = false end

        -- Don't re-offer a quest that's currently active.
        if ok then
            local row = getQuestRow(citizenid, npcId, quest.id)
            if row and (row.status == 'accepted' or row.status == 'in_progress') then
                ok = false
            end
        end

        if ok then
            offerable[#offerable + 1] = {
                id = quest.id,
                title = quest.title,
                description = quest.description,
                type = quest.type,
                reward = quest.reward,
            }
        end
    end
    return offerable
end

RegisterNetEvent('ai-npcs:server:requestQuests', function(npcId)
    local src = source
    if not IsPlayerNearNPC(src, npcId) then return end

    local quests = getOfferableQuests(src, npcId)
    TriggerClientEvent('ai-npcs:client:showQuests', src, npcId, quests)
end)

-----------------------------------------------------------
-- ACCEPT
-----------------------------------------------------------
RegisterNetEvent('ai-npcs:server:acceptQuest', function(npcId, questId)
    local src = source
    if not IsPlayerNearNPC(src, npcId) then return end

    local citizenid, Player = getCitizenId(src)
    if not citizenid then return end

    local npc = GetNPCById(npcId)
    local setKey = GetNPCQuestSet(npc)
    if not setKey then return end

    -- Quest must belong to THIS NPC's set (prevents accepting arbitrary quest ids).
    local quest
    for _, q in ipairs(Config.Quests[setKey]) do
        if q.id == questId then quest = q break end
    end
    if not quest then return end

    -- Re-validate gates server-side.
    local trust = GetPlayerTrust(citizenid, npc.trustCategory, npcId)
    if quest.trustRequired and trust < quest.trustRequired then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Not Yet', description = 'They don\'t trust you enough for that.', type = 'error' })
        return
    end
    if quest.referralRequired and not HasReferral(citizenid, npcId) then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Not Yet', description = 'You need an introduction first.', type = 'error' })
        return
    end

    local existing = getQuestRow(citizenid, npcId, questId)
    if existing then
        if existing.status == 'accepted' or existing.status == 'in_progress' then
            TriggerClientEvent('ox_lib:notify', src, { title = 'Already On It', description = 'You already took this job.', type = 'error' })
            return
        end
        if existing.status == 'completed' and quest.oneTime then
            TriggerClientEvent('ox_lib:notify', src, { title = 'Done', description = 'You already did that one.', type = 'error' })
            return
        end
    end

    local questData = {
        progress = buildProgress(quest),
        acceptedAt = os.time(),
    }

    MySQL.insert.await([[
        INSERT INTO ai_npc_quests (citizenid, npc_id, quest_id, quest_type, status, quest_data, reward_claimed, offered_at)
        VALUES (?, ?, ?, ?, 'accepted', ?, FALSE, CURRENT_TIMESTAMP)
        ON DUPLICATE KEY UPDATE
            status = 'accepted', quest_type = VALUES(quest_type),
            quest_data = VALUES(quest_data), reward_claimed = FALSE,
            completed_at = NULL, offered_at = CURRENT_TIMESTAMP
    ]], {citizenid, npcId, questId, dbQuestType(quest.type), json.encode(questData)})

    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Job Accepted',
        description = quest.title,
        type = 'success',
        duration = 8000
    })
    TriggerClientEvent('ai-npcs:client:questAccepted', src, {
        questId = questId, npcId = npcId, title = quest.title,
        description = quest.description
    })
end)

-----------------------------------------------------------
-- REPORT PROGRESS (validates the NEXT incomplete objective)
-----------------------------------------------------------
local function firstIncomplete(progress)
    for i = 1, #progress do
        if not progress[i].done then return i end
    end
    return nil
end

-- Validate a single objective server-side. Returns ok, consumedItem(bool).
local function validateObjective(src, obj)
    local t = obj.type

    if t == 'goto' or t == 'return' then
        -- Requires being at the coords (if coords are defined). If a quest uses a
        -- named 'location' with no coords, we can't resolve it, so fall through to
        -- the partial rule (must be near the quest NPC / at coords).
        if obj.coords then
            return playerNearCoords(src, obj.coords, obj.radius), false
        end
    elseif t == 'wait' then
        -- handled by caller via elapsed time; treated as ok here.
        return true, false
    elseif t == 'pickup' or t == 'collect' or t == 'retrieve' then
        if obj.item then
            return playerHasItem(src, obj.item, obj.amount), false
        end
    elseif t == 'deliver' then
        -- Must possess the item; if coords given must be there too. Consume on success.
        if obj.item then
            if not playerHasItem(src, obj.item, obj.amount) then return false, false end
            if obj.coords and not playerNearCoords(src, obj.coords, obj.radius) then return false, false end
            return true, true  -- caller removes the item
        end
        if obj.coords then
            return playerNearCoords(src, obj.coords, obj.radius), false
        end
    end

    -- PARTIAL types (kill, intimidate, find, etc.) and coordless goto/deliver:
    -- require the player to physically be at the objective coords if we have them.
    if obj.coords then
        return playerNearCoords(src, obj.coords, obj.radius), false
    end
    -- No coords and no item to check: allow reporting only while standing next to
    -- the quest-giver NPC (handled by the caller, which knows npcId). We signal
    -- "needs npc proximity" by returning true here; caller already enforced it.
    return true, false
end

RegisterNetEvent('ai-npcs:server:reportObjective', function(questId)
    local src = source
    local citizenid, Player = getCitizenId(src)
    if not citizenid then return end

    -- Locate the quest definition + owning NPC.
    local quest, setKey = GetQuestById(questId)
    if not quest then return end

    local row = MySQL.single.await([[
        SELECT * FROM ai_npc_quests
        WHERE citizenid = ? AND quest_id = ? AND status IN ('accepted','in_progress')
    ]], {citizenid, questId})
    if not row then return end

    local npcId = row.npc_id
    local npc = GetNPCById(npcId)

    local data = json.decode(row.quest_data or '{}')
    local progress = data.progress or {}
    local idx = firstIncomplete(progress)
    if not idx then return end  -- already all done (completion race)

    local obj = progress[idx]

    -- Anti-spoof gate: the player must either be at the objective coords, or (for
    -- objectives we can't place in the world) next to the quest-giver NPC.
    local hasCoords = obj.coords ~= nil
    if not hasCoords and not IsPlayerInQuestRange(src, npcId) then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Not Here', description = 'Go back to them to report this.', type = 'error'
        })
        return
    end

    -- wait objectives: enforce real elapsed time since accept.
    if obj.type == 'wait' and obj.duration then
        local elapsed = os.time() - (data.acceptedAt or os.time())
        if elapsed < obj.duration then
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Too Soon', description = ('Wait a bit longer (%ds left).'):format(obj.duration - elapsed), type = 'error'
            })
            return
        end
    end

    local ok, consume = validateObjective(src, obj)
    if not ok then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Not Done', description = 'You haven\'t completed that step yet.', type = 'error'
        })
        return
    end

    -- Consume delivered items server-side.
    if consume and obj.item then
        local removed = pcall(function()
            return exports.ox_inventory:RemoveItem(src, obj.item, obj.amount or 1)
        end)
        if not removed then return end
    end

    progress[idx].done = true
    data.progress = progress

    local remaining = firstIncomplete(progress)
    if remaining then
        -- Persist partial progress.
        MySQL.update.await([[
            UPDATE ai_npc_quests SET status = 'in_progress', quest_data = ?
            WHERE citizenid = ? AND quest_id = ?
        ]], {json.encode(data), citizenid, questId})

        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Progress', description = ('Step %d/%d done.'):format(idx, #progress), type = 'success'
        })
    else
        -- All objectives complete -> pay out + close.
        GrantQuestReward(src, citizenid, Player, npc, npcId, quest)
        MySQL.update.await([[
            UPDATE ai_npc_quests
            SET status = 'completed', reward_claimed = TRUE, quest_data = ?, completed_at = CURRENT_TIMESTAMP
            WHERE citizenid = ? AND quest_id = ?
        ]], {json.encode(data), citizenid, questId})

        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Job Complete', description = quest.title, type = 'success', duration = 10000
        })
        TriggerClientEvent('ai-npcs:client:questCompleted', src, { questId = questId, title = quest.title })

        -- Optional Discord log (no-op if logging disabled).
        -- Signature: LogQuestCompletion(playerId, npcId, npcName, questId, trustReward)
        if exports['dps-ainpcs'].LogQuestCompletion then
            pcall(function()
                exports['dps-ainpcs']:LogQuestCompletion(
                    src, npcId, (npc and npc.name) or npcId, quest.title,
                    (quest.reward and quest.reward.trust) or 0
                )
            end)
        end
    end
end)

-----------------------------------------------------------
-- REWARD (server-authoritative; client never supplies amounts)
-----------------------------------------------------------
function GrantQuestReward(src, citizenid, Player, npc, npcId, quest)
    local reward = quest.reward or {}

    -- Money
    if reward.money and reward.money > 0 and Player then
        Player.Functions.AddMoney('cash', reward.money, 'ai-npc-quest:' .. tostring(quest.id))
    end

    -- Item
    if reward.item and reward.item.name then
        pcall(function()
            exports.ox_inventory:AddItem(src, reward.item.name, reward.item.amount or 1)
        end)
    end

    -- Individual NPC trust
    if reward.trust and reward.trust > 0 and npc then
        AddPlayerTrust(citizenid, npc.trustCategory, npcId, reward.trust)
    end

    -- Referral to another NPC
    if reward.referral then
        CreateReferral(citizenid, npcId, reward.referral, 'quest')
    end

    -- Faction trust (quest.factionTrust = { faction = delta, ... })
    if quest.factionTrust and exports['dps-ainpcs'].AddFactionTrust then
        for faction, delta in pairs(quest.factionTrust) do
            pcall(function()
                exports['dps-ainpcs']:AddFactionTrust(citizenid, faction, delta, 'quest:' .. tostring(quest.id))
            end)
        end
    end
end

-----------------------------------------------------------
-- Player's active quests (for the client "my jobs" menu)
-----------------------------------------------------------
RegisterNetEvent('ai-npcs:server:getMyQuests', function()
    local src = source
    local citizenid = getCitizenId(src)
    if not citizenid then return end

    local rows = MySQL.query.await([[
        SELECT npc_id, quest_id, status, quest_data FROM ai_npc_quests
        WHERE citizenid = ? AND status IN ('accepted','in_progress')
    ]], {citizenid}) or {}

    local list = {}
    for _, row in ipairs(rows) do
        local quest = GetQuestById(row.quest_id)
        local data = json.decode(row.quest_data or '{}')
        local progress = data.progress or {}
        local doneCount = 0
        for _, o in ipairs(progress) do if o.done then doneCount = doneCount + 1 end end
        local nextIdx = firstIncomplete(progress)
        list[#list + 1] = {
            questId = row.quest_id,
            title = quest and quest.title or row.quest_id,
            status = row.status,
            done = doneCount,
            total = #progress,
            nextType = nextIdx and progress[nextIdx].type or nil,
            nextLocation = nextIdx and progress[nextIdx].location or nil,
        }
    end
    TriggerClientEvent('ai-npcs:client:showMyQuests', src, list)
end)

-----------------------------------------------------------
-- EXPORTS (server-side, for trusted callers)
-----------------------------------------------------------
exports('GetOfferableQuests', getOfferableQuests)
exports('GrantQuestReward', GrantQuestReward)

print("^2[AI NPCs]^7 Quest engine loaded (server-authoritative)")
