-----------------------------------------------------------
-- TOKEN BUCKET RATE LIMITING (Per-Player)
-- Algorithm: Each player has a bucket with max 5 tokens
-- Tokens refill at 1 per 12 seconds (5 per minute)
-- Each AI request consumes 1 token
-----------------------------------------------------------
local playerBuckets = {}  -- { [playerId] = { tokens, lastRefill } }
local requestQueue = {}
local isProcessingQueue = false
local lastRequestTime = 0
local pendingRequests = {}  -- Track pending requests per player
local currentConcurrent = 0

-- Token Bucket configuration (per-player limits)
local TOKEN_BUCKET = {
    maxTokens = 5,              -- Max tokens per player (burst capacity)
    refillRate = 5,             -- Tokens per minute
    refillIntervalMs = 12000,   -- 1 token every 12 seconds (60000/5)
}

-- Global Token Budget (server-wide limits to prevent overloading local models)
local GLOBAL_TOKEN_BUDGET = {
    enabled = false,            -- Enable via Config.AI.globalBudget
    maxTokensPerMinute = 1000,  -- Server-wide tokens per minute
    currentUsage = 0,           -- Tokens used this minute
    lastReset = 0,              -- Last reset timestamp
}

-- Global stagger configuration (prevents API burst)
local GLOBAL_STAGGER = {
    minDelayMs = 300,           -- Minimum ms between any API calls
    maxConcurrent = 5,          -- Max concurrent API requests
    requestTimeoutMs = 30000,   -- 30 second timeout per request (cloud APIs)
    ollamaTimeoutMs = 120000,   -- 120 second timeout for local Ollama (slower)
}

-----------------------------------------------------------
-- Token Bucket Management
-----------------------------------------------------------
function GetPlayerBucket(playerId)
    local currentTime = GetGameTimer()

    if not playerBuckets[playerId] then
        -- Initialize new bucket at full capacity
        playerBuckets[playerId] = {
            tokens = TOKEN_BUCKET.maxTokens,
            lastRefill = currentTime
        }
    end

    local bucket = playerBuckets[playerId]

    -- Refill tokens based on time elapsed
    local elapsed = currentTime - bucket.lastRefill
    local tokensToAdd = math.floor(elapsed / TOKEN_BUCKET.refillIntervalMs)

    if tokensToAdd > 0 then
        bucket.tokens = math.min(TOKEN_BUCKET.maxTokens, bucket.tokens + tokensToAdd)
        bucket.lastRefill = bucket.lastRefill + (tokensToAdd * TOKEN_BUCKET.refillIntervalMs)
    end

    return bucket
end

function ConsumeToken(playerId)
    local bucket = GetPlayerBucket(playerId)

    if bucket.tokens > 0 then
        bucket.tokens = bucket.tokens - 1
        return true
    end

    return false
end

function GetTokensRemaining(playerId)
    local bucket = GetPlayerBucket(playerId)
    return bucket.tokens
end

function GetTimeUntilNextToken(playerId)
    local bucket = GetPlayerBucket(playerId)
    if bucket.tokens >= TOKEN_BUCKET.maxTokens then
        return 0
    end

    local currentTime = GetGameTimer()
    local elapsed = currentTime - bucket.lastRefill
    local remaining = TOKEN_BUCKET.refillIntervalMs - elapsed

    return math.max(0, remaining)
end

-----------------------------------------------------------
-- Global Token Budget Management (Server-Wide Limits)
-----------------------------------------------------------
function InitGlobalTokenBudget()
    if Config.AI and Config.AI.globalBudget then
        GLOBAL_TOKEN_BUDGET.enabled = Config.AI.globalBudget.enabled or false
        GLOBAL_TOKEN_BUDGET.maxTokensPerMinute = Config.AI.globalBudget.maxTokensPerMinute or 1000
    end
    GLOBAL_TOKEN_BUDGET.lastReset = GetGameTimer()

    if Config.Debug and Config.Debug.enabled and GLOBAL_TOKEN_BUDGET.enabled then
        print(("[AI NPCs] Global Token Budget: %d tokens/minute"):format(GLOBAL_TOKEN_BUDGET.maxTokensPerMinute))
    end
end

function CheckGlobalBudget(estimatedTokens)
    if not GLOBAL_TOKEN_BUDGET.enabled then return true end

    local currentTime = GetGameTimer()

    -- Reset budget every minute
    if currentTime - GLOBAL_TOKEN_BUDGET.lastReset >= 60000 then
        GLOBAL_TOKEN_BUDGET.currentUsage = 0
        GLOBAL_TOKEN_BUDGET.lastReset = currentTime
    end

    return (GLOBAL_TOKEN_BUDGET.currentUsage + estimatedTokens) <= GLOBAL_TOKEN_BUDGET.maxTokensPerMinute
end

function ConsumeGlobalBudget(tokens)
    if not GLOBAL_TOKEN_BUDGET.enabled then return end
    GLOBAL_TOKEN_BUDGET.currentUsage = GLOBAL_TOKEN_BUDGET.currentUsage + tokens
end

function GetGlobalBudgetRemaining()
    if not GLOBAL_TOKEN_BUDGET.enabled then return -1 end -- -1 means unlimited
    return math.max(0, GLOBAL_TOKEN_BUDGET.maxTokensPerMinute - GLOBAL_TOKEN_BUDGET.currentUsage)
end

function GetTimeUntilBudgetReset()
    if not GLOBAL_TOKEN_BUDGET.enabled then return 0 end
    local currentTime = GetGameTimer()
    local elapsed = currentTime - GLOBAL_TOKEN_BUDGET.lastReset
    return math.max(0, 60000 - elapsed)
end

-----------------------------------------------------------
-- Request Queue with Token Bucket
-----------------------------------------------------------
function QueueAIRequest(playerId, conversation, playerMessage)
    -- Check if player already has a pending request
    if pendingRequests[playerId] then
        TriggerClientEvent('ai-npcs:client:receiveMessage', playerId,
            "*holds up a finger* Hold on, I'm still thinking...", conversation.npc.id)
        return
    end

    -- Check global token budget (server-wide limit for local models)
    local estimatedTokens = Config.AI.maxTokens or 200
    if not CheckGlobalBudget(estimatedTokens) then
        local waitTime = math.ceil(GetTimeUntilBudgetReset() / 1000)
        TriggerClientEvent('ai-npcs:client:receiveMessage', playerId,
            ("*looks distracted* The city's busy right now... Try again in %ds."):format(waitTime), conversation.npc.id)

        if Config.Debug and Config.Debug.enabled then
            print(("[AI NPCs] Player %s blocked by global budget - %d remaining, reset in %ds"):format(
                playerId, GetGlobalBudgetRemaining(), waitTime))
        end
        return
    end

    -- Check if player has tokens available
    local tokensRemaining = GetTokensRemaining(playerId)

    if tokensRemaining <= 0 then
        -- No tokens - inform player and queue anyway (will process when token available)
        local waitTime = math.ceil(GetTimeUntilNextToken(playerId) / 1000)
        TriggerClientEvent('ai-npcs:client:receiveMessage', playerId,
            ("*seems busy* Give me a moment... (%ds)"):format(waitTime), conversation.npc.id)

        if Config.Debug and Config.Debug.enabled then
            print(("[AI NPCs] Player %s rate limited - %d tokens, wait %ds"):format(
                playerId, tokensRemaining, waitTime))
        end
    end

    -- Add to queue
    table.insert(requestQueue, {
        playerId = playerId,
        conversation = conversation,
        playerMessage = playerMessage,
        queuedAt = GetGameTimer()
    })

    pendingRequests[playerId] = true

    -- Start processing if not already
    if not isProcessingQueue then
        ProcessRequestQueue()
    end
end

function ProcessRequestQueue()
    if #requestQueue == 0 then
        isProcessingQueue = false
        return
    end

    isProcessingQueue = true
    local currentTime = GetGameTimer()

    -- Check global concurrent limit (stagger)
    if currentConcurrent >= GLOBAL_STAGGER.maxConcurrent then
        SetTimeout(500, ProcessRequestQueue)
        return
    end

    -- Check global minimum delay (stagger)
    local timeSinceLastRequest = currentTime - lastRequestTime
    if timeSinceLastRequest < GLOBAL_STAGGER.minDelayMs then
        SetTimeout(GLOBAL_STAGGER.minDelayMs - timeSinceLastRequest, ProcessRequestQueue)
        return
    end

    -- Find next request that has tokens available
    local requestIndex = nil
    for i, request in ipairs(requestQueue) do
        -- Check if request is too old (player might have left)
        if currentTime - request.queuedAt > 60000 then
            pendingRequests[request.playerId] = nil
            table.remove(requestQueue, i)
            -- Recurse to check next
            SetTimeout(0, ProcessRequestQueue)
            return
        end

        -- Check if player has tokens
        if GetTokensRemaining(request.playerId) > 0 then
            requestIndex = i
            break
        end
    end

    if not requestIndex then
        -- No requests with available tokens - wait for token refill
        local minWait = TOKEN_BUCKET.refillIntervalMs
        for _, request in ipairs(requestQueue) do
            local wait = GetTimeUntilNextToken(request.playerId)
            if wait < minWait then
                minWait = wait
            end
        end

        if Config.Debug.enabled then
            print(("[AI NPCs] All players rate-limited, waiting %dms for token refill"):format(minWait))
        end

        SetTimeout(minWait + 100, ProcessRequestQueue)
        return
    end

    -- Get the request and consume token
    local request = table.remove(requestQueue, requestIndex)

    if not ConsumeToken(request.playerId) then
        -- Token was consumed between check and now (race condition), requeue
        table.insert(requestQueue, 1, request)
        SetTimeout(100, ProcessRequestQueue)
        return
    end

    -- Process the request
    lastRequestTime = currentTime
    currentConcurrent = currentConcurrent + 1

    if Config.Debug.enabled then
        print(("[AI NPCs] Processing request for player %s (%d tokens remaining)"):format(
            request.playerId, GetTokensRemaining(request.playerId)))
    end

    GenerateAIResponseInternal(request.playerId, request.conversation, request.playerMessage, function()
        currentConcurrent = currentConcurrent - 1
        pendingRequests[request.playerId] = nil
        -- Process next request with stagger delay
        SetTimeout(GLOBAL_STAGGER.minDelayMs, ProcessRequestQueue)
    end)
end

-----------------------------------------------------------
-- Cleanup disconnected players
-----------------------------------------------------------
AddEventHandler('playerDropped', function(reason)
    local playerId = source
    playerBuckets[playerId] = nil
    pendingRequests[playerId] = nil

    -- Remove any queued requests for this player
    for i = #requestQueue, 1, -1 do
        if requestQueue[i].playerId == playerId then
            table.remove(requestQueue, i)
        end
    end
end)

-----------------------------------------------------------
-- FALLBACK DIALOGUE SYSTEM (uses Config.FallbackResponses)
-----------------------------------------------------------
function GetFallbackResponse(npc, reason)
    local category = "generic"

    -- Determine category based on NPC trust category
    if npc.trustCategory then
        if npc.trustCategory == "criminal" or npc.trustCategory == "gang" then
            category = "criminal"
        elseif npc.trustCategory == "professional" or npc.trustCategory == "legitimate" then
            category = "legitimate"
        elseif npc.trustCategory == "service" then
            category = "service"
        end
    end

    -- Use specific error messages for different failure types
    if reason == "api_error" or reason == "timeout" then
        category = "api_error"
    elseif reason == "ollama_timeout" then
        -- Specific message for slow local model
        return "*pauses mid-thought* ...Give me a second, thinking takes time."
    elseif reason == "ollama_offline" then
        -- Specific message for offline local model
        return "*stares blankly* ...I'm not feeling myself right now. Come back later."
    elseif reason == "connection_error" then
        return "*seems disconnected* ...Can't think straight right now."
    elseif reason == "server_error" then
        return "*winces* ...Brain's not working. Try again in a minute."
    end

    -- Get from config, fallback to generic if category missing
    local responses = Config.FallbackResponses and Config.FallbackResponses[category]
    if not responses or #responses == 0 then
        responses = Config.FallbackResponses and Config.FallbackResponses.generic
    end

    -- Ultimate fallback if config is missing entirely
    if not responses or #responses == 0 then
        return "*looks distracted* Sorry, what were you saying?"
    end

    return responses[math.random(#responses)]
end

-----------------------------------------------------------
-- AI Response Generation with Full Context
-----------------------------------------------------------
function GenerateAIResponse(playerId, conversation, playerMessage)
    -- Use the queue system instead of direct call
    QueueAIRequest(playerId, conversation, playerMessage)
end

function GenerateAIResponseInternal(playerId, conversation, playerMessage, onComplete)
    local npc = conversation.npc
    local playerContext = conversation.playerContext

    -- Build the enhanced system prompt with context
    local systemPrompt = BuildContextualSystemPrompt(npc, playerContext, conversation)

    -- Build conversation history for API
    local messages = {}

    -- Add conversation history
    for _, msg in ipairs(conversation.conversationHistory) do
        table.insert(messages, msg)
    end

    -- Prepare API request based on provider
    local requestData, headers, apiUrl
    local provider = Config.AI.provider or "openai"

    if provider == "anthropic" then
        -- Anthropic Claude API format
        requestData = {
            model = Config.AI.model,
            messages = messages,
            max_tokens = Config.AI.maxTokens,
            temperature = Config.AI.temperature,
            system = systemPrompt
        }

        headers = {
            ["Content-Type"] = "application/json",
            ["x-api-key"] = Config.AI.apiKey,
            ["anthropic-version"] = "2023-06-01"
        }
        apiUrl = Config.AI.apiUrl

    elseif provider == "ollama" then
        -- Native Ollama API format (local LLM)
        -- Ollama can use either native /api/chat or OpenAI-compatible /v1/chat/completions
        local useNativeApi = Config.AI.ollamaNativeApi ~= false -- Default to native

        if useNativeApi then
            -- Native Ollama /api/chat endpoint
            requestData = {
                model = Config.AI.model,
                messages = {},
                stream = false, -- FiveM can't handle streaming
                options = {
                    temperature = Config.AI.temperature or 0.85,
                    num_predict = Config.AI.maxTokens or 200,
                }
            }

            -- Add system prompt as first message for Ollama
            table.insert(requestData.messages, {
                role = "system",
                content = systemPrompt
            })

            -- Add conversation history
            for _, msg in ipairs(messages) do
                table.insert(requestData.messages, msg)
            end

            apiUrl = (Config.AI.apiUrl or "http://127.0.0.1:11434") .. "/api/chat"
        else
            -- OpenAI-compatible endpoint (for Ollama with /v1/chat/completions)
            table.insert(messages, 1, {
                role = "system",
                content = systemPrompt
            })

            requestData = {
                model = Config.AI.model,
                messages = messages,
                max_tokens = Config.AI.maxTokens,
                temperature = Config.AI.temperature
            }

            apiUrl = (Config.AI.apiUrl or "http://127.0.0.1:11434") .. "/v1/chat/completions"
        end

        -- Ollama doesn't need auth for local, but support optional key for remote
        headers = {
            ["Content-Type"] = "application/json"
        }
        if Config.AI.apiKey and Config.AI.apiKey ~= "" and Config.AI.apiKey ~= "not-needed" then
            headers["Authorization"] = "Bearer " .. Config.AI.apiKey
        end

    else
        -- OpenAI API format (default) - also works with OpenAI-compatible APIs
        table.insert(messages, 1, {
            role = "system",
            content = systemPrompt
        })

        requestData = {
            model = Config.AI.model,
            messages = messages,
            max_tokens = Config.AI.maxTokens,
            temperature = Config.AI.temperature
        }

        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. (Config.AI.apiKey or "")
        }
        apiUrl = Config.AI.apiUrl
    end

    -- Timeout tracking - use longer timeout for local Ollama models
    local requestId = GetGameTimer()
    local hasResponded = false
    local timeoutTriggered = false
    local timeoutMs = (provider == "ollama") and GLOBAL_STAGGER.ollamaTimeoutMs or GLOBAL_STAGGER.requestTimeoutMs

    -- Set up timeout handler with enhanced error info
    SetTimeout(timeoutMs, function()
        if not hasResponded then
            timeoutTriggered = true
            local providerInfo = provider == "ollama" and " (local model may be slow/unresponsive)" or ""
            print(("[AI NPCs] Request timeout for player %s after %dms%s"):format(playerId, timeoutMs, providerInfo))

            -- Provider-specific timeout messages
            local fallbackReason = "timeout"
            if provider == "ollama" then
                fallbackReason = "ollama_timeout"
            end

            local fallback = GetFallbackResponse(npc, fallbackReason)
            TriggerClientEvent('ai-npcs:client:receiveMessage', playerId, fallback, npc.id)

            -- Log additional debug info for Ollama timeouts
            if provider == "ollama" and Config.Debug and Config.Debug.enabled then
                print("[AI NPCs] Ollama timeout - check if:")
                print("  1. Ollama is running: curl " .. (Config.AI.apiUrl or "http://127.0.0.1:11434"))
                print("  2. Model is loaded: ollama list")
                print("  3. GPU has enough VRAM for model")
            end

            if onComplete then onComplete() end
        end
    end)

    -- Make API request
    PerformHttpRequest(apiUrl, function(statusCode, response, respHeaders)
        -- Ignore if timeout already triggered
        if timeoutTriggered then return end
        hasResponded = true

        if statusCode == 200 then
            local success, data = pcall(json.decode, response)
            local aiResponse = nil
            local tokensUsed = Config.AI.maxTokens or 200 -- Estimate if not provided

            if success then
                if provider == "anthropic" and data.content and data.content[1] then
                    -- Anthropic Claude response
                    aiResponse = data.content[1].text
                    if data.usage then
                        tokensUsed = data.usage.output_tokens or tokensUsed
                    end
                elseif provider == "ollama" and data.message then
                    -- Native Ollama /api/chat response
                    aiResponse = data.message.content
                    -- Ollama provides eval_count for tokens generated
                    if data.eval_count then
                        tokensUsed = data.eval_count
                    end
                elseif data.choices and data.choices[1] then
                    -- OpenAI / OpenAI-compatible response (including Ollama /v1/)
                    aiResponse = data.choices[1].message.content
                    if data.usage then
                        tokensUsed = data.usage.completion_tokens or tokensUsed
                    end
                end

                -- Consume global token budget
                ConsumeGlobalBudget(tokensUsed)
            end

            if aiResponse then
                -- Clean up response
                aiResponse = CleanAIResponse(aiResponse)

                -- Add AI response to conversation history
                table.insert(conversation.conversationHistory, {
                    role = "assistant",
                    content = aiResponse
                })

                -- Send response to client (with networked flag for broadcast)
                local isNetworked = Config.Sound and Config.Sound.enableNetworked or false
                TriggerClientEvent('ai-npcs:client:receiveMessage', playerId, aiResponse, npc.id, isNetworked)

                -- Generate TTS if enabled (decoupled from message display)
                -- This sends a separate event for voice playback
                if Config.TTS.enabled and Config.TTS.apiKey ~= "YOUR_ELEVENLABS_KEY_HERE" then
                    GenerateTTS(playerId, aiResponse, npc.voice or Config.TTS.defaultVoice, npc.id, isNetworked)
                end

                if Config.Debug.printResponses then
                    print(("[AI NPCs] %s says: %s"):format(npc.name, aiResponse:sub(1, 80) .. "..."))
                end
            else
                print("[AI NPCs] Failed to parse AI response")
                print("[AI NPCs] Raw response: " .. tostring(response))
                local fallback = GetFallbackResponse(npc, "parse_error")
                TriggerClientEvent('ai-npcs:client:receiveMessage', playerId, fallback, npc.id)
            end
        elseif statusCode == 429 then
            -- Rate limited by API
            print("[AI NPCs] API rate limit hit (429)")
            local fallback = GetFallbackResponse(npc, "api_error")
            TriggerClientEvent('ai-npcs:client:receiveMessage', playerId, fallback, npc.id)
        elseif statusCode == 0 or statusCode == nil then
            -- Connection failed - likely Ollama not running or network issue
            print(("[AI NPCs] Connection failed to %s (provider: %s)"):format(apiUrl, provider))

            if provider == "ollama" then
                print("[AI NPCs] Ollama connection failed - troubleshooting:")
                print("  1. Is Ollama running? Start with: ollama serve")
                print("  2. Check endpoint: " .. apiUrl)
                print("  3. Test with: curl " .. apiUrl)
                print("  4. Model loaded? ollama pull " .. (Config.AI.model or "dolphin-llama3:8b"))
                local fallback = GetFallbackResponse(npc, "ollama_offline")
                TriggerClientEvent('ai-npcs:client:receiveMessage', playerId, fallback, npc.id)
            else
                local fallback = GetFallbackResponse(npc, "connection_error")
                TriggerClientEvent('ai-npcs:client:receiveMessage', playerId, fallback, npc.id)
            end
        elseif statusCode >= 500 then
            -- Server error
            print(("[AI NPCs] Server error %d from %s"):format(statusCode, provider))
            if provider == "ollama" then
                print("[AI NPCs] Ollama server error - model may have crashed or OOM")
            end
            local fallback = GetFallbackResponse(npc, "server_error")
            TriggerClientEvent('ai-npcs:client:receiveMessage', playerId, fallback, npc.id)
        else
            print(("[AI NPCs] AI API request failed with status: %s (provider: %s)"):format(statusCode, provider))
            print("[AI NPCs] Response: " .. tostring(response))
            local fallback = GetFallbackResponse(npc, "api_error")
            TriggerClientEvent('ai-npcs:client:receiveMessage', playerId, fallback, npc.id)
        end

        if onComplete then onComplete() end
    end, 'POST', json.encode(requestData), headers)
end

-----------------------------------------------------------
-- Build Context-Aware System Prompt (v2.5 Enhanced)
-----------------------------------------------------------
function BuildContextualSystemPrompt(npc, playerContext, conversation)
    local prompt = npc.systemPrompt .. "\n\n"

    local citizenid = playerContext.citizenid

    -- ===========================================
    -- V2.5: NPC MOOD CONTEXT
    -- ===========================================
    local moodContext, moodEffects = "", nil
    if exports['ai-npcs'].BuildMoodContext then
        moodContext, moodEffects = exports['ai-npcs']:BuildMoodContext(npc.id, npc)
        if moodContext and moodContext ~= "" then
            prompt = prompt .. moodContext .. "\n"
        end
    end

    -- ===========================================
    -- V2.5: FACTION TRUST CONTEXT
    -- ===========================================
    if exports['ai-npcs'].BuildFactionContext and citizenid then
        local factionContext = exports['ai-npcs']:BuildFactionContext(npc.id, citizenid, playerContext.name)
        if factionContext and factionContext ~= "" then
            prompt = prompt .. factionContext .. "\n"
        end
    end

    -- ===========================================
    -- V2.5: RUMOR MILL CONTEXT
    -- ===========================================
    if exports['ai-npcs'].BuildRumorContext and citizenid then
        local rumorContext = exports['ai-npcs']:BuildRumorContext(npc.id, citizenid, npc)
        if rumorContext and rumorContext ~= "" then
            prompt = prompt .. rumorContext .. "\n"
        end
    end

    -- ===========================================
    -- V2.5: INTEL CONTEXT (what you can offer)
    -- ===========================================
    if exports['ai-npcs'].BuildIntelContext and citizenid then
        local intelContext = exports['ai-npcs']:BuildIntelContext(npc.id, citizenid)
        if intelContext and intelContext ~= "" then
            prompt = prompt .. intelContext .. "\n"
        end
    end

    -- Add current context section
    prompt = prompt .. "=== CURRENT SITUATION ===\n"

    -- Player info
    prompt = prompt .. ("You are currently talking to: %s\n"):format(playerContext.name)
    prompt = prompt .. ("Their job: %s\n"):format(playerContext.jobLabel)

    -- Trust level affects how open you are
    prompt = prompt .. ("Your relationship with them: %s (Trust: %d/100)\n"):format(
        conversation.trustLevel, conversation.trustValue
    )

    -- Context-specific instructions
    if playerContext.isCop then
        prompt = prompt .. "\n⚠️ WARNING: This person is LAW ENFORCEMENT. "
        local reaction = npc.contextReactions.copReaction
        if reaction == "extremely_suspicious" then
            prompt = prompt .. "Be very evasive. Give vague or misleading answers. Try to end the conversation. Do NOT reveal criminal information.\n"
        elseif reaction == "hostile_dismissive" then
            prompt = prompt .. "Be hostile and dismissive. Refuse to engage. Make it clear you don't talk to cops.\n"
        elseif reaction == "paranoid_shutdown" then
            prompt = prompt .. "Completely shut down. Deny knowing anything about anything illegal. Be boring and unhelpful.\n"
        elseif reaction == "professional_denial" then
            prompt = prompt .. "Maintain your cover story perfectly. Be polite but reveal nothing illegal.\n"
        else
            prompt = prompt .. "Be careful about what you reveal.\n"
        end
    else
        -- Non-cop context modifiers
        if playerContext.hasDrugs then
            prompt = prompt .. "✓ They appear to be carrying drugs. This suggests they're in the game. You can be more open about drug-related topics.\n"
        end

        if playerContext.hasCrimeTools then
            prompt = prompt .. "✓ They have professional tools (lockpicks, thermite, etc). They seem like a serious operator.\n"
        end

        if playerContext.hasWeapons then
            prompt = prompt .. "✓ They're armed. Treat them with appropriate respect/caution.\n"
        end

        if playerContext.cash > 10000 then
            prompt = prompt .. ("✓ They're carrying $%d in cash. They might be willing to pay for information.\n"):format(playerContext.cash)
        elseif playerContext.cash < 500 then
            prompt = prompt .. "✗ They don't seem to have much money on them.\n"
        end

        if playerContext.gang and playerContext.gang ~= "" then
            prompt = prompt .. ("✓ They're affiliated with: %s\n"):format(playerContext.gang)
        end
    end

    -- Trust level behavior
    prompt = prompt .. "\n=== TRUST LEVEL BEHAVIOR ===\n"
    if conversation.trustLevel == "Stranger" then
        prompt = prompt .. "They are a STRANGER. Be cautious. Only share vague rumors or public knowledge. Encourage them to prove themselves or pay for information.\n"
    elseif conversation.trustLevel == "Acquaintance" then
        prompt = prompt .. "They are an ACQUAINTANCE. You've met before. Share basic information if they pay. Don't reveal sensitive details yet.\n"
    elseif conversation.trustLevel == "Trusted" then
        prompt = prompt .. "They are TRUSTED. You've built a relationship. Share detailed information for fair payment. Warn them about dangers.\n"
    elseif conversation.trustLevel == "Inner Circle" then
        prompt = prompt .. "They are INNER CIRCLE. They've proven themselves completely. Share sensitive information freely. Give them the real good stuff.\n"
    end

    -- Payment context
    if conversation.paymentMade > 0 then
        prompt = prompt .. ("\n💰 They have paid you $%d this conversation. Be appropriately grateful and informative.\n"):format(conversation.paymentMade)
    end

    -- Intel request context
    if conversation.requestedIntel then
        prompt = prompt .. ("\n📋 INTEL REQUEST: They're asking about '%s' (tier: %s). Provide appropriate information based on trust and payment.\n"):format(
            conversation.requestedIntel.topic, conversation.requestedIntel.tier
        )
    end

    -- Reminder about format
    prompt = prompt .. "\n=== RESPONSE GUIDELINES ===\n"
    prompt = prompt .. "- Stay in character at all times\n"
    prompt = prompt .. "- Keep responses under 100 words\n"
    prompt = prompt .. "- Use appropriate actions in *asterisks*\n"
    prompt = prompt .. "- If they haven't paid enough for information, hint at needing payment\n"
    prompt = prompt .. "- If they're a cop, stick to your cover story\n"
    prompt = prompt .. "- Reference their trust level naturally in how open you are\n"

    return prompt
end

-----------------------------------------------------------
-- Clean AI Response
-----------------------------------------------------------
function CleanAIResponse(response)
    -- Remove any markdown formatting that might slip through
    response = response:gsub("```", "")
    response = response:gsub("##", "")
    response = response:gsub("**", "")

    -- Trim whitespace
    response = response:match("^%s*(.-)%s*$")

    -- Limit length if too long
    if #response > 500 then
        response = response:sub(1, 497) .. "..."
    end

    return response
end

-----------------------------------------------------------
-- Text-to-Speech Generation (with proper caching)
-----------------------------------------------------------
local audioCache = {}
local cacheSize = 0

-- Create a deterministic cache key from text + voice
local function GetTTSCacheKey(text, voiceId)
    -- Normalize text (lowercase, trim, remove excess whitespace)
    local normalized = text:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    -- Create hash from text + voice
    return GetHashKey(normalized .. "_" .. (voiceId or "default"))
end

function GenerateTTS(playerId, text, voiceId, npcId, isNetworked)
    if not Config.TTS.enabled then return end
    if not Config.TTS.apiKey or Config.TTS.apiKey == "YOUR_ELEVENLABS_KEY_HERE" then
        return
    end

    local voice = voiceId or Config.TTS.defaultVoice
    local cacheKey = GetTTSCacheKey(text, voice)

    -- Build voice data packet (decoupled from message)
    local voiceData = {
        npcId = npcId,
        voiceId = voice,
        isNetworked = isNetworked or false,
    }

    -- Check cache first - if we have this exact phrase already, just play it
    if Config.TTS.cacheAudio and audioCache[cacheKey] then
        local cachedFile = audioCache[cacheKey]
        voiceData.audioFile = cachedFile
        voiceData.cached = true
        TriggerClientEvent('ai-npcs:client:playVoice', playerId, voiceData)
        if Config.Debug.enabled then
            print(("[AI NPCs] TTS cache hit: %s"):format(cachedFile))
        end
        return
    end

    local requestData = {
        text = text,
        model_id = "eleven_monolingual_v1",
        voice_settings = {
            stability = 0.5,
            similarity_boost = 0.75
        }
    }

    local headers = {
        ["Content-Type"] = "application/json",
        ["xi-api-key"] = Config.TTS.apiKey
    }

    local url = Config.TTS.apiUrl .. voice

    PerformHttpRequest(url, function(statusCode, response, respHeaders)
        if statusCode == 200 then
            local fileName = ("audio_%s.ogg"):format(cacheKey)
            local savePath = "audio/" .. fileName

            -- Save audio file
            local saved = SaveResourceFile(GetCurrentResourceName(), savePath, response, #response)

            if saved then
                -- Cache reference
                if Config.TTS.cacheAudio then
                    audioCache[cacheKey] = fileName
                    cacheSize = cacheSize + 1

                    -- Clean cache if too large
                    if cacheSize > Config.TTS.maxCacheSize then
                        CleanAudioCache()
                    end
                end

                -- Send decoupled voice event to client
                voiceData.audioFile = fileName
                voiceData.cached = false
                TriggerClientEvent('ai-npcs:client:playVoice', playerId, voiceData)

                -- Broadcast to nearby players if networked
                if isNetworked then
                    TriggerClientEvent('ai-npcs:client:playVoiceNearby', -1, playerId, voiceData)
                end

                if Config.Debug.enabled then
                    print(("[AI NPCs] Generated TTS audio: %s (cached)"):format(fileName))
                end
            end
        else
            if Config.Debug.enabled then
                print(("[AI NPCs] TTS request failed with status: %s"):format(statusCode))
            end
            -- Fallback: trigger voice event without audio (client can handle gracefully)
            voiceData.audioFile = nil
            voiceData.error = "tts_failed"
            TriggerClientEvent('ai-npcs:client:playVoice', playerId, voiceData)
        end
    end, 'POST', json.encode(requestData), headers)
end

-----------------------------------------------------------
-- Audio Cache Management
-----------------------------------------------------------
function CleanAudioCache()
    local count = 0
    for audioId, fileName in pairs(audioCache) do
        if count >= 10 then break end

        audioCache[audioId] = nil
        cacheSize = cacheSize - 1
        count = count + 1
    end

    if Config.Debug.enabled then
        print(("[AI NPCs] Cleaned %d cached audio files"):format(count))
    end
end

-----------------------------------------------------------
-- ADMIN COMMANDS (Token Bucket Management)
-----------------------------------------------------------
local ADMIN_JOBS = {
    ['admin'] = true,
    ['god'] = true,
    ['developer'] = true,
}

local function IsAdmin(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    local job = Player.PlayerData.job.name
    local group = QBCore.Functions.GetPermission(source)

    -- Check job-based admin
    if ADMIN_JOBS[job] then return true end

    -- Check permission group (ace permissions)
    if group == 'admin' or group == 'god' then return true end

    return false
end

-- /ainpc tokens [player_id] - Check a player's token bucket status
RegisterCommand('ainpc', function(source, args, rawCommand)
    if source > 0 and not IsAdmin(source) then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Access Denied',
            description = 'Admin only command',
            type = 'error'
        })
        return
    end

    local subcommand = args[1]

    if subcommand == 'tokens' then
        -- Check token status
        local targetId = tonumber(args[2])
        if not targetId then
            -- Show all players with buckets
            local output = "^3[AI NPCs] Token Bucket Status:^7\n"
            local count = 0
            for playerId, bucket in pairs(playerBuckets) do
                local Player = QBCore.Functions.GetPlayer(playerId)
                local name = Player and Player.PlayerData.charinfo.firstname or "Unknown"
                local tokens = GetTokensRemaining(playerId)
                local nextToken = math.ceil(GetTimeUntilNextToken(playerId) / 1000)
                output = output .. ("  ID %d (%s): %d/%d tokens, next in %ds\n"):format(
                    playerId, name, tokens, TOKEN_BUCKET.maxTokens, nextToken
                )
                count = count + 1
            end
            if count == 0 then
                output = output .. "  No active buckets\n"
            end
            print(output)

            if source > 0 then
                TriggerClientEvent('ox_lib:notify', source, {
                    title = 'Token Status',
                    description = count .. ' active player buckets (see console)',
                    type = 'info'
                })
            end
        else
            -- Check specific player
            local tokens = GetTokensRemaining(targetId)
            local nextToken = math.ceil(GetTimeUntilNextToken(targetId) / 1000)
            local pending = pendingRequests[targetId] and "Yes" or "No"

            local msg = ("Player %d: %d/%d tokens, next in %ds, pending: %s"):format(
                targetId, tokens, TOKEN_BUCKET.maxTokens, nextToken, pending
            )
            print("[AI NPCs] " .. msg)

            if source > 0 then
                TriggerClientEvent('ox_lib:notify', source, {
                    title = 'Token Status',
                    description = msg,
                    type = 'info'
                })
            end
        end

    elseif subcommand == 'refill' then
        -- Refill a player's tokens
        local targetId = tonumber(args[2])
        if not targetId then
            if source > 0 then
                TriggerClientEvent('ox_lib:notify', source, {
                    title = 'Usage',
                    description = '/ainpc refill [player_id]',
                    type = 'error'
                })
            else
                print("[AI NPCs] Usage: /ainpc refill [player_id]")
            end
            return
        end

        -- Reset bucket to full
        playerBuckets[targetId] = {
            tokens = TOKEN_BUCKET.maxTokens,
            lastRefill = GetGameTimer()
        }

        local msg = ("Refilled tokens for player %d to %d"):format(targetId, TOKEN_BUCKET.maxTokens)
        print("[AI NPCs] " .. msg)

        if source > 0 then
            TriggerClientEvent('ox_lib:notify', source, {
                title = 'Tokens Refilled',
                description = msg,
                type = 'success'
            })
        end

        -- Notify target player
        TriggerClientEvent('ox_lib:notify', targetId, {
            title = 'AI NPCs',
            description = 'Your conversation limit has been reset',
            type = 'info'
        })

    elseif subcommand == 'refillall' then
        -- Refill all players' tokens
        local count = 0
        for playerId, _ in pairs(playerBuckets) do
            playerBuckets[playerId] = {
                tokens = TOKEN_BUCKET.maxTokens,
                lastRefill = GetGameTimer()
            }
            count = count + 1
        end

        local msg = ("Refilled tokens for %d players"):format(count)
        print("[AI NPCs] " .. msg)

        if source > 0 then
            TriggerClientEvent('ox_lib:notify', source, {
                title = 'All Tokens Refilled',
                description = msg,
                type = 'success'
            })
        end

    elseif subcommand == 'queue' then
        -- Show request queue status
        local output = ("^3[AI NPCs] Queue Status:^7\n")
        output = output .. ("  Queued requests: %d\n"):format(#requestQueue)
        output = output .. ("  Concurrent: %d/%d\n"):format(currentConcurrent, GLOBAL_STAGGER.maxConcurrent)
        output = output .. ("  Processing: %s\n"):format(isProcessingQueue and "Yes" or "No")

        for i, req in ipairs(requestQueue) do
            if i > 5 then
                output = output .. ("  ... and %d more\n"):format(#requestQueue - 5)
                break
            end
            local age = math.floor((GetGameTimer() - req.queuedAt) / 1000)
            output = output .. ("  [%d] Player %d, queued %ds ago\n"):format(i, req.playerId, age)
        end
        print(output)

        if source > 0 then
            TriggerClientEvent('ox_lib:notify', source, {
                title = 'Queue Status',
                description = ('%d queued, %d/%d concurrent'):format(
                    #requestQueue, currentConcurrent, GLOBAL_STAGGER.maxConcurrent
                ),
                type = 'info'
            })
        end

    elseif subcommand == 'debug' then
        -- Toggle debug mode
        Config.Debug.enabled = not Config.Debug.enabled
        local state = Config.Debug.enabled and "ENABLED" or "DISABLED"
        print(("[AI NPCs] Debug mode %s"):format(state))

        if source > 0 then
            TriggerClientEvent('ox_lib:notify', source, {
                title = 'Debug Mode',
                description = state,
                type = Config.Debug.enabled and 'success' or 'info'
            })
        end

    elseif subcommand == 'budget' then
        -- Show global token budget status
        if not GLOBAL_TOKEN_BUDGET.enabled then
            print("[AI NPCs] Global Token Budget is DISABLED")
            if source > 0 then
                TriggerClientEvent('ox_lib:notify', source, {
                    title = 'Budget Status',
                    description = 'Global Token Budget is disabled',
                    type = 'info'
                })
            end
        else
            local remaining = GetGlobalBudgetRemaining()
            local resetIn = math.ceil(GetTimeUntilBudgetReset() / 1000)
            local output = ("^3[AI NPCs] Global Token Budget:^7\n")
            output = output .. ("  Max per minute: %d\n"):format(GLOBAL_TOKEN_BUDGET.maxTokensPerMinute)
            output = output .. ("  Used this minute: %d\n"):format(GLOBAL_TOKEN_BUDGET.currentUsage)
            output = output .. ("  Remaining: %d\n"):format(remaining)
            output = output .. ("  Reset in: %ds\n"):format(resetIn)
            print(output)

            if source > 0 then
                TriggerClientEvent('ox_lib:notify', source, {
                    title = 'Budget Status',
                    description = ('%d/%d tokens, reset in %ds'):format(
                        remaining, GLOBAL_TOKEN_BUDGET.maxTokensPerMinute, resetIn
                    ),
                    type = 'info'
                })
            end
        end

    elseif subcommand == 'provider' then
        -- Show current AI provider info
        local provider = Config.AI.provider or "openai"
        local model = Config.AI.model or "unknown"
        local apiUrl = Config.AI.apiUrl or "not set"
        local output = ("^3[AI NPCs] AI Provider Info:^7\n")
        output = output .. ("  Provider: %s\n"):format(provider)
        output = output .. ("  Model: %s\n"):format(model)
        output = output .. ("  API URL: %s\n"):format(apiUrl)
        if provider == "ollama" then
            output = output .. ("  Native API: %s\n"):format(Config.AI.ollamaNativeApi ~= false and "Yes" or "No (OpenAI compat)")
            output = output .. ("  Timeout: %dms\n"):format(GLOBAL_STAGGER.ollamaTimeoutMs)
        end
        print(output)

        if source > 0 then
            TriggerClientEvent('ox_lib:notify', source, {
                title = 'AI Provider',
                description = ('%s - %s'):format(provider, model),
                type = 'info'
            })
        end

    elseif subcommand == 'test' then
        -- Quick test of AI provider connection
        local provider = Config.AI.provider or "openai"
        print(("[AI NPCs] Testing %s connection..."):format(provider))

        if source > 0 then
            TriggerClientEvent('ox_lib:notify', source, {
                title = 'Testing AI',
                description = 'Sending test request to ' .. provider,
                type = 'info'
            })
        end

        -- Build a minimal test request
        local testUrl, testData, testHeaders

        if provider == "ollama" then
            local useNative = Config.AI.ollamaNativeApi ~= false
            if useNative then
                testUrl = (Config.AI.apiUrl or "http://127.0.0.1:11434") .. "/api/chat"
                testData = {
                    model = Config.AI.model or "dolphin-llama3:8b",
                    messages = {{ role = "user", content = "Say 'test ok' in 5 words or less." }},
                    stream = false,
                    options = { num_predict = 20 }
                }
            else
                testUrl = (Config.AI.apiUrl or "http://127.0.0.1:11434") .. "/v1/chat/completions"
                testData = {
                    model = Config.AI.model or "dolphin-llama3:8b",
                    messages = {{ role = "user", content = "Say 'test ok' in 5 words or less." }},
                    max_tokens = 20
                }
            end
            testHeaders = { ["Content-Type"] = "application/json" }
        elseif provider == "anthropic" then
            testUrl = Config.AI.apiUrl
            testData = {
                model = Config.AI.model,
                messages = {{ role = "user", content = "Say 'test ok' in 5 words or less." }},
                max_tokens = 20
            }
            testHeaders = {
                ["Content-Type"] = "application/json",
                ["x-api-key"] = Config.AI.apiKey,
                ["anthropic-version"] = "2023-06-01"
            }
        else
            testUrl = Config.AI.apiUrl
            testData = {
                model = Config.AI.model,
                messages = {{ role = "user", content = "Say 'test ok' in 5 words or less." }},
                max_tokens = 20
            }
            testHeaders = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Bearer " .. (Config.AI.apiKey or "")
            }
        end

        local startTime = GetGameTimer()
        PerformHttpRequest(testUrl, function(statusCode, response, respHeaders)
            local elapsed = GetGameTimer() - startTime
            if statusCode == 200 then
                print(("[AI NPCs] ^2SUCCESS^7 - %s responded in %dms"):format(provider, elapsed))
                print("[AI NPCs] Response: " .. tostring(response):sub(1, 200))
                if source > 0 then
                    TriggerClientEvent('ox_lib:notify', source, {
                        title = 'Test Success',
                        description = ('%s OK in %dms'):format(provider, elapsed),
                        type = 'success'
                    })
                end
            else
                print(("[AI NPCs] ^1FAILED^7 - Status %s after %dms"):format(tostring(statusCode), elapsed))
                print("[AI NPCs] Response: " .. tostring(response))
                if source > 0 then
                    TriggerClientEvent('ox_lib:notify', source, {
                        title = 'Test Failed',
                        description = ('Status %s - check console'):format(tostring(statusCode)),
                        type = 'error'
                    })
                end
            end
        end, 'POST', json.encode(testData), testHeaders)

    else
        -- Show help
        local help = [[
^3[AI NPCs] Admin Commands:^7
  /ainpc tokens [id]    - Check token bucket status (all or specific player)
  /ainpc refill <id>    - Refill a player's tokens to max
  /ainpc refillall      - Refill all players' tokens
  /ainpc queue          - Show request queue status
  /ainpc budget         - Show global token budget status
  /ainpc provider       - Show current AI provider info
  /ainpc test           - Test AI provider connection
  /ainpc debug          - Toggle debug mode
]]
        print(help)

        if source > 0 then
            TriggerClientEvent('ox_lib:notify', source, {
                title = 'AI NPC Commands',
                description = 'See console (F8) for command list',
                type = 'info'
            })
        end
    end
end, false)

-- Export for external admin tools
exports('GetPlayerTokens', GetTokensRemaining)
exports('RefillPlayerTokens', function(playerId)
    playerBuckets[playerId] = {
        tokens = TOKEN_BUCKET.maxTokens,
        lastRefill = GetGameTimer()
    }
    return true
end)

-- Global Budget exports
exports('GetGlobalBudgetRemaining', GetGlobalBudgetRemaining)
exports('GetGlobalBudgetStatus', function()
    return {
        enabled = GLOBAL_TOKEN_BUDGET.enabled,
        maxTokensPerMinute = GLOBAL_TOKEN_BUDGET.maxTokensPerMinute,
        currentUsage = GLOBAL_TOKEN_BUDGET.currentUsage,
        remaining = GetGlobalBudgetRemaining(),
        resetIn = GetTimeUntilBudgetReset()
    }
end)

-----------------------------------------------------------
-- /createNPC HELPER COMMAND
-- Generates a config template for a new NPC
-----------------------------------------------------------
RegisterCommand('createnpc', function(source, args, rawCommand)
    if source > 0 and not IsAdmin(source) then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Access Denied',
            description = 'Admin only command',
            type = 'error'
        })
        return
    end

    -- Usage: /createnpc <id> [name] [role]
    local npcId = args[1]
    local npcName = args[2] or "New NPC"
    local npcRole = args[3] or "informant"

    if not npcId then
        local usage = [[
^3[AI NPCs] /createnpc Usage:^7
  /createnpc <id> [name] [role]

Example:
  /createnpc my_dealer "Street Dealer" dealer

This will output a config template to add to config.lua
]]
        print(usage)
        if source > 0 then
            TriggerClientEvent('ox_lib:notify', source, {
                title = 'Create NPC',
                description = 'Usage: /createnpc <id> [name] [role]',
                type = 'info'
            })
        end
        return
    end

    -- Get player position if in-game
    local coords = "vector4(0.0, 0.0, 0.0, 0.0)"
    if source > 0 then
        local playerPed = GetPlayerPed(source)
        if playerPed and playerPed ~= 0 then
            local pos = GetEntityCoords(playerPed)
            local heading = GetEntityHeading(playerPed)
            coords = ("vector4(%.2f, %.2f, %.2f, %.1f)"):format(pos.x, pos.y, pos.z, heading)
        end
    end

    -- Generate NPC template
    local template = ([=[
-----------------------------------------------------------
-- ADD THIS TO YOUR config.lua IN THE Config.NPCs TABLE
-----------------------------------------------------------
{
    id = "%s",
    name = "%s",
    model = "a_m_m_business_01",  -- Change to desired ped model
    blip = { sprite = 280, color = 1, scale = 0.6, label = "%s" },
    homeLocation = %s,
    movement = {
        pattern = "stationary",  -- "stationary", "wander", "patrol", or "schedule"
        locations = {}
    },
    schedule = nil,  -- Set time-based availability
    role = "%s",
    voice = Config.Voices.male_calm,  -- See Config.Voices
    trustCategory = "criminal",  -- Separate trust tracking per category

    personality = {
        type = "%s",
        traits = "Describe personality traits here",
        knowledge = "What does this NPC know about?",
        greeting = "*looks at you* What do you want?"
    },

    contextReactions = {
        copReaction = "extremely_suspicious",  -- How NPC reacts to cops
        hasDrugs = "more_open",
        hasMoney = "greedy",
        hasCrimeTools = "respectful"
    },

    intel = {
        {
            tier = "rumors",
            topics = {"general_info"},
            trustRequired = 0,
            price = 0
        },
        {
            tier = "basic",
            topics = {"specific_info"},
            trustRequired = 10,
            price = "low"
        }
    },

    systemPrompt = [[You are %s. Write your character's personality and knowledge here.

YOUR PERSONALITY:
- Add traits

WHAT YOU KNOW:
- Add knowledge areas

Keep responses under 100 words. Stay in character.]]
},
-----------------------------------------------------------
]=]):format(npcId, npcName, npcName, coords, npcRole, npcRole, npcName)

    print(template)

    if source > 0 then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'NPC Template Generated',
            description = 'Check F8 console for config template',
            type = 'success'
        })
    end
end, false)

-----------------------------------------------------------
-- INITIALIZATION
-----------------------------------------------------------
CreateThread(function()
    -- Initialize global token budget from config
    Wait(100)  -- Wait for config to load
    InitGlobalTokenBudget()

    -- Log provider info on startup
    local provider = Config.AI and Config.AI.provider or "not configured"
    local model = Config.AI and Config.AI.model or "not configured"
    print(("^2[AI NPCs]^7 AI Provider: %s (%s)"):format(provider, model))

    if provider == "ollama" then
        print("^2[AI NPCs]^7 Ollama mode - using local LLM")
        print(("^2[AI NPCs]^7 Ollama endpoint: %s"):format(Config.AI.apiUrl or "http://127.0.0.1:11434"))
        print(("^2[AI NPCs]^7 Timeout: %dms (extended for local inference)"):format(GLOBAL_STAGGER.ollamaTimeoutMs))
    end

    if GLOBAL_TOKEN_BUDGET.enabled then
        print(("^2[AI NPCs]^7 Global Token Budget: %d tokens/minute"):format(GLOBAL_TOKEN_BUDGET.maxTokensPerMinute))
    end
end)
