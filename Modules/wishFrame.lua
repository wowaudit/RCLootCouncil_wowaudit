local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local ST = LibStub("ScrollingTable")

local RCwowaudit = addon:GetModule("RCwowaudit")
local wowauditWishFrame = RCwowaudit:NewModule("wowauditWishFrame", "AceComm-3.0", "AceConsole-3.0", "AceHook-3.0",
    "AceEvent-3.0", "AceTimer-3.0", "AceSerializer-3.0", "AceBucket-3.0")

local ROW_HEIGHT = 20

local DIFFICULTIES = {
    N = "Normal",
    H = "Heroic",
    M = "Mythic",
    R = "LFR"
}

local STATUSES = {
    b = "Best", -- BIS
    n = "Not best", -- not BIS
    o = "Outdated" -- outdated
}

function wowauditWishFrame:OnInitialize()
    if not addon.optionsFrame then -- RCLootCouncil hasn't been initialized.
        return self:ScheduleTimer("OnInitialize", 0.5)
    end

    addon:ModuleChatCmd(self, "Show", nil, "Show synchronised wishlist data from wowaudit", "wishes", "wowaudit",
        "wishlists")
end

function wowauditWishFrame:OnEnable()
    self.colNameToIndex = {}
    self.scrollCols = self:SetupColumns()
end

function wowauditWishFrame:SetupColumns()
    self.colNameToIndex.difficulty = 1
    self.colNameToIndex.class = 2
    self.colNameToIndex.name = 3
    self.colNameToIndex.item = 4
    self.colNameToIndex.spec = 5
    self.colNameToIndex.status = 6
    self.colNameToIndex.value = 7
    self.colNameToIndex.percent = 8
    self.colNameToIndex.note = 9
    return {{
        name = "Difficulty",
        width = 50
    }, {
        name = "",
        width = 20
    }, -- class icon
    {
        name = "Name",
        width = 120
    }, {
        name = "Item",
        width = 180
    }, {
        name = "",
        width = 20
    }, -- spec icon
    {
        name = "Status",
        width = 60
    }, {
        name = "Value",
        width = 50
    }, {
        name = "Percent",
        width = 50
    }, {
        name = "Note",
        width = 30
    }}
end

function wowauditWishFrame:Show()
    self.frame = self:GetFrame()

    local rows = {}
    for character, difficulties in pairs(wishlistData) do
        for difficulty, items in pairs(difficulties) do
            for _, item in ipairs(items) do
                local row = {}
                local _, link, _, _, _, _, _, _, _ = C_Item.GetItemInfo(item.id)

                if tonumber(item.percent) then
                    row[self.colNameToIndex.percent] = withColor(item.percent .. "%", item.status)
                end

                row[self.colNameToIndex.difficulty] = DIFFICULTIES[difficulty]
                row[self.colNameToIndex.class] = CreateAtlasMarkup(specToClassIcon[item.spec], 14, 14)
                row[self.colNameToIndex.name] = character
                row[self.colNameToIndex.item] = link
                row[self.colNameToIndex.spec] = specIcon(item.spec, 14)
                row[self.colNameToIndex.status] = withColor(STATUSES[item.status], item.status)
                row[self.colNameToIndex.value] = withColor(item.value, item.status)
                row[self.colNameToIndex.note] = item.comment
                tinsert(rows, row)
            end
        end
    end

    self.frame.st:SetData(rows, true)
    self.frame:Show()
end

function wowauditWishFrame:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function wowauditWishFrame:GetFrame()
    if self.frame then
        return self.frame
    end
    local f = addon.UI:NewNamed("RCFrame", UIParent, "RCwowauditWishFrame", "RCLootCouncil - wowaudit - Wishes", 250)

    local st = ST:CreateST(self.scrollCols, 12, ROW_HEIGHT, nil, f.content)
    st.frame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -35)
    f:SetWidth(st.frame:GetWidth() + 20)
    f.st = st

    local closeButton = addon:CreateButton("Close", f.content)
    closeButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    closeButton:SetScript("OnClick", function()
        self:Hide()
    end)
    f.closeButton = closeButton

    return f
end
