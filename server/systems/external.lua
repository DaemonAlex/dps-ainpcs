-- External NPCs: talking NPCs whose ped another resource spawns and owns (shop clerks from dps-shops, for example).
-- That resource registers the character here; everything about talking (the model, voice, memory, trust, rate
-- limits) stays this resource's own config. Each reply can also carry live facts the owner supplies through an
-- export (stock, prices, what just happened), so the NPC knows what is true right now.
ExternalNPCs = ExternalNPCs or {}

local function publish()
    local slim = {}
    for _, d in pairs(ExternalNPCs) do
        slim[#slim + 1] = { id = d.id, name = d.name, external = true }
    end
    GlobalState['dps-ainpcs:external'] = slim
end

--- def = { id, name, homeLocation = vector4|vector3, systemPrompt, voiceSamples?, calibration?, voice? (a Config.Voices
---         key or a voice id), trustCategory?, contextExport? = { resource, name } }
--- contextExport is called as exports[resource][name](npcId, playerSource) and returns a string of plain facts.
exports('RegisterExternalNPC', function(def)
    if type(def) ~= 'table' or type(def.id) ~= 'string' or type(def.name) ~= 'string' then return false end
    for _, npc in pairs(Config.NPCs) do
        if npc.id == def.id then return false end   -- never shadow a configured NPC
    end
    def.voice = (type(def.voice) == 'string' and Config.Voices and Config.Voices[def.voice]) or def.voice
    def.trustCategory = def.trustCategory or 'civilian'
    def.movement = { pattern = 'stationary' }
    def.systemPrompt = def.systemPrompt or ('You are ' .. def.name .. '.')
    def.external = true
    def._owner = GetInvokingResource() or GetCurrentResourceName()
    ExternalNPCs[def.id] = def
    publish()
    return true
end)

exports('UnregisterExternalNPC', function(id)
    ExternalNPCs[id] = nil
    publish()
end)

AddEventHandler('onResourceStop', function(res)
    local changed = false
    for id, d in pairs(ExternalNPCs) do
        if d._owner == res then ExternalNPCs[id] = nil; changed = true end
    end
    if changed then publish() end
end)

--- The owner's live facts for this NPC and player, or nil. Never throws.
function ExternalNPCContext(npc, playerSource)
    local ce = npc and npc.contextExport
    if not ce or GetResourceState(ce.resource) ~= 'started' then return nil end
    local ok, text = pcall(function()
        local res = exports[ce.resource]
        return res[ce.name](res, npc.id, playerSource)
    end)
    if ok and type(text) == 'string' and text ~= '' then return text end
    if not ok then print(('[AI NPCs] context from %s failed: %s'):format(ce.resource, tostring(text))) end
    return nil
end

publish()
