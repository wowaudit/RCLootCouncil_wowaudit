local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCwowaudit = addon:GetModule("RCwowaudit")
local wowauditBonusRoll = RCwowaudit:NewModule("wowauditBonusRoll", "AceComm-3.0", "AceSerializer-3.0", "AceTimer-3.0")

local CURRENCY_ID = 3418
local COMM_PREFIX = "WowauditCoins"

local function normalizeRealm(realm)
    if not realm or realm == "" then
        return (GetNormalizedRealmName() or ""):gsub("%s+", "")
    end
    return realm:gsub("%s+", "")
end

local function fullName(name, realm)
    if not name or name == "" then
        return nil
    end
    if string.find(name, "-", 1, true) then
        return name
    end
    return name .. "-" .. normalizeRealm(realm)
end

local function playerFullName()
    local name, realm = UnitFullName("player")
    return fullName(name, realm)
end

function wowauditBonusRoll:OnInitialize()
    if not addon.optionsFrame then -- RCLootCouncil hasn't been initialized.
        return self:ScheduleTimer("OnInitialize", 0.5)
    end

    self:RegisterComm(COMM_PREFIX)

    -- Delegate the window to the companion addon, which owns the UI/roster logic.
    addon:ModuleChatCmd(self, "ShowBonusRolls", "coins",
        "Open the wowaudit bonus roll window (alt. 'bonusrolls')", "coins", "bonusrolls")
end

function wowauditBonusRoll:ShowBonusRolls()
    local companion = LibStub("AceAddon-3.0"):GetAddon("WowauditBonusRoll", true)
    if companion and companion.ShowWindow then
        companion:ShowWindow()
    else
        addon:Print("The Wowaudit Companion addon is required to view the bonus roll window.")
    end
end

function wowauditBonusRoll:OnCommReceived(_, msg, _, sender)
    -- Companion addon owns replies when present; avoid double-whispering.
    if LibStub("AceAddon-3.0"):GetAddon("WowauditBonusRoll", true) then
        return
    end

    local ok, payload = self:Deserialize(msg)
    if not ok or type(payload) ~= "table" or payload.cmd ~= "REQ" then
        return
    end

    if not sender or sender == "" then
        return
    end

    local selfName = playerFullName()
    local senderName = fullName(sender)
    if selfName and senderName and selfName == senderName then
        return
    end

    local info = C_CurrencyInfo.GetCurrencyInfo(CURRENCY_ID)
    if not info then
        return
    end

    local _, _, classId = UnitClass("player")
    self:SendCommMessage(COMM_PREFIX, self:Serialize({
        cmd = "RESP",
        left = info.quantity or 0,
        earned = info.totalEarned or 0,
        cap = info.maxQuantity or 0,
        updatedAt = time(),
        classId = classId,
    }), "WHISPER", sender)
end
