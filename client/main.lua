-- NOTE: this qbx build exposes NO GetCoreObject(). There is no QBCore global
-- on the client; load is gated on a qbx ready check instead (see below).

-- Local variables
local spawnedNPCs = {}
local activeConversation = nil
local conversationCooldown = false
local npcMovementThreads = {}
-- Distance-gated spawning (2026-09-05): one ox_lib point per NPC. The NPC ped
-- exists only while a player is inside the point. Replaces the old behaviour of
-- creating every configured NPC across the whole map the moment a player loaded.
local npcPoints = {}
local SPAWN_DISTANCE = (Config.Movement and Config.Movement.spawnDistance) or 120.0

-----------------------------------------------------------
-- KVP-BASED CLIENT PREFERENCES (Persistent Storage)
-----------------------------------------------------------
local KVP_PREFIX = "ainpcs:"
local clientPreferences = {}

-- Load preference from KVP storage
local function LoadPreference(key, defaultValue)
    local kvpKey = KVP_PREFIX .. key
    local stored = GetResourceKvpString(kvpKey)

    if stored and stored ~= "" then
        -- Try to parse as JSON for complex types
        local success, value = pcall(json.decode, stored)
        if success and value ~= nil then
            return value
        end
        -- Return as string if not JSON
        return stored
    end

    return defaultValue
end

-- Save preference to KVP storage
local function SavePreference(key, value)
    local kvpKey = KVP_PREFIX .. key

    if type(value) == "table" then
        SetResourceKvp(kvpKey, json.encode(value))
    elseif type(value) == "boolean" then
        SetResourceKvp(kvpKey, value and "true" or "false")
    elseif type(value) == "number" then
        SetResourceKvp(kvpKey, tostring(value))
    else
        SetResourceKvp(kvpKey, tostring(value))
    end

    clientPreferences[key] = value
end

-- Get preference (from cache or KVP)
local function GetPreference(key, defaultValue)
    if clientPreferences[key] ~= nil then
        return clientPreferences[key]
    end

    local value = LoadPreference(key, defaultValue)
    clientPreferences[key] = value
    return value
end

-- Delete a preference
local function DeletePreference(key)
    local kvpKey = KVP_PREFIX .. key
    DeleteResourceKvp(kvpKey)
    clientPreferences[key] = nil
end

-- Initialize preferences on load
local function InitializePreferences()
    -- Load all preferences with defaults
    clientPreferences = {
        showSubtitles = LoadPreference("showSubtitles", true),
        subtitleDuration = LoadPreference("subtitleDuration", 5000),
        soundVolume = LoadPreference("soundVolume", 1.0),
        enableNetworkedSpeech = LoadPreference("enableNetworkedSpeech", true),
        preferredNPCVoice = LoadPreference("preferredNPCVoice", nil),
        lastTalkedNPC = LoadPreference("lastTalkedNPC", nil),
    }

    print("[AI NPCs] Client preferences loaded from KVP storage")
end

-- Export preference functions for other scripts
exports('GetPreference', GetPreference)
exports('SetPreference', SavePreference)
exports('DeletePreference', DeletePreference)

-- NUI callback to get/set preferences
RegisterNUICallback('getPreferences', function(data, cb)
    cb(clientPreferences)
end)

RegisterNUICallback('setPreference', function(data, cb)
    if data.key and data.value ~= nil then
        SavePreference(data.key, data.value)
        cb({ success = true })
    else
        cb({ success = false, error = "Invalid key or value" })
    end
end)

-----------------------------------------------------------
-- INITIALIZATION
-----------------------------------------------------------
CreateThread(function()
    -- qbx ready check: wait until the player is fully loaded before spawning NPCs.
    -- LocalPlayer.state.isLoggedIn is set by qbx_core on load; fall back to a
    -- non-empty GetPlayerData() in case state isn't populated yet.
    while not (LocalPlayer.state and LocalPlayer.state.isLoggedIn) do
        local pdata = exports.qbx_core:GetPlayerData()
        if pdata and pdata.citizenid then break end
        Wait(250)
    end

    -- Initialize KVP preferences first
    InitializePreferences()

    SpawnNPCs()
    StartMovementSystem()
    print("[AI NPCs] Client initialized with movement system and preferences")
end)

-----------------------------------------------------------
-- NPC SPAWNING
-----------------------------------------------------------
function SpawnNPCs()
    for _, npcData in pairs(Config.NPCs) do
        RegisterNPCPoint(npcData)
    end
end

-- One ox_lib point per NPC at its current (schedule-aware) location.
-- onEnter creates the ped, onExit removes it. Re-registered on despawn so
-- schedule-pattern NPCs get a point at their current spot.
function RegisterNPCPoint(npcData)
    local coords = GetNPCCurrentLocation(npcData)
    if not coords then return end
    if npcPoints[npcData.id] then
        npcPoints[npcData.id]:remove()
        npcPoints[npcData.id] = nil
    end
    if npcPoints[npcData.id .. ":hail"] then
        npcPoints[npcData.id .. ":hail"]:remove()
        npcPoints[npcData.id .. ":hail"] = nil
    end
    local point = lib.points.new({
        coords = vec3(coords.x, coords.y, coords.z),
        distance = SPAWN_DISTANCE,
        npcId = npcData.id,
    })
    function point:onEnter()
        if not spawnedNPCs[npcData.id] then
            CreateNPC(npcData)
        end
    end
    function point:onExit()
        if spawnedNPCs[npcData.id] then
            DespawnNPC(npcData.id, true)
        end
    end
    npcPoints[npcData.id] = point

    -- DPS 2026-09-27: some NPCs call you over when you walk past (npcData.hail).
    if npcData.hail then
        local hailPoint = lib.points.new({
            coords = vec3(coords.x, coords.y, coords.z),
            distance = npcData.hail.distance or 9.0,
            npcId = npcData.id,
        })
        function hailPoint:onEnter()
            HailPlayer(npcData.id)
        end
        npcPoints[npcData.id .. ":hail"] = hailPoint
    end
end

function CreateNPC(npcData)
    -- Check schedule availability
    if not IsNPCAvailable(npcData) then
        -- Schedule check later
        ScheduleNPCSpawn(npcData)
        return
    end

    -- Get spawn location based on schedule or home
    local spawnCoords = GetNPCCurrentLocation(npcData)
    if not spawnCoords then return end

    -- Never create a ped the player is not near: the point's onEnter will do it
    -- when they arrive. Guards every other caller (schedule loop, culled-entity
    -- respawn) that used to spawn map-wide.
    if #(GetEntityCoords(PlayerPedId()) - vec3(spawnCoords.x, spawnCoords.y, spawnCoords.z)) > SPAWN_DISTANCE then
        return
    end

    RequestModel(npcData.model)
    local modelTimeout = 0
    while not HasModelLoaded(npcData.model) and modelTimeout < 5000 do
        Wait(10)
        modelTimeout = modelTimeout + 10
    end

    if not HasModelLoaded(npcData.model) then
        print(("[AI NPCs] ^1Failed to load model for NPC: %s (%s)^7"):format(npcData.name, npcData.model))
        return
    end

    -- Crowd members take a random spot around their bar instead of the shared centre.
    local crowdSit, crowdSeat = false, false
    if npcData.crowd then
        local pt, sit, seat = CrowdSpawnPoint(npcData)
        crowdSeat = seat
        if not pt then return end
        spawnCoords = pt
        crowdSit = sit
    end

    local npc = CreatePed(4, npcData.model, spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnCoords.w, false, true)

    -- Verify NPC was created successfully
    if not npc or npc == 0 or not DoesEntityExist(npc) then
        print(("[AI NPCs] ^1Failed to spawn NPC: %s (invalid entity)^7"):format(npcData.name))
        SetModelAsNoLongerNeeded(npcData.model)
        return
    end

    -- Final ground snap fallback: place ped on ground properly
    PlaceObjectOnGroundProperly(npc)

    -- Configure NPC base properties
    SetEntityInvincible(npc, true)
    SetPedFleeAttributes(npc, 0, 0)
    SetPedDiesWhenInjured(npc, false)
    SetPedCanRagdollFromPlayerImpact(npc, false)
    SetEntityCanBeDamaged(npc, false)
    SetPedCanBeTargetted(npc, false)
    SetBlockingOfNonTemporaryEvents(npc, true)
    SetPedConfigFlag(npc, 32, false) -- Can't be dragged out of vehicles
    SetPedConfigFlag(npc, 281, true) -- No writhe

    -- Movement configuration based on pattern
    if npcData.movement and npcData.movement.pattern ~= "stationary" and npcData.movement.pattern ~= "crowd" then
        FreezeEntityPosition(npc, false)
        SetPedCanPlayAmbientAnims(npc, true)
        SetPedKeepTask(npc, true)
    elseif npcData.movement and npcData.movement.pattern == "crowd" then
        FreezeEntityPosition(npc, false) -- scenario warps need a free ped; the pose holds them
        SetPedCanPlayAmbientAnims(npc, true)
        SetPedKeepTask(npc, true)
    else
        FreezeEntityPosition(npc, true)
        SetPedCanPlayAmbientAnims(npc, true)
    end

    -- DPS 2026-09-27: pose for this spot (schedule slot `scenario` or npcData.scenario)
    if npcData.crowd then
        CrowdPose(npc, npcData, spawnCoords, crowdSit, crowdSeat)
    else
        ApplyNPCScenario(npc, npcData)
    end

    -- Release model from memory (entity keeps its own reference)
    SetModelAsNoLongerNeeded(npcData.model)

    -- Store NPC data
    spawnedNPCs[npcData.id] = {
        entity = npc,
        data = npcData,
        currentWaypointIndex = 1,
        isMoving = false,
        lastMoveTime = GetGameTimer()
    }

    -- Add ox_target interaction
    AddNPCTarget(npc, npcData)

    -- Add blip if configured
    if npcData.blip then
        CreateNPCBlip(npcData, spawnCoords)
    end

    print(("[AI NPCs] Spawned NPC: %s at %.1f, %.1f, %.1f"):format(
        npcData.name, spawnCoords.x, spawnCoords.y, spawnCoords.z
    ))
end

-----------------------------------------------------------
-- CROWDS (real-people pass 2026-09-27): random spots around a bar, sitters on the real
-- stools and chairs (nearest scenario point), standers at clear floor spots with a pose.
-----------------------------------------------------------
local CROWD_STAND_SCENARIOS = { "WORLD_HUMAN_DRINKING", "WORLD_HUMAN_HANG_OUT_STREET", "WORLD_HUMAN_LEANING", "WORLD_HUMAN_STAND_MOBILE", "WORLD_HUMAN_STAND_IMPATIENT", "WORLD_HUMAN_DRINKING" }

-- DPS 2026-09-27 (Damon: "dude on the roof"): the spot must be at the crowd's own floor height, probed from just above it.
local function crowdFloorZ(center, x, y)
    local found, gz = GetGroundZFor_3dCoord(x, y, center.z + 2.0, false)
    if not found or math.abs(gz - center.z) > 1.5 then return nil end
    return gz
end

local function crowdFloorClear(center, x, y, z)
    -- A wall between the centre and the spot means the spot is in another room or outside.
    local ray = StartShapeTestRay(center.x, center.y, center.z + 0.6, x, y, z + 0.6, 1 + 16, 0, 7)
    local _, hit = GetShapeTestResult(ray)
    return hit == 0
end

local function crowdTooClose(key, x, y)
    for id, info in pairs(spawnedNPCs) do
        if info.data.crowd and info.data.crowd.key == key and DoesEntityExist(info.entity) then
            local p = GetEntityCoords(info.entity)
            if #(vector3(p.x, p.y, 0) - vector3(x, y, 0)) < 1.4 then return true end
        end
    end
    return false
end

local function crowdKeptOut(crowd, x, y)
    for _, k in ipairs(crowd.keepOut or {}) do
        if #(vector2(x, y) - vector2(k.pos.x, k.pos.y)) < (k.radius or 2.0) then return true end
    end
    return false
end

function CrowdSpawnPoint(npcData)
    local crowd = Config.Crowds and Config.Crowds[npcData.crowd.key]
    if not crowd then return nil end
    local c = crowd.center
    local center = vector3(c.x, c.y, c.z)
    local wantSit = npcData.crowd.sit
    -- Hand-marked seats (crowd.seats): sitters take a free one, in random order.
    if wantSit and crowd.seats and #crowd.seats > 0 then
        local order = {}
        for i = 1, #crowd.seats do order[i] = i end
        for i = #order, 2, -1 do local j = math.random(i); order[i], order[j] = order[j], order[i] end
        for _, i in ipairs(order) do
            local s = crowd.seats[i]
            if not crowdTooClose(npcData.crowd.key, s.x, s.y) then
                return vector4(s.x, s.y, s.z, s.w or 0.0), true, true
            end
        end
    end
    -- Hand-set spot wins over everything (data/crowds.lua persona.spot)
    if npcData.crowd.spot then
        local s = npcData.crowd.spot
        return vector4(s.x, s.y, s.z, s.w or 0.0), wantSit
    end
    -- Sitters spawn near the counter and warp into the nearest seat scenario (stool, chair).
    if wantSit and crowd.counter then
        local cc = crowd.counter
        for _ = 1, 8 do
            local x = cc.x + (math.random() - 0.5) * 6.0
            local y = cc.y + (math.random() - 0.5) * 6.0
            if not crowdKeptOut(crowd, x, y) and not crowdTooClose(npcData.crowd.key, x, y) and crowdFloorClear(center, x, y, cc.z) then
                return vector4(x, y, cc.z, math.random(0, 359) + 0.0), true
            end
        end
    end
    for _ = 1, 14 do
        local angle = math.random() * 2 * math.pi
        local dist = 1.5 + math.random() * (crowd.radius - 1.5)
        local x = center.x + math.cos(angle) * dist
        local y = center.y + math.sin(angle) * dist
        local gz = crowdFloorZ(center, x, y)
        if gz and not crowdKeptOut(crowd, x, y) and not crowdTooClose(npcData.crowd.key, x, y) and crowdFloorClear(center, x, y, gz) then
            local heading = math.deg(math.atan(center.y - y, center.x - x)) - 90.0 + (math.random() - 0.5) * 60.0
            return vector4(x, y, gz, heading), false
        end
    end
    return vector4(center.x, center.y, center.z, c.w or 0.0), false
end

function CrowdPose(entity, npcData, spot, trySit, markedSeat)
    if markedSeat then
        -- A hand-marked stool or chair: sit exactly there, facing the marked heading.
        TaskStartScenarioAtPosition(entity, "PROP_HUMAN_SEAT_CHAIR_MP_PLAYER", spot.x, spot.y, spot.z, spot.w, 0, true, true)
        return
    end
    if trySit then
        -- Nearest seat scenario within 3 m (vanilla bars have them on every stool); warp in.
        TaskUseNearestScenarioToCoordWarp(entity, spot.x, spot.y, spot.z, 3.0, -1)
        CreateThread(function()
            Wait(1500)
            if DoesEntityExist(entity) and not IsPedUsingAnyScenario(entity) then
                TaskStartScenarioInPlace(entity, CROWD_STAND_SCENARIOS[math.random(#CROWD_STAND_SCENARIOS)], 0, true)
            end
        end)
        return
    end
    TaskStartScenarioInPlace(entity, CROWD_STAND_SCENARIOS[math.random(#CROWD_STAND_SCENARIOS)], 0, true)
end

function AddNPCTarget(npc, npcData)
    exports.ox_target:addLocalEntity(npc, {
        {
            name = "talk_to_" .. npcData.id,
            label = "Talk to " .. npcData.name,
            icon = "fas fa-comments",
            distance = Config.Interaction.distance,
            onSelect = function()
                StartConversation(npcData.id)
            end
        },
        {
            name = "pay_" .. npcData.id,
            label = "Offer Payment",
            icon = "fas fa-money-bill-wave",
            distance = Config.Interaction.distance,
            canInteract = function()
                return activeConversation and activeConversation.npcId == npcData.id
            end,
            onSelect = function()
                ShowPaymentMenu(npcData.id)
            end
        },
        {
            -- H3: ask this NPC what jobs they have
            name = "work_" .. npcData.id,
            label = "Ask About Work",
            icon = "fas fa-briefcase",
            distance = Config.Interaction.distance,
            onSelect = function()
                TriggerServerEvent('ai-npcs:server:requestQuests', npcData.id)
            end
        },
        {
            -- H3: report progress on / review active jobs
            name = "jobs_" .. npcData.id,
            label = "Active Jobs",
            icon = "fas fa-list-check",
            distance = Config.Interaction.distance,
            onSelect = function()
                TriggerServerEvent('ai-npcs:server:getMyQuests')
            end
        }
    })
end

function CreateNPCBlip(npcData, coords)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, npcData.blip.sprite)
    SetBlipColour(blip, npcData.blip.color)
    SetBlipScale(blip, npcData.blip.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(npcData.blip.label or npcData.name)
    EndTextCommandSetBlipName(blip)

    spawnedNPCs[npcData.id].blip = blip
end

-----------------------------------------------------------
-- SCHEDULE & AVAILABILITY
-----------------------------------------------------------
function IsNPCAvailable(npcData)
    if not npcData.schedule then return true end

    local currentHour = GetClockHours()

    for _, schedule in ipairs(npcData.schedule) do
        local startHour = schedule.time[1]
        local endHour = schedule.time[2]

        local isInTimeRange
        if startHour < endHour then
            isInTimeRange = currentHour >= startHour and currentHour < endHour
        else
            -- Handles overnight schedules (e.g., 20-4)
            isInTimeRange = currentHour >= startHour or currentHour < endHour
        end

        if isInTimeRange then
            return schedule.active ~= false
        end
    end

    return true
end

function GetNPCCurrentLocation(npcData)
    -- Check schedule-based locations first
    if npcData.movement and npcData.movement.pattern == "schedule" then
        local currentHour = GetClockHours()

        for _, locData in ipairs(npcData.movement.locations) do
            local startHour = locData.time[1]
            local endHour = locData.time[2]

            local isInTimeRange
            if startHour < endHour then
                isInTimeRange = currentHour >= startHour and currentHour < endHour
            else
                isInTimeRange = currentHour >= startHour or currentHour < endHour
            end

            if isInTimeRange then
                return locData.coords
            end
        end
    end

    return npcData.homeLocation
end

-- DPS 2026-09-27: ambient scenario for the NPC's current spot. A schedule slot may carry
-- `scenario = "WORLD_HUMAN_..."`; otherwise npcData.scenario; otherwise none (idle).
function GetNPCCurrentScenario(npcData)
    if npcData.movement and npcData.movement.pattern == "schedule" then
        local currentHour = GetClockHours()
        for _, locData in ipairs(npcData.movement.locations) do
            local startHour, endHour = locData.time[1], locData.time[2]
            local inRange
            if startHour < endHour then
                inRange = currentHour >= startHour and currentHour < endHour
            else
                inRange = currentHour >= startHour or currentHour < endHour
            end
            if inRange then return locData.scenario or npcData.scenario end
        end
    end
    return npcData.scenario
end

function ApplyNPCScenario(entity, npcData)
    if not entity or not DoesEntityExist(entity) then return end
    local scenario = GetNPCCurrentScenario(npcData)
    if not scenario then return end
    if IsPedUsingScenario(entity, scenario) then return end
    TaskStartScenarioInPlace(entity, scenario, 0, true)
end

-- Short stroll away from a schedule spot and back. Slot may set `wander = <metres>` (default 7).
function StrollAroundSpot(npcInfo, spot, currentTime)
    if npcInfo.isMoving or npcInfo.inConversation then return end
    local sinceLast = currentTime - (npcInfo.lastMoveTime or 0)
    if sinceLast < (npcInfo.nextStrollIn or math.random(60000, 150000)) then return end
    npcInfo.nextStrollIn = math.random(60000, 150000)

    local entity = npcInfo.entity
    local radius = (spot.wander or 7.0) + 0.0
    if radius < 3.5 then return end -- posted indoors (wander = 0): never stroll through counters and walls
    local angle = math.random() * 2 * math.pi
    local d = 3.0 + math.random() * (radius - 3.0)
    local tx, ty = spot.x + math.cos(angle) * d, spot.y + math.sin(angle) * d
    local found, gz = GetGroundZFor_3dCoord(tx, ty, spot.z + 5.0, false)
    if not found then gz = spot.z end

    npcInfo.isMoving = true
    ClearPedTasks(entity)
    TaskGoToCoordAnyMeans(entity, tx, ty, gz, 1.0, 0, false, 786603, 0.0)

    CreateThread(function()
        local started = GetGameTimer()
        while npcInfo.isMoving and DoesEntityExist(entity) and GetGameTimer() - started < 25000 do
            Wait(500)
            if #(GetEntityCoords(entity) - vector3(tx, ty, gz)) < 1.5 then break end
        end
        if not DoesEntityExist(entity) or npcInfo.inConversation then npcInfo.isMoving = false return end
        Wait(math.random(15000, 35000)) -- stand there a while
        if not DoesEntityExist(entity) or npcInfo.inConversation then npcInfo.isMoving = false return end
        TaskGoToCoordAnyMeans(entity, spot.x, spot.y, spot.z, 1.0, 0, false, 786603, 0.0)
        started = GetGameTimer()
        while DoesEntityExist(entity) and GetGameTimer() - started < 25000 do
            Wait(500)
            if #(GetEntityCoords(entity) - vector3(spot.x, spot.y, spot.z)) < 1.5 then break end
        end
        npcInfo.isMoving = false
        npcInfo.lastMoveTime = GetGameTimer()
        if DoesEntityExist(entity) and not npcInfo.inConversation then
            SetEntityHeading(entity, spot.w or GetEntityHeading(entity))
            ApplyNPCScenario(entity, npcInfo.data)
        end
    end)
end

function ScheduleNPCSpawn(npcData)
    CreateThread(function()
        while true do
            Wait(60000) -- Check every minute
            if IsNPCAvailable(npcData) and not spawnedNPCs[npcData.id] then
                CreateNPC(npcData)
                break
            end
        end
    end)
end

-----------------------------------------------------------
-- MOVEMENT SYSTEM (with dynamic sleep for optimization)
-----------------------------------------------------------
function StartMovementSystem()
    CreateThread(function()
        while true do
            local playerCoords = GetEntityCoords(PlayerPedId())
            local nearestDistance = 999999.0
            local sleepTime = 5000  -- Default: check every 5 seconds

            for npcId, npcInfo in pairs(spawnedNPCs) do
                local npcData = npcInfo.data
                local entity = npcInfo.entity

                if not DoesEntityExist(entity) then
                    -- Entity was culled/streamed out — clean up blip and respawn later
                    if npcInfo.blip then
                        RemoveBlip(npcInfo.blip)
                    end
                    spawnedNPCs[npcId] = nil
                    ScheduleNPCSpawn(npcData)
                    goto continue
                end

                -- Calculate distance for dynamic sleep
                local npcCoords = GetEntityCoords(entity)
                local distance = #(playerCoords - npcCoords)
                if distance < nearestDistance then
                    nearestDistance = distance
                end

                -- Keep blip synced with NPC position (for wander/patrol movement)
                if npcInfo.blip then
                    SetBlipCoords(npcInfo.blip, npcCoords.x, npcCoords.y, npcCoords.z)
                end

                -- Check if NPC should still be available
                if not IsNPCAvailable(npcData) then
                    DespawnNPC(npcId)
                    goto continue
                end

                -- Handle movement patterns (only if player is within range)
                if npcData.movement and distance < 100.0 then
                    HandleNPCMovement(npcId, npcInfo)
                end

                ::continue::
            end

            -- Dynamic sleep based on nearest NPC distance
            -- Optimized thresholds: responsive when close, efficient when far
            -- Note: 0ms is avoided to prevent frame stutter/client freezes
            if nearestDistance < 5.0 then
                sleepTime = 100    -- Very close (<5m): 100ms - near-instant response
            elseif nearestDistance < 15.0 then
                sleepTime = 500    -- Close: 0.5s updates
            elseif nearestDistance < 30.0 then
                sleepTime = 1000   -- Medium-close: 1s updates
            else
                sleepTime = 2000   -- Far (>30m): 2s updates - matches >50m spec
            end

            Wait(sleepTime)
        end
    end)
end

function HandleNPCMovement(npcId, npcInfo)
    local npcData = npcInfo.data
    local entity = npcInfo.entity
    local pattern = npcData.movement.pattern
    local currentTime = GetGameTimer()

    -- Don't move if in conversation (either via global check or local flag)
    if npcInfo.inConversation then
        return
    end
    if activeConversation and activeConversation.npcId == npcId then
        return
    end

    if pattern == "wander" then
        HandleWanderMovement(npcId, npcInfo, currentTime)
    elseif pattern == "patrol" then
        HandlePatrolMovement(npcId, npcInfo, currentTime)
    elseif pattern == "schedule" then
        HandleScheduleMovement(npcId, npcInfo, currentTime)
    end
end

function HandleWanderMovement(npcId, npcInfo, currentTime)
    local entity = npcInfo.entity
    local npcData = npcInfo.data
    local wanderConfig = Config.Movement.patterns.wander

    -- Check if enough time has passed since last move
    local timeSinceMove = currentTime - npcInfo.lastMoveTime
    local waitTime = math.random(wanderConfig.minWait, wanderConfig.maxWait)

    if timeSinceMove < waitTime then return end
    if npcInfo.isMoving then return end

    -- Generate random point within wander radius
    local homeCoords = npcData.homeLocation
    local angle = math.random() * 2 * math.pi
    local distance = math.random() * wanderConfig.radius

    local targetX = homeCoords.x + (math.cos(angle) * distance)
    local targetY = homeCoords.y + (math.sin(angle) * distance)

    -- Get ground Z coordinate
    local found, groundZ = GetGroundZFor_3dCoord(targetX, targetY, homeCoords.z + 10.0, false)
    if not found then groundZ = homeCoords.z end

    -- Make NPC walk to location
    npcInfo.isMoving = true
    TaskGoToCoordAnyMeans(entity, targetX, targetY, groundZ, 1.0, 0, false, 786603, 0.0)

    -- Reset when reached
    CreateThread(function()
        while npcInfo.isMoving do
            Wait(1000)
            local currentCoords = GetEntityCoords(entity)
            local dist = #(currentCoords - vector3(targetX, targetY, groundZ))
            if dist < 2.0 or not IsPedWalking(entity) then
                npcInfo.isMoving = false
                npcInfo.lastMoveTime = GetGameTimer()
            end
        end
    end)
end

function HandlePatrolMovement(npcId, npcInfo, currentTime)
    local entity = npcInfo.entity
    local npcData = npcInfo.data
    local locations = npcData.movement.locations

    if not locations or #locations == 0 then return end
    if npcInfo.isMoving then return end

    -- Get current waypoint
    local waypointIndex = npcInfo.currentWaypointIndex
    local waypoint = locations[waypointIndex]

    -- Check if at waypoint and waited long enough
    local currentCoords = GetEntityCoords(entity)
    local waypointCoords = waypoint.coords
    local dist = #(currentCoords - vector3(waypointCoords.x, waypointCoords.y, waypointCoords.z))

    if dist < 2.0 then
        -- At waypoint, check wait time
        local timeSinceMove = currentTime - npcInfo.lastMoveTime
        local waitTime = waypoint.waitTime or Config.Movement.patterns.patrol.waitAtPoints

        if timeSinceMove < waitTime then return end

        -- Move to next waypoint
        npcInfo.currentWaypointIndex = (waypointIndex % #locations) + 1
    end

    -- Move to current waypoint — snap target to ground level
    local targetWaypoint = locations[npcInfo.currentWaypointIndex].coords
    local patrolZ = targetWaypoint.z
    local foundGround, gZ = GetGroundZFor_3dCoord(targetWaypoint.x, targetWaypoint.y, targetWaypoint.z + 50.0, false)
    if foundGround then patrolZ = gZ end

    npcInfo.isMoving = true

    TaskGoToCoordAnyMeans(entity, targetWaypoint.x, targetWaypoint.y, patrolZ, 1.0, 0, false, 786603, 0.0)

    -- Reset when reached
    CreateThread(function()
        while npcInfo.isMoving do
            Wait(1000)
            local coords = GetEntityCoords(entity)
            local d = #(coords - vector3(targetWaypoint.x, targetWaypoint.y, patrolZ))
            if d < 2.0 then
                npcInfo.isMoving = false
                npcInfo.lastMoveTime = GetGameTimer()
                SetEntityHeading(entity, targetWaypoint.w or GetEntityHeading(entity))
            end
        end
    end)
end

function HandleScheduleMovement(npcId, npcInfo, currentTime)
    local entity = npcInfo.entity
    local npcData = npcInfo.data

    -- Get where NPC should be right now
    local targetLocation = GetNPCCurrentLocation(npcData)
    if not targetLocation then
        DespawnNPC(npcId)
        return
    end

    -- Check if already at target
    local currentCoords = GetEntityCoords(entity)
    local dist = #(currentCoords - vector3(targetLocation.x, targetLocation.y, targetLocation.z))

    if dist < 5.0 then
        -- DPS 2026-09-27: at the spot. Every so often take a short stroll nearby, stand a while,
        -- walk back and pick the pose up again, so schedule NPCs do not stand on one tile.
        StrollAroundSpot(npcInfo, targetLocation, currentTime)
        return
    end
    if npcInfo.isMoving then return end

    -- Teleport if too far (different zone), otherwise walk
    if dist > 100.0 then
        -- Too far, teleport — snap to ground to prevent floating
        local teleZ = targetLocation.z
        local foundGround, gZ = GetGroundZFor_3dCoord(targetLocation.x, targetLocation.y, targetLocation.z + 50.0, false)
        if foundGround then teleZ = gZ end

        SetEntityCoords(entity, targetLocation.x, targetLocation.y, teleZ)
        SetEntityHeading(entity, targetLocation.w)
        ApplyNPCScenario(entity, npcData)
        npcInfo.lastMoveTime = GetGameTimer()

        -- Update blip if exists
        if npcInfo.blip then
            SetBlipCoords(npcInfo.blip, targetLocation.x, targetLocation.y, targetLocation.z)
        end
    else
        -- Walk there — snap to ground level
        local walkZ = targetLocation.z
        local foundWalk, wZ = GetGroundZFor_3dCoord(targetLocation.x, targetLocation.y, targetLocation.z + 50.0, false)
        if foundWalk then walkZ = wZ end

        npcInfo.isMoving = true
        TaskGoToCoordAnyMeans(entity, targetLocation.x, targetLocation.y, walkZ, 1.0, 0, false, 786603, 0.0)

        CreateThread(function()
            while npcInfo.isMoving do
                Wait(1000)
                local coords = GetEntityCoords(entity)
                local d = #(coords - vector3(targetLocation.x, targetLocation.y, walkZ))
                if d < 2.0 then
                    npcInfo.isMoving = false
                    npcInfo.lastMoveTime = GetGameTimer()
                    SetEntityHeading(entity, targetLocation.w)
        ApplyNPCScenario(entity, npcData)
                end
            end
        end)
    end
end

function DespawnNPC(npcId, byDistance)
    local npcInfo = spawnedNPCs[npcId]
    if not npcInfo then return end

    if npcInfo.blip then
        RemoveBlip(npcInfo.blip)
    end

    if DoesEntityExist(npcInfo.entity) then
        exports.ox_target:removeLocalEntity(npcInfo.entity)
        DeleteEntity(npcInfo.entity)
    end

    spawnedNPCs[npcId] = nil
    if byDistance then
        print(("[AI NPCs] Despawned NPC: %s (out of range)"):format(npcInfo.data.name))
    else
        -- schedule closed: refresh the point at the NPC's next location and
        -- keep the 60 s schedule check so it comes back when its window opens
        RegisterNPCPoint(npcInfo.data)
        ScheduleNPCSpawn(npcInfo.data)
        print(("[AI NPCs] Despawned NPC: %s (schedule)"):format(npcInfo.data.name))
    end
end

-----------------------------------------------------------
-- CONVERSATION SYSTEM
-----------------------------------------------------------
-- DPS 2026-09-27 real-people pass: the model may end a line with [walk]. Only NPCs with a
-- quiet spot (schedule slot `quiet = vector4` or npcData.quietSpot) are offered the tag; the
-- ped then paths there properly and the talk stays open while the player follows.
function NPCQuietSpot(npcInfo)
    local data = npcInfo.data
    if data.movement and data.movement.locations then
        local hour = GetClockHours()
        for _, slot in ipairs(data.movement.locations) do
            local t = slot.time
            if t and slot.coords and slot.quiet then
                local from, to = t[1], t[2]
                local inSlot = (from <= to) and (hour >= from and hour < to) or (from > to and (hour >= from or hour < to))
                if inSlot then return slot.quiet end
            end
        end
    end
    return data.quietSpot
end

function WalkNPCToQuiet(npcInfo)
    if not npcInfo or npcInfo.walking then return end
    local quiet = NPCQuietSpot(npcInfo)
    local entity = npcInfo.entity
    if not quiet or not DoesEntityExist(entity) then return end
    npcInfo.walking = true
    CreateThread(function()
        ClearPedTasks(entity)
        Wait(100)
        TaskFollowNavMeshToCoord(entity, quiet.x, quiet.y, quiet.z, 1.0, -1, 0.4, false, quiet.w or 0.0)
        local started = GetGameTimer()
        while DoesEntityExist(entity) and activeConversation and activeConversation.npcId == npcInfo.data.id do
            Wait(250)
            local pos = GetEntityCoords(entity)
            if #(pos - vector3(quiet.x, quiet.y, quiet.z)) < 1.3 or GetGameTimer() - started > 30000 then break end
        end
        npcInfo.walking = false
        if DoesEntityExist(entity) and activeConversation and activeConversation.npcId == npcInfo.data.id then
            ClearPedTasks(entity)
            FaceThePlayer(entity)
            PlayTalkingFace(entity)
        end
    end)
end

-- Ends the talk when the player actually leaves, the way a person would notice: more than
-- 7 m away for three seconds (15 m while the NPC is walking them somewhere).
function StartConversationWatch(npcId)
    CreateThread(function()
        local away = 0
        while activeConversation and activeConversation.npcId == npcId do
            Wait(1000)
            local npcInfo = spawnedNPCs[npcId]
            if not npcInfo or not DoesEntityExist(npcInfo.entity) then break end
            local limit = npcInfo.walking and 15.0 or 7.0
            local dist = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(npcInfo.entity))
            if dist > limit then away = away + 1 else away = 0 end
            if away >= 3 then
                EndConversation()
                break
            end
        end
    end)
end

function StartConversation(npcId)
    if activeConversation then
        exports['ox_lib']:notify({
            title = 'Conversation',
            description = 'You are already talking to someone',
            type = 'error'
        })
        return
    end

    if conversationCooldown then
        exports['ox_lib']:notify({
            title = 'Conversation',
            description = 'Wait a moment before starting another conversation',
            type = 'error'
        })
        return
    end

    local npcInfo = spawnedNPCs[npcId]
    if not npcInfo then return end

    -- Stop NPC movement during conversation
    if DoesEntityExist(npcInfo.entity) then
        ClearPedTasksImmediately(npcInfo.entity)
        npcInfo.isMoving = false
        npcInfo.inConversation = true

        -- Face the player. DPS 2026-09-27: the old one-shot heading set lost to the scenario the
        -- ped was still leaving, so he stood with his back to you. Turn as a task first, then pin.
        FreezeEntityPosition(npcInfo.entity, false)
        FaceThePlayer(npcInfo.entity)

        -- Not frozen any more: the movement loop already skips NPCs in conversation, and a
        -- frozen ped cannot turn. The turn task above holds him in place facing you.

        -- Play idle talking animation
        RequestAnimDict("mp_facial")
        local timeout = 0
        while not HasAnimDictLoaded("mp_facial") and timeout < 1000 do
            Wait(10)
            timeout = timeout + 10
        end
        if HasAnimDictLoaded("mp_facial") then
            TaskPlayAnim(npcInfo.entity, "mp_facial", "mic_chatter", 3.0, -3.0, -1, 49, 0, false, false, false)
        end
    end

    activeConversation = {
        npcId = npcId,
        npc = npcInfo.data,
        paymentMade = 0
    }
    StartConversationWatch(npcId)

    -- Start conversation on server
    TriggerServerEvent('ai-npcs:server:startConversation', npcId)

    -- Open conversation UI
    OpenConversationUI(npcInfo.data)

    print(("[AI NPCs] Started conversation with %s"):format(npcInfo.data.name))
end

function OpenConversationUI(npcData)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openConversation",
        npcName = npcData.name,
        npcRole = npcData.role
    })
end

function EndConversation(reason)
    if not activeConversation then return end

    -- Restore NPC to normal state
    local npcInfo = spawnedNPCs[activeConversation.npcId]
    if npcInfo and DoesEntityExist(npcInfo.entity) then
        -- Clear animation, then go back to the spot's pose
        ClearPedTasks(npcInfo.entity)
        npcInfo.inConversation = false
        local ent, data = npcInfo.entity, npcInfo.data
        SetTimeout(600, function()
            if DoesEntityExist(ent) and not npcInfo.inConversation then
                ApplyNPCScenario(ent, data)
            end
        end)

        -- Unfreeze if NPC has movement pattern
        if npcInfo.data.movement and npcInfo.data.movement.pattern ~= "stationary" then
            FreezeEntityPosition(npcInfo.entity, false)
            npcInfo.lastMoveTime = GetGameTimer()  -- Reset move timer
        end
    end

    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "closeConversation"
    })

    if reason then
        exports['ox_lib']:notify({
            title = 'Conversation Ended',
            description = reason,
            type = 'info'
        })
    end

    TriggerServerEvent('ai-npcs:server:endConversation')
    activeConversation = nil

    -- Set cooldown
    conversationCooldown = true
    SetTimeout(Config.Interaction.cooldown, function()
        conversationCooldown = false
    end)

    print("[AI NPCs] Conversation ended")
end

-----------------------------------------------------------
-- PAYMENT SYSTEM
-----------------------------------------------------------
function ShowPaymentMenu(npcId)
    if not activeConversation or activeConversation.npcId ~= npcId then return end

    local input = exports['ox_lib']:inputDialog('Offer Payment', {
        {
            type = 'number',
            label = 'Amount ($)',
            description = 'How much cash to offer?',
            icon = 'dollar-sign',
            required = true,
            min = 100,
            max = 100000
        }
    })

    if input and input[1] then
        local amount = tonumber(input[1])
        if amount and amount > 0 then
            TriggerServerEvent('ai-npcs:server:sendMessage',
                "*hands over $" .. amount .. "*",
                amount
            )
            activeConversation.paymentMade = (activeConversation.paymentMade or 0) + amount
        end
    end
end

RegisterNetEvent('ai-npcs:client:showPaymentPrompt', function(suggestedPrice, topic, tier)
    if not activeConversation then return end

    local alert = exports['ox_lib']:alertDialog({
        header = 'Payment Required',
        content = ("This information costs around **$%s**\n\nPay for intel about: %s"):format(
            suggestedPrice, topic
        ),
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Pay $' .. suggestedPrice,
            cancel = 'Not Now'
        }
    })

    if alert == 'confirm' then
        TriggerServerEvent('ai-npcs:server:sendMessage',
            "*pays $" .. suggestedPrice .. " for information*",
            suggestedPrice
        )
        activeConversation.paymentMade = (activeConversation.paymentMade or 0) + suggestedPrice

        -- Request the intel after payment
        Wait(500)
        TriggerServerEvent('ai-npcs:server:requestIntel', topic, tier)
    end
end)

-----------------------------------------------------------
-- INPUT VALIDATION (Client-side)
-----------------------------------------------------------
local INPUT_VALIDATION = {
    maxLength = 200,       -- Max message length
    minLength = 1,         -- Min message length
    cooldownMs = 500,      -- Cooldown between messages
}

local lastMessageTime = 0

function ValidateInput(message)
    -- Check type
    if type(message) ~= "string" then
        return false, "Invalid message format"
    end

    -- Trim whitespace
    message = message:match("^%s*(.-)%s*$")

    -- Check empty
    if not message or message == "" then
        return false, "Message cannot be empty"
    end

    -- Check length
    if #message < INPUT_VALIDATION.minLength then
        return false, "Message too short"
    end

    if #message > INPUT_VALIDATION.maxLength then
        -- Truncate instead of rejecting
        message = message:sub(1, INPUT_VALIDATION.maxLength)
    end

    -- Check cooldown
    local now = GetGameTimer()
    if (now - lastMessageTime) < INPUT_VALIDATION.cooldownMs then
        return false, "Please wait before sending another message"
    end

    return true, message
end

-----------------------------------------------------------
-- NUI CALLBACKS
-----------------------------------------------------------
RegisterNUICallback('sendMessage', function(data, cb)
    if not activeConversation then
        cb('error')
        return
    end

    -- Validate input before sending
    local isValid, result = ValidateInput(data.message)
    if not isValid then
        -- Show error notification
        exports['ox_lib']:notify({
            title = 'Error',
            description = result,
            type = 'error',
            duration = 2000
        })
        cb('error')
        return
    end

    -- Update cooldown timer
    lastMessageTime = GetGameTimer()

    TriggerServerEvent('ai-npcs:server:sendMessage', result, data.payment or 0)
    cb('ok')
end)

RegisterNUICallback('endConversation', function(data, cb)
    EndConversation()
    cb('ok')
end)

RegisterNUICallback('closeUI', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('offerPayment', function(data, cb)
    if activeConversation then
        ShowPaymentMenu(activeConversation.npcId)
    end
    cb('ok')
end)

-----------------------------------------------------------
-- SERVER EVENTS
-----------------------------------------------------------
-- DPS 2026-09-27: gesture tags from the model -> upper-body clips on the NPC.
-- Every clip is in the vanilla gestures dictionaries, so nothing to stream.
local GESTURE_CLIPS = {
    shrug     = 'gesture_shrug_hard',
    nod       = 'gesture_nod_yes_hard',
    no        = 'gesture_nod_no_hard',
    point     = 'gesture_point',
    wave_off  = 'gesture_displeased',
    easy      = 'gesture_easy_now',
    you       = 'gesture_you_hard',
    hello     = 'gesture_hello',
    damn      = 'gesture_damn',
    come_here = 'gesture_come_here_soft',
    -- reactions to what the player said
    laugh     = 'gesture_shrug_soft',
    shocked   = 'gesture_damn',
    grunt     = 'gesture_displeased',
}

-- Turn the NPC toward the player: as a task (so the body actually rotates), then pin the
-- heading so nothing the ped was doing before can turn it back.
function FaceThePlayer(entity)
    if not entity or not DoesEntityExist(entity) then return end
    -- A turn task with no end keeps him facing you for the whole talk, even if you walk
    -- around him. No heading maths: the game does the turning, so it cannot end up inverted.
    SetBlockingOfNonTemporaryEvents(entity, true)
    TaskTurnPedToFaceEntity(entity, PlayerPedId(), -1)
end

function PlayTalkingFace(entity)
    if not DoesEntityExist(entity) then return end
    RequestAnimDict("mp_facial")
    local waited = 0
    while not HasAnimDictLoaded("mp_facial") and waited < 1000 do
        Wait(10)
        waited = waited + 10
    end
    if HasAnimDictLoaded("mp_facial") and DoesEntityExist(entity) then
        TaskPlayAnim(entity, "mp_facial", "mic_chatter", 3.0, -3.0, -1, 49, 0, false, false, false)
    end
end

-- Every ped model ships a voice with short lines; these are the ones that read right
-- with each gesture. Played with the gesture so the mouth matches the hands.
local GESTURE_SOUNDS = {
    shrug     = 'GENERIC_WHATEVER',
    nod       = 'GENERIC_YES',
    no        = 'GENERIC_NO',
    point     = 'CHAT_STATE',
    wave_off  = 'GENERIC_WHATEVER',
    easy      = 'CHAT_RESP',
    you       = 'PROVOKE_GENERIC',
    hello     = 'GENERIC_HI',
    damn      = 'GENERIC_CURSE_MED',
    come_here = 'GENERIC_HI',
    laugh     = 'CHAT_RESP',           -- no universal laugh line in the game voices; the closest cheerful one
    shocked   = 'GENERIC_SHOCKED_MED',
    grunt     = 'GENERIC_INSULT_MED',
}

local function PlayNPCSound(entity, gesture)
    local speech = gesture and GESTURE_SOUNDS[gesture]
    if not speech or not entity or not DoesEntityExist(entity) then return end
    PlayPedAmbientSpeechNative(entity, speech, 'SPEECH_PARAMS_FORCE_NORMAL')
end

function PlayNPCGesture(entity, gesture)
    if not gesture or not entity or not DoesEntityExist(entity) then return end
    PlayNPCSound(entity, gesture)
    local clip = GESTURE_CLIPS[gesture]
    print(("[AI NPCs] gesture %s -> %s on %s"):format(tostring(gesture), tostring(clip), tostring(entity)))
    if not clip then return end
    local dict = IsPedMale(entity) and 'gestures@m@standing@casual' or 'gestures@f@standing@casual'
    CreateThread(function()
        RequestAnimDict(dict)
        local waited = 0
        while not HasAnimDictLoaded(dict) and waited < 1000 do
            Wait(10)
            waited = waited + 10
        end
        if not HasAnimDictLoaded(dict) or not DoesEntityExist(entity) then return end
        -- The talking face sits in the secondary slot too, so drop it, play the gesture
        -- (upper body, keeps the feet planted), then bring the face back.
        ClearPedSecondaryTask(entity)
        Wait(50)
        TaskPlayAnim(entity, dict, clip, 4.0, -4.0, 2200, 48, 0, false, false, false)
        Wait(2300)
        if DoesEntityExist(entity) and activeConversation then
            PlayTalkingFace(entity)
        end
        RemoveAnimDict(dict)
    end)
end

-- Called by the hail point when a player walks past an NPC with a `hail` block.
-- Turns to the player, gives the come-here wave and voice line, and a quiet nudge on screen.
local lastHail = {}
function HailPlayer(npcId)
    local npcInfo = spawnedNPCs[npcId]
    if not npcInfo or not npcInfo.entity or not DoesEntityExist(npcInfo.entity) then return end
    if activeConversation or npcInfo.inConversation or conversationCooldown then return end
    local hail = npcInfo.data.hail or {}
    local now = GetGameTimer()
    if lastHail[npcId] and now - lastHail[npcId] < (hail.cooldownSec or 180) * 1000 then return end
    if math.random(100) > (hail.chance or 40) then
        lastHail[npcId] = now - ((hail.cooldownSec or 180) * 1000) + 30000 -- try again in 30 s
        return
    end
    lastHail[npcId] = now
    TaskTurnPedToFaceEntity(npcInfo.entity, PlayerPedId(), 2500)
    PlayNPCGesture(npcInfo.entity, 'come_here')
    exports['ox_lib']:notify({
        title = npcInfo.data.name,
        description = hail.line or 'waves you over',
        type = 'inform',
        duration = 3500,
    })
end

RegisterNetEvent('ai-npcs:client:receiveMessage', function(message, npcId, isNetworked, gesture)
    if not activeConversation or activeConversation.npcId ~= npcId then return end

    local convoNpc = spawnedNPCs[npcId]
    if convoNpc and convoNpc.entity and DoesEntityExist(convoNpc.entity) then
        if gesture == 'walk' then
            PlayNPCGesture(convoNpc.entity, 'come_here')
            WalkNPCToQuiet(convoNpc)
        else
            PlayNPCGesture(convoNpc.entity, gesture)
        end
    end

    SendNUIMessage({
        action = "receiveMessage",
        message = message,
        npcName = activeConversation.npc.name,
        gesture = gesture
    })

    -- Show subtitle if enabled
    if Config.Interaction.showSubtitles then
        exports['ox_lib']:notify({
            title = activeConversation.npc.name,
            description = message:sub(1, 100) .. (message:len() > 100 and "..." or ""),
            type = 'info',
            duration = 5000
        })
    end

    -- Trigger networked speech broadcast if enabled
    if isNetworked and Config.Sound and Config.Sound.enableNetworked then
        local npcInfo = spawnedNPCs[npcId]
        if npcInfo and npcInfo.entity and DoesEntityExist(npcInfo.entity) then
            local npcCoords = GetEntityCoords(npcInfo.entity)
            TriggerServerEvent('ai-npcs:server:broadcastSpeech', npcId, message, npcCoords)
        end
    end
end)

-- Receive networked speech from other players' NPC conversations
RegisterNetEvent('ai-npcs:client:hearNearbySpeech', function(sourcePlayer, npcId, message, npcCoords)
    -- Don't play our own broadcasts
    if sourcePlayer == GetPlayerServerId(PlayerId()) then return end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local distance = #(playerCoords - npcCoords)
    local maxDistance = Config.Sound and Config.Sound.maxDistance or 20.0

    if distance > maxDistance then return end

    -- Find NPC name from config
    local npcName = "Someone"
    for _, npc in pairs(Config.NPCs) do
        if npc.id == npcId then
            npcName = npc.name
            break
        end
    end

    -- Show subtitle for nearby players
    if Config.Interaction and Config.Interaction.showSubtitles then
        -- Volume falls off with distance
        local volume = 1.0 - (distance / maxDistance)
        if volume > 0.3 then  -- Only show if reasonably close
            exports['ox_lib']:notify({
                title = npcName .. ' (nearby)',
                description = message:sub(1, 80) .. (message:len() > 80 and "..." or ""),
                type = 'info',
                duration = 3000
            })
        end
    end
end)

-- (L3) TTS playback events removed: playAudio / playVoice / playVoiceNearby.
-- ElevenLabs is retired; NPC lines are text-only. The text "nearby speech"
-- subtitle path (hearNearbySpeech, above) is kept.

RegisterNetEvent('ai-npcs:client:endConversation', function(reason)
    EndConversation(reason)
end)

-----------------------------------------------------------
-- V2.5 SYSTEM EVENT HANDLERS
-----------------------------------------------------------
RegisterNetEvent('ai-npcs:client:intelReceived', function(intelData)
    if not intelData then return end
    exports['ox_lib']:notify({
        title = 'Intel Received',
        description = intelData.title or 'New intelligence acquired',
        type = 'success',
        duration = 8000
    })
end)

RegisterNetEvent('ai-npcs:client:showIntelList', function(intelList)
    if not intelList or #intelList == 0 then
        exports['ox_lib']:notify({
            title = 'Intel',
            description = 'No intel available from this contact',
            type = 'info'
        })
        return
    end

    local options = {}
    for _, intel in ipairs(intelList) do
        table.insert(options, {
            title = intel.title or 'Unknown Intel',
            description = string.format("Tier: %s | Price: $%d", intel.tier or '?', intel.price or 0),
            metadata = { {label = 'Topic', value = intel.topic or 'N/A'} }
        })
    end

    lib.registerContext({
        id = 'ai_npc_intel_list',
        title = 'Available Intel',
        options = options
    })
    lib.showContext('ai_npc_intel_list')
end)

RegisterNetEvent('ai-npcs:client:coopQuestStarted', function(questData)
    if not questData then return end
    exports['ox_lib']:notify({
        title = 'Co-op Quest Started',
        description = questData.title or 'A new job has begun',
        type = 'success',
        duration = 10000
    })
end)

RegisterNetEvent('ai-npcs:client:coopQuestInvite', function(questData)
    if not questData then return end
    local alert = lib.alertDialog({
        header = 'Quest Invitation',
        content = string.format("You've been invited to: **%s**\n\nAccept?", questData.title or 'Unknown Quest'),
        centered = true,
        cancel = true
    })

    if alert == 'confirm' then
        TriggerServerEvent('ai-npcs:server:acceptCoopInvite', questData.questId)
    end
end)

RegisterNetEvent('ai-npcs:client:interrogationResult', function(resultData)
    if not resultData then return end
    local notifType = resultData.success and 'success' or 'error'
    exports['ox_lib']:notify({
        title = resultData.success and 'Interrogation Success' or 'Interrogation Failed',
        description = resultData.message or (resultData.success and 'They talked.' or 'They didn\'t crack.'),
        type = notifType,
        duration = 8000
    })
end)

-----------------------------------------------------------
-- H3: QUEST ENGINE CLIENT UI (ox_lib menus)
-----------------------------------------------------------
-- NPC offered a list of jobs -> pick one to accept
RegisterNetEvent('ai-npcs:client:showQuests', function(npcId, quests)
    if not quests or #quests == 0 then
        exports['ox_lib']:notify({ title = 'Work', description = 'They\'ve got nothing for you right now.', type = 'info' })
        return
    end

    local options = {}
    for _, q in ipairs(quests) do
        local rewardBits = {}
        if q.reward then
            if q.reward.money then rewardBits[#rewardBits + 1] = ('$%d'):format(q.reward.money) end
            if q.reward.trust then rewardBits[#rewardBits + 1] = ('+%d trust'):format(q.reward.trust) end
            if q.reward.item then rewardBits[#rewardBits + 1] = (q.reward.item.name or 'item') end
        end
        options[#options + 1] = {
            title = q.title,
            description = q.description,
            metadata = {
                { label = 'Type', value = q.type or 'job' },
                { label = 'Reward', value = (#rewardBits > 0 and table.concat(rewardBits, ', ')) or 'unknown' },
            },
            onSelect = function()
                TriggerServerEvent('ai-npcs:server:acceptQuest', npcId, q.id)
            end
        }
    end

    lib.registerContext({ id = 'ai_npc_quest_offers', title = 'Available Work', options = options })
    lib.showContext('ai_npc_quest_offers')
end)

-- Player's active jobs -> report progress on the next objective
RegisterNetEvent('ai-npcs:client:showMyQuests', function(list)
    if not list or #list == 0 then
        exports['ox_lib']:notify({ title = 'Jobs', description = 'You have no active jobs.', type = 'info' })
        return
    end

    local options = {}
    for _, q in ipairs(list) do
        local nextDesc = q.nextType and ('Next: ' .. q.nextType .. (q.nextLocation and (' @ ' .. q.nextLocation) or '')) or 'Ready to finish'
        options[#options + 1] = {
            title = q.title,
            description = ('%s  (%d/%d)'):format(nextDesc, q.done or 0, q.total or 0),
            onSelect = function()
                TriggerServerEvent('ai-npcs:server:reportObjective', q.questId)
            end
        }
    end

    lib.registerContext({ id = 'ai_npc_my_quests', title = 'Active Jobs', options = options })
    lib.showContext('ai_npc_my_quests')
end)

RegisterNetEvent('ai-npcs:client:questAccepted', function(data)
    if not data then return end
    exports['ox_lib']:notify({
        title = 'New Job: ' .. (data.title or ''),
        description = data.description or 'Job accepted.',
        type = 'inform', duration = 10000
    })
end)

RegisterNetEvent('ai-npcs:client:questCompleted', function(data)
    if not data then return end
    exports['ox_lib']:notify({
        title = 'Job Complete', description = data.title or 'You finished the job.',
        type = 'success', duration = 10000
    })
end)

-- Convenience command to review/report active jobs from anywhere
-- DPS 2026-09-27 debug: /npcgesture shrug  plays a gesture on the nearest AI NPC so the clips can be checked by eye.
RegisterCommand('npcgesture', function(_, args)
    local tag = args[1] or 'shrug'
    local me = GetEntityCoords(PlayerPedId())
    local best, bestD = nil, 12.0
    for _, info in pairs(spawnedNPCs) do
        if DoesEntityExist(info.entity) then
            local d = #(GetEntityCoords(info.entity) - me)
            if d < bestD then best, bestD = info, d end
        end
    end
    if not best then print('[AI NPCs] no AI NPC within 12 m') return end
    print(("[AI NPCs] test gesture %s on %s"):format(tag, best.data.name))
    PlayNPCGesture(best.entity, tag)
end, false)

RegisterCommand('myjobs', function()
    TriggerServerEvent('ai-npcs:server:getMyQuests')
end, false)

-----------------------------------------------------------
-- CLEANUP
-----------------------------------------------------------
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    -- Remove all NPCs
    for npcId, npcInfo in pairs(spawnedNPCs) do
        if npcInfo.blip then
            RemoveBlip(npcInfo.blip)
        end
        if DoesEntityExist(npcInfo.entity) then
            exports.ox_target:removeLocalEntity(npcInfo.entity)
            DeleteEntity(npcInfo.entity)
        end
    end

    -- Close any active conversation
    if activeConversation then
        EndConversation()
    end

    print("[AI NPCs] Cleaned up NPCs")
end)

-----------------------------------------------------------
-- HELPER FUNCTIONS
-----------------------------------------------------------
function GetHeadingFromVector_2d(dx, dy)
    local heading = math.deg(math.atan(dy, dx))
    if heading < 0 then
        heading = heading + 360
    end
    return (450.0 - heading) % 360.0
end

-----------------------------------------------------------
-- LOCATION-BASED SPEECH POSITIONING
-- Resolves location inputs to world coordinates
-----------------------------------------------------------
local LOCATION_CONFIG = {
    directionalDistance = 2.5,  -- Distance for front/back/left/right
    verticalOffset = 2.0,       -- Distance for above/below
}

-- Resolve various location input types to world coordinates
-- Supports: nil, vector3, entity handle, offset table, directional strings
function ResolveLocation(location, npcEntity)
    local baseCoords

    -- Get base coordinates (NPC or player)
    if npcEntity and DoesEntityExist(npcEntity) then
        baseCoords = GetEntityCoords(npcEntity)
    else
        baseCoords = GetEntityCoords(PlayerPedId())
    end

    -- Handle nil - return base coords
    if location == nil then
        return baseCoords
    end

    -- Handle vector3 - return as-is
    if type(location) == "vector3" then
        return location
    end

    -- Handle entity handle - get entity coords
    if type(location) == "number" and DoesEntityExist(location) then
        return GetEntityCoords(location)
    end

    -- Handle offset table {x, y, z}
    if type(location) == "table" and location.x and location.y and location.z then
        return vector3(
            baseCoords.x + location.x,
            baseCoords.y + location.y,
            baseCoords.z + location.z
        )
    end

    -- Handle directional strings
    if type(location) == "string" then
        local ped = npcEntity or PlayerPedId()
        local pedCoords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        local headingRad = math.rad(heading)

        if location == "above" then
            return vector3(pedCoords.x, pedCoords.y, pedCoords.z + LOCATION_CONFIG.verticalOffset)

        elseif location == "below" then
            return vector3(pedCoords.x, pedCoords.y, pedCoords.z - LOCATION_CONFIG.verticalOffset)

        elseif location == "front" then
            local offsetX = -math.sin(headingRad) * LOCATION_CONFIG.directionalDistance
            local offsetY = math.cos(headingRad) * LOCATION_CONFIG.directionalDistance
            return vector3(pedCoords.x + offsetX, pedCoords.y + offsetY, pedCoords.z)

        elseif location == "behind" then
            local offsetX = math.sin(headingRad) * LOCATION_CONFIG.directionalDistance
            local offsetY = -math.cos(headingRad) * LOCATION_CONFIG.directionalDistance
            return vector3(pedCoords.x + offsetX, pedCoords.y + offsetY, pedCoords.z)

        elseif location == "left" then
            local leftHeadingRad = math.rad(heading + 90)
            local offsetX = -math.sin(leftHeadingRad) * LOCATION_CONFIG.directionalDistance
            local offsetY = math.cos(leftHeadingRad) * LOCATION_CONFIG.directionalDistance
            return vector3(pedCoords.x + offsetX, pedCoords.y + offsetY, pedCoords.z)

        elseif location == "right" then
            local rightHeadingRad = math.rad(heading - 90)
            local offsetX = -math.sin(rightHeadingRad) * LOCATION_CONFIG.directionalDistance
            local offsetY = math.cos(rightHeadingRad) * LOCATION_CONFIG.directionalDistance
            return vector3(pedCoords.x + offsetX, pedCoords.y + offsetY, pedCoords.z)
        end
    end

    -- Fallback to base coords
    return baseCoords
end

-- Play audio at a resolved location
function PlayAudioAtLocation(soundName, soundSet, location, npcEntity, range)
    local coords = ResolveLocation(location, npcEntity)
    range = range or 15.0

    PlaySoundFromCoord(-1, soundName, coords.x, coords.y, coords.z, soundSet, false, range, false)

    return coords
end

-- Export for external use
exports('ResolveLocation', ResolveLocation)
exports('PlayAudioAtLocation', PlayAudioAtLocation)
