local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCLootCouncilML = addon:GetModule("RCLootCouncilML")
local RCVotingFrame = addon:GetModule("RCVotingFrame")

local RCwowaudit = addon:GetModule("RCwowaudit")
local wowauditVotingFrame = RCwowaudit:NewModule("wowauditVotingFrame", "AceComm-3.0", "AceConsole-3.0", "AceHook-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceSerializer-3.0")

local session = 1
local next = next

function wowauditVotingFrame:OnInitialize()
	if not RCVotingFrame.scrollCols then -- RCVotingFrame hasn't been initialized.
		return self:ScheduleTimer("OnInitialize", 0.5)
	end

  tinsert(RCVotingFrame.scrollCols, 8, {
    name = "Wishlist (wowaudit)",
    DoCellUpdate = wowauditVotingFrame.SetCellWishlist,
    colName = "wishlist",
    sortnext = 5,
    width = 120,
  })

	tinsert(RCVotingFrame.scrollCols, 9, {
		name = "",
		DoCellUpdate = wowauditVotingFrame.SetCellWishlistNote,
		colName = "wishlistNote",
		sortNext = 10,
		width = 30,
	})

  self:RegisterMessage("RCSessionChangedPre", "OnMessageReceived")
end

function wowauditVotingFrame:SetCellWishlist(frame, data, cols, row, realrow, column, fShow, table, ...)
  local lootTable = addon:GetLootTable()

  if lootTable then
		local wishes = wowauditData(data[realrow].name, lootTable[session].itemID, lootTable[session].string)

		local text = ""
		for i, wish in ipairs(wishes) do
			text = text .. specIcon(wish.spec) .. withColor(wish.value, wish.status) .. (i == 2 and "\n" or "    ")
		end

		if string.len(text) > 0 then
			frame.text:SetText(text)
			data[realrow].cols[column].value = text
			return
		end
  end

	frame.text:SetText("-")
	data[realrow].cols[column].value = "-"
end

function wowauditVotingFrame:SetCellWishlistNote(frame, data, cols, row, realrow, column, fShow, table, ...)
	local lootTable = addon:GetLootTable()

  if lootTable then
		local wishes = wowauditData(data[realrow].name, lootTable[session].itemID, lootTable[session].string)

		local text = ""
		for i, wish in ipairs(wishes) do
			if wish.comment then
				text = text .. specIcon(wish.spec) .. wish.comment .. "\n\n"
			end
		end

		if string.len(text) > 0 then
			local name = data[realrow].name
			local f = frame.noteBtn or CreateFrame("Button", nil, frame)
			f:SetSize(20, 20)
			f:SetPoint("CENTER", frame, "CENTER")
			f:SetNormalTexture("Interface/BUTTONS/UI-GuildButton-PublicNote-Up.png")
			f:SetScript("OnEnter", function() addon:CreateTooltip("Wishlist comment", text)	end)
			f:SetScript("OnLeave", function() addon:HideTooltip() end)
			data[realrow].cols[column].value = 1
			frame.noteBtn = f
		end
	end
end

function wowauditVotingFrame:OnMessageReceived(msg, ...)
  if msg == "RCSessionChangedPre" then
    local s = unpack({...})
    session = s
  end
end
