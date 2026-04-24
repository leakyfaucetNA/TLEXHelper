-- main.lua
-- TLEX Helper: reads TalentLoadoutsEx state, tags loadouts as Raid/Mythic+ per spec,
-- and warns when the active loadout doesn't match the zone's instance type.
--
-- Visual primitives live here and are exposed on `ns` so settings.lua can reuse
-- them — keeps the LECDM-styled look in one place.

---@diagnostic disable: undefined-field  -- TalentLoadoutEx and TLX are globals injected by the TLEX addon at runtime.

local _, ns = ...

-- -------------------------------------------------- --
--  Theme (mirrors LECDM)                             --
-- -------------------------------------------------- --

local TEX      = "Interface\\Buttons\\WHITE8x8"
local C_BG     = {0.08, 0.08, 0.08, 0.95}
local C_PANEL  = {0.12, 0.12, 0.12, 1}
local C_ELEM   = {0.18, 0.18, 0.18, 1}
local C_BDR    = {0.25, 0.25, 0.25, 1}
local C_ACCENT = {0.45, 0.45, 0.95, 1}
local C_HOVER  = {0.22, 0.22, 0.22, 1}
local C_TEXT   = {0.90, 0.90, 0.90, 1}
local C_DIM    = {0.60, 0.60, 0.60, 1}
local C_OK     = {0.40, 0.85, 0.40, 1}
local C_WARN   = {0.95, 0.45, 0.45, 1}

ns.theme = {
    TEX=TEX, C_BG=C_BG, C_PANEL=C_PANEL, C_ELEM=C_ELEM, C_BDR=C_BDR,
    C_ACCENT=C_ACCENT, C_HOVER=C_HOVER, C_TEXT=C_TEXT, C_DIM=C_DIM,
    C_OK=C_OK, C_WARN=C_WARN,
}

-- -------------------------------------------------- --
--  Primitives                                        --
-- -------------------------------------------------- --

local function SetBD(f, bg, bdr)
    f:SetBackdrop({
        bgFile   = TEX,
        edgeFile = TEX,
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(unpack(bg))
    f:SetBackdropBorderColor(unpack(bdr or C_BDR))
end

local function MakePanel(parent, bg, bdr)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    SetBD(f, bg or C_PANEL, bdr or C_BDR)
    return f
end

local function MakeLabel(parent, text, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if size then
        local font = fs:GetFont()
        fs:SetFont(font, size, "")
    end
    fs:SetText(text or "")
    fs:SetTextColor(unpack(color or C_TEXT))
    return fs
end

local function MakeButton(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    SetBD(b, C_ELEM, C_BDR)
    b:SetSize(w or 70, h or 22)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER")
    fs:SetText(text or "")
    fs:SetTextColor(unpack(C_TEXT))
    b.text = fs
    b:SetScript("OnEnter", function(s) s:SetBackdropColor(unpack(C_HOVER)) end)
    b:SetScript("OnLeave", function(s) s:SetBackdropColor(unpack(C_ELEM)) end)
    return b
end

local function MakeAccentButton(parent, text, w, h)
    local b = MakeButton(parent, text, w, h)
    b:SetBackdropColor(unpack(C_ACCENT))
    b:SetScript("OnEnter", function(s) s:SetBackdropColor(0.55, 0.55, 1.0, 1) end)
    b:SetScript("OnLeave", function(s) s:SetBackdropColor(unpack(C_ACCENT)) end)
    return b
end

local function MakeCheck(parent)
    local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    SetBD(c, C_ELEM, C_BDR)
    c:SetSize(18, 18)
    c:EnableMouse(true)

    local fill = c:CreateTexture(nil, "OVERLAY")
    fill:SetTexture(TEX)
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetVertexColor(unpack(C_ACCENT))
    fill:Hide()
    c.fill = fill

    function c:SetChecked(v)
        if v then fill:Show() else fill:Hide() end
    end
    function c:GetChecked() return fill:IsShown() end

    c:SetScript("OnMouseUp", function(s, btn)
        if btn ~= "LeftButton" then return end
        s:SetChecked(not s:GetChecked())
        if s.onChanged then s.onChanged(s:GetChecked()) end
    end)
    return c
end

-- Multi-select dropdown. Rows carry a check; popup stays open until the user
-- clicks outside (clickCatcher) or re-clicks the owner. Matches LECDM's
-- ShowDropdown pattern but each row toggles instead of auto-closing.
local DROP_ROW_H        = 22
local DROP_VISIBLE_ROWS = 13

local dropPopup, dropScroll, dropScrollChild, clickCatcher
local function GetDropPopup()
    if dropPopup then return dropPopup end

    clickCatcher = CreateFrame("Button", nil, UIParent)
    clickCatcher:SetAllPoints(UIParent)
    clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
    clickCatcher:RegisterForClicks("AnyUp")
    clickCatcher:Hide()
    clickCatcher:SetScript("OnClick", function()
        if dropPopup then dropPopup:Hide() end
    end)

    dropPopup = CreateFrame("Frame", "TLEXHelperDropPopup", UIParent, "BackdropTemplate")
    SetBD(dropPopup, C_PANEL, C_BDR)
    dropPopup:SetFrameStrata("FULLSCREEN_DIALOG")
    dropPopup:SetFrameLevel(clickCatcher:GetFrameLevel() + 10)
    dropPopup:Hide()
    dropPopup.rows = {}
    dropPopup:SetScript("OnShow", function() clickCatcher:Show() end)
    dropPopup:SetScript("OnHide", function() clickCatcher:Hide() end)

    dropScroll = CreateFrame("ScrollFrame", nil, dropPopup)
    dropScroll:SetPoint("TOPLEFT",     dropPopup, "TOPLEFT",      1,  -1)
    dropScroll:SetPoint("BOTTOMRIGHT", dropPopup, "BOTTOMRIGHT", -1,   1)
    dropScroll:EnableMouseWheel(true)
    dropScroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, (dropScrollChild:GetHeight() or 0) - (self:GetHeight() or 0))
        local new = math.max(0, math.min(maxScroll, (self:GetVerticalScroll() or 0) - delta * DROP_ROW_H))
        self:SetVerticalScroll(new)
    end)

    dropScrollChild = CreateFrame("Frame", nil, dropScroll)
    dropScrollChild:SetSize(1, 1)
    dropScroll:SetScrollChild(dropScrollChild)

    return dropPopup
end

-- items = { {label=, value=, checked=bool}, ... }
-- onToggle(value, nowChecked) fires per click; popup stays open.
local function ShowMultiDropdown(owner, items, onToggle)
    local pop = GetDropPopup()
    pop.owner = owner
    for _, r in ipairs(pop.rows) do r:Hide() end

    local rowW = math.max(owner:GetWidth(), 200)
    for i, it in ipairs(items) do
        local row = pop.rows[i]
        if not row then
            row = CreateFrame("Button", nil, dropScrollChild, "BackdropTemplate")
            SetBD(row, C_PANEL, C_PANEL)
            row:SetScript("OnEnter", function(s) s:SetBackdropColor(unpack(C_HOVER)) end)
            row:SetScript("OnLeave", function(s) s:SetBackdropColor(unpack(C_PANEL)) end)

            local chk = CreateFrame("Frame", nil, row, "BackdropTemplate")
            SetBD(chk, C_ELEM, C_BDR)
            chk:SetSize(14, 14)
            chk:SetPoint("LEFT", 6, 0)
            local fill = chk:CreateTexture(nil, "OVERLAY")
            fill:SetTexture(TEX)
            fill:SetPoint("TOPLEFT", 2, -2)
            fill:SetPoint("BOTTOMRIGHT", -2, 2)
            fill:SetVertexColor(unpack(C_ACCENT))
            fill:Hide()
            chk.fill = fill
            row.chk = chk

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.text:SetPoint("LEFT", chk, "RIGHT", 8, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.text:SetJustifyH("LEFT")
            pop.rows[i] = row
        end
        row:SetSize(rowW, DROP_ROW_H)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * DROP_ROW_H)
        row.text:SetText(it.label)
        row.text:SetTextColor(unpack(C_TEXT))
        if it.checked then row.chk.fill:Show() else row.chk.fill:Hide() end

        row:SetScript("OnClick", function()
            local newVal = not row.chk.fill:IsShown()
            if newVal then row.chk.fill:Show() else row.chk.fill:Hide() end
            it.checked = newVal
            if onToggle then onToggle(it.value, newVal) end
        end)
        row:Show()
    end

    local visible = math.min(math.max(#items, 1), DROP_VISIBLE_ROWS)
    pop:SetSize(rowW + 2, visible * DROP_ROW_H + 2)
    dropScrollChild:SetSize(rowW, math.max(#items, 1) * DROP_ROW_H)
    dropScroll:SetVerticalScroll(0)
    pop:ClearAllPoints()
    pop:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    pop:Show()
end

local function MakeMultiDropdown(parent, w, h)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    SetBD(b, C_ELEM, C_BDR)
    b:SetSize(w or 220, h or 22)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetPoint("LEFT", 8, 0)
    b.text:SetPoint("RIGHT", -18, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetTextColor(unpack(C_TEXT))

    local arrow = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetText("v")
    arrow:SetTextColor(unpack(C_DIM))

    b:SetScript("OnEnter", function(s) s:SetBackdropColor(unpack(C_HOVER)) end)
    b:SetScript("OnLeave", function(s) s:SetBackdropColor(unpack(C_ELEM)) end)

    function b:SetValue(label) self.text:SetText(label or "") end
    function b:Open(items, onToggle) ShowMultiDropdown(self, items, onToggle) end
    return b
end

ns.SetBD             = SetBD
ns.MakePanel         = MakePanel
ns.MakeLabel         = MakeLabel
ns.MakeButton        = MakeButton
ns.MakeAccentButton  = MakeAccentButton
ns.MakeCheck         = MakeCheck
ns.MakeMultiDropdown = MakeMultiDropdown

-- -------------------------------------------------- --
--  Data access                                       --
-- -------------------------------------------------- --

local englishClass = select(2, UnitClass("player"))

local function CurrentSpecIndex()
    return C_SpecializationInfo.GetSpecialization()
end

-- List of TLEX "config" entries (skips group rows) for the given spec index.
-- Each entry: { name, icon, text }
function ns.GetLoadoutsForSpec(specIndex)
    local out = {}
    local tbl = _G.TalentLoadoutEx
        and _G.TalentLoadoutEx[englishClass]
        and _G.TalentLoadoutEx[englishClass][specIndex]
    if not tbl then return out end
    for _, data in ipairs(tbl) do
        if data.text and not data.isLegacy then
            table.insert(out, data)
        end
    end
    return out
end

-- Force Blizzard_PlayerSpells to load so TLEX's InitFrame runs and populates
-- loadedDataList. Without this, TLX.GetLoadedData() returns nil until the user
-- opens the talents pane for the first time. Blizzard_PlayerSpells is LoadOnDemand
-- and TLEX registers InitFrame against its ADDON_LOADED event; LoadAddOn is
-- synchronous, so once it returns TLEX has already wired up loadedDataList.
local tlexPrimed = false
local function PrimeTLEX()
    if tlexPrimed then return end
    tlexPrimed = true
    if not C_AddOns.IsAddOnLoaded("Blizzard_PlayerSpells") then
        C_AddOns.LoadAddOn("Blizzard_PlayerSpells")
    end
end

-- Build the current active-talents export string ourselves, the same way
-- Blizzard's talent frame "Export" button does. Using TLEX's TLX.GetLoadedData
-- is unreliable at login because TLEX populates its loadedDataList via
-- UpdateScrollBox → GetExportText, and GetExportText returns nil when the
-- talent tree info hasn't finished loading from the server yet. Computing the
-- string directly from the talents frame mixin methods is independent of that
-- timing — as long as Blizzard_PlayerSpells is loaded and the tree data is
-- ready, this returns the real string.
local function GetCurrentExportString()
    local frame = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    if not frame or not frame.WriteLoadoutHeader then return nil end

    -- frame:GetTreeInfo() is nil until the talents pane has been opened once,
    -- so derive treeID from the config directly instead of the frame.
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return nil end

    local configInfo = C_Traits.GetConfigInfo(configID)
    local treeID = configInfo and configInfo.treeIDs and configInfo.treeIDs[1]
    if not treeID then return nil end

    local treeHash = C_Traits.GetTreeHash(treeID)
    if not treeHash then return nil end

    local specID  = PlayerUtil.GetCurrentSpecID()
    local version = C_Traits.GetLoadoutSerializationVersion()
    if not specID or not version then return nil end

    local ok, stream = pcall(ExportUtil.MakeExportDataStream)
    if not ok or not stream then return nil end

    local ok2 = pcall(frame.WriteLoadoutHeader,  frame, stream, version, specID, treeHash)
    local ok3 = pcall(frame.WriteLoadoutContent, frame, stream, configID, treeID)
    if not ok2 or not ok3 then return nil end

    return stream:GetExportString()
end

-- Parse a Blizzard export string into a dict keyed by selectionEntryID.
-- Mirrors TLEX's GetLoadoutEntryInfo pipeline:
--   ReadLoadoutHeader → validate (allow empty hash, require matching hash otherwise)
--   ReadLoadoutContent(stream, treeID)
--   ConvertToImportLoadoutEntryInfo(configID, treeID, loadoutContent)
--     → entries with {selectionEntryID, ranksGranted, ranksPurchased, nodeID}
-- The converted entries are what Blizzard's import logic actually uses; the
-- raw bit-level output of ReadLoadoutContent won't compare correctly across
-- strings that encode equivalent selections differently.
local parsedCache = {}
local function ParseTalentText(text)
    if not text then return nil end
    if parsedCache[text] then return parsedCache[text] end

    local frame = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    if not frame or not frame.ReadLoadoutHeader or not frame.ReadLoadoutContent
       or not frame.ConvertToImportLoadoutEntryInfo then
        return nil
    end

    local specID  = PlayerUtil.GetCurrentSpecID()
    local treeID  = specID and C_ClassTalents.GetTraitTreeForSpec(specID)
    local configID = C_ClassTalents.GetActiveConfigID()
    if not treeID or not configID then return nil end

    local stream = ExportUtil.MakeImportDataStream(text)
    if not stream or not stream.currentRemainingValue then return nil end

    local ok, hv, _, hSpecID, hTreeHash = pcall(frame.ReadLoadoutHeader, frame, stream)
    if not ok or not hv then return nil end
    if hSpecID ~= specID then return nil end
    if not frame:IsHashEmpty(hTreeHash)
       and not frame:HashEquals(hTreeHash, C_Traits.GetTreeHash(treeID)) then
        return nil
    end

    local okC, loadoutContent = pcall(frame.ReadLoadoutContent, frame, stream, treeID)
    if not okC or not loadoutContent then return nil end

    local okE, entryInfo =
        pcall(frame.ConvertToImportLoadoutEntryInfo, frame, configID, treeID, loadoutContent)
    if not okE or not entryInfo then return nil end

    local dict = {}
    for _, e in ipairs(entryInfo) do
        if e.selectionEntryID then
            dict[e.selectionEntryID] = e
        end
    end
    parsedCache[text] = dict
    return dict
end

-- Memoize the resolved loadout name for the duration of one "state window".
-- CurrentLoadoutName is hit from several paths — Refresh, RefreshSettingsActive,
-- the retry ticker's condition check, the alert ticker — so a single zone event
-- can drive a dozen lookups, each running the whole serialize-and-compare
-- pipeline. Caching positive results keeps subsequent lookups O(1) until the
-- next real talent/spec change. We don't cache nils so the retry loop can
-- keep polling while data is still arriving from the server.
local cachedName

local function InvalidateParseCache()
    parsedCache = {}
    cachedName  = nil
end
ns.InvalidateParseCache = InvalidateParseCache

function ns.CurrentLoadoutName()
    if cachedName then return cachedName end

    -- Fast path: TLEX's own API, if its loadedDataList is populated.
    if _G.TLX and _G.TLX.GetLoadedData then
        local data = _G.TLX.GetLoadedData()
        if data and data.name then
            cachedName = data.name
            return data.name
        end
    end

    local specIdx = C_SpecializationInfo.GetSpecialization()
    if not specIdx then return nil end

    local current = GetCurrentExportString()
    if not current then return nil end

    local loadouts = ns.GetLoadoutsForSpec(specIdx)

    -- Exact string match first — cheap and catches native-exported strings.
    for _, data in ipairs(loadouts) do
        if data.text == current then
            cachedName = data.name
            return data.name
        end
    end

    -- Fuzzy fallback: parse current once and compare against each saved parse.
    -- Prior versions re-serialized the active config and re-parsed it per
    -- loadout, turning one lookup into N+1 full serializations.
    local curDict = ParseTalentText(current)
    if not curDict then return nil end

    for _, data in ipairs(loadouts) do
        local savedDict = ParseTalentText(data.text)
        if savedDict then
            local matches = true
            for selID, savedEntry in pairs(savedDict) do
                local curEntry = curDict[selID]
                if not curEntry
                   or savedEntry.ranksGranted  ~= curEntry.ranksGranted
                   or savedEntry.ranksPurchased ~= curEntry.ranksPurchased then
                    matches = false
                    break
                end
            end
            if matches then
                cachedName = data.name
                return data.name
            end
        end
    end
    return nil
end

function ns.DumpDebug()
    local P = function(...) print("|cff9999ff[TLEXHelper]|r", ...) end

    P("Class:", englishClass, " Spec idx:", tostring(C_SpecializationInfo.GetSpecialization()))
    P("Blizzard_PlayerSpells loaded?", tostring(C_AddOns.IsAddOnLoaded("Blizzard_PlayerSpells")))
    P("PlayerSpellsFrame:", PlayerSpellsFrame and "yes" or "nil",
      " TalentsFrame:", (PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame) and "yes" or "nil")

    local frame = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    if frame then
        P("  GetConfigID:", frame.GetConfigID and tostring(frame:GetConfigID()) or "method missing")
        local treeInfo = frame.GetTreeInfo and frame:GetTreeInfo()
        P("  TreeInfo.ID:", treeInfo and tostring(treeInfo.ID) or "nil")
        if treeInfo and treeInfo.ID then
            P("  TreeHash:", C_Traits.GetTreeHash(treeInfo.ID) and "present" or "nil")
        end
        P("  WriteLoadoutHeader method:",  type(frame.WriteLoadoutHeader))
        P("  WriteLoadoutContent method:", type(frame.WriteLoadoutContent))
    end

    -- Config-derived tree ID (doesn't depend on frame state)
    local cfgID = C_ClassTalents.GetActiveConfigID()
    if cfgID then
        local cfgInfo = C_Traits.GetConfigInfo(cfgID)
        local treeID = cfgInfo and cfgInfo.treeIDs and cfgInfo.treeIDs[1]
        P("  ConfigInfo treeID:", tostring(treeID))
        if treeID then
            P("  C_Traits.GetTreeHash(treeID):", C_Traits.GetTreeHash(treeID) and "present" or "nil")
        end
    end

    P("C_ClassTalents.GetActiveConfigID:", tostring(C_ClassTalents.GetActiveConfigID()))
    P("PlayerUtil.GetCurrentSpecID:",      tostring(PlayerUtil.GetCurrentSpecID()))
    P("C_Traits.GetLoadoutSerializationVersion:", tostring(C_Traits.GetLoadoutSerializationVersion()))

    local current = GetCurrentExportString()
    P("GetCurrentExportString:", current and ("len=" .. #current) or "nil")
    if current then P("  CURRENT:", current) end

    if _G.TLX and _G.TLX.GetLoadedData then
        local data = _G.TLX.GetLoadedData()
        P("TLX.GetLoadedData:", data and ("name=" .. tostring(data.name)) or "nil")
    else
        P("TLX API: missing")
    end

    local specIdx = C_SpecializationInfo.GetSpecialization()
    local loadouts = specIdx and ns.GetLoadoutsForSpec(specIdx) or {}
    P("Saved loadouts for this spec:", #loadouts)

    local function dictSize(d) local n = 0; if d then for _ in pairs(d) do n = n + 1 end end; return n end

    local curDict = current and ParseTalentText(current) or nil
    P("Parsed current entries:", curDict and dictSize(curDict) or "nil")

    for i, data in ipairs(loadouts) do
        local exact = current and (data.text == current)
        local savedDict = ParseTalentText(data.text)
        local fuzzy = false
        local mismatchID, mismatchSaved, mismatchCur
        if curDict and savedDict then
            fuzzy = true
            for selID, savedEntry in pairs(savedDict) do
                local curEntry = curDict[selID]
                if not curEntry
                   or savedEntry.ranksGranted  ~= curEntry.ranksGranted
                   or savedEntry.ranksPurchased ~= curEntry.ranksPurchased then
                    fuzzy = false
                    mismatchID, mismatchSaved, mismatchCur = selID, savedEntry, curEntry
                    break
                end
            end
        end
        local tag = exact and " <== EXACT" or (fuzzy and " <== FUZZY" or "")
        P(string.format("  [%d] %s (len=%d, entries=%s)%s",
            i, tostring(data.name), #(data.text or ""),
            savedDict and tostring(dictSize(savedDict)) or "nil", tag))
        if not savedDict then
            P("    (could not parse saved text)")
        elseif mismatchID then
            P(string.format("    first diff @ selectionEntryID %s:", tostring(mismatchID)))
            P(string.format("      saved:   ranksGranted=%s ranksPurchased=%s nodeID=%s",
                tostring(mismatchSaved.ranksGranted),
                tostring(mismatchSaved.ranksPurchased),
                tostring(mismatchSaved.nodeID)))
            if mismatchCur then
                P(string.format("      current: ranksGranted=%s ranksPurchased=%s nodeID=%s",
                    tostring(mismatchCur.ranksGranted),
                    tostring(mismatchCur.ranksPurchased),
                    tostring(mismatchCur.nodeID)))
            else
                P("      current: (no entry with this selectionEntryID)")
            end
        end
    end
end

-- Per-character DB. Schema:
--   TLEXHelperDB.specs[specIndex] = { raid = {[name]=true}, mythic = {[name]=true} }
--   TLEXHelperDB.framePoint     = {point, "UIParent", relPoint, x, y}
--   TLEXHelperDB.debugFrame     = bool (shows the TLEX-status debug panel)
local function EnsureDB()
    TLEXHelperDB = TLEXHelperDB or {}
    TLEXHelperDB.specs = TLEXHelperDB.specs or {}
    return TLEXHelperDB
end

function ns.GetSpecConfig(specIndex)
    local db = EnsureDB()
    db.specs[specIndex] = db.specs[specIndex] or {}
    db.specs[specIndex].raid   = db.specs[specIndex].raid   or {}
    db.specs[specIndex].mythic = db.specs[specIndex].mythic or {}
    return db.specs[specIndex]
end

-- -------------------------------------------------- --
--  Status frame                                      --
-- -------------------------------------------------- --

local statusFrame, statusText, statusSub

local function BuildStatusFrame()
    if statusFrame then return statusFrame end
    local db = EnsureDB()

    statusFrame = CreateFrame("Frame", "TLEXHelperStatus", UIParent, "BackdropTemplate")
    SetBD(statusFrame, C_BG, C_BDR)
    statusFrame:SetSize(220, 44)
    statusFrame:SetMovable(true)
    statusFrame:EnableMouse(true)
    statusFrame:RegisterForDrag("LeftButton")
    statusFrame:SetClampedToScreen(true)

    if db.framePoint then
        statusFrame:SetPoint(unpack(db.framePoint))
    else
        statusFrame:SetPoint("TOP", UIParent, "TOP", 0, -200)
    end

    statusFrame:SetScript("OnDragStart", function(s) s:StartMoving() end)
    statusFrame:SetScript("OnDragStop",  function(s)
        s:StopMovingOrSizing()
        local p, _, rp, x, y = s:GetPoint(1)
        db.framePoint = { p, "UIParent", rp, x, y }
    end)

    statusText = MakeLabel(statusFrame, "TLEX: —", 13, C_TEXT)
    statusText:SetPoint("TOPLEFT", 8, -6)
    statusText:SetPoint("TOPRIGHT", -8, -6)
    statusText:SetJustifyH("LEFT")

    statusSub = MakeLabel(statusFrame, "", 11, C_DIM)
    statusSub:SetPoint("BOTTOMLEFT", 8, 6)
    statusSub:SetPoint("BOTTOMRIGHT", -8, 6)
    statusSub:SetJustifyH("LEFT")

    if not db.debugFrame then statusFrame:Hide() end
    return statusFrame
end

local function ZoneCategory()
    local _, instanceType = GetInstanceInfo()
    if instanceType == "raid"  then return "raid"   end
    if instanceType == "party" then return "mythic" end
    return nil
end

local function CategoryLabel(cat)
    if cat == "raid"   then return "Raid"    end
    if cat == "mythic" then return "Mythic+" end
    return "Open world"
end

local function Refresh()
    BuildStatusFrame()
    local name    = ns.CurrentLoadoutName()
    local specIdx = CurrentSpecIndex()
    local cat     = ZoneCategory()

    statusText:SetText("TLEX: " .. (name or "|cff888888(no loadout)|r"))

    local color = C_DIM
    local sub
    if cat and name and specIdx then
        local cfg = ns.GetSpecConfig(specIdx)
        local set = (cat == "raid") and cfg.raid or cfg.mythic
        if set[name] then
            color = C_OK
            sub = CategoryLabel(cat) .. " — OK"
        else
            color = C_WARN
            sub = CategoryLabel(cat) .. " — wrong loadout"
        end
    else
        sub = CategoryLabel(cat)
    end
    statusText:SetTextColor(unpack(color))
    statusSub:SetText(sub or "")
end

ns.Refresh = Refresh

-- Login / zone-entry races the server's talent sync: GetCurrentExportString
-- can return nil for a few seconds after PLAYER_ENTERING_WORLD, and TLEX's
-- cache is empty until either the talents pane is opened once or we manage
-- a successful lookup. Poll for up to ~15s after a trigger; stop as soon as
-- we get a name. Also update the settings label on every tick so it catches
-- up automatically once the data arrives.
local retryTicker
local function StartRefreshRetry()
    if retryTicker then retryTicker:Cancel() end
    local attempts = 0
    retryTicker = C_Timer.NewTicker(0.5, function(t)
        attempts = attempts + 1
        -- Refresh / RefreshSettingsActive both call CurrentLoadoutName; the
        -- in-function cache makes the later calls O(1). Resolve once up front
        -- to use as the stop condition too.
        local name = ns.CurrentLoadoutName()
        Refresh()
        if ns.RefreshSettingsActive then ns.RefreshSettingsActive() end
        if name then
            t:Cancel()
            retryTicker = nil
        elseif attempts >= 30 then
            t:Cancel()
            retryTicker = nil
            print("|cff9999ff[TLEXHelper]|r Your current talents don't match any saved TLEX loadout. That's fine if you've adjusted a build for this fight — run /tlxh debug if you expected a match.")
        end
    end)
end
ns.StartRefreshRetry = StartRefreshRetry

-- -------------------------------------------------- --
--  Instance-entry warning                            --
-- -------------------------------------------------- --

local lastWarnedKey = nil

local function CheckZone(force)
    local cat     = ZoneCategory()
    local specIdx = CurrentSpecIndex()
    if not cat or not specIdx then
        lastWarnedKey = nil
        return
    end

    local name = ns.CurrentLoadoutName()
    local cfg  = ns.GetSpecConfig(specIdx)
    local set  = (cat == "raid") and cfg.raid or cfg.mythic

    local zoneID = select(8, GetInstanceInfo())
    local key = string.format("%s|%s|%s|%s", tostring(zoneID), tostring(cat), tostring(specIdx), tostring(name))
    if not force and key == lastWarnedKey then return end
    lastWarnedKey = key

    if not name then
        print("|cff9999ffTLEXHelper:|r You are in " .. CategoryLabel(cat)
            .. " content but no TLEX loadout is active.")
        if ns.ShowWrongSpecAlert then ns.ShowWrongSpecAlert() end
        return
    end

    if not set[name] then
        print(string.format(
            "|cff9999ffTLEXHelper:|r Current loadout |cff00ccff%s|r is not marked as %s for this spec.",
            name, CategoryLabel(cat)))
        if ns.ShowWrongSpecAlert then ns.ShowWrongSpecAlert() end
    end
end

ns.CheckZone = CheckZone

-- -------------------------------------------------- --
--  Wrong-spec alert dialog                           --
-- -------------------------------------------------- --

---@diagnostic disable-next-line: unused-local
local alertDlg, alertTicker, alertSubLabel  -- alertSubLabel assigned in BuildAlertDialog, read by RefreshAlertSub

local function CurrentIsCorrectForZone()
    local cat = ZoneCategory()
    if not cat then return true end  -- no instance, nothing to be wrong about

    local specIdx = CurrentSpecIndex()
    local name    = ns.CurrentLoadoutName()
    if not specIdx or not name then return false end

    local cfg = ns.GetSpecConfig(specIdx)
    local set = (cat == "raid") and cfg.raid or cfg.mythic
    return set[name] and true or false
end


local function BuildAlertDialog()
    if alertDlg then return alertDlg end

    alertDlg = CreateFrame("Frame", "TLEXHelperAlert", UIParent, "BackdropTemplate")
    SetBD(alertDlg, C_BG, C_BDR)
    alertDlg:SetSize(460, 200)
    alertDlg:SetFrameStrata("DIALOG")
    alertDlg:EnableMouse(true)
    alertDlg:Hide()

    local msg = alertDlg:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    msg:SetFont(STANDARD_TEXT_FONT, 36, "THICKOUTLINE")
    msg:SetPoint("TOP", 0, -28)
    msg:SetPoint("LEFT",  20, 0)
    msg:SetPoint("RIGHT", -20, 0)
    msg:SetText("WRONG SPEC IDIOT")
    msg:SetTextColor(unpack(C_WARN))
    msg:SetJustifyH("CENTER")

    alertSubLabel = alertDlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    alertSubLabel:SetFont(STANDARD_TEXT_FONT, 14, "")
    alertSubLabel:SetPoint("TOP", msg, "BOTTOM", 0, -18)
    alertSubLabel:SetPoint("LEFT",  20, 0)
    alertSubLabel:SetPoint("RIGHT", -20, 0)
    alertSubLabel:SetJustifyH("CENTER")
    alertSubLabel:SetTextColor(unpack(C_TEXT))

    local ok = MakeAccentButton(alertDlg, "OK", 100, 30)
    ok:SetPoint("BOTTOM", 0, 20)
    ok:SetScript("OnClick", function() alertDlg:Hide() end)

    -- Apply has a cast time; the ApplyButton state is unreliable as a signal
    -- because it disables at click-time, not commit-time. TRAIT_CONFIG_UPDATED
    -- fires when the commit cast actually completes — that's when the node
    -- state genuinely flips. Auto-close only after that event if the new
    -- state matches.
    alertDlg:RegisterEvent("TRAIT_CONFIG_UPDATED")
    alertDlg:SetScript("OnEvent", function(self, event)
        if event == "TRAIT_CONFIG_UPDATED" then
            ns.InvalidateParseCache()
            ns.RefreshAlertSub()
            if CurrentIsCorrectForZone() then self:Hide() end
        end
    end)

    alertDlg:SetScript("OnHide", function()
        if alertTicker then
            alertTicker:Cancel()
            alertTicker = nil
        end
    end)

    return alertDlg
end

function ns.RefreshAlertSub()
    if not alertSubLabel then return end
    local name = ns.CurrentLoadoutName()
    if name then
        alertSubLabel:SetText("Current: |cff00ccff" .. name .. "|r")
    else
        alertSubLabel:SetText("Current: |cff888888(no loadout)|r")
    end
end

local function ShowWrongSpecAlert()
    local dlg = BuildAlertDialog()
    ns.RefreshAlertSub()
    -- Always reopen pinned above screen center, regardless of any prior state.
    dlg:ClearAllPoints()
    dlg:SetPoint("BOTTOM", UIParent, "CENTER", 0, 0)
    dlg:Show()

    -- Backup ticker: closes the dialog if the player leaves the instance
    -- altogether (the event path only covers actual commits).
    if alertTicker then alertTicker:Cancel() end
    alertTicker = C_Timer.NewTicker(1, function()
        if not ZoneCategory() then dlg:Hide() end
    end)
end
ns.ShowWrongSpecAlert = ShowWrongSpecAlert

-- -------------------------------------------------- --
--  Events                                            --
-- -------------------------------------------------- --

local ef = CreateFrame("Frame")
ef:RegisterEvent("PLAYER_LOGIN")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ef:RegisterEvent("TRAIT_CONFIG_UPDATED")
ef:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ef:RegisterEvent("CONFIG_COMMIT_FAILED")

ef:SetScript("OnEvent", function(_, event)
    EnsureDB()
    if event == "PLAYER_LOGIN" then
        PrimeTLEX()
        BuildStatusFrame()
        Refresh()
        StartRefreshRetry()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        PrimeTLEX()
        StartRefreshRetry()
        -- TLEX applies loadouts via a timer after import; give it a beat before checking.
        C_Timer.After(0.5, function() Refresh(); CheckZone(false) end)
    elseif event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        ns.InvalidateParseCache()
        C_Timer.After(0.3, Refresh)
    else
        C_Timer.After(0.3, Refresh)
    end
end)

-- -------------------------------------------------- --
--  Slash                                             --
-- -------------------------------------------------- --

SLASH_TLEXHELPER1 = "/tlxh"
SlashCmdList.TLEXHELPER = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "show" then
        TLEXHelperDB.debugFrame = true
        BuildStatusFrame():Show()
    elseif msg == "hide" then
        TLEXHelperDB.debugFrame = false
        BuildStatusFrame():Hide()
    elseif msg == "status" then
        CheckZone(true)
    elseif msg == "debug" then
        ns.DumpDebug()
    elseif msg == "alert" then
        -- Manual trigger for styling/testing the dialog without zoning.
        ShowWrongSpecAlert()
    elseif msg == "" or msg == "config" or msg == "settings" then
        if ns.ToggleSettings then ns.ToggleSettings() end
    else
        print("|cff9999ffTLEXHelper:|r /tlxh [show|hide|status|config|debug|alert]")
    end
end

-- -------------------------------------------------- --
--  Addon Compartment + Blizzard Settings panel       --
-- -------------------------------------------------- --

-- Called by the TOC's AddonCompartmentFunc directive when the player clicks
-- the TLEX Helper icon in the top-of-minimap addon compartment.
function TLEXHelper_OnCompartmentClick(_, _)
    if ns.ToggleSettings then ns.ToggleSettings() end
end

-- Shared parent category for all "leaky" addons in Interface > Options > AddOns.
-- First addon to load creates it and parks it on _G so sibling addons reuse it.
local function GetLeakyParentCategory()
    if _G.LeakyAddonsSettingsCategory then return _G.LeakyAddonsSettingsCategory end
    if not Settings or not Settings.RegisterVerticalLayoutCategory then return nil end

    local category = Settings.RegisterVerticalLayoutCategory("Leaky Addons")
    Settings.RegisterAddOnCategory(category)
    _G.LeakyAddonsSettingsCategory = category
    return category
end

local function RegisterSettingsSubcategory()
    local parent = GetLeakyParentCategory()
    if not parent or not Settings.RegisterCanvasLayoutSubcategory then return end

    local panel = CreateFrame("Frame")
    panel.name = "TLEX Helper"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("TLEX Helper")

    local blurb = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    blurb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    blurb:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    blurb:SetJustifyH("LEFT")
    blurb:SetText("Tag TLEX loadouts by instance type and get a nudge when you zone in on the wrong spec.")

    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -16)
    btn:SetSize(200, 26)
    btn:SetText("Open TLEX Helper")
    btn:SetScript("OnClick", function()
        if ns.ToggleSettings then ns.ToggleSettings() end
    end)

    Settings.RegisterCanvasLayoutSubcategory(parent, panel, "TLEX Helper")
end

-- Register after PLAYER_LOGIN so Settings and the shared category global are
-- both stable. Hook in via a one-shot frame rather than adding another branch
-- to the main event handler.
local regFrame = CreateFrame("Frame")
regFrame:RegisterEvent("PLAYER_LOGIN")
regFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    RegisterSettingsSubcategory()
end)
