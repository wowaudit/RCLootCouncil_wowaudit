local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local Comms = addon.Require "Services.Comms"
local Council = addon.Require "Data.Council"
local lwin = LibStub("LibWindow-1.1")
local LibDialog = LibStub("LibDialog-1.1")
local L = LibStub("AceLocale-3.0"):GetLocale("RCLootCouncil")

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
local SCROLLBAR_WIDTH = 12
local REFRESH_DELAY = 0.1
local RESIZE_GRIP = 8
local SUMMARY_LINE_GAP = 4
local SUMMARY_SECTION_GAP = 12
local SUMMARY_PAD_X = 10
local SUMMARY_PAD_Y = 8
local MIN_SCALE, MAX_SCALE = 0.6, 1.6

local function clampScale(scale)
    return math.min(MAX_SCALE, math.max(MIN_SCALE, tonumber(scale) or 1))
end

local SORT_LABELS = {
    response = "Response",
    votes = "Votes",
    rolls = "Rolls",
    bis = "Best in slot",
    value = "Wish value",
    ilvl = "Item level",
    name = "Name"
}

local SORT_ORDER = {"response", "votes", "rolls", "bis", "value", "ilvl", "name"}

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
local filterMenu, sortMenu, difficultyMenu, disenchantMenu
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
    db.wowauditEvaluationFilters.ranks = db.wowauditEvaluationFilters.ranks or {}
    db.wowauditEvaluationSort = db.wowauditEvaluationSort or "response"
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

-- Rank names come from the candidate; GetGuildRanks maps those names to the
-- index the filter menu stores. Missing keys default to shown, like RCLC.
local function rankVisible(rank)
    local ranks = settings().wowauditEvaluationFilters.ranks
    local guildRanks = addon:GetGuildRanks()
    if rank and guildRanks[rank] then
        return ranks[guildRanks[rank]] ~= false
    end
    return ranks.notInYourGuild ~= false
end

local function rankFilterChecked(key)
    return settings().wowauditEvaluationFilters.ranks[key] ~= false
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

-- RCLC writes these IDs onto candidate.response while the player still has the
-- loot frame open. The yellow "please wait" sentence is only GetResponse().text.
local AWAITING_RESPONSES = {
    ANNOUNCED = true,
    WAIT = true,
    NOTANNOUNCED = true
}

local function isAwaitingResponse(key)
    return AWAITING_RESPONSES[key] == true
end

local function classColoredName(name)
    if addon.GetUnitClassColoredName then
        return addon:GetUnitClassColoredName(name)
    end
    return addon.Ambiguate(name)
end

local function joinClassColoredNames(members)
    local parts = {}
    for _, member in ipairs(members) do
        tinsert(parts, classColoredName(member.name))
    end
    return table.concat(parts, ", ")
end

local function cmpHiddenName(a, b)
    return a.name < b.name
end

-- Everyone the response filter hides, split into "still choosing" vs grouped
-- Autopass/Transmog/etc. Rank-only hides are omitted: those are not a hidden response.
local function buildHiddenGroups(entry)
    local typeCode = entry.typeCode
    local grouped = {}
    local awaiting = {}

    for name, candidate in pairs(entry.candidates or {}) do
        if not awardedToCandidate(entry, name) then
            local key = candidateResponse(candidate)
            local member = {
                name = name,
                class = candidate.class
            }
            -- Still-choosing people always belong in the awaiting block, even if
            -- "Status texts" is on. Rank-only hides stay out, same as before.
            if isAwaitingResponse(key) then
                if rankVisible(candidate.rank) then
                    tinsert(awaiting, member)
                end
            elseif not responseVisible(key) then
                grouped[key] = grouped[key] or {}
                tinsert(grouped[key], member)
            end
        end
    end

    table.sort(awaiting, cmpHiddenName)

    local groups = {}
    for key, members in pairs(grouped) do
        table.sort(members, cmpHiddenName)
        local response = addon:GetResponse(typeCode, key)
        tinsert(groups, {
            key = key,
            text = (response and response.text) or tostring(key),
            color = (response and response.color) or {1, 1, 1},
            sort = (response and response.sort) or 999,
            members = members
        })
    end
    table.sort(groups, function(a, b)
        if a.sort ~= b.sort then
            return a.sort < b.sort
        end
        return a.text < b.text
    end)

    return groups, awaiting
end

local function sessionHasRolls(entry)
    if entry.hasRolls then
        return true
    end
    for _, candidate in pairs(entry.candidates or {}) do
        if candidate.roll ~= nil then
            return true
        end
    end
    return false
end

-- Same visibility rules as RCVotingFrame.SetCellVotes: names stay hidden under
-- anonymous voting, and hideVotes blanks the count until this client has voted.
local function canShowVoteNames(entry)
    local mldb = addon.mldb or {}
    local db = addon:Getdb()
    if mldb.anonymousVoting and not (db.showForML and addon.isMasterLooter) then
        return false
    end
    if mldb.hideVotes and not entry.haveVoted and not (mldb.observe and not addon.isCouncil) then
        return false
    end
    return true
end

local function displayedVotes(entry, candidate)
    local mldb = addon.mldb or {}
    if mldb.hideVotes and not entry.haveVoted and addon.isCouncil then
        return 0
    end
    return candidate.votes or 0
end

local function voterMatches(voters, councilName)
    for _, voter in ipairs(voters) do
        if voter == councilName or addon:UnitIsUnit(voter, councilName) then
            return true
        end
    end
    return false
end

local function voteTooltipLines(candidate)
    local voters = candidate.voters or {}
    local lines = {"Voted"}
    if #voters == 0 then
        tinsert(lines, "No votes")
    else
        for _, name in ipairs(voters) do
            tinsert(lines, addon:GetClassIconAndColoredName(name))
        end
    end

    local missingHeader = #lines + 1
    tinsert(lines, "Haven't voted")
    local missing = 0
    for _, player in pairs(Council:Get()) do
        if not voterMatches(voters, player.name) then
            missing = missing + 1
            tinsert(lines, addon:GetClassIconAndColoredName(player.name))
        end
    end
    if missing == 0 then
        tremove(lines, missingHeader)
    end
    return lines
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
        srolls = refresh,
        rrolls = refresh,
        roll = refresh,
        reset_rolls = refresh,
        lootTable = onNewLootTable,
        lt_add = refresh
    })

    self.wowauditSubscriptions = Comms:BulkSubscribe(RCwowaudit.PREFIXES.MAIN, {
        full_data = refresh,
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

-- Same send-and-flip-haveVoted path as RCVotingFrame.SetCellVote. The vote
-- count itself is applied when the comm comes back through HandleVote.
function wowauditEvaluationFrame:Vote(name)
    local session = currentSession()
    local lootTable = displayLootTable()
    local entry = lootTable[session]
    local candidate = entry and entry.candidates and entry.candidates[name]
    if not entry or not candidate or entry.awarded then
        return
    end
    if not (addon.isCouncil or addon.isMasterLooter) then
        return
    end

    local mldb = addon.mldb or {}
    if candidate.haveVoted then
        addon:Send("group", "vote", session, name, -1)
        candidate.haveVoted = false

        local haveVoted = false
        for _, other in pairs(entry.candidates) do
            if other.haveVoted then
                haveVoted = true
                break
            end
        end
        entry.haveVoted = haveVoted
    else
        if not mldb.selfVote and addon:UnitIsUnit("player", name) then
            return addon:Print(L["The Master Looter doesn't allow votes for yourself."])
        end
        if not mldb.multiVote and entry.haveVoted then
            return addon:Print(L["The Master Looter doesn't allow multiple votes."])
        end
        addon:Send("group", "vote", session, name, 1)
        candidate.haveVoted = true
        entry.haveVoted = true
    end

    self:ScheduleRefresh()
end

function wowauditEvaluationFrame:RollForAll()
    local module = votingFrame()
    if not module or not addon.isMasterLooter or not module.DoRandomRolls then
        return
    end
    module:DoRandomRolls(currentSession())
end

function wowauditEvaluationFrame:Show()
    local frame = self:GetFrame()
    self:UpdateEscapeClose()
    if frame.minimized then
        self:ToggleMinimized()
    end
    frame:Show()
    frame:Raise()
    self:Refresh()

    -- Backfill only when this client is missing profiles (opened late and missed
    -- the loot-ack broadcast). Toggling the window is not another raid-wide request.
    local share = RCwowaudit:GetModule("wowauditShareData")
    if self:HasMissingProfiles() then
        share:RequestProfiles()
    end
    -- Freshness check: a source with newer data replies; already-current is a no-op.
    share:RequestDataset()
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

-- In replace mode this window is the voting UI, so X matches the voting frame's
-- Abort/Close: ML with an active session confirms ending it. After abort the
-- loot table still has unawarded items, so we key off ML.running, not that.
function wowauditEvaluationFrame:Close()
    if RCwowaudit:EvaluationVisibility() == "replace" and addon.isMasterLooter then
        local ml = addon:GetActiveModule("masterlooter")
        local module = votingFrame()
        if ml and ml.running and module and module.HasUnawardedItems and module:HasUnawardedItems() then
            LibDialog:Spawn("RCLOOTCOUNCIL_CONFIRM_ABORT")
            return
        end
    end
    self:Hide()
end

-- Voting frame is a critical window and is not in UISpecialFrames. When we
-- replace it, Escape must not close this one either.
function wowauditEvaluationFrame:UpdateEscapeClose()
    if not self.frame then
        return
    end

    local listed
    for index, name in ipairs(UISpecialFrames) do
        if name == FRAME_NAME then
            listed = index
            break
        end
    end

    if RCwowaudit:EvaluationVisibility() == "replace" then
        if listed then
            tremove(UISpecialFrames, listed)
        end
    elseif not listed then
        tinsert(UISpecialFrames, FRAME_NAME)
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
    -- LibWindow may restore an older saved width; the column geometry is fixed.
    f:SetWidth(width)
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
    disenchantMenu = disenchantMenu or MSA_DropDownMenu_Create("RCwowauditEvaluationDisenchantMenu", UIParent)
    MSA_DropDownMenu_Initialize(filterMenu, self.FilterMenu)
    MSA_DropDownMenu_Initialize(sortMenu, self.SortMenu)
    MSA_DropDownMenu_Initialize(difficultyMenu, self.DifficultyMenu)
    MSA_DropDownMenu_Initialize(disenchantMenu, self.DisenchantMenu)

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

    self.frame = f
    self:UpdateEscapeClose()
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

-- GLOBAL_MOUSE_DOWN closes MSA menus before our button sees the click, so Toggle
-- would reopen the same menu. Remember which menu that close hid, skip the
-- reopen, and drop the flag after this mouse-up so a later click can open again.
local closedDropDown
local dropDownCloseHooked

local function rememberClosedDropDown()
    local list = _G.MSA_DropDownList1
    if list and list:IsShown() then
        closedDropDown = MSA_DROPDOWNMENU_OPEN_MENU
    end
end

local function hookDropDownClose()
    if dropDownCloseHooked or not MSA_CloseDropDownMenus then
        return
    end
    dropDownCloseHooked = true

    local orig = MSA_CloseDropDownMenus
    MSA_CloseDropDownMenus = function(...)
        rememberClosedDropDown()
        return orig(...)
    end

    local clearer = CreateFrame("Frame")
    clearer:RegisterEvent("GLOBAL_MOUSE_UP")
    clearer:SetScript("OnEvent", function()
        C_Timer.After(0, function()
            closedDropDown = nil
        end)
    end)
end

local function bindDropDownButton(button, menu)
    hookDropDownClose()
    button:SetScript("OnClick", function(self)
        local closed = closedDropDown
        closedDropDown = nil
        if closed == menu then
            return
        end
        MSA_ToggleDropDownMenu(1, nil, menu, self, 0, 0)
    end)
end

-- Same MSA menu the voting frame attaches to a row right-click. The menu
-- itself is empty unless this client is the master looter.
function wowauditEvaluationFrame:ShowCandidateMenu(name, anchor)
    local menu = _G.RCLootCouncil_VotingFrame_RightclickMenu
    if not menu or not name or not addon.isMasterLooter then
        return
    end

    hookDropDownClose()
    local closed = closedDropDown
    closedDropDown = nil
    if closed == menu and menu.name == name then
        return
    end

    menu.name = name
    MSA_ToggleDropDownMenu(1, nil, menu, anchor, 0, 0)
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
        if header.lastClick and GetTime() - header.lastClick <= 0.5 then
            header.lastClick = nil
            wowauditEvaluationFrame:ToggleMinimized()
        else
            header.lastClick = GetTime()
        end
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
        wowauditEvaluationFrame:Close()
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

    header.filterButton = Theme:Button(header, "Filter", 64, 22)
    header.filterButton:SetPoint("RIGHT", header.scaleButton, "LEFT", -6, 0)
    bindDropDownButton(header.filterButton, filterMenu)

    header.sortButton = Theme:Button(header, "Sort", 110, 22)
    header.sortButton:SetPoint("RIGHT", header.filterButton, "LEFT", -6, 0)
    bindDropDownButton(header.sortButton, sortMenu)

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
    bindDropDownButton(header.difficultyButton, difficultyMenu)

    -- Icon only. The menu is the voting frame's enchanter list, under a Disenchant header.
    header.disenchantButton = Theme:Button(header, "", 22, 22)
    header.disenchantButton:SetPoint("RIGHT", header.difficultyButton, "LEFT", -6, 0)
    header.disenchantButton.text:SetText("")
    header.disenchantButton.icon = Theme:Icon(header.disenchantButton, 16)
    header.disenchantButton.icon:SetPoint("CENTER")
    local disenchantIcon = C_Spell.GetSpellTexture(13262)
    header.disenchantButton.icon:SetTexture((disenchantIcon and disenchantIcon ~= 0) and disenchantIcon or
        "Interface\\Icons\\INV_Enchant_Disenchant")
    bindDropDownButton(header.disenchantButton, disenchantMenu)

    -- Two-line winner readout, parked left of the wishes control so the item
    -- identity on the left and the header buttons on the right stay put.
    local awarded = CreateFrame("Frame", nil, header)
    awarded:SetSize(1, 28)
    awarded:SetPoint("LEFT", header.ilvl, "RIGHT", 16, 0)

    awarded.label = Theme:Value(awarded, 11)
    awarded.label:SetText("Awarded to")
    awarded.label:SetTextColor(0.2, 1, 0.2)
    awarded.label:SetJustifyH("CENTER")
    awarded.label:SetPoint("TOPLEFT")
    awarded.label:SetPoint("TOPRIGHT")

    awarded.player = Theme:Value(awarded, 13, true)
    awarded.player:SetJustifyH("CENTER")
    awarded.player:SetPoint("TOPLEFT", awarded.label, "BOTTOMLEFT", 0, 0)
    awarded.player:SetPoint("TOPRIGHT", awarded.label, "BOTTOMRIGHT", 0, 0)
    awarded:Hide()

    header.awarded = awarded

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
            local help = Theme:WishColorHelp(strip, COLUMN_HEADER_HEIGHT)
            help:SetPoint("LEFT", strip, "LEFT", column.x + column.width - COLUMN_HEADER_HEIGHT, 0)
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
            lwin.SetScale(f, clampScale(f:GetScale() + (delta > 0 and 0.03 or -0.03)))
            return
        end

        local range = math.max(0, child:GetHeight() - self:GetHeight())
        local target = math.min(range, math.max(0, self:GetVerticalScroll() - delta * minRowStep))
        self:SetVerticalScroll(target)
        wowauditEvaluationFrame:UpdateScrollbar()
    end)

    local slider = Theme:ScrollBar(f, SCROLLBAR_WIDTH)
    slider:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
    slider:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
    slider:SetScript("OnValueChanged", function(bar, value)
        if bar.updating then
            return
        end
        scroll:SetVerticalScroll(value)
    end)

    scroll:SetScript("OnVerticalScroll", function(_, offset)
        if slider.updating or slider:GetValue() == offset then
            return
        end
        slider.updating = true
        slider:SetValue(offset)
        slider.updating = false
    end)

    f.scroll = scroll
    f.scrollChild = child
    f.scrollBar = slider

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

    local awaiting = CreateFrame("Frame", nil, child)
    awaiting:SetWidth(Row.WIDTH)
    Theme:Fill(awaiting, "card", "BACKGROUND")
    Theme:Hairline(awaiting, "outline", 0)
    Theme:Hairline(awaiting, "hairline", 1)
    awaiting.text = Theme:Value(awaiting, 12)
    awaiting.text:SetJustifyH("LEFT")
    awaiting.text:SetWordWrap(true)
    awaiting.text:SetPoint("TOPLEFT", SUMMARY_PAD_X, -SUMMARY_PAD_Y)
    awaiting.text:SetPoint("TOPRIGHT", -SUMMARY_PAD_X, -SUMMARY_PAD_Y)
    awaiting:Hide()
    f.awaitingSummary = awaiting

    local hidden = CreateFrame("Frame", nil, child)
    hidden:SetWidth(Row.WIDTH)
    hidden.lines = {}
    hidden:Hide()
    f.hiddenSummary = hidden
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
    local range = math.max(0, f.scrollChild:GetHeight() - f.scroll:GetHeight())

    if range <= 0 then
        f.scroll:SetVerticalScroll(0)
        f.scrollBar.updating = true
        f.scrollBar:SetMinMaxValues(0, 0)
        f.scrollBar.updating = false
        f.scrollBar:Hide()
        return
    end

    if f.scroll:GetVerticalScroll() > range then
        f.scroll:SetVerticalScroll(range)
    end

    f.scrollBar:Show()
    f.scrollBar.updating = true
    f.scrollBar:SetMinMaxValues(0, range)
    f.scrollBar:SetValue(f.scroll:GetVerticalScroll())
    f.scrollBar.updating = false
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

    local rows = {}
    local best = 0
    local profilesFound = 0
    local hasRolls = sessionHasRolls(entry)
    local canVote = addon.isCouncil or addon.isMasterLooter
    local canRoll = addon.isMasterLooter
    local showVoteNames = canShowVoteNames(entry)

    for name, candidate in pairs(entry.candidates or {}) do
        local responseKey = candidateResponse(candidate)
        if not isAwaitingResponse(responseKey) and (awardedToCandidate(entry, name) or
            (responseVisible(responseKey) and rankVisible(candidate.rank))) then
            local response = addon:GetResponse(typeCode, responseKey)
            local wishes = wowauditDataToDisplay(entry.itemID, entry.string, name, difficulty)
            local profile = wowauditProfileForCharacter(name)
            local value = highestWishValue(wishes)
            local sameSlot = wowauditSameSlotWishes(name, entry.itemID, difficulty)
            local bonusLoot = wowauditBonusLootFor(name, entry.itemID)

            requestIfUncached(candidate.gear1)
            requestIfUncached(candidate.gear2)
            requestIfUncached(entry.link or entry.string)
            requestIfUncached(bonusLoot and bonusLoot.itemID)
            for _, alternative in ipairs(sameSlot) do
                requestIfUncached(alternative.id)
            end
            requestTrackItems(profile, itemTrack and itemTrack.track)
            for _, gear in ipairs({candidate.gear1, candidate.gear2}) do
                local equippedTrack = gear and wowauditTrackForItem(gear, true)
                local crafted = not equippedTrack and gear and wowauditCraftedInfoForItem(gear)
                requestTrackItems(profile, equippedTrack and equippedTrack.track or
                    (crafted and crafted.track))
            end

            if profile then
                profilesFound = profilesFound + 1
            end
            if value > best then
                best = value
            end

            local priority = trinketPriorityToDisplay(entry.itemID, name)

            local slotWishes = {}
            local emptySlotMessage = wowauditEmptySlotMessage(name, wishes, sameSlot, entry.itemID,
                itemTrack, {candidate.gear1, candidate.gear2})
            if not emptySlotMessage then
                slotWishes = wowauditRankedSlotWishes(entry, sameSlot, wishes, value, priority,
                    Row.MAX_WISHES_IN_SLOT)
            end
            local droppedRank = 999
            for _, wish in ipairs(slotWishes) do
                if wish.isDropped then
                    droppedRank = wish.rank or 999
                    break
                end
            end

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
                votes = displayedVotes(entry, candidate),
                haveVoted = candidate.haveVoted,
                voteTooltip = showVoteNames and voteTooltipLines(candidate) or nil,
                hasRolls = hasRolls,
                canVote = canVote,
                canRoll = canRoll,
                rank = candidate.rank,
                ilvl = candidate.ilvl,
                gear1 = candidate.gear1,
                gear2 = candidate.gear2,
                wishes = wishes,
                wishValue = value,
                droppedRank = droppedRank,
                itemTrack = itemTrack,
                priority = priority,
                bonusRollTarget = wowauditBonusRollTargetForItem(entry.itemID, name),
                bonusRollIcon = bonusRollIcon,
                bonusLoot = bonusLoot,
                slotWishes = slotWishes,
                emptySlotMessage = emptySlotMessage,
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

local function cmpName(a, b)
    if a.name ~= b.name then
        return a.name < b.name
    end
end

local function cmpValue(a, b)
    if a.wishValue ~= b.wishValue then
        return a.wishValue > b.wishValue
    end
end

local function cmpBis(a, b)
    local aRank, bRank = a.droppedRank or 999, b.droppedRank or 999
    if aRank ~= bRank then
        return aRank < bRank
    end
end

local function cmpResponse(a, b)
    if a.responseSort ~= b.responseSort then
        return a.responseSort < b.responseSort
    end
end

local function cmpIlvl(a, b)
    local aIlvl, bIlvl = tonumber(a.ilvl) or 0, tonumber(b.ilvl) or 0
    if aIlvl ~= bIlvl then
        return aIlvl > bIlvl
    end
end

local function cmpVotes(a, b)
    local aVotes, bVotes = tonumber(a.votes) or 0, tonumber(b.votes) or 0
    if aVotes ~= bVotes then
        return aVotes > bVotes
    end
end

local function cmpRoll(a, b)
    local aRoll, bRoll = tonumber(a.roll), tonumber(b.roll)
    if aRoll ~= bRoll then
        if not aRoll then
            return false
        end
        if not bRoll then
            return true
        end
        return aRoll > bRoll
    end
end

local sortChains = {
    response = {cmpResponse, cmpBis, cmpValue, cmpName},
    votes = {cmpVotes, cmpResponse, cmpName},
    rolls = {cmpRoll, cmpResponse, cmpName},
    bis = {cmpBis, cmpValue, cmpResponse, cmpName},
    value = {cmpValue, cmpResponse, cmpName},
    ilvl = {cmpIlvl, cmpResponse, cmpName},
    name = {cmpName}
}

local function acquireHiddenLine(summary, index)
    local line = summary.lines[index]
    if not line then
        line = Theme:Value(summary, 12)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(true)
        line:SetWidth(Row.WIDTH)
        summary.lines[index] = line
    end
    return line
end

local function layoutAwaitingSummary(frame, awaiting)
    if #awaiting == 0 then
        frame:Hide()
        return 0
    end

    frame.text:SetText("Awaiting response: " .. joinClassColoredNames(awaiting))
    frame:Show()
    local height = math.max(frame.text:GetStringHeight(), 1) + SUMMARY_PAD_Y * 2
    frame:SetHeight(height)
    return height
end

local function layoutHiddenSummary(frame, groups)
    if #groups == 0 then
        frame:Hide()
        return 0
    end

    frame:Show()
    local offset = 0
    for index, group in ipairs(groups) do
        local line = acquireHiddenLine(frame, index)
        local r, g, b = group.color[1] or 1, group.color[2] or 1, group.color[3] or 1
        local hex = addon.Utils:RGBToHex(r, g, b)
        line:SetText("|cff" .. hex .. group.text .. ":|r " .. joinClassColoredNames(group.members))
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", 0, -offset)
        line:SetPoint("TOPRIGHT", 0, -offset)
        line:Show()
        offset = offset + math.max(line:GetStringHeight(), 1) + SUMMARY_LINE_GAP
    end

    for index = #groups + 1, #frame.lines do
        frame.lines[index]:Hide()
    end

    if offset > 0 then
        offset = offset - SUMMARY_LINE_GAP
    end
    frame:SetHeight(math.max(offset, 1))
    frame:Show()
    return offset
end

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
        f.awaitingSummary:Hide()
        f.hiddenSummary:Hide()
        f.scrollChild:SetHeight(1)
        f.emptyText:SetText("No loot session is running.")
        f.emptyText:Show()
        self:RefreshFooter(0, 0)
        self:UpdateScrollbar()
        return
    end

    local rows, profilesFound = self:BuildRowData(entry, session)
    local groups, awaiting = buildHiddenGroups(entry)

    local chain = sortChains[settings().wowauditEvaluationSort] or sortChains.response

    table.sort(rows, function(a, b)
        for _, compare in ipairs(chain) do
            local ordered = compare(a, b)
            if ordered ~= nil then
                return ordered
            end
        end
        return a.name < b.name
    end)

    local offset = 0
    local awaitingHeight = layoutAwaitingSummary(f.awaitingSummary, awaiting)
    if awaitingHeight > 0 then
        f.awaitingSummary:SetPoint("TOPLEFT", f.scrollChild, "TOPLEFT", 0, 0)
        offset = awaitingHeight + Row.SPACING
    end

    for index, data in ipairs(rows) do
        local row = f.rowPool:Acquire()
        row:SetPoint("TOPLEFT", f.scrollChild, "TOPLEFT", 0, -offset)
        Row:SetData(row, data, index)
        row:Show()
        offset = offset + row:GetHeight() + Row.SPACING
    end
    if #rows > 0 then
        offset = offset - Row.SPACING
    end

    local hiddenHeight = layoutHiddenSummary(f.hiddenSummary, groups)
    if hiddenHeight > 0 then
        if offset > 0 then
            offset = offset + SUMMARY_SECTION_GAP
        end
        f.hiddenSummary:SetPoint("TOPLEFT", f.scrollChild, "TOPLEFT", 0, -offset)
        offset = offset + hiddenHeight
    end

    f.scrollChild:SetHeight(math.max(1, offset))

    if #rows == 0 and awaitingHeight == 0 and hiddenHeight == 0 then
        f.emptyText:SetText("No candidates match the response filter.")
        f.emptyText:Show()
    else
        f.emptyText:Hide()
    end

    self:RefreshFooter(profilesFound, #rows)
    self:UpdateScrollbar()
end

local function candidateClass(entry, awarded)
    local candidate = entry.candidates and entry.candidates[awarded]
    if candidate then
        return candidate.class
    end
    for name, other in pairs(entry.candidates or {}) do
        if addon:UnitIsUnit(name, awarded) or name == awarded then
            return other.class
        end
    end
end

function wowauditEvaluationFrame:RefreshAwardedTo(header, entry)
    local awarded = header.awarded
    local winner = entry and type(entry.awarded) == "string" and entry.awarded
    if not winner then
        awarded:Hide()
        header.bonuses:SetPoint("LEFT", header.ilvl, "RIGHT", 8, 0)
        return
    end

    awarded.player:SetText(addon.Ambiguate(winner))
    local class = candidateClass(entry, winner)
    local color = class and (addon.GetClassColor and addon:GetClassColor(class) or RAID_CLASS_COLORS[class])
    if color then
        awarded.player:SetTextColor(color.r, color.g, color.b)
    else
        awarded.player:SetTextColor(Theme:Color("value"))
    end

    awarded:SetWidth(math.max(awarded.label:GetStringWidth(), awarded.player:GetStringWidth(), 1))
    awarded:Show()
    header.bonuses:SetPoint("LEFT", awarded, "RIGHT", 8, 0)
end

function wowauditEvaluationFrame:RefreshHeader(entry)
    local header = self.frame.header
    local crestsLabel = self.frame.columnHeader.labels.crests

    header.valueButton:SetLabel(wowauditValueDisplay == "VALUE" and "Show %" or "Show value")
    header.sortButton:SetLabel("Sort: " .. (SORT_LABELS[settings().wowauditEvaluationSort] or "Response"))
    local _, nativeDifficulty = wishLookupDifficulty(entry)
    local shownDifficulty = wishDifficultyOverride or nativeDifficulty
    header.difficultyButton:SetLabel("Wishes: " .. (DIFFICULTY_LABELS[shownDifficulty] or "Auto"))
    -- The voting frame only offers Disenchant to the master looter.
    if addon.isMasterLooter then
        header.disenchantButton:Show()
    else
        header.disenchantButton:Hide()
    end
    self:RefreshAwardedTo(header, entry)

    local track = entry and (wowauditTrackForItem(entry.link) or wowauditTrackForItem(entry.string))
    crestsLabel:SetText(strupper(track and (track.track .. " crests left") or "Crests"))

    if not entry then
        header.itemLink = nil
        header.itemIcon:Hide()
        header.itemName:SetText("Loot evaluation")
        header.itemName:SetTextColor(Theme:Color("value"))
        header.track:Hide()
        header.track:SetWidth(0.01)
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
    else
        header.track:Hide()
        header.track:SetWidth(0.01)
    end

    local ilvl = C_Item.GetDetailedItemLevelInfo(entry.link or entry.string) or entry.ilvl
    header.ilvl:SetText(ilvl and tostring(ilvl) or "")

    local item = entry.link or entry.string
    local bonuses = item and addon:GetItemBonusText(item, "/") or ""
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
        local ageDays = wowauditWishlistAgeWarning and wowauditWishlistAgeWarning()
        local synced = "Wishlists synced " .. date("%B %d, %H:%M", wowauditTimestamp)
        if ageDays then
            footer.left:SetText(withColor(synced .. " (" .. ageDays .. " days old)", "o"))
        else
            footer.left:SetText(synced)
        end
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
    if level == 1 then
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
            local response = addon:GetResponse(typeCode, index)
            info = MSA_DropDownMenu_CreateInfo()
            info.text = (response and response.text) or ("Response " .. index)
            if response then
                info.colorCode = "|cff" .. addon.Utils:RGBToHex(addon:GetResponseColor(typeCode, index))
            end
            info.checked = responseVisible(index)
            info.keepShownOnClick = true
            info.func = function()
                toggle(index)
            end
            MSA_DropDownMenu_AddButton(info, level)
        end

        for _, key in ipairs({"PASS", "AUTOPASS", "STATUS"}) do
            local response = key ~= "STATUS" and addon:GetResponse(typeCode, key)
            info = MSA_DropDownMenu_CreateInfo()
            info.text = key == "STATUS" and "Status texts" or ((response and response.text) or key)
            info.checked = responseVisible(key)
            info.keepShownOnClick = true
            info.func = function()
                toggle(key)
            end
            MSA_DropDownMenu_AddButton(info, level)
        end

        info = MSA_DropDownMenu_CreateInfo()
        info.text = _G.RANK
        info.isTitle = true
        info.notCheckable = true
        info.disabled = true
        MSA_DropDownMenu_AddButton(info, level)

        info = MSA_DropDownMenu_CreateInfo()
        info.text = _G.RANK .. "..."
        info.notCheckable = true
        info.hasArrow = true
        info.value = "FILTER_RANK"
        MSA_DropDownMenu_AddButton(info, level)
    elseif level == 2 then
        if _G.MSA_DROPDOWNMENU_MENU_VALUE == "FILTER_RANK" then
            local info = MSA_DropDownMenu_CreateInfo()

            if IsInGuild() then
                for k = 1, GuildControlGetNumRanks() do
                    info = MSA_DropDownMenu_CreateInfo()
                    info.text = GuildControlGetRankName(k)
                    info.checked = rankFilterChecked(k)
                    info.keepShownOnClick = true
                    info.func = function()
                        settings().wowauditEvaluationFilters.ranks[k] = not rankFilterChecked(k)
                        wowauditEvaluationFrame:Refresh()
                    end
                    MSA_DropDownMenu_AddButton(info, level)
                end
            end

            info = MSA_DropDownMenu_CreateInfo()
            info.text = L["Not in your guild"]
            info.checked = rankFilterChecked("notInYourGuild")
            info.keepShownOnClick = true
            info.func = function()
                settings().wowauditEvaluationFilters.ranks.notInYourGuild =
                    not rankFilterChecked("notInYourGuild")
                wowauditEvaluationFrame:Refresh()
            end
            MSA_DropDownMenu_AddButton(info, level)
        end
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

-- Enchanter entries come from the voting frame. This only adds the category title.
function wowauditEvaluationFrame.DisenchantMenu(menu, level)
    if level == 1 then
        local info = MSA_DropDownMenu_CreateInfo()
        info.text = "Disenchant"
        info.isTitle = true
        info.notCheckable = true
        info.disabled = true
        MSA_DropDownMenu_AddButton(info, level)
    end

    local module = votingFrame()
    if module and module.EnchantersMenu then
        module.EnchantersMenu(menu, level)
    end
end

-- Collapses to just the header band, the same idea as double-clicking the title of
-- RCLootCouncil's own frames.
function wowauditEvaluationFrame:ToggleMinimized()
    local f = self.frame
    local db = addon:Getdb()
    local body = {f.tabs, f.columnHeader, f.scroll, f.scrollBar, f.footer, f.resizeGrip}

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
            lwin.SetScale(f, clampScale(value))
            readout:SetText(format("%.2f", clampScale(value)))
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
    local scale = clampScale(f:GetScale())
    local right, bottom = button:GetRight(), button:GetBottom()

    panel:ClearAllPoints()
    if right and bottom then
        panel:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right * scale, bottom * scale - 4)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER")
    end
    panel.slider:SetValue(scale)
    panel:Show()
end
