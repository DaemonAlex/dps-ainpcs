dofile("server/systems/facts.lua")

eq("tier stranger", TierIndexForLevel("Stranger"), 1)
eq("tier acq", TierIndexForLevel("Acquaintance"), 2)
eq("tier trusted", TierIndexForLevel("Trusted"), 3)
eq("tier inner", TierIndexForLevel("Inner Circle"), 4)
eq("tier unknown", TierIndexForLevel("nonsense"), 1)
eq("tier nil", TierIndexForLevel(nil), 1)

local facts = { rumors = { "R1" }, basic = { "B1", "B2" }, detailed = { "D1" }, secret = { "S1" } }
eq("no facts field", FormatFactsBlock(nil, 3), "")
eq("empty facts table", FormatFactsBlock({}, 3), "")

local b1 = FormatFactsBlock(facts, 1)
check("stranger sees rumors", b1:find("R1", 1, true))
check("stranger hides basic", not b1:find("B1", 1, true))
check("stranger hides secret", not b1:find("S1", 1, true))
check("stranger gets deflect line", b1:find("not telling them yet", 1, true))

local b3 = FormatFactsBlock(facts, 3)
check("trusted sees detailed", b3:find("D1", 1, true))
check("trusted hides secret", not b3:find("S1", 1, true))

local b4 = FormatFactsBlock(facts, 4)
check("inner sees secret", b4:find("S1", 1, true))
check("inner no deflect line", not b4:find("not telling them yet", 1, true))

eq("npc without facts", BuildFactsContext({ id = "x" }, "Trusted"), "")
check("npc with facts", BuildFactsContext({ id = "x", facts = facts }, "Trusted"):find("D1", 1, true))
