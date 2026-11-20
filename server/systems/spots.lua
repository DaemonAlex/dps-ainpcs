-- NPC spots (DPS 2026-11-20). Maps change, and an NPC placed for the old map ends up in a wall, a
-- lake or a rebuilt building. Staff walk to a good place and put the NPC there; the new spot is kept
-- in the database, laid over config.lua at start, and sent to every player through
-- GlobalState.dpsNpcSpots. Keys are the NPC id, or "<id>#<n>" for its n-th schedule / patrol place.
local TABLE = 'dps_ainpc_spots'
local spots = {}          -- key -> { x, y, z, h }
local original = {}       -- key -> vector4 from config.lua, kept so a spot can be put back

-- Spots that sit inside a rebuilt part of the map (from a scan of the map files, 2026-11-20).
-- A note here means "go and look", not "this is wrong".
local CHECK = {
    homeless_sage = 'was in the middle of the new Legion Square; moved to the Legion garage, not looked at yet',
    cleaner = 'home is inside the racetrack map; one daytime spot is at the rebuilt Pearls',
    informant_yellowjack = 'Yellow Jack area was rebuilt by the Sandy map',
    meth_cook_sandy = 'Sandy was rebuilt here (new houses)',
    mid_level_dealer = 'Sandy was rebuilt here',
    restaurant_owner = 'stands at the new Burger Shot building',
    cartel_boss = 'stands at the new Richman mansion',
    pilot_lsia = 'the airport terminal was rebuilt',
    career_counselor_cityhall = 'one spot is at the new Al Dente\'s',
    fence_chamberlain = 'one spot is at the new supermarket',
    casino_host = 'casino front was rebuilt',
}

local function isStaff(src)
    return src == 0 or IsPlayerAceAllowed(src, 'group.admin') or IsPlayerAceAllowed(src, 'command')
end

local function keyParts(key)
    local id, n = tostring(key):match('^(.-)#(%d+)$')
    if id then return id, tonumber(n) end
    return tostring(key), nil
end

local function findNpc(id)
    for _, npc in pairs(Config.NPCs) do
        if npc.id == id then return npc end
    end
    return nil
end

--- Read or write the place a key points at. Returns the vector4 that is there now.
local function place(key, value)
    local id, n = keyParts(key)
    local npc = findNpc(id)
    if not npc then return nil end
    if not n then
        if value then npc.homeLocation = value end
        return npc.homeLocation
    end
    local loc = npc.movement and type(npc.movement.locations) == 'table' and npc.movement.locations[n]
    if not loc or not loc.coords then return nil end
    if value then loc.coords = value end
    return loc.coords
end

local function publish()
    local out = {}
    for key, s in pairs(spots) do out[key] = { x = s.x, y = s.y, z = s.z, h = s.h } end
    GlobalState.dpsNpcSpots = out
end

local function apply(key)
    local now = place(key)
    if not now then return false end
    original[key] = original[key] or now
    local s = spots[key]
    place(key, s and vector4(s.x, s.y, s.z, s.h) or original[key])
    return true
end

CreateThread(function()
    local ok = pcall(MySQL.query.await, ([[CREATE TABLE IF NOT EXISTS %s (
        spot_key VARCHAR(80) PRIMARY KEY, x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL, h DOUBLE NOT NULL,
        set_by VARCHAR(80) NULL, set_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP)]]):format(TABLE))
    local rows = ok and MySQL.query.await(('SELECT spot_key, x, y, z, h FROM %s'):format(TABLE)) or {}
    local n = 0
    for _, r in ipairs(rows or {}) do
        spots[r.spot_key] = { x = r.x + 0.0, y = r.y + 0.0, z = r.z + 0.0, h = r.h + 0.0 }
        if apply(r.spot_key) then n = n + 1 else spots[r.spot_key] = nil end
    end
    publish()
    print(('[dps-ainpcs] NPC spots: %d moved by staff'):format(n))
end)

lib.callback.register('dps-ainpcs:spots:list', function(src)
    if not isStaff(src) then return nil end
    local list = {}
    for _, npc in pairs(Config.NPCs) do
        if npc.id and npc.homeLocation and not npc.external then
            local h = npc.homeLocation
            local entry = { id = npc.id, name = npc.name or npc.id, note = CHECK[npc.id], moved = spots[npc.id] ~= nil,
                x = h.x, y = h.y, z = h.z, pattern = npc.movement and npc.movement.pattern or 'stationary', extra = {} }
            local locs = npc.movement and npc.movement.locations
            if type(locs) == 'table' then
                for i, loc in ipairs(locs) do
                    if loc.coords then
                        entry.extra[#entry.extra + 1] = { n = i, x = loc.coords.x, y = loc.coords.y, z = loc.coords.z,
                            moved = spots[npc.id .. '#' .. i] ~= nil, time = loc.time }
                    end
                end
            end
            list[#list + 1] = entry
        end
    end
    table.sort(list, function(a, b)
        if (a.note ~= nil) ~= (b.note ~= nil) then return a.note ~= nil end
        return a.name < b.name
    end)
    return list
end)

RegisterNetEvent('dps-ainpcs:spots:goto', function(key)
    local src = source
    if not isStaff(src) or type(key) ~= 'string' then return end
    local at = place(key)
    local ped = GetPlayerPed(src)
    if not at or not ped or ped == 0 then return end
    -- A step to the side and a little up, so staff do not land inside the NPC or under the floor
    SetEntityCoords(ped, at.x + 1.5, at.y + 1.5, at.z + 0.5, false, false, false, false)
end)

RegisterNetEvent('dps-ainpcs:spots:set', function(key)
    local src = source
    if not isStaff(src) or type(key) ~= 'string' or #key > 80 then return end
    if not place(key) then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local at, h = GetEntityCoords(ped), GetEntityHeading(ped)
    -- Saved as the game reports it, the same way the spots in config.lua were written down
    spots[key] = { x = at.x, y = at.y, z = at.z, h = h }
    apply(key)
    publish()
    MySQL.query(('REPLACE INTO %s (spot_key, x, y, z, h, set_by) VALUES (?, ?, ?, ?, ?, ?)'):format(TABLE),
        { key, at.x, at.y, at.z, h, GetPlayerName(src) })
    print(('[dps-ainpcs] NPC spot %s set to %.2f, %.2f, %.2f by %s'):format(key, at.x, at.y, at.z, GetPlayerName(src)))
    TriggerClientEvent('ox_lib:notify', src, { title = 'NPC spots', description = 'Saved. The NPC is here now, for everyone.', type = 'success' })
end)

RegisterNetEvent('dps-ainpcs:spots:reset', function(key)
    local src = source
    if not isStaff(src) or type(key) ~= 'string' or not spots[key] then return end
    spots[key] = nil
    apply(key)
    publish()
    MySQL.query(('DELETE FROM %s WHERE spot_key = ?'):format(TABLE), { key })
    TriggerClientEvent('ox_lib:notify', src, { title = 'NPC spots', description = 'Back to the spot in config.lua.', type = 'inform' })
end)

RegisterCommand('npcspots', function(source)
    if source == 0 then
        for key, s in pairs(spots) do print(('%s  %.2f, %.2f, %.2f, %.1f'):format(key, s.x, s.y, s.z, s.h)) end
        return
    end
    if not isStaff(source) then return end
    TriggerClientEvent('dps-ainpcs:spots:open', source)
end, false)
