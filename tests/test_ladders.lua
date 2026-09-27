dofile("data/ladders.lua")
dofile("server/systems/ladders.lua")

local L, R, I, rung = FindRungForQuest("pawn_shop_owner", "pawn_stolen_goods")
eq("ladder", L, "score"); eq("region", R, "ls"); eq("rung idx", I, 1)
eq("not on ladder", FindRungForQuest("pawn_shop_owner", "dealer_first_delivery"), nil)
eq("wrong npc", FindRungForQuest("chop_shop_boss", "pawn_stolen_goods"), nil)

MySQL.__scalars = { ["FROM ai_npc_quests"] = 2 }
check("rung complete", RungIsComplete("cid", "pawn_shop_owner", rung))
MySQL.__scalars = { ["FROM ai_npc_quests"] = 1 }
check("rung incomplete", not RungIsComplete("cid", "pawn_shop_owner", rung))

local referrals, memories, notifies = {}, {}, {}
CreateReferral = function(cid, from, to, kind) referrals[#referrals + 1] = { from = from, to = to, kind = kind } end
RememberEngine = function(cid, npc, text) memories[#memories + 1] = npc .. ":" .. text end
GetNPCById = function(id) return { id = id, name = id } end
TriggerClientEvent = function(ev, src, data) notifies[#notifies + 1] = data end

MySQL.__scalars = { ["FROM ai_npc_quests"] = 2 }
MySQL.__rows = { ["FROM ai_npc_ladders"] = {} }
MySQL.__writes = {}
eq("advance", AdvanceLadder(1, "cid", "pawn_shop_owner", "pawn_stolen_goods"), "advanced")
eq("referral to tao", referrals[1] and referrals[1].to, "chop_shop_boss")
eq("referral kind", referrals[1] and referrals[1].kind, "ladder")
check("row written", #MySQL.__writes >= 1)
eq("row rung 2", MySQL.__writes[1].params[4], 2)
eq("row active", MySQL.__writes[1].params[5], "active")
eq("memory both faces", #memories, 2)
check("player told", notifies[1] and notifies[1].description:find("Tao in La Mesa", 1, true))

eq("quest off ladder is nil", AdvanceLadder(1, "cid", "pawn_shop_owner", "dealer_first_delivery"), nil)

-- already past this rung: nothing happens
MySQL.__rows = { ["FROM ai_npc_ladders"] = { { ladder = "score", region = "ls", rung = 3, status = "active" } } }
eq("already past", AdvanceLadder(1, "cid", "pawn_shop_owner", "pawn_stolen_goods"), nil)

-- burned: nothing happens
MySQL.__rows = { ["FROM ai_npc_ladders"] = { { ladder = "score", region = "ls", rung = 1, status = "burned" } } }
eq("burned", AdvanceLadder(1, "cid", "pawn_shop_owner", "pawn_stolen_goods"), nil)

-- last rung: done + payoff
local added = {}
exports = setmetatable({}, { __index = function() return { AddItem = function(_, src, name, amount) added[#added + 1] = name .. "x" .. amount end } end })
MySQL.__rows = { ["FROM ai_npc_ladders"] = { { ladder = "score", region = "ls", rung = 3, status = "active" } } }
MySQL.__scalars = { ["FROM ai_npc_quests"] = 1 }
MySQL.__writes = {}
eq("done", AdvanceLadder(1, "cid", "arms_dealer_docks", "arms_small_delivery"), "done")
eq("payoff items", #added, 3)
eq("row done", MySQL.__writes[1].params[5], "done")

-- context line for the face that owns the current rung
MySQL.__rows = { ["FROM ai_npc_ladders"] = { { ladder = "score", region = "ls", rung = 2, status = "active" } } }
local ctx = BuildLadderContext({ id = "chop_shop_boss" }, "cid")
check("ctx step", ctx:find("step 2 of 3", 1, true))
check("ctx breadcrumb", ctx:find("Russian at the docks", 1, true))
eq("ctx other npc empty", BuildLadderContext({ id = "informant_yellowjack" }, "cid"), "")
MySQL.__rows = {}
eq("ctx no row, first face", BuildLadderContext({ id = "pawn_shop_owner" }, "cid"):find("step 1 of 3", 1, true) ~= nil, true)
eq("ctx nil citizen", BuildLadderContext({ id = "pawn_shop_owner" }, nil), "")
