-- Upgrade track data, needed to turn any item link into a track and upgrade step
-- ("Hero 3/6"). Ported from BONUS_IDS_BY_SEASON in core/lib/utils/bonus_ids.rb and
-- the crest metadata in web/config/static_data/seasons/live.json. Both need a new
-- entry here when a season starts.

local function range(from, to)
    local ids = {}
    for id = from, to do
        tinsert(ids, id)
    end
    return ids
end

-- Current season only, on purpose. Gear from an earlier season carries that season's
-- upgrade bonus IDs, so including older seasons made previous-expansion gear count
-- towards this season's track totals. An item that isn't on a current track should
-- report no track at all.
local currentSeasonTracks = { -- 18: Midnight S2
    Myth = range(12849, 12854),
    Hero = range(12841, 12846),
    Champion = range(12833, 12838),
    Veteran = range(12825, 12830),
    Adventurer = range(12265, 12272)
}

-- Highest track first. Used for display order and to decide which track "wins"
-- when summarising a full set of equipped gear.
wowauditTrackOrder = {"Myth", "Hero", "Champion", "Veteran", "Adventurer", "Explorer"}

-- Item qualities, so track colours match the website (colorByTrack in
-- web/app/frontend/types/custom/UpgradeTrack.ts maps to the same qualities).
wowauditTrackQuality = {
    Myth = Enum.ItemQuality.Legendary,
    Hero = Enum.ItemQuality.Epic,
    Champion = Enum.ItemQuality.Rare,
    Veteran = Enum.ItemQuality.Uncommon,
    Adventurer = Enum.ItemQuality.Uncommon,
    Explorer = Enum.ItemQuality.Common
}

-- [bonusID] = { track = "Hero", step = 3, total = 6 }
wowauditTrackByBonusId = {}
for track, ids in pairs(currentSeasonTracks) do
    for step, bonusId in ipairs(ids) do
        wowauditTrackByBonusId[bonusId] = {
            track = track,
            step = step,
            total = #ids
        }
    end
end

-- Crest currencies, per upgrade track.
wowauditCrestCurrencies = {
    Myth = 3446,
    Hero = 3445,
    Champion = 3444,
    Veteran = 3443
}

-- Catalyst charges (Venomblight Manaflux).
wowauditCatalystCurrencyID = 3465

-- Bonus roll coins, the same currency the /rc coins window reports on.
wowauditBonusRollCurrencyID = 3418
