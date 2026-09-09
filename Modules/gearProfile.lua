local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")

local RCwowaudit = addon:GetModule("RCwowaudit")
local wowauditGearProfile = RCwowaudit:NewModule("wowauditGearProfile", "AceEvent-3.0", "AceHook-3.0", "AceTimer-3.0")

local SEND_THROTTLE = 5

-- Crests, catalyst charges and equipped upgrade tracks are not part of anything
-- RCLootCouncil transmits, so every client with this module builds a compact
-- profile of its own and shares it alongside the data RCLootCouncil already sends.
local profile = nil
local lastSentSignature = nil
local lastSentAt = 0
local pendingSend
local pendingReplay

local function playerName()
    return addon.player and addon.player:GetName() or addon.playerName
end

function wowauditGearProfile:OnInitialize()
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "Invalidate")
    self:RegisterEvent("CURRENCY_DISPLAY_UPDATE", "Invalidate")

    -- Ride RCLootCouncil's own transmit points instead of running a separate
    -- handshake: SendLootAck fires when the loot table arrives, SendResponse when
    -- the candidate actually votes.
    self:SecureHook(addon, "SendLootAck", "OnLootAckSent")
    self:SecureHook(addon, "SendResponse", "OnResponseSent")
end

function wowauditGearProfile:Invalidate()
    profile = nil
end

function wowauditGearProfile:Build()
    if profile then
        return profile
    end

    local crests = {}
    for track in pairs(wowauditCrestCurrencies) do
        local info = wowauditCrestInfo(track)
        if info then
            crests[track] = {
                q = info.left,
                e = info.earnable
            }
        end
    end

    local equipped = {}
    for track, summary in pairs(wowauditScanEquipped()) do
        equipped[track] = {
            c = summary.count,
            d = summary.stepsDone,
            s = summary.stepsLeft,
            i = summary.items
        }
    end

    local catalyst = wowauditCatalystCharges()
    local bonusRoll = wowauditBonusRollInfo()

    profile = {
        il = math.floor(tonumber((select(2, GetAverageItemLevel()))) or 0),
        cat = catalyst and catalyst.amount or nil,
        br = bonusRoll and {
            q = bonusRoll.left,
            e = bonusRoll.earned,
            m = bonusRoll.cap
        } or nil,
        cr = crests,
        eq = equipped
    }

    -- Our own broadcasts aren't guaranteed to come back to us, so the local row
    -- is populated directly.
    local name = playerName()
    if name then
        sharedWowauditProfiles[name] = profile
    end

    return profile
end

local function signatureFor(data)
    local parts = {data.il or 0, data.cat or -1, data.br and data.br.q or -1}

    for _, track in ipairs(wowauditTrackOrder) do
        local crest = data.cr[track]
        local equipped = data.eq[track]
        tinsert(parts, crest and (crest.q .. "/" .. (crest.e or -1)) or "-")
        tinsert(parts, equipped and (equipped.c .. "/" .. equipped.d .. "/" .. equipped.s) or "-")
        if equipped and equipped.i then
            for _, item in ipairs(equipped.i) do
                tinsert(parts, (item[1] or 0) .. "/" .. (item[2] or 0) .. "/" .. (item[3] or 0))
            end
        end
    end

    return table.concat(parts, ":")
end

function wowauditGearProfile:Send(force, replay)
    local data = self:Build()
    if not IsInGroup() then
        return
    end

    local signature = signatureFor(data)

    -- Loot ack and votes skip an unchanged snapshot. A replay is someone who
    -- missed that broadcast asking us to put it on the wire again.
    if not replay and signature == lastSentSignature then
        return
    end

    if not force and not replay and GetTime() - lastSentAt < SEND_THROTTLE then
        return
    end

    lastSentSignature = signature
    lastSentAt = GetTime()
    RCwowaudit:Send("group", "profile", data)
end

function wowauditGearProfile:ScheduleSend(replay)
    pendingReplay = pendingReplay or replay
    if pendingSend then
        return
    end

    -- Spread replies so a full raid answering one request (or acking the same
    -- loot table) doesn't land in a single frame.
    pendingSend = self:ScheduleTimer(function()
        pendingSend = nil
        local replayNow = pendingReplay
        pendingReplay = nil
        wowauditGearProfile:Send(false, replayNow)
    end, 0.5 + math.random() * 2)
end

function wowauditGearProfile:OnLootAckSent()
    self:Build()
    self:ScheduleSend()
end

-- Crests and gear do change mid-raid, so a vote re-sends only when something the
-- window shows actually moved.
function wowauditGearProfile:OnResponseSent()
    local data = self:Build()
    if signatureFor(data) ~= lastSentSignature then
        -- A vote is a quiet moment to push a real change without waiting out
        -- the 5s throttle from the loot-ack send.
        self:Send(true)
    end
end

function wowauditGearProfile:SendOnRequest()
    self:ScheduleSend(true)
end

wowauditProfileForCharacter = function(name)
    if not name then
        return nil
    end
    if sharedWowauditProfiles[name] then
        return sharedWowauditProfiles[name]
    end
    -- Own profile is stored under whatever RCLootCouncil calls us; the loot
    -- table key is not always that string, especially in /rc test.
    if addon:UnitIsUnit(name, "player") then
        local me = playerName()
        return (me and sharedWowauditProfiles[me]) or profile
    end
    return nil
end
