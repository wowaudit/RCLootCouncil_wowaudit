local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCLootFrame = addon:GetModule("RCLootFrame")

local RCwowaudit = addon:GetModule("RCwowaudit")
local wowauditLootFrame = RCwowaudit:NewModule("wowauditLootFrame", "AceHook-3.0")

local hookRunning = false

function wowauditLootFrame:OnInitialize()
	self.initialize = true
end

function wowauditLootFrame:OnEnable()
	self:SecureHook(RCLootFrame.EntryManager, "GetEntry", "HookGetEntry")
end

function wowauditLootFrame:HookGetEntry(_, item)
	if not hookRunning then
		hookRunning = true
		local frame = RCLootFrame.EntryManager:GetEntry(item)
		if not self:IsHooked(frame, "Update") then
			self:SecureHook(frame, "Update", "HookEntryUpdate")
			frame:Update()
		end
	end
	hookRunning = false
end

function wowauditLootFrame.HookEntryUpdate(_, entry)
	local lootTable = addon:GetLootTable()
	local text = entry.itemLvl:GetText()
	local session = entry.item.sessions and entry.item.sessions[1]
	if session then
		entry.itemLvl:SetText(text.."  |cffffff00GP: ".."|TInterface\\AddOns\\RCLootCouncil_wowaudit\\Media\\logo:16:16:0:0:0:0:0:0:0:0|tTEST very long text what is gonna happen!".."|r")
	end
end
