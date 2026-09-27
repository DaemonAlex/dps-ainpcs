-- Minimal FiveM/oxmysql stand-ins so server/systems/*.lua load under plain lua5.4.
Config = Config or {}
Config.Debug = { enabled = false }
Config.Trust = { enabled = true, levels = {
    { name = "Stranger", minTrust = 0, maxTrust = 10 },
    { name = "Acquaintance", minTrust = 11, maxTrust = 30 },
    { name = "Trusted", minTrust = 31, maxTrust = 60 },
    { name = "Inner Circle", minTrust = 61, maxTrust = 100 } } }
Config.Memory = { maxLines = 5, talkSummary = false, minMessages = 3, summaryMaxTokens = 60, summaryExpiresDays = 30 }
Config.Ledger = { maxLines = 6, hours = 48 }
Config.AI = { provider = "ollama", apiUrl = "http://127.0.0.1:11434", model = "test" }
Config.NPCs = {}
Config.Quests = {}
Config.Ladders = {}

MySQL = { query = {}, scalar = {}, insert = {}, update = {} }
MySQL.__rows = {}      -- tests set MySQL.__rows["sql fragment"] = rows
MySQL.__scalars = {}
MySQL.__writes = {}
local function matchKey(tbl, sql)
    for k, v in pairs(tbl) do if sql:find(k, 1, true) then return v end end
end
function MySQL.query.await(sql, params) return matchKey(MySQL.__rows, sql) or {} end
function MySQL.scalar.await(sql, params) return matchKey(MySQL.__scalars, sql) end
function MySQL.insert.await(sql, params) MySQL.__writes[#MySQL.__writes + 1] = { sql = sql, params = params } return 1 end
setmetatable(MySQL.insert, { __call = function(_, sql, params) MySQL.__writes[#MySQL.__writes + 1] = { sql = sql, params = params } end })
function MySQL.update.await(sql, params) MySQL.__writes[#MySQL.__writes + 1] = { sql = sql, params = params } return 1 end

exports = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })
json = { encode = function(t) return "{}" end, decode = function(s) return {} end }
function GetGameTimer() return 0 end
function TriggerClientEvent() end
function PerformHttpRequest(url, cb) cb(500, nil, {}) end
function GetCurrentResourceName() return 'dps-ainpcs' end

TESTS = { pass = 0, fail = 0 }
function check(name, cond, detail)
    if cond then TESTS.pass = TESTS.pass + 1
    else TESTS.fail = TESTS.fail + 1; print("FAIL " .. name .. (detail and (": " .. tostring(detail)) or "")) end
end
function eq(name, got, want) check(name, got == want, ("got %s want %s"):format(tostring(got), tostring(want))) end
