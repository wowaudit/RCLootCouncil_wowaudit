local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local Comms = addon.Require "Services.Comms"
local Player = addon.Require "Data.Player"

local RCwowaudit = addon:GetModule("RCwowaudit")
local wowauditBonusLoot = RCwowaudit:NewModule("wowauditBonusLoot")

-- Long enough to cover a raid night, short enough that the list stays tiny.
local KEEP_FOR = 12 * 60 * 60

local function store()
    local db = addon:Getdb()
    db.wowauditBonusLoot = db.wowauditBonusLoot or {}
    return db.wowauditBonusLoot
end

function wowauditBonusLoot:OnInitialize()
    -- RCLootCouncil registers BONUS_ROLL_RESULT and broadcasts the win to the group,
    -- so there is nothing to parse out of the chat log: anyone who shows up as a
    -- candidate is running RCLootCouncil already.
    Comms:Subscribe(addon.PREFIXES.MAIN, "bonus_roll", function(data, sender)
        local kind, link = unpack(data)
        if kind == "item" then
            self:Record(sender, link)
        end
    end)

    self:Prune()
end

function wowauditBonusLoot:Record(sender, link)
    local player = sender and Player:Get(sender)
    local character = player and player.name or sender
    local itemID = link and tonumber(link:match("item:(%d+)"))

    if not character or not itemID then
        return
    end

    tinsert(store(), {
        name = character,
        itemID = itemID,
        encounter = addon.lastEncounterID,
        time = time()
    })

    self:Prune()
end

function wowauditBonusLoot:Prune()
    local entries = store()
    local cutoff = time() - KEEP_FOR

    for index = #entries, 1, -1 do
        if (entries[index].time or 0) < cutoff then
            table.remove(entries, index)
        end
    end
end

-- What a character won from their bonus roll on a given encounter, if anything.
wowauditBonusLootFor = function(name, encounterID)
    if not name or not encounterID then
        return nil
    end

    local newest = nil
    for _, entry in ipairs(store()) do
        if entry.name == name and entry.encounter == encounterID then
            if not newest or (entry.time or 0) > (newest.time or 0) then
                newest = entry
            end
        end
    end

    return newest
end
