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
        width = 150
    }, {
        name = "Item",
        width = 180,
        comparesort = self.StringSort,
        DoCellUpdate = self.SetItemLink
    }, {
        name = "",
        width = 20
    }, -- spec icon
    {
        name = "Status",
        width = 60
    }, {
        name = "Value",
        width = 50,
        comparesort = self.NumberSort
    }, {
        name = "Percent",
        width = 50,
        comparesort = self.NumberSort
        -- }, {
        --     name = "Note",
        --     width = 30,
        --     DoCellUpdate = self.SetWishNote
    }}
end

function wowauditWishFrame:Show()
    self.frame = self:GetFrame()

    local rows = {}
    local charactersFound = 0
    local wishesFound = 0
    for character, difficulties in pairs(wishlistData) do
        charactersFound = charactersFound + 1
        for difficulty, items in pairs(difficulties) do
            for _, item in ipairs(items) do
                item = transformWish(item)
                local row = {}
                local name, link, _, _, _, _, _, _, _ = C_Item.GetItemInfo(item.id)

                if tonumber(item.percent) then
                    row[self.colNameToIndex.percent] = {
                        value = withColor(item.percent .. "%", item.status),
                        sortValue = item.percent
                    }
                else
                    row[self.colNameToIndex.percent] = {
                        value = "",
                        sortValue = 0
                    }
                end

                row[self.colNameToIndex.difficulty] = DIFFICULTIES[difficulty]
                row[self.colNameToIndex.class] = CreateAtlasMarkup(specToClassIcon[item.spec], 16, 16)
                row[self.colNameToIndex.name] = character
                row[self.colNameToIndex.item] = {
                    value = link,
                    sortValue = name
                }
                row[self.colNameToIndex.spec] = specIcon(item.spec, 16)
                row[self.colNameToIndex.status] = withColor(STATUSES[item.status], item.status)
                row[self.colNameToIndex.value] = {
                    value = withColor(item.value, item.status),
                    sortValue = item.value
                }
                -- row[self.colNameToIndex.note] = {
                --     value = item.comment or ""
                -- }
                tinsert(rows, row)
                wishesFound = wishesFound + 1
            end
        end
    end

    if wowauditTimestamp == nil then
        self.frame.infoText:SetText(withColor(
            "No wishlist data found. Ensure that the desktop client is installed and running.", "o"))
    else
        self.frame.infoText:SetText(wishesFound .. " wishes found, from " .. charactersFound ..
                                        " characters. Last updated " .. date("%B %d, %H:%M", wowauditTimestamp), "b")
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

    local st = ST:CreateST(self.scrollCols, 25, ROW_HEIGHT, nil, f.content)
    st.frame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -35)
    f:SetWidth(st.frame:GetWidth() + 20)
    f:SetHeight(585)
    f.st = st

    local closeButton = addon:CreateButton("Close", f.content)
    closeButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    closeButton:SetScript("OnClick", function()
        self:Hide()
    end)
    f.closeButton = closeButton

    local infoText = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 15, 15)
    infoText:SetTextColor(1, 1, 1, 1)
    f.infoText = infoText

    return f
end

function wowauditWishFrame:SetItemLink(frame, data, cols, row, realrow, column, fShow, table, ...)
    local itemLink = data[realrow][column].value

    frame:SetScript("OnEnter", function()
        addon:CreateHypertip(itemLink)
    end)
    frame:SetScript("OnLeave", function()
        addon:HideTooltip()
    end)

    frame.text:SetText(itemLink)
    frame:Show()
end

-- This doesn't work properly when the table is scrolled, the button is sticky and doesn't respect the row
function wowauditWishFrame:SetWishNote(frame, data, cols, row, realrow, column, fShow, table, ...)
    local note = data[realrow][column].value

    if string.len(note) > 0 then
        local f = frame.noteBtn or CreateFrame("Button", nil, frame)
        f:SetSize(20, 20)
        f:SetPoint("CENTER", frame, "CENTER")
        f:SetNormalTexture("Interface/BUTTONS/UI-GuildButton-PublicNote-Up.png")
        f:SetScript("OnEnter", function()
            addon:CreateTooltip("Wish comment", note)
        end)
        f:SetScript("OnLeave", function()
            addon:HideTooltip()
        end)
        frame.noteBtn = f
        f:Show()
    end
end

function wowauditWishFrame:NumberSort(rowa, rowb, sortbycol)
    local column = self.cols[sortbycol]
    a, b = self:GetRow(rowa)[sortbycol].sortValue, self:GetRow(rowb)[sortbycol].sortValue;

    local direction = column.sort or column.defaultsort or 1
    if direction == 1 then
        return (tonumber(a) or 0) < (tonumber(b) or 0)
    else
        return (tonumber(a) or 0) > (tonumber(b) or 0)
    end
end

function wowauditWishFrame:StringSort(rowa, rowb, sortbycol)
    local column = self.cols[sortbycol]
    a, b = self:GetRow(rowa)[sortbycol].sortValue, self:GetRow(rowb)[sortbycol].sortValue;

    local direction = column.sort or column.defaultsort or 1
    if direction == 1 then
        return (a or "") < (b or "")
    else
        return (a or "") > (b or "")
    end
end
