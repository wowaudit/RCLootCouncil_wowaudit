local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")

local itemContextDifficulties = {
    ["3"] = "N",
    ["4"] = "R",
    ["5"] = "H",
    ["6"] = "M"
}

-- Equipped items that compete for the same wish. Both chest types, both finger and
-- trinket slots and every one-hand variant collapse into a single key, so "other
-- items you have wishes for in this slot" matches what a player would expect.
local slotByEquipLoc = {
    INVTYPE_HEAD = "head",
    INVTYPE_NECK = "neck",
    INVTYPE_SHOULDER = "shoulder",
    INVTYPE_CLOAK = "back",
    INVTYPE_CHEST = "chest",
    INVTYPE_ROBE = "chest",
    INVTYPE_WRIST = "wrist",
    INVTYPE_HAND = "hands",
    INVTYPE_WAIST = "waist",
    INVTYPE_LEGS = "legs",
    INVTYPE_FEET = "feet",
    INVTYPE_FINGER = "finger",
    INVTYPE_TRINKET = "trinket",
    INVTYPE_WEAPON = "weapon",
    INVTYPE_WEAPONMAINHAND = "weapon",
    INVTYPE_WEAPONOFFHAND = "weapon",
    INVTYPE_2HWEAPON = "weapon",
    INVTYPE_RANGED = "weapon",
    INVTYPE_RANGEDRIGHT = "weapon",
    INVTYPE_SHIELD = "offhand",
    INVTYPE_HOLDABLE = "offhand"
}

local equippedSlots = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17}

local twoHandedEquipLocs = {
    INVTYPE_2HWEAPON = true,
    INVTYPE_RANGED = true,
    INVTYPE_RANGEDRIGHT = true
}

-- Resolves the loot's difficulty from its bonus IDs, falling back to the item
-- context for dungeon journal items which carry no bonus IDs.
wowauditDifficultyForItem = function(itemString)
    if not itemString then
        return nil
    end

    local difficulty = nil
    for property in string.gmatch(itemString, "([^:]+)") do
        if difficulties[property] then
            difficulty = difficulties[property]
        end
    end

    -- Items from the dungeon journal don't have bonus IDs, but they do have
    -- itemContext. In "item:ID:enchant:g1:g2:g3:g4:suffix:unique:level:spec:
    -- modifiersMask:itemContext:..." that is the 13th field (field 12 is the
    -- modifiersMask, which is why reading 12 never matched).
    return difficulty or itemContextDifficulties[getValueFromItemLink(itemString, 13)]
end

-- Bonus IDs start at field 15 of an item string (field 1 being "item", or the
-- colour and hyperlink prefix for a full link). Scanning from 14 skips enchant,
-- gem and uniqueID fields, whose values can otherwise fall inside a track's bonus
-- ID range and report the wrong upgrade track. The split has to keep empty fields
-- so the positions stay meaningful.
local FIRST_BONUS_ID_FIELD = 14

-- Journal and /rc test items often have a difficulty (itemContext) but no upgrade
-- bonus IDs. The crest column still needs a track, and raid difficulty maps onto one.
local difficultyTrackNames = {
    M = "Myth",
    H = "Hero",
    N = "Champion",
    R = "Veteran"
}

local function trackFromBonusFields(itemString, fromField)
    local position = 0
    for field in (itemString .. ":"):gmatch("(.-):") do
        position = position + 1
        if position >= fromField then
            local track = wowauditTrackByBonusId[tonumber(field) or 0]
            if track then
                return track
            end
        end
    end
end

local function trackTotal(trackName)
    for _, info in pairs(wowauditTrackByBonusId) do
        if info.track == trackName then
            return info.total
        end
    end
    return 6
end

local function canonicalTrackName(trackString)
    if not trackString or trackString == "" then
        return nil
    end
    if wowauditTrackQuality[trackString] then
        return trackString
    end

    local lowered = strlower(trackString)
    for _, name in ipairs(wowauditTrackOrder) do
        if lowered == strlower(name) or strfind(lowered, strlower(name), 1, true) then
            return name
        end
    end
end

-- The tooltip's "Upgrade Level: Hero 3/6" comes from this API. Bonus-ID parsing
-- misses journal and /rc test links, which is how the header ended up stuck on 1/6.
local function trackFromUpgradeAPI(itemInfo)
    if not itemInfo or not C_Item.GetItemUpgradeInfo then
        return nil
    end

    local info = C_Item.GetItemUpgradeInfo(itemInfo)
    if type(info) ~= "table" then
        return nil
    end

    local trackName = canonicalTrackName(info.trackString)
    if not trackName then
        return nil
    end

    local total = (info.maxLevel and info.maxLevel > 0) and info.maxLevel or trackTotal(trackName)
    local step = tonumber(info.currentLevel) or 0
    if step < 1 then
        step = 1
    end

    return {
        track = trackName,
        step = step,
        total = total
    }
end

-- `strict` is for real items (equipped gear): trust only the upgrade API and current
-- season bonus IDs. The loose field-1 scan and the difficulty fallback below exist for
-- journal and /rc test links of the dropped item; on genuine gear they invent a track
-- (e.g. an old Mythic item reported as "Myth 1/6") from itemContext, so gear passes
-- strict = true and simply gets no badge when it isn't on a current track.
wowauditTrackForItem = function(itemStringOrLink, strict)
    if not itemStringOrLink then
        return nil
    end

    local raw = tostring(itemStringOrLink)
    local fromAPI = trackFromUpgradeAPI(raw)
    if fromAPI then
        return fromAPI
    end

    -- Full links carry a colour prefix and a trailing "|h[Name]|h|r", which would
    -- otherwise glue itself to the last bonus ID and stop it parsing as a number.
    local itemString = string.match(raw, "item:[%d:%-]+")
    if not itemString then
        -- RCLootCouncil's loot table stores `string` with the "item:" prefix
        -- already stripped for comms (`268233::::::::16:4:12841:...`).
        if string.match(raw, "^%d") then
            itemString = "item:" .. raw
        else
            itemString = nil
        end
    end

    if itemString then
        fromAPI = trackFromUpgradeAPI(itemString)
        if fromAPI then
            return fromAPI
        end

        local track = trackFromBonusFields(itemString, FIRST_BONUS_ID_FIELD)
        if track then
            return track
        end

        -- Cleaned strings don't always line up with field 14. Difficulty already
        -- finds these IDs by scanning every field; do the same for the step.
        if not strict then
            track = trackFromBonusFields(itemString, 1)
            if track then
                return track
            end
        end
    end

    if strict then
        return nil
    end

    local difficulty = itemString and wowauditDifficultyForItem(itemString) or wowauditDifficultyForItem(raw)
    local trackName = difficulty and difficultyTrackNames[difficulty]
    if not trackName then
        return nil
    end

    return {
        track = trackName,
        step = 1,
        total = trackTotal(trackName)
    }
end

wowauditTrackLabel = function(track)
    if not track then
        return nil
    end
    return track.track .. " " .. track.step .. "/" .. track.total
end

wowauditTrackColor = function(trackName)
    local quality = trackName and wowauditTrackQuality[trackName]
    local color = quality and ITEM_QUALITY_COLORS[quality]
    if not color then
        return 0.7, 0.7, 0.7
    end
    return color.r, color.g, color.b
end

-- How many upgrade steps the item still has left on its own track.
wowauditStepsLeft = function(track)
    if not track then
        return 0
    end
    return math.max(0, track.total - track.step)
end

-- Memoised: an item's slot never changes, and this is called for every wish of
-- every candidate whenever the window redraws.
local slotCache = {}

wowauditSlotForItem = function(itemID)
    if not itemID then
        return nil
    end

    local cached = slotCache[itemID]
    if cached ~= nil then
        return cached or nil
    end

    local slot
    local tokenSlot = wowauditTokenSlots and wowauditTokenSlots[itemID]
    if tokenSlot then
        slot = tokenSlot
    else
        local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)

        if equipLoc and slotByEquipLoc[equipLoc] then
            slot = slotByEquipLoc[equipLoc]
        else
            -- Tier tokens have no equip location of their own; RCLootCouncil knows
            -- which slot they turn into, for older tokens not in Data/tokens.lua.
            local tokenEquipLoc = addon:GetTokenEquipLoc(itemID)
            slot = tokenEquipLoc and slotByEquipLoc[tokenEquipLoc] or nil
        end
    end

    slotCache[itemID] = slot or false
    return slot
end

-- The difficulty whose wishes we should read for a character. Mirrors the leniency
-- in wowauditCharacterDataForDifficulty exactly: STRICT never looks further,
-- LENIENT allows a single hop up, ANY keeps climbing.
local function effectiveDifficulty(character, difficulty)
    if not difficulty or not wishlistData[character] then
        return nil
    end

    local mayClimb = wowauditDifficultyMatch ~= "STRICT"
    local current = difficulty

    while current do
        local wishes = wishlistData[character][current]
        if wishes and next(wishes) ~= nil then
            return current
        end

        if not mayClimb then
            return nil
        end

        mayClimb = wowauditDifficultyMatch == "ANY"
        current = getNextDifficulty(current)
    end

    return nil
end

-- Grouping a character's wishes by slot only depends on the synced wishlist, which
-- cannot change without a reload, so it is cached per character, difficulty and
-- dropped item. Only the ordering is redone per call, since that depends on whether
-- values or percentages are being displayed.
local slotWishCache = {}

wowauditInvalidateSlotWishes = function()
    slotWishCache = {}
end

local function groupSameSlotWishes(character, itemID, difficulty)
    local slot = wowauditSlotForItem(itemID)
    if not slot then
        return {}
    end

    local resolved = effectiveDifficulty(character, difficulty)
    if not resolved then
        return {}
    end

    local results = {}
    local byItem = {}

    for _, wish in ipairs(wishlistData[character][resolved]) do
        if wish.id ~= itemID and wowauditSlotForItem(wish.id) == slot then
            if not byItem[wish.id] then
                byItem[wish.id] = {}
                tinsert(results, {
                    id = wish.id,
                    bonus = wish.b or wish.bonus,
                    wishes = byItem[wish.id],
                    -- Compare to the difficulty we asked for (header override or
                    -- the loot itself). Comparing to the loot's native difficulty
                    -- hid (H) on every alternative when the drop was already Heroic.
                    difficulty = (resolved ~= difficulty) and resolved or nil,
                    priority = trinketPriorities[character] and trinketPriorities[character][wish.id]
                })
            end
            tinsert(byItem[wish.id], wish)
        end
    end

    return results
end

-- Other items the character has wishes for in the same slot, best value first.
-- After a full sync the displayed wishlistData is complete for the active team.
wowauditSameSlotWishes = function(character, itemID, difficulty)
    if not character or not itemID or not wishlistData[character] then
        return {}
    end

    local perCharacter = slotWishCache[character]
    if not perCharacter then
        perCharacter = {}
        slotWishCache[character] = perCharacter
    end

    local key = (difficulty or "?") .. ":" .. itemID
    local results = perCharacter[key]
    if not results then
        results = groupSameSlotWishes(character, itemID, difficulty)
        perCharacter[key] = results
    end

    for _, entry in ipairs(results) do
        entry.value = highestWishValue(entry.wishes)
    end

    table.sort(results, function(a, b)
        if a.value == b.value then
            return a.id < b.id
        end
        return a.value > b.value
    end)

    return results
end

-- Crests the player still holds, and how many they can still earn this season.
wowauditCrestInfo = function(trackName)
    local currencyID = wowauditCrestCurrencies[trackName]
    if not currencyID then
        return nil
    end

    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if not info then
        return nil
    end

    local earnable = nil
    if info.maxQuantity and info.maxQuantity > 0 then
        earnable = math.max(0, info.maxQuantity - (info.totalEarned or 0))
    end

    return {
        left = info.quantity or 0,
        earnable = earnable,
        icon = info.iconFileID,
        name = info.name
    }
end

wowauditCatalystCharges = function()
    local info = C_CurrencyInfo.GetCurrencyInfo(wowauditCatalystCurrencyID)
    if not info then
        return nil
    end

    return {
        amount = info.quantity or 0,
        icon = info.iconFileID,
        name = info.name
    }
end

-- Bonus roll coins, matching what the /rc coins window reports.
wowauditBonusRollInfo = function()
    local info = C_CurrencyInfo.GetCurrencyInfo(wowauditBonusRollCurrencyID)
    if not info then
        return nil
    end

    return {
        left = info.quantity or 0,
        earned = info.totalEarned or 0,
        cap = info.maxQuantity or 0,
        icon = info.iconFileID,
        name = info.name
    }
end

-- RCLootCouncil only tracks the last encounter the raid finished, which is wrong for
-- items awarded later or sessions spanning several bosses. The generated item map in
-- Data/encounters.lua gives the encounter the item itself came from.
wowauditEncounterForItem = function(itemID)
    return itemID and wowauditItemEncounters[itemID] or nil
end

wowauditBonusRollTargetForItem = function(itemID, name)
    local mapped = itemID and wowauditItemEncounters[itemID]

    if mapped then
        return isBonusRollTarget(mapped, name)
    end

    -- Known to drop outside any encounter, so there is nothing to be a target for.
    if mapped == false then
        return false
    end

    -- Unknown item, most likely from content this map doesn't cover. In a dungeon the
    -- last encounter is a dungeon boss, which never appears in bonusRollTargets.
    return isBonusRollTarget(addon.lastEncounterID, name)
end

-- Counts equipped items per upgrade track, along with the upgrades already applied
-- and the ones still available. An item at Myth 3/6 has had two upgrades and has
-- three to go. Two-handers count double, matching how the website reports gear.
wowauditScanEquipped = function()
    local summary = {}

    for _, slot in ipairs(equippedSlots) do
        local link = GetInventoryItemLink("player", slot)
        local track = link and wowauditTrackForItem(link, true)

        if track then
            local weight = 1
            if slot == INVSLOT_MAINHAND then
                local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
                if twoHandedEquipLocs[equipLoc] and not GetInventoryItemLink("player", INVSLOT_OFFHAND) then
                    weight = 2
                end
            end

            local entry = summary[track.track] or {
                count = 0,
                stepsDone = 0,
                stepsLeft = 0,
                items = {}
            }

            entry.count = entry.count + weight
            entry.stepsDone = entry.stepsDone + (track.step - 1) * weight
            entry.stepsLeft = entry.stepsLeft + wowauditStepsLeft(track) * weight

            -- Listed once even when a two-hander counts double in the totals, so the
            -- evaluation tooltip can show each piece rather than a phantom copy.
            local itemID = GetInventoryItemID("player", slot) or C_Item.GetItemInfoInstant(link)
            if itemID then
                tinsert(entry.items, {itemID, track.step, track.total})
            end

            summary[track.track] = entry
        end
    end

    return summary
end
