wowauditValueDisplay = 'value'
sharedDataTimestamp = nil
sharedWowauditData = {}
itemContextDifficulties = {
    ["3"] = "N",
    ["4"] = "R",
    ["5"] = "H",
    ["6"] = "M"
}

wowauditDataPresent = function()
    if wowauditTimestamp == nil and sharedDataTimestamp == nil then
        return false
    else
        return true
    end
end

wowauditDataToDisplay = function(itemID, itemString, character)
    if sharedDataTimestamp ~= nil and (wowauditTimestamp == nil or sharedDataTimestamp > wowauditTimestamp) then
        if sharedWowauditData[itemID] and sharedWowauditData[itemID][character] then
            return sharedWowauditData[itemID][character]
        end
    else
        return wowauditDataForCharacter(itemID, itemString, character)
    end
end

wowauditDataForCharacter = function(itemID, itemString, character)
    local wishes = {}
    local difficulty = nil
    for property in string.gmatch(itemString, "([^:]+)") do
        if difficulties[property] then
            difficulty = difficulties[property]
        end
    end

    -- Items from the dungeon journal don't have bonus IDs, but they do have itemContext.
    if not difficulty then
        difficulty = itemContextDifficulties[getValueFromItemLink(itemString, 12)]
    end

    if difficulty then
        if wishlistData[character] and wishlistData[character][difficulty] then
            for _, item in ipairs(wishlistData[character][difficulty]) do
                if item.id == itemID then
                    tinsert(wishes, item)
                end
            end
        end
    end

    return wishes
end

wowauditDataForItem = function(itemID, itemString)
    local characters = {}
    for character, _ in pairs(wishlistData) do
        local wishes = wowauditDataForCharacter(itemID, itemString, character)
        if #wishes > 0 then
            characters[character] = wishes
        end
    end

    return characters
end

highestWishValue = function(wishes)
    local highest = 0
    if wishes then
        for i, wish in ipairs(wishes) do
            local value = wowauditValueDisplay == "value" and wish.value or wish.percent

            if value > highest then
                highest = value
            end
        end
    end

    return highest
end

-- status values are one-character acronyms on purpose, to save space.
textColors = {
    b = "DIM_GREEN_FONT_COLOR", -- BIS
    n = "YELLOW_THREAT_COLOR", -- not BIS
    o = "DRAGONFLIGHT_RED_COLOR" -- outdated
}

withColor = function(text, colorKey)
    return "|cn" .. textColors[colorKey] .. ":" .. (text or "error") .. "|r"
end

-- Copied from Details/functions/profiles.lua
specCoords = {
    [577] = {128 / 512, 192 / 512, 256 / 512, 320 / 512}, -- havoc demon hunter
    [581] = {192 / 512, 256 / 512, 256 / 512, 320 / 512}, -- vengeance demon hunter

    [250] = {0, 64 / 512, 0, 64 / 512}, -- blood dk
    [251] = {64 / 512, 128 / 512, 0, 64 / 512}, -- frost dk
    [252] = {128 / 512, 192 / 512, 0, 64 / 512}, -- unholy dk

    [102] = {192 / 512, 256 / 512, 0, 64 / 512}, -- druid balance
    [103] = {256 / 512, 320 / 512, 0, 64 / 512}, -- druid feral
    [104] = {320 / 512, 384 / 512, 0, 64 / 512}, -- druid guardian
    [105] = {384 / 512, 448 / 512, 0, 64 / 512}, -- druid resto

    [253] = {448 / 512, 512 / 512, 0, 64 / 512}, -- hunter bm
    [254] = {0, 64 / 512, 64 / 512, 128 / 512}, -- hunter marks
    [255] = {64 / 512, 128 / 512, 64 / 512, 128 / 512}, -- hunter survivor

    [62] = {(128 / 512) + 0.001953125, 192 / 512, 64 / 512, 128 / 512}, -- mage arcane
    [63] = {192 / 512, 256 / 512, 64 / 512, 128 / 512}, -- mage fire
    [64] = {256 / 512, 320 / 512, 64 / 512, 128 / 512}, -- mage frost

    [268] = {320 / 512, 384 / 512, 64 / 512, 128 / 512}, -- monk bm
    [269] = {448 / 512, 512 / 512, 64 / 512, 128 / 512}, -- monk ww
    [270] = {384 / 512, 448 / 512, 64 / 512, 128 / 512}, -- monk mw

    [65] = {0, 64 / 512, 128 / 512, 192 / 512}, -- paladin holy
    [66] = {64 / 512, 128 / 512, 128 / 512, 192 / 512}, -- paladin protect
    [70] = {(128 / 512) + 0.001953125, 192 / 512, 128 / 512, 192 / 512}, -- paladin ret

    [256] = {192 / 512, 256 / 512, 128 / 512, 192 / 512}, -- priest disc
    [257] = {256 / 512, 320 / 512, 128 / 512, 192 / 512}, -- priest holy
    [258] = {(320 / 512) + (0.001953125 * 4), 384 / 512, 128 / 512, 192 / 512}, -- priest shadow

    [259] = {384 / 512, 448 / 512, 128 / 512, 192 / 512}, -- rogue assassination
    [260] = {448 / 512, 512 / 512, 128 / 512, 192 / 512}, -- rogue combat
    [261] = {0, 64 / 512, 192 / 512, 256 / 512}, -- rogue sub

    [262] = {64 / 512, 128 / 512, 192 / 512, 256 / 512}, -- shaman elemental
    [263] = {128 / 512, 192 / 512, 192 / 512, 256 / 512}, -- shamel enhancement
    [264] = {192 / 512, 256 / 512, 192 / 512, 256 / 512}, -- shaman resto

    [265] = {256 / 512, 320 / 512, 192 / 512, 256 / 512}, -- warlock aff
    [266] = {320 / 512, 384 / 512, 192 / 512, 256 / 512}, -- warlock demo
    [267] = {384 / 512, 448 / 512, 192 / 512, 256 / 512}, -- warlock destro

    [71] = {448 / 512, 512 / 512, 192 / 512, 256 / 512}, -- warrior arms
    [72] = {0, 64 / 512, 256 / 512, 320 / 512}, -- warrior fury
    [73] = {64 / 512, 128 / 512, 256 / 512, 320 / 512}, -- warrior protect

    [1467] = {256 / 512, 320 / 512, 256 / 512, 320 / 512}, -- Devastation
    [1468] = {320 / 512, 384 / 512, 256 / 512, 320 / 512}, -- Preservation
    [1473] = {384 / 512, 448 / 512, 256 / 512, 320 / 512} -- Augmentation
}

logoIconSmall = "|TInterface\\AddOns\\RCLootCouncil_wowaudit\\Media\\logo:12:12:0:0:0:0:0:0:0:0|t"
logoIcon = "|TInterface\\AddOns\\RCLootCouncil_wowaudit\\Media\\logo:16:16:0:0:0:0:0:0:0:0|t"

specIcon = function(specID)
    local iconSize = 12
    local L, R, T, B = unpack(specCoords[specID])
    return "|TInterface\\AddOns\\RCLootCouncil_wowaudit\\Media\\spec_icons_normal:" .. iconSize .. ":" .. iconSize ..
               ":0:0:512:512:" .. (L * 512) .. ":" .. (R * 512) .. ":" .. (T * 512) .. ":" .. (B * 512) .. "|t "
end

-- https://wowpedia.fandom.com/wiki/ItemLink
getValueFromItemLink = function(itemLink, index)
    local result = {}
    for match in (itemLink .. ":"):gmatch("(.-)" .. ":") do
        table.insert(result, match)
    end
    return result[index]
end
