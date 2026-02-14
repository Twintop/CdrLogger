local _, CdrLogger = ...
CdrLogger.Functions.SpellCast = CdrLogger.Functions.SpellCast or {}

----------------------------------------------------------------------
-- Spellcast event frame
----------------------------------------------------------------------
local spellCastFrame = CreateFrame("Frame")

local CAST_EVENTS = {
    "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_STOP",
}

local EVENT_LABELS = {
    UNIT_SPELLCAST_SUCCEEDED     = "CAST",
    UNIT_SPELLCAST_CHANNEL_START = "CHANNEL START",
    UNIT_SPELLCAST_CHANNEL_STOP  = "CHANNEL STOP",
    UNIT_SPELLCAST_EMPOWER_START = "EMPOWER START",
    UNIT_SPELLCAST_EMPOWER_STOP  = "EMPOWER STOP",
}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function HasTrackedEntries(tabKey)
    local tracked = CdrLogger.Data.tracked[tabKey]
    if tracked == nil then return false end
    return next(tracked) ~= nil
end

local function GetSpellEntry(event, spellId)
    local label = EVENT_LABELS[event] or event
    local spellInfo = C_Spell.GetSpellInfo(spellId)

    local name = ""
    local iconID = nil

    if spellInfo then
        -- Guard against secret values returned during combat
        name = CdrLogger.Functions:SecureValue(spellInfo.name, "")
        iconID = CdrLogger.Functions:SecureValue(spellInfo.iconID, nil)
    end

    -- If the API returned nothing useful, try to get info from tracked entries
    if (name == "" or iconID == nil) then
        local tracked = CdrLogger.Data.tracked
        for _, tabKey in ipairs({"spells", "items", "buffs"}) do
            local obj = tracked[tabKey] and tracked[tabKey][spellId]
            if obj then
                if name == "" and obj.name and obj.name ~= "" then
                    name = obj.name
                end
                if iconID == nil and obj.icon and obj.icon ~= "" then
                    -- obj.icon is formatted as "|T<id>:0|t"; extract the id
                    local rawId = obj.icon:match("|T(.-):0|t")
                    if rawId then iconID = rawId end
                end
                break
            end
        end
    end

    -- If we still have no name, skip this entry
    if name == "" then return nil end

    local icon = iconID and string.format("|T%s:0|t", iconID) or nil
    return {
        event     = label,
        icon      = icon,
        id        = spellId,
        name      = name,
    }
end

----------------------------------------------------------------------
-- Event handler
----------------------------------------------------------------------
local function OnSpellCastEvent(self, event, unit, castGUID, spellId)
    if unit ~= "player" then return end
    if spellId == nil then return end

    local entry = GetSpellEntry(event, spellId)
    if entry == nil then return end

    -- Log to each tab that has tracked entries
    if HasTrackedEntries("spells") then
        local spellEntry = {}
        for k, v in pairs(entry) do spellEntry[k] = v end
        spellEntry.charges    = ""
        spellEntry.prevRemain = ""
        spellEntry.newRemain  = ""
        spellEntry.delta      = ""
        spellEntry.pctReduce  = ""
        CdrLogger.LogWindow:AddLogEntry("spells", spellEntry)
    end

    if HasTrackedEntries("items") then
        local itemEntry = {}
        for k, v in pairs(entry) do itemEntry[k] = v end
        itemEntry.charges    = ""
        itemEntry.prevRemain = ""
        itemEntry.newRemain  = ""
        itemEntry.delta      = ""
        itemEntry.pctReduce  = ""
        CdrLogger.LogWindow:AddLogEntry("items", itemEntry)
    end

    if HasTrackedEntries("buffs") then
        local buffEntry = {}
        for k, v in pairs(entry) do buffEntry[k] = v end
        buffEntry.stacks     = ""
        buffEntry.duration   = ""
        buffEntry.remaining  = ""
        buffEntry.delta      = ""
        buffEntry.pctInitial = ""
        CdrLogger.LogWindow:AddLogEntry("buffs", buffEntry)
    end
end

spellCastFrame:SetScript("OnEvent", OnSpellCastEvent)

----------------------------------------------------------------------
-- Enable / Disable
----------------------------------------------------------------------
function CdrLogger.Functions.SpellCast:Enable()
    for _, event in ipairs(CAST_EVENTS) do
        spellCastFrame:RegisterEvent(event)
    end
end

function CdrLogger.Functions.SpellCast:Disable()
    for _, event in ipairs(CAST_EVENTS) do
        spellCastFrame:UnregisterEvent(event)
    end
end
