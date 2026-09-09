local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local Comms = addon.Require "Services.Comms"
local lwin = LibStub("LibWindow-1.1")
local LibDialog = LibStub("LibDialog-1.1")

local RCwowaudit = addon:GetModule("RCwowaudit")
local wowauditEvaluationFrame = RCwowaudit:NewModule("wowauditEvaluationFrame", "AceEvent-3.0", "AceHook-3.0",
    "AceTimer-3.0")

local Theme = wowauditTheme
local Row = wowauditEvaluationRow

local FRAME_NAME = "RCwowauditEvaluationFrame"
local PADDING = 12
local HEADER_HEIGHT = 46
local COLUMN_HEADER_HEIGHT = 18
local FOOTER_HEIGHT = 22
local VISIBLE_ROWS = 8
-- Same size, gap and wrap as RCLootCouncil's voting-frame session buttons.
local SESSION_BUTTON_SIZE = 40
local SESSION_BUTTON_GAP = 2
local SESSION_COLUMN_WRAP = 10
local SCROLLBAR_WIDTH = 4
local REFRESH_DELAY = 0.1
local RESIZE_GRIP = 8
local MIN_SCALE, MAX_SCALE = 0.6, 1.6

local SORT_LABELS = {
    value = "Wish value",
    ilvl = "Item level",
    response = "Response",
    name = "Name"
}

local SORT_ORDER = {"value", "response", "ilvl", "name"}

local DIFFICULTY_LABELS = {
    R = "LFR",
    N = "Normal",
    H = "Heroic",
    M = "Mythic"
}

local DIFFICULTY_ORDER = {"R", "N", "H", "M"}

local maxRowStep = Row.HEIGHT + Row.SPACING
local minRowStep = Row.MIN_HEIGHT + Row.SPACING
local crestIcons = nil
local uncachedItems = {}
local filterMenu, sortMenu, difficultyMenu
-- Which difficulty's wishes to show. Nil means each item's own. Kept for the
-- current loot table so closing the window or switching tabs does not reset it.
local wishDifficultyOverride

local function chromeHeight()
    return HEADER_HEIGHT + COLUMN_HEADER_HEIGHT + FOOTER_HEIGHT + PADDING
end

-- GetLeft/GetTop are the visual edges in UIParent space. Pinning TOPLEFT there
-- keeps the header still when the height changes, and is also the only anchor
-- StartSizing can grow from without jumping.
local function pinTopLeft(f)
    local left, top = f:GetLeft(), f:GetTop()
    if not left or not top then
        return
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local function setHeightKeepingTop(f, height)
    pinTopLeft(f)
    f:SetHeight(height)
    f:SavePosition()
end

-- Same StartMoving/SavePosition path RCLootCouncil's voting frame uses
-- (UI/Widgets/Frame.lua). That frame never snaps; a custom cursor-follow did.
local function savePosition(f)
    if f:GetScale() and f:GetLeft() and f:GetRight() and f:GetTop() and f:GetBottom() then
        f:SavePosition()
    end
end

local function votingFrame()
    return addon:GetActiveModule("votingframe")
end

local function currentSession()
    local module = votingFrame()
    return module and module:GetCurrentSession() or 1
end

-- The voting frame keeps its own copy of the loot table and that copy is the only
-- one carrying candidate responses, so it is the source of truth here. The addon's
-- table is the fallback for when the voting frame isn't running.
local function displayLootTable()
    local module = votingFrame()
    local lootTable = module and module.GetLootTable and module:GetLootTable()

    if lootTable and next(lootTable) ~= nil then
        return lootTable
    end

    return addon:GetLootTable() or {}
end

local function settings()
    local db = addon:Getdb()
    db.wowauditEvaluationFilters = db.wowauditEvaluationFilters or {}
    db.wowauditEvaluationSort = db.wowauditEvaluationSort or "value"
    return db
end

-- Response filter, using the same keys RCLootCouncil's own voting frame filter uses
-- so the two feel consistent. Defaults to actual responses only, which is what
-- "players who responded" means.
local function responseVisible(response)
    local filters = settings().wowauditEvaluationFilters

    if type(response) == "number" then
        return filters[response] ~= false
    end
    if response == "PASS" or response == "AUTOPASS" then
        return filters[response] == true
    end
    return filters.STATUS == true
end

-- Awarding overwrites the candidate's response with "AWARDED" and stashes the
-- one they actually clicked in real_response. Filter and display that original
-- so Mainspec still shows as Mainspec; the award column already marks the winner.
local function candidateResponse(candidate)
    if candidate.response == "AWARDED" and candidate.real_response ~= nil then
        return candidate.real_response
    end
    return candidate.response
end

local function awardedToCandidate(entry, name)
    local awarded = entry and entry.awarded
    return type(awarded) == "string" and (addon:UnitIsUnit(name, awarded) or name == awarded)
end

-- Asks the client to load anything not in its item cache yet, so the redraw on
-- GET_ITEM_INFO_RECEIVED fills in the names and icons.
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

local function requestTrackItems(profile, trackName)
    local items = profile and trackName and profile.eq and profile.eq[trackName] and
                      profile.eq[trackName].i
    if type(items) ~= "table" then
        return
    end
    for _, item in ipairs(items) do
        requestIfUncached(item[1])
    end
end

local function itemDifficultyFor(entry)
    if not entry then
        return nil
    end
    return wowauditDifficultyForItem(entry.link) or wowauditDifficultyForItem(entry.string)
end

-- Explicit pick from the header, otherwise the loot's own difficulty. The
-- pick is kept across items and while the window is closed, until a new loot
-- table replaces the session.
local function wishLookupDifficulty(entry)
    local native = itemDifficultyFor(entry)
    return wishDifficultyOverride or native, native
end

-- The dropped item and the character's other wishes for that slot, ranked together
-- so the council can see where the drop sits among the alternatives. The dropped
-- item is always in the list even with no wishes at all.
local function rankedSlotWishes(entry, sameSlot, wishes, value, priority)
    local bonus
    for _, wish in ipairs(wishes or {}) do
        bonus = wish.b or wish.bonus
        if bonus then
            break
        end
    end

    local ranked = {{
        id = entry.itemID,
        bonus = bonus,
        wishes = wishes,
        value = value,
        priority = priority,
        isDropped = true
    }}

    for _, alternative in ipairs(sameSlot) do
        tinsert(ranked, alternative)
    end

    table.sort(ranked, function(a, b)
        if a.value == b.value then
            return a.isDropped or (not b.isDropped and a.id < b.id)
        end
        return a.value > b.value
    end)

    while #ranked > Row.MAX_WISHES_IN_SLOT do
        -- Never drop the item actually being rolled for to make room.
        local last = ranked[#ranked]
        if last.isDropped then
            ranked[#ranked - 1] = last
        end
        table.remove(ranked)
    end

    return ranked
end

-- Crest currency icons are the same for everyone, so they are resolved once and
-- shared by every row.
local function crestIconsByTrack()
    if not crestIcons then
        crestIcons = {}
        for track in pairs(wowauditCrestCurrencies) do
            local info = wowauditCrestInfo(track)
            crestIcons[track] = info and info.icon or nil
        end
    end
    return crestIcons
end

function wowauditEvaluationFrame:OnInitialize()
    -- Wishlist items the player has never seen are not in the client's item cache,
    -- so they resolve asynchronously and the window redraws once they land.
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED", "OnItemInfoReceived")
    self:RegisterMessage("RCSessionChangedPost", "OnSessionChanged")
    self:RegisterMessage("RCLootTableAdditionsReceived", "ScheduleRefresh")
    self:RegisterMessage("RCMLAwardSuccess", "ScheduleRefresh")
    self:RegisterMessage("RCConfigTableChanged", "ScheduleRefresh")

    local refresh = function()
        self:ScheduleRefresh()
    end

    local function onNewLootTable()
        wishDifficultyOverride = nil
        RCwowaudit:GetModule("wowauditShareData"):AllowProfileRequest()
        self:ScheduleRefresh()
    end

    -- No message is fired for candidate responses, so the comms themselves are the
    -- trigger. Everything funnels into one debounced redraw.
    self.subscriptions = Comms:BulkSubscribe(addon.PREFIXES.MAIN, {
        response = refresh,
        change_response = refresh,
        lootAck = refresh,
        vote = refresh,
        awarded = refresh,
        lootTable = onNewLootTable,
        lt_add = refresh
    })

    self.wowauditSubscriptions = Comms:BulkSubscribe(RCwowaudit.PREFIXES.MAIN, {
        wishlist_data = refresh,
        profile = refresh
    })
end

function wowauditEvaluationFrame:OnDisable()
    for _, subscriptions in ipairs({self.subscriptions or {}, self.wowauditSubscriptions or {}}) do
        for _, subscription in ipairs(subscriptions) do
            subscription:unsubscribe()
        end
    end
end

function wowauditEvaluationFrame:ScheduleRefresh()
    if not self.frame or not self.frame:IsShown() then
        return
    end
    if self.refreshTimer then
        return
    end

    self.refreshTimer = self:ScheduleTimer(function()
        wowauditEvaluationFrame.refreshTimer = nil
        wowauditEvaluationFrame:Refresh()
    end, REFRESH_DELAY)
end

function wowauditEvaluationFrame:OnItemInfoReceived(_, itemID)
    if uncachedItems[itemID] then
        uncachedItems[itemID] = nil
        self:ScheduleRefresh()
    end
end

-- Switching in the voting frame drives this window. Because the tab strip only
-- ever calls SwitchSession and this handler only ever reads, there is no loop.
function wowauditEvaluationFrame:OnSessionChanged()
    self:ScheduleRefresh()
end

function wowauditEvaluationFrame:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Same confirm dialog as the voting frame's right-click Award, including
-- changing the winner after the item has already been given out.
function wowauditEvaluationFrame:Award(name)
    local module = votingFrame()
    local session = currentSession()
    local lootTable = displayLootTable()
    local candidate = lootTable[session] and lootTable[session].candidates and lootTable[session].candidates[name]

    if not module or not module.GetAwardPopupData or not candidate then
        return
    end

    LibDialog:Spawn("RCLOOTCOUNCIL_CONFIRM_AWARD", module:GetAwardPopupData(session, name, candidate))
end

function wowauditEvaluationFrame:Show()
    local frame = self:GetFrame()
    frame:Show()
    frame:Raise()
    self:Refresh()

    -- Backfill only when this client is missing profiles (opened late and missed
    -- the loot-ack broadcast). Toggling the window is not another raid-wide request.
    if self:HasMissingProfiles() then
        RCwowaudit:GetModule("wowauditShareData"):RequestProfiles()
    end
end

function wowauditEvaluationFrame:HasMissingProfiles()
    local entry = displayLootTable()[currentSession()]
    for name in pairs(entry and entry.candidates or {}) do
        if not wowauditProfileForCharacter(name) then
            return true
        end
    end
    return false
end

function wowauditEvaluationFrame:Hide()
    if self.frame then
        if self.frame.scalePanel then
            self.frame.scalePanel:Hide()
        end
        self.frame:Hide()
    end
end

function wowauditEvaluationFrame:GetFrame()
    if self.frame then
        return self.frame
    end

    local db = addon:Getdb()
    db.UI[FRAME_NAME] = db.UI[FRAME_NAME] or {}

    local width = Row.WIDTH + PADDING * 2 + SCROLLBAR_WIDTH + 4
    local minHeight = chromeHeight() + 2 * minRowStep

    local f = Theme:Panel(UIParent, FRAME_NAME)
    f:SetSize(width, db.UI[FRAME_NAME].height or (chromeHeight() + VISIBLE_ROWS * maxRowStep))
    -- RCLootCouncil's own frames sit in DIALOG, so anything lower ends up behind
    -- the voting frame this window is opened from.
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    -- Without this the body is click-through and clicks land on whatever is behind.
    f:EnableMouse(true)
    f:Hide()

    f:SetResizable(true)
    f:SetResizeBounds(width, minHeight, width, UIParent:GetHeight())

    lwin:Embed(f)
    f:RegisterConfig(db.UI[FRAME_NAME])
    f:RestorePosition()
    -- NOT MakeDraggable: that also does RegisterForDrag("LeftButton") on f. RCLootCouncil's
    -- RCFrame calls MakeDraggable too, but its top-level frame is never EnableMouse'd, so those
    -- drag handlers stay dormant and only SetMovable matters. We do enable the mouse on f (to
    -- block click-through), which would activate LibWindow's drag on the same frame the header
    -- already moves with StartMoving. WoW's drag threshold then bubbles from the header to f and
    -- fires a second StartMoving mid-drag, re-basing the move origin - that is the intermittent
    -- snap. SetMovable alone gives us movability with a single drag owner, like the voting frame.
    f:SetMovable(true)

    filterMenu = filterMenu or MSA_DropDownMenu_Create("RCwowauditEvaluationFilterMenu", UIParent)
    sortMenu = sortMenu or MSA_DropDownMenu_Create("RCwowauditEvaluationSortMenu", UIParent)
    difficultyMenu = difficultyMenu or MSA_DropDownMenu_Create("RCwowauditEvaluationDifficultyMenu", UIParent)
    MSA_DropDownMenu_Initialize(filterMenu, self.FilterMenu)
    MSA_DropDownMenu_Initialize(sortMenu, self.SortMenu)
    MSA_DropDownMenu_Initialize(difficultyMenu, self.DifficultyMenu)

    self:BuildHeader(f)
    self:BuildTabs(f)
    self:BuildColumnHeader(f)
    self:BuildList(f)
    self:BuildFooter(f)
    self:BuildResizeGrip(f)

    -- Dragging the body moves the window too, the same as RCLootCouncil's content frame.
    -- This is a manual StartMoving, not LibWindow's RegisterForDrag, so f stays the single
    -- drag owner and no second StartMoving can fire mid-drag. Children that capture the
    -- mouse (header, rows, resize grip) keep their own behaviour; bare areas fall through here.
    f:SetScript("OnMouseDown", function(self)
        self:StartMoving()
    end)
    f:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        savePosition(self)
    end)

    -- Escape closes the window, which can happen mid-drag. RCLootCouncil guards its own
    -- frames the same way: without this the frame stays in moving or sizing mode and is
    -- left anchored wherever it happened to be, ignoring later drags.
    f:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        if self.scalePanel then
            self.scalePanel:Hide()
        end
    end)

    tinsert(UISpecialFrames, FRAME_NAME)

    self.frame = f
    return f
end

-- Drag the bottom edge to show more or fewer candidates at once.
function wowauditEvaluationFrame:BuildResizeGrip(f)
    local grip = CreateFrame("Frame", nil, f)
    grip:SetHeight(RESIZE_GRIP)
    grip:SetPoint("BOTTOMLEFT")
    grip:SetPoint("BOTTOMRIGHT")
    grip:EnableMouse(true)

    -- Drag events rather than mouse down/up: WoW guarantees OnDragStop fires even when
    -- the button is released away from the grip. With OnMouseUp the frame could be left
    -- stuck in sizing mode, following the cursor and ignoring later drags.
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function()
        pinTopLeft(f)
        f:StartSizing("BOTTOM")
    end)
    grip:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        addon:Getdb().UI[FRAME_NAME].height = f:GetHeight()
        -- Resizing leaves the frame anchored by whatever edge StartSizing used, so let
        -- LibWindow renormalise the stored position afterwards.
        savePosition(f)
        wowauditEvaluationFrame:UpdateScrollbar()
    end)

    local hint = Theme:Solid(grip, "OVERLAY")
    hint:SetHeight(1)
    hint:SetPoint("BOTTOMLEFT", PADDING, 2)
    hint:SetPoint("BOTTOMRIGHT", -PADDING, 2)
    hint:SetVertexColor(Theme:Color("hairline"))

    f.resizeGrip = grip
end

function wowauditEvaluationFrame:BuildHeader(f)
    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:EnableMouse(true)
    header:SetScript("OnMouseDown", function()
        f:StartMoving()
        f:SetToplevel(true)
    end)
    header:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        savePosition(f)
    end)

    local bg = Theme:Solid(header, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetGradient("VERTICAL", CreateColor(0.06, 0.06, 0.075, 1), CreateColor(0.11, 0.115, 0.135, 1))

    local divider = Theme:Divider(header)
    divider:SetPoint("BOTTOMLEFT")
    divider:SetPoint("BOTTOMRIGHT")

    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\AddOns\\RCLootCouncil_wowaudit\\Media\\logo")
    logo:SetSize(22, 22)
    logo:SetPoint("LEFT", PADDING, 0)

    header.itemIcon = Theme:Icon(header, 26)
    header.itemIcon:SetPoint("LEFT", logo, "RIGHT", PADDING, 0)

    header.itemHover = CreateFrame("Frame", nil, header)
    header.itemHover:SetAllPoints(header.itemIcon)
    header.itemHover:EnableMouse(true)
    header.itemHover:SetScript("OnEnter", function(self)
        Theme:ShowItemTooltip(self, header.itemLink)
    end)
    header.itemHover:SetScript("OnLeave", function()
        Theme:HideItemTooltip()
    end)

    header.itemName = Theme:Value(header, 15, true)
    header.itemName:SetPoint("LEFT", header.itemIcon, "RIGHT", 8, 0)
    header.itemName:SetWordWrap(false)

    -- Same pairing as the equipped column: track badge, then ilvl.
    header.track = Theme:Pill(header, 18)
    header.track:SetPoint("LEFT", header.itemName, "RIGHT", 8, 0)
    Theme:AttachTooltip(header.track)

    header.ilvl = Theme:Value(header, 15, true)
    header.ilvl:SetPoint("LEFT", header.track, "RIGHT", 8, 0)

    -- Sockets and tertiary stats, using RCLootCouncil's own formatting so the two
    -- windows say the same thing about the same item.
    header.bonuses = Theme:Value(header, 12)
    header.bonuses:SetTextColor(0.2, 1, 0.2)
    header.bonuses:SetPoint("LEFT", header.ilvl, "RIGHT", 8, 0)

    local close = Theme:Button(header, "X", 24, 22)
    close:SetPoint("RIGHT", -PADDING, 0)
    close:SetScript("OnClick", function()
        wowauditEvaluationFrame:Hide()
    end)

    header.minimizeButton = Theme:Button(header, "_", 24, 22)
    header.minimizeButton:SetPoint("RIGHT", close, "LEFT", -4, 0)
    header.minimizeButton:SetScript("OnClick", function()
        wowauditEvaluationFrame:ToggleMinimized()
    end)

    header.scaleButton = Theme:Button(header, "Scale", 52, 22)
    header.scaleButton:SetPoint("RIGHT", header.minimizeButton, "LEFT", -4, 0)
    header.scaleButton:SetScript("OnClick", function()
        wowauditEvaluationFrame:ToggleScaleSlider()
    end)

    header.filterButton = Theme:Button(header, "Responses", 88, 22)
    header.filterButton:SetPoint("RIGHT", header.scaleButton, "LEFT", -6, 0)
    -- MSA_ToggleDropDownMenu is a real toggle, so a second click closes the menu
    -- instead of closing and immediately reopening it.
    header.filterButton:SetScript("OnClick", function(button)
        MSA_ToggleDropDownMenu(1, nil, filterMenu, button, 0, 0)
    end)

    header.sortButton = Theme:Button(header, "Sort", 110, 22)
    header.sortButton:SetPoint("RIGHT", header.filterButton, "LEFT", -6, 0)
    header.sortButton:SetScript("OnClick", function(button)
        MSA_ToggleDropDownMenu(1, nil, sortMenu, button, 0, 0)
    end)

    header.valueButton = Theme:Button(header, "Show %", 84, 22)
    header.valueButton:SetPoint("RIGHT", header.sortButton, "LEFT", -6, 0)
    header.valueButton:SetScript("OnClick", function()
        RCwowaudit:SetValueDisplay(wowauditValueDisplay == "VALUE" and "PERCENTAGE" or "VALUE")
        wowauditEvaluationFrame:Refresh()

        local module = votingFrame()
        if module and module:IsEnabled() then
            module:Update()
        end
    end)

    header.difficultyButton = Theme:Button(header, "Wishes: Heroic", 124, 22)
    header.difficultyButton:SetPoint("RIGHT", header.valueButton, "LEFT", -6, 0)
    header.difficultyButton:SetScript("OnClick", function(button)
        MSA_ToggleDropDownMenu(1, nil, difficultyMenu, button, 0, 0)
    end)

    f.header = header
end

function wowauditEvaluationFrame:BuildTabs(f)
    -- Hangs off the left of the window, same place and size as the voting
    -- frame's sessionToggleFrame.
    local tabs = CreateFrame("Frame", nil, f)
    tabs:SetWidth(SESSION_BUTTON_SIZE)
    tabs:SetPoint("TOPRIGHT", f, "TOPLEFT", -SESSION_BUTTON_GAP, 0)
    tabs:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", -SESSION_BUTTON_GAP, 0)
    tabs.buttons = {}
    f.tabs = tabs
end

function wowauditEvaluationFrame:BuildColumnHeader(f)
    local strip = CreateFrame("Frame", nil, f)
    strip:SetHeight(COLUMN_HEADER_HEIGHT)
    strip:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", PADDING, 0)
    strip:SetPoint("TOPRIGHT", f.header, "BOTTOMRIGHT", -PADDING, 0)

    -- Column labels live here rather than on every card, which keeps the rows clean
    -- while still pairing each value with a label. This strip shares its left edge
    -- with the rows, so the row's own x offsets line the labels up exactly.
    strip.labels = {}
    for _, column in ipairs(Row.columns) do
        local label = Theme:Label(strip, column.label)
        label:SetPoint("LEFT", strip, "LEFT", column.x, 0)
        strip.labels[column.key] = label

        -- A small legend on the right of the wishes column. The swatches use the same
        -- colour keys as displayWish so they match the values shown in the column.
        if column.key == "wishes" then
            local help = CreateFrame("Frame", nil, strip)
            help:SetSize(COLUMN_HEADER_HEIGHT, COLUMN_HEADER_HEIGHT)
            help:SetPoint("LEFT", strip, "LEFT", column.x + column.width - COLUMN_HEADER_HEIGHT, 0)

            local glyph = Theme:Label(help, "?")
            glyph:SetPoint("CENTER")

            Theme:AttachTooltip(help)
            help:SetTooltip("Wish colours", withColor("Best in slot", "b"),
                withColor("Not best in slot", "n"), withColor("Outdated", "o"))
            strip.wishHelp = help
        end
    end

    f.columnHeader = strip
end

function wowauditEvaluationFrame:BuildList(f)
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", f.columnHeader, "BOTTOMLEFT", 0, -2)
    -- Anchored top and bottom so the list grows with the window instead of needing a
    -- recalculated row count.
    scroll:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PADDING, FOOTER_HEIGHT + RESIZE_GRIP)
    scroll:SetWidth(Row.WIDTH)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(Row.WIDTH, 1)
    scroll:SetScrollChild(child)

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        if IsControlKeyDown() then
            lwin.SetScale(f, delta > 0 and f:GetScale() + 0.03 or f:GetScale() - 0.03)
            return
        end

        local range = math.max(0, child:GetHeight() - self:GetHeight())
        local target = math.min(range, math.max(0, self:GetVerticalScroll() - delta * minRowStep))
        self:SetVerticalScroll(target)
        wowauditEvaluationFrame:UpdateScrollbar()
    end)

    local track = CreateFrame("Frame", nil, f)
    track:SetWidth(SCROLLBAR_WIDTH)
    track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
    track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
    Theme:Fill(track, "track", "ARTWORK")

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(SCROLLBAR_WIDTH)
    thumb:SetPoint("TOP")
    Theme:Fill(thumb, {1, 1, 1, 0.28}, "OVERLAY")
    thumb:RegisterForDrag("LeftButton")

    thumb:SetScript("OnDragStart", function(self)
        self.dragOrigin = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        self.scrollOrigin = scroll:GetVerticalScroll()
        self:SetScript("OnUpdate", function(thumb)
            local range = math.max(0, child:GetHeight() - scroll:GetHeight())
            if range == 0 then
                return
            end

            local travel = track:GetHeight() - thumb:GetHeight()
            if travel <= 0 then
                return
            end

            local cursor = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
            local moved = (thumb.dragOrigin - cursor) / travel * range
            scroll:SetVerticalScroll(math.min(range, math.max(0, thumb.scrollOrigin + moved)))
            wowauditEvaluationFrame:UpdateScrollbar()
        end)
    end)
    thumb:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    f.scroll = scroll
    f.scrollChild = child
    f.scrollTrack = track
    f.scrollThumb = thumb

    f.rowPool = CreateObjectPool(function()
        return Row:Create(child)
    end, function(_, row)
        row:Hide()
        row:ClearAllPoints()
    end)

    f.emptyText = Theme:Value(scroll, 12)
    f.emptyText:SetTextColor(Theme:Color("dim"))
    f.emptyText:SetPoint("TOP", scroll, "TOP", 0, -40)
    f.emptyText:Hide()
end

function wowauditEvaluationFrame:BuildFooter(f)
    local footer = CreateFrame("Frame", nil, f)
    footer:SetHeight(FOOTER_HEIGHT)
    footer:SetPoint("BOTTOMLEFT", PADDING, 2)
    footer:SetPoint("BOTTOMRIGHT", -PADDING, 2)

    footer.left = Theme:Value(footer, 10)
    footer.left:SetTextColor(Theme:Color("dim"))
    footer.left:SetPoint("LEFT")

    footer.right = Theme:Value(footer, 10)
    footer.right:SetTextColor(Theme:Color("dim"))
    footer.right:SetPoint("RIGHT")

    f.footer = footer
end

function wowauditEvaluationFrame:UpdateScrollbar()
    local f = self.frame
    local range = f.scrollChild:GetHeight()
    local visible = f.scroll:GetHeight()

    if range <= visible then
        -- Filtering down to fewer rows can leave the view scrolled past the content.
        f.scroll:SetVerticalScroll(0)
        f.scrollTrack:Hide()
        return
    end

    if f.scroll:GetVerticalScroll() > range - visible then
        f.scroll:SetVerticalScroll(range - visible)
    end

    f.scrollTrack:Show()

    local trackHeight = f.scrollTrack:GetHeight()
    local thumbHeight = math.max(20, trackHeight * (visible / range))
    local travel = trackHeight - thumbHeight
    local progress = f.scroll:GetVerticalScroll() / (range - visible)

    f.scrollThumb:SetHeight(thumbHeight)
    f.scrollThumb:SetPoint("TOP", f.scrollTrack, "TOP", 0, -travel * progress)
end

-- Everything a row needs, gathered per candidate so the row itself only draws.
function wowauditEvaluationFrame:BuildRowData(entry, session)
    local typeCode = entry.typeCode
    local difficulty = wishLookupDifficulty(entry)
    -- Prefer the full link; `string` is RCLootCouncil's comms form without "item:".
    local itemTrack = wowauditTrackForItem(entry.link) or wowauditTrackForItem(entry.string)
    local catalyst = wowauditCatalystCharges()
    local bonusRoll = wowauditBonusRollInfo()
    local bonusRollIcon = bonusRoll and bonusRoll.icon or nil
    local icons = crestIconsByTrack()
    local encounterID = wowauditEncounterForItem(entry.itemID)

    local rows = {}
    local best = 0
    local profilesFound = 0

    for name, candidate in pairs(entry.candidates or {}) do
        local responseKey = candidateResponse(candidate)
        if awardedToCandidate(entry, name) or responseVisible(responseKey) then
            local response = addon:GetResponse(typeCode, responseKey)
            local wishes = wowauditDataToDisplay(entry.itemID, entry.string, name, difficulty)
            local profile = wowauditProfileForCharacter(name)
            local value = highestWishValue(wishes)
            local sameSlot = wowauditSameSlotWishes(name, entry.itemID, difficulty)
            local bonusLoot = wowauditBonusLootFor(name, encounterID)

            requestIfUncached(candidate.gear1)
            requestIfUncached(candidate.gear2)
            requestIfUncached(bonusLoot and bonusLoot.itemID)
            for _, alternative in ipairs(sameSlot) do
                requestIfUncached(alternative.id)
            end
            requestTrackItems(profile, itemTrack and itemTrack.track)
            for _, gear in ipairs({candidate.gear1, candidate.gear2}) do
                local equippedTrack = gear and wowauditTrackForItem(gear, true)
                if equippedTrack then
                    requestTrackItems(profile, equippedTrack.track)
                end
            end

            if profile then
                profilesFound = profilesFound + 1
            end
            if value > best then
                best = value
            end

            local priority = trinketPriorityToDisplay(entry.itemID, name)

            tinsert(rows, {
                name = name,
                class = candidate.class,
                specID = candidate.specID,
                response = responseKey,
                responseText = response and response.text,
                responseColor = response and response.color,
                responseSort = response and response.sort or 999,
                note = candidate.note,
                roll = candidate.roll,
                votes = candidate.votes,
                ilvl = candidate.ilvl,
                gear1 = candidate.gear1,
                gear2 = candidate.gear2,
                wishes = wishes,
                wishValue = value,
                itemTrack = itemTrack,
                priority = priority,
                bonusRollTarget = wowauditBonusRollTargetForItem(entry.itemID, name),
                bonusRollIcon = bonusRollIcon,
                bonusLoot = bonusLoot,
                slotWishes = rankedSlotWishes(entry, sameSlot, wishes, value, priority),
                profile = profile,
                crestIcons = icons,
                catalystIcon = catalyst and catalyst.icon,
                awardedTo = entry.awarded
            })
        end
    end

    for _, row in ipairs(rows) do
        row.bestWishValue = best
    end

    return rows, profilesFound
end

-- Each sort exposes a single numeric key so ties can fall through to the name
-- without evaluating a comparator twice per comparison.
local sortKeys = {
    value = function(row)
        return -row.wishValue
    end,
    ilvl = function(row)
        return -(tonumber(row.ilvl) or 0)
    end,
    response = function(row)
        return row.responseSort
    end
}

function wowauditEvaluationFrame:Refresh()
    local f = self.frame
    if not f or not f:IsShown() then
        return
    end

    local session = currentSession()
    local lootTable = displayLootTable()
    local entry = lootTable[session]

    self:RefreshTabs(lootTable, session)
    self:RefreshHeader(entry)

    f.rowPool:ReleaseAll()

    if not entry then
        f.scrollChild:SetHeight(1)
        f.emptyText:SetText("No loot session is running.")
        f.emptyText:Show()
        self:RefreshFooter(0, 0)
        self:UpdateScrollbar()
        return
    end

    local rows, profilesFound = self:BuildRowData(entry, session)

    local keyFor = sortKeys[settings().wowauditEvaluationSort]
    if keyFor then
        for _, row in ipairs(rows) do
            row.sortKey = keyFor(row)
        end
    end

    table.sort(rows, function(a, b)
        if keyFor and a.sortKey ~= b.sortKey then
            return a.sortKey < b.sortKey
        end
        return a.name < b.name
    end)

    local offset = 0
    for index, data in ipairs(rows) do
        local row = f.rowPool:Acquire()
        row:SetPoint("TOPLEFT", f.scrollChild, "TOPLEFT", 0, -offset)
        Row:SetData(row, data, index)
        row:Show()
        offset = offset + row:GetHeight() + Row.SPACING
    end

    f.scrollChild:SetHeight(math.max(1, offset > 0 and offset - Row.SPACING or 1))

    if #rows == 0 then
        f.emptyText:SetText("No candidates match the response filter.")
        f.emptyText:Show()
    else
        f.emptyText:Hide()
    end

    self:RefreshFooter(profilesFound, #rows)
    self:UpdateScrollbar()
end

function wowauditEvaluationFrame:RefreshHeader(entry)
    local header = self.frame.header
    local crestsLabel = self.frame.columnHeader.labels.crests

    header.valueButton:SetLabel(wowauditValueDisplay == "VALUE" and "Show %" or "Show value")
    header.sortButton:SetLabel("Sort: " .. (SORT_LABELS[settings().wowauditEvaluationSort] or "Wish value"))
    local _, nativeDifficulty = wishLookupDifficulty(entry)
    local shownDifficulty = wishDifficultyOverride or nativeDifficulty
    header.difficultyButton:SetLabel("Wishes: " .. (DIFFICULTY_LABELS[shownDifficulty] or "Auto"))

    local track = entry and (wowauditTrackForItem(entry.link) or wowauditTrackForItem(entry.string))
    crestsLabel:SetText(strupper(track and (track.track .. " crests left") or "Crests"))

    if not entry then
        header.itemLink = nil
        header.itemIcon:Hide()
        header.itemName:SetText("Loot evaluation")
        header.itemName:SetTextColor(Theme:Color("value"))
        header.track:Hide()
        header.track:SetWidth(0.01)
        header.track:SetTooltip()
        header.ilvl:SetText("")
        header.bonuses:SetText("")
        return
    end

    header.itemLink = entry.link
    header.itemIcon:SetTexture(entry.texture)
    header.itemIcon:Show()

    local name, _, quality = C_Item.GetItemInfo(entry.link or entry.string)
    header.itemName:SetText(name or "...")

    local color = quality and ITEM_QUALITY_COLORS[quality]
    if color then
        header.itemName:SetTextColor(color.r, color.g, color.b)
    else
        header.itemName:SetTextColor(Theme:Color("value"))
    end

    if track then
        header.track:Set(wowauditTrackLabel(track), wowauditTrackColor(track.track))
        header.track:SetTooltip(wowauditTrackLabel(track),
            wowauditStepsLeft(track) .. " upgrades left on this item")
    else
        header.track:Hide()
        header.track:SetWidth(0.01)
        header.track:SetTooltip()
    end

    local ilvl = C_Item.GetDetailedItemLevelInfo(entry.link or entry.string) or entry.ilvl
    header.ilvl:SetText(ilvl and tostring(ilvl) or "")

    local bonuses = addon:GetItemBonusText(entry.link, "/")
    header.bonuses:SetText(bonuses ~= "" and ("+ " .. bonuses) or "")
end

function wowauditEvaluationFrame:RefreshTabs(lootTable, session)
    local tabs = self.frame.tabs
    lootTable = lootTable or {}

    for index = #lootTable + 1, #tabs.buttons do
        tabs.buttons[index]:Hide()
    end

    for index, entry in ipairs(lootTable) do
        local button = tabs.buttons[index]
        if not button then
            -- Same IconBordered widget the voting frame uses, including the
            -- ready-check overlay for awarded items.
            button = addon.UI:NewNamed("IconBordered", tabs, FRAME_NAME .. "Session" .. index,
                entry.texture)
            if index == 1 then
                button:SetPoint("TOPRIGHT", tabs)
            elseif mod(index, SESSION_COLUMN_WRAP) == 1 then
                button:SetPoint("TOPRIGHT", tabs.buttons[index - SESSION_COLUMN_WRAP], "TOPLEFT",
                    -SESSION_BUTTON_GAP, 0)
            else
                button:SetPoint("TOP", tabs.buttons[index - 1], "BOTTOM", 0, -SESSION_BUTTON_GAP)
            end
            button:SetScript("OnClick", function(self)
                local module = votingFrame()
                local loot = displayLootTable()

                if module and module:IsEnabled() and loot and loot[self.session] then
                    module:SwitchSession(self.session)
                end
            end)
            button.check = button:CreateTexture(nil, "OVERLAY")
            button.check:SetTexture("interface/raidframe/readycheck-ready")
            button.check:SetDesaturated(true)
            button.check:SetAllPoints()
            button.check:Hide()
            tabs.buttons[index] = button
        end

        button.session = index
        button:SetNormalTexture(entry.texture or "Interface\\InventoryItems\\WoWUnknownItem01")
        button:GetNormalTexture():SetDrawLayer("BACKGROUND")
        button.check:Hide()

        local lines = {format("Click to switch to %s", entry.link or ("Item " .. index))}
        if index == session then
            button:SetBorderColor("yellow")
            button.check:SetVertexColor(1, 1, 0, 1)
            if entry.awarded then
                button.check:Show()
            end
        elseif entry.awarded then
            button:SetBorderColor("green")
            button.check:SetVertexColor(0, 1, 0, 1)
            button.check:Show()
            tinsert(lines, "This item has been awarded")
        else
            button:SetBorderColor("white")
        end

        button:SetScript("OnEnter", function(self)
            Theme:ShowTooltip(self, unpack(lines))
        end)
        button:SetScript("OnLeave", function()
            Theme:HideTooltip()
        end)
        button:Show()
    end
end

function wowauditEvaluationFrame:RefreshFooter(profilesFound, total)
    local footer = self.frame.footer

    if wowauditTimestamp then
        footer.left:SetText("Wishlists synced " .. date("%B %d, %H:%M", wowauditTimestamp))
    elseif next(sharedWowauditData) ~= nil then
        footer.left:SetText("Using wishlist data shared by your raid")
    else
        footer.left:SetText(withColor("No wishlist data. Is the desktop client running?", "o"))
    end

    if total == 0 then
        footer.right:SetText("")
    elseif profilesFound == total then
        footer.right:SetText("Crest data from all " .. total .. " candidates")
    else
        footer.right:SetText("Crest data from " .. profilesFound .. "/" .. total ..
                                 " candidates")
    end
end

-- Built with RCLootCouncil's embedded dropdown library so the menus look and behave
-- like the voting frame's own filter menu.
function wowauditEvaluationFrame.FilterMenu(_, level)
    if level ~= 1 then
        return
    end

    local entry = displayLootTable()[currentSession()]
    local typeCode = entry and entry.typeCode or "default"

    local info = MSA_DropDownMenu_CreateInfo()
    info.text = "Show responses"
    info.isTitle = true
    info.notCheckable = true
    info.disabled = true
    MSA_DropDownMenu_AddButton(info, level)

    local function toggle(key)
        settings().wowauditEvaluationFilters[key] = not responseVisible(key)
        wowauditEvaluationFrame:Refresh()
    end

    for index = 1, addon:GetNumButtons(typeCode) do
        info = MSA_DropDownMenu_CreateInfo()
        info.text = addon:GetResponse(typeCode, index).text or ("Response " .. index)
        info.colorCode = "|cff" .. addon.Utils:RGBToHex(addon:GetResponseColor(typeCode, index))
        info.checked = responseVisible(index)
        info.keepShownOnClick = true
        info.func = function()
            toggle(index)
        end
        MSA_DropDownMenu_AddButton(info, level)
    end

    for _, key in ipairs({"PASS", "AUTOPASS", "STATUS"}) do
        info = MSA_DropDownMenu_CreateInfo()
        info.text = key == "STATUS" and "Status texts" or (addon:GetResponse(typeCode, key).text or key)
        info.checked = responseVisible(key)
        info.keepShownOnClick = true
        info.func = function()
            toggle(key)
        end
        MSA_DropDownMenu_AddButton(info, level)
    end
end

function wowauditEvaluationFrame.SortMenu(_, level)
    if level ~= 1 then
        return
    end

    local info = MSA_DropDownMenu_CreateInfo()
    info.text = "Sort by"
    info.isTitle = true
    info.notCheckable = true
    info.disabled = true
    MSA_DropDownMenu_AddButton(info, level)

    for _, key in ipairs(SORT_ORDER) do
        info = MSA_DropDownMenu_CreateInfo()
        info.text = SORT_LABELS[key]
        info.checked = settings().wowauditEvaluationSort == key
        info.func = function()
            settings().wowauditEvaluationSort = key
            wowauditEvaluationFrame:Refresh()
        end
        MSA_DropDownMenu_AddButton(info, level)
    end
end

function wowauditEvaluationFrame.DifficultyMenu(_, level)
    if level ~= 1 then
        return
    end

    local entry = displayLootTable()[currentSession()]
    local native = itemDifficultyFor(entry)
    local selected = wishDifficultyOverride or native

    local info = MSA_DropDownMenu_CreateInfo()
    info.text = "Wish difficulty"
    info.isTitle = true
    info.notCheckable = true
    info.disabled = true
    MSA_DropDownMenu_AddButton(info, level)

    for _, key in ipairs(DIFFICULTY_ORDER) do
        info = MSA_DropDownMenu_CreateInfo()
        info.text = DIFFICULTY_LABELS[key]
        if key == native then
            info.text = info.text .. " (item)"
        end
        info.checked = selected == key
        info.func = function()
            wishDifficultyOverride = key
            wowauditInvalidateSlotWishes()
            wowauditEvaluationFrame:Refresh()
        end
        MSA_DropDownMenu_AddButton(info, level)
    end
end

-- Collapses to just the header band, the same idea as double-clicking the title of
-- RCLootCouncil's own frames.
function wowauditEvaluationFrame:ToggleMinimized()
    local f = self.frame
    local db = addon:Getdb()
    local body = {f.tabs, f.columnHeader, f.scroll, f.scrollTrack, f.footer, f.resizeGrip}

    if f.minimized then
        f.minimized = false
        for _, part in ipairs(body) do
            part:Show()
        end
        f:SetResizable(true)
        setHeightKeepingTop(f, db.UI[FRAME_NAME].height or (chromeHeight() + VISIBLE_ROWS * maxRowStep))
        self:Refresh()
    else
        f.minimized = true
        for _, part in ipairs(body) do
            part:Hide()
        end
        f:SetResizable(false)
        setHeightKeepingTop(f, HEADER_HEIGHT + 2)
    end

    f.header.minimizeButton:SetLabel(f.minimized and "+" or "_")
end

function wowauditEvaluationFrame:ToggleScaleSlider()
    local f = self.frame

    if not f.scalePanel then
        -- Parented to UIParent, not to the window it scales: as a child it would move
        -- out from under the cursor on every step of the drag.
        local panel = Theme:Panel(UIParent, nil)
        panel:SetSize(150, 44)
        panel:SetFrameStrata("FULLSCREEN_DIALOG")
        panel:EnableMouse(true)
        panel:Hide()

        local label = Theme:Label(panel, "Window scale")
        label:SetPoint("TOPLEFT", PADDING, -8)

        local readout = Theme:Value(panel, 11)
        readout:SetPoint("TOPRIGHT", -PADDING, -7)
        readout:SetJustifyH("RIGHT")

        local slider = Theme:Slider(panel, 150 - PADDING * 2, MIN_SCALE, MAX_SCALE, 0.05)
        slider:SetPoint("BOTTOMLEFT", PADDING, 8)
        slider:SetValue(f:GetScale())
        readout:SetText(format("%.2f", f:GetScale()))

        slider:SetScript("OnValueChanged", function(_, value)
            lwin.SetScale(f, value)
            readout:SetText(format("%.2f", value))
        end)

        panel.slider = slider
        f.scalePanel = panel
    end

    local panel = f.scalePanel
    if panel:IsShown() then
        panel:Hide()
        return
    end

    -- Placed once, in UIParent's coordinates, so rescaling the window leaves it be.
    local button = f.header.scaleButton
    local scale = f:GetScale()

    panel:ClearAllPoints()
    panel:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", button:GetRight() * scale, button:GetBottom() * scale - 4)
    panel.slider:SetValue(scale)
    panel:Show()
end
