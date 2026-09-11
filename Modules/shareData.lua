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
local REQUEST_THROTTLE = 10
local REPLY_DEBOUNCE = 10
local ACK_WAIT = 4
local RECEIVE_WAIT = 45
local STALE_AFTER = 7 * 24 * 60 * 60

local wasInGroup = false
local lastRequestAt = 0
local pushedTimestamp
local suppressPush = false
local pendingAfterSend = false
local sendFullData
local inbound = {
    awaitingAcks = false,
    willReceive = false,
    gotAck = false,
    result = nil
}
local broadcast = {
    inProgress = false,
    sent = 0,
    total = 0,
    lastCompletedAt = nil,
    lastDuration = nil
}

local function persistBroadcast()
    local db = addon:Getdb()
    db.wowauditLastShareAt = broadcast.lastCompletedAt
    db.wowauditLastShareDuration = broadcast.lastDuration
end

local function notifyShareUI()
    local wishes = RCwowaudit:GetModule("wowauditWishFrame", true)
    if wishes and wishes.UpdateShareStatus then
        wishes:UpdateShareStatus()
    end
end

local function onSendProgress(_, sent, total)
    broadcast.sent = sent or 0
    broadcast.total = total or 0
    broadcast.inProgress = broadcast.sent < broadcast.total
    if not broadcast.inProgress then
        broadcast.lastCompletedAt = time()
        if broadcast.startedAt then
            broadcast.lastDuration = GetTime() - broadcast.startedAt
        end
        broadcast.startedAt = nil
        persistBroadcast()
        notifyShareUI()
        if pendingAfterSend then
            pendingAfterSend = false
            sendFullData()
        end
        return
    end
    notifyShareUI()
end

function wowauditShareData:GetBroadcastStatus()
    return broadcast
end

function wowauditShareData:ShareStatusView()
    if not wowauditIsSource then
        if inbound.awaitingAcks and not inbound.willReceive then
            return {
                inProgress = true,
                text = "Waiting for a source…",
                sent = 0,
                total = 1
            }
        end
        if inbound.willReceive then
            return {
                inProgress = true,
                text = "Receiving wishlist data…",
                sent = 1,
                total = 1
            }
        end
        if inbound.result == "current" then
            return {
                inProgress = false,
                text = "Already up to date",
                sent = 0,
                total = 1
            }
        end
        if inbound.result == "nobody" then
            return {
                inProgress = false,
                text = "No one in the group can share data",
                sent = 0,
                total = 1
            }
        end
        if inbound.result == "updated" then
            return {
                inProgress = false,
                text = "Updated " .. date("%H:%M"),
                sent = 0,
                total = 1
            }
        end
        if inbound.result == "missing" then
            return {
                inProgress = false,
                text = "Share didn't arrive. Try again.",
                sent = 0,
                total = 1
            }
        end
        return {
            inProgress = false,
            text = "Not requested this session",
            sent = 0,
            total = 1
        }
    end
    if broadcast.inProgress then
        local total = broadcast.total or 0
        local sent = broadcast.sent or 0
        local text = "Sharing wishlists with group…"
        if total > 0 then
            text = format("Sharing wishlists with group… %d%%  %.1f / %.1f KB", math.floor(sent / total * 100), sent / 1024,
                total / 1024)
        end
        return {
            inProgress = true,
            text = text,
            sent = sent,
            total = math.max(total, 1)
        }
    end
    if self.replyTimer then
        return {
            inProgress = false,
            text = "Share queued, waiting for more people…",
            sent = 0,
            total = 1
        }
    end
    if broadcast.lastCompletedAt then
        local took = broadcast.lastDuration and format(" (took %ds)", math.floor(broadcast.lastDuration + 0.5)) or ""
        return {
            inProgress = false,
            text = "Last shared " .. date("%H:%M", broadcast.lastCompletedAt) .. took,
            sent = 0,
            total = 1
        }
    end
    return {
        inProgress = false,
        text = "Not shared this session",
        sent = 0,
        total = 1
    }
end

local function teamKey(id)
    return tostring(id or 0)
end

local function isSelf(sender)
    return sender and addon:UnitIsUnit(sender, "player")
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

-- One snapshot. A later group with another team sends a fresh dump.
local function cachedPayload(db)
    local cache = db.wowauditSharedDataset
    if type(cache) ~= "table" then
        return nil
    end
    if cache.timestamp then
        return cache
    end
    -- Older builds keyed this by team.
    local entry = db.wowauditActiveTeam and cache[db.wowauditActiveTeam]
    if type(entry) == "table" and entry.timestamp then
        return entry
    end
    local best
    for _, data in pairs(cache) do
        if type(data) == "table" and data.timestamp and (not best or data.timestamp > best.timestamp) then
            best = data
        end
    end
    return best
end

local function persistDataset()
    if not wowauditTimestamp then
        return
    end
    addon:Getdb().wowauditSharedDataset = currentPayload()
end

local function applyDataset(payload, fromCache)
    if type(payload) ~= "table" or not payload.timestamp then
        return false
    end

    local payloadTeam = payload.teamID or 0
    local differentTeam = teamKey(payloadTeam) ~= teamKey(teamID)
    local newer = not wowauditTimestamp or payload.timestamp > wowauditTimestamp

    if wowauditIsSource and differentTeam then
        return false
    end
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
    end

    RCwowaudit:RefreshEvaluationFrame()
    local wishes = RCwowaudit:GetModule("wowauditWishFrame", true)
    if wishes and wishes.frame and wishes.frame:IsShown() then
        wishes:Show()
    end
    return true
end

local function hydrateFromCache()
    local entry = cachedPayload(addon:Getdb())
    if not entry then
        return
    end
    if wowauditIsSource and teamKey(entry.teamID) ~= teamKey(teamID) then
        return
    end
    applyDataset(entry, true)
end

-- RCLootCouncil's Comms sender already serialises, compresses (LibDeflate) and
-- chunks. The full dataset is one table; ChatThrottleLib rate-limits the rest.
sendFullData = function()
    if not wowauditIsSource or not wowauditTimestamp then
        return
    end
    if broadcast.inProgress then
        pendingAfterSend = true
        return
    end

    pendingAfterSend = false
    pushedTimestamp = wowauditTimestamp
    broadcast.inProgress = true
    broadcast.sent = 0
    broadcast.total = 0
    broadcast.startedAt = GetTime()
    notifyShareUI()

    Comms:Send({
        prefix = RCwowaudit.PREFIXES.MAIN,
        target = "group",
        command = "full_data",
        data = {currentPayload()},
        callback = onSendProgress
    })
end

function wowauditShareData:BroadcastNow()
    if not wowauditIsSource or not wowauditTimestamp then
        return
    end
    if not IsInGroup() then
        addon:Print("Join a group to broadcast wishlist data.")
        return
    end
    if broadcast.inProgress then
        return
    end

    suppressPush = false
    self:CancelPendingSend()
    sendFullData()
end

function wowauditShareData:CancelPendingSend()
    if self.replyTimer then
        self:CancelTimer(self.replyTimer)
        self.replyTimer = nil
        notifyShareUI()
    end
end

function wowauditShareData:AnnounceVersion()
    if not wowauditIsSource or not wowauditTimestamp or not IsInGroup() then
        return
    end
    RCwowaudit:Send("group", "data_version", wowauditTimestamp, teamID or 0)
end

function wowauditShareData:ScheduleReply()
    pendingAfterSend = false
    if self.replyTimer then
        self:CancelTimer(self.replyTimer)
    end

    self.replyTimer = self:ScheduleTimer(function()
        wowauditShareData.replyTimer = nil
        if suppressPush then
            notifyShareUI()
            return
        end
        sendFullData()
    end, REPLY_DEBOUNCE)
    notifyShareUI()
end

function wowauditShareData:RequestDataset(force)
    if not IsInGroup() then
        return
    end
    if not force and GetTime() - lastRequestAt < REQUEST_THROTTLE then
        return
    end

    lastRequestAt = GetTime()
    RCwowaudit:Send("group", "request_data", wowauditTimestamp, teamID or 0, wowauditIsSource)
end

function wowauditShareData:CancelInboundWait()
    if self.ackTimer then
        self:CancelTimer(self.ackTimer)
        self.ackTimer = nil
    end
    if self.receiveTimer then
        self:CancelTimer(self.receiveTimer)
        self.receiveTimer = nil
    end
end

function wowauditShareData:FinishInbound(result)
    inbound.awaitingAcks = false
    inbound.willReceive = false
    inbound.result = result
    self:CancelInboundWait()
    notifyShareUI()
end

function wowauditShareData:RequestNow()
    if wowauditIsSource then
        return
    end
    if not IsInGroup() then
        addon:Print("Join a group to request wishlist data.")
        return
    end
    if inbound.awaitingAcks or inbound.willReceive then
        return
    end

    inbound.awaitingAcks = true
    inbound.willReceive = false
    inbound.gotAck = false
    inbound.result = nil
    self:CancelInboundWait()
    notifyShareUI()
    self:RequestDataset(true)

    self.ackTimer = self:ScheduleTimer(function()
        wowauditShareData.ackTimer = nil
        inbound.awaitingAcks = false
        if inbound.willReceive then
            notifyShareUI()
            return
        end
        wowauditShareData:FinishInbound(inbound.gotAck and "current" or "nobody")
    end, ACK_WAIT)
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
        if wowauditIsSource then
            wowauditShareData:AnnounceVersion()
        else
            wowauditShareData:RequestDataset()
        end
    end, GROUP_SYNC_DELAY)
end

function wowauditShareData:IsStaleVs(theirTimestamp, theirTeam)
    if not theirTimestamp then
        return false
    end
    if teamKey(theirTeam) ~= teamKey(teamID) then
        return not wowauditIsSource
    end
    return not wowauditTimestamp or theirTimestamp > wowauditTimestamp
end

function wowauditShareData:ShouldReply(theirTimestamp, theirTeam, theyAreSource)
    if not wowauditIsSource or not wowauditTimestamp then
        return false
    end
    if teamKey(theirTeam) ~= teamKey(teamID) then
        return not theyAreSource
    end
    return wowauditTimestamp > (theirTimestamp or 0)
end

function wowauditShareData:OnDataVersionReceived(sender, theirTimestamp, theirTeam)
    if isSelf(sender) then
        return
    end
    if not self:IsStaleVs(theirTimestamp, theirTeam) then
        return
    end
    self:RequestDataset()
end

function wowauditShareData:OnRequestDataReceived(sender, theirTimestamp, theirTeam, theyAreSource)
    if isSelf(sender) then
        return
    end
    if not wowauditIsSource or not wowauditTimestamp then
        return
    end

    local willSend = self:ShouldReply(theirTimestamp, theirTeam, theyAreSource)
    RCwowaudit:Send("group", "data_ack", sender, willSend and "pending" or "current")
    if willSend then
        self:ScheduleReply()
    end
end

function wowauditShareData:OnDataAckReceived(sender, forWhom, status)
    if isSelf(sender) or not forWhom then
        return
    end
    if not addon:UnitIsUnit(forWhom, "player") then
        return
    end
    if not inbound.awaitingAcks and not inbound.willReceive then
        return
    end

    inbound.gotAck = true
    if status ~= "pending" then
        return
    end

    inbound.willReceive = true
    if not self.receiveTimer then
        self.receiveTimer = self:ScheduleTimer(function()
            wowauditShareData.receiveTimer = nil
            if inbound.willReceive then
                wowauditShareData:FinishInbound("missing")
            end
        end, RECEIVE_WAIT)
    end
    notifyShareUI()
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

    if inbound.awaitingAcks or inbound.willReceive then
        self:FinishInbound(adopted and "updated" or "current")
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
        local db = addon:Getdb()
        broadcast.lastCompletedAt = db.wowauditLastShareAt
        broadcast.lastDuration = db.wowauditLastShareDuration
        if wowauditIsSource and wowauditTimestamp then
            local cached = cachedPayload(db)
            if not cached or teamKey(cached.teamID) ~= teamKey(teamID) or (cached.timestamp or 0) < wowauditTimestamp then
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
        data_version = function(data, sender)
            self:OnDataVersionReceived(sender, unpack(data))
        end,
        request_data = function(data, sender)
            self:OnRequestDataReceived(sender, unpack(data))
        end,
        data_ack = function(data, sender)
            self:OnDataAckReceived(sender, unpack(data))
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
