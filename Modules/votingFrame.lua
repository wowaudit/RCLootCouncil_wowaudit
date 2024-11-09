local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCVotingFrame = addon:GetModule("RCVotingFrame")

local RCwowaudit = addon:GetModule("RCwowaudit")
local wowauditVotingFrame = RCwowaudit:NewModule("wowauditVotingFrame", "AceComm-3.0", "AceConsole-3.0", "AceHook-3.0",
    "AceEvent-3.0", "AceTimer-3.0", "AceSerializer-3.0")

local session = 1
local next = next

function wowauditVotingFrame:OnInitialize()
    if not RCVotingFrame.scrollCols then -- RCVotingFrame hasn't been initialized.
        return self:ScheduleTimer("OnInitialize", 0.5)
    end

    self:SecureHook(RCVotingFrame, "OnEnable", "AddButtonToFrame")

    -- Translate sortnext into colNames (copied from RCLootCouncil_ExtraUtilities)
    self.sortnext = {}
    for _, v in ipairs(RCVotingFrame.scrollCols) do
        if v.sortnext then
            self.sortnext[v.colName] = RCVotingFrame.scrollCols[v.sortnext].colName
        end
    end

    tinsert(RCVotingFrame.scrollCols, 8, {
        name = "Wishlist (" .. logoIcon .. " wowaudit)",
        DoCellUpdate = wowauditVotingFrame.SetCellWishlist,
        colName = "wishlist",
        comparesort = wowauditVotingFrame.WishlistSort,
        width = 150
    })

    tinsert(RCVotingFrame.scrollCols, 9, {
        name = "",
        DoCellUpdate = wowauditVotingFrame.SetCellWishlistNote,
        colName = "wishlistNote",
        width = 30
    })

    self:RegisterMessage("RCSessionChangedPre", "OnMessageReceived")
    self:UpdateSortNext()
end

function wowauditVotingFrame:SetCellWishlist(frame, data, cols, row, realrow, column, fShow, table, ...)
    local lootTable = addon:GetLootTable()

    if not wowauditDataPresent() then
        local text = withColor("no data found", "o")
        frame.text:SetText(text)
        data[realrow].cols[column].value = text
        return
    end

    if lootTable and lootTable[session] then
        local wishes = wowauditDataToDisplay(lootTable[session].itemID, lootTable[session].string, data[realrow].name)

        local text = ""
        if wishes then
            for i, wish in ipairs(wishes) do
                text = text .. displayWish(wish) .. "    "
            end

            if wishes[1] and wishes[1].difficulty then
                text = text .. " (" .. wishes[1].difficulty .. ")"
            end
        end

        if string.len(text) > 0 then
            frame.text:SetText(text)
            data[realrow].cols[column].value = text
            return
        end
    end

    frame.text:SetText("-")
    data[realrow].cols[column].value = "-"
end

function wowauditVotingFrame:SetCellWishlistNote(frame, data, cols, row, realrow, column, fShow, table, ...)
    local lootTable = addon:GetLootTable()

    if lootTable and lootTable[session] and wowauditDataPresent() then
        local wishes = wowauditDataToDisplay(lootTable[session].itemID, lootTable[session].string, data[realrow].name)

        local text = ""
        if wishes then
            for i, wish in ipairs(wishes) do
                wish = transformWish(wish)
                if wish.comment then
                    text = text .. specIcon(wish.spec, 12) .. " " .. wish.comment .. "\n\n"
                end
            end
        end

        local f = frame.noteBtn or CreateFrame("Button", nil, frame)
        if string.len(text) > 0 then
            f:SetSize(20, 20)
            f:SetPoint("CENTER", frame, "CENTER")
            f:SetNormalTexture("Interface/BUTTONS/UI-GuildButton-PublicNote-Up.png")
            f:SetScript("OnEnter", function()
                addon:CreateTooltip("Wishlist comment", text)
            end)
            f:SetScript("OnLeave", function()
                addon:HideTooltip()
            end)
            data[realrow].cols[column].value = 1
        else
            f:SetNormalTexture("Interface/BUTTONS/UI-GuildButton-PublicNote-Disabled.png")
            f:SetScript("OnEnter", nil)
            data[realrow].cols[column].value = 0
        end
        frame.noteBtn = f
    end
end

function wowauditVotingFrame:OnMessageReceived(msg, ...)
    if msg == "RCSessionChangedPre" then
        local s = unpack({...})
        session = s
    end
end

function wowauditVotingFrame:WishlistSort(rowa, rowb, sortbycol)
    local column = self.cols[sortbycol]
    local namea, nameb = self:GetRow(rowa).name, self:GetRow(rowb).name;
    local lootTable = addon:GetLootTable()

    local a = highestWishValue(wowauditDataToDisplay(lootTable[session].itemID, lootTable[session].string, namea))
    local b = highestWishValue(wowauditDataToDisplay(lootTable[session].itemID, lootTable[session].string, nameb))

    if a == b then
        return false
    else
        local direction = column.sort or column.defaultsort or 1
        if direction == 1 then
            return a < b;
        else
            return a > b;
        end
    end
end

function wowauditVotingFrame:AddButtonToFrame()
    local f = RCVotingFrame:GetFrame()
    db = addon:Getdb()

    local text = wowauditValueDisplay == "VALUE" and " Show %" or " Show value"
    local valueDisplayButton = addon:CreateButton(logoIconSmall .. text, f.content)
    valueDisplayButton:SetSize(125, 25)
    valueDisplayButton:SetPoint("RIGHT", f.disenchant, "LEFT", -10, 0)
    valueDisplayButton:SetScript("OnClick", function(self)
        if wowauditValueDisplay == "VALUE" then
            wowauditValueDisplay = "PERCENTAGE"
            valueDisplayButton:SetText(logoIconSmall .. " Show value")
        else
            wowauditValueDisplay = "VALUE"
            valueDisplayButton:SetText(logoIconSmall .. " Show %")
        end

        RCVotingFrame:Update()
    end)

    f.valueDisplayButton = valueDisplayButton
end

function wowauditVotingFrame:UpdateSortNext()
    for index in ipairs(RCVotingFrame.scrollCols) do
        if RCVotingFrame.scrollCols[index].sortnext then
            local exists = RCVotingFrame:GetColumnIndexFromName(self.sortnext[RCVotingFrame.scrollCols[index].colName])
            RCVotingFrame.scrollCols[index].sortnext = exists
        end
    end

    local frame = RCVotingFrame:GetFrame()
    if frame then
        frame.st:SetDisplayCols(RCVotingFrame.scrollCols)
        frame:SetWidth(frame.st.frame:GetWidth() + 20)
    end
end
