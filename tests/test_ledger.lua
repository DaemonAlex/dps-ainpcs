dofile("server/systems/ledger.lua")

eq("empty", FormatLedgerBlock({}, { news = true }), "")
local items = {
    { kind = "mdt", text = "the cops got a call about a fleeca on alta", hoursAgo = 3 },
    { kind = "street", text = "word is somebody pulled a drug sale", hoursAgo = 30 },
}
local b = FormatLedgerBlock(items, { mdt = true, street = true, news = true })
check("header", b:find("=== WHAT YOU HEARD LATELY ===", 1, true))
check("hours", b:find("3 hours ago", 1, true))
check("day", b:find("yesterday", 1, true))
check("source voice", b:find("heard from people", 1, true))

local civ = FormatLedgerBlock(items, { mdt = false, street = false, news = true })
eq("civilian hears neither", civ, "")

local s = LedgerSourcesFor({ trustCategory = "legitimate", role = "career_counselor" })
check("civ no mdt", s.mdt == false)
check("civ no street", s.street == false)
check("civ news", s.news == true)
local st = LedgerSourcesFor({ trustCategory = "criminal", role = "fence" })
check("criminal street", st.street == true)
local law = LedgerSourcesFor({ trustCategory = "legitimate", role = "lawyer" })
check("lawyer mdt", law.mdt == true)

local capped = {}
for i = 1, 10 do capped[i] = { kind = "news", text = "n" .. i, hoursAgo = i } end
local n = 0; for _ in FormatLedgerBlock(capped, { news = true }):gmatch("\n%- ") do n = n + 1 end
eq("cap 6", n, 6)

-- DB path with empty tables -> empty block, no error
MySQL.__rows = {}
eq("db empty", BuildLedgerContext({ trustCategory = "criminal", role = "lawyer" }), "")
-- DB path with one closed incident -> news line for a civilian
MySQL.__rows = { ["FROM wsb_mdt_incidents"] = { { title = "Bank Robbery", location = "Alta", h = 5 } } }
local ctx = BuildLedgerContext({ trustCategory = "legitimate", role = "greeter_info" })
check("news line", ctx:find("bank robbery in Alta", 1, true))
MySQL.__rows = {}
