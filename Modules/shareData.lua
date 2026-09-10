local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local Comms = addon.Require "Services.Comms"
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

-- Captured once at load from db.lua, before any adoption. Eligible to share, not
-- permanently authoritative: sources still adopt strictly-newer same-team data.
wowauditIsSource = wowauditTimestamp ~= nil

local GROUP_SYNC_DELAY = 2
local PUSH_LISTEN_DELAY = 3
local REQUEST_THROTTLE = 10
local REPLY_JITTER_MIN = 0.3
local REPLY_JITTER_MAX = 1.8
local STALE_AFTER = 7 * 24 * 60 * 60

local wasInGroup = false
local lastRequestAt = 0
local pushedTimestamp
local suppressPush = false

local function teamKey(id)
    return tostring(id or 0)
end

local function isSelf(sender)
    return sender and addon:UnitIsUnit(sender, "player")
end

local function datasetStore()
    local db = addon:Getdb()
    db.wowauditSharedDataset = db.wowauditSharedDataset or {}
    return db
end

local function currentPayload()
    return {
        wishlistData = wishlistData or {},
        bonusRollTargets = bonusRollTargets or {},
        trinketPriorities = trinketPriorities or {},
        difficulties = difficulties or {},
        timestamp = wowauditTimestamp,
        teamID = teamID or 0
    }
end

local function persistDataset()
    if not wowauditTimestamp then
        return
    end

    local db = datasetStore()
    local key = teamKey(teamID)
    db.wowauditSharedDataset[key] = currentPayload()
    db.wowauditActiveTeam = key
end

local function applyDataset(payload, fromCache)
    if type(payload) ~= "table" or not payload.timestamp then
        return false
    end

    local payloadTeam = payload.teamID or 0
    local currentTeam = teamID or 0
    local differentTeam = teamKey(payloadTeam) ~= teamKey(currentTeam)
    local newer = not wowauditTimestamp or payload.timestamp > wowauditTimestamp

    if not differentTeam and not newer then
        return false
    end

    wishlistData = payload.wishlistData or {}
    bonusRollTargets = payload.bonusRollTargets or {}
    trinketPriorities = payload.trinketPriorities or {}
    difficulties = payload.difficulties or difficulties or {}
    wowauditTimestamp = payload.timestamp
    teamID = payloadTeam

    wowauditRebuildPresentDifficulties()
    wowauditInvalidateSlotWishes()

    if not fromCache then
        persistDataset()
    else
        datasetStore().wowauditActiveTeam = teamKey(teamID)
    end

    RCwowaudit:RefreshEvaluationFrame()
    return true
end

local function hydrateFromCache()
    local db = datasetStore()
    local cache = db.wowauditSharedDataset
    if type(cache) ~= "table" then
        return
    end

    -- Sources only overlay same-team cache (newer leftover-stale db.lua).
    -- Switching teams is a raid-time adoption, not an init-time one.
    if wowauditIsSource then
        local entry = cache[teamKey(teamID)]
        if entry then
            applyDataset(entry, true)
        end
        return
    end

    local entry = db.wowauditActiveTeam and cache[db.wowauditActiveTeam]
    if not entry then
        local bestTimestamp
        for _, data in pairs(cache) do
            if data and data.timestamp and (not bestTimestamp or data.timestamp > bestTimestamp) then
                bestTimestamp = data.timestamp
                entry = data
            end
        end
    end

    if entry then
        applyDataset(entry, true)
    end
end

-- RCLootCouncil's Comms sender already serialises, compresses (LibDeflate) and
-- chunks. The full dataset is one table; ChatThrottleLib rate-limits the rest.
local function sendFullData()
    if not wowauditIsSource or not wowauditTimestamp then
        return
    end

    pushedTimestamp = wowauditTimestamp
    RCwowaudit:Send("group", "full_data", currentPayload())
end

function wowauditShareData:CancelPendingSend()
    if self.pushTimer then
        self:CancelTimer(self.pushTimer)
        self.pushTimer = nil
    end
    if self.replyTimer then
        self:CancelTimer(self.replyTimer)
        self.replyTimer = nil
    end
end

function wowauditShareData:SchedulePush()
    if self.pushTimer then
        return
    end

    self.pushTimer = self:ScheduleTimer(function()
        wowauditShareData.pushTimer = nil
        if suppressPush then
            return
        end
        if not wowauditIsSource or not wowauditTimestamp then
            return
        end
        sendFullData()
    end, PUSH_LISTEN_DELAY)
end

function wowauditShareData:ScheduleReply()
    if self.replyTimer or self.pushTimer then
        return
    end

    local delay = REPLY_JITTER_MIN + math.random() * (REPLY_JITTER_MAX - REPLY_JITTER_MIN)
    self.replyTimer = self:ScheduleTimer(function()
        wowauditShareData.replyTimer = nil
        sendFullData()
    end, delay)
end

function wowauditShareData:RequestDataset()
    if not IsInGroup() then
        return
    end
    if GetTime() - lastRequestAt < REQUEST_THROTTLE then
        return
    end

    lastRequestAt = GetTime()
    RCwowaudit:Send("group", "request_data", wowauditTimestamp, teamID or 0)
end

function wowauditShareData:ScheduleGroupSync()
    if self.groupSyncTimer then
        return
    end

    self.groupSyncTimer = self:ScheduleTimer(function()
        wowauditShareData.groupSyncTimer = nil
        if not IsInGroup() then
            return
        end

        suppressPush = false
        wowauditShareData:RequestDataset()
        if wowauditIsSource then
            wowauditShareData:SchedulePush()
        end
    end, GROUP_SYNC_DELAY)
end

function wowauditShareData:ShouldReply(theirTimestamp, theirTeam)
    if not wowauditIsSource or not wowauditTimestamp then
        return false
    end
    if teamKey(theirTeam) ~= teamKey(teamID) then
        return true
    end
    return wowauditTimestamp > (theirTimestamp or 0)
end

function wowauditShareData:OnRequestDataReceived(sender, theirTimestamp, theirTeam)
    if isSelf(sender) then
        return
    end
    if not self:ShouldReply(theirTimestamp, theirTeam) then
        return
    end
    self:ScheduleReply()
end

function wowauditShareData:OnFullDataReceived(sender, payload)
    if type(payload) ~= "table" then
        return
    end

    if isSelf(sender) then
        pushedTimestamp = payload.timestamp
        self:CancelPendingSend()
        return
    end

    local adopted = applyDataset(payload, false)
    local sameTeam = teamKey(payload.teamID) == teamKey(teamID)
    local equalOrNewer = payload.timestamp and wowauditTimestamp and payload.timestamp >= wowauditTimestamp

    -- First-wins: another source already put this (or newer) data on the wire.
    if adopted or (sameTeam and equalOrNewer) then
        suppressPush = true
        self:CancelPendingSend()
    end
end

function wowauditShareData:PLAYER_ENTERING_WORLD(_, isLogin, isReload)
    if isLogin or isReload then
        self:ScheduleGroupSync()
    end
end

function wowauditShareData:GROUP_ROSTER_UPDATE()
    local grouped = IsInGroup()
    if grouped and not wasInGroup then
        self:ScheduleGroupSync()
    end
    wasInGroup = grouped
end

function wowauditShareData:OnInitialize()
    RCwowaudit.Send = Comms:GetSender(RCwowaudit.PREFIXES.MAIN)

    -- Source flag is already captured at file load. Hydrate cached datasets next
    -- so a consumer (or a source with leftover stale db.lua) has data before login
    -- grouping fires. Own db.lua is only written to the cache if it is fresher.
    local ok = pcall(function()
        hydrateFromCache()
        if wowauditIsSource and wowauditTimestamp then
            local cached = datasetStore().wowauditSharedDataset[teamKey(teamID)]
            if not cached or (cached.timestamp or 0) < wowauditTimestamp then
                persistDataset()
            end
        end
    end)
    if not ok then
        self:ScheduleTimer(function()
            hydrateFromCache()
        end, 1)
    end

    wasInGroup = IsInGroup()
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")

    Comms:BulkSubscribe(RCwowaudit.PREFIXES.MAIN, {
        request_data = function(data, sender)
            self:OnRequestDataReceived(sender, unpack(data))
        end,
        full_data = function(data, sender)
            self:OnFullDataReceived(sender, unpack(data))
        end,
        profile = function(data, sender)
            self:OnProfileReceived(sender, unpack(data))
        end,
        request_profile = function(data, sender)
            RCwowaudit:GetModule("wowauditGearProfile"):SendOnRequest()
        end
    })
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

wowauditWishlistAgeWarning = function()
    if not wowauditTimestamp then
        return nil
    end
    local days = math.floor((time() - wowauditTimestamp) / (24 * 60 * 60))
    if (time() - wowauditTimestamp) >= STALE_AFTER then
        return days
    end
    return nil
end
