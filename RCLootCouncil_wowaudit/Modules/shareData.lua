local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local Comms = addon.Require "Services.Comms"
local ItemUtils = addon.Require "Utils.Item"

local RCwowaudit = addon:GetModule("RCwowaudit")
local wowauditShareData = RCwowaudit:NewModule("wowauditShareData", "AceComm-3.0", "AceConsole-3.0", "AceHook-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceSerializer-3.0")

function wowauditShareData:OnInitialize()
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

function wowauditShareData:OnMessageReceived(msg, ...)
	if msg == "RCMLAddItem" then
		local item, entry = unpack({...})

		local itemID = ItemUtils:GetItemIDFromLink(item)
    if wowauditTimestamp ~= nil and itemID then
      addon:Send("group", "wishlist_data", itemID, wowauditTimestamp, wowauditDataForItem(itemID, entry.string))
    end
	end
end

function wowauditShareData:OnWishlistDataReceived(itemID, timestamp, wishes)
  sharedDataTimestamp = timestamp
  sharedWowauditData[itemID] = wishes
end
