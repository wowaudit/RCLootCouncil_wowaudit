local LibDialog = LibStub("LibDialog-1.1")
local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")

LibDialog:Register("RCWOWAUDIT_OUTDATED_MESSAGE", {
    text = "Your version of RCLootCouncil is probably too old to work with this version of the wowaudit module. Please update it!",
    icon = "",
    buttons = {{
        text = _G.OKAY
    }},
    show_while_dead = true,
    hide_on_escape = true
})

local LOGO = "Interface\\AddOns\\RCLootCouncil_wowaudit\\Media\\logo"
local VISIBILITY_WIDTH = 340
local VISIBILITY_PAD = 20
local VISIBILITY_ICON = 36
local VISIBILITY_BUTTON_WIDTH = 260
local VISIBILITY_BUTTON_GAP = 6

-- LibDialog recycles frames. If we leave text/icon re-anchored, the next popup
-- (Abort, Award, …) inherits that layout and looks off-centre.
local function restoreDialogLayout(dialog)
    if dialog.text then
        dialog.text:ClearAllPoints()
        dialog.text:SetJustifyH("CENTER")
        dialog.text:SetJustifyV("MIDDLE")
        dialog.text:SetPoint("TOP", 0, -16)
    end
    if dialog.icon then
        dialog.icon:ClearAllPoints()
        dialog.icon:SetPoint("LEFT", dialog, "LEFT", 16, 0)
    end
end

local visibilityDelegate

local function layoutVisibilityDialog(dialog)
    if dialog.delegate ~= visibilityDelegate or not dialog:IsShown() or not dialog.buttons then
        return
    end

    if dialog.icon then
        dialog.icon:ClearAllPoints()
        dialog.icon:SetSize(VISIBILITY_ICON, VISIBILITY_ICON)
        dialog.icon:SetTexture(LOGO)
        dialog.icon:SetPoint("TOPLEFT", VISIBILITY_PAD, -VISIBILITY_PAD)
        dialog.icon:Show()
    end

    local textWidth = VISIBILITY_WIDTH - VISIBILITY_PAD - VISIBILITY_ICON - 12 - VISIBILITY_PAD - 24
    dialog.text:ClearAllPoints()
    dialog.text:SetJustifyH("LEFT")
    dialog.text:SetJustifyV("TOP")
    dialog.text:SetWidth(textWidth)
    dialog.text:SetPoint("TOPLEFT", dialog.icon, "TOPRIGHT", 12, 0)

    local prev
    for index = #dialog.buttons, 1, -1 do
        local button = dialog.buttons[index]
        button:ClearAllPoints()
        button:SetWidth(VISIBILITY_BUTTON_WIDTH)
        if prev then
            button:SetPoint("BOTTOM", prev, "TOP", 0, VISIBILITY_BUTTON_GAP)
        else
            button:SetPoint("BOTTOM", 0, VISIBILITY_PAD)
        end
        prev = button
    end

    local textHeight = math.max(VISIBILITY_ICON, dialog.text:GetStringHeight())
    local buttonCount = #dialog.buttons
    local buttonsHeight = buttonCount * 21 + math.max(0, buttonCount - 1) * VISIBILITY_BUTTON_GAP
    dialog:SetWidth(VISIBILITY_WIDTH)
    dialog:SetHeight(VISIBILITY_PAD + textHeight + 16 + buttonsHeight + VISIBILITY_PAD)
end

visibilityDelegate = {
    text = "wowaudit evaluation window\n\nYou used the evaluation window this session. How should it open next time?\n\nThis can always be changed in the RCLootCouncil wowaudit config.",
    icon = LOGO,
    text_justify_h = "LEFT",
    buttons = {{
        text = "Don't open automatically",
        on_click = function()
            addon:GetModule("RCwowaudit"):SetEvaluationVisibility("never")
        end
    }, {
        text = "Open alongside voting frame",
        on_click = function()
            addon:GetModule("RCwowaudit"):SetEvaluationVisibility("alongside")
        end
    }, {
        text = "Replace voting frame",
        on_click = function()
            addon:GetModule("RCwowaudit"):SetEvaluationVisibility("replace")
        end
    }},
    on_show = function(self)
        -- LibDialog lays buttons in a row and resizes after on_show; wait one
        -- frame so the stacked layout and height stick.
        C_Timer.After(0, function()
            layoutVisibilityDialog(self)
        end)
    end,
    on_hide = restoreDialogLayout,
    show_while_dead = true,
    hide_on_escape = true
}
LibDialog:Register("RCWOWAUDIT_EVALUATION_VISIBILITY", visibilityDelegate)
