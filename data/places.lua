--[[
    PLACES A LOCAL KNOWS (DPS 2026-09-27)
    Real spots on this server, nothing invented. Each NPC is handed the ones near where
    he stands plus the few everyone knows, as facts; how he talks about them is his voice.
    kind is plain words the model can use. known = 'everyone' means every NPC hears it.
    Coords: business board walk 2026-09-26, script configs, vanilla landmarks.
]]
Places = {
    -- everyone knows these
    { name = "Los Santos International Airport, arrivals hall", kind = "airport", coords = vector3(-1093.10, -2835.84, 28.04), area = "Los Santos", known = "everyone" },
    { name = "Diamond Casino", kind = "casino and hotel", coords = vector3(927.68, 49.65, 81.54), area = "Los Santos", known = "everyone" },
    { name = "Pillbox hospital", kind = "big hospital, Ocean Medical", coords = vector3(307.16, -595.21, 43.28), area = "Los Santos", known = "everyone" },
    { name = "Mission Row police station", kind = "LSPD station", coords = vector3(428.23, -984.28, 30.71), area = "Los Santos", known = "everyone" },
    { name = "Bolingbroke Penitentiary", kind = "state prison", coords = vector3(1845.0, 2585.0, 45.7), area = "Grand Senora", known = "everyone" },
    { name = "the Maze Bank branch inside the airport", kind = "bank", coords = vector3(-1079.88, -2792.12, 21.36), area = "Los Santos", known = "everyone" },
    { name = "the job centre by the Legion Square garage", kind = "place to get hired for regular work", coords = vector3(-268.95, -956.13, 31.22), area = "Los Santos", known = "everyone" },

    -- Los Santos
    { name = "Vanilla Unicorn", kind = "strip club", coords = vector3(127.92, -1284.64, 29.28), area = "Los Santos", note = "off Elgin Avenue, Strawberry" },
    { name = "Bahama Mamas West", kind = "nightclub and bar", coords = vector3(-1386.05, -593.02, 30.32), area = "Los Santos" },
    { name = "Koi", kind = "Japanese restaurant, hires staff", coords = vector3(-1034.73, -1484.28, 4.58), area = "Los Santos" },
    { name = "Pizza This", kind = "pizza place, hires staff", coords = vector3(812.0, -752.99, 26.78), area = "Los Santos" },
    { name = "the Cat Cafe", kind = "cafe with cats, hires staff", coords = vector3(-581.06, -1066.22, 22.34), area = "Los Santos" },
    { name = "Dynasty 8 real estate, top floor of the Mile High tower", kind = "real estate office", coords = vector3(-176.0, -977.18, 264.99), area = "Los Santos" },
    { name = "the City Works yard", kind = "city maintenance job, clock in and fix the grid", coords = vector3(884.47, -2337.14, 29.34), area = "Los Santos" },

    -- Sandy Shores (the business board walk)
    { name = "the Yellow Jack Inn", kind = "roadhouse bar, rough crowd", coords = vector3(1985.0, 3053.0, 47.2), area = "Sandy Shores" },
    { name = "Revolution", kind = "night club", coords = vector3(1678.87, 3772.06, 29.58), area = "Sandy Shores" },
    { name = "Threads", kind = "clothing store", coords = vector3(1698.05, 3754.39, 34.63), area = "Sandy Shores" },
    { name = "Kirkland law firm", kind = "lawyers", coords = vector3(1695.19, 3755.22, 40.24), area = "Sandy Shores" },
    { name = "the Sandy Fleeca", kind = "bank", coords = vector3(1645.44, 3721.01, 34.16), area = "Sandy Shores" },
    { name = "Rinshot Cookies", kind = "bakery", coords = vector3(1630.89, 3736.37, 34.85), area = "Sandy Shores" },
    { name = "PipeDown Tobacco", kind = "smoke shop", coords = vector3(1619.3, 3727.24, 34.68), area = "Sandy Shores" },
    { name = "Wholesome Bakes", kind = "bakery", coords = vector3(1625.03, 3708.61, 34.55), area = "Sandy Shores" },
    { name = "Dream Cream", kind = "ice cream parlour", coords = vector3(1614.07, 3708.16, 34.59), area = "Sandy Shores" },
    { name = "InkInc", kind = "tattoo shop", coords = vector3(1598.5, 3710.54, 34.99), area = "Sandy Shores" },
    { name = "Cuts & Shaves", kind = "barber", coords = vector3(1607.84, 3714.34, 34.62), area = "Sandy Shores" },
    { name = "Ronnies Carwash", kind = "car wash", coords = vector3(1981.58, 3766.52, 32.26), area = "Sandy Shores" },
    { name = "the Boat House", kind = "boats, marina", coords = vector3(1532.67, 3784.5, 34.51), area = "Sandy Shores" },
    { name = "PostOp depot", kind = "parcel depot", coords = vector3(1716.22, 3759.15, 34.42), area = "Sandy Shores" },
    { name = "the Fire Museum", kind = "museum", coords = vector3(1707.77, 3784.75, 35.49), area = "Sandy Shores" },
    { name = "Breasy Joe's", kind = "diner", coords = vector3(1897.56, 3890.88, 33.66), area = "Sandy Shores" },
    { name = "Strike Zone", kind = "bowling alley", coords = vector3(1934.69, 3886.05, 32.6), area = "Sandy Shores" },
    { name = "Digital Den", kind = "electronics store", coords = vector3(1935.32, 3821.11, 32.47), area = "Sandy Shores" },
    { name = "Sandy Auto Parts", kind = "car parts", coords = vector3(1931.17, 3837.95, 32.48), area = "Sandy Shores" },
    { name = "the Sandy Ammu-Nation", kind = "gun store", coords = vector3(1935.47, 3840.3, 32.47), area = "Sandy Shores" },
    { name = "Drugs-N-Stuff", kind = "pharmacy", coords = vector3(1943.81, 3824.27, 32.47), area = "Sandy Shores" },
    { name = "the General Store of Sandy Beach", kind = "general store", coords = vector3(1942.41, 3845.0, 32.47), area = "Sandy Shores" },
    { name = "Sandy's Market", kind = "grocery", coords = vector3(2005.32, 3784.53, 32.2), area = "Sandy Shores" },
    { name = "the Church of Sandy Shores", kind = "church", coords = vector3(1809.42, 3909.83, 35.04), area = "Sandy Shores" },
    { name = "the Dusty Boot", kind = "bar", coords = vector3(1882.45, 3913.79, 33.29), area = "Sandy Shores" },
    { name = "the Sandy sheriff station", kind = "BCSO station", coords = vector3(1853.0, 3689.0, 34.3), area = "Sandy Shores" },
    { name = "the Sandy airfield", kind = "small airfield", coords = vector3(1740.0, 3290.0, 41.1), area = "Sandy Shores" },

    -- Grapeseed
    { name = "Up & Atom", kind = "burger joint", coords = vector3(1800.81, 4596.42, 37.33), area = "Grapeseed" },
    { name = "the Grapeseed farms", kind = "farms you can work or buy", coords = vector3(2221.0, 4931.05, 40.84), area = "Grapeseed" },
    { name = "the farm shop", kind = "seeds and animals for farmers", coords = vector3(2030.4, 4980.38, 41.1), area = "Grapeseed" },
    { name = "the farm market", kind = "sells crops and animal goods", coords = vector3(2310.5, 4884.98, 40.81), area = "Grapeseed" },

    -- Roxwood
    { name = "Chulz Family Farm", kind = "farm for sale", coords = vector3(-1805.42, 7069.76, 32.62), area = "Roxwood" },
    { name = "Roxwood Raceway", kind = "race track, hires track crew", coords = vector3(-2869.0, 8427.4, 87.7), area = "Roxwood" },
    { name = "Roxwood police", kind = "RPD station", coords = vector3(-464.0, 7087.8, 20.0), area = "Roxwood" },
    { name = "Roxwood hospital", kind = "hospital", coords = vector3(-511.2, 7385.5, 12.0), area = "Roxwood" },
    { name = "Roxwood fire station", kind = "fire station", coords = vector3(-438.3, 7085.5, 21.0), area = "Roxwood" },
}
