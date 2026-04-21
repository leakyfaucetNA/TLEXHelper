-- settings.lua
-- TLEX Helper settings panel. LECDM-styled: dark charcoal panels, purple accent,
-- title bar → spec bar → content. For each spec, two multi-select dropdowns
-- (Raid / Mythic+) listing the spec's TLEX loadouts with checkboxes.

local _, ns = ...

local t = ns.theme
local TEX, C_BG, C_PANEL, C_BDR, C_ACCENT, C_TEXT, C_DIM =
    t.TEX, t.C_BG, t.C_PANEL, t.C_BDR, t.C_ACCENT, t.C_TEXT, t.C_DIM

local TITLE_H = 28
local SPEC_H  = 54
local PAD     = 8

local frame
local specBar, specButtons = nil, {}
local contentPanel
local selectedSpecIdx
---@diagnostic disable-next-line: unused-local
local activeLoadoutLbl  -- assigned in BuildFrame, read by RefreshActiveLoadout

-- -------------------------------------------------- --
--  Dropdown helpers                                  --
-- -------------------------------------------------- --

local function DropdownLabel(count)
    if count == 0 then return "None selected" end
    if count == 1 then return "1 loadout selected" end
    return count .. " loadouts selected"
end

local function RebuildSetItems(set)
    local loadouts = ns.GetLoadoutsForSpec(selectedSpecIdx)
    local items = {}
    for _, data in ipairs(loadouts) do
        table.insert(items, {
            label   = data.name,
            value   = data.name,
            checked = set[data.name] and true or false,
        })
    end
    return items
end

local function CountSelected(set)
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end

-- -------------------------------------------------- --
--  Content panel                                     --
-- -------------------------------------------------- --

local raidDrop, mythicDrop, raidCountLbl, mythicCountLbl, emptyLbl

local function RefreshActiveLoadout()
    if not activeLoadoutLbl then return end
    local name = ns.CurrentLoadoutName()
    if name then
        activeLoadoutLbl:SetText("Active: |cff00ccff" .. name .. "|r")
    else
        activeLoadoutLbl:SetText("Active: |cff888888(none)|r")
    end
end
ns.RefreshSettingsActive = RefreshActiveLoadout

local function RefreshContent()
    RefreshActiveLoadout()
    if not selectedSpecIdx then return end
    local cfg = ns.GetSpecConfig(selectedSpecIdx)
    local loadouts = ns.GetLoadoutsForSpec(selectedSpecIdx)

    raidDrop:SetValue(DropdownLabel(CountSelected(cfg.raid)))
    mythicDrop:SetValue(DropdownLabel(CountSelected(cfg.mythic)))

    if #loadouts == 0 then
        emptyLbl:Show()
        raidDrop:Hide()
        mythicDrop:Hide()
        raidCountLbl:Hide()
        mythicCountLbl:Hide()
    else
        emptyLbl:Hide()
        raidDrop:Show()
        mythicDrop:Show()
        raidCountLbl:Show()
        mythicCountLbl:Show()
    end
end

local function BuildContent(parent)
    contentPanel = ns.MakePanel(parent, C_PANEL, C_BDR)

    local title = ns.MakeLabel(contentPanel, "Tag loadouts by instance type", 14, C_ACCENT)
    title:SetPoint("TOPLEFT", PAD, -PAD)

    local help = ns.MakeLabel(contentPanel,
        "Loadouts you check here will be treated as the correct choice when entering that instance type.",
        11, C_DIM)
    help:SetPoint("TOPLEFT", PAD, -PAD - 22)
    help:SetPoint("TOPRIGHT", -PAD, -PAD - 22)
    help:SetJustifyH("LEFT")
    help:SetWordWrap(true)

    raidCountLbl = ns.MakeLabel(contentPanel, "Raid loadouts", 13, C_TEXT)
    raidCountLbl:SetPoint("TOPLEFT", PAD, -PAD - 58)

    raidDrop = ns.MakeMultiDropdown(contentPanel, 280, 24)
    raidDrop:SetPoint("TOPLEFT", PAD, -PAD - 78)
    raidDrop:SetScript("OnClick", function(s)
        local cfg = ns.GetSpecConfig(selectedSpecIdx)
        s:Open(RebuildSetItems(cfg.raid), function(value, nowChecked)
            if nowChecked then cfg.raid[value] = true else cfg.raid[value] = nil end
            raidDrop:SetValue(DropdownLabel(CountSelected(cfg.raid)))
            if ns.Refresh then ns.Refresh() end
        end)
    end)

    mythicCountLbl = ns.MakeLabel(contentPanel, "Mythic+ loadouts", 13, C_TEXT)
    mythicCountLbl:SetPoint("TOPLEFT", PAD, -PAD - 118)

    mythicDrop = ns.MakeMultiDropdown(contentPanel, 280, 24)
    mythicDrop:SetPoint("TOPLEFT", PAD, -PAD - 138)
    mythicDrop:SetScript("OnClick", function(s)
        local cfg = ns.GetSpecConfig(selectedSpecIdx)
        s:Open(RebuildSetItems(cfg.mythic), function(value, nowChecked)
            if nowChecked then cfg.mythic[value] = true else cfg.mythic[value] = nil end
            mythicDrop:SetValue(DropdownLabel(CountSelected(cfg.mythic)))
            if ns.Refresh then ns.Refresh() end
        end)
    end)

    emptyLbl = ns.MakeLabel(contentPanel,
        "No TLEX loadouts saved for this spec yet. Create one in the talents pane first.",
        12, C_DIM)
    emptyLbl:SetPoint("TOPLEFT", PAD, -PAD - 78)
    emptyLbl:SetPoint("TOPRIGHT", -PAD, -PAD - 78)
    emptyLbl:SetJustifyH("LEFT")
    emptyLbl:SetWordWrap(true)
    emptyLbl:Hide()

    return contentPanel
end

-- -------------------------------------------------- --
--  Spec bar                                          --
-- -------------------------------------------------- --

local function BuildSpecBar()
    for _, b in ipairs(specButtons) do b:Hide() end
    wipe(specButtons)

    local numSpecs  = GetNumSpecializations() or 0
    local activeIdx = GetSpecialization()

    if not selectedSpecIdx then selectedSpecIdx = activeIdx end

    local x = PAD
    for i = 1, numSpecs do
        local _, sname, _, sicon = GetSpecializationInfo(i)
        local b = CreateFrame("Button", nil, specBar, "BackdropTemplate")
        ns.SetBD(b, t.C_ELEM, C_BDR)
        b:SetSize(40, 40)
        b:SetPoint("LEFT", x, 0)

        local tex = b:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", 2, -2)
        tex:SetPoint("BOTTOMRIGHT", -2, 2)
        if sicon then tex:SetTexture(sicon) end

        if i == activeIdx then
            tex:SetDesaturated(false); tex:SetAlpha(1)
        else
            tex:SetDesaturated(true);  tex:SetAlpha(0.6)
        end

        if i == selectedSpecIdx then
            b:SetBackdropBorderColor(unpack(C_ACCENT))
        end

        b:SetScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_TOP")
            GameTooltip:SetText(sname or "", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function()
            selectedSpecIdx = i
            BuildSpecBar()
            RefreshContent()
        end)

        table.insert(specButtons, b)
        x = x + 44
    end
end

-- -------------------------------------------------- --
--  Window                                            --
-- -------------------------------------------------- --

local function BuildFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "TLEXHelperSettings", UIParent, "BackdropTemplate")
    frame:SetSize(520, 320)
    frame:SetPoint("CENTER")
    ns.SetBD(frame, C_BG, C_BDR)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:Hide()

    local title = ns.MakePanel(frame, C_PANEL, C_BDR)
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetPoint("TOPRIGHT", 0, 0)
    title:SetHeight(TITLE_H)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() frame:StartMoving() end)
    title:SetScript("OnDragStop",  function() frame:StopMovingOrSizing() end)

    local titleText = ns.MakeLabel(title, "TLEX Helper", 14, C_ACCENT)
    titleText:SetPoint("LEFT", 10, 0)

    local close = ns.MakeButton(title, "X", 24, 20)
    close:SetPoint("RIGHT", -4, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    activeLoadoutLbl = ns.MakeLabel(title, "", 12, t.C_TEXT)
    activeLoadoutLbl:SetPoint("RIGHT", close, "LEFT", -10, 0)
    activeLoadoutLbl:SetJustifyH("RIGHT")

    specBar = ns.MakePanel(frame, C_PANEL, C_BDR)
    specBar:SetPoint("TOPLEFT", 0, -TITLE_H)
    specBar:SetPoint("TOPRIGHT", 0, -TITLE_H)
    specBar:SetHeight(SPEC_H)

    local content = BuildContent(frame)
    content:SetPoint("TOPLEFT", 0, -(TITLE_H + SPEC_H))
    content:SetPoint("BOTTOMRIGHT", 0, 0)

    frame:SetScript("OnShow", function()
        BuildSpecBar()
        RefreshContent()
        -- If we don't have a name yet, keep polling so the label fills in once
        -- the talent data becomes available.
        if not ns.CurrentLoadoutName() and ns.StartRefreshRetry then
            ns.StartRefreshRetry()
        end
    end)

    return frame
end

function ns.OpenSettings()   BuildFrame():Show() end
function ns.CloseSettings()  if frame then frame:Hide() end end
function ns.ToggleSettings()
    local f = BuildFrame()
    if f:IsShown() then f:Hide() else f:Show() end
end
