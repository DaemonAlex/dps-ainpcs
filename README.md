# dps-ainpcs - Advanced Conversational AI for FiveM RP

A comprehensive AI-powered NPC conversation system for QBCore FiveM servers. NPCs respond dynamically based on player context, build trust relationships, provide intel for crime RP, form faction alliances, spread rumors, and move around the map realistically.

## Features

### Core Systems

- **Dynamic AI Conversations**: NPCs respond intelligently using Ollama (local), Claude AI, or OpenAI GPT
- **Text-to-Speech Audio**: Optional ElevenLabs voice synthesis for immersive conversations
- **Player Context Awareness**: NPCs react differently based on your job, items, cash, and gang affiliation
- **Trust/Reputation System**: Build relationships with individual NPCs to unlock better intel
- **Intel/Clue System**: Pay for time-sensitive information about crimes, heists, drug operations, and more
- **NPC Movement**: NPCs wander, patrol, or follow schedules - they're not just standing still!
- **Modern UI**: Clean conversation interface with payment options
- **ox_target Integration**: Seamless interaction system

### v2.5 Systems

- **Faction Trust**: Group-level trust with gangs and organizations. Your reputation with the Vagos affects how all Vagos NPCs treat you
- **Rumor Mill**: NPCs gossip about player actions. Rob a bank and street NPCs will talk about it for days
- **NPC Mood**: NPCs have dynamic moods affected by events, weather, time of day, and player interactions
- **Cooperative Quests**: Multi-player group missions offered by NPCs with role assignments and shared rewards
- **Interrogation System**: Law enforcement can interrogate NPCs with varying methods and resistance levels
- **Phone Notifications**: NPCs can send you messages when you're offline - debt reminders, intel tips, quest updates
- **Discord Logging**: Configurable webhook logging for conversations, payments, intel purchases, and more

### Player Context Awareness

NPCs can detect and react to:
- **Your Job**: Cops get stonewalled or lied to, criminals get business talk
- **Items You Carry**: Drugs, weapons, crime tools, valuables all affect NPC behavior
- **Cash on Hand**: Rich players get more attention
- **Gang Affiliation**: Gang NPCs recognize their own
- **Criminal Record**: Some NPCs know your history
- **Faction Reputation**: Your standing with rival or allied factions changes everything

### Trust System

Build relationships over time:
- **Stranger** (0-10): Vague hints, rumors only
- **Acquaintance** (11-30): Basic info for cash
- **Trusted** (31-60): Detailed intel, warnings
- **Inner Circle** (61-100): The real good stuff, exclusive access

Trust is earned through:
- Repeated visits (+2 per visit)
- Successful conversations (+1)
- Payments (+5 per payment)
- Bringing requested items (+10)
- Referrals from other NPCs (+15)

### Faction Trust & Reputation

Faction reputation levels:
- **Unknown**: They don't know you
- **Enemy**: Hostile, may refuse to talk
- **Neutral**: Default state
- **Friendly**: Discounts, better intel
- **Ally**: Full access, co-op quests available
- **Blood**: You're family - the highest honor

### Intel Tiers & Pricing

| Tier | Trust Required | Price Range | Cooldown |
|------|---------------|-------------|----------|
| Rumors | 0 | Free | 5 min |
| Basic | 10-20 | $500-$2,000 | 10 min |
| Detailed | 30-50 | $2,000-$10,000 | 30 min |
| Sensitive | 60-70 | $10,000-$50,000 | 1 hour |
| Exclusive | 80+ | $50,000-$200,000 | 2 hours |

### NPC Movement Patterns

- **Stationary**: Classic standing NPC
- **Wander**: Moves randomly within a radius of home location
- **Patrol**: Follows defined waypoints with wait times
- **Schedule**: Different locations at different times of day

## Installation

1. **Dependencies**: Ensure you have:
   - qb-core
   - ox_lib
   - ox_target
   - oxmysql
   - dps-badpeds (shared character pool)
   - AI Provider (choose one):
     - **Ollama** (FREE - runs locally on your server)
     - Anthropic API key (https://console.anthropic.com/)
     - OpenAI API key (https://platform.openai.com/)

2. **Database Setup**:
   Run the SQL schemas to create required tables:
   ```bash
   # Base tables (v2.0)
   mysql -u root -p your_database < sql/install.sql

   # v2.5 systems (faction trust, rumor mill, intel, co-op quests, etc.)
   mysql -u root -p your_database < sql/upgrade_v2.5.sql
   ```

   Base tables (install.sql):
   - `ai_npc_trust` - Trust/reputation tracking per player per NPC
   - `ai_npc_quests` - Quest/task progress tracking
   - `ai_npc_intel_cooldowns` - Intel access cooldowns
   - `ai_npc_referrals` - NPC referral tracking
   - `ai_npc_debts` - Player debts/promises to NPCs
   - `ai_npc_memories` - NPC memories about players

   v2.5 tables (upgrade_v2.5.sql):
   - `ai_npc_faction_trust` - Faction-level trust and reputation
   - `ai_npc_rumors` - Dynamic rumor/gossip system
   - `ai_npc_intel` - Time-sensitive intel items
   - `ai_npc_intel_purchases` - Intel purchase tracking
   - `ai_npc_notifications` - Offline notification queue
   - `ai_npc_coop_quests` - Cooperative quest tracking
   - `ai_npc_coop_members` - Co-op quest participants
   - `ai_npc_relationships` - NPC-to-NPC relationships
   - `ai_npc_player_actions` - Player action log for rumor mill
   - `ai_npc_interrogations` - Interrogation attempt tracking

3. **Copy Config**:
   ```bash
   cp config.example.lua config.lua
   ```

4. **Add API Keys**: Edit `config.lua`:
   ```lua
   Config.AI.apiKey = "your_anthropic_or_openai_key"
   Config.TTS.apiKey = "your_elevenlabs_key" -- Optional
   ```

5. **Add to server.cfg**:
   ```
   ensure dps-ainpcs
   ```

6. **Restart Server**

## Included NPCs

### Crime & Underground
| NPC | ID | Location | Specialty |
|-----|----|----------|-----------|
| Sketchy Mike | informant_yellowjack | Yellow Jack Inn | Street-level drug/crime intel |
| Charlie the Fence | fence_chamberlain | Chamberlain Hills | Stolen goods, buyer contacts |
| The Architect | heist_planner_lester | Mirror Park | Heist planning, bank security |
| Smokey | weed_connect_grove | Grove Street | Weed connections |
| Rico | coke_connect_vinewood | Vinewood | Cocaine supply chain |
| Walter | meth_cook_sandy | Sandy Shores | Meth production |
| Viktor | arms_dealer_docks | Docks | Weapons and ammunition |
| Street Dealer | street_dealer | Various | Low-level drug deals |
| Mid-Level Dealer | mid_level_dealer | Various | Bulk drug distribution |
| Cartel Boss | cartel_boss | Various | Cartel operations |
| Pawn Shop Owner | pawn_shop_owner | Various | Stolen goods, fencing |
| Chop Shop Boss | chop_shop_boss | Various | Vehicle theft operations |
| The Cleaner | cleaner | Various | Evidence disposal, cleanup |

### Gang Contacts
| NPC | Gang | Territory |
|-----|------|-----------|
| El Guapo | Vagos | Jamestown |
| Purple K | Ballas | Davis |
| Big Smoke Jr | Families | Grove Street |
| Chains | Lost MC | East Vinewood |

### Legitimate NPCs
| NPC | Role | Location |
|-----|------|----------|
| Margaret Chen | Career Counselor | City Hall |
| Old Pete | Mechanic Mentor | Burton |
| Dr. Hartman | Doctor | Pillbox Hospital |
| Vanessa Sterling | Real Estate | Downtown |
| Captain Marcus | Pilot | LSIA |
| Attorney Goldstein | Lawyer | Downtown |
| Restaurant Owner | Restaurant Owner | Various |

### Service & Immersion
| NPC | Role | Location |
|-----|------|----------|
| Jackie | Bartender | Bahama Mamas (night) |
| Dexter | Casino Host | Diamond Casino (night) |
| Crazy Earl | Street Sage | Legion Square |

## Configuration

### Adding New NPCs

```lua
{
    id = "unique_id",
    name = "Display Name",
    model = "ped_model_name",
    blip = { sprite = 280, color = 1, scale = 0.6, label = "Blip Name" }, -- Optional
    homeLocation = vector4(x, y, z, heading),
    movement = {
        pattern = "wander", -- stationary, wander, patrol, schedule
        locations = {} -- For patrol/schedule patterns
    },
    schedule = { -- Optional availability times
        { time = {20, 4}, active = true },  -- Active 8 PM to 4 AM
        { time = {4, 20}, active = false }  -- Not available daytime
    },
    role = "street_informant",
    voice = Config.Voices.male_street, -- ElevenLabs voice ID
    trustCategory = "criminal", -- Trust tracked per category
    faction = "vagos", -- Optional faction for faction trust system

    personality = {
        type = "Character Type",
        traits = "Personality description",
        knowledge = "What they know about",
        greeting = "What they say when you approach"
    },

    contextReactions = {
        copReaction = "extremely_suspicious",
        hasDrugs = "more_open",
        hasMoney = "greedy",
        hasCrimeTools = "respectful"
    },

    intel = {
        {
            tier = "rumors",
            topics = {"topic1", "topic2"},
            trustRequired = 0,
            price = 0
        }
    },

    systemPrompt = [[Your AI system prompt here...]]
}
```

### Context Reactions

Available reaction types for NPCs:
- `extremely_suspicious` - Very evasive, gives false info
- `hostile_dismissive` - Refuses to engage, threatens
- `paranoid_shutdown` - Complete shutdown, denies everything
- `professional_denial` - Maintains cover story perfectly
- `pretends_not_to_notice` - Ignores what they see
- `interested` / `very_interested` - Opens up more
- `business_minded` - Talks money and deals
- `neutral` - No special reaction

## Integration with Other Resources

### Exports

```lua
-- =============================================
-- TRUST SYSTEM (Individual NPC)
-- =============================================
-- Get player's trust with an NPC (returns 0-100)
local trust = exports['dps-ainpcs']:GetPlayerTrustWithNPC(playerId, npcId)

-- Add trust between player and NPC
exports['dps-ainpcs']:AddPlayerTrustWithNPC(playerId, npcId, amount)

-- Set trust to specific value (admin/quest rewards)
exports['dps-ainpcs']:SetPlayerTrustWithNPC(playerId, npcId, value)

-- =============================================
-- FACTION TRUST (v2.5 - Group Dynamics)
-- =============================================
-- Get which faction an NPC belongs to
local faction = exports['dps-ainpcs']:GetNPCFaction(npcId)

-- Get player's trust with a faction
local factionTrust = exports['dps-ainpcs']:GetFactionTrust(citizenId, faction)

-- Add faction trust
exports['dps-ainpcs']:AddFactionTrust(citizenId, faction, amount)

-- Record a faction kill (affects trust with both factions)
exports['dps-ainpcs']:RecordFactionKill(citizenId, victimFaction)

-- Get how an NPC views the player based on faction standings
local view = exports['dps-ainpcs']:GetNPCFactionView(npcId, citizenId)

-- Build faction context string for AI prompts
local context = exports['dps-ainpcs']:BuildFactionContext(citizenId, npcId)

-- =============================================
-- RUMOR MILL (v2.5 - Dynamic World Knowledge)
-- =============================================
-- Record a notable player action (robbery, drug sale, etc.)
exports['dps-ainpcs']:RecordPlayerAction(citizenId, actionType, details)

-- Get rumors about a player that NPCs would know
local rumors = exports['dps-ainpcs']:GetRumorsAboutPlayer(citizenId)

-- Build rumor context string for AI prompts
local context = exports['dps-ainpcs']:BuildRumorContext(citizenId)

-- =============================================
-- NPC MOOD (v2.5 - Dynamic Emotions)
-- =============================================
-- Get an NPC's current mood
local mood = exports['dps-ainpcs']:GetNPCMood(npcId)

-- Set a temporary mood for an NPC
exports['dps-ainpcs']:SetNPCTempMood(npcId, mood, duration)

-- Set a global mood event (affects all NPCs)
exports['dps-ainpcs']:SetGlobalMoodEvent(event, duration)

-- Build mood context string for AI prompts
local context = exports['dps-ainpcs']:BuildMoodContext(npcId)

-- =============================================
-- NOTIFICATIONS (v2.5 - Offline Messaging)
-- =============================================
-- Send a generic NPC notification
exports['dps-ainpcs']:CreateNPCNotification(citizenId, npcId, type, title, message)

-- Send specific notification types
exports['dps-ainpcs']:SendIntelNotification(citizenId, npcId, intelTitle)
exports['dps-ainpcs']:SendQuestNotification(citizenId, npcId, questTitle)
exports['dps-ainpcs']:SendDebtReminder(citizenId, npcId, amount)
exports['dps-ainpcs']:SendWarningNotification(citizenId, npcId, warning)
exports['dps-ainpcs']:SendOpportunityNotification(citizenId, npcId, opportunity)

-- =============================================
-- INTEL (v2.5 - Time-Sensitive Information)
-- =============================================
-- Create a new intel item for an NPC
exports['dps-ainpcs']:CreateIntel(npcId, intelType, category, title, details, value, trustReq, expiresAt)

-- Get available intel from an NPC for a player
local intel = exports['dps-ainpcs']:GetAvailableIntel(npcId, citizenId)

-- Purchase intel
exports['dps-ainpcs']:PurchaseIntel(intelId, citizenId, pricePaid)

-- Build intel context string for AI prompts
local context = exports['dps-ainpcs']:BuildIntelContext(npcId, citizenId)

-- Generate intel dynamically for an NPC
exports['dps-ainpcs']:GenerateIntelForNPC(npcId)

-- =============================================
-- CO-OP QUESTS (v2.5 - Group Missions)
-- =============================================
-- Create a cooperative quest
exports['dps-ainpcs']:CreateCoopQuest(questId, leaderCitizenId, npcId, questType, questData)

-- Join/leave a co-op quest
exports['dps-ainpcs']:JoinCoopQuest(questId, citizenId, role)
exports['dps-ainpcs']:LeaveCoopQuest(questId, citizenId)

-- Start/complete/cancel a co-op quest
exports['dps-ainpcs']:StartCoopQuest(questId)
exports['dps-ainpcs']:CompleteCoopQuest(questId)
exports['dps-ainpcs']:CancelCoopQuest(questId)

-- Update player contribution to a co-op quest
exports['dps-ainpcs']:UpdateCoopContribution(questId, citizenId, amount)

-- Get a player's active co-op quests
local quests = exports['dps-ainpcs']:GetPlayerCoopQuests(citizenId)

-- Invite another player to a co-op quest
exports['dps-ainpcs']:InviteToCoopQuest(questId, inviterCitizenId, inviteeCitizenId)

-- =============================================
-- INTERROGATION (v2.5 - Law Enforcement)
-- =============================================
-- Check if an NPC can be interrogated
local canInterrogate = exports['dps-ainpcs']:CanInterrogate(npcId, playerId)

-- Perform an interrogation
local result = exports['dps-ainpcs']:PerformInterrogation(npcId, playerId, method)

-- Get NPC's current resistance level
local resistance = exports['dps-ainpcs']:GetNPCResistance(npcId)

-- =============================================
-- QUEST SYSTEM (Legacy)
-- =============================================
-- Offer a quest to a player
exports['dps-ainpcs']:OfferQuestToPlayer(playerId, npcId, questId, questType, {
    description = "Bring me 5 car batteries",
    items = {name = "carbattery", count = 5},
    reward = {trust = 15, money = 5000}
})

-- Complete a quest and award trust
exports['dps-ainpcs']:CompletePlayerQuest(playerId, npcId, questId, trustReward)

-- Get quest status ('offered', 'accepted', 'in_progress', 'completed', 'failed')
local status = exports['dps-ainpcs']:GetPlayerQuestStatus(playerId, npcId, questId)

-- =============================================
-- REFERRALS, DEBTS, MEMORIES (Legacy)
-- =============================================
-- Referrals
exports['dps-ainpcs']:CreatePlayerReferral(playerId, fromNpcId, toNpcId, 'standard')
local hasRef = exports['dps-ainpcs']:HasPlayerReferral(playerId, toNpcId)

-- Debts
exports['dps-ainpcs']:CreatePlayerDebt(playerId, npcId, 'money', 5000, "Payment for intel")
local debts = exports['dps-ainpcs']:GetPlayerDebts(playerId, npcId)
exports['dps-ainpcs']:PayPlayerDebt(playerId, debtId)

-- Memories
exports['dps-ainpcs']:AddNPCMemoryAboutPlayer(playerId, npcId, 'positive',
    "Helped me with a job", 8, 30)  -- importance 8, expires in 30 days
local memories = exports['dps-ainpcs']:GetNPCMemoriesAboutPlayer(playerId, npcId, 5)
```

### Events

```lua
-- Client: Receive NPC message
RegisterNetEvent('ai-npcs:client:receiveMessage', function(message, npcId)
    -- Handle message
end)

-- Client: Show payment prompt
RegisterNetEvent('ai-npcs:client:showPaymentPrompt', function(price, topic, tier)
    -- Handle payment UI
end)

-- Client: Play voice audio
RegisterNetEvent('ai-npcs:client:playVoice', function(voiceData)
    -- Handle TTS playback
end)

-- Client: Hear nearby NPC speech (networked)
RegisterNetEvent('ai-npcs:client:hearNearbySpeech', function(sourcePlayer, npcId, message, npcCoords)
    -- Handle nearby speech subtitles
end)

-- Server: End conversation
TriggerServerEvent('ai-npcs:server:endConversation')
```

## API Setup

### Ollama (Recommended - FREE)
Run AI locally on your server hardware. No API costs, no rate limits, full privacy.

**Requirements:** GPU with 8GB+ VRAM (RTX 3070, RTX 3080, etc.)

1. Install Ollama:
   ```bash
   curl -fsSL https://ollama.com/install.sh | sh
   ```

2. Pull a model (dolphin-llama3 recommended for uncensored RP):
   ```bash
   ollama pull dolphin-llama3:8b
   ```

3. Start the Ollama server:
   ```bash
   ollama serve
   ```

4. Configure `config.lua`:
   ```lua
   Config.AI = {
       provider = "ollama",
       apiUrl = "http://127.0.0.1:11434",
       apiKey = "not-needed",
       model = "dolphin-llama3:8b",
       maxTokens = 200,
       temperature = 0.85,
       ollamaNativeApi = true,
   }
   ```

5. Test with `/ainpc test` in-game

### Anthropic Claude (Cloud)
1. Visit https://console.anthropic.com/
2. Create API key
3. Set `Config.AI.provider = "anthropic"`
4. Add key to `Config.AI.apiKey`

### OpenAI GPT (Cloud)
1. Visit https://platform.openai.com/api-keys
2. Create API key
3. Set `Config.AI.provider = "openai"`
4. Set `Config.AI.apiUrl = "https://api.openai.com/v1/chat/completions"`
5. Add key to `Config.AI.apiKey`

### ElevenLabs TTS (Optional)
1. Visit https://elevenlabs.io/
2. Create account and get API key
3. Set `Config.TTS.enabled = true`
4. Add key to `Config.TTS.apiKey`

## Usage

1. **Find an NPC**: Look for NPCs at configured locations (check map blips)
2. **Start Conversation**: Use ox_target to "Talk to [Name]"
3. **Chat**: Type messages to interact
4. **Offer Payment**: Use "Offer Payment" option for intel
5. **Build Trust**: Return regularly to build relationships
6. **Get Intel**: Once trusted, ask about specific topics
7. **Co-op Quests**: At high trust, NPCs may offer group missions

## Admin Commands

### /ainpc - AI NPC Management
| Command | Description |
|---------|-------------|
| `/ainpc` | Show all available commands |
| `/ainpc tokens [id]` | Check player token bucket status |
| `/ainpc refill <id>` | Refill a player's conversation tokens |
| `/ainpc refillall` | Refill all players' tokens |
| `/ainpc queue` | Show request queue status |
| `/ainpc budget` | Show global token budget status |
| `/ainpc provider` | Show current AI provider info |
| `/ainpc test` | Test AI provider connection |
| `/ainpc debug` | Toggle debug mode |

### /createnpc - NPC Creation Helper
Generate config templates for new NPCs:
```
/createnpc <id> [name] [role]
```

Example:
```
/createnpc my_dealer "Street Dealer" dealer
```

This outputs a config template to F8 console with your current position as the spawn location.

## Cost Optimization

### AI Provider Costs
| Provider | Cost | Notes |
|----------|------|-------|
| **Ollama** | FREE | Runs locally, requires GPU |
| Claude Haiku | ~$0.00025/1k input | Fast and cheap |
| GPT-3.5 Turbo | ~$0.0015/1k tokens | Budget cloud option |
| GPT-4 | ~$0.03/1k tokens | Expensive |

### Reducing Costs
- **Use Ollama** - completely free, runs on your hardware
- Use Claude Haiku if cloud is needed - fast and cheap
- Limit max tokens (default 200)
- Set reasonable conversation limits
- Enable audio caching for TTS
- Enable Global Token Budget for Ollama to prevent server overload

## Troubleshooting

### NPCs Not Responding
- Check API key validity (or Ollama is running)
- Verify internet connectivity (for cloud providers)
- Check server console for HTTP errors
- Run `/ainpc test` to diagnose connection issues

### Ollama Not Working
- Ensure Ollama is running: `ollama serve`
- Check model is pulled: `ollama list`
- Verify endpoint: `curl http://127.0.0.1:11434/api/tags`
- Check GPU has enough VRAM (8GB+ recommended)
- Look for OOM errors in Ollama logs
- Try a smaller model: `ollama pull dolphin-mistral:7b`

### NPCs Not Moving
- Ensure `Config.Movement.enabled = true`
- Check movement pattern is not "stationary"
- Verify patrol waypoints are valid coordinates

### NPCs Not Appearing (Blips Only)
- Check server console for spawn errors
- Verify ped model names are valid
- Ensure homeLocation Z coordinates are correct (ground level)
- Check if NPC schedule makes them unavailable at current time

### Trust Not Saving
- Ensure oxmysql is running
- Check database tables exist (`ai_npc_trust`)
- Verify oxmysql connection string in server.cfg

### Schedule NPCs Not Appearing
- Check in-game time matches schedule
- Verify schedule time ranges are correct

## Version History

- **v2.5.0** - Advanced Systems Update
  - **Faction Trust System** - Group-level reputation with gangs and organizations
  - **Rumor Mill** - NPCs gossip about player actions dynamically
  - **NPC Mood System** - Dynamic emotions affected by events and interactions
  - **Cooperative Quests** - Multi-player group missions with role assignments
  - **Interrogation System** - Law enforcement can interrogate NPCs
  - **Phone Notifications** - Offline messaging from NPCs (intel tips, debt reminders)
  - **Discord Logging** - Webhook integration for admin oversight
  - **Time-Sensitive Intel** - Intel that expires and has limited availability
  - **NPC Relationships** - NPCs have relationships with each other
  - **Player Action Tracking** - Detailed logging for rumor generation
  - New dependency: `dps-badpeds` for shared character pool
  - 8 new database tables
  - Automatic cleanup of expired data via MySQL events

- **v2.1.0** - Ollama & Local LLM Support
  - **Native Ollama provider** - Run AI locally for FREE
  - Global Token Budget system for server-wide rate limiting
  - Enhanced error handling with provider-specific diagnostics
  - `/ainpc test` command to test AI connection
  - `/ainpc provider` command to view provider info
  - `/ainpc budget` command to view token budget status
  - `/createnpc` helper command for easy NPC creation
  - Extended timeouts for local model inference (120s)
  - Ollama connection troubleshooting in console

- **v2.0.0** - Major overhaul
  - Added trust/reputation system with database persistence
  - Added quest system (item delivery, tasks, kill, frame, escort)
  - Added referral chains between NPCs
  - Added debt/promise system
  - Added NPC memory system
  - Added intel/clue pricing system with cooldowns
  - Added player context awareness (job, items, money, gang)
  - Added NPC movement patterns (wander, patrol, schedule)
  - Added 20+ diverse NPCs with nuanced morality
  - Added cop detection and appropriate NPC reactions
  - Added payment UI integration with ox_lib
  - Claude API support alongside OpenAI
  - Full MySQL persistence via oxmysql

- **v1.0.0** - Initial release
  - Basic AI conversation system
  - OpenAI GPT integration
  - ElevenLabs TTS support

## Credits

Original concept & code by DaemonAlex. Enhanced for DPSRP with comprehensive RP features.
