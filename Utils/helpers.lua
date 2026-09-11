sharedWowauditProfiles = {}
trinketPriorities = trinketPriorities or {}
bonusRollTargets = bonusRollTargets or {}
wishlistData = wishlistData or {}
difficulties = difficulties or {}

-- Manual picks (Huge/Big/Small/Tiny) always sort below numeric wishes, even
-- when the number is small (0.71% vs Huge). Numeric wishes then compare among
-- themselves in the active display (sim value or %).
local WISH_LEVEL_RANK = {
    huge = 4,
    big = 3,
    small = 2,
    tiny = 1
}

local DEFAULT_WISH_LABELS = {
    huge = "Huge",
    big = "Big",
    small = "Small",
    tiny = "Tiny"
}

-- Website orb colours (bg-destructive / warning / success / muted-foreground).
local WISH_LEVEL_COLORS = {
    huge = "da3734",
    big = "fa8900",
    small = "238636",
    tiny = "a1a1b6"
}

-- Theme.colors.warning, used when the drop is already covered.
local WARNING_HEX = "f2bf33"
local ALREADY_EQUIPPED_PREFIX = "Already equipped"

local NUMERIC_SORT_BASE = 1000000000

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

wowauditCharacterHasWishes = function(character)
    local diffs = wishlistData and wishlistData[character]
    if not diffs then
        return false
    end
    for _, items in pairs(diffs) do
        if type(items) == "table" and next(items) ~= nil then
            return true
        end
    end
    return false
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
                if tonumber(item.id) == tonumber(itemId) then
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

local function wishLevelKey(raw)
    if type(raw) ~= "string" or raw == "" then
        return nil
    end
    local key = strlower(raw)
    if WISH_LEVEL_RANK[key] then
        return key
    end
    for canon, label in pairs(DEFAULT_WISH_LABELS) do
        if label == raw or strlower(label) == key then
            return canon
        end
    end
    return nil
end

-- Custom percentages are stored as "14.0%"; Lua's tonumber stops at the %.
wishNumericValue = function(raw)
    if type(raw) == "number" then
        return raw
    end
    if type(raw) ~= "string" then
        return nil
    end
    return tonumber((string.gsub(raw, "%%", "")))
end

-- Sort key for one wish. Sim values and custom % share the numeric band so they
-- compare in the active display (2345 vs 15.0% in value mode, 0.71 vs 15.0 in
-- % mode). Labels live in a lower band: Huge > Big > Small > Tiny.
wishSortValue = function(wish)
    if not wish then
        return 0
    end
    wish = transformWish(wish)
    local raw = wowauditValueDisplay == "VALUE" and wish.value or wish.percent
    local numeric = wishNumericValue(raw)
    if numeric then
        return NUMERIC_SORT_BASE + numeric
    end
    local level = wish.level or wishLevelKey(raw) or wishLevelKey(wish.value) or wishLevelKey(wish.percent)
    if level and WISH_LEVEL_RANK[level] then
        return WISH_LEVEL_RANK[level]
    end
    return 0
end

highestWishValue = function(wishes)
    local highest = 0
    if wishes then
        for _, wish in ipairs(wishes) do
            local value = wishSortValue(wish)
            if value > highest then
                highest = value
            end
        end
    end

    return highest
end

wowauditIsAlreadyEquippedMessage = function(message)
    return type(message) == "string" and message:sub(1, #ALREADY_EQUIPPED_PREFIX) == ALREADY_EQUIPPED_PREFIX
end

-- Short reason the wishes column should show a message instead of a ranked list.
wowauditEmptySlotMessage = function(name, wishes, sameSlot, itemID, droppedTrack, equippedLinks)
    local equipped = wowauditAlreadyHasDroppedItem(itemID, droppedTrack, equippedLinks)
    if equipped then
        return ALREADY_EQUIPPED_PREFIX .. " (" .. equipped.track .. ")"
    end
    if not wowauditCharacterHasWishes(name) then
        return "No wishlist data found"
    end
    if (not wishes or #wishes == 0) and #(sameSlot or {}) == 0 then
        return "No wishes in this slot"
    end
end

-- The dropped item and the character's other wishes for that slot, ranked
-- together by wish value. Items with no wish (including a drop that is not
-- on the list) still appear, but they sort last and do not get a rank number.
wowauditRankedSlotWishes = function(entry, sameSlot, wishes, value, priority, maxCount)
    maxCount = maxCount or 5

    local bonus
    for _, wish in ipairs(wishes or {}) do
        bonus = wish.b or wish.bonus
        if bonus then
            break
        end
    end

    local onWishlist = wishes and #wishes > 0
    local ranked = {{
        id = entry.itemID,
        bonus = bonus,
        wishes = wishes,
        isDropped = true,
        -- Dropped-item tooltip only when this character has no wish; otherwise
        -- the chip uses the wish's bonus IDs.
        link = (not onWishlist) and (entry.link or entry.string) or nil,
        priority = priority
    }}

    for _, alternative in ipairs(sameSlot or {}) do
        tinsert(ranked, alternative)
    end

    for _, item in ipairs(ranked) do
        item.value = highestWishValue(item.wishes)
        item.onWishlist = item.wishes and #item.wishes > 0
    end

    table.sort(ranked, function(a, b)
        if a.onWishlist ~= b.onWishlist then
            return a.onWishlist
        end
        if a.value == b.value then
            if a.isDropped ~= b.isDropped then
                return a.isDropped
            end
            return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
        end
        return a.value > b.value
    end)

    -- Trim extras from the bottom, never the dropped item, then leave it
    -- where the value sort placed it.
    while #ranked > maxCount do
        local removed = false
        for index = #ranked, 1, -1 do
            if not ranked[index].isDropped then
                table.remove(ranked, index)
                removed = true
                break
            end
        end
        if not removed then
            table.remove(ranked)
        end
    end

    local rank = 0
    for _, item in ipairs(ranked) do
        if item.onWishlist then
            rank = rank + 1
            item.rank = rank
        else
            item.rank = nil
        end
    end

    return ranked
end

-- Custom percentages are stored as "14.0%"; sim percents are numbers.
-- Lua strings do not escape %, so a plain find must look for "%" not "%%".
local function isManualPercent(wish)
    local function hasPercent(raw)
        return type(raw) == "string" and raw:find("%", 1, true)
    end
    if hasPercent(wish.percent) or hasPercent(wish.value) then
        return true
    end
    -- Quoted numeric value (sim scores stay numbers). Labels are non-numeric strings.
    return type(wish.value) == "string" and wishNumericValue(wish.value) and
               not wishLevelKey(wish.value)
end

-- Huge/Big/Small/Tiny use the website orb colours. Manual % is always white.
-- Numeric sim/% values keep BIS / not-BIS / outdated.
wishDisplayColor = function(wish)
    wish = transformWish(wish)
    local level = wish.level or wishLevelKey(wish.value) or wishLevelKey(wish.percent)
    if level and WISH_LEVEL_COLORS[level] then
        return level
    end
    if isManualPercent(wish) then
        return "m"
    end
    return wish.status
end

displayWish = function(wish)
    wish = transformWish(wish)

    local level = wish.level or wishLevelKey(wish.value) or wishLevelKey(wish.percent)
    local displayValue
    if level then
        -- v already holds the team's custom name ("Huge" or "Blabla").
        if type(wish.value) == "string" and not wishNumericValue(wish.value) then
            displayValue = wish.value
        else
            displayValue = DEFAULT_WISH_LABELS[level] or wish.percent
        end
    elseif wowauditValueDisplay == "VALUE" then
        displayValue = wish.value
    elseif tonumber(wish.percent) then
        displayValue = wish.percent .. "%"
    else
        displayValue = wish.percent
    end

    return specIcon(wish.spec, 12) .. withColor(displayValue, wishDisplayColor(wish))
end

transformWish = function(wish)
    wish.spec = wish.sp or wish.spec
    wish.status = wish.s or wish.status
    wish.value = wish.v or wish.value
    wish.percent = wish.p or wish.percent
    wish.comment = wish.c or wish.comment
    wish.bonus = wish.b or wish.bonus
    local level = wish.l or wish.level
    if type(level) == "string" then
        wish.level = strlower(level)
    else
        wish.level = level
    end
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
    o = "DRAGONFLIGHT_RED_COLOR", -- outdated
    m = "WHITE_FONT_COLOR" -- manual %
}

wowauditWishColorLegend = function()
    return "Wish colours",
        withColor("Manual", "m"),
        withColor("Best in slot", "b"),
        withColor("Not best in slot", "n"), withColor("Outdated", "o")
end

withColor = function(text, colorKey)
    local hex = WISH_LEVEL_COLORS[colorKey] or (colorKey == "w" and WARNING_HEX)
    if hex then
        return "|cff" .. hex .. (text or "error") .. "|r"
    end
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
