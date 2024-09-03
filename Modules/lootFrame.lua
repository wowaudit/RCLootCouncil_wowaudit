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
    local text = entry.itemLvl:GetText()

    if not wowauditDataPresent() then
        entry.itemLvl:SetText(text .. " - " .. logoIcon .. withColor(' wowaudit data missing', 'o'))
    else
        local lootTable = addon:GetLootTable()

        local session = entry.item.sessions and entry.item.sessions[1]
        if session then
            local wishes = wowauditDataToDisplay(lootTable[session].itemID, lootTable[session].string, addon.playerName)

            local wishText = ""
            if wishes then
                for i, wish in ipairs(wishes) do
                    wishText = wishText .. specIcon(wish.spec) .. withColor(displayWish(wish), wish.status) .. " "
                end
            end

            if string.len(wishText) > 0 then
                entry.itemLvl:SetText(text .. " - " .. logoIcon .. " " .. wishText)
                return
            end

            entry.itemLvl:SetText(text .. " - " .. logoIcon .. withColor(' not on wishlist', 'n'))
        end
    end
end
