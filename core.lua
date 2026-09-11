local LibDialog = LibStub("LibDialog-1.1")

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCwowaudit = addon:NewModule("RCwowaudit", "AceComm-3.0", "AceConsole-3.0", "AceHook-3.0", "AceEvent-3.0",
    "AceTimer-3.0", "AceSerializer-3.0", "AceBucket-3.0")

wowauditValueDisplay = 'VALUE'
wowauditDifficultyMatch = 'LENIENT'
wowauditSharingSetting = 'NEWEST'

-- Response filter for the evaluation window. Keyed exactly like RCLootCouncil's own
-- voting frame filters: response indices plus the PASS, AUTOPASS and STATUS groups.
local function evaluationFilters()
    local db = addon:Getdb()
    db.wowauditEvaluationFilters = db.wowauditEvaluationFilters or {}
    return db.wowauditEvaluationFilters
end

local function responseFilterValues()
    local values = {}

    -- String keys only: Blizzard's settings UI sorts these with `<`, which errors
    -- if response indices (numbers) are mixed with PASS/AUTOPASS/STATUS.
    for index = 1, addon:GetNumButtons() do
        values[tostring(index)] = addon:GetResponse("default", index).text or ("Response " .. index)
    end

    values.PASS = addon:GetResponse("default", "PASS").text or "Pass"
    values.AUTOPASS = addon:GetResponse("default", "AUTOPASS").text or "Autopass"
    values.STATUS = "Status texts"

    return values
end

local function coerceFilterKey(key)
    return tonumber(key) or key
end

local optionsTable = {
    type = "group",
    name = "RCLootCouncil",
    args = {
        wowauditSettings = {
            type = "group",
            inline = true,
            name = "wowaudit",
            width = "full",

            args = {
                WishSettings = {
                    type = "group",
                    inline = true,
                    name = "Wish settings",
                    width = 0.5,
                    args = {
                        SetDifficultyMatch = {
                            type = "select",
                            order = 2,
                            name = "Difficulty leniency",
                            width = "double",
                            desc = "Choose what data to display when there are no wishes for the loot's difficulty (changes only work if you have the desktop client installed).",
                            values = {
                                STRICT = "Don't display wishes from other difficulties",
                                LENIENT = "Display wishes from the next highest difficulty with wishes",
                                ANY = "Search for wishes in any higher difficulty, per player"
                            },
                            get = function(info)
                                return wowauditDifficultyMatch
                            end,
                            set = function(info, value)
                                db = addon:Getdb()
                                db.wowauditDifficultyMatch = value
                                wowauditDifficultyMatch = value
                                -- Which difficulty a character's wishes come from
                                -- feeds the cached slot grouping.
                                wowauditInvalidateSlotWishes()
                                RCwowaudit:RefreshEvaluationFrame()
                            end
                        },
                        SetSharingSetting = {
                            type = "select",
                            order = 2,
                            name = "Shared data",
                            width = "double",
                            desc = "Choose what data to display when there is both shared data and data from your own desktop client.",
                            values = {
                                NEWEST = "Display the most recently synced data, regardless of source",
                                SELF = "Prefer displaying data from own synced data, even if older"
                            },
                            get = function(info)
                                return wowauditSharingSetting
                            end,
                            set = function(info, value)
                                db = addon:Getdb()
                                db.wowauditSharingSetting = value
                                wowauditSharingSetting = value
                            end
                        }
                    }
                },
                DisplaySettings = {
                    type = "group",
                    inline = true,
                    name = "Display settings",
                    args = {
                        SetValueDisplay = {
                            type = "select",
                            order = 1,
                            name = "Display values as",
                            desc = "Choose how to display the wish values in the loot and voting frames.",
                            values = {
                                VALUE = "Value",
                                PERCENTAGE = "Percentage"
                            },
                            get = function(info)
                                return wowauditValueDisplay
                            end,
                            set = function(info, value)
                                RCwowaudit:SetValueDisplay(value)
                            end
                        },
                        SetEvaluationSort = {
                            type = "select",
                            order = 2,
                            name = "Evaluation window sorting",
                            desc = "Choose how the rows in the evaluation window are ordered by default.",
                            values = {
                                response = "Response",
                                bis = "Best in slot",
                                value = "Wish value",
                                ilvl = "Item level",
                                name = "Name"
                            },
                            get = function(info)
                                return addon:Getdb().wowauditEvaluationSort or "response"
                            end,
                            set = function(info, value)
                                addon:Getdb().wowauditEvaluationSort = value
                                RCwowaudit:RefreshEvaluationFrame()
                            end
                        }
                    }
                },
                EvaluationSettings = {
                    type = "group",
                    inline = true,
                    name = "Evaluation window",
                    width = "full",
                    args = {
                        SetEvaluationResponses = {
                            type = "multiselect",
                            order = 1,
                            name = "Responses to display",
                            desc = "Choose which responses show up as rows in the evaluation window. The same setting is available in the window's own header.",
                            values = responseFilterValues,
                            get = function(info, key)
                                local filters = evaluationFilters()
                                key = coerceFilterKey(key)
                                if type(key) == "number" then
                                    return filters[key] ~= false
                                end
                                return filters[key] == true
                            end,
                            set = function(info, key, value)
                                evaluationFilters()[coerceFilterKey(key)] = value
                                RCwowaudit:RefreshEvaluationFrame()
                            end
                        }
                    }
                }
            }
        }
    }
}

function RCwowaudit:OnInitialize()
    if not addon.optionsFrame then -- RCLootCouncil hasn't been initialized.
        return self:ScheduleTimer("OnInitialize", 0.5)
    end

    self.minRCVersion = "3.7.0"

    if addon:VersionCompare(addon.version, self.minRCVersion) then
        LibDialog:Spawn("RCWOWAUDIT_OUTDATED_MESSAGE")
    end

    LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("RCLootCouncil_wowaudit", optionsTable)
    addon.optionsFrame.wowaudit = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("RCLootCouncil_wowaudit", "wowaudit",
        "RCLootCouncil", "wowauditSettings")

    db = addon:Getdb()
    wowauditValueDisplay = db.wowauditValueDisplay or "VALUE"
    wowauditDifficultyMatch = db.wowauditDifficultyMatch or "LENIENT"
    wowauditSharingSetting = db.wowauditSharingSetting or "NEWEST"

    -- Register all "/rc" subcommands from this single module so they share one help header.
    addon:ModuleChatCmd(self, "ShowWishes", nil, "Show synchronised wishlist data from wowaudit", "wishes", "wowaudit",
        "wishlists")
    addon:ModuleChatCmd(self, "ShowEvaluation", "evaluate", "Open the loot evaluation window for the current session",
        "evaluate", "evaluation")
    addon:ModuleChatCmd(self, "ShowBonusRolls", "bonusrolls", "Display available and earned bonus rolls for your raid group and guild (alt. 'coins')",
        "bonusrolls", "coins")
end

function RCwowaudit:ShowWishes()
    self:GetModule("wowauditWishFrame"):Show()
end

function RCwowaudit:ShowEvaluation()
    self:GetModule("wowauditEvaluationFrame"):Show()
end

-- Shared by the options panel and the toggle buttons in both frames, so the setting
-- survives a reload no matter where it was changed.
function RCwowaudit:SetValueDisplay(value)
    addon:Getdb().wowauditValueDisplay = value
    wowauditValueDisplay = value

    local loot = self:GetModule("wowauditLootFrame", true)
    if loot and loot.RefreshVisible then
        loot:RefreshVisible()
    end
end

function RCwowaudit:RefreshEvaluationFrame()
    local module = self:GetModule("wowauditEvaluationFrame", true)
    if module then
        module:Refresh()
    end

    local loot = self:GetModule("wowauditLootFrame", true)
    if loot and loot.RefreshVisible then
        loot:RefreshVisible()
    end
end

-- The bonus roll window lives in the Wowaudit Companion addon.
function RCwowaudit:ShowBonusRolls()
    local companion = LibStub("AceAddon-3.0"):GetAddon("WowauditBonusRoll", true)
    if companion and companion.ShowWindow then
        companion:ShowWindow()
    else
        addon:Print("The Wowaudit Companion addon is required to view the bonus roll window.")
    end
end
