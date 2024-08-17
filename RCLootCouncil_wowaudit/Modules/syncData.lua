local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local Comms = addon.Require "Services.Comms"
local ItemUtils = addon.Require "Utils.Item"

local RCwowaudit = addon:GetModule("RCwowaudit")
local wowauditSyncData = RCwowaudit:NewModule("wowauditSyncData", "AceComm-3.0", "AceConsole-3.0", "AceHook-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceSerializer-3.0")

function wowauditSyncData:OnInitialize()
	self:RegisterMessage("RCMLAddItem", "OnMessageReceived")

  Comms:Subscribe(
		addon.PREFIXES.MAIN,
		"wishlist_data",
		function(data, sender)
			if addon:IsMasterLooter(sender) then
				self:OnWishlistDataReceived(unpack(data))
			end
		end
	)
end

function wowauditSyncData:OnMessageReceived(msg, ...)
	if msg == "RCMLAddItem" then
		local item, entry = unpack({...})

    if wowauditDataPresent() then
      local itemID = ItemUtils:GetItemIDFromLink(item)
      -- addon:Send("group", "wishlist_data", itemID, wowauditTimestamp, wowauditDataForItem(itemID, entry.string))
    end
	end
end

function wowauditSyncData:OnWishlistDataReceived(itemID, timestamp, wishes)
  syncedDataTimestamp = timestamp
  syncedWowauditData[itemID] = wishes
end
