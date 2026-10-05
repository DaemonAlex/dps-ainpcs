--[[
    LEDGER (sources principle, 2026-09-27)
    What this NPC heard lately, drawn from the city's own records and phrased as hearsay:
      mdt    - wsb_mdt_dispatches, wsb_mdt_warrants (police-adjacent faces only)
      street - ai_npc_rumors (criminal and street faces)
      news   - closed wsb_mdt_incidents (everyone)
    The website and news feeds plug into the same block later.
]]

local STREET_CATEGORIES = {
    criminal = true, drugs = true, street = true, underground = true, weapons = true, heist = true,
    cartel = true, vagos = true, ballas = true, families = true, lostmc = true, triads = true,
}
local MDT_ROLES = { lawyer = true, doctor = true, police_contact = true, greeter_info = false }
local STREET_ROLES = { street_informant = true, street_sage = true, bartender = true }

function LedgerSourcesFor(npc)
    local cat = npc and npc.trustCategory or ""
    local role = npc and npc.role or ""
    return {
        mdt = MDT_ROLES[role] == true,
        street = STREET_CATEGORIES[cat] == true or STREET_ROLES[role] == true,
        news = true,
    }
end

local function ago(hours)
    hours = tonumber(hours)
    if not hours or hours < 1 then return "just now" end
    if hours < 24 then return ("%d hours ago"):format(math.floor(hours)) end
    if hours < 48 then return "yesterday" end
    return ("%d days ago"):format(math.floor(hours / 24))
end

function FormatLedgerBlock(items, sources)
    if not items or #items == 0 then return "" end
    sources = sources or { news = true }
    local maxLines = (Config.Ledger and Config.Ledger.maxLines) or 6
    local out = { "=== WHAT YOU HEARD LATELY ===" }
    local n = 0
    for _, it in ipairs(items) do
        if it.kind == "news" or sources[it.kind] then
            n = n + 1
            out[#out + 1] = ("- %s, %s"):format(it.text, ago(it.hoursAgo))
            if n >= maxLines then break end
        end
    end
    if n == 0 then return "" end
    out[#out + 1] = "You heard from people, not from a screen. Say who told you if asked, hedge, get a detail slightly wrong now and then."
    return table.concat(out, "\n") .. "\n"
end

function BuildLedgerContext(npc)
    local cfg = Config.Ledger or {}
    local hours = cfg.hours or 48
    local sources = LedgerSourcesFor(npc)
    local items = {}
    if sources.mdt then
        local rows = MySQL.query.await([[
            SELECT type, title, location, TIMESTAMPDIFF(HOUR, created_at, NOW()) AS h
            FROM wsb_mdt_dispatches WHERE created_at > NOW() - INTERVAL ? HOUR
            ORDER BY created_at DESC LIMIT 6
        ]], { hours }) or {}
        for _, r in ipairs(rows) do
            items[#items + 1] = { kind = "mdt", hoursAgo = r.h,
                text = ("the cops got a call about %s near %s"):format(string.lower(r.title or r.type or "something"), r.location or "town") }
        end
        local w = MySQL.query.await([[
            SELECT title, TIMESTAMPDIFF(HOUR, created_at, NOW()) AS h FROM wsb_mdt_warrants
            WHERE status = 'active' ORDER BY created_at DESC LIMIT 3
        ]], {}) or {}
        for _, r in ipairs(w) do
            items[#items + 1] = { kind = "mdt", hoursAgo = r.h, text = ("there is paper out on someone: %s"):format(string.lower(r.title or "")) }
        end
    end
    if sources.street then
        local rows = MySQL.query.await([[
            SELECT action_type, TIMESTAMPDIFF(HOUR, created_at, NOW()) AS h FROM ai_npc_rumors
            WHERE is_public = 1 AND (expires_at IS NULL OR expires_at > NOW())
            ORDER BY created_at DESC LIMIT 6
        ]], {}) or {}
        for _, r in ipairs(rows) do
            items[#items + 1] = { kind = "street", hoursAgo = r.h, text = ("word is somebody pulled a %s"):format((r.action_type or "job"):gsub("_", " ")) }
        end
    end
    local news = MySQL.query.await([[
        SELECT title, location, TIMESTAMPDIFF(HOUR, closed_at, NOW()) AS h FROM wsb_mdt_incidents
        WHERE status = 'closed' AND closed_at > NOW() - INTERVAL ? HOUR
        ORDER BY closed_at DESC LIMIT 4
    ]], { hours * 3 }) or {}
    for _, r in ipairs(news) do
        items[#items + 1] = { kind = "news", hoursAgo = r.h,
            text = ("it was on the news: %s%s"):format(string.lower(r.title or "an arrest"), r.location and (" in " .. r.location) or "") }
    end
    table.sort(items, function(a, b) return (tonumber(a.hoursAgo) or 0) < (tonumber(b.hoursAgo) or 0) end)
    return FormatLedgerBlock(items, sources)
end
