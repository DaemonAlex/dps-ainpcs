# AI NPCs - Quick Setup Guide

## ✅ API Keys Configured!

Your API keys are already configured:
- **Anthropic Claude**: ✅ Configured (Haiku model for fast responses)
- **ElevenLabs TTS**: ✅ Configured (Voice synthesis ready)

## 🚀 Quick Start

### 1. Enable the Resource
Add to your server.cfg if not already present:
```
ensure ai-npcs
```

### 2. Restart Your Server
Restart FiveM server to load the AI NPC system

### 3. Test the System
- Teleport to Yellow Jack Inn: `/tp 1982 3053 47`
- Look for "Sketchy Mike" (homeless looking NPC)
- Use ox_target and select "Talk to Sketchy Mike"
- Type messages to have a conversation!

## 💬 Example Conversations

Try asking Sketchy Mike:
- "Where can I get some weed?"
- "Know any drug suppliers?"
- "Are the cops around?"
- "How do I start dealing?"
- "What's the word on the street?"

## 🔊 Audio Features

With ElevenLabs configured:
- NPCs will speak their responses
- Voice: Rachel (natural conversational voice)
- Audio is cached to reduce API calls

## 💰 Cost Monitoring

Per conversation (average):
- **Claude Haiku**: ~$0.0025 (very cheap!)
- **ElevenLabs**: ~$0.03 per response
- **Total**: ~$0.03-0.05 per full conversation with voice

## 🎯 Adding More NPCs

Edit `config.lua` to add more NPCs:

```lua
{
    id = "unique_id",
    name = "NPC Name",
    model = "ped_model",
    coords = vector4(x, y, z, heading),
    role = "role_type",
    voice = "21m00Tcm4TlvDq8ikWAM", -- ElevenLabs voice ID
    personality = {
        type = "Character Type",
        traits = "Personality traits",
        knowledge = "What they know",
        greeting = "Hello message"
    },
    systemPrompt = "Detailed AI instructions"
}
```

## 🎤 Available ElevenLabs Voices

Popular voice IDs for different NPC types:
- `21m00Tcm4TlvDq8ikWAM` - Rachel (female, conversational)
- `ErXwobaYiN019PkySvjV` - Antoni (male, young)
- `VR6AewLTigWG4xSOukaG` - Arnold (male, crisp)
- `pNInz6obpgDQGcFmaJgB` - Adam (male, deep)
- `EXAVITQu4vr4xnSDxMaL` - Bella (female, soft)

## 🔧 Troubleshooting

### NPCs Not Spawning
- Check server console for errors
- Verify resource is loading: `ensure ai-npcs`
- Check coordinates are valid

### No AI Responses
- Check server console for API errors
- Verify internet connection
- Check API key validity

### No Audio
- Audio files may take a moment to generate
- Check console for TTS errors
- Verify ElevenLabs quota not exceeded

## 📊 Monitor Usage

Watch server console for:
- `[AI NPCs] Started conversation...`
- `[AI NPCs] Generated response...`
- `[AI NPCs] Generated TTS audio...`

## 🚨 Important Notes

1. **Rate Limits**: Both APIs have rate limits
2. **Costs**: Monitor your API usage dashboards
3. **Cache**: Audio files are cached in `/audio/` folder
4. **Cleanup**: Old conversations auto-cleanup after 5 minutes

## 📈 Next Steps

1. Add more NPCs from the database we created
2. Customize personalities for your server's lore
3. Create quest-giving NPCs
4. Add NPCs that give missions or jobs
5. Create informant networks across the map

---

**Support**: Check server console for detailed debug information