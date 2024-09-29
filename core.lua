local LibDialog = LibStub("LibDialog-1.1")

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCwowaudit = addon:NewModule("RCwowaudit", "AceComm-3.0", "AceConsole-3.0", "AceHook-3.0", "AceEvent-3.0",
    "AceTimer-3.0", "AceSerializer-3.0", "AceBucket-3.0")

wowauditValueDisplay = 'VALUE'
wowauditDifficultyMatch = 'LENIENT'
wowauditSharingSetting = 'NEWEST'

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
                                db = addon:Getdb()
                                db.wowauditValueDisplay = value
                                wowauditValueDisplay = value
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
end
