-- Maps loot to the encounter it drops from, so bonus roll targets can be checked
-- against the item on the table instead of the last boss the raid happened to kill.
-- RCLootCouncil records no per-item encounter: its entry.boss is just the last
-- ENCOUNTER_END, which is wrong as soon as a session spans several kills.
-- Keys are droptimizer encounter IDs, matching bonusRollTargets in Data/db.lua.
-- `false` marks loot that drops outside any encounter, so it is known to have no
-- bonus roll target rather than merely being absent from this map.
-- Generated from web/config/static_data/encounter_items.json; regenerate each tier.
wowauditItemEncounters = {}

local function encounter(droptimizerID, itemIDs)
    for _, itemID in ipairs(itemIDs) do
        wowauditItemEncounters[itemID] = droptimizerID
    end
end

-- Season 17

encounter(2711, { -- Rotmire
    268280, 268282, 268283, 268284, 268285, 268286, 268287, 268288, 268289, 268290, 268291,
    268292
})

encounter(2733, { -- Imperator Averzian
    249275, 249279, 249293, 249306, 249310, 249313, 249319, 249320, 249323, 249326, 249334,
    249335, 249344
})

encounter(2734, { -- Vorasius
    249276, 249302, 249315, 249317, 249327, 249332, 249336, 249342, 249351, 249352, 249353,
    249354, 249925
})

encounter(2735, { -- Vaelgor & Ezzorak
    249280, 249287, 249305, 249318, 249321, 249331, 249339, 249346, 249359, 249360, 249361,
    249362, 249370
})

encounter(2736, { -- Fallen-King Salhadaar
    249281, 249298, 249304, 249308, 249314, 249316, 249337, 249340, 249341, 249363, 249364,
    249365, 249366
})

encounter(2737, { -- Lightblinded Vanguard
    249277, 249294, 249303, 249311, 249330, 249333, 249355, 249356, 249357, 249358, 249369,
    249808
})

encounter(2738, { -- Crown of the Cosmos
    249288, 249295, 249309, 249312, 249325, 249329, 249345, 249368, 249380, 249382, 249809,
    260423
})

encounter(2739, { -- Belo'ren, Child of Al'ar
    249283, 249284, 249307, 249322, 249324, 249328, 249376, 249377, 249806, 249807, 249919,
    249921, 260235
})

encounter(2740, { -- Midnight Falls
    249286, 249296, 249367, 249810, 249811, 249912, 249913, 249914, 249915, 249920, 250247,
    260408
})

encounter(2795, { -- Chimaerus
    249278, 249343, 249347, 249348, 249349, 249350, 249371, 249373, 249374, 249381, 249805,
    249922
})

-- Season 18

encounter(2849, { -- Nymrissa Wavecaller
    268199, 268217, 268221, 268226, 268232, 268238, 268244, 268247, 268262, 268263, 268266,
    270167
})

encounter(2871, { -- Sszorak
    268201, 268206, 268233, 268234, 268252, 268257, 270163, 270174, 270918, 270919, 270920,
    270921
})

encounter(2874, { -- Entombed Sentinels
    268197, 268198, 268204, 268219, 268224, 268228, 268250, 270165, 270910, 270911, 270912,
    270913
})

encounter(2882, { -- Vashnik the Malignant
    268205, 268214, 268246, 268249, 268254, 268260, 270161, 270166, 270926, 270927, 270928,
    270929
})

encounter(2883, { -- The Coiled Altar
    268209, 268211, 268213, 268222, 268225, 268231, 268237, 268243, 268253, 268255, 268256,
    268259, 270169, 270173, 275937, 275938
})

encounter(2887, { -- The Twin Fangs
    268220, 268223, 268241, 268251, 268261, 268264, 270170, 270171, 270914, 270915, 270916,
    270917
})

encounter(2888, { -- Nek'zali the Soulcoiler
    268203, 268208, 268216, 268218, 268229, 268230, 268235, 268236, 268240, 268245, 268248,
    270162, 270930, 281227
})

encounter(2894, { -- The Lost Explorers
    268196, 268200, 268210, 268227, 268239, 268242, 268258, 270160, 270164, 270922, 270923,
    270924, 270925
})

encounter(2895, { -- Ula'tek
    268202, 268207, 268215, 268265, 270168, 270175, 270909, 271092, 271093, 271874, 271875,
    271876, 271878
})

-- Trash and other instance-wide drops: no encounter, so no bonus roll target.
encounter(false, {
    271434, 271435, 271436, 271438, 271440, 271441, 271444, 271445, 271638
})
