sharedWowauditProfiles = {}
trinketPriorities = trinketPriorities or {}
bonusRollTargets = bonusRollTargets or {}
wishlistData = wishlistData or {}
difficulties = difficulties or {}

local difficultyOrder = {"R", "N", "H", "M"}

local presentDifficulties = {}

wowauditRebuildPresentDifficulties = function()
    wipe(presentDifficulties)
    for _, diffs in pairs(wishlistData or {}) do
        for difficulty, items in pairs(diffs) do
            if items and next(items) ~= nil then
                presentDifficulties[difficulty] = true
            end
        end
    end
end

wowauditRebuildPresentDifficulties()

wowauditDataPresent = function()
    return wowauditTimestamp ~= nil
end

wowauditDataToDisplay = function(itemID, itemString, character, difficultyOverride)
    return wowauditDataForCharacter(itemID, itemString, character, difficultyOverride)
end

wowauditDataForCharacter = function(itemID, itemString, character, difficultyOverride)
    -- Difficulty resolution lives in Utils/gear.lua so the evaluation window and
    -- this lookup can never disagree about which difficulty an item belongs to.
    local itemDifficulty = wowauditDifficultyForItem(itemString)
    local difficulty = difficultyOverride or itemDifficulty

    if difficulty then
        -- Tag against what we asked for (override or the item itself), not the
        -- native loot difficulty. Otherwise switching the evaluation header to
        -- LFR still looks up Heroic and never marks the result as (H).
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
                        wowauditDifficultyMatch == "ANY", originalDifficulty)
                else
                    return {}
                end
            end
        else
            for _, item in ipairs(wishlistData[character][difficulty]) do
                if item.id == itemId then
                    -- Copy so LENIENT tags do not leak onto the synced table and
                    -- then show up on later lookups for a different difficulty.
                    local tagged = {}
                    for k, v in pairs(item) do
                        tagged[k] = v
                    end
                    if originalDifficulty and originalDifficulty ~= difficulty then
                        tagged.difficulty = difficulty
                    else
                        tagged.difficulty = nil
                    end

                    tinsert(wishes, tagged)
                end
            end
        end
    end

    return wishes
end

highestWishValue = function(wishes)
    local highest = 0
    if wishes then
        for i, wish in ipairs(wishes) do
            wish = transformWish(wish)
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
    wish = transformWish(wish)

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

transformWish = function(wish)
    wish.spec = wish.sp or wish.spec
    wish.status = wish.s or wish.status
    wish.value = wish.v or wish.value
    wish.percent = wish.p or wish.percent
    wish.comment = wish.c or wish.comment
    wish.bonus = wish.b or wish.bonus
    return wish
end

-- item:ID:...:numBonusIDs:bonus1:bonus2 (bonus IDs start at field 15; see Utils/gear.lua)
wowauditWishItemLink = function(itemID, bonusString)
    if not itemID then
        return nil
    end
    if not bonusString or bonusString == "" then
        return itemID
    end

    local ids = {}
    for id in tostring(bonusString):gmatch("%d+") do
        tinsert(ids, id)
    end
    if #ids == 0 then
        return itemID
    end

    return "item:" .. itemID .. string.rep(":", 12) .. #ids .. ":" .. table.concat(ids, ":")
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
    local color = textColors[colorKey]
    if not color then
        return text or ""
    end
    return "|cn" .. color .. ":" .. (text or "error") .. "|r"
end

specToClassIcon = {
    [577]  = "classicon-demonhunter",
    [581]  = "classicon-demonhunter",
    [1480] = "classicon-demonhunter",

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

logoIconSmall = "|TInterface\\AddOns\\RCLootCouncil_wowaudit\\Media\\logo:12:12:0:0:0:0:0:0:0:0|t"
logoIcon = "|TInterface\\AddOns\\RCLootCouncil_wowaudit\\Media\\logo:16:16:0:0:0:0:0:0:0:0|t"
diceIcon = "|TInterface\\AddOns\\RCLootCouncil_wowaudit\\Media\\dice:14:14:0:0:0:0:0:0:0:0|t"

priorityLabel = function(rank)
    if not rank then
        return nil
    end
    return "|cnDIM_GREEN_FONT_COLOR:P" .. rank .. "|r"
end

trinketPriorityToDisplay = function(itemID, name)
    if not itemID or not name or not trinketPriorities[name] then
        return nil
    end
    return trinketPriorities[name][itemID]
end

isBonusRollTarget = function(encounterID, name)
    if not encounterID or not name then
        return false
    end
    local targets = bonusRollTargets and bonusRollTargets[encounterID]
    if not targets then
        return false
    end
    for _, target in ipairs(targets) do
        if target == name then
            return true
        end
    end
    return false
end

specIcon = function(specID, iconSize)
    local icon = select(4, GetSpecializationInfoByID(specID))
    if not icon then
        return ""
    end
    return "\124T"..icon..":"..iconSize..":"..iconSize..":0:0:64:64:4:60:4:60\124t"
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
