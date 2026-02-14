local _, CdrLogger = ...
CdrLogger.LogWindow = CdrLogger.LogWindow or {}

-- In-memory log store (session only)
CdrLogger.Data = CdrLogger.Data or {}
CdrLogger.Data.log = {
    spells = {},
    items = {},
    buffs = {}
}

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
local WINDOW_WIDTH = 860
local WINDOW_HEIGHT = 480
local ROW_HEIGHT = 18
local HEADER_HEIGHT = 22
local TAB_NAMES = { "Spells", "Items", "Buffs" }
local TAB_KEYS  = { "spells", "items", "buffs" }

-- Column definitions per tab  { key, header, width, align }
local COLUMNS = {
    spells = {
        { key = "timestamp",  header = "Time",       width = 90,  align = "LEFT" },
        { key = "event",      header = "Event",      width = 110, align = "LEFT" },
        { key = "icon",       header = "",            width = 22,  align = "CENTER" },
        { key = "id",         header = "ID",          width = 55,  align = "RIGHT" },
        { key = "name",       header = "Name",        width = 130, align = "LEFT" },
        { key = "charges",    header = "Charges",     width = 60,  align = "CENTER" },
        { key = "prevRemain", header = "Prev Rem",    width = 75,  align = "RIGHT" },
        { key = "newRemain",  header = "New Rem",     width = 75,  align = "RIGHT" },
        { key = "delta",      header = "Delta",       width = 75,  align = "RIGHT" },
        { key = "pctReduce",  header = "% Reduce",    width = 75,  align = "RIGHT" },
    },
    items = {
        { key = "timestamp",  header = "Time",       width = 90,  align = "LEFT" },
        { key = "event",      header = "Event",      width = 110, align = "LEFT" },
        { key = "icon",       header = "",            width = 22,  align = "CENTER" },
        { key = "id",         header = "ID",          width = 55,  align = "RIGHT" },
        { key = "name",       header = "Name",        width = 130, align = "LEFT" },
        { key = "charges",    header = "Charges",     width = 60,  align = "CENTER" },
        { key = "prevRemain", header = "Prev Rem",    width = 75,  align = "RIGHT" },
        { key = "newRemain",  header = "New Rem",     width = 75,  align = "RIGHT" },
        { key = "delta",      header = "Delta",       width = 75,  align = "RIGHT" },
        { key = "pctReduce",  header = "% Reduce",    width = 75,  align = "RIGHT" },
    },
    buffs = {
        { key = "timestamp",  header = "Time",       width = 90,  align = "LEFT" },
        { key = "event",      header = "Event",      width = 100, align = "LEFT" },
        { key = "icon",       header = "",            width = 22,  align = "CENTER" },
        { key = "id",         header = "ID",          width = 55,  align = "RIGHT" },
        { key = "name",       header = "Name",        width = 130, align = "LEFT" },
        { key = "stacks",     header = "Stacks",      width = 80,  align = "CENTER" },
        { key = "duration",   header = "Duration",    width = 75,  align = "RIGHT" },
        { key = "remaining",  header = "Remaining",   width = 75,  align = "RIGHT" },
        { key = "delta",      header = "Delta",       width = 75,  align = "RIGHT" },
        { key = "pctInitial", header = "% of Init",   width = 75,  align = "RIGHT" },
    },
}

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local frame          -- main window frame
local activeTab = 1  -- index into TAB_KEYS
local sortColumn = "timestamp"
local sortAscending = true
local headerButtons = {}
local rows = {}
local scrollFrame
local scrollChild
local tabButtons = {}
local autoScroll = true
local exportFrame
local hScrollBar
local clipFrame
local headerInner
local filterEventSet = nil   -- nil = show all; {[eventStr]=true} = only those
local filterNameSet = nil     -- nil = show all; {[nameStr]=true} = only those
local eventDropdownBtn
local nameDropdownBtn
local filterClickOff
local RefreshDisplay         -- forward declaration (defined later)
local PopulateFilterMenu     -- forward declaration (defined later)

-- Per-tab state storage (filters + sort)
local tabState = {}
for _, key in ipairs(TAB_KEYS) do
    tabState[key] = { filterEventSet = nil, filterNameSet = nil, sortColumn = "timestamp", sortAscending = true }
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function GetActiveKey()
    return TAB_KEYS[activeTab]
end

local function GetActiveColumns()
    return COLUMNS[GetActiveKey()]
end

local function GetActiveData()
    return CdrLogger.Data.log[GetActiveKey()]
end

local function StripTextureString(iconStr)
    if iconStr == nil then return "" end
    -- Extract texture ID from "|T<id>:0|t"
    local id = iconStr:match("|T(.-):0|t")
    return id or ""
end

local function GetTotalColumnWidth()
    local cols = GetActiveColumns()
    local total = 0
    for _, colDef in ipairs(cols) do
        total = total + colDef.width
    end
    return total + 8
end

-- Known event types per tab (pre-populated; new logged events merge in)
local KNOWN_EVENTS = {
    spells = {
        "CAST", "CD CHANGE", "CHANNEL START", "CHANNEL STOP",
        "CHARGE GAIN", "CHARGE USE", "EMPOWER START", "EMPOWER STOP",
        "OFF CD", "ON CD", "TRACKING STOPPED",
    },
    items = {
        "CAST", "CD CHANGE", "CHANNEL START", "CHANNEL STOP",
        "CHARGE GAIN", "CHARGE USE", "EMPOWER START", "EMPOWER STOP",
        "OFF CD", "ON CD", "TRACKING STOPPED",
    },
    buffs = {
        "CAST", "CHANGE", "CHANNEL START", "CHANNEL STOP",
        "EMPOWER START", "EMPOWER STOP",
        "GAINED", "LOST", "TRACKING STOPPED",
    },
}

local function GetKnownEvents()
    local key = GetActiveKey()
    local known = KNOWN_EVENTS[key] or {}
    local seen = {}
    local result = {}
    -- Start with the pre-defined known events
    for _, ev in ipairs(known) do
        if not seen[ev] then
            seen[ev] = true
            result[#result + 1] = ev
        end
    end
    -- Merge any new events that appeared in logged data
    local data = GetActiveData()
    for _, entry in ipairs(data) do
        local ev = entry.event
        if ev and ev ~= "" and not seen[ev] then
            seen[ev] = true
            result[#result + 1] = ev
        end
    end
    table.sort(result)
    return result
end

local function GetTrackedNames()
    local key = GetActiveKey()
    local tracked = CdrLogger.Data.tracked and CdrLogger.Data.tracked[key] or {}
    local seen = {}
    local result = {}
    -- Names from tracked entries (objects with .name and .id)
    for id, obj in pairs(tracked) do
        local n = obj.name
        if n and n ~= "" and not seen[n] then
            seen[n] = true
            local rawIcon = obj.icon and obj.icon:match("|T(.-):0|t") or nil
            result[#result + 1] = { display = n .. " (" .. id .. ")", value = n, tracked = true, iconId = rawIcon }
        end
    end
    -- Merge any names from logged data not already covered
    local data = GetActiveData()
    for _, entry in ipairs(data) do
        local n = entry.name
        if n and n ~= "" and not seen[n] then
            seen[n] = true
            local idStr = entry.id and tostring(entry.id) or "?"
            local rawIcon = entry.iconId and entry.iconId ~= "" and entry.iconId or nil
            result[#result + 1] = { display = n .. " (" .. idStr .. ")", value = n, tracked = false, iconId = rawIcon }
        end
    end
    -- Sort tracked first, then non-tracked, alphabetically within each group
    local trackedResults = {}
    local otherResults = {}
    for _, item in ipairs(result) do
        if item.tracked then
            trackedResults[#trackedResults + 1] = item
        else
            otherResults[#otherResults + 1] = item
        end
    end
    table.sort(trackedResults, function(a, b) return a.display < b.display end)
    table.sort(otherResults, function(a, b) return a.display < b.display end)
    result = {}
    for _, item in ipairs(trackedResults) do result[#result + 1] = item end
    for _, item in ipairs(otherResults) do result[#result + 1] = item end
    return result
end
local function GetTrackedNameSet()
    local key = GetActiveKey()
    local tracked = CdrLogger.Data.tracked and CdrLogger.Data.tracked[key] or {}
    local nameSet = {}
    for _, obj in pairs(tracked) do
        if obj.name and obj.name ~= "" then
            nameSet[obj.name] = true
        end
    end
    return nameSet
end

local function PassesFilters(entry)
    if filterEventSet and not filterEventSet[entry.event or ""] then
        return false
    end
    if filterNameSet and not filterNameSet[entry.name or ""] then
        return false
    end
    return true
end

----------------------------------------------------------------------
-- Filter dropdown system
----------------------------------------------------------------------
local FILTER_ROW_H = 20
local FILTER_MENU_WIDTH = 200

local function DismissMenus()
    if eventDropdownBtn and eventDropdownBtn.menu then eventDropdownBtn.menu:Hide() end
    if nameDropdownBtn and nameDropdownBtn.menu then nameDropdownBtn.menu:Hide() end
    if filterClickOff then filterClickOff:Hide() end
end

local function UpdateDropdownLabel(btn, labelPrefix, filterSet)
    if not btn or not btn.label then return end
    if filterSet == nil then
        btn.label:SetText(labelPrefix .. ": All")
    else
        local count = 0
        for _ in pairs(filterSet) do count = count + 1 end
        btn.label:SetText(labelPrefix .. ": (" .. count .. ")")
    end
end

local function CreateFilterDropdownButton(parent, labelPrefix, getOptionsFunc, getCurrentFilterFunc, setFilterFunc, getTrackedSetFunc)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(155, 20)
    btn:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 6, 0)
    label:SetPoint("RIGHT", -16, 0)
    label:SetJustifyH("LEFT")
    btn.label = label
    UpdateDropdownLabel(btn, labelPrefix, nil)

    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(8, 8)
    arrow:SetPoint("RIGHT", -4, 0)
    arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")

    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    menu:SetFrameStrata("TOOLTIP")
    menu:SetClampedToScreen(true)
    menu:Hide()
    menu.checkRows = {}

    local menuScroll = CreateFrame("ScrollFrame", nil, menu, "UIPanelScrollFrameTemplate")
    menuScroll:SetPoint("TOPLEFT", 6, -6)
    menuScroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local menuChild = CreateFrame("Frame", nil, menuScroll)
    menuChild:SetWidth(FILTER_MENU_WIDTH)
    menuChild:SetHeight(1)
    menuScroll:SetScrollChild(menuChild)

    menu.scrollFrame = menuScroll
    menu.scrollChild = menuChild
    btn.menu = menu

    btn:SetScript("OnClick", function()
        if menu:IsShown() then
            DismissMenus()
        else
            DismissMenus()
            local options = getOptionsFunc()
            local currentFilter = getCurrentFilterFunc()
            local trackedSet = getTrackedSetFunc and getTrackedSetFunc() or nil
            PopulateFilterMenu(btn, options, currentFilter, setFilterFunc, labelPrefix, trackedSet)

            if not filterClickOff then
                filterClickOff = CreateFrame("Button", nil, UIParent)
                filterClickOff:SetAllPoints(UIParent)
                filterClickOff:SetFrameStrata("TOOLTIP")
                filterClickOff:SetScript("OnClick", DismissMenus)
            end
            filterClickOff:Show()
            filterClickOff:SetFrameLevel(menu:GetFrameLevel() - 1)

            menu:Show()
            menu:Raise()
        end
    end)

    btn:SetScript("OnEnter", function()
        btn:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end)
    btn:SetScript("OnLeave", function()
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end)

    return btn
end

----------------------------------------------------------------------
-- Sorting
----------------------------------------------------------------------
local function SortData(data, col, asc)
    local sorted = {}
    for i, v in ipairs(data) do
        sorted[i] = v
    end
    table.sort(sorted, function(a, b)
        local va = a[col]
        local vb = b[col]
        if va == nil then va = "" end
        if vb == nil then vb = "" end
        -- Attempt numeric comparison
        local na, nb = tonumber(va), tonumber(vb)
        if na and nb then
            if asc then return na < nb else return na > nb end
        end
        -- String comparison
        va = tostring(va)
        vb = tostring(vb)
        if asc then return va < vb else return va > vb end
    end)
    return sorted
end

----------------------------------------------------------------------
-- Row pool
----------------------------------------------------------------------
local function EnsureRows(count)
    local cols = GetActiveColumns()
    for i = #rows + 1, count do
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetHeight(ROW_HEIGHT)
        row.cells = {}
        row.textures = {}

        -- Alternating background
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        row.bg = bg

        for c, colDef in ipairs(cols) do
            if colDef.key == "icon" then
                local tex = row:CreateTexture(nil, "ARTWORK")
                tex:SetSize(16, 16)
                row.textures[c] = tex
                row.cells[c] = nil -- no fontstring for icon
            else
                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetJustifyH(colDef.align)
                fs:SetWordWrap(false)
                row.cells[c] = fs
            end
        end
        rows[i] = row
    end
end

local function LayoutRow(row, index)
    local cols = GetActiveColumns()
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)

    -- Alternate color
    if index % 2 == 0 then
        row.bg:SetColorTexture(1, 1, 1, 0.04)
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
    end

    local xOff = 4
    for c, colDef in ipairs(cols) do
        if colDef.key == "icon" then
            local tex = row.textures[c]
            if tex then
                tex:ClearAllPoints()
                tex:SetPoint("LEFT", row, "LEFT", xOff + 2, 0)
            end
        else
            local fs = row.cells[c]
            if fs then
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", row, "LEFT", xOff + 2, 0)
                fs:SetWidth(colDef.width - 4)
            end
        end
        xOff = xOff + colDef.width
    end
end

----------------------------------------------------------------------
-- Refresh display
----------------------------------------------------------------------
RefreshDisplay = function()
    if not frame or not frame:IsShown() then return end

    local data = GetActiveData()
    local cols = GetActiveColumns()

    -- Apply active filters
    local filtered = {}
    for _, entry in ipairs(data) do
        if PassesFilters(entry) then
            filtered[#filtered + 1] = entry
        end
    end

    local sorted = SortData(filtered, sortColumn, sortAscending)

    -- Ensure enough rows
    EnsureRows(#sorted)

    -- Hide all rows first
    for _, row in ipairs(rows) do
        row:Hide()
    end

    -- Populate
    local trackedNameSet = GetTrackedNameSet()
    for i, entry in ipairs(sorted) do
        local row = rows[i]
        LayoutRow(row, i)

        local isTrackedEntry = trackedNameSet[entry.name or ""] == true

        for c, colDef in ipairs(cols) do
            if colDef.key == "icon" then
                local tex = row.textures[c]
                if tex then
                    local iconId = entry.iconId
                    if iconId and iconId ~= "" then
                        tex:SetTexture(tonumber(iconId) or iconId)
                        tex:Show()
                    else
                        tex:Hide()
                    end
                end
            else
                local fs = row.cells[c]
                if fs then
                    local val = entry[colDef.key]
                    fs:SetText(val ~= nil and tostring(val) or "")
                    if isTrackedEntry then
                        fs:SetTextColor(0.2, 0.9, 0.2)
                    else
                        fs:SetTextColor(1, 1, 1)
                    end
                end
            end
        end
        row:Show()
    end

    -- Update scroll child height
    scrollChild:SetHeight(math.max(1, #sorted * ROW_HEIGHT))

    -- Update content widths
    local contentWidth = GetTotalColumnWidth()
    if clipFrame then
        local visibleWidth = math.max(1, clipFrame:GetWidth() - 22)
        scrollChild:SetWidth(math.max(contentWidth, visibleWidth))
    end
    if headerInner then
        headerInner:SetWidth(contentWidth)
    end

    -- Update horizontal scrollbar
    if hScrollBar and clipFrame then
        local visibleWidth = clipFrame:GetWidth() - 22
        if contentWidth > visibleWidth and visibleWidth > 0 then
            hScrollBar:SetMinMaxValues(0, contentWidth - visibleWidth)
            hScrollBar:Show()
        else
            hScrollBar:SetMinMaxValues(0, 0)
            hScrollBar:SetValue(0)
            hScrollBar:Hide()
            if scrollFrame then
                scrollFrame:SetHorizontalScroll(0)
            end
            if headerInner then
                headerInner:ClearAllPoints()
                headerInner:SetPoint("TOPLEFT", clipFrame, "TOPLEFT", 0, 0)
            end
        end
    end

    -- Update row count
    if frame and frame.rowCountLabel then
        if #filtered < #data then
            frame.rowCountLabel:SetText(#sorted .. " of " .. #data .. " entries")
        else
            frame.rowCountLabel:SetText(#sorted .. " entries")
        end
    end

    -- Auto-scroll to bottom
    if autoScroll and scrollFrame then
        C_Timer.After(0, function()
            scrollFrame:SetVerticalScroll(scrollFrame:GetVerticalScrollRange())
        end)
    end
end

----------------------------------------------------------------------
-- PopulateFilterMenu (defined after RefreshDisplay)
----------------------------------------------------------------------
PopulateFilterMenu = function(btn, options, filterSet, setFilterFunc, labelPrefix, trackedSet)
    local menu = btn.menu
    local child = menu.scrollChild

    for _, chk in ipairs(menu.checkRows) do
        chk:Hide()
    end

    -- Extra header row for "(Tracked)" if we have a trackedSet
    local hasTrackedRow = (trackedSet ~= nil and next(trackedSet) ~= nil)
    local headerRows = hasTrackedRow and 2 or 1  -- (All) + optionally (Tracked)
    local totalRows = #options + headerRows
    local SEP_HEIGHT = 6
    -- Count separators: 1 below headers, +1 between tracked and non-tracked groups if applicable
    local trackedOptionCount = 0
    local hasNonTracked = false
    if hasTrackedRow then
        for _, opt in ipairs(options) do
            if type(opt) == "table" and opt.tracked then
                trackedOptionCount = trackedOptionCount + 1
            else
                hasNonTracked = true
            end
        end
    end
    local hasGroupSep = hasTrackedRow and trackedOptionCount > 0 and hasNonTracked
    local sepCount = 1 + (hasGroupSep and 1 or 0)
    local totalHeight = totalRows * FILTER_ROW_H + sepCount * SEP_HEIGHT + 4
    local visibleHeight = math.min(totalHeight, 300)

    menu:SetSize(FILTER_MENU_WIDTH + 40, visibleHeight + 16)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)

    child:SetWidth(FILTER_MENU_WIDTH)
    child:SetHeight(math.max(1, totalHeight))

    -- Ensure enough checkbutton rows
    for i = #menu.checkRows + 1, totalRows do
        local chk = CreateFrame("CheckButton", nil, child)
        chk:SetSize(FILTER_ROW_H, FILTER_ROW_H)
        chk:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        chk:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        chk:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
        chk:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
        local lbl = chk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", chk, "RIGHT", 2, 0)
        lbl:SetWidth(FILTER_MENU_WIDTH - FILTER_ROW_H - 8)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        chk.text = lbl
        -- Icon texture (hidden by default, shown for name options with icons)
        local ico = chk:CreateTexture(nil, "ARTWORK")
        ico:SetSize(14, 14)
        ico:SetPoint("LEFT", chk, "RIGHT", 2, 0)
        ico:Hide()
        chk.icon = ico
        menu.checkRows[i] = chk
    end

    -- Row 1: "(All)" toggle
    local allChk = menu.checkRows[1]
    allChk.text:SetText("|cFFFFFF00(All)|r")
    -- Reset icon/text anchors for header rows
    if allChk.icon then allChk.icon:Hide() end
    allChk.text:ClearAllPoints()
    allChk.text:SetPoint("LEFT", allChk, "RIGHT", 2, 0)
    allChk.text:SetWidth(FILTER_MENU_WIDTH - FILTER_ROW_H - 8)
    allChk:SetChecked(filterSet == nil)
    allChk:ClearAllPoints()
    allChk:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -2)
    allChk:SetScript("OnClick", function(self)
        if self:GetChecked() then
            -- Checking "(All)": clear filter (show everything)
            setFilterFunc(nil)
            UpdateDropdownLabel(btn, labelPrefix, nil)
            PopulateFilterMenu(btn, options, nil, setFilterFunc, labelPrefix, trackedSet)
        else
            -- Unchecking "(All)": empty set (show nothing, all unchecked)
            local emptySet = {}
            setFilterFunc(emptySet)
            UpdateDropdownLabel(btn, labelPrefix, emptySet)
            PopulateFilterMenu(btn, options, emptySet, setFilterFunc, labelPrefix, trackedSet)
        end
        RefreshDisplay()
    end)
    allChk:Show()

    -- Separator line below last header row
    if not menu.separator then
        local sep = child:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetColorTexture(0.5, 0.5, 0.5, 0.6)
        menu.separator = sep
    end
    -- Position will be updated after header rows are laid out
    menu.separator:Hide()

    -- Row 2 (optional): "(Tracked)" toggle
    if hasTrackedRow then
        -- Ensure checkbutton row exists
        if not menu.checkRows[2] then
            local chk = CreateFrame("CheckButton", nil, child)
            chk:SetSize(FILTER_ROW_H, FILTER_ROW_H)
            chk:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
            chk:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
            chk:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
            chk:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
            local lbl = chk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lbl:SetPoint("LEFT", chk, "RIGHT", 2, 0)
            lbl:SetWidth(FILTER_MENU_WIDTH - FILTER_ROW_H - 8)
            lbl:SetJustifyH("LEFT")
            lbl:SetWordWrap(false)
            chk.text = lbl
            menu.checkRows[2] = chk
        end
        local trackedChk = menu.checkRows[2]
        trackedChk.text:SetText("|cFF00FF00(Tracked)|r")
        -- Reset icon/text anchors for header rows
        if trackedChk.icon then trackedChk.icon:Hide() end
        trackedChk.text:ClearAllPoints()
        trackedChk.text:SetPoint("LEFT", trackedChk, "RIGHT", 2, 0)
        trackedChk.text:SetWidth(FILTER_MENU_WIDTH - FILTER_ROW_H - 8)
        -- Determine if all tracked items are currently checked
        local allTrackedChecked = true
        if filterSet ~= nil then
            for tName in pairs(trackedSet) do
                if not filterSet[tName] then
                    allTrackedChecked = false
                    break
                end
            end
        end
        trackedChk:SetChecked(filterSet == nil or allTrackedChecked)
        trackedChk:ClearAllPoints()
        trackedChk:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -(1 * FILTER_ROW_H) - 2)
        trackedChk:SetScript("OnClick", function(self)
            local newSet = {}
            if self:GetChecked() then
                -- Enable all tracked names; preserve other existing checks
                if filterSet then
                    for k, v in pairs(filterSet) do newSet[k] = v end
                end
                for tName in pairs(trackedSet) do
                    newSet[tName] = true
                end
            else
                -- Disable all tracked names; preserve non-tracked checks
                if filterSet then
                    for k, v in pairs(filterSet) do
                        if not trackedSet[k] then
                            newSet[k] = v
                        end
                    end
                else
                    -- Was "All" before; need to add all non-tracked
                    for _, o in ipairs(options) do
                        local oValue = type(o) == "table" and o.value or o
                        if not trackedSet[oValue] then
                            newSet[oValue] = true
                        end
                    end
                end
            end
            -- Check if result is all or none
            local allChecked = true
            local noneChecked = true
            for _, o in ipairs(options) do
                local oValue = type(o) == "table" and o.value or o
                if newSet[oValue] then noneChecked = false else allChecked = false end
            end
            if allChecked or noneChecked then
                if allChecked then
                    setFilterFunc(nil)
                    UpdateDropdownLabel(btn, labelPrefix, nil)
                    PopulateFilterMenu(btn, options, nil, setFilterFunc, labelPrefix, trackedSet)
                else
                    setFilterFunc(newSet)
                    UpdateDropdownLabel(btn, labelPrefix, newSet)
                    PopulateFilterMenu(btn, options, newSet, setFilterFunc, labelPrefix, trackedSet)
                end
            else
                setFilterFunc(newSet)
                UpdateDropdownLabel(btn, labelPrefix, newSet)
                PopulateFilterMenu(btn, options, newSet, setFilterFunc, labelPrefix, trackedSet)
            end
            RefreshDisplay()
        end)
        trackedChk:Show()
    end

    -- Position separator below the last header row
    local sepY = -(headerRows * FILTER_ROW_H) - 2
    menu.separator:ClearAllPoints()
    menu.separator:SetPoint("TOPLEFT", child, "TOPLEFT", 4, sepY)
    menu.separator:SetPoint("RIGHT", child, "RIGHT", -4, 0)
    menu.separator:Show()
    local sepOffset = SEP_HEIGHT  -- extra vertical gap for first separator

    -- Second separator between tracked and non-tracked groups
    if not menu.separator2 then
        local sep2 = child:CreateTexture(nil, "ARTWORK")
        sep2:SetHeight(1)
        sep2:SetColorTexture(0.5, 0.5, 0.5, 0.6)
        menu.separator2 = sep2
    end
    menu.separator2:Hide()
    local sep2Offset = 0
    if hasGroupSep then
        local sep2Y = sepY - SEP_HEIGHT - (trackedOptionCount * FILTER_ROW_H)
        menu.separator2:ClearAllPoints()
        menu.separator2:SetPoint("TOPLEFT", child, "TOPLEFT", 4, sep2Y)
        menu.separator2:SetPoint("RIGHT", child, "RIGHT", -4, 0)
        menu.separator2:Show()
        sep2Offset = SEP_HEIGHT
    end

    -- Individual options
    for i, opt in ipairs(options) do
        local chk = menu.checkRows[i + headerRows]
        -- Support both plain string options and {display, value} tables
        local displayText = type(opt) == "table" and opt.display or opt
        local filterValue = type(opt) == "table" and opt.value or opt
        local isTracked = type(opt) == "table" and opt.tracked
        local optIconId = type(opt) == "table" and opt.iconId or nil

        -- Show icon if available, shift text label to the right
        if chk.icon then
            if optIconId and optIconId ~= "" then
                chk.icon:SetTexture(tonumber(optIconId) or optIconId)
                chk.icon:Show()
                chk.text:ClearAllPoints()
                chk.text:SetPoint("LEFT", chk.icon, "RIGHT", 3, 0)
                chk.text:SetWidth(FILTER_MENU_WIDTH - FILTER_ROW_H - 24)
            else
                chk.icon:Hide()
                chk.text:ClearAllPoints()
                chk.text:SetPoint("LEFT", chk, "RIGHT", 2, 0)
                chk.text:SetWidth(FILTER_MENU_WIDTH - FILTER_ROW_H - 8)
            end
        end

        if isTracked then
            chk.text:SetText("|cFF00FF00" .. displayText .. "|r")
        else
            chk.text:SetText(displayText)
        end
        chk:SetChecked(filterSet == nil or (filterSet[filterValue] == true))
        chk:ClearAllPoints()
        -- Account for separator(s): first sep always present; second sep after tracked group
        local extraSep = 0
        if hasGroupSep and not isTracked then
            extraSep = sep2Offset
        end
        chk:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -((i + headerRows - 1) * FILTER_ROW_H) - 2 - sepOffset - extraSep)
        chk:SetScript("OnClick", function(self)
            local newSet = {}
            local allChecked = true
            local noneChecked = true
            for j, o in ipairs(options) do
                local oValue = type(o) == "table" and o.value or o
                local isChecked
                if j == i then
                    isChecked = self:GetChecked()
                else
                    isChecked = menu.checkRows[j + headerRows]:GetChecked()
                end
                if isChecked then
                    newSet[oValue] = true
                    noneChecked = false
                else
                    allChecked = false
                end
            end
            if allChecked or noneChecked then
                setFilterFunc(nil)
                UpdateDropdownLabel(btn, labelPrefix, nil)
                PopulateFilterMenu(btn, options, nil, setFilterFunc, labelPrefix, trackedSet)
            else
                setFilterFunc(newSet)
                UpdateDropdownLabel(btn, labelPrefix, newSet)
                PopulateFilterMenu(btn, options, newSet, setFilterFunc, labelPrefix, trackedSet)
            end
            RefreshDisplay()
        end)
        chk:Show()
    end

    -- Hide unused rows
    for j = totalRows + 1, #menu.checkRows do
        if menu.checkRows[j] then menu.checkRows[j]:Hide() end
    end
end

----------------------------------------------------------------------
-- Header bar
----------------------------------------------------------------------
local function CreateHeaders(parent)
    -- Remove old headers
    for _, btn in ipairs(headerButtons) do
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(headerButtons)

    local cols = GetActiveColumns()
    local xOff = 0
    for c, colDef in ipairs(cols) do
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(colDef.width, HEADER_HEIGHT)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, 0)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", 4, 0)
        fs:SetPoint("RIGHT", -4, 0)
        fs:SetJustifyH(colDef.align)
        fs:SetText(colDef.header)

        -- Sort indicator (texture arrow)
        local arrow = btn:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(10, 10)
        arrow:SetPoint("RIGHT", -2, 0)
        arrow:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
        arrow:Hide()
        btn.arrow = arrow

        if sortColumn == colDef.key then
            arrow:SetTexture(sortAscending and "Interface\\Buttons\\Arrow-Up-Up" or "Interface\\Buttons\\Arrow-Down-Up")
            arrow:Show()
        end

        btn:SetScript("OnClick", function()
            if sortColumn == colDef.key then
                sortAscending = not sortAscending
            else
                sortColumn = colDef.key
                sortAscending = true
            end
            -- Update all arrows
            for _, hb in ipairs(headerButtons) do
                hb.arrow:Hide()
            end
            arrow:SetTexture(sortAscending and "Interface\\Buttons\\Arrow-Up-Up" or "Interface\\Buttons\\Arrow-Down-Up")
            arrow:Show()
            RefreshDisplay()
        end)

        btn:SetScript("OnEnter", function(self)
            bg:SetColorTexture(0.25, 0.25, 0.25, 0.9)
        end)
        btn:SetScript("OnLeave", function(self)
            bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
        end)

        headerButtons[c] = btn
        xOff = xOff + colDef.width
    end
end

----------------------------------------------------------------------
-- Tab switching
----------------------------------------------------------------------
local function SwitchTab(index)
    -- Save current tab state before switching
    local prevKey = TAB_KEYS[activeTab]
    if tabState[prevKey] then
        tabState[prevKey].filterEventSet = filterEventSet
        tabState[prevKey].filterNameSet = filterNameSet
        tabState[prevKey].sortColumn = sortColumn
        tabState[prevKey].sortAscending = sortAscending
    end

    activeTab = index

    -- Restore saved state for the new tab
    local newKey = TAB_KEYS[index]
    local saved = tabState[newKey]
    sortColumn = saved and saved.sortColumn or "timestamp"
    sortAscending = saved and saved.sortAscending ~= nil and saved.sortAscending or true
    filterEventSet = saved and saved.filterEventSet or nil
    filterNameSet = saved and saved.filterNameSet or nil

    if eventDropdownBtn then UpdateDropdownLabel(eventDropdownBtn, "Event", filterEventSet) end
    if nameDropdownBtn then UpdateDropdownLabel(nameDropdownBtn, "Name", filterNameSet) end
    DismissMenus()
    -- Invalidate row pool (columns may differ)
    for _, row in ipairs(rows) do
        row:Hide()
        row:SetParent(nil)
    end
    wipe(rows)

    -- Highlight active tab
    for i, tb in ipairs(tabButtons) do
        if i == index then
            tb:GetNormalTexture():SetVertexColor(0.3, 0.3, 0.6, 1)
            tb.label:SetTextColor(1, 1, 1)
        else
            tb:GetNormalTexture():SetVertexColor(0.15, 0.15, 0.15, 1)
            tb.label:SetTextColor(0.6, 0.6, 0.6)
        end
    end

    CreateHeaders(frame.headerInner or frame.headerContainer)
    if hScrollBar then
        hScrollBar:SetValue(0)
    end
    RefreshDisplay()
end

----------------------------------------------------------------------
-- Export frame
----------------------------------------------------------------------
local function BuildTSV()
    local cols = GetActiveColumns()
    local lines = {}
    -- Header
    local hdr = {}
    for _, colDef in ipairs(cols) do
        if colDef.key ~= "icon" then
            hdr[#hdr + 1] = colDef.header
        end
    end
    lines[#lines + 1] = table.concat(hdr, "\t")

    -- Data (respects active filters)
    local data = GetActiveData()
    local filtered = {}
    for _, entry in ipairs(data) do
        if PassesFilters(entry) then
            filtered[#filtered + 1] = entry
        end
    end
    local sorted = SortData(filtered, sortColumn, sortAscending)
    for _, entry in ipairs(sorted) do
        local vals = {}
        for _, colDef in ipairs(cols) do
            if colDef.key ~= "icon" then
                local v = entry[colDef.key]
                vals[#vals + 1] = v ~= nil and tostring(v) or ""
            end
        end
        lines[#lines + 1] = table.concat(vals, "\t")
    end
    return table.concat(lines, "\n")
end

local function ShowExport()
    if not exportFrame then
        exportFrame = CreateFrame("Frame", "CdrLoggerExportFrame", frame, "BackdropTemplate")
        exportFrame:SetSize(600, 400)
        exportFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        exportFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        exportFrame:SetFrameStrata("DIALOG")
        exportFrame:SetMovable(true)
        exportFrame:EnableMouse(true)
        exportFrame:RegisterForDrag("LeftButton")
        exportFrame:SetScript("OnDragStart", exportFrame.StartMoving)
        exportFrame:SetScript("OnDragStop", exportFrame.StopMovingOrSizing)

        local title = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -10)
        title:SetText("Export (Ctrl+A, Ctrl+C to copy)")

        local sf = CreateFrame("ScrollFrame", nil, exportFrame, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 12, -34)
        sf:SetPoint("BOTTOMRIGHT", -30, 40)

        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject("ChatFontNormal")
        eb:SetWidth(sf:GetWidth() or 540)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        sf:SetScrollChild(eb)
        exportFrame.editBox = eb

        local closeBtn = CreateFrame("Button", nil, exportFrame, "UIPanelButtonTemplate")
        closeBtn:SetSize(80, 22)
        closeBtn:SetPoint("BOTTOM", 0, 10)
        closeBtn:SetText("Close")
        closeBtn:SetScript("OnClick", function() exportFrame:Hide() end)
    end

    exportFrame.editBox:SetText(BuildTSV())
    exportFrame.editBox:HighlightText()
    exportFrame:Show()
end

----------------------------------------------------------------------
-- Build main frame
----------------------------------------------------------------------
local function CreateMainFrame()
    if frame then return end

    frame = CreateFrame("Frame", "CdrLoggerLogWindow", UIParent, "BackdropTemplate")
    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:EnableMouse(true)
    frame:SetResizeBounds(600, 300, 1400, 900)
    frame:SetClampedToScreen(true)
    frame.isSizing = false
    tinsert(UISpecialFrames, "CdrLoggerLogWindow") -- ESC to close

    -- Title bar drag region (only the top area is draggable for moving)
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(28)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    -- Title
    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 14, -10)
    titleText:SetText("Cooldown Reduction Logger")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Resize grip (bottom-right)
    local resizeBtn = CreateFrame("Button", nil, frame)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeBtn:EnableMouse(true)
    resizeBtn:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            frame:StartSizing("BOTTOMRIGHT")
            frame.isSizing = true
        end
    end)
    resizeBtn:SetScript("OnMouseUp", function(self, button)
        frame:StopMovingOrSizing()
        frame.isSizing = false
        RefreshDisplay()
    end)

    -- Tabs
    local tabY = -28
    for i, tabName in ipairs(TAB_NAMES) do
        local tb = CreateFrame("Button", nil, frame)
        tb:SetSize(80, 24)
        if i == 1 then
            tb:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, tabY)
        else
            tb:SetPoint("LEFT", tabButtons[i - 1], "RIGHT", 4, 0)
        end
        local tbBg = tb:CreateTexture(nil, "BACKGROUND")
        tbBg:SetAllPoints()
        tbBg:SetColorTexture(0.15, 0.15, 0.15, 1)
        tb:SetNormalTexture(tbBg)

        local label = tb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER")
        label:SetText(tabName)
        tb.label = label

        tb:SetScript("OnClick", function() SwitchTab(i) end)
        tabButtons[i] = tb
    end

    -- Filter dropdowns (same row as tabs, right-aligned)
    nameDropdownBtn = CreateFilterDropdownButton(
        frame, "Name",
        GetTrackedNames,
        function() return filterNameSet end,
        function(newSet) filterNameSet = newSet end,
        GetTrackedNameSet
    )
    nameDropdownBtn:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    nameDropdownBtn:ClearAllPoints()
    nameDropdownBtn:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    nameDropdownBtn:SetPoint("TOP", frame, "TOP", 0, tabY - 2)

    eventDropdownBtn = CreateFilterDropdownButton(
        frame, "Event",
        GetKnownEvents,
        function() return filterEventSet end,
        function(newSet) filterEventSet = newSet end
    )
    eventDropdownBtn:ClearAllPoints()
    eventDropdownBtn:SetPoint("RIGHT", nameDropdownBtn, "LEFT", -6, 0)
    eventDropdownBtn:SetPoint("TOP", frame, "TOP", 0, tabY - 2)

    -- Bottom toolbar
    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(70, 22)
    clearBtn:SetPoint("BOTTOMLEFT", 10, 8)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        wipe(CdrLogger.Data.log[GetActiveKey()])
        RefreshDisplay()
    end)

    local exportBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportBtn:SetSize(70, 22)
    exportBtn:SetPoint("LEFT", clearBtn, "RIGHT", 6, 0)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", ShowExport)

    -- Row count label (bottom right)
    local rowCountLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rowCountLabel:SetPoint("BOTTOMRIGHT", -24, 12)
    rowCountLabel:SetJustifyH("RIGHT")
    frame.rowCountLabel = rowCountLabel

    -- Clip frame: prevents headers and data from overflowing the window
    clipFrame = CreateFrame("Frame", nil, frame)
    clipFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, tabY - 28)
    clipFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 48)
    clipFrame:SetClipsChildren(true)

    -- Header inner frame (full content width, shifts with horizontal scroll)
    headerInner = CreateFrame("Frame", nil, clipFrame)
    headerInner:SetHeight(HEADER_HEIGHT)
    headerInner:SetPoint("TOPLEFT", clipFrame, "TOPLEFT", 0, 0)
    headerInner:SetWidth(GetTotalColumnWidth())
    frame.headerInner = headerInner

    -- Vertical scroll frame (inside clip, below header)
    scrollFrame = CreateFrame("ScrollFrame", "CdrLoggerScrollFrame", clipFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", clipFrame, "TOPLEFT", 0, -HEADER_HEIGHT)
    scrollFrame:SetPoint("BOTTOMRIGHT", clipFrame, "BOTTOMRIGHT", -22, 0)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(GetTotalColumnWidth())
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Horizontal scrollbar
    hScrollBar = CreateFrame("Slider", "CdrLoggerHScrollBar", frame)
    hScrollBar:SetHeight(14)
    hScrollBar:SetPoint("BOTTOMLEFT", clipFrame, "BOTTOMLEFT", 0, -16)
    hScrollBar:SetPoint("RIGHT", clipFrame, "RIGHT", -22, 0)
    hScrollBar:SetOrientation("HORIZONTAL")
    hScrollBar:SetMinMaxValues(0, 1)
    hScrollBar:SetValue(0)
    hScrollBar:SetValueStep(1)
    hScrollBar:SetObeyStepOnDrag(true)

    local hThumb = hScrollBar:CreateTexture(nil, "OVERLAY")
    hThumb:SetSize(50, 12)
    hThumb:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    hScrollBar:SetThumbTexture(hThumb)

    local hScrollBg = hScrollBar:CreateTexture(nil, "BACKGROUND")
    hScrollBg:SetAllPoints()
    hScrollBg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

    hScrollBar:SetScript("OnValueChanged", function(self, value)
        if scrollFrame then
            scrollFrame:SetHorizontalScroll(value)
        end
        if headerInner then
            headerInner:ClearAllPoints()
            headerInner:SetPoint("TOPLEFT", clipFrame, "TOPLEFT", -value, 0)
        end
    end)

    hScrollBar:EnableMouseWheel(true)
    hScrollBar:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetValue()
        self:SetValue(current - delta * 40)
    end)

    hScrollBar:Hide()

    -- Track manual scrolling to disable auto-scroll
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = current - (delta * ROW_HEIGHT * 3)
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        self:SetVerticalScroll(newScroll)

        -- If user scrolled up, disable auto-scroll; if at bottom, re-enable
        if newScroll >= maxScroll - 2 then
            autoScroll = true
        else
            autoScroll = false
        end
    end)

    -- On resize, refresh display (which handles horizontal scroll)
    frame:HookScript("OnSizeChanged", function(self, width, height)
        if not frame.isSizing then
            RefreshDisplay()
        end
    end)

    -- Initialize first tab
    SwitchTab(1)
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

---Shows the log window, creating it if necessary
function CdrLogger.LogWindow:Show()
    CreateMainFrame()
    frame:Show()
    RefreshDisplay()
end

---Hides the log window
function CdrLogger.LogWindow:Hide()
    if frame then
        frame:Hide()
    end
end

---Returns true if the window is currently visible
---@return boolean
function CdrLogger.LogWindow:IsShown()
    return frame ~= nil and frame:IsShown()
end

---Adds a log entry and refreshes the display if the relevant tab is active.
---@param tabKey string # "spells", "items", or "buffs"
---@param entry table # A flat table with keys matching column definitions
function CdrLogger.LogWindow:AddLogEntry(tabKey, entry)
    if CdrLogger.Data.log[tabKey] == nil then
        CdrLogger.Data.log[tabKey] = {}
    end

    -- Generate timestamp string using the addon's existing settings
    local ts
    if CdrLogger.Data.settings.core.time.showTimestamps then
        if CdrLogger.Data.settings.core.time.usePreciseTimestamps then
            ts = CdrLogger.Functions:RoundTo(GetTime(), CdrLogger.Data.settings.core.time.precision, "floor")
        else
            local _, _, _, time, _ = strsplit(" ", date(), 5)
            ts = time
        end
    else
        ts = ""
    end
    entry.timestamp = ts

    -- Store the raw icon texture ID for rendering
    if entry.icon then
        entry.iconId = StripTextureString(entry.icon)
        entry.icon = nil -- don't need the formatted string in the table
    else
        entry.iconId = ""
    end

    table.insert(CdrLogger.Data.log[tabKey], entry)

    -- Refresh if the window is showing and the active tab matches
    if tabKey == GetActiveKey() then
        RefreshDisplay()
    end
end
