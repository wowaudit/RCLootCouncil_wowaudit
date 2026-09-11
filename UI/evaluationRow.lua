local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
local Theme = wowauditTheme
local RCwowaudit = addon:GetModule("RCwowaudit")

-- One candidate per card. Every element sits at a fixed x offset shared by all
-- rows, which is what makes the window scannable top to bottom.
wowauditEvaluationRow = {}
local Row = wowauditEvaluationRow

local LINE_HEIGHT = 16
local TOP_PADDING = 6
local ITEM_ICON_SIZE = 16

Row.MIN_LINES = 2
Row.MAX_WISHES_IN_SLOT = 5
Row.SPACING = 4

function Row.HeightFor(lines)
    lines = math.max(Row.MIN_LINES, math.min(tonumber(lines) or Row.MIN_LINES, Row.MAX_WISHES_IN_SLOT))
    return TOP_PADDING * 2 + lines * LINE_HEIGHT
end

Row.HEIGHT = Row.HeightFor(Row.MAX_WISHES_IN_SLOT)
Row.MIN_HEIGHT = Row.HeightFor(Row.MIN_LINES)

-- Column geometry, also used by the window to draw its header labels once.
Row.columns = {
    {key = "player", label = "Player", x = 12, width = 200},
    {key = "equipped", label = "Equipped", x = 224, width = 200},
    {key = "wishes", label = "Wishes in this slot", x = 444, width = 250},
    {key = "crests", label = "Crests left", x = 706, width = 132},
    {key = "bonusRoll", label = "Bonus roll", x = 850, width = 130},
    {key = "award", label = "Award", x = 992, width = 80}
}

Row.WIDTH = 1084

local MAX_SPEC_WISHES_SHOWN = 3
local MAX_EQUIPPED_SHOWN = 2
local HOVER_ALPHA = 0.06
local NOTE_ICON = "Interface/BUTTONS/UI-GuildButton-PublicNote-Up.png"
local NOTE_SIZE = 14

local function lineY(index)
    return -(TOP_PADDING + (index - 1) * LINE_HEIGHT)
end

local function columnX(key)
    for _, column in ipairs(Row.columns) do
        if column.key == key then
            return column.x, column.width
        end
    end
end

local function classColor(class)
    local color = class and RAID_CLASS_COLORS[class]
    if not color then
        return Theme:Color("value")
    end
    return color.r, color.g, color.b, 1
end

-- Child frames with their own tooltip steal mouse focus from the row, which would
-- drop the row highlight. Keeping it lit while the cursor is still inside the row.
local function keepRowLit(row, child)
    child:HookScript("OnEnter", function()
        row.hover:SetAlpha(HOVER_ALPHA)
    end)
    child:HookScript("OnLeave", function()
        row.hover:SetAlpha(row:IsMouseOver() and HOVER_ALPHA or 0)
    end)
end

-- Same parchment icon RCLootCouncil uses in the voting frame. Hidden and collapsed
-- when empty so neighbours can sit flush against whatever they were anchored to.
local function createNoteIcon(parent, row)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(NOTE_SIZE, NOTE_SIZE)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexture(NOTE_ICON)
    Theme:AttachTooltip(button)
    keepRowLit(row, button)

    function button:SetNote(title, ...)
        if not title or select("#", ...) == 0 then
            self:SetWidth(0.01)
            self:SetTooltip()
            self:Hide()
            return
        end
        self:SetWidth(NOTE_SIZE)
        self:SetTooltip(title, ...)
        self:Show()
    end

    button:Hide()
    return button
end

local function wishCommentLines(wishes)
    local lines = {}
    for _, wish in ipairs(wishes or {}) do
        wish = transformWish(wish)
        if wish.comment and wish.comment ~= "" then
            tinsert(lines, specIcon(wish.spec, 12) .. " " .. wish.comment)
        end
    end
    return lines
end

local function specWishesText(wishes)
    if not wishes or #wishes == 0 then
        return nil
    end

    local parts = {}
    for index, wish in ipairs(wishes) do
        if index > MAX_SPEC_WISHES_SHOWN then
            tinsert(parts, "|cff6b6f7a+" .. (#wishes - MAX_SPEC_WISHES_SHOWN) .. "|r")
            break
        end
        tinsert(parts, displayWish(wish))
    end

    return table.concat(parts, "  ")
end

-- Icons plus 1/6 labels for every equipped piece on the dropped item's track.
-- Texture escapes keep this in RCLootCouncil's text tooltip instead of a second frame.
local function trackItemsTooltipLine(items)
    if type(items) ~= "table" or #items == 0 then
        return nil
    end

    local parts = {}
    for _, item in ipairs(items) do
        local id, step, total = item[1], item[2], item[3]
        if id and step and total then
            local icon = C_Item.GetItemIconByID(id) or 134400
            tinsert(parts, "|T" .. icon .. ":14:14:0:0:64:64:4:60:4:60|t " .. step .. "/" .. total)
        end
    end

    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "  ")
end

local function trackStepTotals(equipped)
    if not equipped then
        return 0, 0
    end

    local current, possible = 0, 0
    if type(equipped.i) == "table" then
        for _, item in ipairs(equipped.i) do
            current = current + (item[2] or 0)
            possible = possible + (item[3] or 0)
        end
        return current, possible
    end

    -- Older profiles only sent aggregates. An item at 1/6 has had 0 upgrades, so
    -- the current step is upgrades applied plus one per piece.
    current = (equipped.d or 0) + (equipped.c or 0)
    return current, current + (equipped.s or 0)
end

-- "N items on this track. M upgrade steps left." plus the icon/step line the
-- crests column already uses. Nil extra lines when there's nothing to say.
local function trackUpgradesTooltipLines(equipped)
    local current, possible = trackStepTotals(equipped)
    local items = equipped and equipped.i
    local count = type(items) == "table" and #items or (equipped and equipped.c or 0)
    if possible <= 0 or count <= 0 then
        return current, possible, nil
    end

    local left = math.max(0, possible - current)
    local lines = {
        count .. (count == 1 and " item on this track" or " items on this track") ..
            ". " .. left .. (left == 1 and " upgrade step left." or " upgrade steps left.")
    }
    local itemsLine = trackItemsTooltipLine(items)
    if itemsLine then
        tinsert(lines, itemsLine)
    end
    return current, possible, lines
end

-- Crests held for a track that the crests column is not already showing. The
-- column is always the dropped item's track, so equipped badges only need this
-- when they sit on a different one.
local function otherTrackCrestsTooltip(trackName, profile, crestIcon)
    if not trackName or not profile then
        return nil
    end

    local lines = {trackName .. " crests"}
    local hasBody = false

    local crest = profile.cr and profile.cr[trackName]
    if crest then
        hasBody = true
        local held = tostring(crest.q or 0)
        if crestIcon then
            held = "|T" .. crestIcon .. ":14:14:0:0:64:64:4:60:4:60|t " .. held
        end
        if crest.e then
            tinsert(lines, held .. " crests, +" .. crest.e .. " to earn")
        else
            tinsert(lines, held .. " crests")
        end
    end

    local equipped = profile.eq and profile.eq[trackName]
    local current, possible = trackStepTotals(equipped)
    if possible > 0 then
        hasBody = true
        tinsert(lines, current .. " |cff6b6f7a/|r " .. possible .. " upgraded")
        local itemsLine = trackItemsTooltipLine(equipped and equipped.i)
        if itemsLine then
            tinsert(lines, itemsLine)
        end
    end

    if not hasBody then
        return nil
    end
    return lines
end

local function layoutEquippedLine(line, stacked)
    line.chip:ClearAllPoints()
    line.ilvl:ClearAllPoints()
    line.track:ClearAllPoints()

    if stacked then
        line:SetHeight(LINE_HEIGHT * 2)
        line.chip:SetPoint("TOPLEFT")
        line.chip:SetPoint("TOPRIGHT")
        line.track:SetPoint("TOPLEFT", line.chip, "BOTTOMLEFT")
        line.ilvl:SetJustifyH("LEFT")
        line.ilvl:SetPoint("LEFT", line.track, "RIGHT", 6, 0)
    else
        line:SetHeight(LINE_HEIGHT)
        line.ilvl:SetPoint("RIGHT", -10, 0)
        line.ilvl:SetWidth(26)
        line.ilvl:SetJustifyH("RIGHT")
        line.track:SetPoint("RIGHT", line.ilvl, "LEFT", -6, 0)
        line.chip:SetPoint("LEFT")
        line.chip:SetPoint("RIGHT", line.track, "LEFT", -4, 0)
    end
end

local function setEquippedTrackTooltip(line, trackName, data)
    local dropped = data.itemTrack and data.itemTrack.track
    if not trackName or trackName == dropped then
        line.track:SetTooltip()
        return
    end

    local lines = otherTrackCrestsTooltip(trackName, data.profile,
        data.crestIcons and data.crestIcons[trackName])
    if lines then
        line.track:SetTooltip(unpack(lines))
    else
        line.track:SetTooltip()
    end
end

local function setEquippedTrack(line, item, data)
    local track = wowauditTrackForItem(item, true)
    if track then
        line.track:Set(wowauditTrackLabel(track), wowauditTrackColor(track.track))
        setEquippedTrackTooltip(line, track.track, data)
        return
    end

    local crafted = wowauditCraftedInfoForItem(item)
    if crafted then
        line.track:Set("Crafted", wowauditTrackColor(crafted.track))
        setEquippedTrackTooltip(line, crafted.track, data)
        return
    end

    line.track:Hide()
    line.track:SetWidth(0.01)
    line.track:SetTooltip()
end

function Row:Create(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(Row.WIDTH, Row.HEIGHT)
    row:EnableMouse(true)
    row:SetClipsChildren(true)

    row.bg = Theme:Solid(row, "BACKGROUND")
    row.bg:SetAllPoints()

    -- The tint strength lives in the alpha we set here, not in the vertex colour:
    -- fading a texture's own alpha towards 1 would wash the row out to pure white.
    row.hover = Theme:Solid(row, "BACKGROUND", 1)
    row.hover:SetAllPoints()
    row.hover:SetVertexColor(1, 1, 1, 1)
    row.hover:SetAlpha(0)

    -- Class accent bar plus a gradient bleeding in from it.
    row.accent = Theme:Solid(row, "ARTWORK")
    row.accent:SetWidth(3)
    row.accent:SetPoint("TOPLEFT")
    row.accent:SetPoint("BOTTOMLEFT")

    row.accentGlow = Theme:Solid(row, "BACKGROUND", 2)
    row.accentGlow:SetWidth(120)
    row.accentGlow:SetPoint("TOPLEFT", row.accent, "TOPRIGHT")
    row.accentGlow:SetPoint("BOTTOMLEFT", row.accent, "BOTTOMRIGHT")

    row:SetScript("OnEnter", function(self)
        self.hover:SetAlpha(HOVER_ALPHA)
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:SetAlpha(0)
    end)

    self:BuildPlayerBlock(row)
    self:BuildEquippedBlock(row)
    self:BuildWishesBlock(row)
    self:BuildCrestsBlock(row)
    self:BuildBonusRollBlock(row)
    self:BuildAwardBlock(row)

    return row
end

function Row:BuildPlayerBlock(row)
    local x, width = columnX("player")

    row.classIcon = Theme:Icon(row, 18)
    row.classIcon:SetTexCoord(0, 1, 0, 1)
    row.classIcon:SetPoint("TOPLEFT", x, lineY(1))

    row.characterIlvl = Theme:Value(row, 13)
    row.characterIlvl:SetPoint("TOPRIGHT", row, "TOPLEFT", x + width, lineY(1) - 2)
    row.characterIlvl:SetJustifyH("RIGHT")
    row.characterIlvl:SetTextColor(Theme:Color("dim"))

    row.name = Theme:Value(row, 13)
    row.name:SetPoint("TOPLEFT", row.classIcon, "TOPRIGHT", 6, -2)
    row.name:SetPoint("RIGHT", row.characterIlvl, "LEFT", -6, 0)
    row.name:SetWordWrap(false)

    row.specIcon = Theme:Icon(row, 14)
    row.specIcon:SetPoint("TOPLEFT", x, lineY(2) - 1)

    -- Clip the badge and note to this column so a long response cannot spill
    -- into Equipped. Spec icon stays outside so it never gets cropped.
    local responseLine = CreateFrame("Frame", nil, row)
    responseLine:SetHeight(LINE_HEIGHT)
    responseLine:SetPoint("TOPLEFT", row.specIcon, "TOPRIGHT", 5, 1)
    responseLine:SetPoint("TOPRIGHT", row, "TOPLEFT", x + width, lineY(2))
    responseLine:SetClipsChildren(true)
    row.responseLine = responseLine

    row.coins = Theme:IconText(responseLine, 13)
    row.coins:SetPoint("RIGHT")
    Theme:AttachTooltip(row.coins)
    keepRowLit(row, row.coins)

    row.catalyst = Theme:IconText(responseLine, 13)
    row.catalyst:SetPoint("RIGHT", row.coins, "LEFT", -8, 0)
    Theme:AttachTooltip(row.catalyst)
    keepRowLit(row, row.catalyst)

    row.responsePill = Theme:Pill(responseLine)
    row.responsePill:SetPoint("LEFT")

    row.noteButton = createNoteIcon(responseLine, row)
    row.noteButton:SetPoint("LEFT", row.responsePill, "RIGHT", 4, 0)
end

-- Trinkets and rings mean two equipped items compete with the drop, and
-- RCLootCouncil sends both. A single item uses both lines: name on the first,
-- track then ilvl on the second.
function Row:BuildEquippedBlock(row)
    local x, width = columnX("equipped")

    row.equipped = {}
    for index = 1, MAX_EQUIPPED_SHOWN do
        local line = CreateFrame("Frame", nil, row)
        line:SetSize(width, LINE_HEIGHT)
        line:SetPoint("TOPLEFT", x, lineY(index))

        line.ilvl = Theme:Value(line, 12)
        line.ilvl:SetPoint("RIGHT", -10, 0)
        line.ilvl:SetWidth(26)
        line.ilvl:SetJustifyH("RIGHT")

        line.track = Theme:Pill(line)
        line.track:SetPoint("RIGHT", line.ilvl, "LEFT", -6, 0)
        Theme:AttachTooltip(line.track)
        keepRowLit(row, line.track)

        line.chip = Theme:ItemChip(line, width, 16)
        line.chip:SetPoint("LEFT")
        line.chip:SetPoint("RIGHT", line.track, "LEFT", -4, 0)

        row.equipped[index] = line
    end
end

-- The dropped item and every other item this character wants in the same slot, in
-- one ranked list. The dropped item is always present, even with no wishes.
function Row:BuildWishesBlock(row)
    local x, width = columnX("wishes")

    row.wishes = {}
    for index = 1, Row.MAX_WISHES_IN_SLOT do
        local line = CreateFrame("Frame", nil, row)
        line:SetSize(width, LINE_HEIGHT)
        line:SetPoint("TOPLEFT", x, lineY(index))

        line.rank = Theme:Value(line, 11)
        line.rank:SetPoint("LEFT")
        line.rank:SetWidth(16)
        line.rank:SetJustifyH("LEFT")
        line.rank:SetTextColor(Theme:Color("dim"))

        -- Spec percents are sized to their text and pinned right so they never
        -- clip. The item name is the one that yields space.
        line.value = Theme:Value(line, 12)
        line.value:SetPoint("RIGHT")
        line.value:SetJustifyH("RIGHT")
        line.value:SetWordWrap(false)

        line.note = createNoteIcon(line, row)
        line.note:SetPoint("RIGHT", line.value, "LEFT", -3, 0)

        line.chip = Theme:ItemChip(line, width, 14)
        line.chip:SetPoint("LEFT", line.rank, "RIGHT", 2, 0)
        line.chip:SetPoint("RIGHT", line.note, "LEFT", -4, 0)

        row.wishes[index] = line
    end
end

-- Crests for the dropped item's track only. Line 1 is held + still earnable;
-- line 2 is upgrade progress on that track, which owns the item tooltip.
function Row:BuildCrestsBlock(row)
    local x, width = columnX("crests")

    local block = CreateFrame("Frame", nil, row)
    block:SetSize(width, LINE_HEIGHT * 2)
    block:SetPoint("TOPLEFT", x, lineY(1))

    block.icon = Theme:Icon(block, ITEM_ICON_SIZE)
    block.icon:SetPoint("TOPLEFT", 0, 0)

    block.held = Theme:Value(block, 12)
    block.held:SetPoint("LEFT", block.icon, "RIGHT", 4, 0)

    block.earnable = Theme:Value(block, 11)
    block.earnable:SetTextColor(Theme:Color("dim"))
    block.earnable:SetPoint("LEFT", block.held, "RIGHT", 4, 0)

    block.upgrades = CreateFrame("Frame", nil, block)
    block.upgrades:SetSize(width, LINE_HEIGHT)
    block.upgrades:SetPoint("TOPLEFT", 0, -LINE_HEIGHT)
    Theme:AttachTooltip(block.upgrades)
    keepRowLit(row, block.upgrades)

    block.upgrades.text = Theme:Value(block.upgrades, 11)
    block.upgrades.text:SetPoint("LEFT")
    block.upgrades.text:SetPoint("RIGHT")
    block.upgrades.text:SetJustifyH("LEFT")
    block.upgrades.text:SetWordWrap(false)

    -- Shown when the candidate has no shared profile: they can't tell us their crests
    -- because they don't run this addon. Wrapped so the sentence fits the column.
    block.missing = Theme:Value(block, 11)
    block.missing:SetTextColor(Theme:Color("dim"))
    block.missing:SetPoint("TOPLEFT")
    block.missing:SetWidth(width)
    block.missing:SetJustifyH("LEFT")
    block.missing:SetWordWrap(true)
    block.missing:Hide()

    row.crest = block
end

-- What the player actually got out of their bonus roll on this encounter, which is
-- the follow-up question to the dice marker in the wishes column.
function Row:BuildBonusRollBlock(row)
    local x, width = columnX("bonusRoll")

    row.bonusLootChip = Theme:ItemChip(row, width, 16)
    row.bonusLootChip:SetPoint("TOPLEFT", x, lineY(1))

    row.bonusLootStatus = Theme:Value(row, 11)
    row.bonusLootStatus:SetTextColor(Theme:Color("dim"))
    row.bonusLootStatus:SetPoint("TOPLEFT", x, lineY(2))
    row.bonusLootStatus:SetWidth(width)
    row.bonusLootStatus:SetWordWrap(false)
end

-- Same confirm dialog as the voting frame's right-click Award. The winner
-- keeps a badge; everyone else can still award, which is how RCLC changes it.
function Row:BuildAwardBlock(row)
    local x, width = columnX("award")

    row.awardButton = Theme:Button(row, "Award", width - 8, 16)
    row.awardButton:SetPoint("TOPLEFT", x, lineY(1))
    keepRowLit(row, row.awardButton)
    row.awardButton:SetScript("OnClick", function()
        local name = row.data and row.data.name
        local eval = name and RCwowaudit:GetModule("wowauditEvaluationFrame", true)
        if eval then
            eval:Award(name)
        end
    end)

    row.awardedPill = Theme:Pill(row, 16)
    row.awardedPill:SetPoint("TOPLEFT", x, lineY(1))
end

function Row:SetData(row, data, index)
    row.data = data
    row.lines = math.max(Row.MIN_LINES, #(data.slotWishes or {}))
    row:SetHeight(Row.HeightFor(row.lines))

    row.bg:SetVertexColor(Theme:Color(index % 2 == 0 and "cardAlt" or "card"))

    local r, g, b = classColor(data.class)
    row.accent:SetVertexColor(r, g, b, 0.9)
    row.accentGlow:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.10), CreateColor(r, g, b, 0))

    self:SetPlayerData(row, data, r, g, b)
    self:SetEquippedData(row, data)
    self:SetWishesData(row, data)
    self:SetCrestsData(row, data)
    self:SetBonusRollData(row, data)
    self:SetAwardData(row, data)
end

function Row:SetPlayerData(row, data, r, g, b)
    if data.class then
        row.classIcon:SetAtlas("classicon-" .. strlower(data.class))
        row.classIcon:Show()
    else
        row.classIcon:Hide()
    end

    row.name:SetText(addon.Ambiguate(data.name))
    row.name:SetTextColor(r, g, b)

    local ilvl = data.ilvl
    if not ilvl or ilvl == "" then
        ilvl = data.profile and data.profile.il
    end
    local rounded = tonumber(ilvl)
    row.characterIlvl:SetText(rounded and ("ilvl " .. math.floor(rounded)) or "-")
    row.characterIlvl:SetWidth(math.max(1, row.characterIlvl:GetStringWidth()))

    local specTexture = data.specID and select(4, GetSpecializationInfoByID(data.specID))
    if specTexture then
        row.specIcon:SetTexture(specTexture)
        row.specIcon:Show()
    else
        row.specIcon:Hide()
    end

    if data.responseText then
        row.responsePill:Set(data.responseText, unpack(data.responseColor or {1, 1, 1}))
    else
        row.responsePill:Hide()
        row.responsePill:SetWidth(0.01)
    end

    if type(data.note) == "string" and data.note ~= "" then
        row.noteButton:SetNote(_G.LABEL_NOTE, data.note)
    else
        row.noteButton:SetNote()
    end

    local profile = data.profile
    if profile and profile.cat then
        row.catalyst:Set(data.catalystIcon, tostring(profile.cat))
        row.catalyst:SetTooltip("Catalyst charges", profile.cat .. " available")
    else
        row.catalyst:Set()
    end

    local coins = profile and profile.br
    if coins then
        row.coins:Set(data.bonusRollIcon, tostring(coins.q or 0))
        row.coins:SetTooltip("Bonus rolls",
            (coins.q or 0) .. " available, " .. (coins.e or 0) .. " of " .. (coins.m or 0) .. " earned")
    else
        row.coins:Set()
    end

    -- Response yields to the currencies on the right, same line as the spec.
    local reserved = 0
    if row.coins:IsShown() then
        reserved = reserved + row.coins:GetWidth() + 8
    end
    if row.catalyst:IsShown() then
        reserved = reserved + row.catalyst:GetWidth() + 8
    end
    if row.noteButton:IsShown() then
        reserved = reserved + NOTE_SIZE + 4
    end
    if row.responsePill:IsShown() then
        local maxWidth = math.max(24, row.responseLine:GetWidth() - reserved)
        row.responsePill:SetWidth(math.min(row.responsePill:GetWidth(), maxWidth))
    end
end

function Row:SetEquippedData(row, data)
    local gear = {data.gear1, data.gear2}
    local stacked = data.gear1 and not data.gear2

    for index, line in ipairs(row.equipped) do
        local item = gear[index]

        if not item then
            line:Hide()
        else
            layoutEquippedLine(line, stacked and index == 1)
            line.chip:SetItem(item)
            line.ilvl:SetText(C_Item.GetDetailedItemLevelInfo(item) or "")
            if stacked then
                line.ilvl:SetWidth(math.max(1, line.ilvl:GetStringWidth()))
            end
            setEquippedTrack(line, item, data)
            line:Show()
        end
    end

    if not data.gear1 then
        local line = row.equipped[1]
        layoutEquippedLine(line, true)
        line.chip:SetItem(nil, "Nothing equipped")
        line.ilvl:SetText("")
        line.track:Hide()
        line.track:SetWidth(0.01)
        line.track:SetTooltip()
        line:Show()
    end
end

function Row:SetWishesData(row, data)
    local entries = data.slotWishes

    for index, line in ipairs(row.wishes) do
        local wish = entries[index]

        if not wish then
            line:Hide()
        else
            local link = wish.link or wowauditWishItemLink(wish.id, wish.bonus)
            line.chip:SetItem(link)
            line.chip:SetMuted(not wish.isDropped)
            if wish.isDropped then
                line.rank:SetFont(Theme:Font(12))
                line.rank:SetTextColor(Theme:Color("value"))
                line.value:SetFont(Theme:Font(12))
                line.value:SetAlpha(1)
            else
                line.rank:SetFont(Theme:Font(11))
                line.rank:SetTextColor(Theme:Color("dim"))
                line.value:SetFont(Theme:Font(11))
                line.value:SetAlpha(0.55)
            end
            line.rank:SetText(index .. ".")

            local text = specWishesText(wish.wishes)
            if not text then
                text = wowauditDataPresent() and "|cff6b6f7aNot on wishlist|r" or
                           withColor("No wowaudit data", "o")
            end

            if wish.priority then
                text = priorityLabel(wish.priority) .. " " .. text
            end
            -- Same suffix the voting frame uses when the wish came from another
            -- difficulty than the item on the table.
            local diff = wish.difficulty or (wish.wishes and wish.wishes[1] and wish.wishes[1].difficulty)
            if diff then
                text = text .. " |cff6b6f7a(" .. diff .. ")|r"
            end
            if wish.id and wowauditBonusRollTargetForItem(wish.id, data.name) then
                text = diceIcon .. " " .. text
            end

            line.value:SetText(text)
            line.value:SetWidth(math.max(1, line.value:GetStringWidth()))

            local comments = wishCommentLines(wish.wishes)
            if #comments > 0 then
                line.note:SetNote("Wishlist comment", unpack(comments))
            else
                line.note:SetNote()
            end

            line:Show()
        end
    end
end

function Row:SetCrestsData(row, data)
    local block = row.crest
    local trackName = data.itemTrack and data.itemTrack.track
    local profile = data.profile

    -- No track on the dropped item means there are no crests to talk about for anyone.
    if not trackName then
        block:Hide()
        return
    end

    -- No profile means this candidate isn't running the addon, so they can't share what
    -- they hold. Say so rather than leaving the column blank.
    if not profile then
        block.icon:Hide()
        block.held:Hide()
        block.earnable:Hide()
        block.upgrades:Hide()
        block.upgrades:SetTooltip()
        block.missing:SetText("Does not have addon installed")
        block.missing:Show()
        block:Show()
        return
    end

    block.missing:Hide()

    local crest = profile.cr and profile.cr[trackName]
    local equipped = profile.eq and profile.eq[trackName]
    local icon = data.crestIcons and data.crestIcons[trackName]
    local r, g, b = wowauditTrackColor(trackName)

    if icon then
        block.icon:SetTexture(icon)
        block.icon:SetAlpha(1)
        block.icon:Show()
        block.held:ClearAllPoints()
        block.held:SetPoint("LEFT", block.icon, "RIGHT", 4, 0)
    else
        block.icon:Hide()
        block.held:ClearAllPoints()
        block.held:SetPoint("TOPLEFT")
    end

    if crest then
        block.held:SetText(crest.q or 0)
        block.held:SetTextColor(r, g, b, 1)
        block.held:Show()
        block.held:SetWidth(math.max(1, block.held:GetStringWidth()))
        block.earnable:SetText(crest.e and ("+" .. crest.e .. " to earn") or "")
        block.earnable:Show()
    else
        block.held:Hide()
        block.earnable:SetText("")
        block.earnable:Hide()
    end

    local current, possible, upgradeTooltip = trackUpgradesTooltipLines(equipped)

    if possible > 0 then
        block.upgrades.text:SetText(current .. " |cff6b6f7a/|r " .. possible .. " upgraded")
        if upgradeTooltip then
            block.upgrades:SetTooltip(unpack(upgradeTooltip))
        else
            block.upgrades:SetTooltip()
        end
        block.upgrades:Show()
    else
        block.upgrades:SetTooltip()
        block.upgrades:Hide()
    end

    if not crest and possible == 0 then
        block:Hide()
        return
    end

    block:Show()
end

function Row:SetBonusRollData(row, data)
    local loot = data.bonusLoot
    local x, width = columnX("bonusRoll")

    row.bonusLootStatus:SetWidth(width)
    row.bonusLootStatus:ClearAllPoints()

    if loot then
        row.bonusLootChip:SetItem(loot.itemID)
        row.bonusLootStatus:SetPoint("TOPLEFT", x, lineY(2))
        row.bonusLootStatus:SetWordWrap(false)
        row.bonusLootStatus:SetTextColor(Theme:Color("dim"))
        row.bonusLootStatus:SetText(date("%H:%M", loot.time))
        return
    end

    row.bonusLootChip:Hide()
    row.bonusLootStatus:SetPoint("TOPLEFT", x, lineY(1))

    if data.bonusRollTarget then
        row.bonusLootStatus:SetWordWrap(false)
        row.bonusLootStatus:SetTextColor(Theme:Color("warning"))
        row.bonusLootStatus:SetText("Did not bonus roll")
    else
        row.bonusLootStatus:SetWordWrap(true)
        row.bonusLootStatus:SetTextColor(Theme:Color("dim"))
        row.bonusLootStatus:SetText("Not a bonus roll target")
    end
end

function Row:SetAwardData(row, data)
    local winner = type(data.awardedTo) == "string" and
                       (addon:UnitIsUnit(data.name, data.awardedTo) or data.name == data.awardedTo)

    if winner then
        row.awardButton:Hide()
        row.awardedPill:Set("Awarded", Theme:Color("accent"))
    else
        row.awardedPill:Hide()
        row.awardButton:Show()
    end
end
