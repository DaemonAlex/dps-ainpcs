-----------------------------------------------------------
-- DISCORD WEBHOOK LOGGING WITH BATCHING
-- Inspired by mad_goon's logging system
-----------------------------------------------------------
local QBCore = exports['qb-core']:GetCoreObject()

-- Log queue for batching
local logQueue = {}  -- { [webhookType] = { embeds } }
local LOG_BATCH_SIZE = 10
local LOG_FLUSH_INTERVAL = 60000  -- 1 minute

-----------------------------------------------------------
-- CONFIG (add these to your config.lua)
-----------------------------------------------------------
--[[
Config.Logs = {
    enabled = true,
    authorName = '🤖 AI NPCs',
    username = 'AI NPCs Logs',
    iconUrl = 'https://cdn-icons-png.flaticon.com/512/4712/4712109.png',
    tagType = '@everyone',  -- or a role ID like '<@&1234567890>'

    -- Webhook URLs per log type
    webhooks = {
        conversation = '',  -- Webhook for conversation logs
        trust = '',         -- Webhook for trust changes
        intel = '',         -- Webhook for intel purchases
        quest = '',         -- Webhook for quest completions
        error = '',         -- Webhook for errors
    },

    -- What to log
    logConversations = true,
    logTrustChanges = false,
    logIntelPurchases = true,
    logQuestCompletions = true,
    logErrors = true,

    -- Tag settings
    tagOnConversation = false,
    tagOnError = true,
}
]]

-----------------------------------------------------------
-- HELPER FUNCTIONS
-----------------------------------------------------------
local function GetPlayerIdentifiers(playerId)
    local identifiers = {
        steam = nil,
        license = nil,
        discord = nil,
        fivem = nil,
        ip = nil,
    }

    for _, id in ipairs(GetPlayerIdentifiers(playerId)) do
        if string.find(id, "steam:") then
            identifiers.steam = id
        elseif string.find(id, "license:") then
            identifiers.license = id
        elseif string.find(id, "discord:") then
            identifiers.discord = id:gsub("discord:", "")
        elseif string.find(id, "fivem:") then
            identifiers.fivem = id
        elseif string.find(id, "ip:") then
            identifiers.ip = id
        end
    end

    return identifiers
end

local function FormatIdentifiers(identifiers)
    local parts = {}

    if identifiers.discord then
        table.insert(parts, ("**Discord:** <@%s>"):format(identifiers.discord))
    end
    if identifiers.steam then
        table.insert(parts, ("**Steam:** `%s`"):format(identifiers.steam))
    end
    if identifiers.license then
        table.insert(parts, ("**License:** `%s`"):format(identifiers.license:sub(1, 20) .. "..."))
    end
    if identifiers.fivem then
        table.insert(parts, ("**FiveM:** `%s`"):format(identifiers.fivem))
    end

    return table.concat(parts, "\n")
end

local function GetTimestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

local function GetColor(logType)
    local colors = {
        conversation = 3447003,  -- Blue
        trust = 15844367,        -- Gold
        intel = 10181046,        -- Purple
        quest = 3066993,         -- Green
        error = 15158332,        -- Red
        info = 9807270,          -- Gray
    }
    return colors[logType] or colors.info
end

-----------------------------------------------------------
-- CORE LOGGING FUNCTIONS
-----------------------------------------------------------
function CreateLogEmbed(logType, title, fields, playerId)
    local config = Config.Logs or {}
    if not config.enabled then return nil end

    local embed = {
        title = title,
        color = GetColor(logType),
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        footer = {
            text = GetTimestamp()
        },
        author = {
            name = config.authorName or '🤖 AI NPCs',
            icon_url = config.iconUrl
        },
        fields = fields or {}
    }

    -- Add player identifiers if provided
    if playerId then
        local Player = QBCore.Functions.GetPlayer(playerId)
        if Player then
            local charName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
            local identifiers = GetPlayerIdentifiers(playerId)

            table.insert(embed.fields, 1, {
                name = "Player",
                value = ("**%s** (ID: %d)"):format(charName, playerId),
                inline = true
            })

            if Config.Logs.includeIdentifiers ~= false then
                table.insert(embed.fields, {
                    name = "Identifiers",
                    value = FormatIdentifiers(identifiers),
                    inline = false
                })
            end
        end
    end

    return embed
end

function QueueLog(logType, embed, shouldTag)
    local config = Config.Logs or {}
    if not config.enabled then return end

    local webhook = config.webhooks and config.webhooks[logType]
    if not webhook or webhook == '' then
        -- Fall back to default/error webhook
        webhook = config.webhooks and config.webhooks.error
        if not webhook or webhook == '' then
            return  -- No webhook configured
        end
    end

    -- Initialize queue for this webhook
    if not logQueue[webhook] then
        logQueue[webhook] = {
            embeds = {},
            shouldTag = false
        }
    end

    table.insert(logQueue[webhook].embeds, embed)

    -- Track if any log in batch should tag
    if shouldTag then
        logQueue[webhook].shouldTag = true
    end

    -- Flush if batch is full
    if #logQueue[webhook].embeds >= LOG_BATCH_SIZE then
        FlushLogs(webhook)
    end
end

function FlushLogs(specificWebhook)
    local config = Config.Logs or {}

    local function sendToWebhook(webhook, data)
        local payload = {
            username = config.username or 'AI NPCs Logs',
            embeds = data.embeds
        }

        -- Add content for tagging if needed
        if data.shouldTag and config.tagType then
            payload.content = config.tagType
        end

        PerformHttpRequest(webhook, function(statusCode, response)
            if statusCode ~= 200 and statusCode ~= 204 then
                print(("[AI NPCs] Failed to send logs to Discord: %s"):format(statusCode))
            end
        end, 'POST', json.encode(payload), {
            ["Content-Type"] = "application/json"
        })
    end

    if specificWebhook then
        -- Flush specific webhook
        if logQueue[specificWebhook] and #logQueue[specificWebhook].embeds > 0 then
            sendToWebhook(specificWebhook, logQueue[specificWebhook])
            logQueue[specificWebhook] = { embeds = {}, shouldTag = false }
        end
    else
        -- Flush all webhooks
        for webhook, data in pairs(logQueue) do
            if #data.embeds > 0 then
                sendToWebhook(webhook, data)
                logQueue[webhook] = { embeds = {}, shouldTag = false }
            end
        end
    end
end

-- Periodic flush (every minute)
CreateThread(function()
    while true do
        Wait(LOG_FLUSH_INTERVAL)
        FlushLogs()
    end
end)

-- Flush on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        FlushLogs()
    end
end)

-----------------------------------------------------------
-- LOG TYPE FUNCTIONS
-----------------------------------------------------------

-- Log a conversation message
function LogConversation(playerId, npcId, npcName, playerMessage, aiResponse)
    local config = Config.Logs or {}
    if not config.logConversations then return end

    local embed = CreateLogEmbed('conversation',
        ("💬 Conversation with %s"):format(npcName),
        {
            { name = "NPC", value = npcName, inline = true },
            { name = "NPC ID", value = npcId, inline = true },
            { name = "Player Message", value = ("```%s```"):format(playerMessage:sub(1, 500)), inline = false },
            { name = "AI Response", value = ("```%s```"):format(aiResponse:sub(1, 500)), inline = false },
        },
        playerId
    )

    if embed then
        QueueLog('conversation', embed, config.tagOnConversation)
    end
end

-- Log trust changes
function LogTrustChange(playerId, npcId, npcName, oldTrust, newTrust, reason)
    local config = Config.Logs or {}
    if not config.logTrustChanges then return end

    local change = newTrust - oldTrust
    local emoji = change > 0 and "📈" or "📉"

    local embed = CreateLogEmbed('trust',
        ("%s Trust Changed: %s"):format(emoji, npcName),
        {
            { name = "NPC", value = npcName, inline = true },
            { name = "Change", value = ("%+d"):format(change), inline = true },
            { name = "New Trust", value = ("%d/100"):format(newTrust), inline = true },
            { name = "Reason", value = reason or "Unknown", inline = false },
        },
        playerId
    )

    if embed then
        QueueLog('trust', embed, false)
    end
end

-- Log intel purchases
function LogIntelPurchase(playerId, npcId, npcName, topic, tier, price)
    local config = Config.Logs or {}
    if not config.logIntelPurchases then return end

    local embed = CreateLogEmbed('intel',
        ("🔍 Intel Purchased from %s"):format(npcName),
        {
            { name = "NPC", value = npcName, inline = true },
            { name = "Topic", value = topic, inline = true },
            { name = "Tier", value = tier, inline = true },
            { name = "Price", value = ("$%d"):format(price), inline = true },
        },
        playerId
    )

    if embed then
        QueueLog('intel', embed, false)
    end
end

-- Log quest completions
function LogQuestCompletion(playerId, npcId, npcName, questId, trustReward)
    local config = Config.Logs or {}
    if not config.logQuestCompletions then return end

    local embed = CreateLogEmbed('quest',
        ("✅ Quest Completed: %s"):format(questId),
        {
            { name = "NPC", value = npcName, inline = true },
            { name = "Quest ID", value = questId, inline = true },
            { name = "Trust Reward", value = ("+%d"):format(trustReward or 0), inline = true },
        },
        playerId
    )

    if embed then
        QueueLog('quest', embed, false)
    end
end

-- Log errors
function LogError(errorType, errorMessage, playerId, additionalData)
    local config = Config.Logs or {}
    if not config.logErrors then return end

    local fields = {
        { name = "Error Type", value = errorType, inline = true },
        { name = "Message", value = ("```%s```"):format(errorMessage:sub(1, 1000)), inline = false },
    }

    if additionalData then
        for key, value in pairs(additionalData) do
            table.insert(fields, {
                name = key,
                value = tostring(value):sub(1, 500),
                inline = true
            })
        end
    end

    local embed = CreateLogEmbed('error',
        ("❌ Error: %s"):format(errorType),
        fields,
        playerId
    )

    if embed then
        QueueLog('error', embed, config.tagOnError)
    end
end

-----------------------------------------------------------
-- EXPORTS
-----------------------------------------------------------
exports('LogConversation', LogConversation)
exports('LogTrustChange', LogTrustChange)
exports('LogIntelPurchase', LogIntelPurchase)
exports('LogQuestCompletion', LogQuestCompletion)
exports('LogError', LogError)
exports('FlushLogs', FlushLogs)

print("^2[AI NPCs]^7 Discord logging system loaded")
