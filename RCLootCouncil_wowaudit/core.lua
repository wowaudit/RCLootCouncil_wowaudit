local LibDialog = LibStub("LibDialog-1.1")

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCwowaudit = addon:NewModule("RCwowaudit", "AceComm-3.0", "AceConsole-3.0", "AceHook-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceSerializer-3.0", "AceBucket-3.0")

function RCwowaudit:OnInitialize()
  self.minRCVersion = "3.7.0"

  if addon:VersionCompare(addon.version, self.minRCVersion) then
    LibDialog:Spawn("RCWOWAUDIT_OUTDATED_MESSAGE")
  end
end
