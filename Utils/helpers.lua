sharedWowauditData = {}

local itemContextDifficulties = {
    ["3"] = "N",
    ["4"] = "R",
    ["5"] = "H",
    ["6"] = "M"
}
local difficultyOrder = {"R", "N", "H", "M"}

local presentDifficulties = {}
for character, difficulties in pairs(wishlistData) do
    for difficulty, items in pairs(difficulties) do
        if presentDifficulties[difficulty] == nil and items and next(items) ~= nil then
            presentDifficulties[difficulty] = true
        end
    end
end

wowauditDataPresent = function()
    if wowauditTimestamp == nil and next(sharedWowauditData) == nil then
        return false
    else
        return true
    end
end

wowauditDataToDisplay = function(itemID, itemString, character)
    local wishes = {}
    local timestamp = nil

    for _, team in pairs(sharedWowauditData) do
        if (not timestamp or team["timestamp"] > timestamp) and team["wishes"][itemID] and
            team["wishes"][itemID][character] then
            wishes = team["wishes"][itemID][character]
            timestamp = team["timestamp"]
        end
    end

    if wowauditTimestamp ~= nil then
        local ownWishes = wowauditDataForCharacter(itemID, itemString, character)
        if next(ownWishes) ~= nil then
            if wowauditSharingSetting == 'SELF' then
                wishes = ownWishes
            else
                if timestamp == nil or wowauditTimestamp > timestamp then
                    wishes = ownWishes
                end
            end
        end
    end

    return wishes
end

wowauditDataForCharacter = function(itemID, itemString, character)
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
        return wowauditCharacterDataForDifficulty(itemID, character, difficulty, true, difficulty)
    else
        return {}
    end
end

wowauditCharacterDataForDifficulty = function(itemId, character, difficulty, initial, originalDifficulty)
    local wishes = {}
    if wishlistData[character] then
        if wishlistData[character][difficulty] == nil or next(wishlistData[character][difficulty]) == nil then
            if wowauditDifficultyMatch == "STRICT" then
                return {}
            else
                local nextDifficulty = getNextDifficulty(difficulty)
                if initial and nextDifficulty then
                    return wowauditCharacterDataForDifficulty(itemId, character, nextDifficulty,
                        wowauditDifficultyMatch == "ANY", difficulty)
                else
                    return {}
                end
            end
        else
            for _, item in ipairs(wishlistData[character][difficulty]) do
                if item.id == itemId then
                    if originalDifficulty ~= difficulty then
                        item.difficulty = difficulty
                    end

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
            local value = tonumber(wowauditValueDisplay == "VALUE" and wish.value or wish.percent)

            if value and value > highest then
                highest = value
            end
        end
    end

    return highest
end

displayWish = function(wish)
    local displayValue

    if wowauditValueDisplay == "VALUE" then
        displayValue = wish.value
    else
        if tonumber(wish.percent) then
            displayValue = wish.percent .. "%"
        else
            displayValue = wish.percent
        end
    end

    return specIcon(wish.spec, 12) .. withColor(displayValue, wish.status)
end

getNextDifficulty = function(currentDifficulty)
    for i, diff in ipairs(difficultyOrder) do
        if diff == currentDifficulty then
            local nextDifficulty = difficultyOrder[i + 1]
            if presentDifficulties[nextDifficulty] then
                return nextDifficulty
            else
                if nextDifficulty then
                    return getNextDifficulty(nextDifficulty)
                else
                    return nil
                end
            end
        end
    end
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

specToClassIcon = {
    [577] = "classicon-demonhunter",
    [581] = "classicon-demonhunter",

    [250] = "classicon-deathknight",
    [251] = "classicon-deathknight",
    [252] = "classicon-deathknight",

    [102] = "classicon-druid",
    [103] = "classicon-druid",
    [104] = "classicon-druid",
    [105] = "classicon-druid",

    [253] = "classicon-hunter",
    [254] = "classicon-hunter",
    [255] = "classicon-hunter",

    [62] = "classicon-mage",
    [63] = "classicon-mage",
    [64] = "classicon-mage",

    [268] = "classicon-monk",
    [269] = "classicon-monk",
    [270] = "classicon-monk",

    [65] = "classicon-paladin",
    [66] = "classicon-paladin",
    [70] = "classicon-paladin",

    [256] = "classicon-priest",
    [257] = "classicon-priest",
    [258] = "classicon-priest",

    [259] = "classicon-rogue",
    [260] = "classicon-rogue",
    [261] = "classicon-rogue",

    [262] = "classicon-shaman",
    [263] = "classicon-shaman",
    [264] = "classicon-shaman",

    [265] = "classicon-warlock",
    [266] = "classicon-warlock",
    [267] = "classicon-warlock",

    [71] = "classicon-warrior",
    [72] = "classicon-warrior",
    [73] = "classicon-warrior",

    [1467] = "classicon-evoker",
    [1468] = "classicon-evoker",
    [1473] = "classicon-evoker"
}

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

specIcon = function(specID, iconSize)
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

-- printtable = function(data, level)
--     if not data then
--         return
--     end
--     level = level or 0
--     local ident = strrep('     ', level)
--     if level > 6 then
--         return
--     end
--     if type(data) ~= 'table' then
--         print(tostring(data))
--     end
--     for index, value in pairs(data) do
--         repeat
--             if type(value) ~= 'table' then
--                 print(ident .. '[' .. tostring(index) .. '] = ' .. tostring(value) .. ' (' .. type(value) .. ')');
--                 break
--             end
--             print(ident .. '[' .. tostring(index) .. '] = {')
--             _G.printtable(value, level + 1)
--             print(ident .. '}');
--         until true
--     end
-- end
