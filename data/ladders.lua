--[[
    LADDERS (mold engine slice 3) — data only.
    A rung: the face that owns it, the quests that finish it, and either a breadcrumb
    (a referral to the next face plus the line the player hears) or a payoff.
    Rung 0, the hook, is the first face's rumors facts and hail line: nothing to track.
    Quest ids must exist in quests.lua under the owning face's quest set (role).
]]
Config = Config or {}
Config.Ladders = {
    score = {
        ls = {
            label = "Score, Los Santos",
            rungs = {
                {
                    npc = "pawn_shop_owner",
                    quests = { "pawn_collect_item", "pawn_stolen_goods" },
                    breadcrumb = { npc = "chop_shop_boss", line = "Sal says Tao in La Mesa needs drivers who don't ask questions." },
                },
                {
                    npc = "chop_shop_boss",
                    quests = { "chop_first_boost" },
                    breadcrumb = { npc = "arms_dealer_docks", line = "Tao says a Russian at the docks sells the tools for bigger work." },
                },
                {
                    npc = "arms_dealer_docks",
                    quests = { "arms_small_delivery" },
                    payoff = { kind = "items", items = { { name = "c4_bomb", amount = 2 }, { name = "usb_stick", amount = 1 }, { name = "drill", amount = 1 } } },
                },
            },
        },
    },
}
