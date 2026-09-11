local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local RCLootFrame = addon:GetModule("RCLootFrame")

local RCwowaudit = addon:GetModule("RCwowaudit")
local Theme = wowauditTheme
local SlotWishes = wowauditSlotWishes
local wowauditLootFrame = RCwowaudit:NewModule("wowauditLootFrame", "AceHook-3.0", "AceEvent-3.0")

local ARROW_SIZE = 16
local POPUP_PADDING = 8
local POPUP_LINE = 16
local POPUP_HEADER = 22

local hookRunning = false
local uncachedItems = {}
local expandedEntry

local function requestIfUncached(linkOrID)
    if not linkOrID then
        return
    end

    local itemID = C_Item.GetItemInfoInstant(linkOrID)
    if itemID and not C_Item.GetItemInfo(linkOrID) then
        uncachedItems[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

local function setArrowTexture(texture, expanded)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("common-icon-forwardarrow") then
        texture:SetAtlas("common-icon-forwardarrow")
    else
        texture:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    end
    texture:SetTexCoord(expanded and 1 or 0, expanded and 0 or 1, 0, 1)
end

-- Same compact line as before: the dropped item's wish, with its slot rank in front.
local function compactSummary(data)
    if data and wowauditIsAlreadyEquippedMessage(data.emptySlotMessage) then
        return withColor(data.emptySlotMessage, "w")
    end
    if not data or data.emptySlotMessage then
        if not wowauditDataPresent() or (data and data.emptySlotMessage == "No wishlist data found") then
            return withColor("wowaudit data missing", "o")
        end
        return "not on wishlist"
    end

    for _, wish in ipairs(data.slotWishes or {}) do
        if wish.isDropped then
            if not wish.rank then
                return "not on wishlist"
            end
            return SlotWishes.RankText(wish.rank) .. " " .. (SlotWishes.WishValueText(wish, data.name) or "")
        end
    end

    return "not on wishlist"
end

local function canExpand(data)
    return data and not data.emptySlotMessage and data.slotWishes and #data.slotWishes > 0
end

function wowauditLootFrame:OnInitialize()
    self.initialize = true
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED", "OnItemInfoReceived")
end

function wowauditLootFrame:OnEnable()
    self:SecureHook(RCLootFrame.EntryManager, "GetEntry", "HookGetEntry")
    self:SecureHook(RCLootFrame, "OnDisable", "HidePopup")
end

function wowauditLootFrame:OnItemInfoReceived(_, itemID)
    if uncachedItems[itemID] then
        uncachedItems[itemID] = nil
        self:RefreshVisible()
    end
end

function wowauditLootFrame:RefreshVisible()
    if not RCLootFrame:IsEnabled() then
        return
    end

    for _, entry in ipairs(RCLootFrame.EntryManager.entries) do
        if type(entry) == "table" and entry.frame and entry.frame:IsShown() and entry.item then
            entry:Update(entry.item)
        end
    end

    RCLootFrame.EntryManager:Update()

    if expandedEntry then
        if canExpand(expandedEntry.wowauditWishData) then
            self:ShowPopup(expandedEntry)
        else
            self:HidePopup()
        end
    end
end

function wowauditLootFrame:HookGetEntry(_, item)
    if not hookRunning then
        hookRunning = true
        local frame = RCLootFrame.EntryManager:GetEntry(item)
        if not self:IsHooked(frame, "Update") then
            self:SecureHook(frame, "Update", "HookEntryUpdate")
            self:HookEntryUpdate(frame)
        end
    end
    hookRunning = false
end

function wowauditLootFrame:AttachControls(entry)
    -- Same chrome as the voting frame's Evaluate tab: a real button with a
    -- filled background, hairline, and the forward-arrow atlas.
    local button = CreateFrame("Button", nil, entry.frame)
    button:SetSize(ARROW_SIZE + 6, ARROW_SIZE + 4)
    button:SetFrameLevel(entry.frame:GetFrameLevel() + 2)

    button.bg = Theme:Solid(button, "BACKGROUND")
    button.bg:SetAllPoints()
    button.bg:SetVertexColor(Theme:Color("header"))
    Theme:Hairline(button, "outline", 0)
    Theme:Hairline(button, "hairline", 1)

    button.arrow = button:CreateTexture(nil, "ARTWORK")
    button.arrow:SetSize(ARROW_SIZE - 2, ARROW_SIZE - 2)
    button.arrow:SetPoint("CENTER")
    button.arrow:SetVertexColor(Theme:Color("value"))
    setArrowTexture(button.arrow, false)

    button:SetScript("OnEnter", function(self)
        self.bg:SetVertexColor(0, 0, 0, 1)
    end)
    button:SetScript("OnLeave", function(self)
        self.bg:SetVertexColor(Theme:Color("header"))
    end)
    button:SetScript("OnClick", function()
        wowauditLootFrame:TogglePopup(entry)
    end)

    entry.wowauditArrow = button

    entry.frame:HookScript("OnHide", function()
        if expandedEntry == entry then
            wowauditLootFrame:HidePopup()
        end
    end)
end

function wowauditLootFrame:LayoutArrow(entry, show)
    local button = entry.wowauditArrow
    if not button then
        return
    end

    if not show then
        button:Hide()
        entry.bonuses:ClearAllPoints()
        entry.bonuses:SetPoint("LEFT", entry.itemLvl, "RIGHT", 1, 0)
        if expandedEntry == entry then
            self:HidePopup()
        end
        return
    end

    button:ClearAllPoints()
    button:SetPoint("LEFT", entry.itemLvl, "RIGHT", 4, 0)
    button:Show()
    setArrowTexture(button.arrow, expandedEntry == entry)

    entry.bonuses:ClearAllPoints()
    entry.bonuses:SetPoint("LEFT", button, "RIGHT", 4, 0)
end

function wowauditLootFrame:WishDataFor(entry)
    local lootTable = addon:GetLootTable()
    local session = entry.item and entry.item.sessions and entry.item.sessions[1]
    local lootEntry = session and lootTable and lootTable[session]

    if not lootEntry then
        return {
            name = addon.playerName,
            emptySlotMessage = wowauditDataPresent() and "No wishes in this slot" or "No wishlist data found"
        }
    end

    requestIfUncached(lootEntry.link or lootEntry.string)

    local difficulty = wowauditDifficultyForItem(lootEntry.link) or
                           wowauditDifficultyForItem(lootEntry.string)
    local itemTrack = wowauditTrackForItem(lootEntry.link) or wowauditTrackForItem(lootEntry.string)
    local wishes = wowauditDataToDisplay(lootEntry.itemID, lootEntry.string, addon.playerName)
    local sameSlot = wowauditSameSlotWishes(addon.playerName, lootEntry.itemID, difficulty)
    local priority = trinketPriorityToDisplay(lootEntry.itemID, addon.playerName)
    local value = highestWishValue(wishes)
    local emptySlotMessage = wowauditEmptySlotMessage(addon.playerName, wishes, sameSlot,
        lootEntry.itemID, itemTrack, wowauditPlayerEquippedLinks())
    local slotWishes = {}

    if not emptySlotMessage then
        slotWishes = wowauditRankedSlotWishes(lootEntry, sameSlot, wishes, value, priority)
        for _, wish in ipairs(slotWishes) do
            requestIfUncached(wish.link or wish.id)
        end
    end

    return {
        name = addon.playerName,
        slotWishes = slotWishes,
        emptySlotMessage = emptySlotMessage
    }
end

function wowauditLootFrame:HookEntryUpdate(entry)
    if not entry or not entry.frame then
        return
    end

    if not entry.wowauditArrow then
        self:AttachControls(entry)
    end

    local data = self:WishDataFor(entry)
    entry.wowauditWishData = data

    local text = entry.itemLvl:GetText()
    entry.itemLvl:SetText(text .. " - " .. logoIcon .. " " .. compactSummary(data))
    self:LayoutArrow(entry, canExpand(data))

    -- RCLootCouncil sizes the card before we append the wish line. Measure the
    -- ilvl row (wish, arrow, bonuses) so the frame is exactly as wide as it needs.
    local iconWidth = entry.icon and entry.icon:GetWidth() or 60
    local needed = 10 + iconWidth + 6 + entry.itemLvl:GetStringWidth()
    if entry.wowauditArrow and entry.wowauditArrow:IsShown() then
        needed = needed + 4 + entry.wowauditArrow:GetWidth()
    end
    local bonuses = entry.bonuses:GetStringWidth() or 0
    if bonuses > 0 then
        needed = needed + 4 + bonuses
    end
    needed = needed + 10
    entry.width = math.max(entry.width or 0, 150 + entry.itemText:GetStringWidth(), needed)
end

function wowauditLootFrame:GetPopup()
    if self.popup then
        return self.popup
    end

    local popup = Theme:Panel(UIParent)
    popup:SetFrameStrata("DIALOG")
    popup:EnableMouse(true)
    popup:Hide()

    popup.header = CreateFrame("Frame", nil, popup)
    popup.header:SetHeight(POPUP_HEADER)
    popup.header:SetPoint("TOPLEFT", POPUP_PADDING, -POPUP_PADDING)
    popup.header:SetPoint("TOPRIGHT", -POPUP_PADDING, -POPUP_PADDING)

    popup.header.label = popup.header:CreateFontString(nil, "OVERLAY")
    popup.header.label:SetFont(Theme:Font(11))
    popup.header.label:SetTextColor(Theme:Color("label"))
    popup.header.label:SetJustifyH("LEFT")
    popup.header.label:SetJustifyV("MIDDLE")
    popup.header.label:SetPoint("LEFT", 0, 0)
    popup.header.label:SetText("WISHES IN THIS SLOT")

    popup.header.help = Theme:WishColorHelp(popup.header, POPUP_HEADER, 11)
    popup.header.help:SetPoint("RIGHT", 0, 0)

    local divider = Theme:Divider(popup.header)
    divider:SetPoint("BOTTOMLEFT")
    divider:SetPoint("BOTTOMRIGHT")

    popup.list = SlotWishes:Create(popup, SlotWishes.WIDTH, {
        lineHeight = POPUP_LINE,
        muteAlternatives = false
    })
    popup.list:SetPoint("TOPLEFT", popup.header, "BOTTOMLEFT", 0, -6)

    self.popup = popup
    return popup
end

function wowauditLootFrame:TogglePopup(entry)
    if expandedEntry == entry then
        self:HidePopup()
        return
    end
    self:ShowPopup(entry)
end

function wowauditLootFrame:ShowPopup(entry)
    local data = entry.wowauditWishData or self:WishDataFor(entry)
    entry.wowauditWishData = data
    if not canExpand(data) then
        self:HidePopup()
        return
    end

    local popup = self:GetPopup()
    SlotWishes:Set(popup.list, data)

    local lines = math.max(2, #(data.slotWishes or {}))
    popup:SetSize(SlotWishes.WIDTH + POPUP_PADDING * 2,
        POPUP_PADDING * 2 + POPUP_HEADER + 6 + lines * POPUP_LINE)

    local parent = RCLootFrame.frame
    if parent then
        popup:SetParent(parent)
        popup:SetFrameStrata("DIALOG")
    end
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", entry.frame, "TOPRIGHT", 2, 0)
    popup:Show()
    popup:Raise()

    local previous = expandedEntry
    expandedEntry = entry
    if previous and previous.wowauditArrow then
        setArrowTexture(previous.wowauditArrow.arrow, false)
    end
    if entry.wowauditArrow then
        setArrowTexture(entry.wowauditArrow.arrow, true)
    end
end

function wowauditLootFrame:HidePopup()
    local previous = expandedEntry
    expandedEntry = nil
    if previous and previous.wowauditArrow then
        setArrowTexture(previous.wowauditArrow.arrow, false)
    end
    if self.popup then
        self.popup:Hide()
    end
end
