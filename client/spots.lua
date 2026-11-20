-- NPC spots, player side. Lays the staff-set places (GlobalState.dpsNpcSpots) over config.lua and
-- re-places an NPC when its spot changes. /npcspots is the staff menu.
local original = {}   -- key -> vector4 from config.lua

local function place(npc, n, value)
    if not n then
        if value then npc.homeLocation = value end
        return npc.homeLocation
    end
    local loc = npc.movement and type(npc.movement.locations) == 'table' and npc.movement.locations[n]
    if not loc or not loc.coords then return nil end
    if value then loc.coords = value end
    return loc.coords
end

local function same(a, b)
    return a and b and math.abs(a.x - b.x) < 0.01 and math.abs(a.y - b.y) < 0.01 and math.abs(a.z - b.z) < 0.01
        and math.abs((a.w or 0) - (b.w or 0)) < 0.1
end

--- Returns the NPCs whose places changed.
local function apply(spots, respawn)
    spots = type(spots) == 'table' and spots or {}
    local changed = {}
    for _, npc in pairs(Config.NPCs) do
        if npc.id then
            local count = npc.movement and type(npc.movement.locations) == 'table' and #npc.movement.locations or 0
            for n = 0, count do
                local idx = n > 0 and n or nil
                local key = idx and (npc.id .. '#' .. idx) or npc.id
                local now = place(npc, idx)
                if now then
                    original[key] = original[key] or now
                    local s = spots[key]
                    local want = s and vector4(s.x + 0.0, s.y + 0.0, s.z + 0.0, (s.h or 0) + 0.0) or original[key]
                    if not same(now, want) then
                        place(npc, idx, want)
                        changed[npc.id] = npc
                    end
                end
            end
        end
    end
    if respawn then
        for id, npc in pairs(changed) do
            DespawnNPC(id, false)
            RegisterNPCPoint(npc)
        end
    end
end

apply(GlobalState.dpsNpcSpots, false)   -- before the first spawn

AddStateBagChangeHandler('dpsNpcSpots', 'global', function(_, _, value)
    apply(value, true)
end)

-- ---------- staff menu ----------
local function spotMenu(entry, key, label, x, y, z, moved)
    lib.registerContext({
        id = 'npcspots_one', title = label, menu = 'npcspots_npc',
        options = {
            { title = 'Go there', description = ('%.1f, %.1f, %.1f'):format(x, y, z), icon = 'fa-solid fa-location-arrow',
              onSelect = function() TriggerServerEvent('dps-ainpcs:spots:goto', key) end },
            { title = 'Put this spot where I stand', description = 'Uses your position and the way you face. Saved for everyone.',
              icon = 'fa-solid fa-thumbtack',
              onSelect = function() TriggerServerEvent('dps-ainpcs:spots:set', key) end },
            { title = 'Back to the config.lua spot', icon = 'fa-solid fa-rotate-left', disabled = not moved,
              onSelect = function() TriggerServerEvent('dps-ainpcs:spots:reset', key) end },
        },
    })
    lib.showContext('npcspots_one')
end

local function npcMenu(entry)
    local options = {
        { title = 'Main spot' .. (entry.moved and ' (moved by staff)' or ''), description = ('%s. %.1f, %.1f, %.1f'):format(entry.pattern, entry.x, entry.y, entry.z),
          icon = 'fa-solid fa-house',
          onSelect = function() spotMenu(entry, entry.id, entry.name .. ': main spot', entry.x, entry.y, entry.z, entry.moved) end },
    }
    for _, e in ipairs(entry.extra or {}) do
        local when = type(e.time) == 'table' and (' (%s:00 to %s:00)'):format(tostring(e.time[1]), tostring(e.time[2])) or ''
        options[#options + 1] = {
            title = ('Spot %d%s%s'):format(e.n, when, e.moved and ' (moved by staff)' or ''),
            description = ('%.1f, %.1f, %.1f'):format(e.x, e.y, e.z), icon = 'fa-solid fa-route',
            onSelect = function() spotMenu(entry, entry.id .. '#' .. e.n, ('%s: spot %d'):format(entry.name, e.n), e.x, e.y, e.z, e.moved) end,
        }
    end
    lib.registerContext({ id = 'npcspots_npc', title = entry.name, menu = 'npcspots_all', options = options })
    lib.showContext('npcspots_npc')
end

RegisterNetEvent('dps-ainpcs:spots:open', function()
    local list = lib.callback.await('dps-ainpcs:spots:list', false)
    if not list then return end
    local options = {}
    for _, entry in ipairs(list) do
        options[#options + 1] = {
            title = entry.name .. (entry.moved and ' (moved)' or ''),
            description = entry.note and ('CHECK: ' .. entry.note) or entry.id,
            icon = entry.note and 'fa-solid fa-triangle-exclamation' or 'fa-solid fa-user',
            iconColor = entry.note and '#f59e0b' or nil,
            onSelect = function() npcMenu(entry) end,
        }
    end
    lib.registerContext({ id = 'npcspots_all', title = 'AI NPC spots (' .. #list .. ')', options = options })
    lib.showContext('npcspots_all')
end)
