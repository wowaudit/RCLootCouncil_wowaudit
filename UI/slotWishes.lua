local Theme = wowauditTheme

-- Ranked "Wishes in this slot" list used by the evaluation row and the loot frame.
wowauditSlotWishes = {}
local SlotWishes = wowauditSlotWishes

SlotWishes.MAX = 5
SlotWishes.WIDTH = 250

local MAX_SPEC_WISHES_SHOWN = 3
local NOTE_ICON = "Interface/BUTTONS/UI-GuildButton-PublicNote-Up.png"
local NOTE_SIZE = 14
local HOVER_ALPHA = 0.06

-- Child frames with their own tooltip steal mouse focus from the evaluation
-- row, which would drop the row highlight. Optional: loot cards have no hover.
local function keepRowLit(row, child)
    if not row or not row.hover then
        return
    end

    child:HookScript("OnEnter", function()
        row.hover:SetAlpha(HOVER_ALPHA)
    end)
    child:HookScript("OnLeave", function()
        row.hover:SetAlpha(row:IsMouseOver() and HOVER_ALPHA or 0)
    end)
end

local function createNoteIcon(parent, litRow)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(NOTE_SIZE, NOTE_SIZE)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexture(NOTE_ICON)
    Theme:AttachTooltip(button)
    keepRowLit(litRow, button)

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

function SlotWishes.RankText(index)
    return "#" .. index
end

-- Spec values, priority, difficulty and dice for one ranked slot item.
-- Used by the chip list and by the loot card's compact summary.
function SlotWishes.WishValueText(wish, characterName)
    if not wish then
        return nil
    end

    local text = specWishesText(wish.wishes)
    if not text then
        text = wowauditDataPresent() and "Not on wishlist" or withColor("No wowaudit data", "o")
    end

    if wish.priority then
        text = priorityLabel(wish.priority) .. " " .. text
    end
    local diff = wish.difficulty or (wish.wishes and wish.wishes[1] and wish.wishes[1].difficulty)
    if diff then
        text = text .. " |cff6b6f7a(" .. diff .. ")|r"
    end
    if wish.id and characterName and wowauditBonusRollTargetForItem(wish.id, characterName) then
        text = diceIcon .. " " .. text
    end

    return text
end

-- opts.lineHeight defaults to 16 (evaluation). opts.litRow keeps an
-- evaluation row highlighted while a chip tooltip is showing.
function SlotWishes:Create(parent, width, opts)
    opts = opts or {}
    local lineHeight = opts.lineHeight or 16
    local litRow = opts.litRow
    local muteAlternatives = opts.muteAlternatives
    if muteAlternatives == nil then
        muteAlternatives = true
    end

    local block = CreateFrame("Frame", nil, parent)
    block:SetSize(width, lineHeight * SlotWishes.MAX)
    block.lineHeight = lineHeight
    block.muteAlternatives = muteAlternatives

    block.empty = Theme:Value(block, 11)
    block.empty:SetTextColor(Theme:Color("dim"))
    block.empty:SetPoint("TOPLEFT")
    block.empty:SetWidth(width)
    block.empty:SetJustifyH("LEFT")
    block.empty:SetWordWrap(true)
    block.empty:Hide()

    block.lines = {}
    for index = 1, SlotWishes.MAX do
        local line = CreateFrame("Frame", nil, block)
        line:SetSize(width, lineHeight)
        line:SetPoint("TOPLEFT", 0, -(index - 1) * lineHeight)

        line.rank = Theme:Value(line, 11)
        line.rank:SetPoint("LEFT")
        line.rank:SetWidth(22)
        line.rank:SetJustifyH("LEFT")
        line.rank:SetTextColor(Theme:Color("dim"))

        -- Spec percents are sized to their text and pinned right so they never
        -- clip. The item name is the one that yields space.
        line.value = Theme:Value(line, 12)
        line.value:SetPoint("RIGHT")
        line.value:SetJustifyH("RIGHT")
        line.value:SetWordWrap(false)

        line.note = createNoteIcon(line, litRow)
        line.note:SetPoint("RIGHT", line.value, "LEFT", -3, 0)

        line.chip = Theme:ItemChip(line, width, 14)
        line.chip:SetPoint("LEFT", line.rank, "RIGHT", 2, 0)
        line.chip:SetPoint("RIGHT", line.note, "LEFT", -4, 0)
        keepRowLit(litRow, line.chip)

        block.lines[index] = line
    end

    return block
end

function SlotWishes:Set(block, data)
    local message = data.emptySlotMessage
    if message then
        for _, line in ipairs(block.lines) do
            line:Hide()
        end
        block.empty:SetText(message)
        block.empty:SetTextColor(Theme:Color(wowauditIsAlreadyEquippedMessage(message) and "warning" or "dim"))
        block.empty:Show()
        block:Show()
        return
    end
    block.empty:Hide()

    local entries = data.slotWishes or {}

    for index, line in ipairs(block.lines) do
        local wish = entries[index]

        if not wish then
            line:Hide()
        else
            local link = wish.link or wowauditWishItemLink(wish.id, wish.bonus)
            local mute = block.muteAlternatives and not wish.isDropped
            line.chip:SetItem(link)
            line.chip:SetMuted(mute)
            if mute then
                line.rank:SetFont(Theme:Font(11))
                line.rank:SetTextColor(Theme:Color("dim"))
                line.value:SetFont(Theme:Font(11))
            else
                line.rank:SetFont(Theme:Font(12))
                line.rank:SetTextColor(Theme:Color("value"))
                line.value:SetFont(Theme:Font(12))
            end
            -- SetTextColor last-arg alpha would undo mute, so colour first, then alpha.
            line.value:SetTextColor(Theme:Color("value"))
            line.value:SetAlpha(mute and 0.55 or 1)
            if wish.rank then
                line.rank:SetText(SlotWishes.RankText(wish.rank))
            else
                -- Keep the column so item icons still line up.
                line.rank:SetText("")
            end

            local text = SlotWishes.WishValueText(wish, data.name)
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

    block:Show()
end
