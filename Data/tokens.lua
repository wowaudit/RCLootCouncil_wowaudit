-- Token id -> converted slot. Generated from web/config/static_data/encounter_items.json
-- (tier_token: true). Consulted in wowauditSlotForItem before GetTokenEquipLoc, because
-- RCLootCouncil's token table misses current-season tokens.
wowauditTokenSlots = {}

local function tokens(slot, ids)
    for _, id in ipairs(ids) do
        wowauditTokenSlots[id] = slot
    end
end

tokens("head", {
    225622, 225623, 225624, 225625, 237589, 237590, 237591, 237592,
    249355, 249356, 249357, 249358, 270914, 270915, 270916, 270917
})

tokens("shoulder", {
    225630, 225631, 225632, 225633, 237597, 237598, 237599, 237600,
    249363, 249364, 249365, 249366, 270922, 270923, 270924, 270925
})

tokens("chest", {
    225614, 225615, 225616, 225617, 237581, 237582, 237583, 237584,
    249347, 249348, 249349, 249350, 270926, 270927, 270928, 270929
})

tokens("hands", {
    225618, 225619, 225620, 225621, 237585, 237586, 237587, 237588,
    249351, 249352, 249353, 249354, 270910, 270911, 270912, 270913
})

tokens("legs", {
    225626, 225627, 225628, 225629, 237593, 237594, 237595, 237596,
    249359, 249360, 249361, 249362, 270918, 270919, 270920, 270921
})
