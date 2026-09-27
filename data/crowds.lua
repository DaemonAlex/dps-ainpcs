--[[
    CROWDS (real-people pass, 2026-09-27)
    A pool of regulars for a place, spawned at random spots around it each session, some
    sitting on the real stools and chairs, some standing with a drink. Each is a talkable
    AI face with a name, one trait, one thing on its mind, and rumour-level knowledge only.
    Shared script: ExpandCrowds() appends the generated NPC entries to Config.NPCs on both
    sides so ids match. Client-only placement lives in client/main.lua (CrowdSpawn).

    Damon 2026-09-27: "can we increase AI activity overall in the Yellow Jack",
    "more than that randomly all over the bar", "some standing some sitting".
]]
Config = Config or {}

Config.Crowds = {
    yellowjack = {
        label = "the Yellow Jack Inn",
        center = vector4(1998.04, 3054.68, 47.06, 203.2),  -- DPS 2026-09-27 Damon: "spawn them in the lot not on the roof" (/spot yj-lot #179)
        counter = nil,                                     -- no counter outside: sitters take a bench if one is near, else they stand
        radius = 12.0,
        -- Damon 2026-09-27: "I will spot some stools and seats so you can get people in those". Sitters take a free
        -- one of these (vector4, heading = the way the seat faces) with a proper sit scenario; standers stay random.
        seats = {  -- Damon /spot seat1..seat10 2026-09-27 (#180-#189): bar stools and tables inside the Yellow Jack
            vector4(1985.32, 3053.08, 47.02, 24.2),
            vector4(1984.70, 3052.26, 47.12, 50.4),
            vector4(1984.22, 3051.54, 47.02, 57.4),
            vector4(1989.12, 3049.02, 46.72, 344.2),
            vector4(1996.66, 3049.20, 46.72, 118.8),
            vector4(1989.46, 3046.16, 46.72, 57.8),
            vector4(1987.48, 3046.48, 46.72, 262.8),
            vector4(1985.74, 3055.92, 47.02, 133.0),
            vector4(1984.66, 3056.88, 47.02, 145.2),
            vector4(1981.20, 3056.70, 46.72, 322.0),
        },
        -- DPS 2026-09-27 Damon: "stop a_f_m_salton_01 from spawning there in the 1983.45 3049.82 47.21" — that is
        -- the bartender's side of the counter. No regular spawns within this radius of these points.
        keepOut = { { pos = vector3(1983.45, 3049.82, 47.21), radius = 3.0 } },
        hours = nil,                -- DPS 2026-09-27 Damon: no clock gating, the whole pool shows all day
        dayCount = 99,              -- (set hours = {18, 4} and dayCount = 2 to thin the bar by day again)
        rumors = {
            "People who want work drink here after dark and talk to the skinny guy out by the lot.",
            "The bartender hears everything and repeats none of it, unless you tip.",
            "Cops from the sheriff's office come in for the chili on Thursdays.",
            "The trailer park is where the county's problems go to sleep.",
            "Somebody keeps stealing diesel off the farm road at night.",
        },
    },
}

-- sit = true means try a stool or chair first, else a standing pose.
-- spot = vector4 pins a regular to one hand-set place (Damon 2026-09-27: "they are on the roof and sitting on top
-- of stuff, let me hand set location"); without it the client picks a random floor spot around the counter.
CrowdPersonas = {
    yellowjack = {
        { key = "earl",    name = "Earl",        model = "a_m_m_hillbilly_02", sit = true,  trait = "Retired oil-field hand, drinks slow, talks slower. Calls everyone 'chief'.", onMind = "Your truck failed inspection again and you blame the mechanic.", samples = { "Chief, if it ain't broke, you ain't looked hard enough.", "Sit down or don't, you're making the beer nervous." } },
        { key = "darlene", name = "Darlene",     model = "a_f_m_salton_01",     sit = true,  trait = "Waitress on her night off, laughs loud, knows every marriage in Sandy.", onMind = "Your sister is moving back in with you and you are not ready.", samples = { "Oh honey, that one? Don't. Just don't.", "I'm off tonight, so the answer's no, whatever you're about to ask." } },
        { key = "tanner",  name = "Tanner",      model = "a_m_y_motox_01",      sit = false, trait = "Dirt-bike kid, all elbows, thinks he's tougher than he is.", onMind = "You crashed your bike and you have not told your dad.", samples = { "Bro. Bro. You seen the jump out past the airfield? Insane.", "I could take him. Easy. Not tonight though." } },
        { key = "rosa",    name = "Rosa",        model = "a_f_y_rurmeth_01",    sit = false, trait = "Twitchy, sweet, borrows cigarettes she never returns. Knows the trailer park.", onMind = "You owe someone money and they were here an hour ago.", samples = { "Got a smoke? I'll pay you back, I always pay back.", "Don't go out to the park after two, that's all I'm saying." } },
        { key = "walt",    name = "Walt",        model = "a_m_o_acult_01",      sit = true,  trait = "Old-timer, ex-preacher, half deaf, hears more than he lets on.", onMind = "The church roof leaks again and nobody will help you fix it.", samples = { "Speak up, son. No, louder. No, that's shouting.", "Everybody in this county is running from something. Most of them badly." } },
        { key = "jolene",  name = "Jolene",      model = "a_f_m_fatwhite_01",   sit = true,  trait = "Runs the trailer park bingo, gossip queen, fierce about her dog.", onMind = "Your dog got out again and half the park saw you chasing it in a robe.", samples = { "You didn't hear it from me, but you heard it from me.", "Bingo's Tuesdays. Bring cash, not excuses." } },
        { key = "dale",    name = "Dale",        model = "a_m_m_salton_02",     sit = false, trait = "Long-haul trucker on a layover, tired, generous with advice nobody asked for.", onMind = "Dispatch gave you a Roxwood run tomorrow and you hate that road at night.", samples = { "Take the 68 if it's raining. Trust me. Don't trust me, take the 68 anyway.", "Coffee here's bad. Beer's fine. Pick." } },
        { key = "skeeter", name = "Skeeter",     model = "g_m_y_lost_01",       sit = false, trait = "Lost MC hang-around, not patched, wants to be. Loud about it.", onMind = "The club told you to shut up for a week and you're on day two.", samples = { "You know who I ride with? Nah, you don't. Forget it.", "*grins* Everybody here's a friend of mine till they ain't." } },
        -- Damon 2026-09-27: "the Yellow Jack is a gang hangout, there should be biker NPCs around the place esp at night"
        { key = "hatchet", name = "Hatchet",     model = "g_m_y_lost_02",       sit = false, trait = "Patched Lost MC. Fifty, scarred, speaks in short sentences and means every one.", onMind = "A prospect wrecked a bike last night and the club is deciding what that costs him.", samples = { "This is our bar. You're welcome in it. Keep it that way.", "*looks you up and down* You lost? Wrong word to use in here." } },
        { key = "gravy",   name = "Gravy",       model = "g_m_y_lost_03",       sit = true,  trait = "Patched Lost MC, big, cheerful until he isn't. Eats constantly.", onMind = "Somebody's been selling on the club's road without asking and the club noticed.", samples = { "Try the chili. No, really. I'm not asking.", "*laughs* Relax. If we had a problem with you, you'd know. You'd really know." } },
        { key = "trix",    name = "Trix",        model = "g_f_y_lost_01",       sit = false, trait = "Rides with the Lost, sharper than any of them, does the counting. Watches the door.", onMind = "You saw a sheriff's cruiser sit at the end of the road for twenty minutes today.", samples = { "Sit anywhere but that table. That table's spoken for.", "You ask a lot of questions for somebody who just walked in." } },
    },
}

-- Build the NPC entries for every crowd. Deterministic, so client and server agree on ids.
function ExpandCrowds()
    if not Config.Crowds or not Config.NPCs then return 0 end
    local added = 0
    for key, crowd in pairs(Config.Crowds) do
        local pool = CrowdPersonas[key] or {}
        for i, p in ipairs(pool) do
            local id = ("crowd_%s_%s"):format(key, p.key)
            local exists = false
            for _, npc in ipairs(Config.NPCs) do if npc.id == id then exists = true break end end
            if not exists then
                local schedule = nil
                if crowd.hours and i > (crowd.dayCount or 0) then
                    schedule = { { time = { crowd.hours[1], crowd.hours[2] }, active = true }, { time = { crowd.hours[2], crowd.hours[1] }, active = false } }
                end
                Config.NPCs[#Config.NPCs + 1] = {
                    id = id,
                    name = p.name,
                    model = p.model,
                    homeLocation = crowd.center,
                    movement = { pattern = "crowd", radius = crowd.radius },
                    schedule = schedule,
                    crowd = { key = key, slot = i, sit = p.sit == true, spot = p.spot },
                    role = "crowd",
                    trustCategory = "social",
                    voice = Config.Voices and Config.Voices.male_street or nil,
                    facts = { rumors = crowd.rumors },
                    voiceSamples = p.samples,
                    onMindFixed = p.onMind,
                    personality = {
                        type = "Regular at " .. crowd.label,
                        traits = p.trait,
                        knowledge = "What a regular hears in this bar, nothing more",
                        greeting = "*looks up from the drink* Yeah?",
                    },
                    contextReactions = { copReaction = "neutral", hasDrugs = "neutral", hasMoney = "neutral", hasCrimeTools = "neutral" },
                    intel = {},
                    systemPrompt = ("You are %s, a regular at %s. %s\n\nYOU ARE NOT A SOURCE. You know bar talk and your own life. If someone pushes you for real names, places or work, you point them at the bartender or at the skinny guy who hangs around the lot, and you get back to your drink. You do not lead anyone anywhere. Keep it short, keep it in character, under 60 words."):format(p.name, crowd.label, p.trait),
                }
                added = added + 1
            end
        end
    end
    return added
end

ExpandCrowds()
