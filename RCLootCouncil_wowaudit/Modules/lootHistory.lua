local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local ItemUtils = addon.Require "Utils.Item"

local RCwowaudit = addon:GetModule("RCwowaudit")
local wowauditLootHistory = RCwowaudit:NewModule("wowauditLootHistory", "AceComm-3.0", "AceConsole-3.0", "AceHook-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceSerializer-3.0")

function wowauditLootHistory:OnInitialize()
	self:RegisterMessage("RCMLLootHistorySend", "OnMessageReceived")
end

function wowauditLootHistory:OnMessageReceived(msg, ...)
	if msg == "RCMLLootHistorySend" then
		local history_table, winner, responseID, boss, reason, session, candData = unpack({...})

    -- Wait a little before enriching, the message is sent before the loot is added to the history
    self:ScheduleTimer(function()
      self:EnrichLootHistory(history_table, winner, responseID, boss, reason, session, candData)
    end, 1)
	end
end

function wowauditLootHistory:EnrichLootHistory(history_table, winner, responseID, boss, reason, session, candData)
  local lootTable = addon:GetLootTable()

  if addon.lootDB.factionrealm[winner] and lootTable then
    for index, entry in ipairs(addon.lootDB.factionrealm[winner]) do
      if history_table["id"] == entry["id"] then
        local itemID = ItemUtils:GetItemIDFromLink(history_table["lootWon"])
        local itemString = ItemUtils:GetItemStringFromLink(history_table["lootWon"])

        entry["same_response_amount"] = self:CountSameResponseAsWinner(session, responseID)
        entry["wishes"] = wowauditDataForCharacter(itemID, itemString, winner)
      end
    end
  end
end

function wowauditLootHistory:CountSameResponseAsWinner(session, responseID)
  local sameVoteAmount = 0

  for name in addon:GroupIterator() do
    local playerResponseID = addon:GetActiveModule("votingframe"):GetCandidateData(session, name, "response")
    if playerResponseID == responseID then
      sameVoteAmount = sameVoteAmount + 1
    end
  end

  return sameVoteAmount
end
