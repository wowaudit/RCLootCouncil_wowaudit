local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local Comms = addon.Require "Services.Comms"
local ItemUtils = addon.Require "Utils.Item"
local Player = addon.Require "Data.Player"

local RCwowaudit = addon:GetModule("RCwowaudit")
local wowauditShareData = RCwowaudit:NewModule("wowauditShareData", "AceComm-3.0", "AceConsole-3.0", "AceHook-3.0",
    "AceEvent-3.0", "AceTimer-3.0", "AceSerializer-3.0")

RCwowaudit.PREFIXES = {
    MAIN = "RCau"
}

-- Comms:Subscribe asserts that the prefix is one RCLootCouncil knows about, so ours
-- is registered at load time: any module subscribing during initialisation is then
-- safe regardless of the order they initialise in.
addon.PREFIXES.WOWAUDIT = RCwowaudit.PREFIXES.MAIN

function wowauditShareData:OnInitialize()
    RCwowaudit.Send = Comms:GetSender(RCwowaudit.PREFIXES.MAIN)

    self:RegisterMessage("RCMLAddItem", "OnMessageReceived")

    Comms:BulkSubscribe(RCwowaudit.PREFIXES.MAIN, {
        wishlist_data = function(data, sender)
            self:OnWishlistDataReceived(unpack(data))
        end,
        request_wishlist_data = function(data, sender)
            self:OnWishlistDataRequested(unpack(data))
        end,
        profile = function(data, sender)
            self:OnProfileReceived(sender, unpack(data))
        end,
        request_profile = function(data, sender)
            RCwowaudit:GetModule("wowauditGearProfile"):SendOnRequest()
        end
    })
end

function wowauditShareData:OnMessageReceived(msg, ...)
    if msg == "RCMLAddItem" then
        local item, entry = unpack({...})
        local itemID = ItemUtils:GetItemIDFromLink(item)

        if wowauditTimestamp == nil then
            RCwowaudit:Send("group", "request_wishlist_data", itemID, entry.string)
        else
            self:SendWishlistData(itemID, entry.string, true)
        end
    end
end

function wowauditShareData:SendWishlistData(itemID, itemString, fromMasterLooter)
    if itemID and wowauditTimestamp ~= nil then
        RCwowaudit:Send("group", "wishlist_data", itemID, itemString, wowauditTimestamp,
            wowauditDataForItem(itemID, itemString), teamID or 0, fromMasterLooter,
            trinketPrioritiesForItem(itemID))
    end
end

function wowauditShareData:OnWishlistDataReceived(itemID, itemString, timestamp, wishes, team, fromMasterLooter, priorities)
    if sharedWowauditData[team] == nil then
        sharedWowauditData[team] = {
            timestamp = timestamp,
            wishes = {
                [itemID] = wishes
            },
            priorities = {
                [itemID] = priorities or {}
            }
        }
    else
        if sharedWowauditData[team]["wishes"][itemID] == nil or timestamp > sharedWowauditData[team]["timestamp"] then
            sharedWowauditData[team]["timestamp"] = timestamp
            sharedWowauditData[team]["wishes"][itemID] = wishes
            sharedWowauditData[team]["priorities"] = sharedWowauditData[team]["priorities"] or {}
            sharedWowauditData[team]["priorities"][itemID] = priorities or {}
        end
    end

    if fromMasterLooter and team ~= (teamID or 0) then
        self:SendWishlistData(itemID, itemString, false)
    end
end

function wowauditShareData:OnWishlistDataRequested(itemID, itemString)
    self:SendWishlistData(itemID, itemString, false)
end

-- Keyed the same way RCLootCouncil keys its candidates, so a row can look up the
-- sender's profile without any name juggling. The payload comes from another
-- player's client, so it is normalised rather than trusted.
function wowauditShareData:OnProfileReceived(sender, data)
    if type(data) ~= "table" or not sender then
        return
    end

    local player = Player:Get(sender)
    local name = player and player.name or sender

    data.cr = type(data.cr) == "table" and data.cr or {}
    data.eq = type(data.eq) == "table" and data.eq or {}
    sharedWowauditProfiles[name] = data
    -- AceComm's sender string is not always the loot-table candidate key.
    if sender ~= name then
        sharedWowauditProfiles[sender] = data
    end
end

-- One request per loot table. Reopening the window is not another raid-wide
-- ask; a new loot table is, so a council member who missed the first wave can
-- still recover.
local allowProfileRequest = true

function wowauditShareData:AllowProfileRequest()
    allowProfileRequest = true
end

function wowauditShareData:RequestProfiles()
    if not IsInGroup() or not allowProfileRequest then
        return
    end

    allowProfileRequest = false
    RCwowaudit:Send("group", "request_profile")
end
