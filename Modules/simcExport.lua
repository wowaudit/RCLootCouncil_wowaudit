local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")

local RCwowaudit = addon:GetModule("RCwowaudit")
local wowauditSimcExport = RCwowaudit:NewModule("wowauditSimcExport", "AceComm-3.0", "AceSerializer-3.0", "AceEvent-3.0", "AceTimer-3.0")

-- Answers SimC export requests from the Wowaudit Companion admin, who collects them for the website.
-- The protocol is shared with the companion's simcExport module, so players only need one of
-- the two addons to share their export. When both are installed, this module answers.

local COMM_PREFIX = "WowauditSimc"
local PAYLOAD_VERSION = 1
local MAX_REPLY_DELAY = 10
local MAX_EXPORT_LENGTH = 60000

WowauditSimcResponder = "RCLootCouncil_wowaudit"

local replyTimers = {}
local deferredReplies = {}

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

local function sharingEnabled()
    return addon:Getdb().wowauditSimcSharing ~= false
end

-- Only the lines SimC simulates on count, so the export's timestamp header and
-- currency comments don't make every export look new. Must match the companion.
local function exportHash(text)
    local hash = 5381
    for line in text:gmatch("[^\n]+") do
        if line:sub(1, 1) ~= "#" then
            for i = 1, #line do
                hash = (hash * 33 + line:byte(i)) % 4294967296
            end
        end
    end
    return format("%08x", hash)
end

local function currentSpecId()
    local index = GetSpecialization and GetSpecialization()
    if not index then
        return nil
    end
    return GetSpecializationInfo(index)
end

local function generateExport()
    local simc = LibStub("AceAddon-3.0"):GetAddon("Simulationcraft", true)
    if not simc or type(simc.GetSimcProfile) ~= "function" then
        return nil
    end

    local ok, profile, printError = pcall(simc.GetSimcProfile, simc, false, false, false, false)
    if not ok or type(profile) ~= "string" or profile == "" or printError then
        return nil
    end

    -- Pipes are doubled for display in the addon's edit box.
    profile = profile:gsub("||", "|")
    if #profile > MAX_EXPORT_LENGTH then
        return nil
    end
    return profile
end

function wowauditSimcExport:OnRequestReceived(sender, known)
    if not sharingEnabled() or fullName(sender) == playerFullName() then
        return
    end

    local myName = playerFullName()
    local knownForMe = type(known) == "table" and myName and known[myName] or nil
    self:ScheduleReply(sender, knownForMe)
end

-- Spread replies so a raid answering one request doesn't all whisper at once.
function wowauditSimcExport:ScheduleReply(sender, knownForMe)
    if replyTimers[sender] then
        self:CancelTimer(replyTimers[sender])
    end
    replyTimers[sender] = self:ScheduleTimer(function()
        replyTimers[sender] = nil
        wowauditSimcExport:SendExport(sender, knownForMe)
    end, math.random() * MAX_REPLY_DELAY)
end

function wowauditSimcExport:SendExport(sender, knownForMe)
    if InCombatLockdown() then
        deferredReplies[sender] = knownForMe or false
        return
    end

    local specId = currentSpecId()
    local text = generateExport()
    if not specId or not text then
        return
    end

    local hash = exportHash(text)
    if type(knownForMe) == "table" and knownForMe[specId] == hash then
        return
    end

    self:SendCommMessage(COMM_PREFIX, self:Serialize("SIMC", PAYLOAD_VERSION, specId, time(), hash, text), "WHISPER", sender, "BULK")
end

function wowauditSimcExport:OnCommReceived(prefix, message, _, sender)
    if prefix ~= COMM_PREFIX then
        return
    end

    local ok, command, known = self:Deserialize(message)
    if ok and command == "REQ" then
        self:OnRequestReceived(sender, known)
    end
end

function wowauditSimcExport:PLAYER_REGEN_ENABLED()
    local replies = deferredReplies
    deferredReplies = {}
    for sender, knownForMe in pairs(replies) do
        self:ScheduleReply(sender, knownForMe or nil)
    end
end

function wowauditSimcExport:OnInitialize()
    self:RegisterComm(COMM_PREFIX)
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
end
