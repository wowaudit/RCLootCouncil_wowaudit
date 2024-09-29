local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local Comms = addon.Require "Services.Comms"
local ItemUtils = addon.Require "Utils.Item"

local RCwowaudit = addon:GetModule("RCwowaudit")
local wowauditShareData = RCwowaudit:NewModule("wowauditShareData", "AceComm-3.0", "AceConsole-3.0", "AceHook-3.0",
    "AceEvent-3.0", "AceTimer-3.0", "AceSerializer-3.0")

function wowauditShareData:OnInitialize()
    self:RegisterMessage("RCMLAddItem", "OnMessageReceived")

    Comms:Subscribe(addon.PREFIXES.MAIN, "wishlist_data", function(data, sender)
        self:OnWishlistDataReceived(unpack(data))
    end)

    Comms:Subscribe(addon.PREFIXES.MAIN, "request_wishlist_data", function(data, sender)
        self:OnWishlistDataRequested(unpack(data))
    end)
end

function wowauditShareData:OnMessageReceived(msg, ...)
    if msg == "RCMLAddItem" then
        local item, entry = unpack({...})
        local itemID = ItemUtils:GetItemIDFromLink(item)

        if wowauditTimestamp == nil then
            addon:Send("group", "request_wishlist_data", itemID, entry.string)
        else
            self:SendWishlistData(itemID, entry.string, true)
        end
    end
end

function wowauditShareData:SendWishlistData(itemID, itemString, fromMasterLooter)
    if itemID and wowauditTimestamp ~= nil then
        addon:Send("group", "wishlist_data", itemID, itemString, wowauditTimestamp,
            wowauditDataForItem(itemID, itemString), teamID or 0, fromMasterLooter)
    end
end

function wowauditShareData:OnWishlistDataReceived(itemID, itemString, timestamp, wishes, team, fromMasterLooter)
    if sharedWowauditData[team] == nil then
        sharedWowauditData[team] = {
            timestamp = timestamp,
            wishes = {
                [itemID] = wishes
            }
        }
    else
        if sharedWowauditData[team]["wishes"][itemID] == nil or timestamp > sharedWowauditData[team]["timestamp"] then
            sharedWowauditData[team]["timestamp"] = timestamp
            sharedWowauditData[team]["wishes"][itemID] = wishes
        end
    end

    if fromMasterLooter and team ~= (teamID or 0) then
        self:SendWishlistData(itemID, itemString, false)
    end
end

function wowauditShareData:OnWishlistDataRequested(itemID, itemString)
    self:SendWishlistData(itemID, itemString, false)
end
