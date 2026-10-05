# dps-ainpcs

Talking NPCs for Qbox servers: each NPC answers in free text through a language model, remembers players, and trades intel and jobs for trust and cash.

## Features

### Players

- Talk to an NPC with ox_target ("Talk to <name>"), then type what you want to say. NPC lines show as head bubbles (see Prerequisites).
- Offer Payment: pay an NPC cash (bank and crypto are config options, off by default) to unlock intel.
- Ask About Work: the NPC offers jobs (quests) you qualify for.
- Active Jobs: shows your active jobs. The `/myjobs` command does the same from anywhere.
- Trust: each NPC tracks your trust (0 to 100): Stranger, Acquaintance, Trusted, Inner Circle. Higher trust unlocks better intel and jobs.
- Faction trust: gangs and groups have their own standing with you (unknown, enemy, neutral, friendly, ally, blood).
- NPCs react to your job, gang, cash, items you carry, and recent actions that spread as rumors.
- NPCs remember earlier talks (a one-line memory after each talk) and know a short list of real places near them.
- Some NPCs call you over when you walk past (`hail`).
- Intel can be bought with cash. Co-op quests and phone notifications are available through the exports below.
- NPCs can wander, patrol, follow a time-of-day schedule, or stand still. They only exist while a player is nearby.
- Bar crowds (`data/crowds.lua`) spawn extra talkable regulars around a place.

### Admins

All admin commands need ACE `group.admin` (or the `command` ACE), a player job named `admin`, `god` or `developer`, or the server console.

| Command | Where | What it does |
|---|---|---|
| `/ainpc` | server | Prints help |
| `/ainpc tokens [id]` | server | Show the rate-limit tokens for all players or one player |
| `/ainpc refill <id>` | server | Refill one player's tokens |
| `/ainpc refillall` | server | Refill everyone's tokens |
| `/ainpc queue` | server | Show the request queue |
| `/ainpc budget` | server | Show the global token budget |
| `/ainpc provider` | server | Show the current AI provider settings |
| `/ainpc test` | server | Send a test request to the AI provider |
| `/ainpc debug` | server | Toggle debug mode |
| `/createnpc <id> [name] [role]` | server | Prints a config template for a new NPC (uses your position in game) |
| `/myjobs` | client | Show your active jobs (any player) |
| `/npcgesture [tag]` | client | Debug: play a gesture on the nearest AI NPC within 12 m (default `shrug`) |

There are no key bindings. All interaction is through ox_target.

### Rate limits

Each player has 5 tokens, refilled at 5 per minute. At most 5 AI requests run at once. Requests time out after 30 s (120 s for Ollama). When a request fails, the NPC says a line from `Config.FallbackResponses`.

## Prerequisites

Required (listed in `fxmanifest.lua` `dependencies`):

- `ox_lib`
- `qbx_core`
- `ox_target` (talk, pay, work, jobs options)
- `ox_inventory` (item checks, quest items and rewards)
- `oxmysql`
- `dps-badpeds` (the manifest loads `@dps-badpeds/shared/characters.lua` and the server calls its `IsCharacterAvailable` export)

An AI model endpoint, one of:

- Ollama (`provider = "ollama"`, native `/api/chat`)
- Any OpenAI-compatible chat-completions server (`provider = "openai"`; `apiUrl` is used as the full URL)
- Anthropic (`provider = "anthropic"`)

Optional:

- `dps-chat`: NPC speech shows as head bubbles through `exports["dps-chat"]:ShowBubble`. If `dps-chat` is not started, or the call fails, the client falls back to an ox_lib notification. Long lines are cut to 118 characters for the bubble.
- `npwd` or `lb-phone`: used to deliver NPC phone notifications when started (`server/systems/notifications.lua`).
- Discord webhooks, for `Config.Logs`.

Convars: this resource reads none. The API key is `Config.AI.apiKey` in `config.lua` (see the warning in Installation).

## Installation

1. Put the folder in your resources directory as `dps-ainpcs`.
2. Copy `config.example.lua` to `config.lua` if you do not have one.
3. Run `sql/install.sql`, then `sql/upgrade_v2.5.sql`, on your database. Both use `CREATE TABLE IF NOT EXISTS`.
4. In `config.lua`, set `Config.AI.provider`, `apiUrl`, `model` and, if your provider needs one, `apiKey`.
   - Warning: `config.lua` is a shared script, so its contents are loaded on the client too. Do not leave a paid API key in it on a public server. Use a provider that needs no key, or put the model behind an address that checks access itself.
5. Start order in `server.cfg`, after the dependencies:
   ```
   ensure ox_lib
   ensure oxmysql
   ensure qbx_core
   ensure ox_inventory
   ensure ox_target
   ensure dps-badpeds
   ensure dps-chat      # optional
   ensure dps-ainpcs
   ```
6. Grant admin commands if needed, for example:
   ```
   add_ace group.admin command allow
   ```
7. Restart the server and run `/ainpc test` from the console to check the model connection.

Tables created: `ai_npc_trust`, `ai_npc_quests`, `ai_npc_intel_cooldowns`, `ai_npc_referrals`, `ai_npc_debts`, `ai_npc_memories`, `ai_npc_ladders`, `ai_npc_conversations`, `ai_npc_faction_trust`, `ai_npc_rumors`, `ai_npc_intel`, `ai_npc_intel_purchases`, `ai_npc_notifications`, `ai_npc_coop_quests`, `ai_npc_coop_members`, `ai_npc_relationships`, `ai_npc_player_actions`, `ai_npc_interrogations`.

## Configuration

Main file: `config.lua`. Jobs, items and gangs named in it must match your server.

### Config.AI

| Option | Default | Meaning |
|---|---|---|
| `provider` | `"ollama"` | `ollama`, `openai` or `anthropic` |
| `apiUrl` | `http://100.127.29.87:11434` | Ollama: base URL. OpenAI-compatible: full chat-completions URL. Change this to your own server |
| `apiKey` | `""` | Sent as a Bearer token (OpenAI-compatible) or `x-api-key` (Anthropic). Empty means no auth header |
| `model` | `"granite4.1:8b"` | Model name |
| `maxTokens` | `320` | Max reply length |
| `temperature` | `0.9` | Higher is more varied |
| `contextLength` | `8192` | Ollama `num_ctx` |
| `repeatPenalty` | `1.15` | Ollama `repeat_penalty` |
| `globalBudget.enabled` | `false` | Turn on a server-wide token limit |
| `globalBudget.maxTokensPerMinute` | `2000` | The limit when enabled |

### Config.Trust

| Option | Default | Meaning |
|---|---|---|
| `enabled` | `true` | Use trust |
| `levels` | 0-10, 11-30, 31-60, 61-100 | Stranger, Acquaintance, Trusted, Inner Circle |
| `earnRates.conversation` | `1` | Per successful conversation |
| `earnRates.payment` | `5` | Per payment |
| `earnRates.correctItem` | `10` | Bringing a requested item |
| `earnRates.repeatVisit` | `2` | Returning to the same NPC |
| `earnRates.referral` | `15` | Referred by another NPC |
| `decayRate` | `2` | Trust lost per real day of inactivity |
| `decayCheckInterval` | `86400000` | Decay check interval (ms) |

### Config.Intel

| Option | Default | Meaning |
|---|---|---|
| `prices.low` | 500 to 2,000 | Price range |
| `prices.medium` | 2,000 to 10,000 | Price range |
| `prices.high` | 10,000 to 50,000 | Price range |
| `prices.premium` | 50,000 to 200,000 | Price range |
| `trustRequirements` | rumors 0, basic 10, detailed 30, sensitive 60, exclusive 80 | Trust needed per tier |
| `cooldowns` | 5 min, 10 min, 30 min, 1 h, 2 h | Per-tier cooldown (ms), rumors to exclusive |

### Config.Memory and Config.Ledger

| Option | Default | Meaning |
|---|---|---|
| `Memory.maxLines` | `5` | Memories added to the prompt |
| `Memory.talkSummary` | `true` | Make one extra model call after a talk to store a one-line memory |
| `Memory.minMessages` | `2` | Shorter talks are not remembered |
| `Memory.summaryMaxTokens` | `60` | Length of the summary |
| `Memory.summaryExpiresDays` | `30` | Memory lifetime |
| `Ledger.maxLines` | `6` | Lines of recent city news the NPC has heard |
| `Ledger.hours` | `48` | How far back that news reaches |

### Config.Movement

| Option | Default | Meaning |
|---|---|---|
| `enabled` | `true` | NPCs move |
| `spawnDistance` | `120.0` | NPCs exist only within this many metres of a player |
| `patterns.wander.radius` | `20.0` | Wander radius from home |
| `patterns.wander.minWait` / `maxWait` | `30000` / `120000` | Wait at each spot (ms) |
| `patterns.patrol.waitAtPoints` | `60000` | Wait at each waypoint (ms) |

Patterns: `stationary`, `wander`, `patrol`, `schedule`.

### Config.Interaction

| Option | Default | Meaning |
|---|---|---|
| `distance` | `3.0` | ox_target distance |
| `cooldown` | `3000` | Delay between messages (ms) |
| `maxConversationLength` | `15` | Max exchanges per conversation |
| `showSubtitles` | `true` | Show subtitles |
| `idleTimeout` | `900000` | Safety timeout (ms). A talk also ends when the player walks away |
| `modelGreeting` | `true` | The opening line comes from the model |
| `paymentMethods` | cash `true`, bank `false`, crypto `false` | Accepted payment types |

### Config.PlayerContext

| Option | Default | Meaning |
|---|---|---|
| `includeJob`, `includeJobGrade`, `includeMoney`, `includeItems`, `includeGang`, `includeCriminalRecord` | all `true` | What the NPC may know about the player |
| `suspiciousJobs` | `police, bcso, sasp, fib, doc, dfw, rpd, rcso, uscg` | Jobs that make NPCs wary. Replace with your job names |
| `specialItems.drugs` | weed, coke, meth, crack, oxy, lean | Item names counted as drugs |
| `specialItems.weapons` | weapon_pistol, weapon_smg, weapon_rifle | Weapons |
| `specialItems.crimeTools` | lockpick, thermite, laptop, drill | Crime tools |
| `specialItems.valuables` | goldbar, diamond, rolex, cash_bag | Valuables |

### Other

| Option | Default | Meaning |
|---|---|---|
| `Config.Sound.enableNetworked` | `false` | Show NPC lines to nearby players too |
| `Config.Sound.maxDistance` | `20.0` | Range for that (m) |
| `Config.Logs.enabled` | `false` | Discord webhook logging. Set `webhooks` first |
| `Config.Logs.logConversations` / `logIntelPurchases` / `logQuestCompletions` / `logErrors` | `true` | Events to log |
| `Config.Logs.logTrustChanges` | `false` | Log trust changes |
| `Config.Logs.includeIdentifiers` | `true` | Add player identifiers to logs |
| `Config.Logs.tagOnConversation` / `tagOnError` | `false` / `true` | Ping `tagType` on these events |
| `Config.Debug.enabled` | `false` | Debug output |
| `Config.Debug.printResponses` / `printPlayerContext` | `true` / `false` | Extra debug prints |
| `Config.FallbackResponses` | lists | Lines used when the AI fails: generic, criminal, legitimate, service, api_error |
| `Config.TTS`, `Config.Voices`, `Config.Audio` | retired | Text-to-speech is disabled. Leave `Config.TTS.enabled = false` |

Other files:

- `quests.lua`: quest definitions (`Config.Quests`). The template at the top shows the fields (trust, cooldown, job limits, objectives, rewards, failure rules). See `docs/QUEST_DESIGN.md`.
- `data/places.lua`: real places NPCs may mention. Replace with places on your map.
- `data/crowds.lua`: bar crowds (center, radius, seats).
- `data/ladders.lua`, `data/onmind.lua`: breadcrumb chains between NPCs, and one daily topic per NPC.

## Adding an NPC

Add an entry to `Config.NPCs` in `config.lua`. Run `/createnpc <id> [name] [role]` to print a starting template with your position.

```lua
{
    id = "my_dealer",                          -- unique
    name = "Display Name",
    model = "a_m_m_tramp_01",
    blip = { sprite = 280, color = 1, scale = 0.6, label = "Contact" },  -- optional
    homeLocation = vector4(x, y, z, heading),
    movement = { pattern = "stationary" },     -- stationary, wander, patrol, schedule
    schedule = nil,                            -- or { { time = {20, 4}, active = true } }
    role = "street_informant",
    trustCategory = "criminal",
    faction = "vagos",                         -- optional, ties to faction trust
    hail = { chance = 45, cooldownSec = 180, distance = 9.0, line = "psst... over here" },  -- optional
    facts = { rumors = { "..." }, basic = { "..." }, detailed = { "..." }, secret = { "..." } },
    personality = { type = "...", traits = "...", knowledge = "...", greeting = "..." },
    contextReactions = { copReaction = "extremely_suspicious", hasDrugs = "more_open",
                         hasMoney = "greedy", hasCrimeTools = "respectful" },
    intel = { { tier = "rumors", topics = { "topic1" }, trustRequired = 0, price = 0 } },
    systemPrompt = [[Who the NPC is and how they talk.]],
}
```

- Facts are given to the model only for the trust tiers the player has reached.
- Reaction values used in the included NPCs: `extremely_suspicious`, `hostile_dismissive`, `paranoid_shutdown`, `professional_denial`, `pretends_not_to_notice`, `interested`, `very_interested`, `business_minded`, `neutral`.
- Give an NPC jobs by adding quests for their `role` in `quests.lua`.
- Restart the resource after editing.

## Exports (server)

Other resources can call these on `dps-ainpcs`:

- Trust: `GetPlayerTrustWithNPC`, `AddPlayerTrustWithNPC`, `SetPlayerTrustWithNPC`
- Factions: `GetNPCFaction`, `GetFactionTrust`, `AddFactionTrust`, `RecordFactionKill`, `GetNPCFactionView`, `BuildFactionContext`
- Rumors: `RecordPlayerAction`, `GetRumorsAboutPlayer`, `BuildRumorContext`
- Mood: `GetNPCMood`, `SetNPCTempMood`, `SetGlobalMoodEvent`, `BuildMoodContext`
- Notifications: `CreateNPCNotification`, `SendIntelNotification`, `SendQuestNotification`, `SendDebtReminder`, `SendWarningNotification`, `SendOpportunityNotification`
- Intel: `CreateIntel`, `GetAvailableIntel`, `PurchaseIntel`, `BuildIntelContext`, `GenerateIntelForNPC`
- Co-op quests: `CreateCoopQuest`, `JoinCoopQuest`, `LeaveCoopQuest`, `StartCoopQuest`, `UpdateCoopContribution`, `CompleteCoopQuest`, `CancelCoopQuest`, `GetPlayerCoopQuests`, `InviteToCoopQuest`
- Interrogation: `CanInterrogate`, `PerformInterrogation`, `GetNPCResistance`
- Quests: `OfferQuestToPlayer`, `CompletePlayerQuest`, `GetPlayerQuestStatus`, `GetOfferableQuests`, `GrantQuestReward`
- Referrals and debts: `CreatePlayerReferral`, `HasPlayerReferral`, `CreatePlayerDebt`, `GetPlayerDebts`, `PayPlayerDebt`
- Memories: `AddNPCMemoryAboutPlayer`, `GetNPCMemoriesAboutPlayer`
- Logging: `LogConversation`, `LogTrustChange`, `LogIntelPurchase`, `LogQuestCompletion`, `LogError`, `FlushLogs`
- Rate limits: `GetPlayerTokens`, `RefillPlayerTokens`

Example:

```lua
local trust = exports['dps-ainpcs']:GetPlayerTrustWithNPC(source, 'informant_yellowjack')
exports['dps-ainpcs']:AddFactionTrust(citizenid, 'vagos', 10)
```

## Troubleshooting

- **NPCs only say lines like "Sorry, not feeling well right now":** the model request failed. Run `/ainpc test` and `/ainpc provider`. Check `apiUrl`, `model`, and that the model server is reachable from the game server.
- **Replies are slow or time out with Ollama:** local models can be slow. The Ollama timeout is 120 s. Use a smaller model or lower `maxTokens`.
- **"Connection failed" in the server console:** the URL is wrong or blocked. For `openai`, `apiUrl` must be the full chat-completions URL. For `ollama`, give the base URL only.
- **Players get no reply after several messages:** they ran out of tokens (5, refilling 5 per minute). Use `/ainpc tokens <id>` and `/ainpc refill <id>`.
- **Speech shows as a corner notification, not a head bubble:** `dps-chat` is not started, or it does not export `ShowBubble`. This is the built-in fallback.
- **Resource fails to start on a missing file:** `dps-badpeds` must be installed and started before `dps-ainpcs`. `server/config_secrets.lua` must exist (it ships empty).
- **Database errors:** run both SQL files. `ai_npc_*` tables are missing if only `install.sql` was run.
- **A job or item reaction never triggers:** the job and item names in `Config.PlayerContext` do not match your server. Edit them.
- **NPC missing from the map:** NPCs spawn only within `Config.Movement.spawnDistance` of a player, and `schedule` NPCs only at their active hours.
- **Admin command says "Admin only command":** grant the ACE (step 6) or run it from the server console.
