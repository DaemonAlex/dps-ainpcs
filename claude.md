# DPS AI NPCs - Development Notes

## API Keys & Credentials

### ElevenLabs TTS
```
API Key: sk_6c964f5f2baea6b46dccf6487235f931f36c5499741f6f0d
```

**Usage in config.lua:**
```lua
Config.TTS = {
    enabled = true,
    provider = "elevenlabs",
    apiUrl = "https://api.elevenlabs.io/v1/text-to-speech/",
    apiKey = "sk_6c964f5f2baea6b46dccf6487235f931f36c5499741f6f0d",
    defaultVoice = "21m00Tcm4TlvDq8ikWAM",  -- Rachel
    cacheAudio = true,
    maxCacheSize = 100
}
```

---

## Recent Updates (from mad_goon patterns)

### v2.5.1 Improvements

1. **Networked Speech System**
   - Added `isNetworked` parameter to broadcast NPC speech to nearby players
   - Config option: `Config.Sound.enableNetworked`
   - Distance-based volume falloff

2. **Client-Side Input Validation**
   - 3-layer validation: client → server → AI
   - Message length limits (200 chars)
   - Cooldown between messages (500ms)

3. **Decoupled Voice Events**
   - Separate `playVoice` event from message display
   - Allows text-only or audio-only responses
   - Better TTS failure handling

4. **Discord Webhook Logging**
   - Batched logging (10 logs per POST)
   - Automatic flush every 60 seconds
   - Log types: conversation, trust, intel, quest, error

---

## Config Additions Needed

Add these to your `config.lua`:

```lua
-- Sound/Networked Speech Config
Config.Sound = {
    enableNetworked = true,   -- Broadcast speech to nearby players
    maxDistance = 20.0,       -- Max distance for networked speech
}

-- Discord Logging Config
Config.Logs = {
    enabled = true,
    authorName = '🤖 AI NPCs',
    username = 'AI NPCs Logs',
    iconUrl = 'https://cdn-icons-png.flaticon.com/512/4712/4712109.png',
    tagType = '@everyone',
    includeIdentifiers = true,

    webhooks = {
        conversation = '',  -- Add your webhook URL
        trust = '',
        intel = '',
        quest = '',
        error = '',
    },

    logConversations = true,
    logTrustChanges = false,
    logIntelPurchases = true,
    logQuestCompletions = true,
    logErrors = true,
    tagOnConversation = false,
    tagOnError = true,
}
```

---

## Ultimate Roadmap (Remaining Items)

### Priority Features

1. **Voice Input (STT)** - Allow players to speak to NPCs via microphone instead of typing
   - Integration options: Whisper API, Google STT, Azure Speech

2. **Local LLM Support** - ✅ Already implemented (Ollama support exists)
   - Support for Llama 3, Mistral, etc.

3. **Visual Perception** - Use GPT-4o Vision so NPCs can comment on player outfits, vehicles, or held weapons
   - Requires screenshot capture and vision API integration

4. **Procedural Mission Generator** - NPCs generate dynamic, multi-step quests based on server economy/events
   - Extend quest system with AI-generated objectives

5. **Phone Integration** - NPCs can text/call players for job updates, rumors, or threats
   - Already have notification system; needs phone script bridges

6. **Animation System** - Sync NPC gestures (nodding, angry, scared) with sentiment of AI response
   - Sentiment analysis + animation mapping

7. **Faction Ecosystem** - ✅ Partially implemented (faction_trust.lua)
   - NPCs share information; angering one Vagos member lowers trust with all Vagos NPCs

8. **In-Game Creator** - Admin menu to place, configure, and prompt-engineer NPCs without touching code
   - NUI-based NPC editor

9. **Dispatch Integration** - Civ NPCs automatically call 911/Dispatch if they witness a crime
   - Integration with ps-dispatch or similar

10. **Multi-Framework Support** - Add bridges for ESX and Qbox compatibility
    - Bridge pattern similar to mad_goon

---

*Last Updated: 2026-01-17*
