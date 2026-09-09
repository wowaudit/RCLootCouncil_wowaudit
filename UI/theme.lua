local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")

-- Shared look for the evaluation window. Deliberately does not use RCLootCouncil's
-- RCFrame, lib-st or AceGUI: everything is drawn from flat fills and hairlines so
-- the window reads like a dashboard instead of a Blizzard panel.
wowauditTheme = {}
local Theme = wowauditTheme

local SOLID = "Interface\\Buttons\\WHITE8X8"

Theme.spacing = 8
Theme.rowHeight = 64

Theme.colors = {
    body = {0.047, 0.047, 0.059, 0.96},
    header = {0.086, 0.090, 0.106, 1},
    outline = {0, 0, 0, 0.9},
    hairline = {1, 1, 1, 0.10},
    card = {0.106, 0.110, 0.129, 0.9},
    cardAlt = {0.078, 0.082, 0.098, 0.9},
    hover = {1, 1, 1, 0.05},
    divider = {1, 1, 1, 0.06},
    label = {0.51, 0.53, 0.58, 1},
    value = {0.92, 0.93, 0.95, 1},
    dim = {0.42, 0.44, 0.49, 1},
    -- Matches --color-primary from the website's dark theme.
    accent = {0.13, 0.77, 0.37, 1},
    warning = {0.95, 0.75, 0.2, 1},
    track = {1, 1, 1, 0.07}
}

local function unpackColor(color, alphaOverride)
    return color[1], color[2], color[3], alphaOverride or color[4] or 1
end

function Theme:Color(name, alpha)
    return unpackColor(self.colors[name], alpha)
end

function Theme:Font(size, bold)
    local file = select(1, (bold and _G.GameFontNormalLarge or _G.GameFontNormal):GetFont())
    return file, size, ""
end

function Theme:Solid(parent, layer, sublevel)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
    texture:SetTexture(SOLID)
    return texture
end

function Theme:Fill(parent, color, layer, sublevel)
    local texture = self:Solid(parent, layer, sublevel)
    texture:SetAllPoints()
    texture:SetVertexColor(unpackColor(self.colors[color] or color))
    return texture
end

-- A 1px inner border. Two of these nested (dark outside, light inside) is what
-- gives the window a crisp edge without any bevelled artwork. Anchored corner to
-- corner so no edge is over-constrained.
function Theme:Hairline(frame, color, inset, layer)
    inset = inset or 0
    local edges = {}
    local r, g, b, a = unpackColor(self.colors[color] or color)

    local anchors = {
        TOP = {"TOPLEFT", "TOPRIGHT", inset, -inset, -inset, -inset},
        BOTTOM = {"BOTTOMLEFT", "BOTTOMRIGHT", inset, inset, -inset, inset},
        LEFT = {"TOPLEFT", "BOTTOMLEFT", inset, -inset, inset, inset},
        RIGHT = {"TOPRIGHT", "BOTTOMRIGHT", -inset, -inset, -inset, inset}
    }

    for edge, anchor in pairs(anchors) do
        local texture = self:Solid(frame, layer or "BORDER")
        texture:SetVertexColor(r, g, b, a)

        if edge == "TOP" or edge == "BOTTOM" then
            texture:SetHeight(1)
        else
            texture:SetWidth(1)
        end

        texture:SetPoint(anchor[1], frame, anchor[1], anchor[3], anchor[4])
        texture:SetPoint(anchor[2], frame, anchor[2], anchor[5], anchor[6])

        edges[edge] = texture
    end

    return edges
end

function Theme:Panel(parent, name)
    local frame = CreateFrame("Frame", name, parent or UIParent)
    self:Fill(frame, "body", "BACKGROUND")
    self:Hairline(frame, "outline", 0)
    self:Hairline(frame, "hairline", 1)
    return frame
end

function Theme:Label(parent, text)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(self:Font(9))
    label:SetTextColor(self:Color("label"))
    label:SetJustifyH("LEFT")
    if text then
        label:SetText(strupper(text))
    end
    return label
end

function Theme:Value(parent, size, bold)
    local value = parent:CreateFontString(nil, "OVERLAY")
    value:SetFont(self:Font(size or 12, bold))
    value:SetTextColor(self:Color("value"))
    value:SetJustifyH("LEFT")
    return value
end

function Theme:Divider(parent, vertical)
    local divider = self:Solid(parent, "ARTWORK")
    divider:SetVertexColor(self:Color("divider"))
    if vertical then
        divider:SetWidth(1)
    else
        divider:SetHeight(1)
    end
    return divider
end

-- Filled badge used for upgrade tracks ("Hero 3/6"), responses and priorities.
function Theme:Pill(parent, height)
    local pill = CreateFrame("Frame", nil, parent)
    pill:SetHeight(height or 16)

    pill.bg = self:Solid(pill, "ARTWORK")
    pill.bg:SetAllPoints()

    pill.text = pill:CreateFontString(nil, "OVERLAY")
    pill.text:SetFont(self:Font(10))
    pill.text:SetPoint("LEFT", 6, 0)
    pill.text:SetPoint("RIGHT", -6, 0)
    pill.text:SetWordWrap(false)
    pill.text:SetJustifyH("CENTER")

    function pill:Set(text, r, g, b)
        if not text then
            self:Hide()
            return
        end
        self.text:SetText(text)
        self.bg:SetVertexColor(r, g, b, 0.18)
        self.text:SetTextColor(r, g, b)
        self:SetWidth(self.text:GetStringWidth() + 12)
        self:Show()
    end

    return pill
end

-- Horizontal bar that ranks a value against the best one in the session. Reading
-- the bars is faster than reading the numbers, which is the point.
function Theme:Bar(parent, width, height)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width or 60, height or 3)

    bar.track = self:Solid(bar, "ARTWORK")
    bar.track:SetAllPoints()
    bar.track:SetVertexColor(self:Color("track"))

    bar.fill = self:Solid(bar, "ARTWORK", 1)
    bar.fill:SetPoint("TOPLEFT")
    bar.fill:SetPoint("BOTTOMLEFT")

    function bar:SetProgress(fraction, r, g, b)
        if not fraction or fraction <= 0 then
            self.fill:Hide()
            return
        end
        self.fill:SetWidth(math.max(2, self:GetWidth() * math.min(1, fraction)))
        self.fill:SetVertexColor(r or 1, g or 1, b or 1, 0.9)
        self.fill:Show()
    end

    return bar
end

function Theme:Icon(parent, size, layer)
    local icon = parent:CreateTexture(nil, layer or "ARTWORK")
    icon:SetSize(size or 16, size or 16)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    return icon
end

-- Icon plus a number, for catalyst charges and crest counts.
function Theme:IconText(parent, iconSize)
    local group = CreateFrame("Frame", nil, parent)
    group:SetHeight(iconSize or 12)

    group.icon = self:Icon(group, iconSize or 12)
    group.icon:SetPoint("LEFT")

    group.text = self:Value(group, 11)
    group.text:SetPoint("LEFT", group.icon, "RIGHT", 3, 0)

    function group:Set(icon, text, r, g, b)
        if not text then
            -- Collapse rather than just hide, so anything anchored to the right of
            -- this group doesn't leave a gap behind.
            self:SetWidth(0.01)
            self:Hide()
            return
        end
        if icon then
            self.icon:SetTexture(icon)
            self.icon:Show()
            self.text:SetPoint("LEFT", self.icon, "RIGHT", 3, 0)
        else
            self.icon:Hide()
            self.text:SetPoint("LEFT", self, "LEFT", 0, 0)
        end
        self.text:SetText(text)
        self.text:SetTextColor(r or Theme.colors.value[1], g or Theme.colors.value[2],
            b or Theme.colors.value[3])
        self:SetWidth((icon and (iconSize or 12) + 3 or 0) + self.text:GetStringWidth())
        self:Show()
    end

    return group
end

-- Item icon, name in its quality colour and a real hypertip on hover.
function Theme:ItemChip(parent, width, iconSize)
    local chip = CreateFrame("Frame", nil, parent)
    chip:SetSize(width or 150, iconSize or 18)
    chip:EnableMouse(true)

    chip.icon = self:Icon(chip, iconSize or 18)
    chip.icon:SetPoint("LEFT")

    chip.name = self:Value(chip, 12)
    chip.name:SetPoint("LEFT", chip.icon, "RIGHT", 5, 0)
    chip.name:SetPoint("RIGHT")
    chip.name:SetWordWrap(false)

    chip:SetScript("OnEnter", function(self)
        Theme:ShowItemTooltip(self, self.link)
    end)
    chip:SetScript("OnLeave", function()
        Theme:HideItemTooltip()
    end)

    function chip:SetItem(linkOrID, fallbackText)
        if not linkOrID then
            self.link = nil
            self.icon:Hide()
            self.name:SetText(fallbackText or "-")
            self.name:SetTextColor(Theme:Color("dim"))
            self:Show()
            return
        end

        local name, link, quality = C_Item.GetItemInfo(linkOrID)
        local icon = select(5, C_Item.GetItemInfoInstant(linkOrID))

        self.link = link or (type(linkOrID) == "string" and linkOrID or nil)
        self.icon:SetTexture(icon or 134400)
        self.icon:Show()
        self.name:SetText(name or fallbackText or "...")

        local color = quality and ITEM_QUALITY_COLORS[quality]
        if color then
            self.name:SetTextColor(color.r, color.g, color.b)
        else
            self.name:SetTextColor(Theme:Color("value"))
        end
        self:Show()
    end

    return chip
end

-- Flat header control. Hover brightens the fill rather than swapping artwork.
function Theme:Button(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 90, height or 22)

    button.bg = self:Solid(button, "ARTWORK")
    button.bg:SetAllPoints()
    button.bg:SetVertexColor(1, 1, 1, 0.06)

    self:Hairline(button, "hairline", 0, "OVERLAY")

    button.text = button:CreateFontString(nil, "OVERLAY")
    button.text:SetFont(self:Font(11))
    button.text:SetPoint("CENTER")
    button.text:SetTextColor(self:Color("value"))
    button.text:SetText(text or "")

    button:SetScript("OnEnter", function(self)
        self.bg:SetVertexColor(1, 1, 1, 0.13)
    end)
    button:SetScript("OnLeave", function(self)
        self.bg:SetVertexColor(1, 1, 1, 0.06)
    end)

    function button:SetLabel(value)
        self.text:SetText(value)
    end

    return button
end

-- Our own item tooltip rather than GameTooltip. Blizzard attaches the "Equipped"
-- comparison tooltips to GameTooltip, and with several item links per row those
-- would bury the window. A tooltip frame without shoppingTooltips of its own simply
-- never shows them, which is also why RCLootCouncil has to create them by hand for
-- its voting frame tooltip.
-- Anchored to the hovered element with ANCHOR_RIGHT and clamped to the screen, exactly
-- like Blizzard's own bag and character-panel tooltips - no cursor tracking of our own.
local itemTooltip

function Theme:ShowItemTooltip(owner, link)
    if not link then
        return
    end

    if not itemTooltip then
        itemTooltip = CreateFrame("GameTooltip", "RCwowauditItemTooltip", UIParent, "GameTooltipTemplate")
        itemTooltip:SetClampedToScreen(true)
    end

    itemTooltip:SetOwner(owner, "ANCHOR_LEFT")
    itemTooltip:SetHyperlink(link)
    itemTooltip:Show()
end

function Theme:HideItemTooltip()
    if itemTooltip then
        itemTooltip:Hide()
    end
end

-- Text tooltip for the small data points, owned by us (rather than RCLootCouncil's
-- cursor-anchored CreateTooltip) so it can sit next to the hovered element the same way
-- Blizzard's tooltips do.
local textTooltip

function Theme:ShowTooltip(owner, ...)
    if select("#", ...) == 0 then
        return
    end

    if not textTooltip then
        textTooltip = CreateFrame("GameTooltip", "RCwowauditTextTooltip", UIParent, "GameTooltipTemplate")
        textTooltip:SetClampedToScreen(true)
    end

    textTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    for i = 1, select("#", ...) do
        textTooltip:AddLine((select(i, ...)), 1, 1, 1)
    end
    textTooltip:Show()
end

function Theme:HideTooltip()
    if textTooltip then
        textTooltip:Hide()
    end
end

-- Gives a small element its own focused tooltip, so each data point explains itself
-- instead of one tooltip covering a whole row.
function Theme:AttachTooltip(frame)
    frame:EnableMouse(true)

    frame:SetScript("OnEnter", function(self)
        if self.tooltipLines then
            Theme:ShowTooltip(self, unpack(self.tooltipLines))
        end
    end)
    frame:SetScript("OnLeave", function()
        Theme:HideTooltip()
    end)

    function frame:SetTooltip(...)
        self.tooltipLines = select("#", ...) > 0 and {...} or nil
    end

    return frame
end

function Theme:Slider(parent, width, minimum, maximum, step)
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetSize(width, 14)

    local track = self:Solid(slider, "ARTWORK")
    track:SetHeight(2)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetVertexColor(self:Color("track"))

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(SOLID)
    thumb:SetSize(6, 14)
    thumb:SetVertexColor(self:Color("accent"))
    slider:SetThumbTexture(thumb)

    return slider
end
