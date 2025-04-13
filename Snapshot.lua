---@diagnostic disable: undefined-field, undefined-global
local _, CdrLogger = ...
CdrLogger = CdrLogger or {}

---@class CdrLogger.Classes.SnapshotBuff
---@field public auraInstanceId integer?
---@field public isActive boolean
---@field public endTime number?
---@field public duration number
---@field public remaining number
---@field public applications integer
---@field private lastRefreshGetTime number
---@field public previousRemaining number
---@field public currentlySimple boolean
---@field private initialStartTime number?
---@field private initialEndTime number?
---@field private initialDuration number
---@field private initialApplications number
---@field private updateCount integer
---@field private applicationsChangeCount integer
---@field private applicationsMax integer
---@field private durationDelta number
---@field private durationChangeCount integer
CdrLogger.Classes.SnapshotBuff = {}
CdrLogger.Classes.SnapshotBuff.__index = CdrLogger.Classes.SnapshotBuff

---Creates a new Snapshot object
---@param spellId integer
---@return CdrLogger.Classes.SnapshotBuff
function CdrLogger.Classes.SnapshotBuff:New(spellId)
	local self = {}
	setmetatable(self, CdrLogger.Classes.SnapshotBuff)
    self.id = spellId

    local spellInfo = C_Spell.GetSpellInfo(self.id) --[[@as SpellInfo]]
    self.name = spellInfo.name
    self.icon = string.format("|T%s:0|t", spellInfo.iconID)
    self.infoLoaded = true

	self:Reset()
	return self
end

---Resets the object to default values
function CdrLogger.Classes.SnapshotBuff:Reset()
	if self.auraInstanceId ~= nil then
		CdrLogger.Functions.Aura:RemoveBuffAuraInstanceId(self.auraInstanceId)
	end
	self.auraInstanceId = nil
	self.isActive = false
	self.endTime = nil
	self.duration = 0
	self.remaining = 0
	self.applications = 0
	self.lastRefreshGetTime = 0
	self.previousRemaining = 0

    self.updateCount = 0
    self.applicationsChangeCount = 0
    self.applicationsMax = 0
    self.durationDelta = 0
    self.durationChangeCount = 0

    self.initialApplications = 0
    self.initialDuration = 0
    self.initialEndTime = nil
    self.initialStartTime = nil
end

---Computes the time remaining on the Snapshot
---@param currentTime number? # Timestamp to use for calculations. If not specified, the current time from `GetTime()` will be used instead.
---@return number # Duration remaining on the Snapshot
function CdrLogger.Classes.SnapshotBuff:GetRemainingTime(currentTime)
	currentTime = currentTime or GetTime()

	local remainingTime = 0
	local endTime = self.endTime

	if endTime ~= nil and endTime > currentTime then
		remainingTime = endTime - currentTime
	end

	if remainingTime <= 0 then
		self.isActive = false
		remainingTime = 0
	else
		self.isActive = true
	end

	self.remaining = remainingTime
	self.lastRefreshGetTime = currentTime
	return remainingTime
end

---Initializes the buff information for the snapshot
---@param osTimestamp string|osdate
---@param eventType CdrLoggerAuraEventType? # Event type sourced from the combat log event. If not provided, will do a generic buff update
---@param simple? boolean # Just updates isActive. If not provided, defaults to `false`
---@param unit? UnitId # Unit we want to check to update. If not provided, defaults to `player`
function CdrLogger.Classes.SnapshotBuff:Initialize(osTimestamp, eventType, simple, unit)
	unit = unit or "player"
	if simple == nil then
		simple = false
	end
	self:Refresh(osTimestamp, eventType, unit)
end


function CdrLogger.Classes.SnapshotBuff:GetOutputTimeIfAny(timeInput)
    if CdrLogger.Data.settings.core.time.showTimestamps then
        return "[" .. CdrLogger.Functions:GetOutputTime(timeInput) .. "] "
    end
    return ""
end

---Parse the buff
---@param aura AuraData # Data about the buff
---@param osTimestamp string|osdate
---@return integer? # The SpellID of the buff, if found
function CdrLogger.Classes.SnapshotBuff:ParseBuffData(aura, osTimestamp)
    local currentTime = GetTime()    
    local outputLink = self:GetOutput()
    local outputTime = currentTime
    if not CdrLogger.Data.settings.core.time.usePreciseTimestamps then
---@diagnostic disable-next-line: cast-local-type
        outputTime = osTimestamp
    end

	if aura ~= nil then
        local durationChanged = false
        local durationDelta = 0
        local applicationsChanged = false

        if aura.expirationTime <= 0 or aura.duration <= 0 then
            -- Make sure we have the most up-to-date remaining time before we set the buff to simple mode
            self:GetRemainingTime()
            self.currentlySimple = true
        else
            self.currentlySimple = false
        end

        if self.endTime ~= aura.expirationTime and self.isActive then
            durationDelta = aura.expirationTime - self.endTime
            self.durationChangeCount = self.durationChangeCount + 1
            self.durationDelta = self.durationDelta + durationDelta
            durationChanged = true
        end

        if self.applications ~= aura.applications and self.applications > 0 and self.isActive then
            self.applicationsChangeCount = self.applicationsChangeCount + 1
            
            if aura.applications > self.applications then
                self.applicationsMax = aura.applications
            end

            applicationsChanged = true
        end

        if not self.isActive then
            if aura.applications > 0 then
                print("|c" .. CdrLogger.Data.settings.core.colors.cdChange .. self:GetOutputTimeIfAny(outputTime) .. "BUFF GAINED: |r" .. outputLink .. " (" .. aura.applications .. ") -- " .. CdrLogger.Functions:RoundTo(aura.duration, 3, floor))
            else
                print("|c" .. CdrLogger.Data.settings.core.colors.cdChange .. self:GetOutputTimeIfAny(outputTime) .. "BUFF GAINED: |r" .. outputLink .. " -- " .. CdrLogger.Functions:RoundTo(aura.duration, 3, floor))
            end
        elseif applicationsChanged and durationChanged then
            self:GetRemainingTime()
            print("|c" .. CdrLogger.Data.settings.core.colors.cdChange .. self:GetOutputTimeIfAny(outputTime) .. "BUFF CHANGE: |r" .. outputLink .. " (" .. self.applications .. " -> " .. aura.applications .. ") -- " .. CdrLogger.Functions:RoundTo(self.remaining, 3, floor) .. " + " .. CdrLogger.Functions:RoundTo(durationDelta, 3, floor) .. " = " .. CdrLogger.Functions:RoundTo(durationDelta + self.remaining, 3, floor))
        elseif durationChanged then
            self:GetRemainingTime()
            print("|c" .. CdrLogger.Data.settings.core.colors.cdChange .. self:GetOutputTimeIfAny(outputTime) .. "BUFF CHANGE: |r" .. outputLink .. " -- " .. CdrLogger.Functions:RoundTo(self.remaining, 3, floor) .. " + " .. CdrLogger.Functions:RoundTo(durationDelta, 3, floor) .. " = " .. CdrLogger.Functions:RoundTo(durationDelta + self.remaining, 3, floor))
        elseif applicationsChanged then
            print("|c" .. CdrLogger.Data.settings.core.colors.cdChange .. self:GetOutputTimeIfAny(outputTime) .. "BUFF CHANGE: |r" .. outputLink .. " (" .. self.applications .. " -> " .. aura.applications .. ")")
        end

        self.previousRemaining = self.remaining
        self.auraInstanceId = aura.auraInstanceID
		self.applications = aura.applications
		self.duration = aura.duration
		self.endTime = aura.expirationTime

		CdrLogger.Functions.Aura:StoreBuffAuraInstanceId(self)
		return aura.spellId
	else
        if self.applications > 0 then
            print("|c" .. CdrLogger.Data.settings.core.colors.cdEnd .. self:GetOutputTimeIfAny(outputTime) .. "BUFF LOST: |r" .. outputLink .. " (" .. self.applications .. ") -- Remaining = " .. CdrLogger.Functions:RoundTo(self.endTime - currentTime, 3, floor) .. " | Total = " .. CdrLogger.Functions:RoundTo(currentTime - self.initialStartTime, 3, floor) .. " (" .. CdrLogger.Functions:RoundTo(100 * (((currentTime - self.initialStartTime)/self.initialDuration)-1), 3, floor) .. "% of " .. self.initialDuration .. ") | Delta = " .. CdrLogger.Functions:RoundTo(self.durationDelta, 3, floor))
        else
            print("|c" .. CdrLogger.Data.settings.core.colors.cdEnd .. self:GetOutputTimeIfAny(outputTime) .. "BUFF LOST: |r" .. outputLink .. " -- Remaining = " .. CdrLogger.Functions:RoundTo(self.endTime - currentTime, 3, floor) .. " | Total = " .. CdrLogger.Functions:RoundTo(currentTime - self.initialStartTime, 3, floor) .. " (" .. CdrLogger.Functions:RoundTo(100 * (((currentTime - self.initialStartTime)/self.initialDuration)-1), 3, floor) .. "% of " .. self.initialDuration .. ") | Delta = " .. CdrLogger.Functions:RoundTo(self.durationDelta, 3, floor))
        end
		self:Reset()
	end
end

---Refreshes the buff snapshot with already captured AuraData
---@param auraData AuraData
---@param osTimestamp string|osdate
---@param isInitial boolean
function CdrLogger.Classes.SnapshotBuff:RefreshWithAuraData(auraData, osTimestamp, isInitial)
	if self.isCustom then
		return
	end

	self:ParseBuffData(auraData, osTimestamp)

    if isInitial then
        self.initialStartTime = self.endTime - self.duration
        self.initialEndTime = self.endTime
        self.initialDuration = self.duration
        self.initialApplications = self.applications
    end

	if self.currentlySimple then
		self.isActive = true
	else
		local currentTime = GetTime()
		if self.endTime ~= nil and self.endTime > currentTime then
			self.isActive = true
			self:GetRemainingTime()
		else
			self:Reset()
		end
	end
end

---Refreshes the buff information for the snapshot
---@param osTimestamp string|osdate
---@param eventType CdrLoggerAuraEventType? # Event type sourced from the combat log event. If not provided, will do a generic buff update
---@param unit UnitId? # Unit we want to check to update. If not provided, defaults to `player`
function CdrLogger.Classes.SnapshotBuff:Refresh(osTimestamp, eventType, unit)
	unit = unit or "player"

    if eventType == "SPELL_AURA_APPLIED" or eventType == "SPELL_AURA_REFRESH" or eventType == "SPELL_AURA_APPLIED_DOSE" then -- Gained buff
        self.isActive = true
        if unit == "player" then
            self:ParseBuffData(C_UnitAuras.GetPlayerAuraBySpellID(self.id), osTimestamp)
        else
            self:ParseBuffData(CdrLogger.Functions.Aura:FindBuffById(self.id, unit), osTimestamp)
        end
        if not self.currentlySimple then
            self:GetRemainingTime()
        end
    elseif eventType == "SPELL_AURA_REMOVED_DOSE" then -- Lost stack
        if self.applications ~= nil then
            self.applications = self.applications - 1
        end
    elseif eventType == "SPELL_AURA_REMOVED" or eventType == "SPELL_DISPEL" then -- Lost buff
        self:Reset()
    elseif eventType == nil or eventType == "" then
        local currentTime = currentTime or GetTime()
        local foundId = nil
        
        if unit == "player" then
            foundId = self:ParseBuffData(C_UnitAuras.GetPlayerAuraBySpellID(self.id), osTimestamp)
        else
            foundId = self:ParseBuffData(CdrLogger.Functions.Aura:FindBuffById(self.id, unit), osTimestamp)
        end

        if self.currentlySimple then
            self.isActive = foundId == self.id
        else
            if self.endTime ~= nil and self.endTime > currentTime then
                self.isActive = true
                self:GetRemainingTime()
            else
                self:Reset()
            end
        end
    end
end

function CdrLogger.Classes.SnapshotBuff:GetOutput(includeId)
    local id = ""
    if includeId then
        id = " (" .. self.id .. ")"
    end
    return "|Hspell:" .. self.id .. "|h[" .. self.icon .. " " .. self.name .. "]|h" .. id
end


---@alias CdrLoggerBuffSimpleMode
---| '"always"' # Always run in simple mode
---| '"sometimes"' # Run in simple mode sometimes
---| '"never"' # Never run in simple mode